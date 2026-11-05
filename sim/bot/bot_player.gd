class_name BotPlayer
extends RefCounted
## Бот для автопрогонов, тестов и balance_sim. Играет только через команды, как игрок.
## Стратегии (профили ниже) различаются весами гемов и спец-башен, порядком трат и вниманием к воздуху:
## maze — длинный лабиринт и универсальные гемы; specials — охота за рецептами и улучшениями;
## damage — чистый урон, слияния и удача; control — замедление, оглушение, яд и снижение брони;
## antiair — пробивающий урон и защита от воздушных волн; slates — как maze, но делает слейты
## (Gem TD 3.2), кладёт их на путь и объединяет; random — случайная игра (базовая линия).

const STRATEGIES: Array[String] = ["maze", "specials", "damage", "control", "antiair", "slates", "random"]
## Стратегии, которые гоняет balance_sim (random — только как базовая линия). slates — с 2.3: слейты стали частью баланса.
const BALANCE_STRATEGIES: Array[String] = ["maze", "specials", "damage", "control", "antiair", "slates"]
const MAX_CANDIDATES: int = 48
## Сколько волн вперёд бот смотрит на трейты (Покров, иммунитеты) и воздух.
const LOOKAHEAD: int = 3
## Покров бот видит дальше: обнаружение нужно успеть поставить заранее.
const SHROUD_LOOKAHEAD: int = 6
## Сколько атакующих башен нужно на поле, прежде чем сплавлять башню поддержки.
const SUPPORT_MIN_ATTACKERS: int = 7
## Золото, которое бот держит в запасе при покупке жизней (на улучшения спец-башен).
const LIFE_RESERVE: int = 150
const PROFILES: Dictionary = {
	"maze": {"gem_w": {}, "special_w": {}, "affinity": 1.0, "air_w": 0.35, "air_soon_w": 1.2, "luck_first": false,
		"combine_bias": 1.0, "hot_zone": 0.15},
	"specials": {"gem_w": {}, "special_w": {}, "affinity": 2.5, "air_w": 0.35, "air_soon_w": 1.2, "luck_first": false,
		"combine_bias": 0.8, "hot_zone": 0.1},
	"damage": {"gem_w": {"ruby": 1.5, "diamond": 1.5, "topaz": 1.3, "sapphire": 1.1, "aquamarine": 0.6, "opal": 0.7},
		"special_w": {"razor_prism": 1.6, "quake_heart": 1.5, "cinder_crown": 1.4, "warbanner_crystal": 1.4, "titanbane": 1.6},
		"affinity": 0.6, "air_w": 0.3, "air_soon_w": 1.0, "luck_first": true, "combine_bias": 1.3, "hot_zone": 0.2},
	"control": {"gem_w": {"aquamarine": 1.8, "sapphire": 1.4, "emerald": 1.4, "opal": 1.3, "ruby": 0.8},
		"special_w": {"frostwell": 1.8, "gravity_geode": 1.8, "blightbloom": 1.6, "rust_obelisk": 1.6, "stormspire": 1.3},
		"affinity": 1.4, "air_w": 0.35, "air_soon_w": 1.2, "luck_first": false, "combine_bias": 1.0, "hot_zone": 0.15},
	"antiair": {"gem_w": {"amethyst": 2.0, "sapphire": 1.3, "opal": 1.2, "topaz": 0.6, "diamond": 0.7},
		"special_w": {"skypiercer": 2.0, "stormspire": 1.5, "beacon_lens": 1.3},
		"affinity": 1.2, "air_w": 0.9, "air_soon_w": 1.8, "luck_first": false, "combine_bias": 1.0, "hot_zone": 0.1},
	"slates": {"gem_w": {}, "special_w": {}, "affinity": 1.0, "air_w": 0.35, "air_soon_w": 1.2, "luck_first": false,
		"combine_bias": 1.0, "hot_zone": 0.15, "use_slates": true},
	"random": {"gem_w": {}, "special_w": {}, "affinity": 0.0, "air_w": 0.35, "air_soon_w": 1.2, "luck_first": false,
		"combine_bias": 1.0, "hot_zone": 0.0},
}

