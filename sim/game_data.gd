class_name GameData
extends RefCounted
## Загрузка и валидация всех балансовых данных из res://data.
## Симуляция читает числа только отсюда (инвариант §2.4).

const DATA_DIR: String = "res://data"
const FILES: Dictionary = {
	"gems": "gems.json",
	"qualities": "qualities.json",
	"damage": "damage_matrix.json",
	"enemies": "enemies.json",
	"waves": "waves.json",
	"economy": "economy.json",
	"difficulty": "difficulty.json",
	"scoring": "scoring.json",
	"specials": "specials.json",
	"traits": "traits.json",
	"slates": "slates.json",
}
const SCHEMAS: Dictionary = {
	"gems": "gems.schema.json",
	"qualities": "qualities.schema.json",
	"damage": "damage_matrix.schema.json",
	"enemies": "enemies.schema.json",
	"waves": "waves.schema.json",
	"economy": "economy.schema.json",
	"difficulty": "difficulty.schema.json",
	"scoring": "scoring.schema.json",
	"specials": "specials.schema.json",
	"traits": "traits.schema.json",
	"slates": "slates.schema.json",
}
const MAP_FILES: Dictionary = {"arena_01": "maps/arena_01.json"}
## Эффекты слейтов, которым нужны парные числа (SlateCombat и SlateText читают их без запасных значений).
const SLATE_EFFECT_NEEDS: Dictionary = {
	"poison_dps": ["poison_duration"],
	"spell_chance": ["spell_damage", "spell_radius"],
	"spell_gold": ["spell_chance", "spell_armor", "spell_armor_duration", "spell_slow", "spell_slow_duration", "spell_damage", "spell_radius"],
	"level_every_kills": ["level_damage", "max_levels"],
	"armor_reduction": ["stun"],
	"aura_speed": ["aura_radius"],
	"aura_damage": ["aura_radius"],
}

static var _cache: GameData = null

var raw: Dictionary = {}
var errors: PackedStringArray = PackedStringArray()
var data_hash: int = 0

var gems: Array[Dictionary] = []
var gem_by_id: Dictionary = {}
var gem_ids: PackedStringArray = PackedStringArray()
var quality_levels: Array = []
var luck_levels: Array = []
var damage_types: PackedStringArray = PackedStringArray()
var armor_types: PackedStringArray = PackedStringArray()
var damage_matrix: Dictionary = {}
var damage_colors: Dictionary = {}
var armor_k: float = 0.06
var armor_negative_base: float = 0.94
var archetypes: Dictionary = {}
var waves: Array = []
var waves_cfg: Dictionary = {}
var economy: Dictionary = {}
var difficulty_levels: Dictionary = {}
var difficulty_order: PackedStringArray = PackedStringArray()
var default_difficulty: String = "normal"
var scoring: Dictionary = {}
var maps: Dictionary = {}
var specials: Array[Dictionary] = []
var special_by_id: Dictionary = {}
var special_ids: PackedStringArray = PackedStringArray()
var traits: Dictionary = {}
var trait_rules: Dictionary = {}
## Слейты (Gem TD 3.2): плиты на земле — базовые из двух гемов раунда, составные из двух базовых.
var slates: Array[Dictionary] = []
var slate_by_id: Dictionary = {}
## Бесконечный режим: средний «вес» HP волн второго акта по видам (ground / air / boss), см. endless_hp_norm.
var _endless_ref: Dictionary = {}


static func load_default() -> GameData:
	if _cache == null:
		var d: GameData = GameData.new()
		d.load_from(DATA_DIR)
		_cache = d
	return _cache


static func clear_cache() -> void:
	_cache = null


func is_valid() -> bool:
	return errors.is_empty()


