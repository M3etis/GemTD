class_name EnemyState
extends RefCounted
## Враг на маршруте. Позиция задаётся расстоянием вдоль пути (наземного или воздушного).
## Трейты и способности боссов обрабатывает EnemyTraits.

var id: int = 0
var archetype: String = ""
var max_hp: float = 1.0
var hp: float = 1.0
var armor: float = 0.0
var armor_type: String = "medium"
var base_speed: float = 2.0
var flying: bool = false
var boss: bool = false
var elite: bool = false
## Босс финальной волны забега (усилен по waves.json → lengths) — полоса HP подписывает его «Финал».
var finale: bool = false
var immortal: bool = false
var bounty: int = 0
var leak_damage: int = 1
var size: float = 0.3

var dist: float = 0.0
var seg: int = 0
var pos: Vector2 = Vector2.ZERO
var prev_pos: Vector2 = Vector2.ZERO
var heading: float = 0.0
var alive: bool = true
var leaked: bool = false

var slow_pct: float = 0.0
var slow_until: float = -1.0
## Стаки яда: {dps, until, source, spread}
var poison: Array[Dictionary] = []
var last_hit_time: float = -10.0
var stun_until: float = -1.0
var vuln_pct: float = 0.0
var vuln_until: float = -1.0
## Последнее отравление лужей Blightbloom: до какого времени и от какой башни.
var blight_until: float = -1.0
var blight_source: int = -1

# --- Трейты (traits.json) и свойства архетипа ---------------------------------
## Набор трейтов: id → true.
var traits: Dictionary = {}
## Сопротивления по типам урона: dtype → множитель.
var resist: Dictionary = {}
## Типы урона, к которым враг неуязвим (Антимагия, Эфирность).
var immune: Dictionary = {}
## Иммунитет к контролю: замедление, оглушение, притяжение.
var cc_immune: bool = false
var shield: float = 0.0
var max_shield: float = 0.0
## Регенерация: доля макс. HP в секунду (трейт + фаза босса).
var regen_pct: float = 0.0
var evasion: float = 0.0
var evasion_types: Dictionary = {}
var refraction: int = 0
var hardening_hits: int = 0
var hardening_bonus: float = 0.0
var carapace_block: float = 0.0
var carapace_next: float = 0.0
var rush_used: bool = false
var rush_until: float = -1.0
var blink_next: float = -1.0
var disarm_next: float = -1.0
var thief_gold: int = 0
## Покров: невидим, пока рядом нет обнаружителя. visible пересчитывается каждый тик.
var shrouded: bool = false
var visible: bool = true
## Покров: после любого урона враг проявляется до этого времени.
var revealed_until: float = -1.0
## Ускорение фазы босса.
var speed_mult: float = 1.0
var phase_index: int = 0
var phases: Array = []
var summon: Dictionary = {}
var summon_next: float = -1.0
var split: Dictionary = {}
## Gilded Idol L3: «золотой» враг даёт ×N награды.
var golden: bool = false
var golden_mult: float = 1.0
## Снижение брони аурой Rust Obelisk (действует, пока враг в ауре).
var shred: float = 0.0
var shred_until: float = -1.0
## Снижение брони на время (оглушение Древнего слейта, заклинание Руин) — отдельно от ауры:
## действует сильнейшее из двух, и аура не обрывает его раньше срока.
var timed_shred: float = 0.0
var timed_shred_until: float = -1.0
## Замедление «до смерти» (Замедляющий слейт) — отдельно от временного: действует сильнейшее из двух,
## поэтому временное замедление его не перезаписывает. Снимается только очищением (Антимагия).
var slow_floor: float = 0.0
## Метка Razor Prism L3: +X % получаемого урона.
var mark_pct: float = 0.0
var mark_until: float = -1.0
## Нужен ли врагу покадровый шаг трейтов (регенерация, рывок, мерцание, обезоруживание, панцирь, фазы, призыв).
var dynamic: bool = false
## Урон, полученный неуязвимым колоссом (Испытание урона).
var absorbed: float = 0.0


func has_trait(t: String) -> bool:
	return traits.has(t)


func current_slow(now: float) -> float:
	var s: float = slow_pct if now < slow_until else 0.0
	return maxf(s, slow_floor) if slow_floor > 0.0 else s


func apply_slow(pct: float, until: float, now: float) -> void:
	if cc_immune:
		return
	if now >= slow_until or pct > slow_pct:
		slow_pct = pct
		slow_until = until
	elif is_equal_approx(pct, slow_pct):
		slow_until = maxf(slow_until, until)


func apply_permanent_slow(pct: float) -> void:
	if not cc_immune:
		slow_floor = maxf(slow_floor, pct)


## Снижение брони на время: сильнее — заменяет, такое же — продлевает.
func apply_timed_shred(value: float, until: float, now: float) -> void:
	if now >= timed_shred_until or value > timed_shred:
		timed_shred = value
		timed_shred_until = until
	elif is_equal_approx(value, timed_shred):
		timed_shred_until = maxf(timed_shred_until, until)


func stun(until: float) -> bool:
	if cc_immune:
		return false
	stun_until = maxf(stun_until, until)
	return true


func is_stunned(now: float) -> bool:
	return now < stun_until


func effective_armor(now: float) -> float:
	var s: float = shred if now < shred_until else 0.0
	if now < timed_shred_until:
		s = maxf(s, timed_shred)
	return armor + hardening_bonus - s


## Множитель получаемого урона от дебаффов (уязвимость Skypiercer, метка Razor Prism).
func damage_taken_mult(now: float) -> float:
	var m: float = 1.0
	if now < vuln_until:
		m *= 1.0 + vuln_pct
	if now < mark_until:
		m *= 1.0 + mark_pct
	return m


func current_speed(now: float) -> float:
	if is_stunned(now):
		return 0.0
	var spd: float = base_speed * speed_mult * (1.0 - current_slow(now))
	if now < rush_until:
		spd *= 2.0
	return spd


## Сдвиг по пути; true — дошёл до конца.
func advance(dt: float, now: float, points: PackedVector2Array, cum: PackedFloat64Array) -> bool:
	dist += current_speed(now) * dt
	prev_pos = pos
	return place_on_path(points, cum)


## Пересчитывает позицию по dist (dist может уменьшиться — притяжение Gravity Geode).
func place_on_path(points: PackedVector2Array, cum: PackedFloat64Array) -> bool:
	var last: int = cum.size() - 1
	if last <= 0 or dist >= cum[last]:
		pos = points[last] if last >= 0 else pos
		return true
	dist = maxf(dist, 0.0)
	while seg > 0 and cum[seg] > dist:
		seg -= 1
	while seg < last - 1 and cum[seg + 1] <= dist:
		seg += 1
	var seg_len: float = cum[seg + 1] - cum[seg]
	var t: float = (dist - cum[seg]) / seg_len if seg_len > 0.0 else 0.0
	pos = points[seg].lerp(points[seg + 1], t)
	var d: Vector2 = points[seg + 1] - points[seg]
	if d.length_squared() > 0.0:
		heading = atan2(d.y, d.x)
	return false


func place_at_start(points: PackedVector2Array) -> void:
	dist = 0.0
	seg = 0
	pos = points[0]
	prev_pos = pos
	if points.size() > 1:
		var d: Vector2 = points[1] - points[0]
		heading = atan2(d.y, d.x)


## Для превью/UI: список трейтов в стабильном порядке.
func trait_list() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray(traits.keys())
	out.sort()
	return out
