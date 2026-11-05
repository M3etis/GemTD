extends SceneTree
## Балансные прогоны (§14 PROMPT.md): стратегии бота × seed'ы × сложности.
## Параллельно — отдельными процессами Godot (в потоках одного процесса симуляции упираются в общие блокировки движка).
## Запуск:
##   godot --headless --path . -s res://tools/balance_sim.gd -- --seeds=50 --difficulty=normal,hard
## Параметры: --seeds=N (50), --difficulty=список (normal), --strategies=список (6 стратегий),
##   --waves=N (все), --workers=N (процессов, по числу ядер), --out=папка (res://docs/balance), --no-test (без Испытания урона),
##   --tag=имя (суффикс файлов), --trace=стратегия:seed (один прогон с отчётом по каждой волне),
##   --polish (бот тратит лишнее золото на огранку — мера её влияния на баланс),
##   --finale-mult=X, --finale-elite=0|1, --finale-leak=N (подбор финала длины --waves без правки waves.json).
## Пишет CSV по каждой сложности и сводку в markdown (docs/balance/summary_<tag>.md).

const SEED_BASE: int = 1000
const PARTS_ROOT: String = "user://balance_parts"

var _results: Array[Dictionary] = []
## Папка частичных результатов воркеров — своя у каждого тега: параллельные прогоны не перезаписывают друг друга.
var _parts_dir: String = PARTS_ROOT
var _jobs: Array[Dictionary] = []
var _data: GameData


func _initialize() -> void:
	var args: Dictionary = _parse(OS.get_cmdline_user_args())
	_data = GameData.load_default()
	if not _data.is_valid():
		printerr("balance_sim: данные не прошли проверку")
		quit(2)
		return
	if args.has("trace"):
		_trace(String(args["trace"]), String(args.get("difficulty", "normal")))
		return
	var seeds: int = int(args.get("seeds", "50"))
	var difficulties: PackedStringArray = String(args.get("difficulty", "normal")).split(",", false)
	var strategies: PackedStringArray = String(args.get("strategies", ",".join(BotPlayer.BALANCE_STRATEGIES))).split(",", false)
	var waves: int = int(args.get("waves", str(_data.wave_count())))
	var with_test: bool = not args.has("no-test")
	var polish: bool = args.has("polish")
	var out_dir: String = String(args.get("out", "res://docs/balance"))
	var tag: String = String(args.get("tag", "latest"))
	_parts_dir = PARTS_ROOT.path_join(tag)
	_override_finale(args, waves)
	for diff: String in difficulties:
		for strat: String in strategies:
			for i: int in seeds:
				_jobs.append({"difficulty": diff, "strategy": strat, "seed": SEED_BASE + i, "waves": waves, "test": with_test, "polish": polish})
	if args.has("worker"):
		_run_worker(int(args["worker"]), int(args["workers"]))
		return
	var workers: int = clampi(int(args.get("workers", str(OS.get_processor_count()))), 1, _jobs.size())
	print("balance_sim: %d прогонов (%s × %s × %d seed), волн %d, процессов %d" % [_jobs.size(), ",".join(difficulties),
		",".join(strategies), seeds, waves, workers])
	var t0: int = Time.get_ticks_msec()
	if not _run_workers(workers):
		quit(3)
		return
	var total_ms: int = Time.get_ticks_msec() - t0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	for diff2: String in difficulties:
		_write_csv(out_dir.path_join("balance_%s_%s.csv" % [diff2, tag]), diff2)
	var md: String = _summary_md(difficulties, strategies, seeds, waves, total_ms)
	var f: FileAccess = FileAccess.open(out_dir.path_join("summary_%s.md" % tag), FileAccess.WRITE)
	f.store_string(md)
	f.close()
	print(md)
	quit(0)


