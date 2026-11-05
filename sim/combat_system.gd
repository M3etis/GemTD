class_name CombatSystem
extends RefCounted
## Боевая фаза: спавн, движение, трейты, статусы, выстрелы, снаряды, урон и смерти.

const HIT_RADIUS: float = 0.18
## Сколько держится дебафф ауры после выхода из радиуса (снижение брони Rust Obelisk).
const AURA_REFRESH: float = 0.2

## Ссылка на симуляцию держится только на время вызова (_bind/_unbind),
## чтобы не было цикла ссылок GameSim ↔ CombatSystem и утечки RefCounted.
var sim: GameSim
var data: GameData
var spatial: SpatialHash
var schedule: Array[Dictionary] = []
var schedule_index: int = 0
var _query: Array[EnemyState] = []
## Снаряды, созданные во время обработки снарядов (пробитие) — добавляются после цикла.
var spawned: Array[ProjectileState] = []
## Враги, появившиеся во время шага (раскол, призыв) — добавляются после циклов.
var pending: Array[EnemyState] = []
var _detectors: PackedVector3Array = PackedVector3Array()


func _init(game_data: GameData) -> void:
	data = game_data
	spatial = SpatialHash.new(float(data.economy["sim"]["spatial_bucket"]))


func begin_wave(owner: GameSim, wave_n: int) -> void:
	schedule = WaveSpawner.build_schedule(data, wave_n, owner.finale_for(wave_n))
	schedule_index = 0
	_reset_towers(owner)


## Испытание урона: вместо волны — один неуязвимый колосс.
func begin_damage_test(owner: GameSim) -> void:
	schedule = [{"time": 0.0, "type": "colossus", "hp_mult": 1.0, "traits": [], "elite": false, "order": 0}]
	schedule_index = 0
	_reset_towers(owner)


func _reset_towers(owner: GameSim) -> void:
	for t: TowerState in owner.towers:
		t.cooldown = 0.0
		t.disarmed_until = -1.0
		t.flash_timer = 0.0


func wave_finished(owner: GameSim) -> bool:
	return schedule_index >= schedule.size() and owner.enemies.is_empty() and pending.is_empty()


func recompute_auras(owner: GameSim) -> void:
	sim = owner
	_recompute_auras()
	sim = null


func _recompute_auras() -> void:
	var mvp_cfg: Dictionary = data.economy["mvp"]
	var mvp_cap: int = int(mvp_cfg["max_stacks"])
	for t: TowerState in sim.towers:
		var opal_speed: float = 0.0
		var beacon_speed: float = 0.0
		var beacon_range: float = 0.0
		var banner_damage: float = 0.0
		var banner_speed: float = 0.0
		var mvp_aura: float = 0.0
		for src: TowerState in sim.towers:
			if src == t:
				continue
			var d: float = t.pos.distance_to(src.pos)
			if src.gem_id == "opal" and d <= float(data.gem_effect("opal", "aura_radius", src.quality, 0.0)):
				opal_speed = maxf(opal_speed, float(data.gem_effect("opal", "aura_attack_speed", src.quality, 0.0)))
			elif src.special_id == "beacon_lens" and d <= float(data.special_effect("beacon_lens", "aura_radius", src.level, 0.0)):
				beacon_speed = maxf(beacon_speed, src.strength(data, "aura_attack_speed"))
				beacon_range = maxf(beacon_range, src.strength(data, "aura_range"))
			elif src.special_id == "warbanner_crystal" and d <= float(data.special_effect("warbanner_crystal", "aura_radius", src.level, 0.0)):
				banner_damage = maxf(banner_damage, src.strength(data, "aura_damage"))
				banner_speed = maxf(banner_speed, src.strength(data, "aura_speed"))
			if src.mvp >= mvp_cap and d <= float(mvp_cfg["aura_radius"]):
				mvp_aura = float(mvp_cfg["aura_damage"])
		# Ауры слейтов (Опаловая жила, Призрачный — скорость; Урона, Гадюка — урон): сильнейшая в своей
		# категории, складывается с аурами гемов и спец-башен, как в оригинале.
		var slate_speed: float = 0.0
		var slate_damage: float = 0.0
		for sl: TowerState in sim.slates:
			var r: float = float(data.slate_effect(sl.slate_id, "aura_radius", 0.0))
			if r > 0.0 and t.pos.distance_to(sl.pos) <= r:
				slate_speed = maxf(slate_speed, float(data.slate_effect(sl.slate_id, "aura_speed", 0.0)))
				slate_damage = maxf(slate_damage, float(data.slate_effect(sl.slate_id, "aura_damage", 0.0)))
		t.aura_speed_bonus = opal_speed + beacon_speed + banner_speed + slate_speed
		t.aura_range_bonus = beacon_range
		t.aura_damage_bonus = mvp_aura + banner_damage + slate_damage
		t.attack_range = t.base_range + t.aura_range_bonus


