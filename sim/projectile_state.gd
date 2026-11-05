class_name ProjectileState
extends RefCounted
## Самонаводящийся снаряд. Урон рассчитан в момент выстрела, эффекты — при попадании.

var id: int = 0
var source_id: int = 0
var target_id: int = 0
var gem_id: String = ""
var quality: int = 1
var damage: float = 0.0
var damage_type: String = "physical"
var crit: bool = false
var speed: float = 10.0
var pos: Vector2 = Vector2.ZERO
var prev_pos: Vector2 = Vector2.ZERO
var target_pos: Vector2 = Vector2.ZERO
var target_flying: bool = false
var alive: bool = true
## Для спец-башен: уровень (0 — обычный гем) и сколько ещё целей пробьёт снаряд.
var special_level: int = 0
var pierce_left: int = 0
var hit_ids: Array[int] = []
## Номер выстрела башни (для «каждого N-го выстрела»).
var shot: int = 0
