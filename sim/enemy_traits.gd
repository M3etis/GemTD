class_name EnemyTraits
extends RefCounted
## Трейты врагов (traits.json), элита и способности боссов (фазы, призыв), раскол.
## Вся случайность — через sim.combat_rng, поэтому поведение детерминировано.


## Настраивает врага при появлении: архетип, трейты группы, элита, фазы босса.
static func setup(c: CombatSystem, e: EnemyState, a: Dictionary, extra_traits: Array, elite: bool, now: float) -> void:
	var data: GameData = c.data
	var sim: GameSim = c.sim
	e.resist = (a["resist"] as Dictionary).duplicate()
	e.immortal = bool(a["immortal"])
	e.split = a["split"]
	for t: Variant in a["traits"]:
		e.traits[String(t)] = true
	for t2: Variant in extra_traits:
		e.traits[String(t2)] = true
	if elite:
		var ec: Dictionary = data.economy["elite"]
		e.elite = true
		e.max_hp *= float(ec["hp_mult"])
		e.hp = e.max_hp
		e.bounty = int(roundf(float(e.bounty) * float(ec["bounty_mult"])))
		e.leak_damage *= int(ec["leak_mult"])
		e.armor += float(ec["armor_bonus"])
		e.size *= float(ec["size_mult"])
	var shield_pct: float = float(a["shield_pct"])
	if shield_pct > 0.0:
		e.shield = e.max_hp * shield_pct
		e.max_shield = e.shield
	for id: String in e.traits.keys():
		var cfg: Dictionary = data.trait_cfg(id)
		match id:
			"regen":
				e.regen_pct += float(cfg["pct_per_sec"])
			"evasion":
				e.evasion = float(cfg["chance"])
				for dt: Variant in cfg["types"]:
					e.evasion_types[String(dt)] = true
			"antimagic", "ethereal":
				for dt2: Variant in cfg["immune"]:
					e.immune[String(dt2)] = true
				e.cc_immune = e.cc_immune or bool(cfg["cc_immune"])
			"refraction":
				e.refraction = int(cfg["charges"])
			"carapace":
				e.carapace_block = float(cfg["block_pct"]) * data.enemy_base_hp(sim.hp_wave()) * sim.diff_hp_mult()
				e.carapace_next = now + float(cfg["cleanse_interval"])
			"blink":
				e.blink_next = now + float(cfg["interval"])
			"disarm":
				e.disarm_next = now + float(data.trait_rules["disarm_recheck"])
			"thief":
				e.thief_gold = int(cfg["gold_base"]) + int(roundf(float(cfg["gold_per_wave"]) * float(sim.wave_number)))
			"shroud":
				e.shrouded = true
	if e.immortal:
		e.cc_immune = true
	var abilities: Dictionary = a["abilities"]
	e.phases = abilities.get("phases", [])
	e.summon = abilities.get("summon", {})
	e.dynamic = e.regen_pct > 0.0 or e.traits.has("rush") or e.blink_next >= 0.0 or e.disarm_next >= 0.0 \
		or e.carapace_block > 0.0 or not e.phases.is_empty() or not e.summon.is_empty()
	_check_phases(c, e, now)


## Шаг трейтов до движения: регенерация, рывок, мерцание, обезоруживание, панцирь, фазы, призыв.
static func update(c: CombatSystem, e: EnemyState, dt: float, now: float) -> void:
	var data: GameData = c.data
	if e.regen_pct > 0.0 and e.hp < e.max_hp and not e.immortal:
		var heal: float = e.max_hp * e.regen_pct * dt
		if not e.poison.is_empty() or now < e.blight_until:
			heal *= 1.0 - float(data.gem_effect("emerald", "poison_regen_cut", 1, 0.0))
		e.hp = minf(e.max_hp, e.hp + heal)
	if e.traits.has("rush") and not e.rush_used:
		var rc: Dictionary = data.trait_cfg("rush")
		if e.hp < e.max_hp * float(rc["hp_threshold"]):
			e.rush_used = true
			e.rush_until = now + float(rc["duration"])
			_proc(c, e, "rush")
	if e.blink_next >= 0.0 and now >= e.blink_next and not e.is_stunned(now):
		var bc: Dictionary = data.trait_cfg("blink")
		e.blink_next = now + float(bc["interval"])
		_proc(c, e, "blink")
		e.dist += float(bc["distance"])
	if e.disarm_next >= 0.0 and now >= e.disarm_next:
		_disarm(c, e, now)
	if e.carapace_block > 0.0 and now >= e.carapace_next:
		e.carapace_next = now + float(data.trait_cfg("carapace")["cleanse_interval"])
		if _cleanse(e, now):
			_proc(c, e, "carapace")
	_check_phases(c, e, now)
	if not e.summon.is_empty() and e.phase_index >= int(e.summon["from_phase"]):
		if e.summon_next < 0.0:
			e.summon_next = now
		if now >= e.summon_next:
			e.summon_next = now + float(e.summon["interval"])
			_summon(c, e)