var sim: GameSim
var strategy: String = "maze"
var profile: Dictionary = {}
var rng: RunRng
## false — бот не запускает волну сам (в «Гонке» волну открывает хост).
var auto_start_wave: bool = true
## Огранка (economy.polish): тратить лишнее золото после максимальной удачи и жизней на огранку
## сильнейшей башни. Выключено по умолчанию — эталонные прогоны и контрольные суммы прежние;
## balance_sim --polish меряет, насколько огранка сдвигает баланс.
var use_polish: bool = false
## Угрозы ближайших волн (кеш на раунд): {round, shroud, immune: {dtype: доля}}.
var _threat: Dictionary = {}
## Раунд, в котором бот уже разложил и объединил слейты (в «Гонке» act() в READY зовётся много раз).
var _slates_round: int = -1


func _init(target: GameSim, strategy_name: String = "maze", bot_seed: int = 0) -> void:
	sim = target
	strategy = strategy_name if STRATEGIES.has(strategy_name) else "maze"
	profile = PROFILES[strategy]
	rng = RunRng.new(HashUtil.combine(bot_seed, HashUtil.fnv1a_str("bot-" + strategy)))


## Один шаг решения бота. true — команда отправлена.
func act() -> bool:
	match sim.phase:
		GameSim.Phase.PLACING:
			_spend_gold()
			var cell: Vector2i = choose_rock_cell()
			if cell.x < 0:
				return false
			return sim.apply({"type": "place", "x": cell.x, "y": cell.y})["ok"]
		GameSim.Phase.CHOOSING:
			return sim.apply(choose_action())["ok"]
		GameSim.Phase.READY:
			_forge_from_board()
			if bool(profile.get("use_slates", false)) and _slates_round != sim.round_index:
				_slates_round = sim.round_index
				_tend_slates()
			_spend_gold()
			if not auto_start_wave:
				return false
			return sim.apply({"type": "start_wave"})["ok"]
	return false


## Порядок трат: улучшение спец-башен до L2, затем удача (у damage — наоборот).
func _spend_gold() -> void:
	if strategy == "random" or bool(profile["luck_first"]):
		_maybe_upgrade_luck()
	if strategy == "random":
		return
	for t: TowerState in sim.towers:
		var up: Dictionary = BuildCommands.next_upgrade(sim, t)
		if not up.is_empty() and String(up["gem"]).is_empty() and sim.gold >= int(up["gold"]):
			sim.apply({"type": "upgrade_special", "x": t.cell.x, "y": t.cell.y})
	_maybe_upgrade_luck()
	_maybe_buy_lives()
	if use_polish:
		_maybe_polish()


## Огранка: только когда удача на максимуме и жизни полные; запас как у покупки жизней.
## Гранит башню с наибольшим уроном за забег (на ней огранка даёт больше всего).
func _maybe_polish() -> void:
	if sim.data.luck_cost(sim.luck) >= 0 or sim.lives < sim.max_lives:
		return
	var guard: int = 0
	while guard < 20:
		guard += 1
		var best: TowerState = null
		for t: TowerState in sim.towers:
			if BuildCommands.polish_cost(sim, t) >= 0 and (best == null or t.total_damage > best.total_damage):
				best = t
		if best == null or sim.gold < BuildCommands.polish_cost(sim, best) + LIFE_RESERVE:
			return
		if not sim.apply({"type": "polish", "x": best.cell.x, "y": best.cell.y})["ok"]:
			return


