extends TestCase


func test_air_waves_every_fourth() -> void:
	var d: GameData = data()
	for n: int in range(1, d.wave_count() + 1):
		var s: Dictionary = WaveSpawner.summary(d, n)
		if n % 4 == 0:
			assert_true(s["air"], "волна %d должна быть воздушной" % n)
			for grp: Dictionary in s["groups"]:
				assert_true(bool(d.archetypes[grp["type"]]["flying"]) or bool(d.archetypes[grp["type"]]["boss"]))
		else:
			assert_false(s["air"])


func test_boss_wave_ten() -> void:
	var d: GameData = data()
	assert_true(d.is_boss_wave(10))
	var has_boss: bool = false
	for grp: Dictionary in WaveSpawner.summary(d, 10)["groups"]:
		has_boss = has_boss or bool(d.archetypes[grp["type"]]["boss"])
	assert_true(has_boss)


func test_hp_grows() -> void:
	var d: GameData = data()
	for n: int in range(2, d.wave_count() + 1):
		assert_true(d.enemy_base_hp(n) > d.enemy_base_hp(n - 1))


## Второй акт: после late.from_wave HP растёт медленнее (доска выходит на плато), без скачка на стыке.
func test_hp_late_growth_is_slower_and_continuous() -> void:
	var d: GameData = data()
	var f: Dictionary = d.waves_cfg["hp_formula"]
	var from: int = int(f["late"]["from_wave"])
	var classic: float = float(f["base"]) * pow(float(f["growth"]), float(from - 1)) + float(f["linear"]) * float(from - 1)
	assert_near(d.enemy_base_hp(from), classic, 0.001)
	var early: float = d.enemy_base_hp(from) / d.enemy_base_hp(from - 1)
	var late: float = d.enemy_base_hp(from + 1) / d.enemy_base_hp(from)
	assert_true(late < early, "рост после %d-й (%.3f) ниже, чем до неё (%.3f)" % [from, late, early])
	assert_true(late > 1.0)


func test_schedule_sorted_and_complete() -> void:
	var d: GameData = data()
	for n: int in range(1, d.wave_count() + 1):
		var sch: Array[Dictionary] = WaveSpawner.build_schedule(d, n)
		assert_eq(sch.size(), int(WaveSpawner.summary(d, n)["total"]))
		for i: int in range(1, sch.size()):
			assert_true(float(sch[i]["time"]) >= float(sch[i - 1]["time"]))
