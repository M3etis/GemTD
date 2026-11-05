class_name SpecialText
extends RefCounted
## Человекочитаемые описания эффектов спец-башен из данных (specials.json) — без захардкоженных чисел.


static func _pct(v: float) -> String:
	var p: float = v * 100.0
	if absf(p - roundf(p)) > 0.01:
		return "%.1f%%" % p
	return "%d%%" % int(roundf(p))


static func _num(v: float) -> String:
	return UiTokens.format_number(v)


## Строки эффекта уровня level.
static func describe(data: GameData, special: String, level: int) -> PackedStringArray:
	var fx: Dictionary = data.special_level(special, level).get("effects", {})
	var lv: Dictionary = data.special_level(special, level)
	var out: PackedStringArray = PackedStringArray()
	var tr_: Callable = TranslationServer.translate
	match special:
		"beacon_lens":
			out.append(String(tr_.call("FX_BEACON")) % [_num(float(fx["aura_radius"])), _num(float(fx["aura_range"])), _pct(float(fx["aura_attack_speed"]))])
			if int(fx.get("detect", 0)) > 0:
				out.append(String(tr_.call("FX_DETECT")))
		"cinder_crown":
			out.append(String(tr_.call("FX_BURN")) % [_num(float(fx["burn_radius"])), _num(float(fx["burn_dps"]))])
			if float(fx.get("flash_every", 0.0)) > 0.0:
				out.append(String(tr_.call("FX_FLASH")) % [int(fx["flash_every"]), int(fx["flash_mult"])])
		"skypiercer":
			out.append(String(tr_.call("FX_SKY")) % [_num(float(lv["damage"])), _num(float(fx["air_mult"])), _num(float(fx["ground_mult"]))])
			if int(fx.get("pierce", 1)) > 1:
				out.append(String(tr_.call("FX_PIERCE")) % int(fx["pierce"]))
			if float(fx.get("vuln", 0.0)) > 0.0:
				out.append(String(tr_.call("FX_VULN")) % [_pct(float(fx["debuff_slow"])), _pct(float(fx["vuln"])), int(fx["debuff_duration"])])
		"frostwell":
			out.append(String(tr_.call("FX_SLOW_AURA")) % [_pct(float(fx["slow"])), _num(float(fx["slow_radius"]))])
			if float(fx.get("freeze_chance", 0.0)) > 0.0:
				out.append(String(tr_.call("FX_FREEZE")) % [_pct(float(fx["freeze_chance"])), _num(float(fx["freeze_duration"]))])
		"blightbloom":
			out.append(String(tr_.call("FX_POOL")) % [_num(float(lv["damage"])), _num(float(fx["pool_dps"])), _num(float(fx["pool_duration"])), int(fx["pool_stacks"])])
			if float(fx.get("pool_slow", 0.0)) > 0.0:
				out.append(String(tr_.call("FX_POOL_SLOW")) % _pct(float(fx["pool_slow"])))
			if int(fx.get("explode", 0)) > 0:
				out.append(String(tr_.call("FX_EXPLODE")))
		"rust_obelisk":
			out.append(String(tr_.call("FX_SHRED")) % [_num(float(lv["damage"])), _num(float(fx["armor_reduction"])), _num(float(fx["armor_aura_radius"]))])
			if int(fx.get("strip", 0)) > 0:
				out.append(String(tr_.call("FX_STRIP")))
		"gravity_geode":
			out.append(String(tr_.call("FX_STUN")) % [_num(float(lv["damage"])), _pct(float(fx["stun_chance"])), _num(float(fx["stun_duration"]))])
			if int(fx.get("pull", 0)) > 0:
				out.append(String(tr_.call("FX_PULL")) % _num(float(fx["pull_radius"])))
		"stormspire":
			out.append(String(tr_.call("FX_CHAIN")) % [_num(float(lv["damage"])), int(fx["chain_targets"]), _pct(1.0 - float(fx["chain_falloff"]))])
			if float(fx.get("discharge_chance", 0.0)) > 0.0:
				out.append(String(tr_.call("FX_DISCHARGE")) % [_pct(float(fx["discharge_chance"])), _pct(float(fx["discharge_mult"]))])
		"razor_prism":
			out.append(String(tr_.call("FX_CRIT")) % [_num(float(lv["damage"])), _pct(float(fx["crit_chance"])), _num(float(fx["crit_mult"]))])
			if int(fx.get("crit_pierce", 0)) > 0:
				out.append(String(tr_.call("FX_MARK")) % [_pct(float(fx["mark"])), _num(float(fx["mark_duration"]))])
		"quake_heart":
			out.append(String(tr_.call("FX_QUAKE")) % [_num(float(lv["damage"])), _num(float(fx["splash_radius"]))])
			if float(fx.get("stun", 0.0)) > 0.0:
				out.append(String(tr_.call("FX_QUAKE_STUN")) % _num(float(fx["stun"])))
			if int(fx.get("shockwave_every", 0)) > 0:
				out.append(String(tr_.call("FX_SHOCKWAVE")) % [int(fx["shockwave_every"]), _num(float(fx["shockwave_radius"])), _pct(float(fx["shockwave_mult"]))])
		"gilded_idol":
			out.append(String(tr_.call("FX_IDOL")) % [_pct(float(fx["bounty_bonus"])), _num(float(fx["bounty_radius"])), int(fx["wave_gold"])])
			if float(fx.get("golden_chance", 0.0)) > 0.0:
				out.append(String(tr_.call("FX_GOLDEN")) % [_pct(float(fx["golden_chance"])), int(fx["golden_mult"])])
		"warbanner_crystal":
			out.append(String(tr_.call("FX_BANNER")) % [_pct(float(fx["aura_damage"])), _num(float(fx["aura_radius"]))])
			if float(fx.get("aura_speed", 0.0)) > 0.0:
				out.append(String(tr_.call("FX_BANNER_SPEED")) % _pct(float(fx["aura_speed"])))
		"titanbane":
			out.append(String(tr_.call("FX_TITAN")) % [_num(float(lv["damage"])), _pct(float(fx["hp_pct"])), _num(float(fx["elite_mult"]))])
			if int(fx.get("strip_carapace", 0)) > 0:
				out.append(String(tr_.call("FX_TITAN_STRIP")))
	return out


static func recipe_text(data: GameData, special: String) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for comp: Dictionary in data.special(special).get("recipe", []):
		parts.append("%s %s" % [TranslationServer.translate(String(data.gem(String(comp["gem"]))["name_key"])), String(data.quality(int(comp["quality"]))["roman"])])
	return " + ".join(parts)


## Требование улучшения до уровня to_level: «45 золота» или «110 золота + Опал III+ в фазе выбора».
static func upgrade_text(data: GameData, special: String, to_level: int) -> String:
	var up: Dictionary = data.special_upgrade(special, to_level)
	if up.is_empty():
		return ""
	var gold: String = String(TranslationServer.translate("UP_GOLD")) % int(up["gold"])
	if String(up["gem"]).is_empty():
		return gold
	var gem: String = TranslationServer.translate(String(data.gem(String(up["gem"]))["name_key"]))
	return String(TranslationServer.translate("UP_GOLD_GEM")) % [gold, gem, String(data.quality(int(up["min_quality"]))["roman"])]