func load_from(dir: String) -> bool:
	errors.clear()
	raw.clear()
	var hash_h: int = 0x811C9DC5
	var names: Array = FILES.keys()
	names.sort()
	for name: String in names:
		var text: String = _read_text("%s/%s" % [dir, FILES[name]])
		hash_h = HashUtil.fnv1a_str(text) ^ HashUtil.mix32(hash_h)
		raw[name] = _parse(text, FILES[name])
		var schema_text: String = _read_text("%s/schema/%s" % [dir, SCHEMAS[name]])
		if raw[name] is Dictionary and not schema_text.is_empty():
			var schema: Variant = JSON.parse_string(schema_text)
			if schema is Dictionary:
				for e: String in JsonSchema.validate(raw[name], schema, FILES[name]):
					errors.append(e)
	var map_schema: Variant = JSON.parse_string(_read_text("%s/schema/map.schema.json" % dir))
	for map_id: String in MAP_FILES.keys():
		var text: String = _read_text("%s/%s" % [dir, MAP_FILES[map_id]])
		hash_h = HashUtil.fnv1a_str(text) ^ HashUtil.mix32(hash_h)
		var m: Variant = _parse(text, MAP_FILES[map_id])
		if m is Dictionary:
			if map_schema is Dictionary:
				for e: String in JsonSchema.validate(m, map_schema, MAP_FILES[map_id]):
					errors.append(e)
			maps[map_id] = m
	data_hash = HashUtil.mix32(hash_h)
	if errors.is_empty():
		_index()
		_cross_validate()
	for e: String in errors:
		push_error("[data] " + e)
	return errors.is_empty()


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		errors.append("файл не найден: " + path)
		return ""
	return FileAccess.get_file_as_string(path)


