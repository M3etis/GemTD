class_name SpecialCombat
extends RefCounted
## Боевое поведение спец-башен: ауры урона, замедления и снижения брони, ядовитые лужи, пробитие,
## уязвимость, оглушение и притяжение, криты, сплэш с ударной волной, золото, процентный урон.
## Вызывается из CombatSystem во время шага симуляции.

const FROST_REFRESH: float = 0.25
const POOL_MARK: float = 0.6
const PIERCE_SEARCH: float = 3.0


static func aura_damage(c: CombatSystem, t: TowerState, dt: float, now: float) -> void:
	var data: GameData = c.data
	var radius: float = float(data.special_effect(t.special_id, "burn_radius", t.level, 2.5))
	var dps: float = t.strength(data, "burn_dps") * t.damage_mult()
	t.cooldown -= dt
	if t.cooldown <= 0.0:
		var interval: float = 1.0 / maxf(t.effective_attack_speed(), 0.05)
		t.cooldown += interval
		var any: bool = false
		for e: EnemyState in c.enemies_in(t.pos, radius):
			if c._can_hit(t, e):
				c.hit(e, dps * interval, t.damage_type, t, false, now, true)
				any = true
		if any:
			c.sim.emit_event({"type": "aura_pulse", "tower_id": t.id, "pos": t.pos, "radius": radius, "kind": "burn", "special": t.special_id})
	var every: float = float(data.special_effect(t.special_id, "flash_every", t.level, 0.0))
	if every <= 0.0:
		return
	t.flash_timer += dt
	if t.flash_timer < every:
		return
	t.flash_timer -= every
	var flash: float = dps * float(data.special_effect(t.special_id, "flash_mult", t.level, 0.0)) * 0.5
	var hit_any: bool = false
	for e: EnemyState in c.enemies_in(t.pos, radius):
		if c._can_hit(t, e):
			c.hit(e, flash, t.damage_type, t, true, now, false)
			hit_any = true
	if hit_any:
		c.sim.emit_event({"type": "aura_flash", "tower_id": t.id, "pos": t.pos, "radius": radius, "special": t.special_id})


static func aura_slow(c: CombatSystem, t: TowerState, dt: float, now: float) -> void:
	var data: GameData = c.data
	var radius: float = float(data.special_effect(t.special_id, "slow_radius", t.level, 3.0))
	var slow: float = t.strength(data, "slow")
	var boss_factor: float = float(data.special_effect(t.special_id, "boss_factor", t.level, 1.0))
	var inside: Array[EnemyState] = []
	for e: EnemyState in c.enemies_in(t.pos, radius):
		if c._can_hit(t, e):
			inside.append(e)
			e.apply_slow(slow * (boss_factor if e.boss else 1.0), now + FROST_REFRESH, now)
	t.cooldown -= dt
	if t.cooldown > 0.0:
		return
	t.cooldown += 1.0 / maxf(t.effective_attack_speed(), 0.05)
	if inside.is_empty():
		return
	c.sim.emit_event({"type": "aura_pulse", "tower_id": t.id, "pos": t.pos, "radius": radius, "kind": "frost", "special": t.special_id})
	var chance: float = float(data.special_effect(t.special_id, "freeze_chance", t.level, 0.0))
	if chance <= 0.0:
		return
	var duration: float = float(data.special_effect(t.special_id, "freeze_duration", t.level, 0.0))
	for e: EnemyState in inside:
		if c.sim.combat_rng.chance(chance) and e.stun(now + duration * (boss_factor if e.boss else 1.0)):
			c.sim.emit_event({"type": "frozen", "pos": e.pos, "flying": e.flying, "enemy_id": e.id})


## Аура Rust Obelisk: снижение брони врагов в радиусе (берётся сильнейшая аура).
static func armor_auras(c: CombatSystem, now: float) -> void:
	var data: GameData = c.data
	for t: TowerState in c.sim.towers:
		if t.special_id != "rust_obelisk" or not t.enabled:
			continue
		var radius: float = float(data.special_effect("rust_obelisk", "armor_aura_radius", t.level, 0.0))
		var value: float = t.strength(data, "armor_reduction")
		for e: EnemyState in c.enemies_in(t.pos, radius):
			if not e.alive:
				continue
			if now >= e.shred_until or value > e.shred:
				e.shred = value
			e.shred_until = now + CombatSystem.AURA_REFRESH


