extends Node
## Точка входа: разбор аргументов CLI и переход в нужный экран.


func _ready() -> void:
	var cli: Dictionary = Game.cli
	if not Balance.is_valid():
		push_error("Игра не может стартовать: ошибки в data/ (см. вывод выше)")
	if cli.has("check-scripts"):
		_check_scripts()
		return
	if cli.has("audio-report"):
		Audio.print_report()
		get_tree().quit()
		return
	if cli.has("autoplay") and not cli.has("visual") and not cli.has("screenshot"):
		_run_headless_autoplay(cli)
		return
	if cli.has("mp-host") or cli.has("mp-join"):
		Game.goto_scene.call_deferred("lobby")
		return
	var shot: String = String(cli.get("screenshot", ""))
	if shot == "replay":
		var sim: GameSim = GameSim.new(GameData.load_default(), {"seed": 42, "difficulty": "normal", "max_waves": 4, "record_events": false})
		sim.start()
		BotPlayer.new(sim, "maze", 42).run_to_end()
		Game.run_config = {"mode": "replay", "replay": Replay.from_sim(sim, Game.version()), "record": {"name": "Бот"}}
		Game.goto_scene.call_deferred("game")
		return
	if shot == "tutorial":
		Game.run_config = {"tutorial": true}
		Game.goto_scene.call_deferred("game")
		return
	if shot == "lobby":
		Game.goto_scene.call_deferred("lobby")
		return
	if shot in ["build", "draft", "combat", "results", "tower", "codex", "saveload", "boss", "stress", "damagetest", "codextraits", "codexspecials", "codexenemies", "codexhelp", "wavetraits", "vfx", "forge", "forecast"]:
		Game.run_config = {"seed": 42, "difficulty": "normal"}
		Game.goto_scene.call_deferred("game")
	elif cli.has("autoplay"):
		Game.run_config = {}
		Game.goto_scene.call_deferred("game")
	else:
		Game.goto_scene.call_deferred("menu")


func _run_headless_autoplay(cli: Dictionary) -> void:
	var data: GameData = GameData.load_default()
	var cfg: Dictionary = {
		"seed": RunRng.seed_from_text(String(cli.get("seed", "42"))),
		"difficulty": String(cli.get("difficulty", "normal")),
		"record_events": false,
	}
	if cli.has("waves"):
		cfg["max_waves"] = int(String(cli["waves"]))
	var t0: int = Time.get_ticks_msec()
	var sim: GameSim = GameSim.new(data, cfg)
	sim.start()
	var bot: BotPlayer = BotPlayer.new(sim, String(cli.get("strategy", "maze")), sim.seed_value)
	var s: Dictionary = bot.run_to_end()
	var ms: int = Time.get_ticks_msec() - t0
	var rep: Dictionary = Replay.simulate(data, Replay.from_sim(sim, Game.version()))
	print("autoplay seed=%s difficulty=%s strategy=%s" % [RunRng.seed_to_text(sim.seed_value), sim.difficulty_id, bot.strategy])
	print("  исход: %s, волн %d/%d, жизней %d, убийств %d, утечек %d, удача %d, башен %d" % [s["outcome"], int(s["waves_cleared"]), int(s["total_waves"]), int(s["lives"]), int(s["kills"]), int(s["leaks"]), int(s["luck"]), int(s["towers"])])
	print("  спец-башни: %s" % (str(s["specials"]) if not (s["specials"] as Dictionary).is_empty() else "—"))
	print("  очки: %d, урон: %d, пиковый DPS: %d, время боя: %.1f с, длина пути: %.1f" % [Scoring.compute(data, s), int(s["total_damage"]), int(s["peak_dps"]), float(s["combat_seconds"]), float(s["max_path_length"])])
	print("  checksum: %d (реплей: %s), %d команд, %d мс" % [int(s["checksum"]), "OK" if rep["ok"] else String(rep["reason"]), sim.command_log.size(), ms])
	get_tree().quit(0 if rep["ok"] else 2)


## Компилирует все скрипты проекта в контексте игры (с автозагрузками) и сообщает об ошибках.
func _check_scripts() -> void:
	var failed: int = 0
	var total: int = 0
	var stack: Array[String] = ["res://"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		# ResourceLoader видит и скрипты внутри .pck экспорта (там они лежат как .gdc с ремапами).
		for f: String in ResourceLoader.list_directory(dir):
			if f.ends_with("/"):
				if not f.begins_with("."):
					stack.append(dir.path_join(f.trim_suffix("/")))
				continue
			if not f.ends_with(".gd"):
				continue
			total += 1
			var s: GDScript = load(dir.path_join(f)) as GDScript
			if s == null or not s.can_instantiate() and not s.is_abstract():
				failed += 1
				print("✗ " + dir.path_join(f))
	print("check-scripts: %d скриптов, ошибок %d" % [total, failed])
	get_tree().quit(1 if failed > 0 else 0)