func _forge_from_board() -> void:
	if strategy == "random":
		return
	var done: bool = true
	while done:
		done = false
		for t: TowerState in sim.towers:
			if t.is_special():
				continue
			var opts: Array[Dictionary] = _worth_forging(RecipeBook.available_at(sim, t.cell))
			if opts.is_empty():
				continue
			var best: String = _best_special(opts)
			if sim.apply({"type": "forge", "x": t.cell.x, "y": t.cell.y, "special": best})["ok"]:
				done = true
				break


func _best_special(opts: Array[Dictionary]) -> String:
	var best: String = String(opts[0]["special"])
	for o: Dictionary in opts:
		if special_score(String(o["special"])) > special_score(best):
			best = String(o["special"])
	return best


## Башни поддержки (без собственного урона) сплавляем, только когда атакующих башен уже достаточно.
func _worth_forging(opts: Array[Dictionary]) -> Array[Dictionary]:
	var attackers: int = 0
	for t: TowerState in sim.towers:
		if t.attack_kind != "none":
			attackers += 1
	var out: Array[Dictionary] = []
	for o: Dictionary in opts:
		if String(sim.data.special(String(o["special"]))["attack"]) == "none" and attackers < SUPPORT_MIN_ATTACKERS:
			continue
		out.append(o)
	return out


## Ценность спец-башни для стратегии: «стоимость» × вес профиля × поправки на угрозы.
func special_score(sp: String) -> float:
	var score: float = float(sim.data.special(sp)["value"]) * float((profile["special_w"] as Dictionary).get(sp, 1.0))
	var th: Dictionary = threat()
	score *= 1.0 - 0.6 * float((th["immune"] as Dictionary).get(String(sim.data.special(sp)["damage_type"]), 0.0))
	if bool(th["shroud"]) and not bool(th["detected"]) and sp == "beacon_lens":
		score *= 3.0
	return score


## Трейты ближайших волн: есть ли Покров, есть ли уже обнаружение, доля волн с иммунитетом к типу урона.
func threat() -> Dictionary:
	if int(_threat.get("round", -1)) == sim.round_index and int(_threat.get("towers", -1)) == sim.towers.size():
		return _threat
	var shroud: bool = false
	var immune: Dictionary = {}
	var waves: int = 0
	for n: int in range(sim.round_index, mini(sim.round_index + SHROUD_LOOKAHEAD, sim.wave_limit()) + 1):
		var summary: Dictionary = WaveSpawner.summary(sim.data, n)
		var near: bool = n <= sim.round_index + LOOKAHEAD
		if near:
			waves += 1
		for t: Variant in summary["traits"]:
			var cfg: Dictionary = sim.data.trait_cfg(String(t))
			if String(t) == "shroud":
				shroud = true
			if not near:
				continue
			for dt: Variant in cfg.get("immune", []):
				immune[String(dt)] = float(immune.get(String(dt), 0.0)) + 1.0
	for k: String in immune.keys():
		immune[k] = float(immune[k]) / float(maxi(waves, 1))
	var detected: bool = not EnemyTraits.detectors(sim).is_empty()
	_threat = {"round": sim.round_index, "towers": sim.towers.size(), "shroud": shroud, "detected": detected, "immune": immune}
	return _threat


