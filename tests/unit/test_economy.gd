extends TestCase


func test_sell_returns_value_and_leaves_wall() -> void:
	var sim: GameSim = new_sim()
	var cells: Array[Vector2i] = place_round(sim, [["ruby", 3], ["topaz", 1], ["emerald", 1], ["diamond", 2], ["opal", 1]])
	sim.apply({"type": "keep", "x": cells[0].x, "y": cells[0].y})
	var t: TowerState = sim.tower_by_cell[cells[0]]
	var expected: int = int(floorf(float(sim.data.gem_value(3)) * float(sim.data.economy["sell_refund"])))
	var gold: int = sim.gold
	assert_true(sim.apply({"type": "sell", "x": t.cell.x, "y": t.cell.y})["ok"])
	assert_eq(sim.gold, gold + expected)
	assert_eq(sim.grid.get_cell(cells[0]), BoardGrid.Cell.ROCK)
	assert_true(sim.towers.is_empty())
	assert_false(sim.apply({"type": "sell", "x": t.cell.x, "y": t.cell.y})["ok"])


func test_break_wall_cost_grows_and_path_recomputes() -> void:
	var sim: GameSim = new_sim()
	var cells: Array[Vector2i] = place_round(sim, [["ruby", 1], ["topaz", 1], ["emerald", 1], ["diamond", 2], ["opal", 1]])
	sim.apply({"type": "keep", "x": cells[0].x, "y": cells[0].y})
	sim.gold = 1000
	var c0: int = BuildCommands.break_wall_cost(sim)
	assert_false(sim.apply({"type": "break_wall", "x": cells[0].x, "y": cells[0].y})["ok"], "башню ломать нельзя")
	assert_true(sim.apply({"type": "break_wall", "x": cells[1].x, "y": cells[1].y})["ok"])
	assert_eq(sim.gold, 1000 - c0)
	assert_eq(sim.grid.get_cell(cells[1]), BoardGrid.Cell.EMPTY)
	assert_false(sim.rocks.has(cells[1]))
	assert_true(BuildCommands.break_wall_cost(sim) > c0)
	assert_false(sim.apply({"type": "break_wall", "x": cells[1].x, "y": cells[1].y})["ok"], "стены уже нет")


func test_buy_life_cap_and_cost() -> void:
	var sim: GameSim = new_sim()
	sim.gold = 1000
	assert_false(sim.apply({"type": "buy_life"})["ok"], "жизни полные")
	sim.lives -= 3
	var c0: int = BuildCommands.buy_life_cost(sim)
	assert_true(sim.apply({"type": "buy_life"})["ok"])
	assert_eq(sim.lives, sim.max_lives - 2)
	assert_eq(sim.gold, 1000 - c0)
	assert_true(BuildCommands.buy_life_cost(sim) > c0)
	sim.phase = GameSim.Phase.COMBAT
	assert_false(sim.apply({"type": "buy_life"})["ok"], "только в строительстве")


func test_targeting_and_toggle() -> void:
	var sim: GameSim = new_sim()
	var t: TowerState = add_tower(sim, 0, "ruby", 1)
	assert_true(sim.apply({"type": "set_targeting", "x": t.cell.x, "y": t.cell.y, "mode": "strongest"})["ok"])
	assert_eq(t.targeting, "strongest")
	assert_false(sim.apply({"type": "set_targeting", "x": t.cell.x, "y": t.cell.y, "mode": "random"})["ok"])
	assert_true(sim.apply({"type": "toggle_tower", "x": t.cell.x, "y": t.cell.y, "enabled": false})["ok"])
	assert_false(t.enabled)


func test_mvp_awarded_after_wave() -> void:
	var sim: GameSim = new_sim(3)
	var t: TowerState = sim.add_gem_tower(Vector2i(3, 7), "ruby", 4)
	sim.route.recompute()
	sim.phase = GameSim.Phase.READY
	sim.apply({"type": "start_wave"})
	while sim.phase == GameSim.Phase.COMBAT:
		sim.step()
	assert_eq(t.mvp, 1)
	assert_true(t.damage_mult() > 1.0)