func step(owner: GameSim, dt: float) -> void:
	sim = owner
	var now: float = sim.wave_time
	_spawn(now)
	_update_enemies(dt, now)
	_flush_pending()
	_detectors = EnemyTraits.detectors(sim)
	var reveal_time: float = float(data.trait_cfg("shroud")["reveal_time"])
	spatial.clear()
	for e: EnemyState in sim.enemies:
		if e.alive:
			if e.shrouded:
				EnemyTraits.refresh_visibility(e, _detectors, now, reveal_time)
			spatial.insert(e)
	SpecialCombat.armor_auras(self, now)
	SlateCombat.step(self, dt, now)
	for t: TowerState in sim.towers:
		_update_tower(t, dt, now)
	SpecialCombat.update_pools(self, dt, now)
	_update_projectiles(dt, now)
	if not spawned.is_empty():
		sim.projectiles.append_array(spawned)
		spawned.clear()
	_compact()
	_flush_pending()
	sim = null


# --- Спавн и движение ------------------------------------------------------

func _spawn(now: float) -> void:
	while schedule_index < schedule.size() and float(schedule[schedule_index]["time"]) <= now + 0.00001:
		var entry: Dictionary = schedule[schedule_index]
		schedule_index += 1
		var e: EnemyState = spawn_enemy(String(entry["type"]), float(entry["hp_mult"]), entry["traits"], bool(entry["elite"]), 0.0)
		e.finale = bool(entry.get("finale", false))
		# Финальный босс короткого забега снимает у цитадели finale_leak жизней (20): Normal и Hard это не
		# переживают, Easy (30) — да. Иначе его утечка снимала лишь часть жизней, и финал почти не решал исход.
		if int(entry.get("leak", 0)) > 0:
			e.leak_damage = int(entry["leak"])
		if e.boss:
			sim.emit_event({"type": "boss_spawned", "id": e.id, "archetype": e.archetype, "finale": e.finale})


## Создаёт врага на расстоянии at_dist от начала его пути. Попадает в бой после текущего цикла.
func spawn_enemy(type: String, hp_mult: float, traits: Array, elite: bool, at_dist: float) -> EnemyState:
	var a: Dictionary = data.archetypes[type]
	var now: float = sim.wave_time
	var e: EnemyState = EnemyState.new()
	e.id = sim.new_id()
	e.archetype = type
	e.max_hp = data.enemy_base_hp(sim.hp_wave()) * float(a["hp_mult"]) * hp_mult * sim.diff_hp_mult()
	e.hp = e.max_hp
	e.armor = float(a["armor"])
	e.armor_type = a["armor_type"]
	e.base_speed = float(a["speed"])
	e.flying = bool(a["flying"])
	e.boss = bool(a["boss"])
	e.bounty = int(a["bounty"])
	e.leak_damage = int(a["leak_damage"])
	e.size = float(a["size"])
	if sim.wave_number > data.wave_count() and not sim.damage_test:
		# Бесконечный режим: с каждым кругом волн враги крепче и быстрее (и призванные боссами тоже).
		e.armor += data.endless_armor_bonus(sim.wave_number)
		e.base_speed *= data.endless_speed_mult(sim.wave_number)
	var points: PackedVector2Array = sim.route.air_points if e.flying else sim.route.ground_points
	var cum: PackedFloat64Array = sim.route.air_cum if e.flying else sim.route.ground_cum
	e.place_at_start(points)
	if at_dist > 0.0:
		e.dist = at_dist
		e.place_on_path(points, cum)
		e.prev_pos = e.pos
	EnemyTraits.setup(self, e, a, traits, elite, now)
	pending.append(e)
	sim.emit_event({"type": "enemy_spawned", "id": e.id, "archetype": e.archetype, "boss": e.boss, "flying": e.flying,
		"elite": e.elite, "traits": e.trait_list()})
	return e


