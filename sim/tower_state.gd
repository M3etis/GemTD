class_name TowerState
extends RefCounted
## Башня на поле: базовый гем или спец-башня. Только данные и производные статы.

const TARGETING_MODES: Array[String] = ["first", "last", "strongest", "weakest", "flying"]
## Эффекты спец-башен, силу которых слитая башня наследует; радиусы, шансы, длительности и счётчики — свои.
const MERGE_STRENGTH_KEYS: Array[String] = ["burn_dps", "pool_dps", "aura_attack_speed", "aura_range", "aura_damage", "aura_speed",
	"slow", "pool_slow", "debuff_slow", "armor_reduction", "bounty_bonus", "wave_gold", "vuln", "mark", "hp_pct"]

var id: int = 0
var cell: Vector2i = Vector2i.ZERO
var pos: Vector2 = Vector2.ZERO
var gem_id: String = ""
var quality: int = 1
## Спец-башня: id из specials.json и уровень 1..3. Пусто — обычный гем.
var special_id: String = ""
var level: int = 1
## Слитая спец-башня (две одинаковые → одна): уровень второй башни на момент слияния, 0 — не слита.
## Урон и сила эффектов — свои + economy.special_merge.inherit × этого уровня; прокачка поднимает только
## свою часть. Сливается только один раз.
var merge_level: int = 0
## Слейт (data/slates.json): плита на земле, путь не перекрывает. Хранится в GameSim.slates, не в towers.
var slate_id: String = ""
## Сколько раз перекладывали этот слейт (перекладывать можно сколько угодно — цена растёт, см. SlateCommands).
var moves: int = 0
## Призрачный слейт: подряд попаданий по одной цели (каждое следующее сильнее).
var stack_target: int = -1
var stack_hits: int = 0
var created_round: int = 0

var damage: float = 0.0
var attack_speed: float = 1.0
var base_range: float = 3.0
var attack_range: float = 3.0
var damage_type: String = "physical"
var hits_ground: bool = true
var hits_air: bool = true
var projectile: String = "bolt"
var projectile_speed: float = 10.0
## projectile | lightning | none | aura_damage | aura_slow
var attack_kind: String = "projectile"

var aura_speed_bonus: float = 0.0
var aura_range_bonus: float = 0.0
var aura_damage_bonus: float = 0.0
var mvp: int = 0
var mvp_damage_per_stack: float = 0.0
## Огранка (economy.polish): уровень, за каждый +polish_damage_per_level урона. Золото на неё идёт в invested_gold.
var polish: int = 0
var polish_damage_per_level: float = 0.0
var merge_inherit: float = 0.0
var merge_max_slow: float = 1.0

var cooldown: float = 0.0
var flash_timer: float = 0.0
var attack_count: int = 0
var targeting: String = "first"
var enabled: bool = true
var invested_gold: int = 0
var total_damage: float = 0.0
var wave_damage: float = 0.0
## Урон по колоссу в Испытании урона.
var test_damage: float = 0.0
## Обезоруживание (трейт врага): до этого времени волны башня не атакует.
var disarmed_until: float = -1.0
var kills: int = 0


func setup(data: GameData, tower_id: int, at: Vector2i, gem: String, q: int, round_index: int) -> void:
	id = tower_id
	cell = at
	pos = BoardGrid.center(at)
	gem_id = gem
	quality = q
	created_round = round_index
	refresh_stats(data)


func setup_special(data: GameData, tower_id: int, at: Vector2i, special: String, round_index: int) -> void:
	id = tower_id
	cell = at
	pos = BoardGrid.center(at)
	special_id = special
	gem_id = ""
	quality = 0
	level = 1
	created_round = round_index
	refresh_stats(data)


func setup_slate(data: GameData, tower_id: int, at: Vector2i, slate: String, round_index: int) -> void:
	id = tower_id
	cell = at
	pos = BoardGrid.center(at)
	slate_id = slate
	gem_id = ""
	quality = 0
	created_round = round_index
	refresh_stats(data)


func is_special() -> bool:
	return not special_id.is_empty()


func is_slate() -> bool:
	return not slate_id.is_empty()


## Башня или слейт в другой клетке (перенос): позиция для поиска целей и аур.
func move_to(at: Vector2i) -> void:
	cell = at
	pos = BoardGrid.center(at)


## Идентификатор для визуала/звука: id слейта, спец-башни или гема.
func source_id() -> String:
	if is_slate():
		return slate_id
	return special_id if is_special() else gem_id


func refresh_stats(data: GameData) -> void:
	mvp_damage_per_stack = float(data.economy["mvp"]["damage_per_stack"])
	polish_damage_per_level = float(data.economy["polish"]["damage_per_level"])
	merge_inherit = float(data.economy["special_merge"]["inherit"])
	merge_max_slow = float(data.economy["special_merge"]["max_slow"])
	if is_slate():
		var sl: Dictionary = data.slate(slate_id)
		damage = float(sl["damage"])
		attack_speed = 1.0 / float(sl["interval"])
		base_range = float(sl["radius"])
		damage_type = sl["damage_type"]
		hits_ground = sl["targets"] != "air"
		hits_air = sl["targets"] != "ground"
		projectile = "none"
		attack_kind = "slate"
	elif is_special():
		var sp: Dictionary = data.special(special_id)
		var lv: Dictionary = data.special_level(special_id, level)
		damage = float(lv["damage"])
		if merge_level > 0:
			damage += merge_inherit * float(data.special_level(special_id, merge_level)["damage"])
		attack_speed = float(lv["attack_speed"])
		base_range = float(lv["range"])
		damage_type = sp["damage_type"]
		var targets: String = sp["targets"]
		hits_ground = targets != "air"
		hits_air = targets != "ground"
		projectile = sp["projectile"]
		projectile_speed = float(sp["projectile_speed"])
		attack_kind = sp["attack"]
	else:
		var g: Dictionary = data.gem(gem_id)
		var ql: Dictionary = data.quality(quality)
		damage = float(g["base_damage"]) * float(ql["damage_mult"])
		attack_speed = float(g["attack_speed"]) * float(ql["speed_mult"])
		base_range = float(g["range"]) + float(ql["range_bonus"])
		damage_type = g["damage_type"]
		var targets2: String = g["targets"]
		hits_ground = targets2 != "air"
		hits_air = targets2 != "ground"
		projectile = g["projectile"]
		projectile_speed = float(g["projectile_speed"])
		attack_kind = "lightning" if projectile == "lightning" else "projectile"
	attack_range = base_range + aura_range_bonus


