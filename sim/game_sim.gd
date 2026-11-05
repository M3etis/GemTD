class_name GameSim
extends RefCounted
## Детерминированная симуляция забега. Не зависит от узлов сцены.
## Любое изменение состояния — через apply(команда) или step() (§2 PROMPT.md).

enum Phase { PLACING, CHOOSING, READY, COMBAT, VICTORY, DEFEAT }

const PHASE_NAMES: Array[String] = ["placing", "choosing", "ready", "combat", "victory", "defeat"]

var data: GameData
var config: Dictionary = {}
var seed_value: int = 0
var difficulty_id: String = "normal"
var diff: Dictionary = {}
var map_id: String = "arena_01"
var rng: RunRng
var combat_rng: RunRng
var grid: BoardGrid
var route: RoutePlanner
var combat: CombatSystem
var record_events: bool = true

var phase: int = Phase.PLACING
var round_index: int = 1
var wave_number: int = 0
## Последняя волна забега; в бесконечном режиме («Гонка» до последнего выжившего) — 0.
var total_waves: int = 0
var endless: bool = false
## Настройки длины забега (waves.json → lengths): финальный босс и разгон сложности. {} — нестандартная длина.
var length_cfg: Dictionary = {}
var tick: int = 0
var dt: float = 1.0 / 30.0
var wave_time: float = 0.0
var lives: int = 20
var max_lives: int = 20
var gold: int = 0
var luck: int = 1
var rocks_per_round: int = 5

var next_id: int = 1
var towers: Array[TowerState] = []
var tower_by_cell: Dictionary = {}
var tower_by_id: Dictionary = {}
var rocks: Array[Vector2i] = []
## Слейты — плиты на земле отдельным слоем: клетка под слейтом проходима, камень и башню на неё ставить можно.
var slates: Array[TowerState] = []
var slate_by_cell: Dictionary = {}
var slate_by_id: Dictionary = {}
## Гемы текущего раунда до выбора: {cell, gem, quality, slot}
var candidates: Array[Dictionary] = []
var enemies: Array[EnemyState] = []
var enemy_by_id: Dictionary = {}
var projectiles: Array[ProjectileState] = []
## Ядовитые лужи: {pos, radius, dps, slow, until, source}
var pools: Array[Dictionary] = []
var walls_broken: int = 0
var lives_bought: int = 0
## Сколько раз перекладывали слейты и переносили башни: от этого растёт цена следующего переноса.
var slate_moves: int = 0
var tower_moves: int = 0

var events: Array[Dictionary] = []
var command_log: Array[Dictionary] = []
## Вызывается после каждой успешной команды (мультиплеер пересылает её соперникам).
var command_listener: Callable = Callable()
var wave_checksums: Array[Dictionary] = []

var stats: Dictionary = {}
var wave_leaks: int = 0
var wave_start_tick: int = 0
var wave_damage_total: float = 0.0
## Испытание урона: идёт поверх фазы COMBAT после победы, затем снова VICTORY.
var damage_test: bool = false
var damage_test_done: bool = false
var test_damage: float = 0.0


func _init(game_data: GameData, cfg: Dictionary = {}) -> void:
	data = game_data
	config = cfg.duplicate(true)
	seed_value = int(cfg.get("seed", 0)) & HashUtil.MASK32
	difficulty_id = String(cfg.get("difficulty", data.default_difficulty))
	diff = data.difficulty(difficulty_id).duplicate()
	difficulty_id = String(diff.get("id", difficulty_id))
	map_id = String(cfg.get("map", "arena_01"))
	record_events = bool(cfg.get("record_events", true))
	endless = bool(cfg.get("endless", false))
	total_waves = 0 if endless else mini(data.wave_count(), int(cfg.get("max_waves", data.wave_count())))
	length_cfg = {} if endless else data.run_length_cfg(total_waves)
	# Короткий забег: разгон HP сложности (Hard, Extreme) укладывается в его длину (ramp_scale).
	var ramp: int = int(diff.get("hp_ramp_waves", 0))
	if ramp > 0 and not length_cfg.is_empty():
		diff["hp_ramp_waves"] = maxi(1, roundi(float(ramp) * float(length_cfg["ramp_scale"])))
	dt = 1.0 / float(data.tick_rate())
	rng = RunRng.new(seed_value)
	combat_rng = rng.fork("combat", 0)


