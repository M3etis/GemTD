extends TestCase
## Испытание урона: после победы, 60 с, колосс неуязвим, результат проверяется реплеем.


func _won_sim() -> GameSim:
	var sim: GameSim = new_sim(42, {"difficulty": "easy", "max_waves": 2, "record_events": false})
	BotPlayer.new(sim, "maze", 42).run_to_end()
	return sim


func test_only_after_victory() -> void:
	var sim: GameSim = new_sim()
	assert_false(sim.apply({"type": "start_damage_test"})["ok"])


func test_damage_test_runs_and_replays() -> void:
	var sim: GameSim = _won_sim()
	assert_eq(sim.phase, GameSim.Phase.VICTORY)
	assert_true(sim.apply({"type": "start_damage_test"})["ok"])
	assert_true(sim.damage_test)
	var ticks: int = 0
	var colossus_seen: bool = false
	while sim.phase == GameSim.Phase.COMBAT and ticks < 30 * 120:
		sim.step()
		ticks += 1
		for e: EnemyState in sim.enemies:
			if e.immortal:
				colossus_seen = true
				assert_near(e.hp, e.max_hp, 0.001, "колосс неуязвим")
	assert_true(colossus_seen)
	assert_eq(sim.phase, GameSim.Phase.VICTORY)
	assert_near(float(ticks) * sim.dt, sim.damage_test_duration(), 0.05)
	var s: Dictionary = sim.summary()
	assert_true(bool(s["damage_test_done"]))
	assert_true(int(s["damage_test_dps"]) > 0)
	assert_false(sim.apply({"type": "start_damage_test"})["ok"], "второй раз нельзя")
	var rep: Dictionary = Replay.simulate(sim.data, Replay.from_sim(sim, "test"))
	assert_true(rep["ok"], "реплей с испытанием совпадает")
	var rec: Dictionary = RecordIO.record_from_summary(sim.data, s, {"id": "x"})
	assert_eq(int(rec["damage_dps"]), int(s["damage_test_dps"]))


func test_damage_test_does_not_change_speed_metric() -> void:
	var sim: GameSim = _won_sim()
	var before: float = float(sim.summary()["combat_seconds"])
	sim.apply({"type": "start_damage_test"})
	while sim.phase == GameSim.Phase.COMBAT:
		sim.step()
	assert_near(float(sim.summary()["combat_seconds"]), before, 0.0001)
