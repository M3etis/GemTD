extends TestCase
## Перенос башни (за растущую цену: на стену и на башню — обмен местами, на пустую клетку — переезд
## с пересчётом пути) и огранка (куда тратить золото в поздней игре: +урон, цена растёт геометрически).


func _ready_sim() -> GameSim:
	var sim: GameSim = new_sim(7)
	sim.phase = GameSim.Phase.READY
	sim.gold = 100000
	return sim


func test_move_cost_grows() -> void:
	var sim: GameSim = _ready_sim()
	var cfg: Dictionary = sim.data.economy["tower_move"]
	var t: TowerState = add_tower(sim, 0, "ruby", 2)
	assert_eq(BuildCommands.tower_move_cost(sim), int(cfg["base"]))
	var to: Vector2i = Vector2i(20, 16)
	assert_true(sim.apply({"type": "move_tower", "x": t.cell.x, "y": t.cell.y, "to_x": to.x, "to_y": to.y})["ok"])
	assert_eq(sim.gold, 100000 - int(cfg["base"]))
	assert_eq(BuildCommands.tower_move_cost(sim), int(cfg["base"]) + int(cfg["step"]), "следующий перенос дороже")
	assert_true(sim.apply({"type": "move_tower", "x": to.x, "y": to.y, "to_x": 21, "to_y": 16})["ok"])
	assert_eq(sim.tower_moves, 2)
	assert_eq(sim.gold, 100000 - 2 * int(cfg["base"]) - int(cfg["step"]))


func test_move_onto_wall_swaps_and_keeps_maze() -> void:
	var sim: GameSim = _ready_sim()
	var t: TowerState = add_tower(sim, 0, "ruby", 2)
	var from: Vector2i = t.cell
	var wall: Vector2i = Vector2i(20, 16)
	sim.grid.set_cell(wall, BoardGrid.Cell.ROCK)
	sim.rocks.append(wall)
	sim.route.recompute()
	var length: float = sim.route.ground_length
	var cells_hash: int = sim.grid.cells_hash()
	assert_true(sim.apply({"type": "move_tower", "x": from.x, "y": from.y, "to_x": wall.x, "to_y": wall.y})["ok"])
	assert_eq(t.cell, wall)
	assert_eq(t.pos, BoardGrid.center(wall))
	assert_eq(sim.tower_by_cell.get(wall), t)
	assert_false(sim.tower_by_cell.has(from))
	assert_eq(sim.grid.get_cell(from), BoardGrid.Cell.ROCK, "стена встала на место башни")
	assert_eq(sim.grid.get_cell(wall), BoardGrid.Cell.GEM)
	assert_true(sim.rocks.has(from) and not sim.rocks.has(wall))
	assert_near(sim.route.ground_length, length, 0.0001, "лабиринт тот же")
	assert_ne(sim.grid.cells_hash(), cells_hash)


func test_move_onto_tower_swaps_both() -> void:
	var sim: GameSim = _ready_sim()
	var a: TowerState = add_tower(sim, 0, "ruby", 2)
	var b: TowerState = add_tower(sim, 1, "sapphire", 3)
	var ca: Vector2i = a.cell
	var cb: Vector2i = b.cell
	assert_true(sim.apply({"type": "move_tower", "x": ca.x, "y": ca.y, "to_x": cb.x, "to_y": cb.y})["ok"])
	assert_eq(a.cell, cb)
	assert_eq(b.cell, ca)
	assert_eq(sim.tower_by_cell[ca], b)
	assert_eq(sim.tower_by_cell[cb], a)


func test_move_to_empty_recomputes_path_and_rejects_blocking() -> void:
	var sim: GameSim = _ready_sim()
	var t: TowerState = add_tower(sim, 0, "ruby", 2)
	var path_cell: Vector2i = sim.route.ground_cells[sim.route.ground_cells.size() / 2]
	assert_eq(BuildCommands.can_move_tower(sim, t.cell, sim.grid.route_points[1]), "ERR_NO_BUILD_ZONE")
	var to: Vector2i = Vector2i(20, 16)
	var from: Vector2i = t.cell
	var res: Dictionary = sim.apply({"type": "move_tower", "x": from.x, "y": from.y, "to_x": to.x, "to_y": to.y})
	assert_true(res["ok"], String(res["reason"]))
	assert_eq(sim.grid.get_cell(from), BoardGrid.Cell.EMPTY, "старая клетка освободилась")
	assert_eq(sim.grid.get_cell(to), BoardGrid.Cell.GEM)
	# Стена-столбец между C1 и C2 с одной щелью: башня в щели перекрыла бы путь — перенос отклоняется.
	var sim2: GameSim = _ready_sim()
	var t2: TowerState = add_tower(sim2, 0, "ruby", 2)
	var gap: Vector2i = Vector2i(11, 12)
	for y: int in sim2.grid.height:
		var c: Vector2i = Vector2i(gap.x, y)
		if c != gap:
			sim2.grid.set_cell(c, BoardGrid.Cell.ROCK)
	assert_true(sim2.route.recompute(), "щель оставлена")
	assert_eq(BuildCommands.can_move_tower(sim2, t2.cell, gap), "ERR_BLOCKS_PATH")
	assert_true(BuildCommands.can_move_tower(sim2, t2.cell, Vector2i(20, 16)).is_empty())
	assert_true(path_cell.x >= 0)


