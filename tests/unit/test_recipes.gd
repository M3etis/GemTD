extends TestCase


func test_one_hit_forge() -> void:
	var sim: GameSim = new_sim()
	var cells: Array[Vector2i] = place_round(sim, [["ruby", 1], ["topaz", 1], ["emerald", 1], ["diamond", 2], ["opal", 1]])
	var opts: Array[Dictionary] = RecipeBook.available_at(sim, cells[1])
	assert_eq(opts.size(), 1)
	assert_eq(String(opts[0]["special"]), "cinder_crown")
	assert_true(sim.apply({"type": "forge", "x": cells[1].x, "y": cells[1].y, "special": "cinder_crown"})["ok"])
	assert_eq(sim.phase, GameSim.Phase.READY)
	assert_eq(sim.towers.size(), 1)
	assert_eq(sim.towers[0].special_id, "cinder_crown")
	assert_eq(sim.towers[0].level, 1)
	assert_eq(sim.towers[0].cell, cells[1])
	assert_eq(sim.rocks.size(), 4)
	assert_eq(int(sim.stats["specials_forged"]["cinder_crown"]), 1)


func test_forge_from_collection_with_candidate() -> void:
	var sim: GameSim = new_sim()
	var a: TowerState = add_tower(sim, 0, "opal", 1)
	var b: TowerState = add_tower(sim, 1, "amethyst", 1)
	add_tower(sim, 2, "ruby", 3)
	var cells: Array[Vector2i] = place_round(sim, [["aquamarine", 1], ["ruby", 1], ["ruby", 1], ["topaz", 2], ["diamond", 1]])
	assert_true(sim.apply({"type": "forge", "x": cells[0].x, "y": cells[0].y, "special": "beacon_lens"})["ok"])
	assert_eq(sim.towers.size(), 2, "opal и amethyst поглощены, ruby III остался")
	assert_eq(sim.grid.get_cell(a.cell), BoardGrid.Cell.ROCK)
	assert_eq(sim.grid.get_cell(b.cell), BoardGrid.Cell.ROCK)
	assert_false(sim.tower_by_cell.has(a.cell))
	assert_eq((sim.tower_by_cell[cells[0]] as TowerState).special_id, "beacon_lens")


func test_forge_on_board_in_ready_phase() -> void:
	var sim: GameSim = new_sim()
	var cells: Array[Vector2i] = place_round(sim, [["ruby", 1], ["diamond", 1], ["diamond", 1], ["diamond", 1], ["diamond", 1]])
	sim.apply({"type": "keep", "x": cells[0].x, "y": cells[0].y})
	add_tower(sim, 0, "topaz", 1)
	add_tower(sim, 1, "emerald", 1)
	assert_eq(sim.phase, GameSim.Phase.READY)
	assert_eq(RecipeBook.available_at(sim, cells[0]).size(), 1)
	assert_true(sim.apply({"type": "forge", "x": cells[0].x, "y": cells[0].y, "special": "cinder_crown"})["ok"])
	assert_eq(sim.towers.size(), 1)
	assert_eq(sim.towers[0].special_id, "cinder_crown")
	assert_eq(sim.phase, GameSim.Phase.READY, "сплав на поле не меняет фазу")


func test_forge_requires_exact_quality_and_component() -> void:
	var sim: GameSim = new_sim()
	var cells: Array[Vector2i] = place_round(sim, [["ruby", 2], ["topaz", 1], ["emerald", 1], ["diamond", 2], ["opal", 1]])
	assert_true(RecipeBook.available_at(sim, cells[1]).is_empty(), "рубин II не подходит под рубин I")
	assert_false(sim.apply({"type": "forge", "x": cells[1].x, "y": cells[1].y, "special": "cinder_crown"})["ok"])
	assert_false(sim.apply({"type": "forge", "x": cells[3].x, "y": cells[3].y, "special": "cinder_crown"})["ok"], "алмаз — не компонент")
	assert_false(sim.apply({"type": "forge", "x": cells[1].x, "y": cells[1].y, "special": "nope"})["ok"])


func test_multiple_recipes_available() -> void:
	var sim: GameSim = new_sim()
	add_tower(sim, 0, "ruby", 1)
	add_tower(sim, 1, "topaz", 1)
	add_tower(sim, 2, "emerald", 1)
	add_tower(sim, 3, "opal", 1)
	add_tower(sim, 4, "amethyst", 1)
	var cells: Array[Vector2i] = place_round(sim, [["aquamarine", 1], ["ruby", 1], ["diamond", 1], ["diamond", 1], ["diamond", 1]])
	var ids: Array[String] = []
	for o: Dictionary in RecipeBook.available_at(sim, cells[1]):
		ids.append(String(o["special"]))
	assert_true(ids.has("cinder_crown"))
	var ids2: Array[String] = []
	for o: Dictionary in RecipeBook.available_at(sim, cells[0]):
		ids2.append(String(o["special"]))
	assert_true(ids2.has("beacon_lens"))
	var prog: Dictionary = RecipeBook.progress(sim, "skypiercer", false)
	assert_eq(int(prog["have"]), 0)