func _flush_pending() -> void:
	if pending.is_empty():
		return
	for e: EnemyState in pending:
		sim.enemies.append(e)
		sim.enemy_by_id[e.id] = e
	pending.clear()


func _update_enemies(dt: float, now: float) -> void:
	_flush_pending()
	# Урон со временем (яд) начисляется раз в dot_ticks тиков тем же суммарным уроном — дешевле при 300 врагах.
	var dot_ticks: int = dot_every()
	var dot_now: bool = sim.tick % dot_ticks == 0
	for e: EnemyState in sim.enemies:
		if not e.alive:
			continue
		if e.dynamic:
			EnemyTraits.update(self, e, dt, now)
		if dot_now:
			_tick_poison(e, dt * float(dot_ticks), now)
		if not e.alive:
			continue
		var reached: bool
		if e.flying:
			reached = e.advance(dt, now, sim.route.air_points, sim.route.air_cum)
		else:
			reached = e.advance(dt, now, sim.route.ground_points, sim.route.ground_cum)
		if reached:
			if e.immortal:
				# Колосс Испытания урона идёт по лабиринту по кругу.
				e.place_at_start(sim.route.air_points if e.flying else sim.route.ground_points)
				sim.emit_event({"type": "enemy_looped", "id": e.id})
				continue
			e.alive = false
			e.leaked = true
			var instant: bool = e.boss and bool(sim.diff["boss_leak_instant_defeat"])
			sim.lose_lives(e.leak_damage, instant)
			EnemyTraits.on_leak(self, e)
			sim.emit_event({"type": "enemy_leaked", "id": e.id, "damage": e.leak_damage, "boss": e.boss})


func dot_every() -> int:
	return maxi(1, int(data.economy["sim"].get("dot_ticks", 1)))


func _tick_poison(e: EnemyState, dt: float, now: float) -> void:
	if e.poison.is_empty():
		return
	var i: int = 0
	while i < e.poison.size():
		var st: Dictionary = e.poison[i]
		if now >= float(st["until"]):
			e.poison.remove_at(i)
			continue
		var src: TowerState = _tower_by_id(int(st["source"]))
		hit(e, float(st["dps"]) * dt, "nature", src, false, now, true, true)
		if not e.alive:
			return
		i += 1


# --- Башни -----------------------------------------------------------------

func _update_tower(t: TowerState, dt: float, now: float) -> void:
	if not t.enabled or t.attack_kind == "none":
		return
	if now < t.disarmed_until:
		return
	match t.attack_kind:
		"aura_damage":
			SpecialCombat.aura_damage(self, t, dt, now)
			return
		"aura_slow":
			SpecialCombat.aura_slow(self, t, dt, now)
			return
	t.cooldown -= dt
	if t.cooldown > 0.0:
		return
	var target: EnemyState = _find_target(t)
	if target == null:
		t.cooldown = maxf(t.cooldown, 0.0)
		return
	_fire(t, target, now)
	t.cooldown += 1.0 / maxf(t.effective_attack_speed(), 0.05)


## Может ли башня задеть врага (тип цели). Площадные эффекты задевают и невидимых.
func _can_hit(t: TowerState, e: EnemyState) -> bool:
	return e.alive and ((e.flying and t.hits_air) or (not e.flying and t.hits_ground))


## Может ли башня выбрать врага целью: нужен ещё и видимый враг (Покров).
func can_target(t: TowerState, e: EnemyState) -> bool:
	return e.visible and _can_hit(t, e)


func _remaining(e: EnemyState) -> float:
	var total: float = sim.route.air_length if e.flying else sim.route.ground_length
	return total - e.dist


## Выбор цели по приоритету башни (меньше score — лучше).
func _find_target(t: TowerState) -> EnemyState:
	_query.clear()
	spatial.query(t.pos, t.attack_range, _query)
	var best: EnemyState = null
	var best_score: float = INF
	for e: EnemyState in _query:
		if not can_target(t, e):
			continue
		var score: float
		match t.targeting:
			"last":
				score = -_remaining(e)
			"strongest":
				score = -e.hp
			"weakest":
				score = e.hp
			"flying":
				score = _remaining(e) - (100000.0 if e.flying else 0.0)
			_:
				score = _remaining(e)
		if score < best_score:
			best_score = score
			best = e
	return best