func start() -> void:
	grid = BoardGrid.new()
	grid.setup(data.map(map_id))
	route = RoutePlanner.new(grid)
	route.recompute()
	combat = CombatSystem.new(data)
	lives = int(diff["lives"])
	max_lives = lives
	gold = int(data.economy["start_gold"])
	rocks_per_round = int(data.economy["rocks_per_round"])
	stats = {
		"kills": 0, "leaks": 0, "gold_earned": 0, "perfect_waves": 0, "waves_cleared": 0,
		"combat_ticks": 0, "total_damage": 0.0, "peak_wave_dps": 0.0, "max_path_length": route.ground_length,
		"specials_forged": {},
		"slates_made": {},
		"damage_by_type": {},
		"leaks_by_wave": [],
		"wave_dps": [],
	}
	phase = Phase.PLACING
	_emit({"type": "round_started", "round": round_index})


# --- Команды -----------------------------------------------------------------

## Применяет команду игрока. Возвращает {ok, reason}. Успешные команды пишутся в лог (реплей).
func apply(cmd: Dictionary) -> Dictionary:
	var res: Dictionary
	match String(cmd.get("type", "")):
		"place":
			res = _cmd_place(Vector2i(int(cmd["x"]), int(cmd["y"])))
		"keep":
			res = _cmd_keep(Vector2i(int(cmd["x"]), int(cmd["y"])))
		"downgrade":
			res = _cmd_downgrade(_cell(cmd))
		"start_wave":
			res = _cmd_start_wave()
		"upgrade_luck":
			res = _cmd_upgrade_luck()
		"combine":
			res = BuildCommands.combine(self, _cell(cmd), int(cmd.get("count", 2)))
		"forge":
			res = BuildCommands.forge(self, _cell(cmd), String(cmd.get("special", "")))
		"upgrade_special":
			var with_cell: Vector2i = Vector2i(int(cmd.get("with_x", -1)), int(cmd.get("with_y", -1)))
			res = BuildCommands.upgrade_special(self, _cell(cmd), with_cell)
		"merge_special":
			res = BuildCommands.merge_special(self, _cell(cmd), Vector2i(int(cmd.get("with_x", -1)), int(cmd.get("with_y", -1))))
		"make_slate":
			res = SlateCommands.make(self, _cell(cmd), String(cmd.get("slate", "")))
		"combine_slates":
			res = SlateCommands.combine(self, _cell(cmd), Vector2i(int(cmd.get("with_x", -1)), int(cmd.get("with_y", -1))))
		"move_slate":
			res = SlateCommands.move(self, _cell(cmd), Vector2i(int(cmd.get("to_x", -1)), int(cmd.get("to_y", -1))))
		"move_tower":
			res = BuildCommands.move_tower(self, _cell(cmd), Vector2i(int(cmd.get("to_x", -1)), int(cmd.get("to_y", -1))))
		"polish":
			res = BuildCommands.polish(self, _cell(cmd))
		"sell":
			res = BuildCommands.sell(self, _cell(cmd))
		"sell_slate":
			res = SlateCommands.sell(self, _cell(cmd))
		"break_wall":
			res = BuildCommands.break_wall(self, _cell(cmd))
		"buy_life":
			res = BuildCommands.buy_life(self)
		"give_gold":
			res = BuildCommands.give_gold(self, int(cmd.get("to", 0)), int(cmd.get("amount", 0)))
		"receive_gold":
			res = BuildCommands.receive_gold(self, int(cmd.get("from", 0)), int(cmd.get("amount", 0)))
		"set_targeting":
			res = BuildCommands.set_targeting(self, _cell(cmd), String(cmd.get("mode", "first")))
		"toggle_tower":
			res = BuildCommands.toggle_tower(self, _cell(cmd), bool(cmd.get("enabled", true)))
		"start_damage_test":
			res = _cmd_start_damage_test()
		_:
			res = {"ok": false, "reason": "ERR_UNKNOWN_COMMAND"}
	if res["ok"]:
		var logged: Dictionary = cmd.duplicate()
		logged.erase("tick")
		logged["tick"] = tick
		command_log.append(logged)
		if command_listener.is_valid():
			command_listener.call(logged)
	return res