## Обнаружение невидимых: Opal (detect_radius) и Beacon Lens L3.
static func detectors(sim: GameSim) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var data: GameData = sim.data
	for t: TowerState in sim.towers:
		if t.gem_id == "opal":
			out.append(Vector3(t.pos.x, t.pos.y, float(data.gem_effect("opal", "detect_radius", t.quality, 0.0))))
		elif t.special_id == "beacon_lens" and int(data.special_effect("beacon_lens", "detect", t.level, 0)) > 0:
			out.append(Vector3(t.pos.x, t.pos.y, float(data.special_effect("beacon_lens", "aura_radius", t.level, 0.0))))
	return out


## Обнаруженный враг остаётся видимым ещё reveal_time секунд после выхода из радиуса.
static func refresh_visibility(e: EnemyState, dets: PackedVector3Array, now: float, reveal_time: float) -> void:
	if not e.shrouded:
		e.visible = true
		return
	for d: Vector3 in dets:
		if e.pos.distance_squared_to(Vector2(d.x, d.y)) <= d.z * d.z:
			e.revealed_until = maxf(e.revealed_until, now + reveal_time)
			break
	e.visible = now < e.revealed_until


## Проверки до расчёта урона: иммунитет, уклонение, Отражение. true — удар не прошёл.
static func blocks_hit(c: CombatSystem, e: EnemyState, dtype: String, quiet: bool) -> bool:
	if e.immune.has(dtype):
		if not quiet:
			_block(c, e, "antimagic" if dtype == "arcane" else "ethereal")
		return true
	if quiet:
		return false
	if e.evasion > 0.0 and e.evasion_types.has(dtype) and c.sim.combat_rng.chance(e.evasion):
		_block(c, e, "evasion")
		return true
	if e.refraction > 0:
		e.refraction -= 1
		_block(c, e, "refraction")
		return true
	return false


## Урон после брони: сопротивления, Панцирь, Закалка, щит. Возвращает урон по HP.
static func absorb(c: CombatSystem, e: EnemyState, amount: float, dtype: String, quiet: bool) -> float:
	if dtype != "pure":
		amount *= float(e.resist.get(dtype, 1.0))
	if not quiet:
		if e.carapace_block > 0.0:
			var before: float = amount
			amount = maxf(0.0, amount - e.carapace_block)
			if amount <= 0.0 and before > 0.0:
				_block(c, e, "carapace")
		if e.traits.has("hardening"):
			var hc: Dictionary = c.data.trait_cfg("hardening")
			e.hardening_hits += 1
			if e.hardening_hits % int(hc["hits_per_armor"]) == 0 and e.hardening_bonus < float(hc["max_bonus"]):
				e.hardening_bonus += 1.0
				_proc(c, e, "hardening")
	if e.shield > 0.0 and amount > 0.0:
		var taken: float = minf(e.shield, amount)
		e.shield -= taken
		amount -= taken
		if e.shield <= 0.0:
			e.shield = 0.0
			c.sim.emit_event({"type": "shield_broken", "enemy_id": e.id, "pos": e.pos, "flying": e.flying})
	return amount


## Утечка: Вор крадёт золото.
static func on_leak(c: CombatSystem, e: EnemyState) -> void:
	if e.thief_gold <= 0:
		return
	var stolen: int = mini(c.sim.gold, e.thief_gold)
	if stolen > 0:
		c.sim.add_gold(-stolen)
		c.sim.emit_event({"type": "gold_stolen", "amount": stolen, "enemy_id": e.id})


