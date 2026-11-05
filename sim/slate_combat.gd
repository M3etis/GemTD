class_name SlateCombat
extends RefCounted
## Бой слейтов. У каждого свой интервал: импульс бьёт всех врагов в радиусе (target_mode all) или
## первого по пути видимого (single). Эффекты — из slates.json: урон (против воздуха, за убийства,
## за волну, уровни, нарастающий по одной цели), яд, замедление, оглушение со снятием брони,
## заклинания, взрыв при убийстве. Ауры башням считает CombatSystem.recompute_auras.
## Удары тихие (quiet): ловушка на земле не проходит через уклонение и «ударные» трейты.


static func step(c: CombatSystem, dt: float, now: float) -> void:
	var sim: GameSim = c.sim
	for s: TowerState in sim.slates:
		s.cooldown -= dt
		if s.cooldown > 0.0:
			continue
		var sl: Dictionary = c.data.slate(s.slate_id)
		var radius: float = float(sl["radius"])
		var single: bool = String(sl["target_mode"]) == "single"
		var picked: Array[EnemyState] = []
		var first: EnemyState = null
		# Общий буфер запроса (как в CombatSystem._find_target): простаивающий слейт опрашивает радиус
		# каждый такт, и новый массив на каждый опрос был бы лишним.
		c._query.clear()
		c.spatial.query(s.pos, radius, c._query)
		for e: EnemyState in c._query:
			if not c._can_hit(s, e):
				continue
			if not single:
				picked.append(e)
			elif e.visible and (first == null or e.dist > first.dist):
				first = e
		if first != null:
			picked.append(first)
		if picked.is_empty():
			s.cooldown = 0.0
			continue
		s.cooldown = float(sl["interval"])
		for e: EnemyState in picked:
			_apply(c, s, sl, e, now)
		sim.emit_event({"type": "slate_pulse", "pos": s.pos, "radius": radius, "slate": s.slate_id, "tower_id": s.id})


static func _apply(c: CombatSystem, s: TowerState, sl: Dictionary, e: EnemyState, now: float) -> void:
	var fx: Dictionary = sl["effects"]
	var dtype: String = String(sl["damage_type"])
	var dmg: float = float(fx["damage_air"]) if e.flying and fx.has("damage_air") else float(sl["damage"])
	dmg += float(fx.get("damage_per_kill", 0.0)) * float(s.kills) + float(fx.get("damage_per_wave", 0.0)) * float(c.sim.wave_number)
	if fx.has("level_every_kills"):
		var lvl: int = mini(int(fx["max_levels"]), s.kills / maxi(1, int(fx["level_every_kills"])))
		dmg *= 1.0 + float(fx["level_damage"]) * float(lvl)
	if fx.has("stack_damage"):
		if s.stack_target == e.id:
			s.stack_hits += 1
		else:
			s.stack_target = e.id
			s.stack_hits = 0
		dmg += float(fx["stack_damage"]) * float(s.stack_hits)
	if dmg > 0.0:
		c.hit(e, dmg, dtype, s, false, now, true)
	if not e.alive:
		if fx.has("death_blast"):
			_blast(c, s, e.pos, float(fx["death_blast"]), float(fx.get("death_blast_radius", 1.5)), dtype, now)
		return
	if fx.has("poison_dps"):
		_poison(e, s, float(fx["poison_dps"]), now + float(fx["poison_duration"]))
	if fx.has("slow"):
		var dur: float = float(fx.get("slow_duration", 1.0))
		var pct: float = float(fx["slow"]) * (float(fx.get("boss_factor", 1.0)) if e.boss else 1.0)
		if dur > 0.0:
			e.apply_slow(pct, now + dur, now)
		else:
			e.apply_permanent_slow(pct)
	if fx.has("stun"):
		var st: float = float(fx["stun"]) * EnemyTraits.cc_factor(c, e)
		if e.stun(now + st):
			c.sim.emit_event({"type": "stunned", "enemy_id": e.id, "pos": e.pos, "flying": e.flying, "duration": st})
			if fx.has("armor_reduction"):
				e.apply_timed_shred(float(fx["armor_reduction"]), now + st, now)
	if fx.has("spell_chance") and c.sim.combat_rng.chance(float(fx["spell_chance"])):
		_spell(c, s, fx, e, now)


## Взрыв вокруг точки: урон всем подходящим врагам в радиусе.
static func _blast(c: CombatSystem, s: TowerState, at: Vector2, dmg: float, radius: float, dtype: String, now: float) -> void:
	for e: EnemyState in c.enemies_in(at, radius):
		if c._can_hit(s, e):
			c.hit(e, dmg, dtype, s, false, now, true)
	c.sim.emit_event({"type": "slate_blast", "pos": at, "radius": radius, "slate": s.slate_id})


## Один стак яда от слейта: повторный импульс обновляет его, а не складывает.
static func _poison(e: EnemyState, s: TowerState, dps: float, until: float) -> void:
	if e.immune.has("nature"):
		return
	for st: Dictionary in e.poison:
		if int(st["source"]) == s.id:
			st["dps"] = dps
			st["until"] = until
			return
	e.poison.append({"dps": dps, "until": until, "source": s.id, "spread": false, "quality": 0})


## Заклинание: у Руин — случайно золото, снятие брони, замедление или вспышка; у Заклинаний — вспышка.
static func _spell(c: CombatSystem, s: TowerState, fx: Dictionary, e: EnemyState, now: float) -> void:
	var kind: String = "damage"
	if fx.has("spell_gold"):
		kind = ["gold", "armor", "slow", "damage"][c.sim.combat_rng.range_int(0, 3)]
	match kind:
		"gold":
			c.sim.add_gold(int(fx["spell_gold"]))
		"armor":
			e.apply_timed_shred(float(fx["spell_armor"]), now + float(fx["spell_armor_duration"]), now)
		"slow":
			e.apply_slow(float(fx["spell_slow"]), now + float(fx["spell_slow_duration"]), now)
		_:
			_blast(c, s, e.pos, float(fx["spell_damage"]), float(fx["spell_radius"]), "arcane", now)
	c.sim.emit_event({"type": "slate_spell", "pos": e.pos, "kind": kind, "slate": s.slate_id})
