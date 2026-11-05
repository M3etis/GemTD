extends TestCase


func _setup_tower_sim(gem: String, quality: int) -> GameSim:
	var sim: GameSim = new_sim(7)
	# Башня у первого отрезка маршрута.
	var t: TowerState = TowerState.new()
	t.setup(sim.data, sim.new_id(), Vector2i(3, 7), gem, quality, 1)
	sim.towers.append(t)
	sim.tower_by_id[t.id] = t
	sim.tower_by_cell[t.cell] = t
	sim.grid.set_cell(t.cell, BoardGrid.Cell.GEM)
	sim.route.recompute()
	sim.phase = GameSim.Phase.READY
	return sim


func test_wave_runs_to_completion() -> void:
	var sim: GameSim = _setup_tower_sim("ruby", 5)
	assert_true(sim.apply({"type": "start_wave"})["ok"])
	var guard: int = 0
	while sim.phase == GameSim.Phase.COMBAT and guard < 30 * 600:
		sim.step()
		guard += 1
	assert_eq(sim.phase, GameSim.Phase.PLACING, "волна должна закончиться")
	assert_eq(sim.round_index, 2)
	assert_eq(int(sim.stats["kills"]) + int(sim.stats["leaks"]), int(WaveSpawner.summary(sim.data, 1)["total"]))
	assert_true(sim.gold > 0)


func test_leaks_cost_lives() -> void:
	var sim: GameSim = new_sim(9)
	sim.phase = GameSim.Phase.READY
	var lives: int = sim.lives
	sim.apply({"type": "start_wave"})
	while sim.phase == GameSim.Phase.COMBAT:
		sim.step()
	var total: int = int(WaveSpawner.summary(sim.data, 1)["total"])
	assert_eq(sim.lives, lives - total)
	assert_eq(int(sim.stats["leaks"]), total)


func test_slow_and_poison_apply() -> void:
	var sim: GameSim = _setup_tower_sim("aquamarine", 1)
	sim.apply({"type": "start_wave"})
	var slowed: bool = false
	for i: int in 30 * 20:
		sim.step()
		for e: EnemyState in sim.enemies:
			if e.current_slow(sim.wave_time) > 0.0:
				slowed = true
	assert_true(slowed, "аквамарин должен замедлять")
	var sim2: GameSim = _setup_tower_sim("emerald", 1)
	sim2.apply({"type": "start_wave"})
	var poisoned: bool = false
	for i: int in 30 * 20:
		sim2.step()
		for e: EnemyState in sim2.enemies:
			if not e.poison.is_empty():
				poisoned = true
	assert_true(poisoned, "изумруд должен отравлять")


func test_ground_only_tower_ignores_flyers() -> void:
	var sim: GameSim = _setup_tower_sim("diamond", 5)
	var e: EnemyState = EnemyState.new()
	e.id = sim.new_id()
	e.flying = true
	e.hp = 100.0
	e.max_hp = 100.0
	e.pos = sim.towers[0].pos + Vector2(0.5, 0.0)
	assert_false(sim.combat._can_hit(sim.towers[0], e))


func test_wave_dps_recorded_per_wave() -> void:
	var sim: GameSim = new_sim(42, {"max_waves": 3, "record_events": false})
	BotPlayer.new(sim, "maze", 42).run_to_end()
	var s: Dictionary = sim.summary()
	assert_eq((s["wave_dps"] as Array).size(), int(s["waves_cleared"]))
	for v: Variant in s["wave_dps"]:
		assert_true(float(v) >= 0.0)
