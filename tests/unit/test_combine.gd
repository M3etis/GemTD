extends TestCase


func test_combine_two_raises_quality() -> void:
	var sim: GameSim = new_sim()
	var cells: Array[Vector2i] = place_round(sim, [["ruby", 1], ["ruby", 1], ["topaz", 1], ["opal", 2], ["diamond", 1]])
	assert_eq(sim.phase, GameSim.Phase.CHOOSING)
	assert_eq(BuildCommands.can_combine(sim, cells[2], 2), "ERR_COMBINE_NEED_2", "топаз один — нельзя")
	assert_true(sim.apply({"type": "combine", "x": cells[1].x, "y": cells[1].y, "count": 2})["ok"])
	assert_eq(sim.phase, GameSim.Phase.READY)
	assert_eq(sim.towers.size(), 1)
	assert_eq(sim.towers[0].gem_id, "ruby")
	assert_eq(sim.towers[0].quality, 2)
	assert_eq(sim.towers[0].cell, cells[1])
	assert_eq(sim.rocks.size(), 4)


func test_combine_four_adds_two() -> void:
	var sim: GameSim = new_sim()
	var cells: Array[Vector2i] = place_round(sim, [["emerald", 2], ["emerald", 2], ["emerald", 2], ["emerald", 2], ["ruby", 1]])
	assert_true(BuildCommands.can_combine(sim, cells[0], 4).is_empty())
	assert_true(sim.apply({"type": "combine", "x": cells[0].x, "y": cells[0].y, "count": 4})["ok"])
	assert_eq(sim.towers[0].quality, 4)


func test_combine_capped_at_max_quality() -> void:
	var sim: GameSim = new_sim()
	var cells: Array[Vector2i] = place_round(sim, [["diamond", 5], ["diamond", 5], ["ruby", 1], ["ruby", 1], ["opal", 1]])
	assert_eq(BuildCommands.can_combine(sim, cells[0], 2), "ERR_COMBINE_MAX")
	assert_false(sim.apply({"type": "combine", "x": cells[0].x, "y": cells[0].y, "count": 2})["ok"])
	var four: GameSim = new_sim()
	var c4: Array[Vector2i] = place_round(four, [["opal", 4], ["opal", 4], ["opal", 4], ["opal", 4], ["ruby", 1]])
	assert_eq(BuildCommands.can_combine(four, c4[0], 4), "ERR_COMBINE_MAX", "IV + 2 > V")
	assert_true(BuildCommands.can_combine(four, c4[0], 2).is_empty())