## Бонус к награде от Gilded Idol, в радиусе которого погиб враг (сильнейший идол).
static func idol_bonus(c: CombatSystem, at: Vector2) -> float:
	var best: float = 0.0
	for t: TowerState in c.sim.towers:
		if t.special_id != "gilded_idol":
			continue
		var r: float = float(c.data.special_effect("gilded_idol", "bounty_radius", t.level, 0.0))
		if t.pos.distance_squared_to(at) <= r * r:
			best = maxf(best, t.strength(c.data, "bounty_bonus"))
	return best


## Золото Gilded Idol за пройденную волну.
static func idol_wave_gold(sim: GameSim) -> int:
	var total: int = 0
	for t: TowerState in sim.towers:
		if t.special_id == "gilded_idol":
			total += int(roundf(t.strength(sim.data, "wave_gold", 0)))
	return total


## Разряд Stormspire L3 вокруг цели цепи.
static func discharge(c: CombatSystem, t: TowerState, at: Vector2, amount: float, now: float) -> void:
	var data: GameData = c.data
	var radius: float = float(data.special_effect(t.special_id, "discharge_radius", t.level, 0.0))
	var dmg: float = amount * float(data.special_effect(t.special_id, "discharge_mult", t.level, 0.0))
	for e: EnemyState in c.enemies_in(at, radius):
		if c._can_hit(t, e):
			c.hit(e, dmg, t.damage_type, t, false, now, true)
	c.sim.emit_event({"type": "discharge", "pos": at, "radius": radius, "tower_id": t.id})


static func impact(c: CombatSystem, p: ProjectileState, target: EnemyState, src: TowerState, now: float) -> void:
	var data: GameData = c.data
	var lvl: int = p.special_level
	match p.gem_id:
		"skypiercer":
			if target == null:
				return
			var mult: float = float(data.special_effect("skypiercer", "air_mult" if target.flying else "ground_mult", lvl, 1.0))
			c.hit(target, p.damage * mult, p.damage_type, src, false, now, false)
			p.hit_ids.append(target.id)
			var vuln: float = src_strength(src, data, "skypiercer", "vuln", lvl)
			if vuln > 0.0 and target.alive:
				var dur: float = float(data.special_effect("skypiercer", "debuff_duration", lvl, 0.0))
				target.vuln_pct = vuln
				target.vuln_until = now + dur
				target.apply_slow(src_strength(src, data, "skypiercer", "debuff_slow", lvl), now + dur, now)
			if target.flying and p.pierce_left > 0:
				_pierce(c, p, target)
		"blightbloom":
			if target != null:
				c.hit(target, p.damage, p.damage_type, src, false, now, false)
			add_pool(c, p.pos, src, lvl, now, 1.0)
		"rust_obelisk":
			if target == null:
				return
			if int(data.special_effect("rust_obelisk", "strip", lvl, 0)) > 0 and (target.refraction > 0 or target.shield > 0.0):
				target.refraction = 0
				target.shield = 0.0
				c.sim.emit_event({"type": "stripped", "enemy_id": target.id, "pos": target.pos, "flying": target.flying, "what": "shield"})
			c.hit(target, p.damage, p.damage_type, src, false, now, false)
		"gravity_geode":
			if target == null:
				return
			c.hit(target, p.damage, p.damage_type, src, false, now, false)
			if target.alive and c.sim.combat_rng.chance(float(data.special_effect("gravity_geode", "stun_chance", lvl, 0.0))):
				var dur: float = float(data.special_effect("gravity_geode", "stun_duration", lvl, 0.0)) * EnemyTraits.cc_factor(c, target)
				if target.stun(now + dur):
					c.sim.emit_event({"type": "stunned", "enemy_id": target.id, "pos": target.pos, "flying": target.flying, "duration": dur})
					if int(data.special_effect("gravity_geode", "pull", lvl, 0)) > 0:
						_pull(c, target, float(data.special_effect("gravity_geode", "pull_radius", lvl, 0.0)))
		"razor_prism":
			if target == null:
				return
			var pierce_armor: bool = p.crit and int(data.special_effect("razor_prism", "crit_pierce", lvl, 0)) > 0
			c.hit(target, p.damage, p.damage_type, src, p.crit, now, false, false, pierce_armor)
			if pierce_armor and target.alive:
				target.mark_pct = src_strength(src, data, "razor_prism", "mark", lvl)
				target.mark_until = now + float(data.special_effect("razor_prism", "mark_duration", lvl, 0.0))
		"quake_heart":
			_quake(c, p, target, src, now)
		"gilded_idol":
			if target == null:
				return
			var chance: float = float(data.special_effect("gilded_idol", "golden_chance", lvl, 0.0))
			if chance > 0.0 and not target.golden and not target.immortal and c.sim.combat_rng.chance(chance):
				target.golden = true
				target.golden_mult = float(data.special_effect("gilded_idol", "golden_mult", lvl, 1.0))
				c.sim.emit_event({"type": "golden", "enemy_id": target.id, "pos": target.pos, "flying": target.flying})
			c.hit(target, p.damage, p.damage_type, src, false, now, false)
		"titanbane":
			if target == null:
				return
			if int(data.special_effect("titanbane", "strip_carapace", lvl, 0)) > 0 and target.carapace_block > 0.0:
				target.carapace_block = 0.0
				c.sim.emit_event({"type": "stripped", "enemy_id": target.id, "pos": target.pos, "flying": target.flying, "what": "carapace"})
			var pct: float = src_strength(src, data, "titanbane", "hp_pct", lvl)
			if target.boss or target.elite:
				pct *= float(data.special_effect("titanbane", "elite_mult", lvl, 1.0))
			c.hit(target, p.damage + target.max_hp * pct * src_mult(src), p.damage_type, src, p.crit, now, false)
		_:
			if target != null:
				c.hit(target, p.damage, p.damage_type, src, p.crit, now, false)