static func _cell(cmd: Dictionary) -> Vector2i:
	return Vector2i(int(cmd.get("x", -1)), int(cmd.get("y", -1)))


func is_build_phase() -> bool:
	return phase == Phase.PLACING or phase == Phase.CHOOSING or phase == Phase.READY


func can_place(c: Vector2i) -> String:
	if phase != Phase.PLACING:
		return "ERR_NOT_PLACING"
	if not grid.in_bounds(c):
		return "ERR_OUT_OF_BOUNDS"
	if grid.is_no_build(c):
		return "ERR_NO_BUILD_ZONE"
	if grid.get_cell(c) != BoardGrid.Cell.EMPTY:
		return "ERR_OCCUPIED"
	return ""


## Превью постановки камня: {ok, reason, length, delta, cells, segment}.
func preview_place(c: Vector2i) -> Dictionary:
	var reason: String = can_place(c)
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "length": route.ground_length, "delta": 0.0, "cells": [], "segment": -1}
	var extra: Array[Vector2i] = [c]
	var res: Dictionary = route.compute(extra)
	if not res["ok"]:
		return {"ok": false, "reason": "ERR_BLOCKS_PATH", "length": route.ground_length, "delta": 0.0, "cells": [], "segment": res["segment"]}
	var pts: PackedVector2Array = RoutePlanner.cells_to_points(res["cells"])
	var length: float = RoutePlanner.path_length(pts)
	return {"ok": true, "reason": "", "length": length, "delta": length - route.ground_length, "cells": res["cells"], "segment": -1}


func _cmd_place(c: Vector2i) -> Dictionary:
	var preview: Dictionary = preview_place(c)
	if not preview["ok"]:
		return {"ok": false, "reason": preview["reason"], "segment": preview.get("segment", -1)}
	var slot: int = candidates.size()
	var roll: Dictionary = roll_gem(round_index, slot, luck)
	grid.set_cell(c, BoardGrid.Cell.CANDIDATE)
	candidates.append({"cell": c, "gem": roll["gem"], "quality": roll["quality"], "slot": slot})
	route.recompute()
	stats["max_path_length"] = maxf(float(stats["max_path_length"]), route.ground_length)
	_emit({"type": "rock_placed", "cell": c, "slot": slot})
	_emit({"type": "gem_revealed", "cell": c, "slot": slot, "gem": roll["gem"], "quality": roll["quality"]})
	_emit({"type": "path_changed", "length": route.ground_length})
	if candidates.size() >= rocks_per_round:
		phase = Phase.CHOOSING
		_emit({"type": "choice_ready"})
	return {"ok": true, "reason": ""}


## Ролл зависит только от seed, раунда, слота и уровня удачи — не от позиции и не от времени.
## config.draft_overrides {"<раунд>": [[гем, качество], …]} задаёт выпадение заранее (обучение).
func roll_gem(round_i: int, slot: int, luck_level: int) -> Dictionary:
	var overrides: Dictionary = config.get("draft_overrides", {})
	var fixed: Array = overrides.get(str(round_i), [])
	if slot < fixed.size():
		return {"gem": String(fixed[slot][0]), "quality": int(fixed[slot][1])}
	var r: RunRng = rng.fork("draft", round_i, slot)
	var gem_index: int = r.range_int(0, data.gem_ids.size() - 1)
	var chances: Array = data.luck_chances(luck_level)
	var total: float = 0.0
	for ch: Variant in chances:
		total += float(ch)
	var roll: float = r.next_float() * total
	var q: int = 1
	for i: int in chances.size():
		roll -= float(chances[i])
		if roll < 0.0:
			q = i + 1
			break
	return {"gem": data.gem_ids[gem_index], "quality": q}


func candidate_at(c: Vector2i) -> Dictionary:
	for cand: Dictionary in candidates:
		if cand["cell"] == c:
			return cand
	return {}


