extends Node
## Локальная таблица лидеров (§10 PROMPT.md): записи, реплеи и фоновая проверка ресимуляцией.

const PATH_DEFAULT: String = "user://leaderboard.json"
const REPLAY_DIR_DEFAULT: String = "user://replays"
const PROFILE_PATH: String = "user://profiles/default.json"
## Автопрогоны бота и скриншоты пишут в отдельную «песочницу», не засоряя таблицу игрока.
const DEV_DIR: String = "user://dev"
const SCHEMA_VERSION: int = 1
const CATEGORIES: Array[String] = ["classic", "speed", "damage", "daily", "race"]

var records_path: String = PATH_DEFAULT
var replays_dir: String = REPLAY_DIR_DEFAULT
var records: Array[Dictionary] = []
var profile: Dictionary = {}
var _tasks: Dictionary = {}
var _results: Array[Dictionary] = []
var _mutex: Mutex = Mutex.new()


func _ready() -> void:
	var cli: Dictionary = Game.parse_cli(OS.get_cmdline_user_args())
	if cli.has("autoplay") or cli.has("screenshot") or cli.has("bot"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEV_DIR))
		records_path = DEV_DIR.path_join("leaderboard_%d.json" % OS.get_process_id() if cli.has("bot") else "leaderboard.json")
		replays_dir = DEV_DIR.path_join("replays")
	_load_profile()
	_load_records()
	for r: Dictionary in records:
		if String(r.get("verify_state", "")) == "pending":
			_verify_async(r)


## Выход из игры: дождаться фоновых проверок реплеев — поток не должен пережить объект.
func _exit_tree() -> void:
	for task_id: int in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(task_id)
	_tasks.clear()


func _process(_delta: float) -> void:
	if _tasks.is_empty():
		return
	for task_id: int in _tasks.keys():
		if WorkerThreadPool.is_task_completed(task_id):
			WorkerThreadPool.wait_for_task_completion(task_id)
			_tasks.erase(task_id)
	_mutex.lock()
	var done: Array[Dictionary] = _results.duplicate()
	_results.clear()
	_mutex.unlock()
	for res: Dictionary in done:
		var rec: Dictionary = find(String(res["id"]))
		if rec.is_empty():
			continue
		rec["verified"] = bool(res["ok"])
		rec["verify_state"] = "ok" if res["ok"] else "failed"
		rec["verify_reason"] = String(res["reason"])
		_save_records()
		Events.leaderboard_updated.emit(String(rec["id"]))


# --- Профиль ---------------------------------------------------------------

func _load_profile() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROFILE_PATH.get_base_dir()))
	if FileAccess.file_exists(PROFILE_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
		if parsed is Dictionary:
			profile = parsed
	if not profile.has("uuid"):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.randomize()
		profile = {"uuid": "%08x%08x" % [rng.randi(), rng.randi()], "color": "#7cc4ff"}
		_write_json(PROFILE_PATH, profile)


# --- Записи ----------------------------------------------------------------

func _load_records() -> void:
	records.clear()
	var path: String = records_path
	if not FileAccess.file_exists(path) and FileAccess.file_exists(records_path + ".bak"):
		path = records_path + ".bak"
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and parsed.has("records"):
		for r: Variant in parsed["records"]:
			if r is Dictionary:
				records.append(r)
	else:
		push_warning("Лидерборд повреждён, пробую резервную копию")
		if path != records_path + ".bak" and FileAccess.file_exists(records_path + ".bak"):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(records_path), ProjectSettings.globalize_path(records_path + ".corrupt"))
			_load_records()


func _save_records() -> void:
	if FileAccess.file_exists(records_path):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(records_path), ProjectSettings.globalize_path(records_path + ".bak"))
	_write_json(records_path, {"schema": SCHEMA_VERSION, "records": records})


## Атомарная запись: во временный файл, затем переименование.
func _write_json(path: String, value: Variant) -> void:
	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Не удалось записать %s: %s" % [tmp, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(value, "\t"))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))


## Сохраняет результат завершённого забега. Возвращает {record, rank, best, previous_best}.
func submit(sim: GameSim, meta: Dictionary) -> Dictionary:
	var rec: Dictionary = _build_record(sim, meta)
	var prev: Dictionary = personal_best("classic", String(rec["difficulty"]))
	records.append(rec)
	_save_records()
	_verify_async(rec)
	Events.leaderboard_updated.emit(String(rec["id"]))
	var rank: int = rank_of(String(rec["id"]), "classic", String(rec["difficulty"]))
	var is_best: bool = prev.is_empty() or int(rec["score"]) > int(prev.get("score", 0))
	return {"record": rec, "rank": rank, "best": is_best, "previous_best": prev}