func test_special_upgrades() -> void:
	var sim: GameSim = new_sim()
	var cells: Array[Vector2i] = place_round(sim, [["ruby", 1], ["topaz", 1], ["emerald", 1], ["diamond", 2], ["opal", 1]])
	sim.apply({"type": "forge", "x": cells[0].x, "y": cells[0].y, "special": "cinder_crown"})
	var t: TowerState = sim.tower_by_cell[cells[0]]
	var cost2: int = int(sim.data.special_upgrade("cinder_crown", 2)["gold"])
	assert_false(sim.apply({"type": "upgrade_special", "x": t.cell.x, "y": t.cell.y})["ok"], "нет золота")
	sim.gold = cost2 + 1000
	assert_true(sim.apply({"type": "upgrade_special", "x": t.cell.x, "y": t.cell.y})["ok"])
	assert_eq(t.level, 2)
	assert_eq(t.invested_gold, cost2)
	assert_false(sim.apply({"type": "upgrade_special", "x": t.cell.x, "y": t.cell.y})["ok"], "L3 требует гем")
	# Следующий раунд: рубин IV среди кандидатов.
	sim.phase = GameSim.Phase.PLACING
	sim.round_index += 1
	var c2: Array[Vector2i] = place_round(sim, [["ruby", 3], ["ruby", 4], ["topaz", 1], ["opal", 1], ["opal", 1]])
	assert_false(sim.apply({"type": "upgrade_special", "x": t.cell.x, "y": t.cell.y, "with_x": c2[0].x, "with_y": c2[0].y})["ok"], "рубин III мал")
	assert_true(sim.apply({"type": "upgrade_special", "x": t.cell.x, "y": t.cell.y, "with_x": c2[1].x, "with_y": c2[1].y})["ok"])
	assert_eq(t.level, 3)
	assert_eq(sim.phase, GameSim.Phase.READY)
	assert_eq(sim.towers.size(), 1, "кандидаты стали стенами, новой башни нет")


## Трекер: компонент среди кандидатов раунда — «на поле», галочку даёт только оставленная башня.
func test_progress_separates_kept_from_candidates() -> void:
	var sim: GameSim = new_sim()
	add_tower(sim, 0, "ruby", 1)
	place_round(sim, [["topaz", 1], ["opal", 1], ["opal", 1], ["diamond", 1], ["sapphire", 1]])
	var prog: Dictionary = RecipeBook.progress(sim, "cinder_crown", true)
	assert_eq(int(prog["have"]), 2)
	assert_eq(int(prog["kept"]), 1)
	var parts: Array = prog["parts"]
	assert_true(bool(parts[0]["owned"]) and not bool(parts[0]["candidate"]), "рубин — башня")
	assert_true(bool(parts[1]["owned"]) and bool(parts[1]["candidate"]), "топаз — пока кандидат")
	assert_false(bool(parts[2]["owned"]), "изумруда нет")
	var without: Dictionary = RecipeBook.progress(sim, "cinder_crown", false)
	assert_eq(int(without["have"]), 1)
	assert_false(bool(without["parts"][1]["owned"]))


## Готовый рецепт из башен на поле (кнопка в панели фазы, F) собирается на последнем поставленном
## компоненте, а не на первом в списке башен.
func test_board_forge_on_last_placed_component() -> void:
	var sim: GameSim = new_sim()
	add_tower(sim, 0, "opal", 1)
	add_tower(sim, 1, "amethyst", 1)
	var last: TowerState = add_tower(sim, 2, "aquamarine", 1)
	var forges: Array[Dictionary] = ChoiceLogic.board_forges(sim)
	assert_eq(forges.size(), 1)
	assert_eq(String(forges[0]["special"]), "beacon_lens")
	assert_eq(forges[0]["cell"], last.cell, "на месте последнего камня")
	assert_true(sim.apply({"type": "forge", "x": last.cell.x, "y": last.cell.y, "special": "beacon_lens"})["ok"])
	assert_eq((sim.tower_by_cell[last.cell] as TowerState).special_id, "beacon_lens")


## Рецепт из башен на поле собирается в любой момент матча, и в бою тоже.
func test_forge_during_combat() -> void:
	var sim: GameSim = new_sim()
	var a: TowerState = add_tower(sim, 0, "opal", 1)
	add_tower(sim, 1, "amethyst", 1)
	var last: TowerState = add_tower(sim, 2, "aquamarine", 1)
	sim.phase = GameSim.Phase.COMBAT
	assert_eq(ChoiceLogic.board_forges(sim).size(), 1, "в бою сплав предлагается")
	assert_true(sim.apply({"type": "forge", "x": last.cell.x, "y": last.cell.y, "special": "beacon_lens"})["ok"])
	assert_eq(sim.phase, GameSim.Phase.COMBAT, "бой продолжается")
	assert_eq(sim.grid.get_cell(a.cell), BoardGrid.Cell.ROCK, "компонент стал стеной")
	sim.phase = GameSim.Phase.DEFEAT
	assert_eq(String(sim.apply({"type": "forge", "x": 0, "y": 0, "special": "beacon_lens"})["reason"]), "ERR_GAME_OVER")
