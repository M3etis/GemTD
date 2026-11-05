extends TestCase


func test_save_mid_round_restores_exactly() -> void:
	var sim: GameSim = new_sim(77, {"max_waves": 4, "record_events": false})
	var bot: BotPlayer = BotPlayer.new(sim, "maze", 77)
	# Два полных раунда + два камня третьего.
	while sim.round_index < 3:
		if sim.phase == GameSim.Phase.COMBAT:
			sim.step()
		else:
			bot.act()
	bot.act()
	bot.act()
	assert_eq(sim.phase, GameSim.Phase.PLACING)
	var header: Dictionary = Replay.from_sim(sim, "test")
	header["saved_tick"] = sim.tick
	header["saved_checksum"] = sim.checksum()
	var json_save: Dictionary = JSON.parse_string(JSON.stringify(header))
	var res: Dictionary = Replay.resimulate(data(), json_save, int(json_save["saved_tick"]))
	assert_true(res["ok"], String(res["reason"]))
	var loaded: GameSim = res["sim"]
	assert_eq(loaded.checksum(), sim.checksum(), "состояние после загрузки совпадает")
	assert_eq(loaded.candidates.size(), 2)
	# Доигрываем обе копии одинаковым ботом — финал должен совпасть.
	var bot2: BotPlayer = BotPlayer.new(loaded, "maze", 77)
	bot2.rng.set_state(bot.rng.get_state())
	bot.run_to_end()
	bot2.run_to_end()
	assert_eq(loaded.checksum(), sim.checksum())


func test_bot_forges_a_special_on_seed_42() -> void:
	var sim: GameSim = new_sim(42, {"max_waves": 10, "record_events": false})
	BotPlayer.new(sim, "maze", 42).run_to_end()
	assert_false((sim.stats["specials_forged"] as Dictionary).is_empty(), "бот должен создать хотя бы одну спец-башню")
	var rep: Dictionary = Replay.simulate(data(), Replay.from_sim(sim, "test"))
	assert_true(rep["ok"], "реплей со спец-башнями: " + String(rep["reason"]))