## Решение фазы выбора: сплавить спец-башню > улучшить до L3 > объединить > оставить лучший гем.
func choose_action() -> Dictionary:
	if strategy != "random":
		var best_forge: Dictionary = {}
		var best_score: float = -INF
		for cand: Dictionary in sim.candidates:
			var cell: Vector2i = cand["cell"]
			var opts: Array[Dictionary] = _worth_forging(RecipeBook.available_at(sim, cell))
			if opts.is_empty():
				continue
			var sp: String = _best_special(opts)
			var score: float = special_score(sp) * (1.0 + _hot_zone_bonus(cell) * 0.02)
			if score > best_score:
				best_score = score
				best_forge = {"type": "forge", "x": cell.x, "y": cell.y, "special": sp}
		if not best_forge.is_empty():
			return best_forge
		if bool(profile.get("use_slates", false)):
			var slate_cmd: Dictionary = _choose_slate()
			if not slate_cmd.is_empty():
				return slate_cmd
		for t: TowerState in sim.towers:
			var up: Dictionary = BuildCommands.next_upgrade(sim, t)
			if up.is_empty() or String(up["gem"]).is_empty() or sim.gold < int(up["gold"]):
				continue
			for cand2: Dictionary in sim.candidates:
				if BuildCommands.candidate_fits_upgrade(cand2, up):
					var wc: Vector2i = cand2["cell"]
					return {"type": "upgrade_special", "x": t.cell.x, "y": t.cell.y, "with_x": wc.x, "with_y": wc.y}
	var keep: Vector2i = choose_keep()
	var keep_cand: Dictionary = sim.candidate_at(keep)
	var air_soon: bool = sim.data.is_air_wave(sim.round_index) or sim.data.is_air_wave(mini(sim.round_index + 1, sim.wave_limit()))
	var keep_score: float = keep_value(String(keep_cand["gem"]), int(keep_cand["quality"]), keep, air_soon)
	if strategy != "random":
		for count: int in [4, 2]:
			for cand3: Dictionary in sim.candidates:
				var c3: Vector2i = cand3["cell"]
				if not BuildCommands.can_combine(sim, c3, count).is_empty():
					continue
				var q: int = int(cand3["quality"]) + (1 if count == 2 else 2)
				var v: float = keep_value(String(cand3["gem"]), q, c3, air_soon) * float(profile["combine_bias"])
				if v > keep_score:
					return {"type": "combine", "x": c3.x, "y": c3.y, "count": count}
	return {"type": "keep", "x": keep.x, "y": keep.y}


## Играет до конца или до max_waves. Возвращает summary симуляции.
func run_to_end() -> Dictionary:
	var guard: int = 0
	while not sim.is_over() and guard < 10_000_000:
		guard += 1
		if sim.phase == GameSim.Phase.COMBAT:
			sim.step()
		elif not act():
			push_error("BotPlayer: бот не смог сделать ход в фазе %s" % sim.phase_name())
			break
	return sim.summary()


func play_build_phase() -> void:
	var guard: int = 0
	while sim.phase != GameSim.Phase.COMBAT and not sim.is_over() and guard < 64:
		guard += 1
		if not act():
			break


## Покупка жизней до максимума, если после остальных трат осталось золото сверх резерва.
func _maybe_buy_lives() -> void:
	var guard: int = 0
	while sim.lives < sim.max_lives and guard < 40:
		guard += 1
		var cost: int = BuildCommands.buy_life_cost(sim)
		if sim.gold < cost + LIFE_RESERVE or not sim.apply({"type": "buy_life"})["ok"]:
			return


func _maybe_upgrade_luck() -> void:
	var cost: int = sim.data.luck_cost(sim.luck)
	if cost >= 0 and sim.gold >= cost:
		sim.apply({"type": "upgrade_luck"})


func choose_rock_cell() -> Vector2i:
	if strategy == "random":
		return _random_cell()
	var candidates: Array[Vector2i] = _candidate_cells()
	var best: Vector2i = Vector2i(-1, -1)
	var best_score: float = -INF
	for c: Vector2i in candidates:
		var pv: Dictionary = sim.preview_place(c)
		if not pv["ok"]:
			continue
		var score: float = float(pv["delta"]) + _hot_zone_bonus(c) * float(profile["hot_zone"]) + rng.next_float() * 0.01
		if score > best_score:
			best_score = score
			best = c
	if best.x < 0:
		return _random_cell()
	return best


func _candidate_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen: Dictionary = {}
	var path: Array[Vector2i] = sim.route.ground_cells
	for c: Vector2i in path:
		if sim.grid.is_buildable(c) and not seen.has(c):
			seen[c] = true
			out.append(c)
	# Перемешиваем детерминированно и ограничиваем перебор.
	for i: int in range(out.size() - 1, 0, -1):
		var j: int = rng.range_int(0, i)
		var tmp: Vector2i = out[i]
		out[i] = out[j]
		out[j] = tmp
	if out.size() > MAX_CANDIDATES:
		out.resize(MAX_CANDIDATES)
	return out


