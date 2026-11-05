extends TestCase
## Полоса HP босса: при двух живых боссах (финал 62-й — Матка Роя и Король) показывается главный — с наибольшим HP.


func _spawn(sim: GameSim, type: String, hp_mult: float) -> EnemyState:
	sim.combat.sim = sim
	var e: EnemyState = sim.combat.spawn_enemy(type, hp_mult, [], false, 5.0)
	sim.combat._flush_pending()
	sim.combat.sim = null
	return e


func _group_hp(wave: Dictionary, type: String) -> float:
	for grp: Dictionary in wave["groups"]:
		if String(grp["type"]) == type:
			return float(grp["hp_mult"])
	return 0.0


func test_bar_follows_the_main_boss_in_the_finale() -> void:
	var d: GameData = data()
	var finale: Dictionary = d.wave(d.wave_count())
	var sim: GameSim = new_sim(42, {"record_events": false})
	sim.wave_number = d.wave_count()
	var bar: BossBar = BossBar.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(bar)
	var mother: EnemyState = _spawn(sim, "boss_summoner", _group_hp(finale, "boss_summoner"))
	bar.update_from(sim)
	assert_eq(int(bar.get("_boss_id")), mother.id, "до выхода Короля — Матка")
	var king: EnemyState = _spawn(sim, "boss_final", _group_hp(finale, "boss_final"))
	assert_true(king.max_hp > mother.max_hp)
	bar.update_from(sim)
	assert_eq(int(bar.get("_boss_id")), king.id, "Король вышел — полоса его, хотя Матка раньше в списке")
	king.alive = false
	bar.update_from(sim)
	assert_eq(int(bar.get("_boss_id")), mother.id, "Король пал — снова Матка")
	bar.queue_free()
