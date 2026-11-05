extends TestCase


func _bot_game(seed_value: int, waves: int) -> GameSim:
	var sim: GameSim = new_sim(seed_value, {"max_waves": waves, "record_events": false})
	var bot: BotPlayer = BotPlayer.new(sim, "maze", seed_value)
	bot.run_to_end()
	return sim


func test_bot_is_deterministic() -> void:
	var a: GameSim = _bot_game(42, 4)
	var b: GameSim = _bot_game(42, 4)
	assert_true(a.is_over())
	assert_eq(a.checksum(), b.checksum(), "два прогона с одним seed должны совпасть")
	assert_eq(a.command_log.size(), b.command_log.size())


func test_replay_resimulates_to_same_checksum() -> void:
	var sim: GameSim = _bot_game(2024, 4)
	var rep: Dictionary = Replay.from_sim(sim, "test")
	var json_rep: Variant = JSON.parse_string(JSON.stringify(rep))
	var res: Dictionary = Replay.simulate(data(), json_rep)
	assert_true(res["ok"], "реплей: %s" % res["reason"])
	assert_eq(int(res["checksum"]), sim.checksum())


func test_tampered_replay_fails() -> void:
	var sim: GameSim = _bot_game(7, 3)
	var rep: Dictionary = Replay.from_sim(sim, "test")
	rep["final_checksum"] = int(rep["final_checksum"]) ^ 1
	assert_false(Replay.simulate(data(), rep)["ok"])
	var rep2: Dictionary = Replay.from_sim(sim, "test")
	rep2["seed"] = 8
	assert_false(Replay.simulate(data(), rep2)["ok"])