func test_move_only_in_build_phase_and_needs_gold() -> void:
	var sim: GameSim = _ready_sim()
	var t: TowerState = add_tower(sim, 0, "ruby", 2)
	sim.gold = BuildCommands.tower_move_cost(sim) - 1
	assert_eq(BuildCommands.can_move_tower(sim, t.cell, Vector2i(20, 16)), "ERR_NOT_ENOUGH_GOLD")
	sim.gold = 1000
	sim.phase = GameSim.Phase.COMBAT
	assert_eq(BuildCommands.can_move_tower(sim, t.cell, Vector2i(20, 16)), "ERR_NOT_BUILD_PHASE")
	sim.phase = GameSim.Phase.READY
	assert_eq(BuildCommands.can_move_tower(sim, t.cell, t.cell), "ERR_MOVE_TARGET")
	assert_eq(BuildCommands.can_move_tower(sim, Vector2i(20, 16), Vector2i(21, 16)), "ERR_NOT_TOWER")


func test_slate_stays_when_tower_moves() -> void:
	var sim: GameSim = _ready_sim()
	var t: TowerState = add_tower(sim, 0, "ruby", 2)
	var s: TowerState = sim.add_slate(t.cell, "area")
	var from: Vector2i = t.cell
	assert_true(sim.apply({"type": "move_tower", "x": from.x, "y": from.y, "to_x": 20, "to_y": 16})["ok"])
	assert_eq(s.cell, from, "слейт лежит на месте")
	assert_true(sim.slate_by_cell.has(from))


func test_polish_cost_growth_damage_and_cap() -> void:
	var sim: GameSim = _ready_sim()
	var cfg: Dictionary = sim.data.economy["polish"]
	var t: TowerState = add_tower(sim, 0, "ruby", 3)
	var base_mult: float = t.damage_mult()
	var spent: int = 0
	var last_cost: int = 0
	for i: int in int(cfg["max_level"]):
		var cost: int = BuildCommands.polish_cost(sim, t)
		assert_eq(cost, int(roundf(float(cfg["base_cost"]) * pow(float(cfg["growth"]), float(i)))))
		assert_true(cost > last_cost, "каждый уровень дороже")
		last_cost = cost
		assert_true(sim.apply({"type": "polish", "x": t.cell.x, "y": t.cell.y})["ok"])
		spent += cost
	assert_eq(t.polish, int(cfg["max_level"]))
	assert_near(t.damage_mult() - base_mult, float(cfg["max_level"]) * float(cfg["damage_per_level"]), 0.0001)
	assert_eq(BuildCommands.polish_cost(sim, t), -1)
	assert_eq(String(sim.apply({"type": "polish", "x": t.cell.x, "y": t.cell.y})["reason"]), "ERR_POLISH_MAX")
	assert_eq(sim.gold, 100000 - spent)
	assert_eq(t.invested_gold, spent, "огранка — вложенное золото")
	assert_eq(t.sell_value(sim.data), int(floorf(float(sim.data.gem_value(3) + spent) * float(sim.data.economy["sell_refund"]))))
	# Полная огранка одной башни стоит тысячи — лишнее золото конца игры, а не ранний рывок.
	assert_true(spent > 4000, "полная огранка: %d золота" % spent)


func test_polish_rules() -> void:
	var sim: GameSim = _ready_sim()
	var t: TowerState = add_tower(sim, 0, "ruby", 3)
	sim.gold = BuildCommands.polish_cost(sim, t) - 1
	assert_eq(String(sim.apply({"type": "polish", "x": t.cell.x, "y": t.cell.y})["reason"]), "ERR_NOT_ENOUGH_GOLD")
	sim.gold = 1000
	sim.phase = GameSim.Phase.COMBAT
	assert_eq(String(sim.apply({"type": "polish", "x": t.cell.x, "y": t.cell.y})["reason"]), "ERR_NOT_BUILD_PHASE")
	sim.phase = GameSim.Phase.READY
	var before: int = sim.checksum()
	assert_true(sim.apply({"type": "polish", "x": t.cell.x, "y": t.cell.y})["ok"])
	assert_ne(sim.checksum(), before, "огранка входит в контрольную сумму")