func _parse(text: String, label: String) -> Variant:
	if text.is_empty():
		return null
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		errors.append("%s:%d: %s" % [label, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _index() -> void:
	gems.clear()
	gem_by_id.clear()
	gem_ids.clear()
	for g: Dictionary in raw["gems"]["gems"]:
		gems.append(g)
		gem_by_id[g["id"]] = g
		gem_ids.append(g["id"])
	quality_levels = raw["qualities"]["levels"]
	luck_levels = raw["qualities"]["luck_levels"]
	var dm: Dictionary = raw["damage"]
	damage_types = PackedStringArray(dm["damage_types"])
	armor_types = PackedStringArray(dm["armor_types"])
	damage_matrix = dm["matrix"]
	damage_colors = dm["colors"]
	armor_k = float(dm["armor_formula"]["k"])
	armor_negative_base = float(dm["armor_formula"]["negative_base"])
	archetypes = raw["enemies"]["archetypes"]
	waves_cfg = raw["waves"]
	waves = raw["waves"]["waves"]
	economy = raw["economy"]
	difficulty_levels.clear()
	difficulty_order.clear()
	for lvl: Dictionary in raw["difficulty"]["levels"]:
		difficulty_levels[lvl["id"]] = lvl
		difficulty_order.append(lvl["id"])
	default_difficulty = raw["difficulty"]["default"]
	scoring = raw["scoring"]
	specials.clear()
	special_by_id.clear()
	special_ids.clear()
	for sp: Dictionary in raw["specials"]["specials"]:
		specials.append(sp)
		special_by_id[sp["id"]] = sp
		special_ids.append(sp["id"])
	traits = raw["traits"]["traits"]
	trait_rules = raw["traits"]["rules"]
	slates.clear()
	slate_by_id.clear()
	for sl: Dictionary in raw["slates"]["slates"]:
		slates.append(sl)
		slate_by_id[sl["id"]] = sl
	_endless_ref.clear()
	var sums: Dictionary = {}
	var counts: Dictionary = {}
	for n: int in range(maxi(1, int(waves_cfg["endless"]["ref_from_wave"])), waves.size() + 1):
		var kind: String = wave_kind(n)
		sums[kind] = float(sums.get(kind, 0.0)) + wave_weight(n)
		counts[kind] = int(counts.get(kind, 0)) + 1
	for kind: String in sums.keys():
		_endless_ref[kind] = float(sums[kind]) / float(counts[kind])


func _cross_validate() -> void:
	var qn: int = quality_levels.size()
	for g: Dictionary in gems:
		if not damage_matrix.has(g["damage_type"]):
			errors.append("gems.json: %s: тип урона %s нет в матрице" % [g["id"], g["damage_type"]])
		for key: String in (g["effects"] as Dictionary).keys():
			var v: Variant = g["effects"][key]
			if v is Array and (v as Array).size() != qn:
				errors.append("gems.json: %s.effects.%s: нужно %d значений (по числу качеств)" % [g["id"], key, qn])
	for dt: String in damage_types:
		if not damage_matrix.has(dt):
			errors.append("damage_matrix.json: нет строки для %s" % dt)
			continue
		for at: String in armor_types:
			if not (damage_matrix[dt] as Dictionary).has(at):
				errors.append("damage_matrix.json: нет значения %s × %s" % [dt, at])
	for id: String in archetypes.keys():
		var a: Dictionary = archetypes[id]
		if not armor_types.has(a["armor_type"]):
			errors.append("enemies.json: %s: неизвестный тип брони" % id)
		for t: String in a["traits"]:
			if not traits.has(t):
				errors.append("enemies.json: %s: неизвестный трейт %s" % [id, t])
		for dt: String in (a["resist"] as Dictionary).keys():
			if not damage_matrix.has(dt):
				errors.append("enemies.json: %s: сопротивление неизвестному типу урона %s" % [id, dt])
		var split: Dictionary = a["split"]
		if not split.is_empty() and not archetypes.has(split.get("type", "")):
			errors.append("enemies.json: %s: split ссылается на неизвестного врага" % id)
		var summon: Dictionary = (a["abilities"] as Dictionary).get("summon", {})
		for st: Variant in summon.get("types", []):
			if not archetypes.has(String(st)):
				errors.append("enemies.json: %s: призыв неизвестного врага %s" % [id, st])
	for t: String in traits.keys():
		for dt: String in traits[t].get("immune", []):
			if not damage_matrix.has(dt):
				errors.append("traits.json: %s: иммунитет к неизвестному типу урона %s" % [t, dt])
	for lvl: Dictionary in luck_levels:
		if (lvl["chances"] as Array).size() != qn:
			errors.append("qualities.json: удача %d: нужно %d шансов" % [int(lvl["level"]), qn])
	if (economy["luck_upgrade_costs"] as Array).size() != luck_levels.size() - 1:
		errors.append("economy.json: luck_upgrade_costs должен содержать %d значений" % (luck_levels.size() - 1))
	if (economy["gem_value"] as Array).size() != qn:
		errors.append("economy.json: gem_value должен содержать %d значений" % qn)
	var recipe_keys: Dictionary = {}
	for sp: Dictionary in specials:
		if not damage_matrix.has(sp["damage_type"]):
			errors.append("specials.json: %s: неизвестный тип урона" % sp["id"])
		var parts: PackedStringArray = PackedStringArray()
		for comp: Dictionary in sp["recipe"]:
			if not gem_by_id.has(comp["gem"]):
				errors.append("specials.json: %s: неизвестный гем %s" % [sp["id"], comp["gem"]])
			if int(comp["quality"]) > qn:
				errors.append("specials.json: %s: качество %d больше максимума" % [sp["id"], int(comp["quality"])])
			parts.append("%s:%d" % [comp["gem"], int(comp["quality"])])
		parts.sort()
		var key: String = ",".join(parts)
		if recipe_keys.has(key):
			errors.append("specials.json: рецепты %s и %s совпадают" % [recipe_keys[key], sp["id"]])
		recipe_keys[key] = sp["id"]
		for up: Dictionary in sp["upgrades"]:
			if not String(up["gem"]).is_empty() and not gem_by_id.has(up["gem"]):
				errors.append("specials.json: %s: улучшение требует неизвестный гем %s" % [sp["id"], up["gem"]])
	_validate_slates(qn)
	var lengths: Array = waves_cfg["lengths"]["options"]
	var seen_lengths: Dictionary = {}
	for opt: Dictionary in lengths:
		var lw: int = int(opt["waves"])
		if lw > waves.size():
			errors.append("waves.json: lengths: %d волн — больше, чем волн в игре (%d)" % [lw, waves.size()])
		if seen_lengths.has(lw):
			errors.append("waves.json: lengths: длина %d повторяется" % lw)
		seen_lengths[lw] = true
	if not seen_lengths.has(int(waves_cfg["lengths"]["default"])):
		errors.append("waves.json: lengths.default нет среди options")
	var air_every: int = int(waves_cfg["air_every"])
	for i: int in waves.size():
		var w: Dictionary = waves[i]
		if int(w["id"]) != i + 1:
			errors.append("waves.json: волны должны идти по порядку с 1 (позиция %d)" % (i + 1))
		var all_flying: bool = true
		var has_boss: bool = false
		for grp: Dictionary in w["groups"]:
			if not archetypes.has(grp["type"]):
				errors.append("waves.json: волна %d: неизвестный враг %s" % [i + 1, grp["type"]])
				continue
			all_flying = all_flying and bool(archetypes[grp["type"]]["flying"])
			for t: String in grp.get("traits", []):
				if not traits.has(t):
					errors.append("waves.json: волна %d: неизвестный трейт %s" % [i + 1, t])
			has_boss = has_boss or bool(archetypes[grp["type"]]["boss"])
		var is_air: bool = (i + 1) % air_every == 0
		if is_air and not all_flying and not has_boss:
			errors.append("waves.json: волна %d должна быть полностью воздушной" % (i + 1))
		if (waves_cfg["boss_waves"] as Array).has(float(i + 1)) and not has_boss:
			errors.append("waves.json: в волне %d нет босса" % (i + 1))


## Слейты: гемы и качества рецептов, составные — из двух разных базовых, рецепты не повторяются.
func _validate_slates(qn: int) -> void:
	var keys: Dictionary = {}
	for sl: Dictionary in slates:
		var id: String = String(sl["id"])
		if not damage_matrix.has(sl["damage_type"]):
			errors.append("slates.json: %s: неизвестный тип урона" % id)
		for miss: String in missing_slate_effects(sl["effects"]):
			errors.append("slates.json: %s: эффекту нужно поле %s" % [id, miss])
		if String(sl["kind"]) == "base":
			var main: Dictionary = sl["recipe"]
			if not gem_by_id.has(main["gem"]) or int(main["quality"]) < 1 or int(main["quality"]) > qn:
				errors.append("slates.json: %s: неверный основной гем" % id)
			if (sl["partners"] as Array).is_empty() or not (sl["from"] as Array).is_empty():
				errors.append("slates.json: %s: базовому нужны partners и пустой from" % id)
			for p: Dictionary in sl["partners"]:
				if not gem_by_id.has(p["gem"]) or int(p["quality"]) > qn:
					errors.append("slates.json: %s: неверный гем-пара %s" % [id, p["gem"]])
				var k2: String = "%s:%d+%s:%d" % [main["gem"], int(main["quality"]), p["gem"], int(p["quality"])]
				if keys.has(k2):
					errors.append("slates.json: рецепты %s и %s совпадают" % [keys[k2], id])
				keys[k2] = id
			continue
		var from: Array = sl["from"]
		if from.size() != 2 or from[0] == from[1] or not (sl["partners"] as Array).is_empty():
			errors.append("slates.json: %s: составному нужны два разных from и пустые partners" % id)
			continue
		for f: Variant in from:
			if not slate_by_id.has(f) or String(slate_by_id[f]["kind"]) != "base":
				errors.append("slates.json: %s: from %s — не базовый слейт" % [id, f])
		var names: Array = from.duplicate()
		names.sort()
		var key: String = "+".join(names)
		if keys.has(key):
			errors.append("slates.json: рецепты %s и %s совпадают" % [keys[key], id])
		keys[key] = id


## Парные поля, которых не хватает эффектам слейта (пусто — всё на месте).
static func missing_slate_effects(effects: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k: String in SLATE_EFFECT_NEEDS.keys():
		if not effects.has(k):
			continue
		for need: String in SLATE_EFFECT_NEEDS[k]:
			if not effects.has(need) and not out.has(need):
				out.append(need)
	return out


# --- Доступ ---------------------------------------------------------------

func quality_count() -> int:
	return quality_levels.size()


func quality(level: int) -> Dictionary:
	return quality_levels[clampi(level, 1, quality_levels.size()) - 1]


func gem(id: String) -> Dictionary:
	return gem_by_id.get(id, {})


func gem_effect(id: String, key: String, quality_level: int, fallback: Variant = 0.0) -> Variant:
	var g: Dictionary = gem(id)
	if g.is_empty() or not (g["effects"] as Dictionary).has(key):
		return fallback
	var v: Variant = g["effects"][key]
	if v is Array:
		return (v as Array)[clampi(quality_level, 1, quality_count()) - 1]
	return v


func trait_cfg(id: String) -> Dictionary:
	return traits.get(id, {})


func archetype(id: String) -> Dictionary:
	return archetypes.get(id, {})


func special(id: String) -> Dictionary:
	return special_by_id.get(id, {})


func special_level(id: String, level: int) -> Dictionary:
	var sp: Dictionary = special(id)
	if sp.is_empty():
		return {}
	return (sp["levels"] as Array)[clampi(level, 1, 3) - 1]


func special_effect(id: String, key: String, level: int, fallback: Variant = 0.0) -> Variant:
	var lv: Dictionary = special_level(id, level)
	return (lv.get("effects", {}) as Dictionary).get(key, fallback)


func slate(id: String) -> Dictionary:
	return slate_by_id.get(id, {})


func slate_effect(id: String, key: String, fallback: Variant = 0.0) -> Variant:
	return (slate(id).get("effects", {}) as Dictionary).get(key, fallback)


func special_upgrade(id: String, to_level: int) -> Dictionary:
	for up: Dictionary in special(id).get("upgrades", []):
		if int(up["level"]) == to_level:
			return up
	return {}


func gem_value(quality: int) -> int:
	return int((economy["gem_value"] as Array)[clampi(quality, 1, quality_count()) - 1])


func max_luck() -> int:
	return luck_levels.size()


func luck_chances(level: int) -> Array:
	return luck_levels[clampi(level, 1, luck_levels.size()) - 1]["chances"]


func luck_roman(level: int) -> String:
	return luck_levels[clampi(level, 1, luck_levels.size()) - 1]["roman"]


## Стоимость перехода с уровня удачи level на level+1, -1 если максимум.
func luck_cost(level: int) -> int:
	var costs: Array = economy["luck_upgrade_costs"]
	if level < 1 or level > costs.size():
		return -1
	return int(costs[level - 1])


func difficulty(id: String) -> Dictionary:
	return difficulty_levels.get(id, difficulty_levels.get(default_difficulty, {}))


## Множитель HP сложности на волне n. С `hp_ramp_waves` он растёт от 1.0 на первой волне до `hp_mult`
## к волне hp_ramp_waves + 1: на старте у игрока одна-три башни I, и крепкие враги решали бы забег
## случайностью первых камней, а не игрой. Без поля — сразу `hp_mult`.
func difficulty_hp_mult(d: Dictionary, n: int) -> float:
	var target: float = float(d.get("hp_mult", 1.0))
	var ramp: int = int(d.get("hp_ramp_waves", 0))
	if ramp <= 0:
		return target
	return lerpf(1.0, target, clampf(float(n - 1) / float(ramp), 0.0, 1.0))


func map(id: String) -> Dictionary:
	return maps.get(id, {})


func wave_count() -> int:
	return waves.size()


## Волна-шаблон для номера n: до последней волны — она сама, дальше (бесконечный режим «Гонки») состав
## идёт по кругу с первой волны, а сила врагов растёт (endless_hp_norm, endless_count_mult, endless_armor_bonus…).
func wave_template(n: int) -> int:
	if n <= waves.size():
		return clampi(n, 1, waves.size())
	return (n - 1) % waves.size() + 1


## Круг бесконечного режима: 0 — основные волны, 1 — волны 63–124 и т. д.
func endless_cycle(n: int) -> int:
	return maxi(0, (n - 1) / waves.size())


func wave(n: int) -> Dictionary:
	return waves[wave_template(n) - 1]


func is_air_wave(n: int) -> bool:
	return n >= 1 and wave_template(n) % int(waves_cfg["air_every"]) == 0


func is_boss_wave(n: int) -> bool:
	return n >= 1 and (waves_cfg["boss_waves"] as Array).has(float(wave_template(n)))


## Вид волны для бесконечного режима: boss, air или ground.
func wave_kind(n: int) -> String:
	if is_boss_wave(n):
		return "boss"
	return "air" if is_air_wave(n) else "ground"


## «Вес» HP волны-шаблона: Σ число × HP-множитель архетипа × множитель группы (× элита).
func wave_weight(n: int) -> float:
	var elite: float = float(economy["elite"]["hp_mult"])
	var total: float = 0.0
	for grp: Dictionary in wave(n)["groups"]:
		total += float(grp["count"]) * float(archetype(String(grp["type"])).get("hp_mult", 1.0)) * float(grp["hp_mult"]) \
			* (elite if bool(grp.get("elite", false)) else 1.0)
	return total


## Бесконечный режим: множитель HP врагов волны n (> последней). Состав берётся из волны-шаблона, а суммарное
## HP выравнивается до среднего у волн второго акта того же вида: волна 63 (восемь Ходоков первой волны) не
## проваливает сложность после финала, а продолжает её. Сама формула HP (enemy_base_hp) растёт дальше как в
## конце второго акта. Шаблоны тяжелее среднего не облегчаются.
func endless_hp_norm(n: int) -> float:
	if n <= waves.size():
		return 1.0
	var ref: float = float(_endless_ref.get(wave_kind(n), 0.0))
	var own: float = wave_weight(n)
	if ref <= 0.0 or own <= 0.0:
		return 1.0
	return maxf(1.0, ref / own)


## Бесконечный режим: врагов в обычных группах больше на count_growth за круг (боссов — столько же).
func endless_count_mult(n: int) -> float:
	return 1.0 + float(waves_cfg["endless"]["count_growth"]) * float(endless_cycle(n))


## Бесконечный режим: прибавка брони всем врагам за круг.
func endless_armor_bonus(n: int) -> float:
	return float(waves_cfg["endless"]["armor_growth"]) * float(endless_cycle(n))


## Бесконечный режим: множитель скорости врагов (рост за круг, не выше 1 + speed_cap).
func endless_speed_mult(n: int) -> float:
	var cfg: Dictionary = waves_cfg["endless"]
	return 1.0 + minf(float(cfg["speed_growth"]) * float(endless_cycle(n)), float(cfg["speed_cap"]))


## Длины забега на выбор (20, 42, 62 — waves.json → lengths.options).
func run_lengths() -> Array[int]:
	var out: Array[int] = []
	for opt: Dictionary in waves_cfg["lengths"]["options"]:
		out.append(int(opt["waves"]))
	return out


func default_run_length() -> int:
	return int(waves_cfg["lengths"]["default"])


## Настройки длины забега (финальный босс, разгон сложности) или {} для нестандартной длины (--waves=N, тесты).
func run_length_cfg(total: int) -> Dictionary:
	for opt: Dictionary in waves_cfg["lengths"]["options"]:
		if int(opt["waves"]) == total:
			return opt
	return {}


## HP врага волны n без множителей: база · ростⁿ⁻¹ + линейная · (n − 1). После `late.from_wave` рост другой
## (`late.growth`): к поздним волнам сила доски выходит на плато (качество V, удача и уровни спец-башен ограничены),
## и прежние +14 % за волну обгоняли бы её. Кривая непрерывна: на волне from_wave обе формулы совпадают.
func enemy_base_hp(n: int) -> float:
	var f: Dictionary = waves_cfg["hp_formula"]
	var late: Dictionary = f.get("late", {})
	var from: int = int(late.get("from_wave", 0))
	var m: int = mini(n, from) if from > 0 else n
	var hp: float = float(f["base"]) * pow(float(f["growth"]), float(m - 1)) + float(f["linear"]) * float(m - 1)
	if from > 0 and n > from:
		hp = hp * pow(float(late["growth"]), float(n - from)) + float(f["linear"]) * float(n - from)
	return hp


func damage_mult(dtype: String, atype: String) -> float:
	return float((damage_matrix.get(dtype, {}) as Dictionary).get(atype, 1.0))


func tick_rate() -> int:
	return int(economy["sim"]["tick_rate"])


static func hex_color(hex: String) -> Color:
	return Color.html(hex)