## Результат матча «Гонка»: место, число игроков, соперники + реплей своего поля.
func submit_race(sim: GameSim, meta: Dictionary) -> Dictionary:
	var rec: Dictionary = _build_record(sim, meta)
	rec["mode"] = "race"
	rec["place"] = int(meta.get("place", 0))
	rec["players"] = int(meta.get("players", 0))
	rec["opponents"] = Array(meta.get("opponents", PackedStringArray()))
	rec["match_seed"] = int(meta.get("match_seed", 0))
	records.append(rec)
	_save_records()
	_verify_async(rec)
	Events.leaderboard_updated.emit(String(rec["id"]))
	return {"record": rec}


## Испытание урона пройдено: запись забега обновляется (реплей теперь включает испытание) и проверяется заново.
## Возвращает {record, rank, best}.
func submit_damage_test(id: String, sim: GameSim) -> Dictionary:
	var rec: Dictionary = find(id)
	if rec.is_empty() or not sim.damage_test_done:
		return {}
	var prev: Dictionary = personal_best("damage", String(rec["difficulty"]))
	_write_json(String(rec["replay"]), Replay.from_sim(sim, Game.version()))
	var base: Dictionary = {}
	for key: String in RecordIO.TRUSTED_FIELDS:
		if rec.has(key):
			base[key] = rec[key]
	base["replay"] = rec["replay"]
	var fresh: Dictionary = RecordIO.record_from_summary(sim.data, sim.summary(), base)
	rec.merge(fresh, true)
	_save_records()
	_verify_async(rec)
	Events.leaderboard_updated.emit(id)
	var is_best: bool = prev.is_empty() or int(rec["damage_dps"]) > int(prev.get("damage_dps", 0))
	return {"record": rec, "rank": rank_of(id, "damage", String(rec["difficulty"])), "best": is_best}


func _build_record(sim: GameSim, meta: Dictionary) -> Dictionary:
	var summary: Dictionary = sim.summary()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var id: String = "%d-%06x" % [int(Time.get_unix_time_from_system()), rng.randi() & 0xFFFFFF]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(replays_dir))
	var replay_path: String = replays_dir.path_join(id + ".gtdr")
	_write_json(replay_path, Replay.from_sim(sim, Game.version()))
	return RecordIO.record_from_summary(sim.data, summary, {
		"id": id,
		"name": String(meta.get("name", Settings.player_name())),
		"profile": String(profile.get("uuid", "")),
		"date": Time.get_datetime_string_from_system(false, true),
		"daily": String(meta.get("daily", "")),
		"real_seconds": snappedf(float(meta.get("real_seconds", 0.0)), 0.1),
		"version": Game.version(),
		"replay": replay_path,
	})


func rename(id: String, new_name: String) -> void:
	var rec: Dictionary = find(id)
	if rec.is_empty() or new_name.strip_edges().is_empty():
		return
	rec["name"] = new_name.strip_edges().left(24)
	_save_records()


func find(id: String) -> Dictionary:
	for r: Dictionary in records:
		if String(r["id"]) == id:
			return r
	return {}


## Отсортированная таблица категории. difficulty "" — все сложности; daily_date — фильтр «Seed дня».
func ranking(category: String, difficulty: String = "", daily_date: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in records:
		if not difficulty.is_empty() and String(r["difficulty"]) != difficulty:
			continue
		var is_race: bool = String(r.get("mode", "solo")) == "race"
		if is_race != (category == "race"):
			continue
		match category:
			"speed":
				if String(r["outcome"]) != "victory":
					continue
			"damage":
				if int(r.get("damage_dps", 0)) <= 0:
					continue
			"daily":
				if String(r.get("daily", "")).is_empty():
					continue
				if not daily_date.is_empty() and String(r["daily"]) != daily_date:
					continue
		out.append(r)
	if category == "daily":
		out = _best_per_day(out)
	if category == "speed":
		# Сначала длинный забег, затем время боя: победа на 20 волнах всегда быстрее, чем на 62, и иначе
		# короткие забеги заняли бы всю таблицу.
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a.get("total_waves", 0)) != int(b.get("total_waves", 0)):
				return int(a.get("total_waves", 0)) > int(b.get("total_waves", 0))
			return float(a["combat_seconds"]) < float(b["combat_seconds"]))
	elif category == "damage":
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["damage_dps"]) != int(b["damage_dps"]):
				return int(a["damage_dps"]) > int(b["damage_dps"])
			return String(a["date"]) < String(b["date"]))
	elif category == "race":
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a.get("place", 99)) != int(b.get("place", 99)):
				return int(a.get("place", 99)) < int(b.get("place", 99))
			return String(a["date"]) > String(b["date"]))
	else:
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["score"]) != int(b["score"]):
				return int(a["score"]) > int(b["score"])
			return String(a["date"]) < String(b["date"]))
	return out


