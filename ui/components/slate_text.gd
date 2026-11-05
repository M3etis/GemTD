class_name SlateText
extends RefCounted
## Тексты слейтов для панели, Кодекса и кнопок: эффекты по полям slates.json, рецепт.


static func _t(key: String) -> String:
	return String(TranslationServer.translate(key))


## 10 → «10», 1.5 → «1.5».
static func _num(v: float) -> String:
	return str(int(roundf(v))) if is_equal_approx(v, roundf(v)) else String.num(snappedf(v, 0.01))


## Строки эффектов слейта (уже с числами).
static func describe(data: GameData, id: String) -> PackedStringArray:
	var sl: Dictionary = data.slate(id)
	var out: PackedStringArray = PackedStringArray()
	if sl.is_empty():
		return out
	var fx: Dictionary = sl["effects"]
	var targets: String = _t("TARGETS_" + String(sl["targets"]).to_upper())
	var pulse_key: String = "SLFX_PULSE_ALL" if String(sl["target_mode"]) == "all" else "SLFX_PULSE_SINGLE"
	out.append(_t(pulse_key) % [_num(float(sl["interval"])), targets, _num(float(sl["radius"]))])
	var dtype: String = _t("DMG_" + String(sl["damage_type"]).to_upper())
	if float(sl["damage"]) > 0.0:
		out.append(_t("SLFX_DAMAGE") % [_num(float(sl["damage"])), dtype])
	if fx.has("damage_air"):
		out.append(_t("SLFX_DAMAGE_AIR") % _num(float(fx["damage_air"])))
	if fx.has("damage_per_wave"):
		out.append(_t("SLFX_PER_WAVE") % [_num(float(fx["damage_per_wave"])), dtype])
	if fx.has("damage_per_kill"):
		out.append(_t("SLFX_PER_KILL") % _num(float(fx["damage_per_kill"])))
	if fx.has("poison_dps"):
		out.append(_t("SLFX_POISON") % [_num(float(fx["poison_dps"])), _num(float(fx["poison_duration"]))])
	if fx.has("slow"):
		var dur: float = float(fx.get("slow_duration", 1.0))
		var pct: int = int(roundf(float(fx["slow"]) * 100.0))
		out.append(_t("SLFX_SLOW_FOREVER") % pct if dur <= 0.0 else _t("SLFX_SLOW") % [pct, _num(dur)])
		if fx.has("boss_factor"):
			out.append(_t("SLFX_BOSS_FACTOR") % int(roundf(float(fx["boss_factor"]) * 100.0)))
	if fx.has("stun"):
		out.append(_t("SLFX_STUN") % _num(float(fx["stun"])))
	if fx.has("armor_reduction"):
		out.append(_t("SLFX_ARMOR_STUN") % _num(float(fx["armor_reduction"])))
	if fx.has("spell_gold"):
		out.append(_t("SLFX_RUINS") % [int(roundf(float(fx["spell_chance"]) * 100.0)), int(fx["spell_gold"]),
			_num(float(fx["spell_armor"])), _num(float(fx["spell_armor_duration"])), int(roundf(float(fx["spell_slow"]) * 100.0)),
			_num(float(fx["spell_slow_duration"])), _num(float(fx["spell_damage"]))])
	elif fx.has("spell_chance"):
		out.append(_t("SLFX_SPELL") % [int(roundf(float(fx["spell_chance"]) * 100.0)), _num(float(fx["spell_damage"])), _num(float(fx["spell_radius"]))])
	if fx.has("stack_damage"):
		out.append(_t("SLFX_STACK") % _num(float(fx["stack_damage"])))
	if fx.has("death_blast"):
		out.append(_t("SLFX_DEATH_BLAST") % [_num(float(fx["death_blast"])), _num(float(fx.get("death_blast_radius", 1.5)))])
	if fx.has("level_every_kills"):
		out.append(_t("SLFX_LEVELS") % [int(roundf(float(fx["level_damage"]) * 100.0)), int(fx["level_every_kills"]), int(fx["max_levels"])])
	if fx.has("aura_speed"):
		out.append(_t("SLFX_AURA_SPEED") % [int(roundf(float(fx["aura_speed"]) * 100.0)), _num(float(fx["aura_radius"]))])
	if fx.has("aura_damage"):
		out.append(_t("SLFX_AURA_DAMAGE") % [int(roundf(float(fx["aura_damage"]) * 100.0)), _num(float(fx["aura_radius"]))])
	return out


## Рецепт: «Изумруд III + Аквамарин / Опал / Топаз II» или «Удерживающий + Парящий».
static func recipe_text(data: GameData, id: String) -> String:
	var sl: Dictionary = data.slate(id)
	if sl.is_empty():
		return ""
	if String(sl["kind"]) == "combo":
		return "%s + %s" % [_t(String(data.slate(String(sl["from"][0]))["name_key"])), _t(String(data.slate(String(sl["from"][1]))["name_key"]))]
	var main: Dictionary = sl["recipe"]
	var partners: PackedStringArray = PackedStringArray()
	var q2: String = ""
	for p: Dictionary in sl["partners"]:
		partners.append(_t(String(data.gem(String(p["gem"]))["name_key"])))
		q2 = String(data.quality(int(p["quality"]))["roman"])
	return "%s %s + %s %s" % [_t(String(data.gem(String(main["gem"]))["name_key"])), String(data.quality(int(main["quality"]))["roman"]),
		" / ".join(partners), q2]
