extends TestCase
## Длина забега 20 / 42 / 62 с усиленным финалом и бесконечный режим «Гонки» (волны по кругу с ростом силы).


func test_run_lengths_and_finale_bosses() -> void:
	var d: GameData = data()
	assert_eq(d.run_lengths(), [20, 42, 62] as Array[int])
	assert_true(d.run_lengths().has(d.default_run_length()))
	for n: int in d.run_lengths():
		assert_true(d.is_boss_wave(n), "финал %d — волна с боссом" % n)
	for n2: int in [20, 42]:
		var sim: GameSim = new_sim(1, {"max_waves": n2})
		assert_true(sim.is_finale(n2), "финал %d усилен" % n2)
		assert_false(sim.is_finale(n2 - 1))
		var cfg: Dictionary = sim.finale_for(n2)
		var plain: Array[Dictionary] = WaveSpawner.build_schedule(d, n2)
		var boosted: Array[Dictionary] = WaveSpawner.build_schedule(d, n2, cfg)
		assert_eq(boosted.size(), plain.size())
		var bosses: int = 0
		for i: int in plain.size():
			var boss: bool = bool(d.archetype(String(plain[i]["type"]))["boss"])
			if boss:
				bosses += 1
				assert_true(bool(boosted[i]["elite"]) == (bool(cfg["finale_elite"]) or bool(plain[i]["elite"])), "элитный финальный босс")
				assert_true(bool(boosted[i]["finale"]))
				assert_near(float(boosted[i]["hp_mult"]), float(plain[i]["hp_mult"]) * float(cfg["finale_hp_mult"]))
			else:
				assert_near(float(boosted[i]["hp_mult"]), float(plain[i]["hp_mult"]), 0.0001, "свита не меняется")
		assert_true(bosses > 0)
	# Вся игра — финал 62-й волны и так самый сильный; нестандартная длина (автотест --waves=5) — без финала.
	assert_false(new_sim(1, {"max_waves": 62}).is_finale(62))
	assert_false(new_sim(1, {"max_waves": 5}).is_finale(5))


func test_finale_boss_spawns_elite() -> void:
	var sim: GameSim = new_sim(3, {"max_waves": 20})
	sim.round_index = 20
	sim.phase = GameSim.Phase.READY
	sim.wave_number = 19
	assert_true(sim.apply({"type": "start_wave"})["ok"])
	var seen: bool = false
	for i: int in 600:
		sim.step()
		for e: EnemyState in sim.enemies:
			if e.boss:
				seen = true
				assert_true(e.finale and e.elite, "финальный босс элитный")
		if seen:
			break
	assert_true(seen, "босс вышел")
	var started: Array = sim.drain_events().filter(func(e: Dictionary) -> bool: return String(e["type"]) == "wave_started")
	assert_true(bool((started[0] as Dictionary)["finale"]))


func test_short_run_scales_difficulty_ramp() -> void:
	var d: GameData = data()
	var full: GameSim = new_sim(1, {"difficulty": "extreme"})
	var cfg: Dictionary = d.run_length_cfg(20)
	var short: GameSim = new_sim(1, {"difficulty": "extreme", "max_waves": 20})
	var ramp: int = int(d.difficulty("extreme")["hp_ramp_waves"])
	assert_eq(int(full.diff["hp_ramp_waves"]), ramp)
	assert_eq(int(short.diff["hp_ramp_waves"]), maxi(1, roundi(float(ramp) * float(cfg["ramp_scale"]))))
	assert_eq(int(d.difficulty("extreme")["hp_ramp_waves"]), ramp, "данные сложности не меняются")


func test_endless_templates_cycle() -> void:
	var d: GameData = data()
	var n: int = d.wave_count()
	assert_eq(d.wave_template(n), n)
	assert_eq(d.wave_template(n + 1), 1)
	assert_eq(d.wave_template(2 * n + 5), 5)
	assert_eq(d.endless_cycle(n), 0)
	assert_eq(d.endless_cycle(n + 1), 1)
	assert_eq(d.endless_cycle(2 * n + 1), 2)
	for k: int in range(1, n + 1):
		assert_eq(d.is_air_wave(n + k), d.is_air_wave(k), "воздушные по шаблону %d" % k)
		assert_eq(d.is_boss_wave(n + k), d.is_boss_wave(k), "боссы по шаблону %d" % k)


