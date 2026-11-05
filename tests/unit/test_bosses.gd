extends TestCase
## 62 волны в два акта, боссы и их фазы (§6.5 PROMPT.md).


func _enemy(sim: GameSim, type: String) -> EnemyState:
	sim.combat.sim = sim
	var e: EnemyState = sim.combat.spawn_enemy(type, 1.0, [], false, 5.0)
	sim.combat._flush_pending()
	sim.combat.sim = null
	return e


func _update(sim: GameSim, e: EnemyState, now: float) -> void:
	sim.combat.sim = sim
	EnemyTraits.update(sim.combat, e, 1.0 / 30.0, now)
	sim.combat._flush_pending()
	sim.combat.sim = null


func test_62_waves_with_six_boss_waves() -> void:
	var d: GameData = data()
	assert_eq(d.wave_count(), 62)
	# Первый акт кончается Королём на 42-й; второй — Левиафан на 52-й (воздушная волна) и финал на 62-й.
	var expected: Dictionary = {10: "boss_stone", 20: "boss_sky", 30: "boss_summoner", 42: "boss_final", 52: "boss_sky", 62: "boss_final"}
	assert_eq((d.waves_cfg["boss_waves"] as Array).size(), expected.size())
	for n: int in expected.keys():
		assert_true(d.is_boss_wave(n))
		var found: bool = false
		for grp: Dictionary in d.wave(n)["groups"]:
			found = found or String(grp["type"]) == String(expected[n])
		assert_true(found, "волна %d: нет %s" % [n, expected[n]])
	assert_true(bool(d.archetype("boss_sky")["flying"]), "босс 20-й волны летающий")


func test_traits_start_at_wave_eight_and_stack_late() -> void:
	var d: GameData = data()
	for n: int in range(1, 8):
		assert_true((WaveSpawner.summary(d, n)["traits"] as Array).is_empty(), "волна %d без трейтов" % n)
	assert_false((WaveSpawner.summary(d, 8)["traits"] as Array).is_empty())
	var multi: int = 0
	for n2: int in range(31, 42):
		for grp: Dictionary in WaveSpawner.summary(d, n2)["groups"]:
			if (grp["traits"] as Array).size() >= 2:
				multi += 1
				break
	assert_true(multi >= 6, "в 31–41 у врагов по 2–3 трейта (волн с ≥2: %d)" % multi)


func test_every_wave_spawns_without_unknown_types() -> void:
	var d: GameData = data()
	for n: int in range(1, d.wave_count() + 1):
		for entry: Dictionary in WaveSpawner.build_schedule(d, n):
			assert_true(d.archetypes.has(String(entry["type"])))
			for t: Variant in entry["traits"]:
				assert_true(d.traits.has(String(t)))


func test_final_boss_three_phases() -> void:
	var sim: GameSim = new_sim()
	var b: EnemyState = _enemy(sim, "boss_final")
	assert_eq(b.phase_index, 1, "фаза 1 — щит сразу")
	assert_true(b.shield > 0.0)
	b.shield = 0.0
	b.hp = b.max_hp * 0.6
	_update(sim, b, 1.0)
	assert_eq(b.phase_index, 2, "фаза 2 — ярость")
	assert_true(b.speed_mult > 1.0)
	var before: int = sim.enemies.size()
	b.hp = b.max_hp * 0.3
	_update(sim, b, 2.0)
	assert_eq(b.phase_index, 3, "фаза 3 — эскорт")
	assert_true(sim.enemies.size() > before, "призыв эскорта")
	var flying: bool = false
	for e: EnemyState in sim.enemies:
		flying = flying or (e.flying and not e.boss)
	assert_true(flying, "эскорт включает воздушных")


func test_summoner_summons_on_interval() -> void:
	var sim: GameSim = new_sim()
	var b: EnemyState = _enemy(sim, "boss_summoner")
	var summon: Dictionary = data().archetype("boss_summoner")["abilities"]["summon"]
	var start: int = sim.enemies.size()
	_update(sim, b, 1.0)
	assert_eq(sim.enemies.size(), start + int(summon["count"]))
	_update(sim, b, 1.5)
	assert_eq(sim.enemies.size(), start + int(summon["count"]), "до интервала новых нет")
	_update(sim, b, 1.0 + float(summon["interval"]) + 0.01)
	assert_eq(sim.enemies.size(), start + 2 * int(summon["count"]))


func test_boss_leak_costs_data_lives() -> void:
	var d: GameData = data()
	for id: String in ["boss_stone", "boss_sky", "boss_summoner", "boss_final"]:
		assert_true(int(d.archetype(id)["leak_damage"]) > 1)
