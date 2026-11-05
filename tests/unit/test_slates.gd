extends TestCase
## Слейты (Gem TD 3.2): рецепты из гемов раунда, плита на проходимой клетке (строить на ней можно),
## перенос за растущую цену, объединение в составной, продажа, бой и ауры башням.


func _enemy(sim: GameSim, type: String, at: Vector2) -> EnemyState:
	sim.combat.sim = sim
	var e: EnemyState = sim.combat.spawn_enemy(type, 1.0, [], false, 5.0)
	sim.combat._flush_pending()
	e.pos = at
	return e


## Шаг боя слейтов с заданными врагами в пространственном индексе.
func _pulse(sim: GameSim, enemies: Array[EnemyState], now: float, dt: float = 0.1) -> void:
	sim.combat.sim = sim
	sim.combat.spatial.clear()
	for e: EnemyState in enemies:
		if e.alive:
			sim.combat.spatial.insert(e)
	SlateCombat.step(sim.combat, dt, now)


func test_twelve_slates_from_gem_td() -> void:
	var d: GameData = data()
	assert_eq(d.slates.size(), 12)
	var base: int = 0
	for sl: Dictionary in d.slates:
		base += 1 if String(sl["kind"]) == "base" else 0
	assert_eq(base, 8, "8 базовых и 4 составных")
	assert_eq(SlateBook.combo_of(d, "airborne", "lingering"), "ancient", "порядок неважен")
	assert_eq(SlateBook.combo_of(d, "spell", "slow"), "")


func test_make_base_slate_from_round_gems() -> void:
	var sim: GameSim = new_sim()
	var cells: Array[Vector2i] = place_round(sim, [["emerald", 3], ["topaz", 2], ["ruby", 1], ["diamond", 1], ["opal", 1]])
	var at_main: Array[Dictionary] = SlateBook.available_at(sim, cells[0])
	assert_eq(at_main.size(), 1)
	assert_eq(String(at_main[0]["slate"]), "poison_vine")
	assert_eq(String(SlateBook.available_at(sim, cells[1])[0]["slate"]), "poison_vine", "и из гема-пары")
	assert_true(SlateBook.available_at(sim, cells[2]).is_empty())
	var res: Dictionary = sim.apply({"type": "make_slate", "x": cells[1].x, "y": cells[1].y, "slate": "poison_vine"})
	assert_true(res["ok"], String(res["reason"]))
	assert_eq(sim.phase, GameSim.Phase.READY)
	assert_eq(sim.grid.get_cell(cells[1]), BoardGrid.Cell.EMPTY, "плита на земле — клетка проходима")
	assert_eq((sim.slate_by_cell[cells[1]] as TowerState).slate_id, "poison_vine")
	for i: int in [0, 2, 3, 4]:
		assert_eq(sim.grid.get_cell(cells[i]), BoardGrid.Cell.ROCK, "остальные кандидаты — стены")
	assert_true(sim.towers.is_empty(), "слейт — не башня")
	assert_eq(String((sim.command_log.back() as Dictionary)["type"]), "make_slate")
	sim.phase = GameSim.Phase.PLACING
	assert_eq(sim.can_place(cells[1]), "", "слейт не мешает поставить камень в свою клетку")


func test_combo_slate_from_four_round_gems() -> void:
	var sim: GameSim = new_sim()
	var cells: Array[Vector2i] = place_round(sim, [["topaz", 3], ["amethyst", 2], ["amethyst", 3], ["ruby", 2], ["diamond", 1]])
	var offers: Array[Dictionary] = SlateBook.available_at(sim, cells[3])
	assert_eq(String(offers[0]["slate"]), "ancient", "составной первым")
	assert_eq((offers[0]["cells"] as Array).size(), 4)
	assert_true(sim.apply({"type": "make_slate", "x": cells[0].x, "y": cells[0].y, "slate": "ancient"})["ok"])
	assert_eq((sim.slate_by_cell[cells[0]] as TowerState).slate_id, "ancient")