## Продолжение сложности: суммарное HP волн второго круга не проваливается после финала и растёт дальше.
func test_endless_difficulty_continues() -> void:
	var d: GameData = data()
	var n: int = d.wave_count()
	var act2_ground: float = 0.0
	var cnt: int = 0
	for w: int in range(int(d.waves_cfg["endless"]["ref_from_wave"]), n + 1):
		if d.wave_kind(w) == "ground":
			act2_ground += _total_hp(d, w)
			cnt += 1
	act2_ground /= float(cnt)
	for w2: int in range(n + 1, n + 20):
		if d.wave_kind(w2) == "ground":
			assert_true(_total_hp(d, w2) >= act2_ground, "волна %d не легче среднего второго акта" % w2)
	assert_true(_total_hp(d, 2 * n + 1) > _total_hp(d, n + 1) * 2.0, "круг за кругом HP растёт")
	var summary: Dictionary = WaveSpawner.summary(d, n + 1)
	assert_true(int(summary["total"]) > int(WaveSpawner.summary(d, 1)["total"]), "врагов больше на втором круге")
	assert_eq(int(summary["cycle"]), 1)
	assert_true(d.endless_armor_bonus(n + 1) > 0.0)
	assert_true(d.endless_speed_mult(n + 1) > 1.0)
	assert_near(d.endless_speed_mult(100 * n), 1.0 + float(d.waves_cfg["endless"]["speed_cap"]), 0.0001, "скорость упирается в потолок")


func _total_hp(d: GameData, w: int) -> float:
	var total: float = 0.0
	for e: Dictionary in WaveSpawner.build_schedule(d, w):
		total += d.enemy_base_hp(w) * float(d.archetype(String(e["type"]))["hp_mult"]) * float(e["hp_mult"]) \
			* (float(d.economy["elite"]["hp_mult"]) if bool(e["elite"]) else 1.0)
	return total


func test_endless_sim_never_wins_and_replays() -> void:
	var sim: GameSim = new_sim(77, {"endless": true, "record_events": false})
	assert_true(sim.endless)
	assert_eq(sim.total_waves, 0)
	assert_eq(sim.wave_limit(), 1 << 30)
	assert_false(sim.is_finale(62))
	sim.round_index = 63
	sim.wave_number = 62
	sim.phase = GameSim.Phase.READY
	assert_eq(sim.next_wave_number(), 63)
	assert_true(sim.apply({"type": "start_wave"})["ok"])
	var e: EnemyState = null
	for i: int in 200:
		sim.step()
		if not sim.enemies.is_empty():
			e = sim.enemies[0]
			break
	assert_true(e != null)
	var a: Dictionary = sim.data.archetype(e.archetype)
	assert_near(e.armor, float(a["armor"]) + sim.data.endless_armor_bonus(63), 0.0001, "броня круга")
	assert_near(e.base_speed, float(a["speed"]) * sim.data.endless_speed_mult(63), 0.0001, "скорость круга")
	var played: GameSim = new_sim(5, {"endless": true, "record_events": false})
	var bot: BotPlayer = BotPlayer.new(played, "maze", played.seed_value)
	while played.round_index <= 3 and not played.is_over():
		if played.phase == GameSim.Phase.COMBAT:
			played.step()
		else:
			bot.act()
	assert_false(played.is_over())
	var header: Dictionary = Replay.from_sim(played, "test")
	assert_eq(int(header["max_waves"]), 0)
	assert_true(bool(header["endless"]))
	assert_true(Replay.well_formed(played.data, header))
	var rep: Dictionary = Replay.resimulate(played.data, header, played.tick)
	assert_true(bool(rep["ok"]))
	assert_eq(int(rep["checksum"]), played.checksum())
	assert_true((rep["sim"] as GameSim).endless)
	var bad: Dictionary = header.duplicate()
	bad["endless"] = false
	assert_false(Replay.well_formed(played.data, bad), "0 волн без бесконечного режима — испорченный файл")


