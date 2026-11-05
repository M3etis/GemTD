class_name DamageCalc
extends RefCounted
## Формулы урона: матрица тип урона × тип брони и снижение от значения брони.


static func armor_factor(data: GameData, armor: float) -> float:
	if armor >= 0.0:
		var k: float = data.armor_k
		return 1.0 - (k * armor) / (1.0 + k * armor)
	return 2.0 - pow(data.armor_negative_base, -armor)


static func final_damage(data: GameData, base: float, dtype: String, armor_type: String, armor: float, armor_ignore: float = 0.0) -> float:
	if dtype == "pure":
		return base
	var a: float = armor
	if a > 0.0:
		a = maxf(0.0, a - armor_ignore)
	return base * data.damage_mult(dtype, armor_type) * armor_factor(data, a)