func _cmd_keep(c: Vector2i) -> Dictionary:
	if phase != Phase.CHOOSING:
		return {"ok": false, "reason": "ERR_NOT_CHOOSING"}
	var chosen: Dictionary = candidate_at(c)
	if chosen.is_empty():
		return {"ok": false, "reason": "ERR_NOT_CANDIDATE"}
	var t: TowerState = add_gem_tower(c, String(chosen["gem"]), int(chosen["quality"]))
	_emit({"type": "gem_kept", "cell": c, "tower_id": t.id, "gem": t.gem_id, "quality": t.quality})
	finish_choice(c)
	return {"ok": true, "reason": ""}


## Можно ли оставить кандидата на уровень качества ниже: "" или код ошибки.
func can_downgrade(c: Vector2i) -> String:
	if phase != Phase.CHOOSING:
		return "ERR_NOT_CHOOSING"
	var cand: Dictionary = candidate_at(c)
	if cand.is_empty():
		return "ERR_NOT_CANDIDATE"
	if int(cand["quality"]) <= 1:
		return "ERR_DOWNGRADE_MIN"
	return ""


## Как Keep, но башня встаёт на уровень качества ниже (нужное качество для рецепта).
func _cmd_downgrade(c: Vector2i) -> Dictionary:
	var reason: String = can_downgrade(c)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	var chosen: Dictionary = candidate_at(c)
	var from_q: int = int(chosen["quality"])
	var t: TowerState = add_gem_tower(c, String(chosen["gem"]), from_q - 1)
	_emit({"type": "gem_kept", "cell": c, "tower_id": t.id, "gem": t.gem_id, "quality": t.quality, "downgraded": true, "from_quality": from_q})
	finish_choice(c)
	return {"ok": true, "reason": ""}


## Создаёт башню-гем в клетке (кандидат или пустая клетка).
func add_gem_tower(c: Vector2i, gem: String, quality: int) -> TowerState:
	var t: TowerState = TowerState.new()
	t.setup(data, _new_id(), c, gem, quality, round_index)
	_register_tower(t)
	return t


func add_special_tower(c: Vector2i, special: String) -> TowerState:
	var t: TowerState = TowerState.new()
	t.setup_special(data, _new_id(), c, special, round_index)
	_register_tower(t)
	return t


func _register_tower(t: TowerState) -> void:
	towers.append(t)
	tower_by_cell[t.cell] = t
	tower_by_id[t.id] = t
	grid.set_cell(t.cell, BoardGrid.Cell.GEM)


func add_slate(c: Vector2i, slate: String) -> TowerState:
	var s: TowerState = TowerState.new()
	s.setup_slate(data, _new_id(), c, slate, round_index)
	slates.append(s)
	slate_by_cell[c] = s
	slate_by_id[s.id] = s
	grid.set_reserved(c, true)
	return s


## Убирает слейт; клетка остаётся как была (пустой, со стеной или башней).
func remove_slate(s: TowerState) -> void:
	slates.erase(s)
	slate_by_cell.erase(s.cell)
	slate_by_id.erase(s.id)
	grid.set_reserved(s.cell, false)


## Убирает башню из списков, не меняя клетку (для замены башни другой в той же клетке).
func remove_tower(t: TowerState) -> void:
	towers.erase(t)
	tower_by_cell.erase(t.cell)
	tower_by_id.erase(t.id)


## Убирает башню; на её месте остаётся стена (лабиринт не меняется).
func tower_to_wall(t: TowerState) -> void:
	towers.erase(t)
	tower_by_cell.erase(t.cell)
	tower_by_id.erase(t.id)
	grid.set_cell(t.cell, BoardGrid.Cell.ROCK)
	rocks.append(t.cell)
	_emit({"type": "wall_formed", "cell": t.cell, "from_tower": true})


## Завершает выбор раунда: все кандидаты, кроме keep_cell, становятся стенами.
func finish_choice(keep_cell: Vector2i) -> void:
	for cand: Dictionary in candidates:
		var cell: Vector2i = cand["cell"]
		if cell == keep_cell:
			continue
		grid.set_cell(cell, BoardGrid.Cell.ROCK)
		rocks.append(cell)
		_emit({"type": "wall_formed", "cell": cell})
	candidates.clear()
	combat.recompute_auras(self)
	phase = Phase.READY
	_emit({"type": "ready_for_wave", "wave": round_index})


