extends TestCase


func test_mul32_matches_reference() -> void:
	assert_eq(HashUtil.mul32(0xFFFFFFFF, 0xFFFFFFFF), 1)
	assert_eq(HashUtil.mul32(0x12345678, 0x9ABCDEF0), (0x12345678 * 0x9ABCDEF0) & 0xFFFFFFFF)
	assert_eq(HashUtil.mul32(3, 5), 15)


func test_same_seed_same_sequence() -> void:
	var a: RunRng = RunRng.new(12345)
	var b: RunRng = RunRng.new(12345)
	for i: int in 1000:
		assert_eq(a.next_u32(), b.next_u32())


func test_different_seeds_differ() -> void:
	var a: RunRng = RunRng.new(1)
	var b: RunRng = RunRng.new(2)
	var same: int = 0
	for i: int in 100:
		if a.next_u32() == b.next_u32():
			same += 1
	assert_true(same < 3, "последовательности почти совпали")


func test_fork_independent_of_parent_usage() -> void:
	var a: RunRng = RunRng.new(777)
	var b: RunRng = RunRng.new(777)
	for i: int in 50:
		b.next_u32()
	var fa: RunRng = a.fork("draft", 3, 1)
	var fb: RunRng = b.fork("draft", 3, 1)
	assert_eq(fa.next_u32(), fb.next_u32(), "fork не должен зависеть от потребления родителя")
	assert_ne(a.fork("draft", 3, 1).next_u32(), a.fork("draft", 3, 2).next_u32())
	assert_ne(a.fork("draft", 3, 1).next_u32(), a.fork("combat", 3, 1).next_u32())


func test_float_range_and_distribution() -> void:
	var r: RunRng = RunRng.new(99)
	var buckets: Array[int] = [0, 0, 0, 0]
	for i: int in 20000:
		var f: float = r.next_float()
		assert_true(f >= 0.0 and f < 1.0)
		buckets[int(f * 4.0)] += 1
	for c: int in buckets:
		assert_true(c > 4500 and c < 5500, "перекос распределения: %s" % str(buckets))


func test_state_roundtrip() -> void:
	var a: RunRng = RunRng.new(5)
	for i: int in 10:
		a.next_u32()
	var b: RunRng = RunRng.new(0)
	b.set_state(a.get_state())
	assert_eq(a.next_u32(), b.next_u32())


func test_seed_text_roundtrip() -> void:
	var s: int = 0x0001E240
	assert_eq(RunRng.seed_from_text(RunRng.seed_to_text(s)), s)
	assert_eq(RunRng.seed_from_text("00012345"), 0x12345)
	assert_eq(RunRng.seed_from_text("42"), 42)
	assert_eq(RunRng.seed_from_text("hello"), RunRng.seed_from_text("hello"))
	assert_eq(RunRng.daily_seed("2026-10-27"), RunRng.daily_seed("2026-10-27"))
	assert_ne(RunRng.daily_seed("2026-10-27"), RunRng.daily_seed("2026-10-28"))