func test_move_any_times_combine_and_sell() -> void:
	var sim: GameSim = new_sim()
	sim.phase = GameSim.Phase.READY
	sim.gold = 1000
	var a: TowerState = sim.add_slate(Vector2i(10, 10), "lingering")
	var b: TowerState = sim.add_slate(Vector2i(12, 10), "airborne")
	b.kills = 4
	assert_eq(String(sim.apply({"type": "move_slate", "x": 10, "y": 10, "to_x": 12, "to_y": 10})["reason"]), "ERR_SLATE_TARGET", "занято слейтом")
	var cfg: Dictionary = sim.data.economy["slate_move"]
	assert_eq(SlateCommands.move_cost(sim), int(cfg["base"]))
	assert_true(sim.apply({"type": "move_slate", "x": 10, "y": 10, "to_x": 11, "to_y": 11})["ok"])
	assert_eq(a.cell, Vector2i(11, 11))
	assert_eq(a.pos, BoardGrid.center(Vector2i(11, 11)))
	assert_eq(sim.gold, 1000 - int(cfg["base"]))
	assert_eq(SlateCommands.move_cost(sim), int(cfg["base"]) + int(cfg["step"]), "следующий перенос дороже")
	assert_true(sim.apply({"type": "move_slate", "x": 11, "y": 11, "to_x": 13, "to_y": 13})["ok"], "перекладывать можно снова")
	assert_eq(sim.gold, 1000 - 2 * int(cfg["base"]) - int(cfg["step"]))
	assert_true(sim.apply({"type": "move_slate", "x": 13, "y": 13, "to_x": 11, "to_y": 11})["ok"])
	assert_eq(a.moves, 3)
	assert_eq(sim.slate_moves, 3)
	assert_true(sim.apply({"type": "combine_slates", "x": 11, "y": 11, "with_x": 12, "with_y": 10})["ok"])
	var c: TowerState = sim.slate_by_cell[Vector2i(11, 11)]
	assert_eq(c.slate_id, "ancient")
	assert_eq(c.kills, 4, "убийства суммируются")
	assert_false(sim.slate_by_cell.has(Vector2i(12, 10)))
	var gold: int = sim.gold
	assert_true(sim.apply({"type": "sell", "x": 11, "y": 11})["ok"])
	assert_true(sim.slates.is_empty())
	assert_gt_or_eq(sim.gold, gold + 1)
	sim.phase = GameSim.Phase.COMBAT
	sim.add_slate(Vector2i(10, 10), "area")
	assert_eq(String(sim.apply({"type": "move_slate", "x": 10, "y": 10, "to_x": 11, "to_y": 11})["reason"]), "ERR_NOT_BUILD_PHASE")


func test_slate_move_needs_gold() -> void:
	var sim: GameSim = new_sim()
	sim.phase = GameSim.Phase.READY
	sim.gold = SlateCommands.move_cost(sim) - 1
	sim.add_slate(Vector2i(10, 10), "area")
	assert_eq(String(sim.apply({"type": "move_slate", "x": 10, "y": 10, "to_x": 11, "to_y": 11})["reason"]), "ERR_NOT_ENOUGH_GOLD")


## Слейт — отдельный слой: камень ставится поверх, башня встаёт на него, слейт кладётся под стену и башню,
## а из кандидата, стоящего на слейте, второй слейт не сделать (только из другого камня рецепта).
func test_slate_under_rock_and_tower() -> void:
	var sim: GameSim = new_sim()
	sim.gold = 1000
	var cell: Vector2i = Vector2i(10, 10)
	var s: TowerState = sim.add_slate(cell, "area")
	assert_true(sim.apply({"type": "place", "x": cell.x, "y": cell.y})["ok"], "камень на слейт")
	assert_eq(sim.grid.get_cell(cell), BoardGrid.Cell.CANDIDATE)
	assert_true(sim.slate_by_cell.has(cell), "слейт остался под камнем")
	assert_true(SlateBook.available_at(sim, cell).is_empty())
	var spare: Array[Vector2i] = [Vector2i(14, 6), Vector2i(18, 8), Vector2i(20, 16), Vector2i(8, 18)]
	for c2: Vector2i in spare:
		sim.apply({"type": "place", "x": c2.x, "y": c2.y})
	assert_eq(sim.phase, GameSim.Phase.CHOOSING)
	assert_true(sim.apply({"type": "keep", "x": cell.x, "y": cell.y})["ok"])
	assert_true(sim.tower_by_cell.has(cell), "башня стоит на слейте")
	assert_eq(s.cell, cell)
	assert_true(sim.apply({"type": "move_slate", "x": cell.x, "y": cell.y, "to_x": spare[0].x, "to_y": spare[0].y})["ok"], "под стену")
	assert_eq(sim.grid.get_cell(spare[0]), BoardGrid.Cell.ROCK)
	assert_true(sim.slate_by_cell.has(spare[0]))
	assert_true(sim.tower_by_cell.has(cell), "башня осталась на месте")
	assert_true(sim.apply({"type": "move_slate", "x": spare[0].x, "y": spare[0].y, "to_x": cell.x, "to_y": cell.y})["ok"], "под башню")
	var entrance: Vector2i = sim.grid.route_points[0]
	assert_true(sim.apply({"type": "move_slate", "x": cell.x, "y": cell.y, "to_x": entrance.x, "to_y": entrance.y})["ok"], "и к порталу")


func assert_gt_or_eq(a: int, b: int) -> void:
	assert_true(a >= b, "%d >= %d" % [a, b])


