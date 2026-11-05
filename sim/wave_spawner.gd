class_name WaveSpawner
extends RefCounted
## Расписание спавна волны: список {time, type, hp_mult}, отсортированный по времени.
## finale — настройки финала забега (waves.json → lengths): боссы последней волны сильнее и элитные,
## а у цитадели снимают finale_leak жизней (поле leak записи расписания).
## Волны после последней (бесконечный режим) берут состав волны-шаблона и растут: HP выравнивается
## (GameData.endless_hp_norm), обычных врагов больше за круг (endless_count_mult), броня и скорость —
## при появлении (CombatSystem.spawn_enemy).


static func build_schedule(data: GameData, wave_n: int, finale: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var order: int = 0
	for grp: Dictionary in groups(data, wave_n, finale):
		for i: int in int(grp["count"]):
			out.append({
				# Округление до 0.1 мс: совпадающие времена разных групп равны точно, сортировка стабильна.
				"time": snappedf(float(grp["delay"]) + float(i) * float(grp["interval"]), 0.0001),
				"type": String(grp["type"]),
				"hp_mult": float(grp["hp_mult"]),
				"traits": grp.get("traits", []),
				"elite": bool(grp.get("elite", false)),
				"finale": bool(grp.get("finale", false)),
				"leak": int(grp.get("leak", 0)),
				"order": order,
			})
			order += 1
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["time"]) != float(b["time"]):
			return float(a["time"]) < float(b["time"])
		return int(a["order"]) < int(b["order"]))
	return out


## Группы волны n с учётом финала и бесконечного режима: те же поля, что в waves.json, плюс finale.
static func groups(data: GameData, wave_n: int, finale: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var endless: bool = wave_n > data.wave_count()
	var norm: float = data.endless_hp_norm(wave_n)
	var more: float = data.endless_count_mult(wave_n)
	for grp: Dictionary in data.wave(wave_n)["groups"]:
		var g: Dictionary = grp.duplicate()
		var boss: bool = bool(data.archetype(String(grp["type"])).get("boss", false))
		g["hp_mult"] = float(grp["hp_mult"]) * norm
		if endless and not boss and more > 1.0:
			g["count"] = maxi(1, roundi(float(grp["count"]) * more))
			g["interval"] = float(grp["interval"]) / more
		if boss and not finale.is_empty():
			g["hp_mult"] = float(g["hp_mult"]) * float(finale["finale_hp_mult"])
			g["elite"] = bool(grp.get("elite", false)) or bool(finale["finale_elite"])
			g["finale"] = true
			g["leak"] = int(finale["finale_leak"])
		out.append(g)
	return out


## Сводка для превью волны в UI: [{type, count, elite, traits}], признаки air/boss, все трейты волны.
static func summary(data: GameData, wave_n: int, finale: Dictionary = {}) -> Dictionary:
	var w: Dictionary = data.wave(wave_n)
	var out_groups: Array[Dictionary] = []
	var total: int = 0
	for grp: Dictionary in groups(data, wave_n, finale):
		out_groups.append({"type": grp["type"], "count": int(grp["count"]), "elite": bool(grp.get("elite", false)),
			"finale": bool(grp.get("finale", false)),
			"traits": Array(data.archetype(String(grp["type"]))["traits"]) + Array(grp.get("traits", []))})
		total += int(grp["count"])
	var traits: Array = []
	for g: Dictionary in out_groups:
		for t: Variant in g["traits"]:
			if not traits.has(t):
				traits.append(t)
	return {
		"wave": wave_n,
		"traits": traits,
		"modifier": w["modifier"],
		"air": data.is_air_wave(wave_n),
		"boss": data.is_boss_wave(wave_n),
		"finale": not finale.is_empty(),
		"finale_cfg": finale,
		"groups": out_groups,
		"total": total,
		"base_hp": data.enemy_base_hp(wave_n) * data.endless_hp_norm(wave_n),
		"cycle": data.endless_cycle(wave_n),
	}
