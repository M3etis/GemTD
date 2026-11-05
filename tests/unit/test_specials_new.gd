extends TestCase
## Восемь спец-башен этапа 4: эффекты по данным specials.json.


func _special(sim: GameSim, cell: Vector2i, id: String, level: int) -> TowerState:
	var t: TowerState = sim.add_special_tower(cell, id)
	t.level = level
	t.refresh_stats(sim.data)
	sim.route.recompute()
	sim.combat.recompute_auras(sim)
	return t


## Волна с одной спец-башней у начала маршрута; возвращает события за N секунд.
func _run(id: String, level: int, seconds: float, wave: int = 1, seed_value: int = 11) -> Dictionary:
	var sim: GameSim = new_sim(seed_value)
	var t: TowerState = _special(sim, Vector2i(3, 7), id, level)
	sim.round_index = wave
	sim.phase = GameSim.Phase.READY
	sim.apply({"type": "start_wave"})
	var events: Array[Dictionary] = []
	for i: int in int(seconds * 30.0):
		if sim.phase != GameSim.Phase.COMBAT:
			break
		sim.step()
		events.append_array(sim.drain_events())
	return {"sim": sim, "tower": t, "events": events}


func _count(events: Array[Dictionary], type: String) -> int:
	var n: int = 0
	for e: Dictionary in events:
		if String(e["type"]) == type:
			n += 1
	return n


func _enemy(sim: GameSim, type: String, traits: Array = []) -> EnemyState:
	sim.combat.sim = sim
	var e: EnemyState = sim.combat.spawn_enemy(type, 1.0, traits, false, 5.0)
	sim.combat._flush_pending()
	sim.combat.sim = null
	return e


func test_all_thirteen_specials_present() -> void:
	var d: GameData = data()
	assert_eq(d.specials.size(), 13)
	for sp: Dictionary in d.specials:
		assert_ne(TranslationServer.translate(String(sp["name_key"])), StringName(String(sp["name_key"])), "перевод " + String(sp["name_key"]))
		assert_false(SpecialText.describe(d, String(sp["id"]), 1).is_empty(), "описание " + String(sp["id"]))
		assert_false(SpecialText.describe(d, String(sp["id"]), 3).is_empty())


func test_rust_obelisk_shreds_armor_and_strips_shield() -> void:
	var sim: GameSim = new_sim()
	var t: TowerState = _special(sim, Vector2i(3, 7), "rust_obelisk", 3)
	var e: EnemyState = _enemy(sim, "shielded", ["refraction"])
	e.pos = t.pos + Vector2(1.0, 0.0)
	sim.combat.sim = sim
	sim.combat.spatial.clear()
	sim.combat.spatial.insert(e)
	SpecialCombat.armor_auras(sim.combat, 1.0)
	assert_near(e.effective_armor(1.05), e.armor - float(data().special_effect("rust_obelisk", "armor_reduction", 3, 0.0)))
	var p: ProjectileState = ProjectileState.new()
	p.gem_id = "rust_obelisk"
	p.special_level = 3
	p.damage = 10.0
	p.damage_type = "physical"
	SpecialCombat.impact(sim.combat, p, e, t, 1.0)
	sim.combat.sim = null
	assert_near(e.shield, 0.0)
	assert_eq(e.refraction, 0)


func test_gravity_geode_stuns() -> void:
	# 200 попаданий по крепкой цели: доля оглушений близка к шансу из данных.
	var sim: GameSim = new_sim()
	var t: TowerState = _special(sim, Vector2i(3, 7), "gravity_geode", 2)
	var e: EnemyState = _enemy(sim, "armored")
	e.max_hp = 1.0e9
	e.hp = e.max_hp
	var p: ProjectileState = ProjectileState.new()
	p.gem_id = "gravity_geode"
	p.special_level = 2
	p.damage = 1.0
	p.damage_type = "arcane"
	var stuns: int = 0
	sim.combat.sim = sim
	for i: int in 200:
		var now: float = float(i) * 10.0
		SpecialCombat.impact(sim.combat, p, e, t, now)
		if e.is_stunned(now + 0.01):
			stuns += 1
	sim.combat.sim = null
	var chance: float = float(data().special_effect("gravity_geode", "stun_chance", 2, 0.0))
	assert_true(stuns > int(200.0 * chance * 0.4) and stuns < int(200.0 * chance * 1.8), "оглушений %d из 200" % stuns)
	# Антимагия защищает от оглушения.
	var am: EnemyState = _enemy(sim, "armored", ["antimagic"])
	assert_false(am.stun(5.0))


