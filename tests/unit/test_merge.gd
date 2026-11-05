extends TestCase
## Слияние двух одинаковых спец-башен (урон и сила эффектов = свои + economy.special_merge.inherit × второй)
## и подсказки трекера: отметка «собран», замена рецептов, чьих камней нет на поле.


func _special(sim: GameSim, index: int, id: String, level: int = 1) -> TowerState:
	var t: TowerState = sim.add_special_tower(SAFE_CELLS[index], id)
	t.level = level
	t.refresh_stats(sim.data)
	sim.route.recompute()
	sim.combat.recompute_auras(sim)
	return t


func _merge(sim: GameSim, a: TowerState, b: TowerState) -> Dictionary:
	return sim.apply({"type": "merge_special", "x": a.cell.x, "y": a.cell.y, "with_x": b.cell.x, "with_y": b.cell.y})


func test_merge_two_identical_specials() -> void:
	var sim: GameSim = new_sim()
	var a: TowerState = _special(sim, 0, "rust_obelisk", 1)
	var b: TowerState = _special(sim, 1, "rust_obelisk", 2)
	b.invested_gold = 40
	b.total_damage = 500.0
	b.kills = 7
	var k: float = BuildCommands.merge_inherit(sim.data)
	var before: int = sim.checksum()
	assert_eq(BuildCommands.merge_partner(sim, a), b)
	var res: Dictionary = _merge(sim, a, b)
	assert_true(res["ok"], String(res["reason"]))
	assert_true(a.is_merged())
	assert_eq(a.level, 2, "свой уровень — больший из двух")
	assert_eq(a.merge_level, 1, "унаследован меньший")
	assert_eq(sim.towers.size(), 1)
	assert_false(sim.tower_by_cell.has(b.cell))
	assert_eq(sim.grid.get_cell(b.cell), BoardGrid.Cell.ROCK, "вторая башня стала стеной, лабиринт не изменился")
	assert_near(a.effective_damage(), 55.0 + k * 30.0, 0.0001, "L2 + 0.75 × L1 = 77.5")
	assert_eq(a.base_value(sim.data), int(sim.data.special("rust_obelisk")["value"]) * 2 + 40, "продажа вернёт обе башни")
	assert_near(a.total_damage, 500.0)
	assert_eq(a.kills, 7)
	assert_ne(sim.checksum(), before)
	assert_eq(String((sim.command_log.back() as Dictionary)["type"]), "merge_special", "команда пишется в реплей")
	var merged_events: int = 0
	for e: Dictionary in sim.drain_events():
		if String(e["type"]) == "special_merged":
			merged_events += 1
	assert_eq(merged_events, 1)


func test_merge_rules() -> void:
	var sim: GameSim = new_sim()
	var a: TowerState = _special(sim, 0, "cinder_crown")
	var b: TowerState = _special(sim, 1, "cinder_crown")
	var c: TowerState = _special(sim, 2, "beacon_lens")
	var d: TowerState = _special(sim, 3, "cinder_crown")
	assert_eq(String(_merge(sim, a, c)["reason"]), "ERR_MERGE_DIFFERENT")
	assert_eq(String(_merge(sim, a, a)["reason"]), "ERR_MERGE_DIFFERENT")
	assert_eq(BuildCommands.merge_partner(sim, c), null, "второй такой башни нет")
	sim.phase = GameSim.Phase.COMBAT
	assert_eq(String(_merge(sim, a, b)["reason"]), "ERR_NOT_BUILD_PHASE")
	sim.phase = GameSim.Phase.READY
	assert_true(_merge(sim, a, b)["ok"])
	assert_eq(BuildCommands.merge_partner(sim, a), null, "слитая башня больше не сливается")
	assert_eq(BuildCommands.merge_partner(sim, d), null, "и не служит парой для третьей")
	assert_eq(String(_merge(sim, a, d)["reason"]), "ERR_MERGE_ALREADY")
	assert_eq(String(_merge(sim, d, a)["reason"]), "ERR_MERGE_ALREADY")


