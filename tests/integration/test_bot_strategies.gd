extends TestCase
## Шесть стратегий бота для balance_sim: играют только командами и детерминированы.


func _play(strategy: String, seed_value: int) -> Dictionary:
	var sim: GameSim = new_sim(seed_value, {"max_waves": 6, "record_events": false})
	return BotPlayer.new(sim, strategy, seed_value).run_to_end()


func test_strategies_deterministic_and_valid() -> void:
	for strategy: String in BotPlayer.BALANCE_STRATEGIES:
		var a: Dictionary = _play(strategy, 5)
		var b: Dictionary = _play(strategy, 5)
		assert_eq(int(a["checksum"]), int(b["checksum"]), strategy + ": два прогона совпадают")
		assert_true(int(a["waves_cleared"]) >= 4, strategy + ": проходит первые волны")


func test_strategies_differ() -> void:
	var sums: Dictionary = {}
	for strategy: String in BotPlayer.BALANCE_STRATEGIES:
		sums[int(_play(strategy, 9)["checksum"])] = true
	assert_true(sums.size() >= 4, "стратегии играют по-разному")