func test_stormspire_chains() -> void:
	# 6-я волна — плотный рой: цепи есть куда прыгать.
	var r: Dictionary = _run("stormspire", 1, 25.0, 6)
	var max_points: int = 0
	for e: Dictionary in r["events"]:
		if String(e["type"]) == "lightning":
			assert_eq(String(e["special"]), "stormspire")
			max_points = maxi(max_points, (e["points"] as PackedVector2Array).size())
	assert_true(max_points >= 3, "цепь прыгает минимум на 2 цели")


func test_razor_prism_crits() -> void:
	var r: Dictionary = _run("razor_prism", 1, 25.0)
	var crits: int = 0
	for e: Dictionary in r["events"]:
		if String(e["type"]) == "tower_fired" and bool(e["crit"]):
			crits += 1
	assert_true(crits > 0)


func test_quake_heart_splash_stun_shockwave() -> void:
	var r: Dictionary = _run("quake_heart", 3, 25.0)
	assert_true(_count(r["events"], "splash") > 0)
	assert_true(_count(r["events"], "shockwave") > 0, "L3: каждый 5-й выстрел — ударная волна")


func test_gilded_idol_bounty_and_wave_gold() -> void:
	var sim: GameSim = new_sim()
	var t: TowerState = _special(sim, Vector2i(3, 7), "gilded_idol", 2)
	sim.combat.sim = sim
	assert_near(SpecialCombat.idol_bonus(sim.combat, t.pos + Vector2(1, 0)), float(data().special_effect("gilded_idol", "bounty_bonus", 2, 0.0)))
	assert_near(SpecialCombat.idol_bonus(sim.combat, t.pos + Vector2(20, 0)), 0.0)
	sim.combat.sim = null
	assert_eq(SpecialCombat.idol_wave_gold(sim), int(data().special_effect("gilded_idol", "wave_gold", 2, 0)))


func test_warbanner_boosts_neighbors() -> void:
	var sim: GameSim = new_sim()
	var g: TowerState = add_tower(sim, 0, "ruby", 1)
	var before: float = g.damage_mult()
	_special(sim, Vector2i(31, 23), "warbanner_crystal", 3)
	assert_near(g.damage_mult(), before + float(data().special_effect("warbanner_crystal", "aura_damage", 3, 0.0)))
	assert_true(g.aura_speed_bonus >= float(data().special_effect("warbanner_crystal", "aura_speed", 3, 0.0)))


func test_titanbane_percent_damage_and_strip() -> void:
	var sim: GameSim = new_sim()
	var t: TowerState = _special(sim, Vector2i(3, 7), "titanbane", 3)
	var boss: EnemyState = _enemy(sim, "boss_final")
	boss.shield = 0.0
	var p: ProjectileState = ProjectileState.new()
	p.gem_id = "titanbane"
	p.special_level = 3
	p.damage = 0.0
	p.damage_type = "pure"
	sim.combat.sim = sim
	SpecialCombat.impact(sim.combat, p, boss, t, 1.0)
	sim.combat.sim = null
	var pct: float = float(data().special_effect("titanbane", "hp_pct", 3, 0.0)) * float(data().special_effect("titanbane", "elite_mult", 3, 1.0))
	assert_near(boss.max_hp - boss.hp, boss.max_hp * pct, 1.0)
	assert_near(boss.carapace_block, 0.0, 0.0001, "L3 снимает Панцирь")