static func src_mult(src: TowerState) -> float:
	return src.damage_mult() if src != null else 1.0


## Сила эффекта башни-источника (у слитой — с унаследованной частью); без башни — по уровню снаряда.
static func src_strength(src: TowerState, data: GameData, special: String, key: String, lvl: int, fallback: Variant = 0.0) -> float:
	return src.strength(data, key, fallback) if src != null else float(data.special_effect(special, key, lvl, fallback))


static func _quake(c: CombatSystem, p: ProjectileState, target: EnemyState, src: TowerState, now: float) -> void:
	var data: GameData = c.data
	var lvl: int = p.special_level
	var radius: float = float(data.special_effect("quake_heart", "splash_radius", lvl, 1.0))
	var edge: float = float(data.special_effect("quake_heart", "splash_edge_mult", lvl, 1.0))
	var stun: float = float(data.special_effect("quake_heart", "stun", lvl, 0.0))
	for e: EnemyState in c.enemies_in(p.pos, radius):
		if e.flying or not e.alive:
			continue
		var k: float = 1.0 - (1.0 - edge) * clampf(e.pos.distance_to(p.pos) / radius, 0.0, 1.0)
		c.hit(e, p.damage * k, p.damage_type, src, e == target, now, false)
		if stun > 0.0 and e.alive:
			e.stun(now + stun * EnemyTraits.cc_factor(c, e))
	c.sim.emit_event({"type": "splash", "pos": p.pos, "radius": radius, "gem": p.gem_id})
	var every: int = int(data.special_effect("quake_heart", "shockwave_every", lvl, 0))
	if every <= 0 or p.shot % every != 0 or src == null:
		return
	var wave_r: float = float(data.special_effect("quake_heart", "shockwave_radius", lvl, 0.0))
	var dmg: float = p.damage * float(data.special_effect("quake_heart", "shockwave_mult", lvl, 0.0))
	for e2: EnemyState in c.enemies_in(src.pos, wave_r):
		if not e2.flying and e2.alive:
			c.hit(e2, dmg, p.damage_type, src, true, now, false)
	c.sim.emit_event({"type": "shockwave", "pos": src.pos, "radius": wave_r, "tower_id": src.id})


## Притяжение Gravity Geode L3: наземные враги впереди оглушённой цели оттягиваются к ней.
static func _pull(c: CombatSystem, center: EnemyState, radius: float) -> void:
	if center.flying:
		return
	var route: RoutePlanner = c.sim.route
	var pulled: int = 0
	for e: EnemyState in c.enemies_in(center.pos, radius):
		if e == center or e.flying or e.boss or e.cc_immune or not e.alive or e.dist <= center.dist:
			continue
		e.dist = center.dist
		e.place_on_path(route.ground_points, route.ground_cum)
		pulled += 1
	if pulled > 0:
		c.sim.emit_event({"type": "pull", "pos": center.pos, "radius": radius, "count": pulled})


