class_name PerfStress
extends RefCounted
## Стресс-режим игровой сцены: 60 башен вдоль пути, на поле держится ~300 врагов, скорость 4×.
## Меряет FPS (средний и 1 % low) и время тика симуляции; пишет docs/perf.md.

const TOWERS: int = 60
const ENEMIES: int = 300
const WAVE: int = 25
const WARMUP: float = 4.0
const RESULTS: String = "res://docs/perf/results.json"
const REPORT: String = "res://docs/perf.md"
const KINDS: Array[String] = ["normal", "fast", "armored", "swarm", "flying", "regenerating", "shielded", "arcane_resistant"]
const FrameProbe: GDScript = preload("res://tests/perf/frame_probe.gd")

var game: Node
var seconds: float = 60.0
var _t: float = 0.0
var _frames: PackedFloat32Array = PackedFloat32Array()
var _tick_usec: int = 0
var _ticks: int = 0
var _tick_max: int = 0
var _enemy_sum: int = 0
var _projectile_max: int = 0
var _done: bool = false
var _probe: RefCounted = null


## Симуляция для замера: башни ставятся напрямую (это не игровой забег), жизни бесконечны.
static func make_sim(data: GameData) -> GameSim:
	var sim: GameSim = GameSim.new(data, {"seed": 777, "difficulty": "normal", "record_events": true})
	sim.start()
	var placed: int = 0
	var on_path: Dictionary = {}
	for c: Vector2i in sim.route.ground_cells:
		on_path[c] = true
	for c2: Vector2i in sim.route.ground_cells:
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var cell: Vector2i = c2 + d * 2
			if placed >= TOWERS or on_path.has(cell) or not sim.grid.is_buildable(cell) or sim.grid.get_cell(cell) != BoardGrid.Cell.EMPTY:
				continue
			if placed % 6 == 5:
				var sp: String = data.special_ids[int(placed / 6.0) % data.special_ids.size()]
				var t: TowerState = sim.add_special_tower(cell, sp)
				t.level = 1 + int(placed / 6.0) % 3
				t.refresh_stats(data)
			else:
				sim.add_gem_tower(cell, data.gem_ids[placed % data.gem_ids.size()], 3 + placed % 3)
			placed += 1
	sim.route.recompute()
	sim.combat.recompute_auras(sim)
	sim.lives = 1000000
	sim.max_lives = sim.lives
	sim.round_index = WAVE
	sim.phase = GameSim.Phase.READY
	sim.apply({"type": "start_wave"})
	sim.drain_events()
	return sim


func _init(g: Node) -> void:
	game = g
	seconds = float(String(Game.cli.get("seconds", "60")))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0


## Кадр игровой сцены: пополняет врагов и копит замеры.
func frame(delta: float) -> void:
	if _done:
		return
	_top_up()
	_t += delta
	if _t < WARMUP:
		return
	_frames.append(delta)
	if _probe == null:
		_probe = FrameProbe.new(game.get_viewport())
	_probe.call("sample")
	var sim: GameSim = game.sim
	_enemy_sum += sim.enemies.size()
	_projectile_max = maxi(_projectile_max, sim.projectiles.size())
	if _t >= WARMUP + seconds:
		_done = true
		_finish()


func add_ticks(usec: int, steps: int) -> void:
	if _t < WARMUP or steps <= 0:
		return
	_tick_usec += usec
	_ticks += steps
	_tick_max = maxi(_tick_max, usec / steps)


func _top_up() -> void:
	var sim: GameSim = game.sim
	var c: CombatSystem = sim.combat
	var missing: int = ENEMIES - sim.enemies.size() - (c.schedule.size() - c.schedule_index)
	for i: int in mini(missing, 12):
		c.schedule.append({"time": sim.wave_time, "type": KINDS[(sim.tick + i) % KINDS.size()], "hp_mult": 8.0,
			"traits": [], "elite": i % 9 == 0, "order": sim.tick * 16 + i})


func _finish() -> void:
	var sorted: PackedFloat32Array = _frames.duplicate()
	sorted.sort()
	var total: float = 0.0
	for f: float in _frames:
		total += f
	var n: int = _frames.size()
	var p99: float = sorted[clampi(int(float(n) * 0.99), 0, n - 1)]
	var res: Dictionary = {
		"preset": Graphics.preset_id(),
		"date": Time.get_datetime_string_from_system(false, true),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"cpu": OS.get_processor_name(),
		"resolution": "%dx%d" % [game.get_viewport().get_visible_rect().size.x, game.get_viewport().get_visible_rect().size.y],
		"render_scale": Graphics.render_scale(),
		"speed": int(game.speed),
		"seconds": snappedf(total, 0.1),
		"frames": n,
		"avg_fps": snappedf(float(n) / maxf(total, 0.001), 0.1),
		"low1_fps": snappedf(1.0 / maxf(p99, 0.0001), 0.1),
		"avg_enemies": roundi(float(_enemy_sum) / float(maxi(n, 1))),
		"towers": (game.sim as GameSim).towers.size(),
		"max_projectiles": _projectile_max,
		"tick_avg_ms": snappedf(float(_tick_usec) / float(maxi(_ticks, 1)) / 1000.0, 0.01),
		"tick_max_ms": snappedf(float(_tick_max) / 1000.0, 0.01),
	}
	res["breakdown"] = _probe.call("report") if _probe != null else {}
	print("stress: %s" % JSON.stringify(res))
	print("stress-breakdown: %s" % JSON.stringify(res["breakdown"]))
	for row: Array in FrameProbe.census(game.get_tree().root).slice(0, 25):
		print("stress-census: %5d  %s" % [int(row[1]), String(row[0])])
	_write(res)
	Audio.stop_all()
	game.get_tree().create_timer(0.3).timeout.connect(func() -> void: game.get_tree().quit())


