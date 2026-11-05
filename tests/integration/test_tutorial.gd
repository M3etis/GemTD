extends TestCase
## Обучение: заданное выпадение гемов и выполнимость шагов (Combine во 2-м раунде, рецепт в 3-м).


func _sim() -> GameSim:
	var cfg: Dictionary = {"seed": 7700, "difficulty": "easy", "draft_overrides": Tutorial.DRAFTS, "record_events": false}
	var sim: GameSim = GameSim.new(data(), cfg)
	sim.start()
	return sim


func _place_all(sim: GameSim, bot: BotPlayer) -> void:
	while sim.phase == GameSim.Phase.PLACING:
		var c: Vector2i = bot.choose_rock_cell()
		assert_true(sim.apply({"type": "place", "x": c.x, "y": c.y})["ok"])


func _finish_wave(sim: GameSim) -> void:
	assert_true(sim.apply({"type": "start_wave"})["ok"])
	while sim.phase == GameSim.Phase.COMBAT:
		sim.step()


func test_tutorial_rounds_are_playable() -> void:
	var sim: GameSim = _sim()
	var bot: BotPlayer = BotPlayer.new(sim, "maze", 1)
	_place_all(sim, bot)
	var gems: Array = sim.candidates.map(func(c: Dictionary) -> String: return "%s%d" % [c["gem"], c["quality"]])
	assert_eq(gems, ["amethyst1", "ruby1", "diamond1", "sapphire1", "topaz1"])
	assert_true(RecipeBook.available_at(sim, sim.candidates[1]["cell"]).is_empty(), "в 1-м раунде рецептов нет")
	assert_true(sim.apply({"type": "keep", "x": sim.candidates[1]["cell"].x, "y": sim.candidates[1]["cell"].y})["ok"])
	_finish_wave(sim)
	_place_all(sim, bot)
	assert_eq(BuildCommands.can_combine(sim, sim.candidates[0]["cell"], 2), "", "во 2-м раунде есть пара для Combine")
	var cc: Vector2i = sim.candidates[0]["cell"]
	assert_true(sim.apply({"type": "combine", "x": cc.x, "y": cc.y, "count": 2})["ok"])
	_finish_wave(sim)
	_place_all(sim, bot)
	var fc: Vector2i = sim.candidates[0]["cell"]
	var specials: Array = RecipeBook.available_at(sim, fc).map(func(o: Dictionary) -> String: return String(o["special"]))
	assert_true(specials.has("cinder_crown"), "в 3-м раунде собран рецепт Венца Пепла")
	assert_true(sim.apply({"type": "forge", "x": fc.x, "y": fc.y, "special": "cinder_crown"})["ok"])
	_finish_wave(sim)
	assert_eq(sim.round_index, 4)


func test_overrides_only_first_rounds() -> void:
	var a: GameSim = _sim()
	var b: GameSim = GameSim.new(data(), {"seed": 7700, "difficulty": "easy"})
	b.start()
	assert_eq(a.roll_gem(4, 0, 1), b.roll_gem(4, 0, 1), "с 4-го раунда выпадение обычное")
	assert_ne(a.roll_gem(1, 0, 1), b.roll_gem(1, 0, 1))