## Подбор финала: параметры длины забега waves меняются в памяти (во всех процессах — те же аргументы).
func _override_finale(args: Dictionary, waves: int) -> void:
	var cfg: Dictionary = _data.run_length_cfg(waves)
	if cfg.is_empty():
		return
	if args.has("finale-mult"):
		cfg["finale_hp_mult"] = float(String(args["finale-mult"]))
	if args.has("finale-elite"):
		cfg["finale_elite"] = String(args["finale-elite"]) == "1"
	if args.has("finale-leak"):
		cfg["finale_leak"] = int(String(args["finale-leak"]))
	if not args.has("worker"):
		print("balance_sim: финал %d волн — %s" % [waves, str(cfg)])


## Запускает рабочие процессы и собирает их результаты.
func _run_workers(workers: int) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_parts_dir))
	var base_args: PackedStringArray = PackedStringArray()
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--workers="):
			base_args.append(a)
	var pids: Array[int] = []
	for i: int in workers:
		var part: String = _parts_dir.path_join("part_%d.json" % i)
		if FileAccess.file_exists(part):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(part))
		var argv: PackedStringArray = PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"-s", "res://tools/balance_sim.gd", "--"])
		argv.append_array(base_args)
		argv.append_array(PackedStringArray(["--worker=%d" % i, "--workers=%d" % workers]))
		pids.append(OS.create_process(OS.get_executable_path(), argv))
	var running: bool = true
	while running:
		OS.delay_msec(250)
		running = false
		for pid: int in pids:
			if pid > 0 and OS.is_process_running(pid):
				running = true
	_results.clear()
	for i2: int in workers:
		var part2: String = _parts_dir.path_join("part_%d.json" % i2)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(part2)) if FileAccess.file_exists(part2) else null
		if not parsed is Array:
			printerr("balance_sim: нет результатов процесса %d" % i2)
			return false
		for r: Variant in parsed:
			_results.append(r as Dictionary)
	return true


func _run_worker(index: int, workers: int) -> void:
	var rows: Array[Dictionary] = []
	for i: int in _jobs.size():
		if i % workers == index:
			rows.append(_run_job(_jobs[i]))
	var f: FileAccess = FileAccess.open(_parts_dir.path_join("part_%d.json" % index), FileAccess.WRITE)
	f.store_string(JSON.stringify(rows))
	f.close()
	quit(0)


func _run_job(job: Dictionary) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	var sim: GameSim = GameSim.new(_data, {"seed": int(job["seed"]), "difficulty": String(job["difficulty"]),
		"max_waves": int(job["waves"]), "record_events": false})
	sim.start()
	var bot: BotPlayer = BotPlayer.new(sim, String(job["strategy"]), sim.seed_value)
	bot.use_polish = bool(job.get("polish", false))
	var s: Dictionary = bot.run_to_end()
	if bool(job["test"]) and sim.phase == GameSim.Phase.VICTORY and sim.apply({"type": "start_damage_test"})["ok"]:
		while sim.phase == GameSim.Phase.COMBAT:
			sim.step()
		s = sim.summary()
	var row: Dictionary = {
		"difficulty": job["difficulty"], "strategy": job["strategy"], "seed": job["seed"],
		"outcome": s["outcome"], "waves_cleared": int(s["waves_cleared"]), "lives": int(s["lives"]),
		"kills": int(s["kills"]), "leaks": int(s["leaks"]), "gold_earned": int(s["gold_earned"]), "luck": int(s["luck"]),
		"towers": int(s["towers"]), "specials": (s["specials"] as Dictionary).size(),
		"special_ids": "|".join(PackedStringArray((s["specials"] as Dictionary).keys())),
		"total_damage": int(s["total_damage"]), "damage_by_type": s["damage_by_type"], "leaks_by_wave": s["leaks_by_wave"],
		"damage_test_dps": int(s["damage_test_dps"]), "combat_seconds": snappedf(float(s["combat_seconds"]), 0.1),
		"score": Scoring.compute(_data, s), "ms": Time.get_ticks_msec() - t0,
	}
	return row


