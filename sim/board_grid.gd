class_name BoardGrid
extends RefCounted
## Сетка поля: что стоит в клетке, где строить нельзя, и A*-граф для наземного пути.

enum Cell { EMPTY = 0, ROCK = 1, GEM = 2, CANDIDATE = 3, TERRAIN = 4 }

const DIAGONAL_MODES: Dictionary = {
	"never": AStarGrid2D.DIAGONAL_MODE_NEVER,
	"only_if_no_obstacles": AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES,
	"at_least_one_walkable": AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE,
}

var width: int = 0
var height: int = 0
var cells: PackedByteArray = PackedByteArray()
var no_build: PackedByteArray = PackedByteArray()
## Клетки под слейтами. Слейт лежит на земле отдельным слоем: камень и башня на него ставятся, а второй слейт — нет.
var reserved: PackedByteArray = PackedByteArray()
var route_points: Array[Vector2i] = []
var astar: AStarGrid2D = AStarGrid2D.new()


func setup(map: Dictionary) -> void:
	width = int(map["width"])
	height = int(map["height"])
	cells.resize(width * height)
	cells.fill(Cell.EMPTY)
	no_build.resize(width * height)
	no_build.fill(0)
	reserved.resize(width * height)
	reserved.fill(0)
	route_points.clear()
	route_points.append(_v(map["entrance"]))
	for cp: Variant in map["checkpoints"]:
		route_points.append(_v(cp))
	route_points.append(_v(map["exit"]))
	var r: int = int(map["no_build_radius"])
	for p: Vector2i in route_points:
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				var c: Vector2i = p + Vector2i(dx, dy)
				if in_bounds(c):
					no_build[idx(c)] = 1
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, width, height)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = DIAGONAL_MODES.get(String(map["diagonal_mode"]), AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES)
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for b: Variant in map["blocked"]:
		var c: Vector2i = _v(b)
		if in_bounds(c):
			no_build[idx(c)] = 1
			set_cell(c, Cell.TERRAIN)


static func _v(a: Variant) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


func idx(c: Vector2i) -> int:
	return c.y * width + c.x


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func get_cell(c: Vector2i) -> int:
	if not in_bounds(c):
		return Cell.TERRAIN
	return cells[idx(c)]


func set_cell(c: Vector2i, v: int) -> void:
	cells[idx(c)] = v
	astar.set_point_solid(c, v != Cell.EMPTY)


func is_no_build(c: Vector2i) -> bool:
	return not in_bounds(c) or no_build[idx(c)] != 0


func is_buildable(c: Vector2i) -> bool:
	return in_bounds(c) and no_build[idx(c)] == 0 and cells[idx(c)] == Cell.EMPTY


func set_reserved(c: Vector2i, on: bool) -> void:
	reserved[idx(c)] = 1 if on else 0


func is_reserved(c: Vector2i) -> bool:
	return in_bounds(c) and reserved[idx(c)] != 0


## Пустая проходимая клетка без слейта (в том числе на пути и у порталов).
func is_free_ground(c: Vector2i) -> bool:
	return in_bounds(c) and cells[idx(c)] == Cell.EMPTY and reserved[idx(c)] == 0


## Куда можно положить слейт: любая клетка поля, кроме скал, без другого слейта — пустая, со стеной или башней.
func can_hold_slate(c: Vector2i) -> bool:
	return in_bounds(c) and cells[idx(c)] != Cell.TERRAIN and reserved[idx(c)] == 0


static func center(c: Vector2i) -> Vector2:
	return Vector2(float(c.x) + 0.5, float(c.y) + 0.5)


func cells_hash() -> int:
	return HashUtil.fnv1a_bytes(cells)
