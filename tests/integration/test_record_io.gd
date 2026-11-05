extends TestCase


func _finished_run(seed_value: int) -> GameSim:
	var sim: GameSim = new_sim(seed_value, {"max_waves": 3, "record_events": false})
	BotPlayer.new(sim, "maze", seed_value).run_to_end()
	return sim


func _record_for(sim: GameSim) -> Dictionary:
	return RecordIO.record_from_summary(data(), sim.summary(), {"id": "test-1", "name": "Аня", "date": "2026-10-27T12:00:00"})


func test_export_import_roundtrip() -> void:
	var sim: GameSim = _finished_run(5)
	var rec: Dictionary = _record_for(sim)
	var bundle: Dictionary = JSON.parse_string(JSON.stringify(RecordIO.export_bundle(rec, Replay.from_sim(sim, "test"))))
	var res: Dictionary = RecordIO.import_bundle(data(), bundle)
	assert_true(res["ok"], String(res.get("reason", "")))
	assert_eq(int(res["record"]["score"]), int(rec["score"]))
	assert_eq(String(res["record"]["name"]), "Аня")
	assert_true(bool(res["record"]["imported"]))
	assert_eq(String(res["record"]["verify_state"]), "ok")


func test_tampered_score_is_recomputed() -> void:
	var sim: GameSim = _finished_run(6)
	var rec: Dictionary = _record_for(sim)
	var bundle: Dictionary = RecordIO.export_bundle(rec, Replay.from_sim(sim, "test"))
	bundle["record"]["score"] = 999999
	bundle["record"]["waves_cleared"] = 42
	var res: Dictionary = RecordIO.import_bundle(data(), bundle)
	assert_true(res["ok"])
	assert_eq(int(res["record"]["score"]), int(rec["score"]), "очки берутся из реплея")
	assert_eq(int(res["record"]["waves_cleared"]), int(rec["waves_cleared"]))


func test_tampered_replay_rejected() -> void:
	var sim: GameSim = _finished_run(7)
	var bundle: Dictionary = RecordIO.export_bundle(_record_for(sim), Replay.from_sim(sim, "test"))
	bundle["replay"]["seed"] = 8
	assert_false(RecordIO.import_bundle(data(), bundle)["ok"])
	assert_false(RecordIO.import_bundle(data(), {"format": "nope"})["ok"])


func test_replay_seek_to_wave() -> void:
	var sim: GameSim = _finished_run(9)
	var rep: Dictionary = Replay.from_sim(sim, "test")
	var idx: int = Replay.start_wave_index(rep, 2)
	assert_true(idx > 0)
	var mid: GameSim = Replay.resimulate_until_command(data(), rep, idx)
	assert_eq(mid.phase, GameSim.Phase.READY)
	assert_eq(mid.round_index, 2)
	# Доигрываем остаток команд — получаем тот же финал.
	var commands: Array = rep["commands"]
	for i: int in range(idx, commands.size()):
		var cmd: Dictionary = commands[i]
		while mid.tick < int(cmd["tick"]) and mid.phase == GameSim.Phase.COMBAT:
			mid.step()
		mid.apply(cmd)
	while mid.phase == GameSim.Phase.COMBAT:
		mid.step()
	assert_eq(mid.checksum(), sim.checksum())