func _random_cell() -> Vector2i:
	for attempt: int in 400:
		var c: Vector2i = Vector2i(rng.range_int(0, sim.grid.width - 1), rng.range_int(0, sim.grid.height - 1))
		if sim.preview_place(c)["ok"]:
			return c
	for y: int in sim.grid.height:
		for x: int in sim.grid.width:
			var c: Vector2i = Vector2i(x, y)
			if sim.preview_place(c)["ok"]:
				return c
	return Vector2i(-1, -1)


## Сколько точек пути попадает в радиус 3 вокруг клетки (горячие зоны).
func _hot_zone_bonus(c: Vector2i) -> float:
	var center: Vector2 = BoardGrid.center(c)
	var count: int = 0
	for p: Vector2 in sim.route.ground_points:
		if p.distance_squared_to(center) <= 9.0:
			count += 1
	return float(count)


func choose_keep() -> Vector2i:
	var next_wave: int = mini(sim.round_index + 1, sim.wave_limit())
	var air_soon: bool = sim.data.is_air_wave(sim.round_index) or sim.data.is_air_wave(next_wave)
	var best: Vector2i = sim.candidates[0]["cell"]
	var best_score: float = -INF
	for cand: Dictionary in sim.candidates:
		var cell: Vector2i = cand["cell"]
		var score: float = keep_value(cand["gem"], int(cand["quality"]), cell, air_soon)
		if strategy == "random":
			score = rng.next_float()
		if score > best_score:
			best_score = score
			best = cell
	return best


func keep_value(gem: String, quality: int, cell: Vector2i, air_soon: bool) -> float:
	var g: Dictionary = sim.data.gem(gem)
	var attack_range: float = float(g["range"]) + float(sim.data.quality(quality)["range_bonus"])
	var center: Vector2 = BoardGrid.center(cell)
	var r2: float = attack_range * attack_range
	var ground_cov: int = 0
	for p: Vector2 in sim.route.ground_points:
		if p.distance_squared_to(center) <= r2:
			ground_cov += 1
	var air_cov: int = 0
	var steps: int = 64
	for i: int in steps + 1:
		var d: float = sim.route.air_length * float(i) / float(steps)
		if _air_point(d).distance_squared_to(center) <= r2:
			air_cov += 1
	var ground_dps: float = TowerState.estimate_dps(sim.data, gem, quality, false)
	var air_dps: float = TowerState.estimate_dps(sim.data, gem, quality, true)
	var air_weight: float = float(profile["air_soon_w"]) if air_soon else float(profile["air_w"])
	var support: float = 0.0
	if gem == "opal":
		support = float(sim.towers.size()) * 2.0
	var base: float = ground_dps * float(ground_cov) + air_dps * float(air_cov) * air_weight * 2.0 + support
	base *= float((profile["gem_w"] as Dictionary).get(gem, 1.0))
	if strategy != "random":
		var th: Dictionary = threat()
		base *= 1.0 - 0.6 * float((th["immune"] as Dictionary).get(String(g["damage_type"]), 0.0))
		if gem == "opal" and bool(th["shroud"]) and not bool(th["detected"]):
			base = maxf(base, 1.0) * 4.0 + 1000.0
	return base * (1.0 + _recipe_affinity(gem, quality) * float(profile["affinity"]))


## Насколько гем приближает к рецепту, которого ещё нет на поле (0..~0.6).
func _recipe_affinity(gem: String, quality: int) -> float:
	if strategy == "random":
		return 0.0
	var best: float = 0.0
	for sp: String in RecipeBook.recipes_with(sim.data, gem, quality):
		var prog: Dictionary = RecipeBook.progress(sim, sp, false)
		var already: bool = false
		for part: Dictionary in prog["parts"]:
			if String(part["gem"]) == gem and int(part["quality"]) == quality and bool(part["owned"]):
				already = true
		if not already:
			best = maxf(best, 0.2 + 0.2 * float(prog["have"]))
	return best


