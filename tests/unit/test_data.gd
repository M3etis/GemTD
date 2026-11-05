extends TestCase


func test_all_data_valid() -> void:
	var d: GameData = data()
	assert_true(d.is_valid(), "ошибки данных: %s" % str(d.errors))
	assert_eq(d.gem_ids.size(), 8)
	assert_eq(d.quality_count(), 5)
	assert_eq(d.max_luck(), 9)


func test_luck_chances_sum_to_100() -> void:
	var d: GameData = data()
	for lvl: int in range(1, d.max_luck() + 1):
		var sum: float = 0.0
		for c: Variant in d.luck_chances(lvl):
			sum += float(c)
		assert_near(sum, 100.0, 0.001, "удача %d" % lvl)


func test_schema_catches_errors() -> void:
	var schema: Dictionary = {"type": "object", "required": ["a"], "properties": {"a": {"type": "integer", "minimum": 1}}}
	assert_eq(JsonSchema.validate({"a": 2.0}, schema).size(), 0)
	assert_eq(JsonSchema.validate({}, schema).size(), 1)
	assert_eq(JsonSchema.validate({"a": 0}, schema).size(), 1)
	assert_eq(JsonSchema.validate({"a": 1.5}, schema).size(), 1)


func test_data_hash_stable() -> void:
	var a: GameData = GameData.new()
	a.load_from(GameData.DATA_DIR)
	var b: GameData = GameData.new()
	b.load_from(GameData.DATA_DIR)
	assert_eq(a.data_hash, b.data_hash)
	assert_ne(a.data_hash, 0)