## Один прогон с построчным отчётом: жизни, утечки, золото, удача, башни и обнаружение перед каждой волной.
func _trace(spec: String, diff: String) -> void:
	var parts: PackedStringArray = spec.split(":")
	var sim: GameSim = GameSim.new(_data, {"seed": int(parts[1]) if parts.size() > 1 else SEED_BASE, "difficulty": diff, "record_events": false})
	sim.start()
	var bot: BotPlayer = BotPlayer.new(sim, parts[0], sim.seed_value)
	while not sim.is_over():
		bot.play_build_phase()
		if sim.phase != GameSim.Phase.COMBAT:
			break
		var lives: int = sim.lives
		var towers: PackedStringArray = PackedStringArray()
		for t: TowerState in sim.towers:
			towers.append("%s%d" % [t.special_id, t.level] if t.is_special() else "%s%d" % [t.gem_id.left(3), t.quality])
		var w: int = sim.wave_number
		var hp: int = roundi(_data.enemy_base_hp(w) * _data.difficulty_hp_mult(sim.diff, w))
		var boss_wave: bool = _data.is_boss_wave(w)
		while sim.phase == GameSim.Phase.COMBAT:
			sim.step()
			if boss_wave and sim.tick % 150 == 0:
				for e: EnemyState in sim.enemies:
					if e.boss:
						var total: float = sim.route.air_length if e.flying else sim.route.ground_length
						print("    t=%3d босс %s HP %d%% щит %d путь %d%% фаза %d врагов %d" % [roundi(sim.wave_time), e.archetype,
							roundi(100.0 * e.hp / e.max_hp), roundi(e.shield), roundi(100.0 * e.dist / total), e.phase_index, sim.enemies.size()])
		print("волна %2d %-11s hp %5d | жизни %2d→%2d | золото %4d удача %d | дет %d | %s" % [w, String(_data.wave(w)["modifier"]), hp,
			lives, sim.lives, sim.gold, sim.luck, EnemyTraits.detectors(sim).size(), " ".join(towers)])
	print(sim.summary()["outcome"])
	quit(0)


func _write_csv(path: String, diff: String) -> void:
	var types: PackedStringArray = _data.damage_types
	var head: PackedStringArray = PackedStringArray(["strategy", "seed", "difficulty", "outcome", "waves_cleared", "lives", "kills", "leaks",
		"gold_earned", "luck", "towers", "specials", "special_ids", "total_damage"])
	for t: String in types:
		head.append("dmg_" + t)
	head.append_array(PackedStringArray(["damage_test_dps", "combat_seconds", "score", "ms"]))
	var lines: PackedStringArray = PackedStringArray([",".join(head)])
	_results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if String(a["strategy"]) != String(b["strategy"]):
			return String(a["strategy"]) < String(b["strategy"])
		return int(a["seed"]) < int(b["seed"]))
	for r: Dictionary in _results:
		if String(r["difficulty"]) != diff:
			continue
		var cells: PackedStringArray = PackedStringArray()
		for key: String in ["strategy", "seed", "difficulty", "outcome", "waves_cleared", "lives", "kills", "leaks", "gold_earned", "luck",
				"towers", "specials", "special_ids", "total_damage"]:
			cells.append(str(r[key]))
		for t2: String in types:
			cells.append(str(int((r["damage_by_type"] as Dictionary).get(t2, 0.0))))
		for key2: String in ["damage_test_dps", "combat_seconds", "score", "ms"]:
			cells.append(str(r[key2]))
		lines.append(",".join(cells))
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()


