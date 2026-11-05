extends TestCase


func test_matrix_lookup() -> void:
	var d: GameData = data()
	assert_near(d.damage_mult("siege", "fortified"), 1.6)
	assert_near(d.damage_mult("pure", "boss"), 1.0)
	assert_near(d.damage_mult("unknown", "boss"), 1.0)


func test_armor_reduces_and_negative_increases() -> void:
	var d: GameData = data()
	assert_near(DamageCalc.armor_factor(d, 0.0), 1.0)
	var f5: float = DamageCalc.armor_factor(d, 5.0)
	assert_true(f5 < 1.0 and f5 > 0.5)
	assert_near(f5, 1.0 - 0.3 / 1.3, 0.0001)
	assert_true(DamageCalc.armor_factor(d, -5.0) > 1.0)


func test_pure_ignores_armor() -> void:
	var d: GameData = data()
	assert_near(DamageCalc.final_damage(d, 100.0, "pure", "boss", 50.0), 100.0)


func test_armor_ignore_only_reduces_positive_armor() -> void:
	var d: GameData = data()
	var full: float = DamageCalc.final_damage(d, 100.0, "physical", "medium", 0.0)
	var ignored: float = DamageCalc.final_damage(d, 100.0, "physical", "medium", 4.0, 10.0)
	assert_near(full, ignored, 0.0001)
	var neg: float = DamageCalc.final_damage(d, 100.0, "physical", "medium", -3.0, 10.0)
	assert_true(neg > full)


func test_tower_stats_scale_with_quality() -> void:
	var d: GameData = data()
	var low: TowerState = TowerState.new()
	low.setup(d, 1, Vector2i(3, 3), "ruby", 1, 1)
	var high: TowerState = TowerState.new()
	high.setup(d, 2, Vector2i(4, 3), "ruby", 5, 1)
	assert_true(high.damage > low.damage * 10.0)
	assert_true(high.attack_range > low.attack_range)
	assert_false(TowerState.estimate_dps(d, "diamond", 1, true) > 0.0, "алмаз не бьёт воздух")
	assert_true(TowerState.estimate_dps(d, "amethyst", 1, true) > TowerState.estimate_dps(d, "amethyst", 1, false))