func is_merged() -> bool:
	return merge_level > 0


## Сила эффекта спец-башни: своя, у слитой — плюс inherit × унаследованного уровня
## (замедления — не выше economy.special_merge.max_slow).
func strength(data: GameData, key: String, fallback: Variant = 0.0) -> float:
	var own: float = float(data.special_effect(special_id, key, level, fallback))
	if merge_level <= 0 or not MERGE_STRENGTH_KEYS.has(key):
		return own
	var total: float = own + merge_inherit * float(data.special_effect(special_id, key, merge_level, fallback))
	if key.ends_with("slow"):
		return maxf(own, minf(total, merge_max_slow))
	return total


## Наносит ли башня урон, к которому применяется damage_mult() (MVP, огранка, ауры урона). Нет — у башен
## поддержки: Маяк-Линза и Боевое знамя (attack "none") только усиливают соседей, Морозный Колодец — замедляет.
func deals_damage() -> bool:
	return not is_slate() and attack_kind != "none" and attack_kind != "aura_slow"


func damage_mult() -> float:
	return 1.0 + float(mvp) * mvp_damage_per_stack + float(polish) * polish_damage_per_level + aura_damage_bonus


func effective_damage() -> float:
	return damage * damage_mult()


func effective_attack_speed() -> float:
	return attack_speed * (1.0 + aura_speed_bonus)


## Стоимость при продаже до коэффициента возврата.
func base_value(data: GameData) -> int:
	if is_slate():
		return int(data.slate(slate_id)["value"])
	if is_special():
		return int(data.special(special_id)["value"]) * (2 if is_merged() else 1) + invested_gold
	return data.gem_value(quality) + invested_gold


func sell_value(data: GameData) -> int:
	return int(floorf(float(base_value(data)) * float(data.economy["sell_refund"])))


## Грубая оценка DPS для UI и бота (без учёта брони).
static func estimate_dps(data: GameData, gem: String, q: int, vs_air: bool = false) -> float:
	var g: Dictionary = data.gem(gem)
	var ql: Dictionary = data.quality(q)
	var dmg: float = float(g["base_damage"]) * float(ql["damage_mult"])
	var aps: float = float(g["attack_speed"]) * float(ql["speed_mult"])
	var mult: float = 1.0
	match gem:
		"sapphire":
			var jumps: int = int(data.gem_effect(gem, "chain_targets", q, 1))
			var falloff: float = float(data.gem_effect(gem, "chain_falloff", q, 1.0))
			var sum: float = 0.0
			var f: float = 1.0
			for i: int in jumps:
				sum += f
				f *= falloff
			mult = 1.0 + (sum - 1.0) * 0.5
		"emerald":
			var stacks: float = float(data.gem_effect(gem, "poison_max_stacks", q, 1))
			mult = 1.0 + float(data.gem_effect(gem, "poison_dps", q, 0.0)) * stacks / maxf(dmg * aps, 0.001)
		"topaz":
			mult = 1.6
		"amethyst":
			if vs_air:
				mult = float(data.gem_effect(gem, "air_mult", q, 1.0))
		"diamond":
			var cc: float = float(data.gem_effect(gem, "crit_chance", q, 0.0))
			var cm: float = float(data.gem_effect(gem, "crit_mult", q, 1.0))
			mult = 1.0 + cc * (cm - 1.0)
		"ruby":
			var every: int = int(data.gem_effect(gem, "empowered_every", q, 0))
			if every > 0:
				mult = 1.0 + (float(data.gem_effect(gem, "empowered_mult", q, 1.0)) - 1.0) / float(every)
	if vs_air and g["targets"] == "ground":
		return 0.0
	return dmg * aps * mult


## Оценка DPS спец-башни (по одной цели; ауры — по одной цели в радиусе).
static func estimate_special_dps(data: GameData, special: String, lvl: int, vs_air: bool = false) -> float:
	var sp: Dictionary = data.special(special)
	var lv: Dictionary = data.special_level(special, lvl)
	if vs_air and sp["targets"] == "ground":
		return 0.0
	match String(sp["attack"]):
		"aura_damage":
			return float(data.special_effect(special, "burn_dps", lvl, 0.0))
		"projectile":
			var base: float = float(lv["damage"]) * float(lv["attack_speed"])
			if special == "skypiercer":
				base *= float(data.special_effect(special, "air_mult" if vs_air else "ground_mult", lvl, 1.0))
			if special == "blightbloom":
				base += float(data.special_effect(special, "pool_dps", lvl, 0.0)) * 1.5
			return base
	return 0.0