func _fire(t: TowerState, target: EnemyState, now: float) -> void:
	t.attack_count += 1
	var dmg: float = t.effective_damage()
	var crit: bool = false
	if t.is_special():
		if t.special_id == "razor_prism":
			if sim.combat_rng.chance(float(data.special_effect("razor_prism", "crit_chance", t.level, 0.0))):
				crit = true
				dmg *= float(data.special_effect("razor_prism", "crit_mult", t.level, 1.0))
	else:
		match t.gem_id:
			"diamond":
				if sim.combat_rng.chance(float(data.gem_effect("diamond", "crit_chance", t.quality, 0.0))):
					crit = true
					dmg *= float(data.gem_effect("diamond", "crit_mult", t.quality, 1.0))
			"ruby":
				var every: int = int(data.gem_effect("ruby", "empowered_every", t.quality, 0))
				if every > 0 and t.attack_count % every == 0:
					crit = true
					dmg *= float(data.gem_effect("ruby", "empowered_mult", t.quality, 1.0))
	sim.emit_event({"type": "tower_fired", "tower_id": t.id, "gem": t.source_id(), "special": t.is_special(), "quality": t.quality,
		"from": t.pos, "to": target.pos, "flying": target.flying, "crit": crit})
	if t.projectile == "lightning":
		_chain_lightning(t, target, dmg, now)
		return
	var p: ProjectileState = ProjectileState.new()
	p.id = sim.new_id()
	p.source_id = t.id
	p.target_id = target.id
	p.gem_id = t.source_id()
	p.quality = t.quality if not t.is_special() else 3
	p.special_level = t.level if t.is_special() else 0
	p.pierce_left = int(data.special_effect(t.special_id, "pierce", t.level, 1)) - 1 if t.is_special() else 0
	p.damage = dmg
	p.damage_type = t.damage_type
	p.crit = crit
	p.shot = t.attack_count
	p.speed = maxf(t.projectile_speed, 1.0)
	p.pos = t.pos
	p.prev_pos = t.pos
	p.target_pos = target.pos
	p.target_flying = target.flying
	sim.projectiles.append(p)


## Цепная молния: Sapphire (параметры по качеству) или Stormspire (по уровню, с разрядами на L3).
func _chain_lightning(t: TowerState, first: EnemyState, dmg: float, now: float) -> void:
	var jumps: int
	var falloff: float
	var radius: float
	var discharge: float = 0.0
	if t.is_special():
		jumps = int(data.special_effect(t.special_id, "chain_targets", t.level, 1))
		falloff = float(data.special_effect(t.special_id, "chain_falloff", t.level, 1.0))
		radius = float(data.special_effect(t.special_id, "chain_radius", t.level, 2.0))
		discharge = float(data.special_effect(t.special_id, "discharge_chance", t.level, 0.0))
	else:
		jumps = int(data.gem_effect("sapphire", "chain_targets", t.quality, 1))
		falloff = float(data.gem_effect("sapphire", "chain_falloff", t.quality, 1.0))
		radius = float(data.gem_effect("sapphire", "chain_radius", t.quality, 2.0))
	var hit_ids: Dictionary = {}
	var points: PackedVector2Array = PackedVector2Array([t.pos])
	var flags: Array[bool] = []
	var current: EnemyState = first
	var amount: float = dmg
	for i: int in jumps:
		if current == null:
			break
		hit_ids[current.id] = true
		points.append(current.pos)
		flags.append(current.flying)
		var at: Vector2 = current.pos
		hit(current, amount, t.damage_type, t, false, now, false)
		if discharge > 0.0 and sim.combat_rng.chance(discharge):
			SpecialCombat.discharge(self, t, at, amount, now)
		amount *= falloff
		_query.clear()
		spatial.query(at, radius, _query)
		var next: EnemyState = null
		var best_d: float = INF
		for e: EnemyState in _query:
			if hit_ids.has(e.id) or not can_target(t, e):
				continue
			var d: float = e.pos.distance_squared_to(at)
			if d < best_d:
				best_d = d
				next = e
		current = next
	sim.emit_event({"type": "lightning", "tower_id": t.id, "points": points, "flying": flags, "quality": t.quality,
		"special": t.special_id})


# --- Снаряды ---------------------------------------------------------------