func _cmd_start_wave() -> Dictionary:
	if phase != Phase.READY:
		return {"ok": false, "reason": "ERR_NOT_READY"}
	wave_number = round_index
	wave_time = 0.0
	wave_leaks = 0
	wave_start_tick = tick
	wave_damage_total = 0.0
	for t: TowerState in towers:
		t.wave_damage = 0.0
	combat_rng = rng.fork("combat", wave_number)
	combat.begin_wave(self, wave_number)
	phase = Phase.COMBAT
	_emit({"type": "wave_started", "wave": wave_number, "air": data.is_air_wave(wave_number),
		"boss": data.is_boss_wave(wave_number), "modifier": data.wave(wave_number)["modifier"], "finale": is_finale(wave_number)})
	return {"ok": true, "reason": ""}


func _cmd_start_damage_test() -> Dictionary:
	if phase != Phase.VICTORY:
		return {"ok": false, "reason": "ERR_NOT_VICTORY"}
	if damage_test_done:
		return {"ok": false, "reason": "ERR_TEST_DONE"}
	damage_test = true
	test_damage = 0.0
	wave_time = 0.0
	for t: TowerState in towers:
		t.test_damage = 0.0
	combat_rng = rng.fork("damage_test", 0)
	combat.begin_damage_test(self)
	phase = Phase.COMBAT
	_emit({"type": "damage_test_started", "duration": damage_test_duration()})
	return {"ok": true, "reason": ""}


func damage_test_duration() -> float:
	return float(data.economy["damage_test"]["duration"])


## Волна, по которой считается HP врагов (для колосса Испытания — волна из economy.damage_test).
func hp_wave() -> int:
	return int(data.economy["damage_test"]["wave"]) if damage_test else maxi(wave_number, 1)


## Множитель HP сложности для текущей волны (с разгоном `hp_ramp_waves`, см. GameData.difficulty_hp_mult).
func diff_hp_mult() -> float:
	return data.difficulty_hp_mult(diff, hp_wave())


func _cmd_upgrade_luck() -> Dictionary:
	if is_over():
		return {"ok": false, "reason": "ERR_GAME_OVER"}
	var cost: int = data.luck_cost(luck)
	if cost < 0:
		return {"ok": false, "reason": "ERR_LUCK_MAX"}
	if gold < cost:
		return {"ok": false, "reason": "ERR_NOT_ENOUGH_GOLD"}
	add_gold(-cost)
	luck += 1
	_emit({"type": "luck_upgraded", "level": luck})
	return {"ok": true, "reason": ""}


# --- Шаг симуляции -----------------------------------------------------------

func step() -> void:
	if phase != Phase.COMBAT:
		return
	combat.step(self, dt)
	tick += 1
	wave_time += dt
	if damage_test:
		if wave_time >= damage_test_duration() - 0.0001:
			_finish_damage_test()
		return
	stats["combat_ticks"] = int(stats["combat_ticks"]) + 1
	if phase == Phase.COMBAT and lives <= 0:
		_finish(false)
	elif phase == Phase.COMBAT and combat.wave_finished(self):
		_end_wave()


func _end_wave() -> void:
	(stats["leaks_by_wave"] as Array).append(wave_leaks)
	var perfect: bool = wave_leaks == 0
	var clear_cfg: Dictionary = data.economy["wave_clear_gold"]
	var bonus: int = int(clear_cfg["base"]) + int(clear_cfg["per_wave"]) * wave_number
	if perfect:
		bonus += int(data.economy["perfect_wave_bonus"])
		stats["perfect_waves"] = int(stats["perfect_waves"]) + 1
	var idol: int = SpecialCombat.idol_wave_gold(self)
	add_gold(bonus + idol)
	_award_mvp()
	pools.clear()
	stats["waves_cleared"] = wave_number
	var seconds: float = maxf(float(tick - wave_start_tick) * dt, 0.001)
	stats["peak_wave_dps"] = maxf(float(stats["peak_wave_dps"]), wave_damage_total / seconds)
	(stats["wave_dps"] as Array).append(roundf(wave_damage_total / seconds))
	projectiles.clear()
	wave_checksums.append({"wave": wave_number, "tick": tick, "checksum": checksum()})
	_emit({"type": "wave_cleared", "wave": wave_number, "perfect": perfect, "gold": bonus, "idol_gold": idol})
	if not endless and wave_number >= total_waves:
		_finish(true)
		return
	round_index += 1
	phase = Phase.PLACING
	_emit({"type": "round_started", "round": round_index})


