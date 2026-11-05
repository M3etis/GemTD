class_name SpatialHash
extends RefCounted
## Корзины по клеткам для быстрого поиска врагов в радиусе. Порядок обхода детерминирован.

var bucket_size: float = 2.0
var _buckets: Dictionary = {}


func _init(size: float = 2.0) -> void:
	bucket_size = size


## Массивы корзин переиспользуются между тиками (без лишних аллокаций).
func clear() -> void:
	for a: Variant in _buckets.values():
		(a as Array).clear()


func _key(bx: int, by: int) -> int:
	return (bx + 1024) * 4096 + (by + 1024)


func insert(e: EnemyState) -> void:
	var k: int = _key(int(floorf(e.pos.x / bucket_size)), int(floorf(e.pos.y / bucket_size)))
	if not _buckets.has(k):
		_buckets[k] = []
	(_buckets[k] as Array).append(e)


func query(center: Vector2, radius: float, out: Array[EnemyState]) -> void:
	var r2: float = radius * radius
	var x0: int = int(floorf((center.x - radius) / bucket_size))
	var x1: int = int(floorf((center.x + radius) / bucket_size))
	var y0: int = int(floorf((center.y - radius) / bucket_size))
	var y1: int = int(floorf((center.y + radius) / bucket_size))
	for by: int in range(y0, y1 + 1):
		for bx: int in range(x0, x1 + 1):
			var k: int = _key(bx, by)
			if not _buckets.has(k):
				continue
			for e: EnemyState in _buckets[k]:
				if e.alive and e.pos.distance_squared_to(center) <= r2:
					out.append(e)