func _update_projectiles(dt: float, now: float) -> void:
	for p: ProjectileState in sim.projectiles:
		if not p.alive:
			continue
		var target: EnemyState = sim.enemy_by_id.get(p.target_id) as EnemyState
		if target != null and target.alive:
			p.target_pos = target.pos
		else:
			target = null
		p.prev_pos = p.pos
		var to_target: Vector2 = p.target_pos - p.pos
		var travel: float = p.speed * dt
		if to_target.length() <= travel + HIT_RADIUS:
			p.pos = p.target_pos
			p.alive = false
			_impact(p, target, now)
		else:
			p.pos += to_target.normalized() * travel


func _impact(p: ProjectileState, target: EnemyState, now: float) -> void:
	var src: TowerState = _tower_by_id(p.source_id)
	if p.special_level > 0:
		SpecialCombat.impact(self, p, target, src, now)
		return
	match p.gem_id:
		"topaz":
			var radius: float = float(data.gem_effect("topaz", "splash_radius", p.quality, 1.0))
			var edge: float = float(data.gem_effect("topaz", "splash_edge_mult", p.quality, 0.5))
			for e: EnemyState in enemies_in(p.pos, radius):
				if e.flying or not e.alive:
					continue
				var k: float = 1.0 - (1.0 - edge) * clampf(e.pos.distance_to(p.pos) / radius, 0.0, 1.0)
				hit(e, p.damage * k, p.damage_type, src, p.crit and e == target, now, false)
			sim.emit_event({"type": "splash", "pos": p.pos, "radius": radius, "gem": p.gem_id})
			return
	if target == null:
		return
	var dmg: float = p.damage
	if p.gem_id == "amethyst" and target.flying:
		dmg *= float(data.gem_effect("amethyst", "air_mult", p.quality, 1.0))
	hit(target, dmg, p.damage_type, src, p.crit, now, false)
	if not target.alive:
		return
	match p.gem_id:
		"aquamarine":
			var slow: float = float(data.gem_effect("aquamarine", "slow", p.quality, 0.0))
			if target.boss:
				slow *= float(data.gem_effect("aquamarine", "boss_slow_factor", p.quality, 1.0))
			target.apply_slow(slow, now + float(data.gem_effect("aquamarine", "slow_duration", p.quality, 1.0)), now)
		"emerald":
			_add_poison(target, p.source_id, p.quality, now)


func _add_poison(e: EnemyState, source: int, quality: int, now: float) -> void:
	if e.immune.has("nature"):
		return
	var dps: float = float(data.gem_effect("emerald", "poison_dps", quality, 0.0))
	var until: float = now + float(data.gem_effect("emerald", "poison_duration", quality, 1.0))
	var max_stacks: int = int(data.gem_effect("emerald", "poison_max_stacks", quality, 1))
	var spread: bool = int(data.gem_effect("emerald", "poison_spread_on_death", quality, 0)) > 0
	var stack: Dictionary = {"dps": dps, "until": until, "source": source, "spread": spread, "quality": quality}
	var own: Array[int] = []
	for i: int in e.poison.size():
		if int(e.poison[i]["source"]) == source:
			own.append(i)
	if own.size() < max_stacks:
		e.poison.append(stack)
		return
	var oldest: int = own[0]
	for i: int in own:
		if float(e.poison[i]["until"]) < float(e.poison[oldest]["until"]):
			oldest = i
	e.poison[oldest] = stack


# --- Урон и смерть ---------------------------------------------------------

## Удар по врагу: иммунитеты и уклонение, матрица урона, броня, дебаффы, Панцирь, щит.
## quiet — без события "hit" и без «ударных» трейтов (ауры, лужи, яд).
## dot — урон со временем (яд), он не проходит через матрицу брони повторно.
## pierce_armor — удар игнорирует броню полностью (крит Razor Prism L3).
func hit(e: EnemyState, base: float, dtype: String, src: TowerState, crit: bool, now: float, quiet: bool,
		dot: bool = false, pierce_armor: bool = false) -> void:
	if not e.alive or base <= 0.0:
		return
	if EnemyTraits.blocks_hit(self, e, dtype, quiet):
		return
	var amount: float
	if dot:
		amount = base * data.damage_mult(dtype, e.armor_type)
	else:
		var ignore: float = 0.0
		if src != null and src.gem_id == "diamond":
			ignore = float(data.gem_effect("diamond", "armor_ignore", src.quality, 0.0))
		var armor: float = e.effective_armor(now)
		if pierce_armor and armor > 0.0:
			armor = 0.0
		amount = DamageCalc.final_damage(data, base, dtype, e.armor_type, armor, ignore)
	amount *= e.damage_taken_mult(now)
	amount = EnemyTraits.absorb(self, e, amount, dtype, quiet)
	e.last_hit_time = now
	if e.shrouded:
		e.revealed_until = maxf(e.revealed_until, now + float(data.trait_cfg("shroud")["reveal_on_damage"]))
	if not quiet:
		sim.emit_event({"type": "hit", "enemy_id": e.id, "pos": e.pos, "flying": e.flying, "damage": amount, "dtype": dtype, "crit": crit,
			"gem": src.source_id() if src != null else ""})
	var dealt: float = _apply_damage(e, amount, src)
	if dealt > 0.0:
		var by_type: Dictionary = sim.stats["damage_by_type"]
		by_type[dtype] = float(by_type.get(dtype, 0.0)) + dealt