## Смерть: раскол на малых врагов.
static func on_death(c: CombatSystem, e: EnemyState) -> void:
	if e.split.is_empty():
		return
	var offset: float = float(c.data.trait_rules["split_offset"])
	for i: int in int(e.split["count"]):
		var at: float = maxf(0.0, e.dist - float(i) * offset)
		c.spawn_enemy(String(e.split["type"]), 1.0, [], false, at)
	c.sim.emit_event({"type": "enemy_split", "pos": e.pos, "count": int(e.split["count"])})


static func cc_factor(c: CombatSystem, e: EnemyState) -> float:
	return float(c.data.trait_rules["boss_cc_factor"]) if e.boss else 1.0


# --- Внутреннее ---------------------------------------------------------------

static func _check_phases(c: CombatSystem, e: EnemyState, now: float) -> void:
	while e.phase_index < e.phases.size() and e.hp <= e.max_hp * float((e.phases[e.phase_index] as Dictionary)["at"]) + 0.0001:
		var ph: Dictionary = e.phases[e.phase_index]
		e.phase_index += 1
		if ph.has("shield_pct"):
			e.shield += e.max_hp * float(ph["shield_pct"])
			e.max_shield = maxf(e.max_shield, e.shield)
		if ph.has("speed_mult"):
			e.speed_mult = float(ph["speed_mult"])
		if ph.has("regen"):
			e.regen_pct += float(ph["regen"])
		c.sim.emit_event({"type": "boss_phase", "enemy_id": e.id, "phase": e.phase_index, "key": String(ph.get("key", "")),
			"pos": e.pos, "flying": e.flying, "time": now})


static func _summon(c: CombatSystem, e: EnemyState) -> void:
	var cap: int = int(c.data.trait_rules["summon_max_alive"])
	if c.sim.enemies.size() + c.pending.size() >= cap:
		return
	var offset: float = float(c.data.trait_rules["summon_offset"])
	var types: Array = e.summon["types"]
	var count: int = int(e.summon["count"])
	for i: int in count:
		var type: String = String(types[i % types.size()])
		var flying: bool = bool(c.data.archetype(type)["flying"])
		var at: float = 0.0 if flying != e.flying else maxf(0.0, e.dist - float(i + 1) * offset)
		c.spawn_enemy(type, 1.0, [], false, at)
	c.sim.emit_event({"type": "boss_summon", "enemy_id": e.id, "pos": e.pos, "flying": e.flying, "count": count})


static func _disarm(c: CombatSystem, e: EnemyState, now: float) -> void:
	var cfg: Dictionary = c.data.trait_cfg("disarm")
	if e.is_stunned(now):
		e.disarm_next = now + float(c.data.trait_rules["disarm_recheck"])
		return
	var radius: float = float(cfg["radius"])
	var ids: Array[int] = []
	for t: TowerState in c.sim.towers:
		if t.attack_kind == "none" or t.pos.distance_squared_to(e.pos) > radius * radius:
			continue
		t.disarmed_until = maxf(t.disarmed_until, now + float(cfg["duration"]))
		ids.append(t.id)
	if ids.is_empty():
		e.disarm_next = now + float(c.data.trait_rules["disarm_recheck"])
		return
	e.disarm_next = now + float(cfg["cooldown"])
	c.sim.emit_event({"type": "disarm", "enemy_id": e.id, "pos": e.pos, "radius": radius, "towers": ids, "duration": float(cfg["duration"])})


## Снимает дебаффы; true — было что снимать.
static func _cleanse(e: EnemyState, now: float) -> bool:
	var any: bool = now < e.slow_until or e.slow_floor > 0.0 or now < e.stun_until or not e.poison.is_empty() or now < e.vuln_until or now < e.mark_until
	e.slow_until = -1.0
	e.slow_floor = 0.0
	e.stun_until = -1.0
	e.poison.clear()
	e.vuln_until = -1.0
	e.mark_until = -1.0
	return any


static func _proc(c: CombatSystem, e: EnemyState, trait_id: String) -> void:
	c.sim.emit_event({"type": "trait_proc", "trait": trait_id, "enemy_id": e.id, "pos": e.pos, "flying": e.flying})


## Удар не прошёл: kind — трейт, который его остановил (antimagic, ethereal, evasion, refraction, carapace).
static func _block(c: CombatSystem, e: EnemyState, kind: String) -> void:
	c.sim.emit_event({"type": "hit_blocked", "kind": kind, "enemy_id": e.id, "pos": e.pos, "flying": e.flying})