func _award_mvp() -> void:
	var best: TowerState = null
	for t: TowerState in towers:
		if t.wave_damage > 0.0 and (best == null or t.wave_damage > best.wave_damage):
			best = t
	if best == null:
		return
	var cap: int = int(data.economy["mvp"]["max_stacks"])
	if best.mvp < cap:
		best.mvp += 1
		combat.recompute_auras(self)
	_emit({"type": "mvp_awarded", "tower_id": best.id, "cell": best.cell, "stacks": best.mvp, "damage": roundf(best.wave_damage)})


func _finish_damage_test() -> void:
	damage_test = false
	damage_test_done = true
	phase = Phase.VICTORY
	enemies.clear()
	enemy_by_id.clear()
	projectiles.clear()
	pools.clear()
	stats["damage_test_damage"] = test_damage
	stats["damage_test_dps"] = test_damage / damage_test_duration()
	_emit({"type": "damage_test_finished", "damage": roundf(test_damage), "dps": roundf(test_damage / damage_test_duration())})


func _finish(victory: bool) -> void:
	if not victory:
		(stats["leaks_by_wave"] as Array).append(wave_leaks)
	phase = Phase.VICTORY if victory else Phase.DEFEAT
	enemies.clear()
	enemy_by_id.clear()
	projectiles.clear()
	pools.clear()
	_emit({"type": "game_over", "victory": victory})


# --- Изменения состояния из боевой системы -----------------------------------

func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold += amount
	if amount > 0:
		stats["gold_earned"] = int(stats["gold_earned"]) + amount
	_emit({"type": "gold_changed", "gold": gold, "delta": amount})


func lose_lives(amount: int, instant_defeat: bool) -> void:
	lives = 0 if instant_defeat else maxi(0, lives - amount)
	wave_leaks += 1
	stats["leaks"] = int(stats["leaks"]) + 1
	_emit({"type": "lives_changed", "lives": lives, "delta": -amount})


func _new_id() -> int:
	var i: int = next_id
	next_id += 1
	return i


func new_id() -> int:
	return _new_id()


func _emit(e: Dictionary) -> void:
	if record_events:
		events.append(e)


func emit_event(e: Dictionary) -> void:
	_emit(e)


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events
	events = []
	return out


# --- Запросы -----------------------------------------------------------------

func is_over() -> bool:
	return phase == Phase.VICTORY or phase == Phase.DEFEAT


func phase_name() -> String:
	return PHASE_NAMES[phase]


func time_seconds() -> float:
	return float(tick) * dt


func next_wave_number() -> int:
	if phase == Phase.COMBAT:
		return wave_number
	return round_index if endless else mini(round_index, total_waves)


## Последняя волна, до которой имеет смысл заглядывать (прогноз, бот): в бесконечном режиме — без предела.
func wave_limit() -> int:
	return 1 << 30 if endless else total_waves


## Финальная волна забега стандартной длины: её боссы усилены (waves.json → lengths).
func is_finale(n: int) -> bool:
	return not endless and n == total_waves and not length_cfg.is_empty() \
		and (float(length_cfg["finale_hp_mult"]) != 1.0 or bool(length_cfg["finale_elite"]) or int(length_cfg["finale_leak"]) > 0)


## Настройки усиления боссов для волны n ({} — волна не финальная).
func finale_for(n: int) -> Dictionary:
	return length_cfg if is_finale(n) else {}


func best_tower() -> TowerState:
	var best: TowerState = null
	for t: TowerState in towers:
		if best == null or t.total_damage > best.total_damage:
			best = t
	return best