## Враги в радиусе (новый массив — безопасно для вложенных вызовов).
func enemies_in(center: Vector2, radius: float) -> Array[EnemyState]:
	var out: Array[EnemyState] = []
	spatial.query(center, radius, out)
	return out


## Возвращает урон, засчитанный в статистику (для колосса — весь, иначе не больше остатка HP).
func _apply_damage(e: EnemyState, amount: float, src: TowerState) -> float:
	if not e.alive or amount <= 0.0:
		return 0.0
	if e.immortal:
		e.absorbed += amount
		sim.test_damage += amount
		if src != null:
			src.test_damage += amount
		return 0.0
	var dealt: float = minf(amount, e.hp)
	e.hp -= amount
	sim.stats["total_damage"] = float(sim.stats["total_damage"]) + dealt
	sim.wave_damage_total += dealt
	if src != null:
		src.total_damage += dealt
		src.wave_damage += dealt
	if e.hp <= 0.0:
		_kill(e, src)
	return dealt


func _kill(e: EnemyState, killer: TowerState) -> void:
	e.alive = false
	e.hp = 0.0
	if killer != null:
		killer.kills += 1
	sim.stats["kills"] = int(sim.stats["kills"]) + 1
	var growth: float = float(data.economy["kill_bounty_wave_growth"])
	var bounty_f: float = float(e.bounty) * (1.0 + growth * float(sim.wave_number - 1)) * float(sim.diff["bounty_mult"])
	bounty_f *= 1.0 + SpecialCombat.idol_bonus(self, e.pos)
	if e.golden:
		bounty_f *= e.golden_mult
	var bounty: int = int(roundf(bounty_f))
	for t: TowerState in sim.towers:
		if t.gem_id != "opal":
			continue
		var extra: int = int(data.gem_effect("opal", "kill_gold", t.quality, 0))
		if extra > 0 and t.pos.distance_to(e.pos) <= float(data.gem_effect("opal", "kill_gold_radius", t.quality, 0.0)):
			bounty += extra
	sim.add_gold(bounty)
	sim.emit_event({"type": "enemy_died", "id": e.id, "pos": e.pos, "archetype": e.archetype,
		"flying": e.flying, "boss": e.boss, "elite": e.elite, "golden": e.golden, "bounty": bounty,
		"killer": killer.id if killer != null else -1})
	_spread_poison(e)
	SpecialCombat.on_kill(self, e)
	EnemyTraits.on_death(self, e)


func _spread_poison(e: EnemyState) -> void:
	for st: Dictionary in e.poison:
		if not bool(st["spread"]):
			continue
		for other: EnemyState in enemies_in(e.pos, 1.5):
			if other != e and other.alive:
				_add_poison(other, int(st["source"]), int(st["quality"]), sim.wave_time)
				break
		return


## Башня или слейт по id (источник яда и луж; продана — null).
func _tower_by_id(id: int) -> TowerState:
	var t: TowerState = sim.tower_by_id.get(id) as TowerState
	return t if t != null else sim.slate_by_id.get(id) as TowerState


func _compact() -> void:
	var alive_enemies: Array[EnemyState] = []
	for e: EnemyState in sim.enemies:
		if e.alive:
			alive_enemies.append(e)
		else:
			sim.enemy_by_id.erase(e.id)
	sim.enemies = alive_enemies
	var alive_projectiles: Array[ProjectileState] = []
	for p: ProjectileState in sim.projectiles:
		if p.alive:
			alive_projectiles.append(p)
	sim.projectiles = alive_projectiles
