class_name HashUtil
extends RefCounted
## Стабильные 32-битные хеши и умножение без переполнения int64.
## Не используем String.hash(): его реализация может поменяться между версиями Godot,
## а seed и реплеи должны оставаться совместимыми.

const MASK32: int = 0xFFFFFFFF


static func mul32(a: int, b: int) -> int:
	a &= MASK32
	b &= MASK32
	var a_lo: int = a & 0xFFFF
	var a_hi: int = a >> 16
	var b_lo: int = b & 0xFFFF
	var b_hi: int = b >> 16
	var cross: int = (a_hi * b_lo + a_lo * b_hi) & 0xFFFF
	return (a_lo * b_lo + (cross << 16)) & MASK32


static func mix32(h: int) -> int:
	h &= MASK32
	h ^= h >> 16
	h = mul32(h, 0x85EBCA6B)
	h ^= h >> 13
	h = mul32(h, 0xC2B2AE35)
	h ^= h >> 16
	return h


static func combine(h: int, v: int) -> int:
	var mixed: int = (mix32(v) + 0x9E3779B9 + ((h << 6) & MASK32) + ((h & MASK32) >> 2)) & MASK32
	return mix32((h & MASK32) ^ mixed)


static func fnv1a_bytes(bytes: PackedByteArray, h: int = 0x811C9DC5) -> int:
	for b: int in bytes:
		h ^= b
		h = mul32(h, 0x01000193)
	return h


static func fnv1a_str(s: String) -> int:
	return fnv1a_bytes(s.to_utf8_buffer())


## Квантование float для контрольных сумм: детерминированно на одной сборке.
static func q(x: float, scale: float = 1000.0) -> int:
	return int(roundf(x * scale)) & MASK32