func test_move_and_polish_replay() -> void:
	var sim: GameSim = new_sim(321, {"max_waves": 3, "record_events": false})
	var bot: BotPlayer = BotPlayer.new(sim, "maze", sim.seed_value)
	while sim.round_index < 3 and not sim.is_over():
		if sim.phase == GameSim.Phase.COMBAT:
			sim.step()
		else:
			bot.act()
	bot.auto_start_wave = false
	bot.play_build_phase()
	assert_eq(sim.phase, GameSim.Phase.READY)
	var t: TowerState = sim.towers[0]
	sim.apply({"type": "receive_gold", "from": 2, "amount": 500})
	assert_true(sim.apply({"type": "polish", "x": t.cell.x, "y": t.cell.y})["ok"])
	var wall: Vector2i = sim.rocks[0]
	assert_true(sim.apply({"type": "move_tower", "x": t.cell.x, "y": t.cell.y, "to_x": wall.x, "to_y": wall.y})["ok"])
	bot.auto_start_wave = true
	bot.run_to_end()
	var rep: Dictionary = Replay.simulate(sim.data, Replay.from_sim(sim, "test"))
	assert_true(bool(rep["ok"]), String(rep.get("reason", "")))


## Слейт под башней продаётся своей командой sell_slate; «sell» в такой клетке продаёт башню, а не слейт.
func test_sell_slate_under_tower() -> void:
	var sim: GameSim = _ready_sim()
	var t: TowerState = add_tower(sim, 0, "ruby", 2)
	var s: TowerState = sim.add_slate(t.cell, "area")
	var gold: int = sim.gold
	assert_true(sim.apply({"type": "sell_slate", "x": t.cell.x, "y": t.cell.y})["ok"])
	assert_eq(sim.gold, gold + s.sell_value(sim.data))
	assert_true(sim.tower_by_cell.has(t.cell), "башня осталась")
	assert_false(sim.slate_by_cell.has(t.cell))
	sim.add_slate(t.cell, "area")
	assert_true(sim.apply({"type": "sell", "x": t.cell.x, "y": t.cell.y})["ok"])
	assert_true(sim.slate_by_cell.has(t.cell), "sell продал башню, слейт лежит под стеной")
	assert_eq(sim.grid.get_cell(t.cell), BoardGrid.Cell.ROCK)
	assert_eq(String(sim.apply({"type": "sell_slate", "x": 0, "y": 0})["reason"]), "ERR_NOT_SLATE")
	assert_true(NetProtocol.valid_command({"type": "sell_slate", "x": 1, "y": 2, "tick": 0}))


## Башни поддержки без урона огранить нельзя: огранке нечего усиливать.
func test_polish_only_for_damage_towers() -> void:
	var sim: GameSim = _ready_sim()
	for sp: String in ["beacon_lens", "warbanner_crystal", "frostwell"]:
		var t: TowerState = sim.add_special_tower(SAFE_CELLS[2], sp)
		assert_false(t.deals_damage(), sp)
		assert_eq(BuildCommands.polish_cost(sim, t), -1, sp)
		assert_eq(String(sim.apply({"type": "polish", "x": t.cell.x, "y": t.cell.y})["reason"]), "ERR_POLISH_NO_DAMAGE", sp)
		sim.remove_tower(t)
	var c: TowerState = sim.add_special_tower(SAFE_CELLS[3], "cinder_crown")
	assert_true(c.deals_damage(), "аура урона огранку получает")
	assert_true(BuildCommands.polish_cost(sim, c) > 0)


## Сплав из огранённых башен: вложенное золото и уровень огранки переходят в спец-башню.
func test_forge_keeps_polish_of_components() -> void:
	var sim: GameSim = _ready_sim()
	var ruby: TowerState = add_tower(sim, 0, "ruby", 1)
	var topaz: TowerState = add_tower(sim, 1, "topaz", 1)
	var emerald: TowerState = add_tower(sim, 2, "emerald", 1)
	var spent: int = 0
	for i: int in 3:
		spent += BuildCommands.polish_cost(sim, ruby)
		assert_true(sim.apply({"type": "polish", "x": ruby.cell.x, "y": ruby.cell.y})["ok"])
	spent += BuildCommands.polish_cost(sim, topaz)
	assert_true(sim.apply({"type": "polish", "x": topaz.cell.x, "y": topaz.cell.y})["ok"])
	var at: Vector2i = emerald.cell
	assert_true(sim.apply({"type": "forge", "x": at.x, "y": at.y, "special": "cinder_crown"})["ok"])
	var crown: TowerState = sim.tower_by_cell[at]
	assert_eq(crown.special_id, "cinder_crown")
	assert_eq(crown.polish, 3, "больший уровень огранки компонентов")
	assert_eq(crown.invested_gold, spent, "золото огранки не пропало")
