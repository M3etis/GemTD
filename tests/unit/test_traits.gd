extends TestCase
## Трейты врагов, элита, щит и раскол (§6.4 PROMPT.md).


## Враг вне расписания волны; бой привязан к симуляции только на время вызова.
func _enemy(sim: GameSim, type: String, traits: Array = [], elite: bool = false, at: float = 5.0) -> EnemyState:
	var c: CombatSystem = sim.combat
	c.sim = sim
	var e: EnemyState = c.spawn_enemy(type, 1.0, traits, elite, at)
	c._flush_pending()
	c.sim = null
	return e


func _hit(sim: GameSim, e: EnemyState, amount: float, dtype: String, now: float = 1.0, quiet: bool = false) -> float:
	var before: float = e.hp + e.shield
	sim.combat.sim = sim
	sim.combat.hit(e, amount, dtype, null, false, now, quiet)
	sim.combat.sim = null
	return before - (e.hp + e.shield)


func _update(sim: GameSim, e: EnemyState, now: float, dt: float = 1.0 / 30.0) -> void:
	sim.combat.sim = sim
	EnemyTraits.update(sim.combat, e, dt, now)
	sim.combat._flush_pending()
	sim.combat.sim = null


func test_all_traits_have_texts_and_configs() -> void:
	var d: GameData = data()
	assert_eq(d.traits.size(), 12)
	for id: String in ["rush", "blink", "regen", "evasion", "antimagic", "ethereal", "refraction", "hardening", "disarm", "thief", "shroud", "carapace"]:
		assert_true(d.traits.has(id), "нет трейта " + id)
		var cfg: Dictionary = d.trait_cfg(id)
		for key: String in ["name_key", "desc_key", "counter_key"]:
			assert_ne(TranslationServer.translate(String(cfg[key])), StringName(String(cfg[key])), "нет перевода " + String(cfg[key]))


func test_antimagic_immune_to_arcane_and_control() -> void:
	var sim: GameSim = new_sim()
	var e: EnemyState = _enemy(sim, "normal", ["antimagic"])
	assert_near(_hit(sim, e, 50.0, "arcane"), 0.0)
	assert_true(_hit(sim, e, 50.0, "siege") > 0.0)
	e.apply_slow(0.5, 5.0, 1.0)
	assert_near(e.current_slow(1.5), 0.0)
	assert_false(e.stun(5.0))


func test_ethereal_immune_to_physical() -> void:
	var sim: GameSim = new_sim()
	var e: EnemyState = _enemy(sim, "normal", ["ethereal"])
	assert_near(_hit(sim, e, 50.0, "physical"), 0.0)
	assert_true(_hit(sim, e, 50.0, "fire") > 0.0)


func test_evasion_dodges_only_physical_and_pierce() -> void:
	var sim: GameSim = new_sim()
	var e: EnemyState = _enemy(sim, "armored", ["evasion"])
	e.max_hp = 1.0e9
	e.hp = e.max_hp
	var dodged: int = 0
	for i: int in 400:
		if _hit(sim, e, 10.0, "physical") <= 0.0:
			dodged += 1
	assert_true(dodged > 40 and dodged < 130, "уклонение ~20%%, получено %d из 400" % dodged)
	for i2: int in 50:
		assert_true(_hit(sim, e, 10.0, "arcane") > 0.0)


func test_refraction_absorbs_first_hits() -> void:
	var sim: GameSim = new_sim()
	var e: EnemyState = _enemy(sim, "normal", ["refraction"])
	var charges: int = int(data().trait_cfg("refraction")["charges"])
	for i: int in charges:
		assert_near(_hit(sim, e, 5.0, "fire"), 0.0)
	assert_true(_hit(sim, e, 5.0, "fire") > 0.0)
	# Урон со временем заряды не тратит.
	var e2: EnemyState = _enemy(sim, "normal", ["refraction"])
	assert_true(_hit(sim, e2, 5.0, "nature", 1.0, true) > 0.0)
	assert_eq(e2.refraction, charges)


func test_hardening_adds_armor_up_to_cap() -> void:
	var sim: GameSim = new_sim()
	var e: EnemyState = _enemy(sim, "normal", ["hardening"])
	e.max_hp = 1.0e9
	e.hp = e.max_hp
	var cfg: Dictionary = data().trait_cfg("hardening")
	for i: int in int(cfg["hits_per_armor"]) * 2:
		_hit(sim, e, 1.0, "fire")
	assert_near(e.hardening_bonus, 2.0)
	for i2: int in 200:
		_hit(sim, e, 1.0, "fire")
	assert_near(e.hardening_bonus, float(cfg["max_bonus"]))


func test_carapace_blocks_flat_damage_and_cleanses() -> void:
	var sim: GameSim = new_sim()
	var e: EnemyState = _enemy(sim, "normal", ["carapace"])
	assert_true(e.carapace_block > 0.0)
	assert_near(_hit(sim, e, e.carapace_block * 0.5, "pure"), 0.0)
	var big: float = e.carapace_block * 3.0
	assert_near(_hit(sim, e, big, "pure"), big - e.carapace_block, 0.01)
	e.apply_slow(0.4, 100.0, 1.0)
	_update(sim, e, e.carapace_next + 0.01)
	assert_near(e.current_slow(e.carapace_next - 1.0), 0.0, 0.0001, "панцирь снимает замедление")