func test_merged_effects_scale() -> void:
	var sim: GameSim = new_sim()
	var k: float = BuildCommands.merge_inherit(sim.data)
	var g: TowerState = add_tower(sim, 2, "ruby", 1)
	var a: TowerState = _special(sim, 0, "warbanner_crystal")
	var b: TowerState = _special(sim, 1, "warbanner_crystal")
	var aura: float = float(sim.data.special_effect("warbanner_crystal", "aura_damage", 1, 0.0))
	assert_near(g.damage_mult(), 1.0 + aura)
	assert_true(_merge(sim, a, b)["ok"])
	assert_near(g.damage_mult(), 1.0 + aura * (1.0 + k), 0.0001, "аура слитого знамени: своя + 0.75 второй")
	var well: TowerState = TowerState.new()
	well.setup_special(sim.data, 999, Vector2i(0, 0), "frostwell", 1)
	assert_near(well.strength(sim.data, "slow"), 0.25, 0.0001, "не слита — своё")
	well.merge_level = 1
	assert_near(well.strength(sim.data, "slow"), 0.25 * (1.0 + k))
	assert_near(well.strength(sim.data, "slow_radius", 3.0), 3.0, 0.0001, "радиус не наследуется")
	well.level = 3
	well.merge_level = 3
	assert_near(well.strength(sim.data, "slow"), float(sim.data.economy["special_merge"]["max_slow"]), 0.0001, "замедление ограничено")
	var idol_sim: GameSim = new_sim()
	var i1: TowerState = _special(idol_sim, 0, "gilded_idol")
	var i2: TowerState = _special(idol_sim, 1, "gilded_idol")
	var gold: int = int(idol_sim.data.special_effect("gilded_idol", "wave_gold", 1, 0))
	assert_eq(SpecialCombat.idol_wave_gold(idol_sim), gold * 2)
	assert_true(_merge(idol_sim, i1, i2)["ok"])
	assert_eq(SpecialCombat.idol_wave_gold(idol_sim), int(roundf(float(gold) * (1.0 + k))))


func test_merge_command_passes_net_validation() -> void:
	assert_true(NetProtocol.valid_command({"type": "merge_special", "x": 1, "y": 2, "with_x": 3, "with_y": 4, "tick": 5}))
	assert_false(NetProtocol.valid_command({"type": "merge_special", "x": 1, "y": 2, "tick": 5}), "нет второй башни")


func test_built_and_replacements() -> void:
	var sim: GameSim = new_sim()
	assert_true(RecipeBook.replacements(sim, ["titanbane"] as Array[String]).is_empty(), "поле пустое — заменять не на что")
	add_tower(sim, 0, "opal", 1)
	add_tower(sim, 1, "amethyst", 1)
	add_tower(sim, 2, "ruby", 1)
	var one: Dictionary = RecipeBook.replacements(sim, ["titanbane"] as Array[String])
	assert_eq(String(one.get("titanbane", "")), "beacon_lens", "больше всего компонентов на поле у Beacon Lens (2 из 3)")
	var two: Dictionary = RecipeBook.replacements(sim, ["titanbane", "frostwell"] as Array[String])
	assert_eq(String(two.get("titanbane", "")), "beacon_lens")
	assert_eq(String(two.get("frostwell", "")), "cinder_crown", "одна замена не предлагается дважды")
	var kept: Dictionary = RecipeBook.replacements(sim, ["titanbane", "beacon_lens"] as Array[String])
	assert_false(kept.has("beacon_lens"), "камни отслеживаемого рецепта на поле есть — замены нет")
	assert_eq(String(kept.get("titanbane", "")), "cinder_crown", "уже отслеживаемый рецепт не предлагается")
	assert_true(RecipeBook.built(sim, "titanbane").is_empty())
	_special(sim, 3, "titanbane")
	assert_eq(RecipeBook.built(sim, "titanbane").size(), 1)
	assert_true(RecipeBook.replacements(sim, ["titanbane"] as Array[String]).is_empty(), "собранный рецепт не заменяется")


func test_merged_tower_keeps_upgrading() -> void:
	var sim: GameSim = new_sim()
	var a: TowerState = _special(sim, 0, "cinder_crown")
	var b: TowerState = _special(sim, 1, "cinder_crown")
	assert_true(_merge(sim, a, b)["ok"])
	var up: Dictionary = BuildCommands.next_upgrade(sim, a)
	assert_eq(int(up["to_level"]), 2, "слитая башня улучшается как обычная")
	sim.gold = int(up["gold"])
	assert_true(sim.apply({"type": "upgrade_special", "x": a.cell.x, "y": a.cell.y})["ok"])
	assert_eq(a.level, 2)
	assert_eq(a.merge_level, 1, "унаследованная часть не растёт")
	var k: float = BuildCommands.merge_inherit(sim.data)
	assert_near(a.strength(sim.data, "burn_dps"), 35.0 + k * 14.0, 0.0001, "горение L2 + 0.75 × L1")
	assert_eq(String(BuildCommands.next_upgrade(sim, a)["gem"]), "ruby", "дальше — L3 гемом, как у обычной")


## L1 и L3 сливаются в L3 + 0.75 × L1 — какую бы из двух ни выбрали в панели.
func test_merge_order_independent() -> void:
	for pick_low: bool in [true, false]:
		var sim: GameSim = new_sim()
		var low: TowerState = _special(sim, 0, "stormspire", 1)
		var high: TowerState = _special(sim, 1, "stormspire", 3)
		var kept: TowerState = low if pick_low else high
		assert_true(_merge(sim, kept, high if pick_low else low)["ok"])
		assert_eq(kept.level, 3)
		assert_eq(kept.merge_level, 1)
		assert_near(kept.damage, 240.0 + BuildCommands.merge_inherit(sim.data) * 90.0)