func _summary_md(difficulties: PackedStringArray, strategies: PackedStringArray, seeds: int, waves: int, total_ms: int) -> String:
	var out: PackedStringArray = PackedStringArray()
	out.append("# balance_sim: %s" % Time.get_datetime_string_from_system(false, true))
	out.append("")
	out.append("Seed'ы %d…%d, волн %d, хеш данных %d, %.1f с." % [SEED_BASE, SEED_BASE + seeds - 1, waves, _data.data_hash, float(total_ms) / 1000.0])
	for diff: String in difficulties:
		out.append("")
		out.append("## %s" % diff)
		out.append("")
		out.append("| Стратегия | Победы | % | Ср. волна | Мин. волна | Частые волны поражения | Ср. золото | Ср. спец-башен | Основной урон | DPS испытания |")
		out.append("|---|---|---|---|---|---|---|---|---|---|")
		for strat: String in strategies:
			var rows: Array[Dictionary] = []
			for r: Dictionary in _results:
				if String(r["difficulty"]) == diff and String(r["strategy"]) == strat:
					rows.append(r)
			if rows.is_empty():
				continue
			var wins: int = 0
			var wave_sum: int = 0
			var wave_min: int = 999
			var gold: int = 0
			var specials: int = 0
			var test_sum: int = 0
			var test_n: int = 0
			var deaths: Dictionary = {}
			var dmg: Dictionary = {}
			for r2: Dictionary in rows:
				if String(r2["outcome"]) == "victory":
					wins += 1
				else:
					var at: int = int(r2["waves_cleared"]) + 1
					deaths[at] = int(deaths.get(at, 0)) + 1
				wave_sum += int(r2["waves_cleared"])
				wave_min = mini(wave_min, int(r2["waves_cleared"]))
				gold += int(r2["gold_earned"])
				specials += int(r2["specials"])
				if int(r2["damage_test_dps"]) > 0:
					test_sum += int(r2["damage_test_dps"])
					test_n += 1
				for t: String in (r2["damage_by_type"] as Dictionary).keys():
					dmg[t] = float(dmg.get(t, 0.0)) + float(r2["damage_by_type"][t])
			var n: int = rows.size()
			out.append("| %s | %d/%d | %d %% | %.1f | %d | %s | %d | %.1f | %s | %s |" % [strat, wins, n, roundi(100.0 * float(wins) / float(n)),
				float(wave_sum) / float(n), wave_min, _top_waves(deaths), gold / n, float(specials) / float(n), _top_types(dmg),
				str(test_sum / test_n) if test_n > 0 else "—"])
		out.append("")
		out.append("Средние утечки по волнам (все стратегии, среди дошедших до волны):")
		out.append("")
		var sums: Dictionary = {}
		var counts: Dictionary = {}
		for r3: Dictionary in _results:
			if String(r3["difficulty"]) != diff:
				continue
			var lw: Array = r3["leaks_by_wave"]
			for w: int in lw.size():
				sums[w + 1] = float(sums.get(w + 1, 0.0)) + float(lw[w])
				counts[w + 1] = int(counts.get(w + 1, 0)) + 1
		var parts: PackedStringArray = PackedStringArray()
		var waves_sorted: Array = sums.keys()
		waves_sorted.sort()
		for wv: Variant in waves_sorted:
			var avg: float = float(sums[wv]) / float(counts[wv])
			if avg >= 0.5:
				parts.append("%d: %.1f" % [int(wv), avg])
		out.append(", ".join(parts) if not parts.is_empty() else "утечек почти нет")
	return "\n".join(out) + "\n"


func _top_waves(deaths: Dictionary) -> String:
	var keys: Array = deaths.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		if int(deaths[a]) != int(deaths[b]):
			return int(deaths[a]) > int(deaths[b])
		return int(a) < int(b))
	var parts: PackedStringArray = PackedStringArray()
	for k: Variant in keys.slice(0, 4):
		parts.append("%d×%d" % [int(k), int(deaths[k])])
	return ", ".join(parts) if not parts.is_empty() else "—"


func _top_types(dmg: Dictionary) -> String:
	var total: float = 0.0
	for v: Variant in dmg.values():
		total += float(v)
	var keys: Array = dmg.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return float(dmg[a]) > float(dmg[b]))
	var parts: PackedStringArray = PackedStringArray()
	for k: Variant in keys.slice(0, 3):
		parts.append("%s %d%%" % [k, roundi(100.0 * float(dmg[k]) / maxf(total, 1.0))])
	return ", ".join(parts)


func _parse(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for a: String in args:
		if not a.begins_with("--"):
			continue
		var kv: PackedStringArray = a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out
