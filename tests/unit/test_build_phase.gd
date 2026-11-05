extends TestCase


func _place_first_valid(sim: GameSim, skip: int = 0) -> Vector2i:
	var n: int = 0
	for y: int in range(6, sim.grid.height):
		for x: int in range(9, sim.grid.width):
			var c: Vector2i = Vector2i(x, y)
			if sim.preview_place(c)["ok"]:
				if n >= skip:
					assert_true(sim.apply({"type": "place", "x": x, "y": y})["ok"])
					return c
				n += 1
	return Vector2i(-1, -1)


func test_five_rocks_then_choosing() -> void:
	var sim: GameSim = new_sim()
	for i: int in 5:
		assert_eq(sim.phase, GameSim.Phase.PLACING)
		_place_first_valid(sim)
	assert_eq(sim.phase, GameSim.Phase.CHOOSING)
	assert_eq(sim.candidates.size(), 5)
	var res: Dictionary = sim.apply({"type": "place", "x": 20, "y": 8})
	assert_false(res["ok"], "шестой камень не должен ставиться")


func test_reveal_depends_on_seed_not_position() -> void:
	var a: GameSim = new_sim(1234)
	var b: GameSim = new_sim(1234)
	_place_first_valid(a, 0)
	_place_first_valid(b, 7)
	assert_eq(a.candidates[0]["gem"], b.candidates[0]["gem"])
	assert_eq(a.candidates[0]["quality"], b.candidates[0]["quality"])
	var c: GameSim = new_sim(4321)
	var differs: bool = false
	for slot: int in 5:
		if a.roll_gem(1, slot, 1)["gem"] != c.roll_gem(1, slot, 1)["gem"]:
			differs = true
	assert_true(differs, "разные seed должны давать разные камни")


func test_luck_one_gives_only_first_quality() -> void:
	var sim: GameSim = new_sim(55)
	for r: int in range(1, 30):
		for slot: int in 5:
			assert_eq(int(sim.roll_gem(r, slot, 1)["quality"]), 1)


func test_keep_creates_tower_and_walls() -> void:
	var sim: GameSim = new_sim()
	var cells: Array[Vector2i] = []
	for i: int in 5:
		cells.append(_place_first_valid(sim))
	var keep: Vector2i = cells[2]
	assert_false(sim.apply({"type": "keep", "x": 0, "y": 0})["ok"], "keep не по кандидату")
	assert_true(sim.apply({"type": "keep", "x": keep.x, "y": keep.y})["ok"])
	assert_eq(sim.phase, GameSim.Phase.READY)
	assert_eq(sim.towers.size(), 1)
	assert_eq(sim.towers[0].cell, keep)
	assert_eq(sim.rocks.size(), 4)
	assert_eq(sim.grid.get_cell(keep), BoardGrid.Cell.GEM)
	for c: Vector2i in cells:
		if c != keep:
			assert_eq(sim.grid.get_cell(c), BoardGrid.Cell.ROCK)


func test_upgrade_luck_costs_gold() -> void:
	var sim: GameSim = new_sim()
	assert_false(sim.apply({"type": "upgrade_luck"})["ok"], "без золота нельзя")
	sim.gold = 100000
	var cost: int = sim.data.luck_cost(1)
	assert_true(sim.apply({"type": "upgrade_luck"})["ok"])
	assert_eq(sim.luck, 2)
	assert_eq(sim.gold, 100000 - cost)
	for i: int in 20:
		sim.apply({"type": "upgrade_luck"})
	assert_eq(sim.luck, sim.data.max_luck())


func test_downgrade_keeps_gem_one_quality_lower() -> void:
	var sim: GameSim = new_sim()
	var cells: Array[Vector2i] = place_round(sim, [["ruby", 3], ["topaz", 1], ["emerald", 1], ["opal", 1], ["diamond", 1]])
	assert_eq(sim.can_downgrade(cells[1]), "ERR_DOWNGRADE_MIN", "первое качество не понижается")
	assert_false(sim.apply({"type": "downgrade", "x": cells[1].x, "y": cells[1].y})["ok"])
	assert_true(sim.apply({"type": "downgrade", "x": cells[0].x, "y": cells[0].y})["ok"])
	assert_eq(sim.phase, GameSim.Phase.READY)
	assert_eq(sim.towers.size(), 1)
	assert_eq(sim.towers[0].gem_id, "ruby")
	assert_eq(sim.towers[0].quality, 2)
	assert_eq(sim.rocks.size(), 4, "остальные кандидаты — стены")
	assert_eq(sim.can_downgrade(cells[0]), "ERR_NOT_CHOOSING")
	var kept: Array = sim.drain_events().filter(func(e: Dictionary) -> bool: return String(e["type"]) == "gem_kept")
	assert_eq(kept.size(), 1)
	assert_true(bool(kept[0].get("downgraded", false)))
	assert_eq(int(kept[0]["from_quality"]), 3)