func checksum() -> int:
	var h: int = HashUtil.combine(seed_value, tick)
	h = HashUtil.combine(h, phase)
	h = HashUtil.combine(h, round_index)
	h = HashUtil.combine(h, wave_number)
	h = HashUtil.combine(h, lives)
	h = HashUtil.combine(h, gold)
	h = HashUtil.combine(h, luck)
	h = HashUtil.combine(h, grid.cells_hash())
	for t: TowerState in towers:
		h = HashUtil.combine(h, t.id)
		h = HashUtil.combine(h, grid.idx(t.cell))
		h = HashUtil.combine(h, HashUtil.fnv1a_str(t.gem_id))
		h = HashUtil.combine(h, t.quality)
		h = HashUtil.combine(h, HashUtil.fnv1a_str(t.special_id + ":" + t.targeting))
		h = HashUtil.combine(h, 1000 * t.merge_level + t.level * 100 + t.mvp * 2 + (1 if t.enabled else 0))
		h = HashUtil.combine(h, t.polish)
		h = HashUtil.combine(h, HashUtil.q(t.total_damage, 10.0))
	for sl: TowerState in slates:
		h = HashUtil.combine(h, sl.id)
		h = HashUtil.combine(h, grid.idx(sl.cell))
		h = HashUtil.combine(h, HashUtil.fnv1a_str(sl.slate_id))
		h = HashUtil.combine(h, sl.kills * 64 + sl.moves)
		h = HashUtil.combine(h, HashUtil.q(sl.total_damage, 10.0))
	for e: EnemyState in enemies:
		h = HashUtil.combine(h, e.id)
		h = HashUtil.combine(h, HashUtil.q(e.hp, 10.0))
		h = HashUtil.combine(h, HashUtil.q(e.dist, 100.0))
	h = HashUtil.combine(h, walls_broken * 1000 + lives_bought)
	h = HashUtil.combine(h, slate_moves * 1000 + tower_moves)
	h = HashUtil.combine(h, (2 if damage_test else 0) + (1 if damage_test_done else 0))
	h = HashUtil.combine(h, HashUtil.q(test_damage, 10.0))
	h = HashUtil.combine(h, combat_rng.state_hash())
	return h


func summary() -> Dictionary:
	var bt: TowerState = best_tower()
	var best: Dictionary = {}
	if bt != null:
		best = {"gem": bt.gem_id, "quality": bt.quality, "special": bt.special_id, "level": bt.level, "damage": roundf(bt.total_damage)}
	var gems_used: Dictionary = {}
	var specials_used: Dictionary = {}
	for t: TowerState in towers:
		if t.is_special():
			specials_used[t.special_id] = maxi(int(specials_used.get(t.special_id, 0)), t.level)
		else:
			gems_used[t.gem_id] = int(gems_used.get(t.gem_id, 0)) + 1
	var slates_used: Dictionary = {}
	for sl: TowerState in slates:
		slates_used[sl.slate_id] = int(slates_used.get(sl.slate_id, 0)) + 1
	for sp: String in stats.get("specials_forged", {}).keys():
		if not specials_used.has(sp):
			specials_used[sp] = 1
	return {
		"outcome": "victory" if phase == Phase.VICTORY else ("defeat" if phase == Phase.DEFEAT else "running"),
		"seed": seed_value,
		"difficulty": difficulty_id,
		"map": map_id,
		"waves_cleared": int(stats["waves_cleared"]),
		"wave_reached": wave_number,
		"total_waves": total_waves,
		"endless": endless,
		"kills": int(stats["kills"]),
		"leaks": int(stats["leaks"]),
		"lives": lives,
		"gold_earned": int(stats["gold_earned"]),
		"perfect_waves": int(stats["perfect_waves"]),
		"combat_seconds": float(stats["combat_ticks"]) * dt,
		"total_damage": roundf(float(stats["total_damage"])),
		"peak_dps": roundf(float(stats["peak_wave_dps"])),
		"max_path_length": float(stats["max_path_length"]),
		"best_tower": best,
		"specials": specials_used,
		"slates": slates_used,
		"towers": towers.size(),
		"gems_used": gems_used,
		"damage_by_type": (stats["damage_by_type"] as Dictionary).duplicate(),
		"leaks_by_wave": (stats["leaks_by_wave"] as Array).duplicate(),
		"wave_dps": (stats["wave_dps"] as Array).duplicate(),
		"luck": luck,
		"damage_test_done": damage_test_done,
		"damage_test_damage": roundf(float(stats.get("damage_test_damage", 0.0))),
		"damage_test_dps": roundf(float(stats.get("damage_test_dps", 0.0))),
		"checksum": checksum(),
		"tick": tick,
	}
