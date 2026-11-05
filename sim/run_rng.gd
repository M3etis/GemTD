class_name RunRng
extends RefCounted
## Детерминированный ГПСЧ xoshiro128** с явным состоянием.
## Все случайные решения симуляции идут через него (см. §2 PROMPT.md).

const MASK32: int = 0xFFFFFFFF

var seed_value: int = 0
var _s0: int = 0
var _s1: int = 0
var _s2: int = 0
var _s3: int = 0


func _init(seed_in: int = 0) -> void:
	seed_value = seed_in & MASK32
	_seed_state(seed_value)


func _seed_state(x: int) -> void:
	var z: int = x & MASK32
	var out: Array[int] = []
	for i: int in 4:
		z = (z + 0x9E3779B9) & MASK32
		var t: int = z
		t = HashUtil.mul32(t ^ (t >> 16), 0x85EBCA6B)
		t = HashUtil.mul32(t ^ (t >> 13), 0xC2B2AE35)
		t ^= t >> 16
		out.append(t & MASK32)
	_s0 = out[0]
	_s1 = out[1]
	_s2 = out[2]
	_s3 = out[3]
	if (_s0 | _s1 | _s2 | _s3) == 0:
		_s0 = 1


static func _rotl(x: int, k: int) -> int:
	return ((x << k) | ((x & MASK32) >> (32 - k))) & MASK32


func next_u32() -> int:
	var result: int = HashUtil.mul32(_rotl(HashUtil.mul32(_s1, 5), 7), 9)
	var t: int = (_s1 << 9) & MASK32
	_s2 ^= _s0
	_s3 ^= _s1
	_s1 ^= _s2
	_s0 ^= _s3
	_s2 ^= t
	_s3 = _rotl(_s3, 11)
	return result


## Равномерное [0, 1).
func next_float() -> float:
	return float(next_u32()) / 4294967296.0


func range_int(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + int(floorf(next_float() * float(hi - lo + 1)))


func range_float(lo: float, hi: float) -> float:
	return lo + (hi - lo) * next_float()


func chance(p: float) -> bool:
	return next_float() < p


## Индекс по весам (веса >= 0). Возвращает -1, если сумма весов 0.
func pick_weighted(weights: Array) -> int:
	var total: float = 0.0
	for w: Variant in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return -1
	var r: float = next_float() * total
	for i: int in weights.size():
		r -= maxf(0.0, float(weights[i]))
		if r < 0.0:
			return i
	return weights.size() - 1


## Независимый под-поток: одинаковые (seed, stream, a, b) всегда дают одинаковую последовательность.
func fork(stream: String, a: int = 0, b: int = 0) -> RunRng:
	var h: int = HashUtil.combine(seed_value, HashUtil.fnv1a_str(stream))
	h = HashUtil.combine(h, a)
	h = HashUtil.combine(h, b)
	return RunRng.new(h)


func get_state() -> Array[int]:
	return [seed_value, _s0, _s1, _s2, _s3]


func set_state(state: Array) -> void:
	seed_value = int(state[0])
	_s0 = int(state[1])
	_s1 = int(state[2])
	_s2 = int(state[3])
	_s3 = int(state[4])


func state_hash() -> int:
	var h: int = HashUtil.combine(_s0, _s1)
	h = HashUtil.combine(h, _s2)
	return HashUtil.combine(h, _s3)


## Seed из пользовательской строки: число — как есть, иначе стабильный хеш.
static func seed_from_text(text: String) -> int:
	var t: String = text.strip_edges()
	if t.is_empty():
		return 0
	# Формат отображения — 8 hex-символов; его парсим в первую очередь, чтобы «скопировать seed» работало.
	if t.length() == 8 and t.is_valid_hex_number(false):
		return t.hex_to_int() & MASK32
	if t.is_valid_int():
		return int(t) & MASK32
	return HashUtil.mix32(HashUtil.fnv1a_str(t))


static func seed_to_text(s: int) -> String:
	return "%08X" % (s & MASK32)


static func daily_seed(date_iso: String) -> int:
	return HashUtil.mix32(HashUtil.fnv1a_str("daily-" + date_iso))