func _write(res: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RESULTS.get_base_dir()))
	var all: Dictionary = {}
	if FileAccess.file_exists(RESULTS):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RESULTS))
		if parsed is Dictionary:
			all = parsed
	all[String(res["preset"]) + ("" if String(res["renderer"]) != "gl_compatibility" else "_compat")] = res
	var f: FileAccess = FileAccess.open(RESULTS, FileAccess.WRITE)
	f.store_string(JSON.stringify(all, "\t"))
	f.close()
	var lines: PackedStringArray = PackedStringArray([
		"# Производительность",
		"",
		"Стресс-тест `tests/perf/stress.tscn` (§13 PROMPT.md): реальная игровая сцена с HUD, %d башен вдоль пути," % TOWERS,
		"на поле поддерживается ~%d врагов (волна %d, все архетипы, часть — элита), скорость 4×, vsync выключен." % [ENEMIES, WAVE],
		"Замер — %d с после %d с прогрева. Цели: ≥ 60 FPS на High; тик симуляции ≤ 2 мс при 300 врагах." % [int(seconds), int(WARMUP)],
		"",
		"```bash",
		"godot --path . res://tests/perf/stress.tscn -- --preset=high",
		"```",
		"",
		"| Пресет | Рендерер | Разрешение | Средний FPS | 1 % low | Врагов (ср.) | Башен | Тик ср., мс | Тик макс., мс | Дата |",
		"|---|---|---|---|---|---|---|---|---|---|",
	])
	var keys: Array = all.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return Graphics.ORDER.find(String(a).trim_suffix("_compat")) * 2 + (1 if String(a).ends_with("_compat") else 0) < Graphics.ORDER.find(String(b).trim_suffix("_compat")) * 2 + (1 if String(b).ends_with("_compat") else 0))
	for k: Variant in keys:
		var r: Dictionary = all[k]
		lines.append("| %s | %s | %s × %d%% | %s | %s | %d | %d | %s | %s | %s |" % [String(r["preset"]), String(r["renderer"]), String(r["resolution"]),
			roundi(float(r["render_scale"]) * 100.0), str(r["avg_fps"]), str(r["low1_fps"]), int(r["avg_enemies"]), int(r["towers"]),
			str(r["tick_avg_ms"]), str(r["tick_max_ms"]), String(r["date"]).substr(0, 16).replace("T", " ")])
	var any: Dictionary = all[keys[0]] if not keys.is_empty() else res
	lines.append("")
	lines.append("Машина: %s, GPU: %s." % [String(any["cpu"]), String(any["gpu"])])
	lines.append("")
	lines.append("Время тика — среднее и максимальное время одного шага `GameSim.step()` (30 тиков в секунду игры; при 4× — 120 тиков в секунду реального времени).")
	lines.append("")
	lines.append("## Разбивка кадра")
	lines.append("")
	lines.append("Средние за кадр (`tests/perf/frame_probe.gd`): «Узлы» — `_process` всех узлов, включая шаги симуляции; «Хвост» — твины, таймеры,")
	lines.append("отложенные вызовы и перерисовка `_draw` до начала отрисовки; «Отрисовка» — от `frame_pre_draw` до `frame_post_draw`")
	lines.append("(с ожиданием GPU); «Прочее» — физика, ввод, аудио до следующего кадра.")
	lines.append("")
	lines.append("| Пресет | Рендерер | Узлы, мс | Хвост, мс | Отрисовка, мс | Прочее, мс | Вызовов отрисовки | Объектов | Узлов в дереве |")
	lines.append("|---|---|---|---|---|---|---|---|---|")
	for k2: Variant in keys:
		var r2: Dictionary = all[k2]
		var b: Dictionary = r2.get("breakdown", {})
		if b.is_empty():
			continue
		lines.append("| %s | %s | %s | %s | %s | %s | %d | %d | %d |" % [String(r2["preset"]), String(r2["renderer"]), str(b.get("seg_nodes_ms", "—")),
			str(b.get("seg_flush_ms", "—")), str(b.get("seg_draw_ms", "—")), str(b.get("seg_rest_ms", "—")), roundi(float(b.get("draw_calls", 0))),
			roundi(float(b.get("objects", 0))), roundi(float(b.get("nodes", 0)))])
	var f2: FileAccess = FileAccess.open(REPORT, FileAccess.WRITE)
	f2.store_string("\n".join(lines) + "\n")
	f2.close()
