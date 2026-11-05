extends TestCase


func test_path_visits_all_checkpoints_in_order() -> void:
	var sim: GameSim = new_sim()
	var cells: Array[Vector2i] = sim.route.ground_cells
	var last_index: int = -1
	for p: Vector2i in sim.grid.route_points:
		var i: int = cells.find(p, maxi(last_index, 0))
		assert_true(i >= 0 and i >= last_index, "точка %s не по порядку" % str(p))
		last_index = i
	assert_eq(cells[0], sim.grid.route_points[0])
	assert_eq(cells[cells.size() - 1], sim.grid.route_points[sim.grid.route_points.size() - 1])


func test_no_build_zones() -> void:
	var sim: GameSim = new_sim()
	for p: Vector2i in sim.grid.route_points:
		assert_eq(sim.can_place(p), "ERR_NO_BUILD_ZONE")
		var near: Vector2i = p + Vector2i(1, 0)
		if sim.grid.in_bounds(near):
			assert_eq(sim.can_place(near), "ERR_NO_BUILD_ZONE")
	assert_eq(sim.can_place(Vector2i(-1, 5)), "ERR_OUT_OF_BOUNDS")


func test_cannot_block_path() -> void:
	var sim: GameSim = new_sim()
	# Стена поперёк поля по x=11 (между C1 и C2), кроме одной клетки.
	var gap: Vector2i = Vector2i(11, 18)
	var placed: int = 0
	for y: int in sim.grid.height:
		var c: Vector2i = Vector2i(11, y)
		if c == gap or not sim.grid.is_buildable(c):
			continue
		sim.grid.set_cell(c, BoardGrid.Cell.ROCK)
		placed += 1
	assert_true(sim.route.recompute(), "путь через щель должен существовать")
	var pv: Dictionary = sim.preview_place(gap)
	assert_false(pv["ok"])
	assert_eq(pv["reason"], "ERR_BLOCKS_PATH")
	var res: Dictionary = sim.apply({"type": "place", "x": gap.x, "y": gap.y})
	assert_false(res["ok"])
	assert_true(placed > 10)


func test_blocking_path_cell_makes_path_longer() -> void:
	var sim: GameSim = new_sim()
	var before: float = sim.route.ground_length
	var cells: Array[Vector2i] = sim.route.ground_cells
	var target: Vector2i = Vector2i(-1, -1)
	for c: Vector2i in cells:
		if sim.grid.is_buildable(c):
			target = c
			break
	assert_true(target.x >= 0)
	var pv: Dictionary = sim.preview_place(target)
	assert_true(pv["ok"])
	assert_true(float(pv["delta"]) >= 0.0)
	sim.apply({"type": "place", "x": target.x, "y": target.y})
	assert_true(sim.route.ground_length >= before)
	assert_false(sim.route.ground_cells.has(target))


func test_air_path_is_straight_between_points() -> void:
	var sim: GameSim = new_sim()
	assert_eq(sim.route.air_points.size(), sim.grid.route_points.size())
	assert_true(sim.route.air_length <= sim.route.ground_length + 0.001)