func test_wave_fraction_text() -> void:
	assert_eq(UiTokens.wave_fraction(12, 42), "12/42")
	assert_eq(UiTokens.wave_fraction(70, 0), "70/∞")


## «Скорость»: победа короткого забега не обгоняет победу длинного — сначала число волн, затем время боя.
func test_speed_board_prefers_longer_runs() -> void:
	var saved: Array[Dictionary] = Leaderboard.records.duplicate()
	Leaderboard.records = [
		{"id": "a", "difficulty": "normal", "mode": "solo", "outcome": "victory", "combat_seconds": 600.0, "total_waves": 20, "date": "1"},
		{"id": "b", "difficulty": "normal", "mode": "solo", "outcome": "victory", "combat_seconds": 2400.0, "total_waves": 62, "date": "2"},
		{"id": "c", "difficulty": "normal", "mode": "solo", "outcome": "victory", "combat_seconds": 2200.0, "total_waves": 62, "date": "3"},
	] as Array[Dictionary]
	var ids: Array = Leaderboard.ranking("speed").map(func(r: Dictionary) -> String: return String(r["id"]))
	Leaderboard.records = saved
	assert_eq(ids, ["c", "b", "a"])


## Финальный босс короткого забега у цитадели снимает finale_leak (20) жизней: Normal — поражение, Easy (30) — нет.
## Обычный босс в середине полного забега снимает свои жизни и исход не решает.
func test_finale_boss_leak_takes_twenty_lives() -> void:
	for spec: Array in [["normal", true], ["easy", false]]:
		var sim: GameSim = new_sim(9, {"max_waves": 20, "difficulty": String(spec[0]), "record_events": false})
		assert_eq(int(sim.length_cfg["finale_leak"]), 20)
		_leak_boss(sim, true)
		assert_eq(sim.phase == GameSim.Phase.DEFEAT, bool(spec[1]), "финальный босс на %s" % spec[0])
		if not bool(spec[1]):
			assert_eq(sim.lives, sim.max_lives - 20)
	var plain: GameSim = new_sim(9, {"max_waves": 62, "record_events": false})
	_leak_boss(plain, false)
	assert_true(plain.lives > 0, "середина полного забега: босс снимает жизни, но не решает исход")


## Босс 20-й волны выходит через расписание (как в бою) и сразу оказывается у цитадели.
func _leak_boss(sim: GameSim, finale: bool) -> void:
	sim.combat.sim = sim
	sim.wave_number = 20
	sim.phase = GameSim.Phase.COMBAT
	var entries: Array[Dictionary] = WaveSpawner.build_schedule(sim.data, 20, sim.finale_for(20))
	var boss: Array[Dictionary] = []
	for en: Dictionary in entries:
		if String(en["type"]) == "boss_sky":
			boss.append(en)
	assert_eq(int(boss[0]["leak"]), 20 if finale else 0)
	sim.combat.schedule = boss
	sim.combat.schedule_index = 0
	sim.combat._spawn(1000.0)
	sim.combat._flush_pending()
	var e: EnemyState = sim.enemies[0]
	assert_eq(e.finale, finale)
	e.dist = sim.route.air_length - 0.01
	e.place_on_path(sim.route.air_points, sim.route.air_cum)
	for i: int in 30:
		sim.step()
		if sim.is_over():
			break


## Текст финала из данных: элита и утечка с перечнем сложностей, где её можно пережить; 62 — без пометок.
func test_finale_notes_text() -> void:
	var d: GameData = data()
	assert_eq(Ui.finale_notes(d, d.run_length_cfg(62)), "")
	assert_eq(Ui.finale_notes(d, {}), "")
	var notes: String = Ui.finale_notes(d, d.run_length_cfg(20))
	assert_true(notes.contains("20"), notes)
	assert_true(notes.contains(TranslationServer.translate("DIFF_EASY")), "Easy переживает утечку: " + notes)
	assert_false(notes.contains(TranslationServer.translate("DIFF_HARD")), notes)
	assert_true(NewGamePanel.length_tip(d, 5).contains("5"), "нестандартная длина без пустого списка боссов")
