class_name TestCase
extends RefCounted
## Базовый класс тестов для собственного раннера (tests/run_all.gd).

var failures: PackedStringArray = PackedStringArray()
var current_test: String = ""


func fail(msg: String) -> void:
	failures.append("%s: %s" % [current_test, msg])


func assert_true(cond: bool, msg: String = "ожидалось true") -> void:
	if not cond:
		fail(msg)


func assert_false(cond: bool, msg: String = "ожидалось false") -> void:
	if cond:
		fail(msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if typeof(actual) != typeof(expected) and not ((actual is int or actual is float) and (expected is int or expected is float)):
		fail("%s ожидалось %s (%s), получено %s (%s)" % [msg, str(expected), type_string(typeof(expected)), str(actual), type_string(typeof(actual))])
	elif actual != expected:
		fail("%s ожидалось %s, получено %s" % [msg, str(expected), str(actual)])


func assert_ne(actual: Variant, expected: Variant, msg: String = "") -> void:
	if actual == expected:
		fail("%s значения не должны совпадать: %s" % [msg, str(actual)])


func assert_near(actual: float, expected: float, eps: float = 0.0001, msg: String = "") -> void:
	if absf(actual - expected) > eps:
		fail("%s ожидалось %f ± %f, получено %f" % [msg, expected, eps, actual])


func data() -> GameData:
	return GameData.load_default()


func new_sim(seed_value: int = 42, extra: Dictionary = {}) -> GameSim:
	var cfg: Dictionary = {"seed": seed_value, "difficulty": "normal", "record_events": true}
	cfg.merge(extra, true)
	var sim: GameSim = GameSim.new(data(), cfg)
	sim.start()
	return sim


## Ставит камни в свободные клетки и подменяет выпавшие гемы на заданные [[gem, quality], ...].
func place_round(sim: GameSim, specs: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(6, sim.grid.height):
		for x: int in range(9, 24):
			if cells.size() >= specs.size():
				break
			var c: Vector2i = Vector2i(x, y)
			if sim.preview_place(c)["ok"] and sim.apply({"type": "place", "x": x, "y": y})["ok"]:
				cells.append(c)
	for i: int in specs.size():
		sim.candidates[i]["gem"] = String(specs[i][0])
		sim.candidates[i]["quality"] = int(specs[i][1])
	return cells


## Башня-гем в «тихом» углу поля, не мешающем маршруту.
const SAFE_CELLS: Array[Vector2i] = [Vector2i(30, 22), Vector2i(31, 22), Vector2i(30, 21), Vector2i(31, 21), Vector2i(29, 22), Vector2i(31, 20)]


func add_tower(sim: GameSim, index: int, gem: String, quality: int) -> TowerState:
	var t: TowerState = sim.add_gem_tower(SAFE_CELLS[index], gem, quality)
	sim.route.recompute()
	return t