func test_area_hits_all_single_hits_first() -> void:
	var sim: GameSim = new_sim()
	var area: TowerState = sim.add_slate(Vector2i(10, 10), "area")
	var e1: EnemyState = _enemy(sim, "normal", area.pos + Vector2(0.5, 0.0))
	var e2: EnemyState = _enemy(sim, "normal", area.pos + Vector2(-1.0, 0.5))
	var far: EnemyState = _enemy(sim, "normal", area.pos + Vector2(5.0, 0.0))
	var hp: Array[float] = [e1.hp, e2.hp, far.hp]
	_pulse(sim, [e1, e2, far] as Array[EnemyState], 1.0)
	assert_true(e1.hp < hp[0] and e2.hp < hp[1], "Площадной бьёт всех в радиусе")
	assert_eq(far.hp, hp[2], "за радиусом — нет")
	var after: float = e1.hp
	_pulse(sim, [e1, e2] as Array[EnemyState], 1.1)
	assert_eq(e1.hp, after, "до следующего импульса — интервал")
	var sim2: GameSim = new_sim()
	var spell: TowerState = sim2.add_slate(Vector2i(10, 10), "airborne")
	var a: EnemyState = _enemy(sim2, "normal", spell.pos + Vector2(0.5, 0.0))
	var b: EnemyState = _enemy(sim2, "normal", spell.pos + Vector2(1.0, 0.0))
	b.dist = a.dist + 3.0
	var hp_a: float = a.hp
	_pulse(sim2, [a, b] as Array[EnemyState], 1.0)
	assert_eq(a.hp, hp_a, "одиночный бьёт только первого по пути")
	assert_true(b.hp < b.max_hp)


func test_ancient_stuns_and_shreds_armor() -> void:
	var sim: GameSim = new_sim()
	var s: TowerState = sim.add_slate(Vector2i(10, 10), "ancient")
	var e: EnemyState = _enemy(sim, "armored", s.pos + Vector2(0.5, 0.0))
	_pulse(sim, [e] as Array[EnemyState], 1.0)
	assert_true(e.is_stunned(1.5), "оглушение 2.5 с")
	assert_near(e.timed_shred, 12.0)
	assert_near(e.effective_armor(1.5), e.armor - 12.0)
	# Аура Ржавого обелиска сильнее (15), но короткая: после выхода из неё −12 Древнего ещё действует.
	e.shred = 15.0
	e.shred_until = 1.2
	assert_near(e.effective_armor(1.1), e.armor - 15.0, 0.0001, "действует сильнейшее")
	assert_near(e.effective_armor(2.0), e.armor - 12.0, 0.0001, "аура не обрывает снятие брони Древнего")
	assert_near(e.effective_armor(4.0), e.armor, 0.0001, "после оглушения броня вернулась")


func test_ghost_stacks_on_same_target() -> void:
	var sim: GameSim = new_sim()
	var s: TowerState = sim.add_slate(Vector2i(10, 10), "ghost")
	var e: EnemyState = _enemy(sim, "armored", s.pos + Vector2(0.5, 0.0))
	e.max_hp = 1.0e6
	e.hp = e.max_hp
	for i: int in 3:
		_pulse(sim, [e] as Array[EnemyState], 1.0 + float(i) * 1.1, 1.1)
	assert_eq(s.stack_target, e.id)
	assert_eq(s.stack_hits, 2, "каждое следующее попадание сильнее")


func test_poison_vine_and_slow() -> void:
	var sim: GameSim = new_sim()
	var s: TowerState = sim.add_slate(Vector2i(10, 10), "poison_vine")
	var e: EnemyState = _enemy(sim, "normal", s.pos + Vector2(0.5, 0.0))
	_pulse(sim, [e] as Array[EnemyState], 1.0)
	assert_eq(e.poison.size(), 1)
	assert_eq(int(e.poison[0]["source"]), s.id)
	assert_near(e.slow_pct, 0.25)
	_pulse(sim, [e] as Array[EnemyState], 2.2, 1.1)
	assert_eq(e.poison.size(), 1, "повторный импульс обновляет стак, а не складывает")


func test_slate_auras_boost_towers() -> void:
	var sim: GameSim = new_sim()
	var g: TowerState = add_tower(sim, 0, "ruby", 1)
	var before_speed: float = g.aura_speed_bonus
	sim.add_slate(g.cell + Vector2i(1, 1), "opal_vein")
	sim.add_slate(g.cell + Vector2i(-1, 1), "damage")
	sim.combat.recompute_auras(sim)
	assert_near(g.aura_speed_bonus, before_speed + 0.10)
	assert_near(g.damage_mult(), 1.10)
	assert_true(NetProtocol.valid_command({"type": "make_slate", "x": 1, "y": 2, "slate": "area", "tick": 3}))
	assert_true(NetProtocol.valid_command({"type": "move_slate", "x": 1, "y": 2, "to_x": 3, "to_y": 4, "tick": 3}))
	assert_true(NetProtocol.valid_command({"type": "combine_slates", "x": 1, "y": 2, "with_x": 3, "with_y": 4, "tick": 3}))