## «Seed дня»: в таблицу идёт только лучшая попытка профиля за каждый день.
func _best_per_day(list: Array[Dictionary]) -> Array[Dictionary]:
	var best: Dictionary = {}
	for r: Dictionary in list:
		var key: String = "%s|%s|%s" % [String(r.get("profile", "")), String(r["daily"]), String(r["difficulty"])]
		var cur: Dictionary = best.get(key, {})
		if cur.is_empty() or int(r["score"]) > int(cur["score"]):
			best[key] = r
	var out: Array[Dictionary] = []
	for r2: Dictionary in list:
		var key2: String = "%s|%s|%s" % [String(r2.get("profile", "")), String(r2["daily"]), String(r2["difficulty"])]
		if best[key2] == r2:
			out.append(r2)
	return out


## Сводка «Гонки» профиля: матчей, побед, среднее место.
func race_summary() -> Dictionary:
	var uuid: String = String(profile.get("uuid", ""))
	var matches: int = 0
	var wins: int = 0
	var places: int = 0
	for r: Dictionary in records:
		if String(r.get("mode", "")) != "race" or String(r.get("profile", "")) != uuid:
			continue
		matches += 1
		places += int(r.get("place", 0))
		if int(r.get("place", 0)) == 1:
			wins += 1
	return {"matches": matches, "wins": wins, "avg_place": float(places) / float(matches) if matches > 0 else 0.0}


## Экспорт записи с реплеем в файл .gtdx (для обмена с друзьями).
func export_record(id: String, path: String) -> Error:
	var rec: Dictionary = find(id)
	var replay: Dictionary = load_replay(rec)
	if rec.is_empty() or replay.is_empty():
		return ERR_FILE_NOT_FOUND
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(RecordIO.export_bundle(rec, replay), "\t"))
	return OK


## Импорт .gtdx: принимается только после успешной пересимуляции; поля записи берутся из неё.
func import_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "ERR_IMPORT_READ"}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {"ok": false, "reason": "ERR_IMPORT_FORMAT"}
	var res: Dictionary = RecordIO.import_bundle(GameData.load_default(), parsed)
	if not res["ok"]:
		return res
	var rec: Dictionary = res["record"]
	if not find(String(rec["id"])).is_empty():
		return {"ok": false, "reason": "ERR_IMPORT_DUPLICATE"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(replays_dir))
	var replay_path: String = replays_dir.path_join(String(rec["id"]) + ".gtdr")
	_write_json(replay_path, res["replay"])
	rec["replay"] = replay_path
	records.append(rec)
	_save_records()
	Events.leaderboard_updated.emit(String(rec["id"]))
	return {"ok": true, "reason": "", "record": rec}


func rank_of(id: String, category: String, difficulty: String = "") -> int:
	var list: Array[Dictionary] = ranking(category, difficulty)
	for i: int in list.size():
		if String(list[i]["id"]) == id:
			return i + 1
	return -1


func personal_best(category: String, difficulty: String) -> Dictionary:
	var uuid: String = String(profile.get("uuid", ""))
	for r: Dictionary in ranking(category, difficulty):
		if String(r.get("profile", "")) == uuid:
			return r
	return {}


func load_replay(rec: Dictionary) -> Dictionary:
	var path: String = String(rec.get("replay", ""))
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


# --- Проверка --------------------------------------------------------------

func _verify_async(rec: Dictionary) -> void:
	var replay: Dictionary = load_replay(rec)
	if replay.is_empty():
		rec["verify_state"] = "failed"
		rec["verify_reason"] = "ERR_REPLAY_MISSING"
		return
	var id: String = String(rec["id"])
	var task_id: int = WorkerThreadPool.add_task(_verify_task.bind(id, replay), true, "verify " + id)
	_tasks[task_id] = id


func _verify_task(id: String, replay: Dictionary) -> void:
	var res: Dictionary = Replay.simulate(GameData.load_default(), replay)
	_mutex.lock()
	_results.append({"id": id, "ok": bool(res["ok"]), "reason": String(res["reason"])})
	_mutex.unlock()