static func _pierce(c: CombatSystem, p: ProjectileState, from: EnemyState) -> void:
	var best: EnemyState = null
	var best_d: float = INF
	for e: EnemyState in c.enemies_in(from.pos, PIERCE_SEARCH):
		if not e.alive or not e.flying or not e.visible or p.hit_ids.has(e.id):
			continue
		var d: float = e.pos.distance_squared_to(from.pos)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return
	var n: ProjectileState = ProjectileState.new()
	n.id = c.sim.new_id()
	n.source_id = p.source_id
	n.target_id = best.id
	n.gem_id = p.gem_id
	n.quality = p.quality
	n.special_level = p.special_level
	n.pierce_left = p.pierce_left - 1
	n.hit_ids = p.hit_ids.duplicate()
	n.damage = p.damage
	n.damage_type = p.damage_type
	n.speed = p.speed
	n.pos = from.pos
	n.prev_pos = from.pos
	n.target_pos = best.pos
	n.target_flying = true
	c.spawned.append(n)


static func add_pool(c: CombatSystem, at: Vector2, src: TowerState, lvl: int, now: float, radius_mult: float) -> void:
	if src == null:
		return
	var data: GameData = c.data
	var pool: Dictionary = {
		"pos": at,
		"radius": float(data.special_effect("blightbloom", "pool_radius", lvl, 1.0)) * radius_mult,
		"dps": src.strength(data, "pool_dps") * src.damage_mult(),
		"slow": src.strength(data, "pool_slow"),
		"stacks": int(data.special_effect("blightbloom", "pool_stacks", lvl, 1)),
		"until": now + float(data.special_effect("blightbloom", "pool_duration", lvl, 1.0)),
		"source": src.id,
	}
	c.sim.pools.append(pool)
	c.sim.emit_event({"type": "pool_created", "pos": at, "radius": pool["radius"], "duration": float(pool["until"]) - now})


static func update_pools(c: CombatSystem, dt: float, now: float) -> void:
	var sim: GameSim = c.sim
	if sim.pools.is_empty():
		return
	# Лужи бьют раз в dot_ticks тиков (как яд); метка и замедление держатся дольше этого шага.
	var dot_ticks: int = c.dot_every()
	if sim.tick % dot_ticks != 0:
		return
	dt *= float(dot_ticks)
	var alive: Array[Dictionary] = []
	for pool: Dictionary in sim.pools:
		if now < float(pool["until"]):
			alive.append(pool)
	sim.pools = alive
	var applied: Dictionary = {}
	for pool: Dictionary in sim.pools:
		var src: TowerState = c._tower_by_id(int(pool["source"]))
		for e: EnemyState in c.enemies_in(pool["pos"], float(pool["radius"])):
			if not e.alive or e.flying:
				continue
			var key: int = e.id * 4096 + int(pool["source"])
			var count: int = int(applied.get(key, 0))
			if count >= int(pool["stacks"]):
				continue
			applied[key] = count + 1
			e.blight_until = now + POOL_MARK
			e.blight_source = int(pool["source"])
			if float(pool["slow"]) > 0.0:
				e.apply_slow(float(pool["slow"]), now + FROST_REFRESH, now)
			c.hit(e, float(pool["dps"]) * dt, "nature", src, false, now, true)


static func on_kill(c: CombatSystem, e: EnemyState) -> void:
	var now: float = c.sim.wave_time
	if e.blight_source < 0 or now > e.blight_until:
		return
	var src: TowerState = c._tower_by_id(e.blight_source)
	if src == null or src.special_id != "blightbloom":
		return
	if int(c.data.special_effect("blightbloom", "explode", src.level, 0)) <= 0:
		return
	var radius: float = float(c.data.special_effect("blightbloom", "explode_radius", src.level, 1.0))
	var dmg: float = float(c.data.special_effect("blightbloom", "explode_mult", src.level, 0.0)) * src.effective_damage()
	c.sim.emit_event({"type": "blight_explode", "pos": e.pos, "radius": radius})
	add_pool(c, e.pos, src, src.level, now, 1.2)
	for o: EnemyState in c.enemies_in(e.pos, radius):
		if o != e and o.alive and not o.flying:
			c.hit(o, dmg, "nature", src, false, now, false)