func test_regen_heals_and_poison_halves_it() -> void:
	var sim: GameSim = new_sim()
	var a: EnemyState = _enemy(sim, "regenerating")
	var b: EnemyState = _enemy(sim, "regenerating")
	a.hp = a.max_hp * 0.5
	b.hp = b.max_hp * 0.5
	b.poison.append({"dps": 0.0, "until": 100.0, "source": -1, "spread": false, "quality": 1})
	for i: int in 30:
		_update(sim, a, 1.0 + float(i) / 30.0)
		_update(sim, b, 1.0 + float(i) / 30.0)
	var heal_a: float = a.hp - a.max_hp * 0.5
	var heal_b: float = b.hp - b.max_hp * 0.5
	assert_near(heal_a, a.max_hp * float(data().trait_cfg("regen")["pct_per_sec"]), a.max_hp * 0.002)
	assert_near(heal_b, heal_a * (1.0 - float(data().gem_effect("emerald", "poison_regen_cut", 1, 0.0))), a.max_hp * 0.002)


func test_rush_doubles_speed_below_threshold() -> void:
	var sim: GameSim = new_sim()
	var e: EnemyState = _enemy(sim, "normal", ["rush"])
	var base: float = e.current_speed(1.0)
	_update(sim, e, 1.0)
	assert_near(e.current_speed(1.0), base)
	e.hp = e.max_hp * 0.4
	_update(sim, e, 1.0)
	assert_near(e.current_speed(1.5), base * 2.0)
	assert_near(e.current_speed(1.0 + float(data().trait_cfg("rush")["duration"]) + 0.1), base)


func test_blink_teleports_forward() -> void:
	var sim: GameSim = new_sim()
	var e: EnemyState = _enemy(sim, "normal", ["blink"])
	var before: float = e.dist
	_update(sim, e, e.blink_next)
	assert_near(e.dist, before + float(data().trait_cfg("blink")["distance"]))


func test_disarm_silences_nearby_towers() -> void:
	var sim: GameSim = new_sim()
	var e: EnemyState = _enemy(sim, "normal", ["disarm"], false, 0.0)
	var near_cell: Vector2i = Vector2i(e.pos.floor()) + Vector2i(1, 0)
	if not sim.grid.is_buildable(near_cell):
		near_cell = Vector2i(e.pos.floor()) + Vector2i(0, 1)
	var t: TowerState = sim.add_gem_tower(near_cell, "ruby", 1)
	var far: TowerState = add_tower(sim, 0, "ruby", 1)
	_update(sim, e, 2.0)
	assert_true(t.disarmed_until > 2.0, "соседняя башня отключена")
	assert_true(far.disarmed_until < 0.0, "дальняя башня работает")


func test_thief_steals_gold_on_leak() -> void:
	var sim: GameSim = new_sim()
	sim.gold = 100
	var e: EnemyState = _enemy(sim, "fast", ["thief"])
	assert_true(e.thief_gold > 0)
	sim.combat.sim = sim
	EnemyTraits.on_leak(sim.combat, e)
	sim.combat.sim = null
	assert_eq(sim.gold, 100 - e.thief_gold)


func test_shroud_needs_detection() -> void:
	var sim: GameSim = new_sim()
	var e: EnemyState = _enemy(sim, "normal", ["shroud"])
	var reveal: float = float(data().trait_cfg("shroud")["reveal_time"])
	EnemyTraits.refresh_visibility(e, PackedVector3Array(), 1.0, reveal)
	assert_false(e.visible, "без обнаружения невидим")
	EnemyTraits.refresh_visibility(e, PackedVector3Array([Vector3(e.pos.x, e.pos.y, 1.0)]), 1.0, reveal)
	assert_true(e.visible)
	EnemyTraits.refresh_visibility(e, PackedVector3Array(), 1.0 + reveal * 0.5, reveal)
	assert_true(e.visible, "остаётся видимым reveal_time секунд")
	EnemyTraits.refresh_visibility(e, PackedVector3Array(), 1.0 + reveal + 0.1, reveal)
	assert_false(e.visible)
	# Урон по площади проявляет врага.
	_hit(sim, e, 1.0, "fire", 10.0, true)
	EnemyTraits.refresh_visibility(e, PackedVector3Array(), 10.5, reveal)
	assert_true(e.visible)
	# Opal на поле — обнаружитель.
	add_tower(sim, 0, "opal", 1)
	assert_eq(EnemyTraits.detectors(sim).size(), 1)


func test_elite_multipliers() -> void:
	var sim: GameSim = new_sim()
	var plain: EnemyState = _enemy(sim, "armored")
	var elite: EnemyState = _enemy(sim, "armored", [], true)
	var ec: Dictionary = data().economy["elite"]
	assert_near(elite.max_hp, plain.max_hp * float(ec["hp_mult"]), 0.01)
	assert_near(elite.armor, plain.armor + float(ec["armor_bonus"]))
	assert_eq(elite.leak_damage, plain.leak_damage * int(ec["leak_mult"]))
	assert_true(elite.elite)


func test_shield_absorbs_before_hp() -> void:
	var sim: GameSim = new_sim()
	var e: EnemyState = _enemy(sim, "shielded")
	assert_near(e.shield, e.max_hp * float(data().archetype("shielded")["shield_pct"]), 0.01)
	_hit(sim, e, e.shield * 0.5 / 1.0, "pure")
	assert_near(e.hp, e.max_hp, 0.01, "HP не тронуто, пока есть щит")


func test_splitter_splits_on_death() -> void:
	var sim: GameSim = new_sim()
	var e: EnemyState = _enemy(sim, "splitter")
	var before: int = sim.enemies.size()
	sim.combat.sim = sim
	sim.combat.hit(e, 1.0e9, "pure", null, false, 1.0, false)
	sim.combat._flush_pending()
	sim.combat.sim = null
	assert_false(e.alive)
	var split: Dictionary = data().archetype("splitter")["split"]
	assert_eq(sim.enemies.size(), before + int(split["count"]))
	assert_eq(sim.enemies[sim.enemies.size() - 1].archetype, String(split["type"]))
