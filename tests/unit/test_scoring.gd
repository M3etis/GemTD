extends TestCase


func test_score_formula() -> void:
	var d: GameData = data()
	var s: Dictionary = {"difficulty": "normal", "waves_cleared": 3, "perfect_waves": 2, "kills": 30, "lives": 10, "outcome": "defeat"}
	# 100*(1+2+3) + 50*2 + 30 + 250*10 = 600 + 100 + 30 + 2500
	assert_eq(Scoring.compute(d, s), 3230)
	s["difficulty"] = "hard"
	assert_eq(Scoring.compute(d, s), int(roundf(3230.0 * float(d.difficulty("hard")["score_mult"]))))


func test_victory_speed_bonus() -> void:
	var d: GameData = data()
	var s: Dictionary = {"difficulty": "normal", "waves_cleared": 1, "perfect_waves": 0, "kills": 0, "lives": 0,
		"outcome": "victory", "total_waves": 1, "combat_seconds": 35.0}
	assert_eq(Scoring.compute(d, s), 100 + 50)