func _air_point(d: float) -> Vector2:
	var pts: PackedVector2Array = sim.route.air_points
	var cum: PackedFloat64Array = sim.route.air_cum
	for i: int in range(1, pts.size()):
		if cum[i] >= d:
			var seg: float = cum[i] - cum[i - 1]
			var t: float = (d - cum[i - 1]) / seg if seg > 0.0 else 0.0
			return pts[i - 1].lerp(pts[i], t)
	return pts[pts.size() - 1]


# --- Слейты (стратегия slates) ---------------------------------------------------

## Слейт из гемов раунда (если оставить нечего лучше III): составной важнее базового. Плита ложится в клетку, которая меньше всего
## укорачивает путь, когда откроется (остальные кандидаты станут стенами).
func _choose_slate() -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -INF
	# Гем IV–V ценнее базового слейта: тогда бот его оставляет.
	var keep_q: int = int(sim.candidate_at(choose_keep()).get("quality", 1))
	if keep_q >= 4:
		return best
	for cand: Dictionary in sim.candidates:
		var cell: Vector2i = cand["cell"]
		for o: Dictionary in SlateBook.available_at(sim, cell):
			var score: float = (3.0 if String(sim.data.slate(String(o["slate"]))["kind"]) == "combo" else 1.0) * 1000.0 + _length_if_open(cell)
			if score > best_score:
				best_score = score
				best = {"type": "make_slate", "x": cell.x, "y": cell.y, "slate": String(o["slate"])}
	return best


## Длина пути, если клетка станет проходимой (кандидаты пока твёрдые).
func _length_if_open(cell: Vector2i) -> float:
	sim.grid.astar.set_point_solid(cell, false)
	var res: Dictionary = sim.route.compute()
	sim.grid.astar.set_point_solid(cell, true)
	if not res["ok"]:
		return 0.0
	return RoutePlanner.path_length(RoutePlanner.cells_to_points(res["cells"]))


## Готовые слейты: объединить пары в составной, ещё не перенесённые — положить на путь туда,
## где в радиус попадает больше всего клеток маршрута.
func _tend_slates() -> void:
	var combined: bool = true
	while combined:
		combined = false
		for s: TowerState in sim.slates:
			var partner: TowerState = SlateBook.combine_partner(sim, s)
			if partner != null:
				combined = sim.apply({"type": "combine_slates", "x": s.cell.x, "y": s.cell.y, "with_x": partner.cell.x, "with_y": partner.cell.y})["ok"]
				break
	for s2: TowerState in sim.slates:
		# Каждый слейт бот перекладывает один раз: перенос платный, и цена растёт с каждым.
		if s2.moves > 0 or sim.gold < SlateCommands.move_cost(sim):
			continue
		var target: Vector2i = _best_slate_cell(s2)
		if target.x >= 0 and target != s2.cell:
			sim.apply({"type": "move_slate", "x": s2.cell.x, "y": s2.cell.y, "to_x": target.x, "to_y": target.y})


func _best_slate_cell(s: TowerState) -> Vector2i:
	var path: Array[Vector2i] = sim.route.ground_cells
	var best: Vector2i = Vector2i(-1, -1)
	var best_n: int = -1
	var r2: float = s.base_range * s.base_range
	for c: Vector2i in path:
		if not sim.grid.is_free_ground(c):
			continue
		var pc: Vector2 = BoardGrid.center(c)
		var n: int = 0
		for o: Vector2i in path:
			if pc.distance_squared_to(BoardGrid.center(o)) <= r2:
				n += 1
		if n > best_n:
			best_n = n
			best = c
	return best
