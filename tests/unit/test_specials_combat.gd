extends TestCase


func _special(sim: GameSim, cell: Vector2i, id: String, level: int) -> TowerState:
	var t: TowerState = sim.add_special_tower(cell, id)
	t.level = level
	t.refresh_stats(sim.data)
	sim.route.recompute()
	sim.combat.recompute_auras(sim)
	return t


func test_beacon_lens_extends_neighbor_range() -> void:
	var sim: GameSim = new_sim()
	var g: TowerState = add_tower(sim, 0, "ruby", 1)
	var before: float = g.attack_range
	_special(sim, Vector2i(31, 23), "beacon_lens", 1)
	assert_near(g.attack_range, before + 1.0, 0.001)
	assert_true(g.aura_speed_bonus > 0.0)


func _run_wave_with(id: String, level: int) -> GameSim:
	var sim: GameSim = new_sim(11)
	_special(sim, Vector2i(3, 7), id, level)
	sim.phase = GameSim.Phase.READY
	sim.apply({"type": "start_wave"})
	return sim


func test_cinder_crown_damages_in_radius() -> void:
	var sim: GameSim = _run_wave_with("cinder_crown", 1)
	var pulses: int = 0
	for i: int in 30 * 25:
		sim.step()
		for e: Dictionary in sim.drain_events():
			if e["type"] == "aura_pulse":
				pulses += 1
	assert_true(pulses > 0, "аура должна срабатывать")
	assert_true(sim.towers[0].total_damage > 0.0)


func test_frostwell_slows_and_l3_freezes() -> void:
	var sim: GameSim = _run_wave_with("frostwell", 3)
	var slowed: bool = false
	var frozen: bool = false
	for i: int in 30 * 25:
		sim.step()
		for e: EnemyState in sim.enemies:
			if e.current_slow(sim.wave_time) >= 0.44:
				slowed = true
		for ev: Dictionary in sim.drain_events():
			if ev["type"] == "frozen":
				frozen = true
	assert_true(slowed)
	assert_true(frozen, "L3: шанс заморозки")


func test_blightbloom_creates_pools() -> void:
	var sim: GameSim = _run_wave_with("blightbloom", 1)
	var pools: int = 0
	for i: int in 30 * 25:
		sim.step()
		for ev: Dictionary in sim.drain_events():
			if ev["type"] == "pool_created":
				pools += 1
	assert_true(pools > 0)
	assert_true(sim.towers[0].total_damage > 0.0)


func test_skypiercer_prefers_air_damage() -> void:
	var d: GameData = data()
	assert_true(TowerState.estimate_special_dps(d, "skypiercer", 1, true) > TowerState.estimate_special_dps(d, "skypiercer", 1, false) * 4.0)