func test_slate_texts_and_sounds() -> void:
	var d: GameData = data()
	for sl: Dictionary in d.slates:
		var id: String = String(sl["id"])
		for key: String in [String(sl["name_key"]), String(sl["role_key"])]:
			assert_ne(TranslationServer.translate(key), StringName(key), "перевод " + key)
		assert_true(SlateText.describe(d, id).size() >= 2, "описание " + id)
		assert_false(SlateText.recipe_text(d, id).is_empty(), "рецепт " + id)
		assert_true(DirAccess.dir_exists_absolute("res://audio/" + String(sl["sfx"])), "звук " + String(sl["sfx"]))


## Партия бота со слейтами (делает, кладёт на путь, объединяет) пересимулируется из реплея бит в бит.
func test_slates_bot_game_replays() -> void:
	var sim: GameSim = new_sim(1001, {"max_waves": 12, "record_events": false})
	var bot: BotPlayer = BotPlayer.new(sim, "slates", sim.seed_value)
	bot.run_to_end()
	assert_false((sim.stats["slates_made"] as Dictionary).is_empty(), "бот сделал слейты")
	var kinds: Array[String] = []
	for c: Dictionary in sim.command_log:
		if String(c["type"]).contains("slate") and not kinds.has(String(c["type"])):
			kinds.append(String(c["type"]))
	assert_true(kinds.has("make_slate") and kinds.has("move_slate"), "сделал и переложил: %s" % str(kinds))
	var rep: Dictionary = Replay.simulate(sim.data, Replay.from_sim(sim, "test"))
	assert_true(bool(rep["ok"]), String(rep.get("reason", "")))


## «Замедление до смерти» не перезаписывается временным: после него снова действует 15 %.
func test_permanent_slow_survives_stronger_temporary_slow() -> void:
	var sim: GameSim = new_sim()
	var s: TowerState = sim.add_slate(Vector2i(10, 10), "slow")
	var e: EnemyState = _enemy(sim, "normal", s.pos + Vector2(0.5, 0.0))
	e.max_hp = 1.0e6
	e.hp = e.max_hp
	_pulse(sim, [e] as Array[EnemyState], 1.0)
	assert_near(e.current_slow(1.0), 0.15)
	e.apply_slow(0.3, 3.0, 1.0)
	assert_near(e.current_slow(2.0), 0.3, 0.0001, "сильнейшее действует")
	assert_near(e.current_slow(10.0), 0.15, 0.0001, "временное кончилось — постоянное осталось")
	assert_true(EnemyTraits._cleanse(e, 10.0), "очищение снимает и постоянное")
	assert_near(e.current_slow(10.0), 0.0)


func test_slate_cells_reserved_in_grid() -> void:
	var sim: GameSim = new_sim()
	sim.phase = GameSim.Phase.READY
	sim.gold = 100
	var c: Vector2i = Vector2i(10, 10)
	sim.add_slate(c, "area")
	assert_true(sim.grid.is_buildable(c), "строить на слейте можно")
	assert_false(sim.grid.is_free_ground(c))
	assert_false(sim.grid.can_hold_slate(c), "второй слейт туда не положить")
	assert_eq(sim.grid.get_cell(c), BoardGrid.Cell.EMPTY, "клетка проходима")
	assert_true(sim.apply({"type": "move_slate", "x": 10, "y": 10, "to_x": 11, "to_y": 11})["ok"])
	assert_true(sim.grid.can_hold_slate(c), "старая клетка освободилась")
	assert_true(sim.grid.is_reserved(Vector2i(11, 11)))
	assert_true(sim.apply({"type": "sell", "x": 11, "y": 11})["ok"])
	assert_false(sim.grid.is_reserved(Vector2i(11, 11)), "продан — клетка свободна")


func test_slate_effect_companions_validated() -> void:
	assert_eq(GameData.missing_slate_effects({"spell_chance": 0.2}), PackedStringArray(["spell_damage", "spell_radius"]))
	assert_eq(GameData.missing_slate_effects({"poison_dps": 5.0}), PackedStringArray(["poison_duration"]))
	assert_true(GameData.missing_slate_effects({}).is_empty())
	for sl: Dictionary in data().slates:
		assert_true(GameData.missing_slate_effects(sl["effects"]).is_empty(), "полные эффекты " + String(sl["id"]))
