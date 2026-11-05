extends Node
## Сохранения забега (§12 PROMPT.md). Сейв = заголовок реплея (seed, настройки, лог команд) + метаданные.
## Загрузка — точная пересимуляция лога до сохранённого тика с проверкой контрольной суммы.

const FORMAT: String = "gtds"
const FORMAT_VERSION: int = 1
const DIR_DEFAULT: String = "user://saves"
const AUTOSAVE: String = "autosave"
const SLOTS: Array[String] = ["slot1", "slot2", "slot3"]

var save_dir: String = DIR_DEFAULT


func _ready() -> void:
	var cli: Dictionary = Game.parse_cli(OS.get_cmdline_user_args())
	if cli.has("autoplay") or cli.has("screenshot") or cli.has("bot"):
		save_dir = "user://dev/saves"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir))


func path_for(slot: String) -> String:
	return save_dir.path_join(slot + ".json")


func can_save(sim: GameSim) -> bool:
	return sim != null and sim.is_build_phase() and not sim.is_over()


func build(sim: GameSim, meta: Dictionary) -> Dictionary:
	var rep: Dictionary = Replay.from_sim(sim, Game.version())
	rep["format"] = FORMAT
	rep["format_version"] = FORMAT_VERSION
	rep["saved_tick"] = sim.tick
	rep["saved_checksum"] = sim.checksum()
	rep["meta"] = {
		"date": Time.get_datetime_string_from_system(false, true),
		"round": sim.round_index,
		"wave_total": sim.total_waves,
		"lives": sim.lives,
		"gold": sim.gold,
		"towers": sim.towers.size(),
		"daily": String(meta.get("daily", "")),
		"real_seconds": float(meta.get("real_seconds", 0.0)),
	}
	return rep


func save_run(sim: GameSim, slot: String, meta: Dictionary) -> bool:
	if not can_save(sim):
		return false
	var data: Dictionary = build(sim, meta)
	var path: String = path_for(slot)
	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Не удалось записать сейв: " + error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	return true


func exists(slot: String) -> bool:
	return FileAccess.file_exists(path_for(slot))


func read(slot: String) -> Dictionary:
	if not exists(slot):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path_for(slot)))
	if parsed is Dictionary and String(parsed.get("format", "")) == FORMAT:
		return parsed
	return {}


func delete(slot: String) -> void:
	if exists(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_for(slot)))


## Совместим ли сейв с текущими данными баланса (иначе ресимуляция даст другой результат).
func compatible(save: Dictionary) -> bool:
	return not save.is_empty() and int(save.get("data_hash", -1)) == GameData.load_default().data_hash


## Восстанавливает симуляцию. {ok, reason, sim}
func restore(save: Dictionary) -> Dictionary:
	if save.is_empty():
		return {"ok": false, "reason": "ERR_SAVE_MISSING", "sim": null}
	if not compatible(save):
		return {"ok": false, "reason": "ERR_SAVE_INCOMPATIBLE", "sim": null}
	if not (save.get("saved_tick") is float or save.get("saved_tick") is int) or not (save.get("saved_checksum") is float or save.get("saved_checksum") is int):
		return {"ok": false, "reason": "ERR_SAVE_CORRUPT", "sim": null}
	var res: Dictionary = Replay.resimulate(GameData.load_default(), save, int(save["saved_tick"]))
	if not res["ok"]:
		return {"ok": false, "reason": String(res["reason"]), "sim": null}
	var sim: GameSim = res["sim"]
	if sim.checksum() != int(save["saved_checksum"]):
		return {"ok": false, "reason": "ERR_SAVE_CHECKSUM", "sim": null}
	sim.record_events = true
	return {"ok": true, "reason": "", "sim": sim}
