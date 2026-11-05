extends TestCase
## Сложности (`difficulty.json`): разгон множителя HP, порядок уровней, применение в симуляции.


func test_ramp_goes_from_one_to_target() -> void:
	var d: GameData = data()
	var lvl: Dictionary = {"hp_mult": 1.5, "hp_ramp_waves": 10}
	assert_near(d.difficulty_hp_mult(lvl, 1), 1.0)
	assert_near(d.difficulty_hp_mult(lvl, 6), 1.25)
	assert_near(d.difficulty_hp_mult(lvl, 11), 1.5)
	assert_near(d.difficulty_hp_mult(lvl, 60), 1.5)
	assert_near(d.difficulty_hp_mult({"hp_mult": 0.8}, 1), 0.8, 0.0001, "без разгона — сразу hp_mult")


## Чем выше уровень, тем крепче враги на каждой волне, меньше жизней и больше очков.
func test_levels_are_ordered() -> void:
	var d: GameData = data()
	for i: int in range(1, d.difficulty_order.size()):
		var a: Dictionary = d.difficulty(d.difficulty_order[i - 1])
		var b: Dictionary = d.difficulty(d.difficulty_order[i])
		for n: int in range(1, d.wave_count() + 1):
			assert_true(d.difficulty_hp_mult(b, n) >= d.difficulty_hp_mult(a, n), "%s слабее %s на волне %d" % [b["id"], a["id"], n])
		assert_true(int(b["lives"]) <= int(a["lives"]), "жизни %s" % b["id"])
		assert_true(float(b["score_mult"]) > float(a["score_mult"]), "очки %s" % b["id"])


func test_sim_spawns_with_ramped_hp() -> void:
	var d: GameData = data()
	for id: String in d.difficulty_order:
		var sim: GameSim = new_sim(42, {"difficulty": id, "record_events": false})
		sim.wave_number = 1
		sim.combat.sim = sim
		var e: EnemyState = sim.combat.spawn_enemy("normal", 1.0, [], false, 0.0)
		sim.combat.sim = null
		var expected: float = d.enemy_base_hp(1) * float(d.archetype("normal")["hp_mult"]) * d.difficulty_hp_mult(d.difficulty(id), 1)
		assert_near(e.max_hp, expected, 0.001, id)


## Разгон в симуляции на середине разгона, Панцирь (его блок считается от HP волны со сложностью)
## и Испытание урона: множитель берётся по волне колосса (economy.damage_test.wave), а не по текущей.
func test_sim_ramp_mid_wave_carapace_and_damage_test() -> void:
	var d: GameData = data()
	var hard: Dictionary = d.difficulty("hard")
	var n: int = int(float(hard["hp_ramp_waves"]) * 0.5) + 1
	var mult: float = d.difficulty_hp_mult(hard, n)
	assert_true(mult > 1.0 and mult < float(hard["hp_mult"]), "волна %d — середина разгона (%.3f)" % [n, mult])
	var sim: GameSim = new_sim(42, {"difficulty": "hard", "record_events": false})
	sim.wave_number = n
	sim.combat.sim = sim
	var e: EnemyState = sim.combat.spawn_enemy("armored", 1.0, ["carapace"], false, 0.0)
	sim.combat.sim = null
	assert_near(e.max_hp, d.enemy_base_hp(n) * float(d.archetype("armored")["hp_mult"]) * mult, 0.001, "HP")
	assert_near(e.carapace_block, float(d.trait_cfg("carapace")["block_pct"]) * d.enemy_base_hp(n) * mult, 0.0001, "Панцирь")
	var extreme: Dictionary = d.difficulty("extreme")
	var ext: GameSim = new_sim(42, {"difficulty": "extreme", "record_events": false})
	ext.wave_number = 1
	ext.damage_test = true
	var test_wave: int = int(d.economy["damage_test"]["wave"])
	assert_near(ext.diff_hp_mult(), d.difficulty_hp_mult(extreme, test_wave), 0.0001, "Испытание урона")
	assert_true(ext.diff_hp_mult() > d.difficulty_hp_mult(extreme, 1), "не множитель первой волны")
