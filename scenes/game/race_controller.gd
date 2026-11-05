class_name RaceController
extends RefCounted
## Игровая сцена в режиме «Гонка»: связывает RaceSession с HUD, вводом и визуалом.
## game — узел игровой сцены (Node, не RefCounted — цикла ссылок нет).

const T := preload("res://ui/theme/ui_tokens.gd")
const WATCH_TOAST_MS: int = 10000

var game: Node
var session: RaceSession
var panel: OpponentsPanel
var chat: ChatPanel
var _finished_local: bool = false
var _badge: PanelContainer
var _badge_label: Label
## Кнопка на плашке наблюдения: снова открыть экран продолжения (после выбывания).
var _badge_out: Button
## Экран продолжения после выбывания (null — закрыт).
var _out_panel: RaceOutPanel = null
var _out_victory: bool = false
## Когда последний раз показано «X наблюдает за вашим полем» (id → мс): перелистывание Tab не спамит.
var _watch_toast_at: Dictionary = {}


func _init(g: Node) -> void:
	game = g
	session = g.race
	panel = OpponentsPanel.new()
	var hud: Hud = g.hud
	hud.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -Hud.MARGIN
	panel.offset_top = 104
	hud.wave_panel.offset_top = 104 + 60 + 40 * session.config["players"].size()
	panel.watch_requested.connect(watch)
	panel.gift_requested.connect(_on_gift_requested)
	_badge = PanelContainer.new()
	_badge.theme_type_variation = "GlassPanel"
	_badge.material = Ui.glass_material()
	var row: HBoxContainer = Ui.hbox(T.SP_2)
	row.add_child(Ui.icon("target", 16, T.ACCENT))
	_badge_label = Ui.label("", "BodyLabel")
	row.add_child(_badge_label)
	_badge_out = Ui.button(TranslationServer.translate("MP_OUT_REOPEN"), "GhostButton", "menu")
	_badge_out.focus_mode = Control.FOCUS_NONE
	_badge_out.visible = false
	_badge_out.pressed.connect(open_out_panel)
	row.add_child(_badge_out)
	_badge.add_child(row)
	hud.add_child(_badge)
	_badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_badge.offset_top = 100
	_badge.visible = false
	# Чат — на своём слое поверх окон: его видно и в итогах матча («gg»).
	var chat_layer: CanvasLayer = CanvasLayer.new()
	chat_layer.layer = 11
	g.add_child(chat_layer)
	chat = ChatPanel.new()
	chat_layer.add_child(chat)
	chat.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	chat.offset_left = Hud.MARGIN
	chat.offset_top = 104
	chat.avoid = hud.tower_panel
	chat.typing_changed.connect(func(on: bool) -> void: g.cam.input_enabled = not on and not g.menu_open)
	session.begin_wave.connect(_on_begin_wave)
	session.force_build.connect(_on_force_build)
	session.speed_changed.connect(func(s: int) -> void:
		g.apply_speed(s)
		if not Net.is_host():
			Events.toast_requested.emit(TranslationServer.translate("MP_SPEED_SET") % s, "info"))
	session.paused_changed.connect(func(on: bool) -> void: g.apply_pause(on))
	session.match_ended.connect(_on_match_ended)
	session.player_out.connect(_on_player_out)
	session.watched_changed.connect(_on_watched)
	session.desync.connect(func(id: int, wave: int) -> void:
		Events.toast_requested.emit(TranslationServer.translate("MP_DESYNC") % [session.player_name(id), wave], "warning"))
	# Итоги при потере хоста показывает match_ended; здесь — причина (раньше её видело только лобби).
	Net.disconnected.connect(_on_net_disconnected)
	if not Net.is_host():
		hud.top.set_speed_enabled(false)
	# Скорость и пауза, заданные хостом, пока эта сцена грузилась.
	if session.speed != 1:
		g.apply_speed(session.speed)
	if session.paused:
		g.apply_pause(true)
	session.on_local_round_started(1)
	refresh()
	var shot: String = String(Game.cli.get("screenshot", ""))
	if shot == "race" or shot == "race_watch":
		_screenshot(shot)


func on_event(e: Dictionary) -> void:
	var sim: GameSim = game.sim
	var hud: Hud = game.hud
	match String(e["type"]):
		"gold_sent":
			hud.wave_panel.log_event(TranslationServer.translate("MP_LOG_GIFT_SENT") % [int(e["amount"]), session.player_name(int(e["to"]))], "coin", T.GOLD, "economy")
			Audio.play("sfx/economy/gold_gain")
			refresh()
		"gold_received":
			var from: String = session.player_name(int(e["from"]))
			Events.toast_requested.emit(TranslationServer.translate("MP_GIFT_RECEIVED") % [from, int(e["amount"])], "gold")
			hud.wave_panel.log_event(TranslationServer.translate("MP_LOG_GIFT_RECEIVED") % [from, int(e["amount"])], "coin", T.GOLD, "economy")
			Audio.play("sfx/economy/gold_gain")
			refresh()
		"round_started":
			session.on_local_round_started(int(e["round"]))
		"ready_for_wave":
			session.on_local_ready(int(e["wave"]))
		"wave_cleared":
			if not sim.wave_checksums.is_empty():
				session.on_local_wave_cleared(int(e["wave"]), int(sim.wave_checksums[sim.wave_checksums.size() - 1]["checksum"]))


func _on_begin_wave(round_index: int) -> void:
	var sim: GameSim = game.sim
	if sim.phase == GameSim.Phase.READY and sim.round_index == round_index:
		game._command({"type": "start_wave"})


## Таймер раунда вышел: достраиваем за игрока (детерминированно, командами — реплики их получат).
func _on_force_build(round_index: int) -> void:
	var sim: GameSim = game.sim
	if sim.round_index != round_index or not (sim.phase == GameSim.Phase.PLACING or sim.phase == GameSim.Phase.CHOOSING):
		return
	var helper: BotPlayer = BotPlayer.new(sim, "maze", sim.seed_value + round_index)
	helper.auto_start_wave = false
	var guard: int = 0
	while (sim.phase == GameSim.Phase.PLACING or sim.phase == GameSim.Phase.CHOOSING) and guard < 16:
		guard += 1
		helper.act()
	Events.toast_requested.emit(TranslationServer.translate("MP_FORCED"), "warning")


## Локальный игрок выбыл или прошёл все волны. Матч идёт дальше без него: если кто-то ещё играет —
## экран продолжения (наблюдать за соперником, остаться, выйти); итоги придут сами, когда закончат все.
func on_local_over(summary: Dictionary, victory: bool) -> void:
	_finished_local = true
	_out_victory = victory
	session.on_local_over(summary)
	var hud: Hud = game.hud
	hud.banner.show_banner(TranslationServer.translate("MP_FINISHED") if victory else TranslationServer.translate("MP_ELIMINATED"),
		TranslationServer.translate("MP_CONTINUE_HINT"), T.SUCCESS if victory else T.DANGER, 1.4)
	if _alive_opponent() >= 0 and not session.ended:
		if Game.cli.has("bot"):
			# Автотест двух процессов: без окна, сразу наблюдение (как раньше).
			watch(_alive_opponent())
		else:
			open_out_panel()


## Первый соперник, который ещё играет (-1 — никого).
func _alive_opponent() -> int:
	for id: int in session.replicas.keys():
		if not bool(session.replicas[id]["over"]):
			return id
	return -1


## Экран продолжения (после выбывания): Esc, кнопка на плашке наблюдения или само выбывание.
func open_out_panel() -> void:
	if not _finished_local or session.ended or is_instance_valid(_out_panel):
		return
	var sim: GameSim = game.sim
	_out_panel = RaceOutPanel.new().setup(_out_victory, int(sim.stats["waves_cleared"]), sim.endless, Net.is_host())
	_out_panel.watch_requested.connect(watch)
	_out_panel.stay_requested.connect(func() -> void: watch(session.local_id))
	_out_panel.leave_requested.connect(func() -> void:
		Net.leave()
		Audio.stop_loop("ambience/arena")
		Game.goto_scene("menu"))
	_out_panel.menu_requested.connect(func() -> void: game._open_pause_menu.call_deferred())
	# Закрыли крестиком или Esc — плашка с «Экран матча» должна остаться и на своём поле.
	_out_panel.closed.connect(_update_badge)
	_out_panel.update_rows(session.board_rows())
	game._open_modal(_out_panel)


func can_open_out_panel() -> bool:
	return _finished_local and not session.ended and not is_instance_valid(_out_panel)


func watch(id: int) -> void:
	var target: GameSim = game.sim if id == session.local_id else (session.replicas[id]["sim"] as GameSim if session.replicas.has(id) else null)
	if target == null:
		return
	var watched: int = id if id != session.local_id else -1
	if watched != panel.watching:
		if panel.watching >= 0:
			session.on_local_watch(panel.watching, false)
		if watched >= 0:
			session.on_local_watch(watched, true)
	panel.watching = watched
	game._bind_view(target)
	_update_badge()
	refresh()


## Плашка: чьё поле на экране; после выбывания — и на своём поле, с кнопкой экрана продолжения.
func _update_badge() -> void:
	var own: bool = panel.watching < 0
	var was: bool = _badge.visible
	_badge.visible = not own or (_finished_local and not session.ended)
	_badge_out.visible = _finished_local and not session.ended
	if not _badge.visible:
		return
	if own:
		_badge_label.text = String(TranslationServer.translate("MP_OWN_FIELD_OUT"))
	else:
		# После выбывания Esc открывает экран продолжения, а не возвращает к своему полю.
		_badge_label.text = String(TranslationServer.translate("MP_WATCHING_OUT" if _finished_local else "MP_WATCHING")) % session.player_name(panel.watching)
	if not was:
		Ui.pop_in(_badge, 0.0, Vector2.ZERO)


## Tab: следующее поле по кругу (свои → соперники → свои).
func watch_next() -> void:
	var ids: Array[int] = [session.local_id]
	for id: int in session.replicas.keys():
		ids.append(id)
	var cur: int = panel.watching if panel.watching >= 0 else session.local_id
	watch(ids[(ids.find(cur) + 1) % ids.size()])


func refresh() -> void:
	var timer: String = ""
	if session.timer_left > 0.0:
		timer = TranslationServer.translate("MP_TIMER") % T.format_time(session.timer_left)
	panel.update_rows(session.board_rows(), timer)
	if is_instance_valid(_out_panel):
		_out_panel.update_rows(session.board_rows())
	var sim: GameSim = game.sim
	if sim.phase == GameSim.Phase.READY and not _finished_local:
		var rc: Vector2i = session.ready_count()
		(game.hud as Hud).phase.show_waiting(sim.round_index, rc.x, rc.y, timer)


func _on_player_out(id: int, player: String, victory: bool) -> void:
	var hud: Hud = game.hud
	if session.replicas.has(id) and bool(session.replicas[id]["left"]):
		# Отключился, а не проиграл — «вышел», а не «выбыл».
		hud.wave_panel.log_event(TranslationServer.translate("NET_PLAYER_LEFT") % player, "close", T.TEXT_DIM)
		Audio.play("sfx/net/player_left")
	else:
		hud.wave_panel.log_event(TranslationServer.translate("MP_LOG_FINISHED" if victory else "MP_LOG_OUT") % player, "crown" if victory else "skull", T.GOLD if victory else T.DANGER)
		Audio.play("sfx/net/opponent_eliminated")
	if panel.watching == id:
		var other: int = _alive_opponent()
		if other >= 0:
			watch(other)
		elif _finished_local:
			watch(session.local_id)


## Клик по золоту соперника в панели игроков: окно суммы, затем команда give_gold
## (получатель зачислит золото своей командой receive_gold).
func _on_gift_requested(id: int) -> void:
	var sim: GameSim = game.sim
	if sim.gold <= 0:
		Events.toast_requested.emit(TranslationServer.translate("MP_GIFT_NO_GOLD"), "info")
		return
	var m: GiftGoldModal = GiftGoldModal.new().setup(session.player_name(id), sim.gold)
	m.gift.connect(func(amount: int) -> void: game._command({"type": "give_gold", "to": id, "amount": amount}))
	game._open_modal(m)


## Соперник смотрит наше поле: сообщение (не чаще раза в WATCH_TOAST_MS от одного игрока) и значок в панели игроков.
func _on_watched(id: int, on: bool) -> void:
	var now: int = Time.get_ticks_msec()
	if on and now - int(_watch_toast_at.get(id, -WATCH_TOAST_MS)) >= WATCH_TOAST_MS:
		_watch_toast_at[id] = now
		Events.toast_requested.emit(TranslationServer.translate("MP_WATCHED_BY") % session.player_name(id), "info")
	refresh()


func _on_net_disconnected(reason: String) -> void:
	Events.toast_requested.emit(TranslationServer.translate(reason), "error")


func _on_match_ended(standings: Array) -> void:
	var sim: GameSim = game.sim
	if is_instance_valid(_out_panel):
		_out_panel.closed.disconnect(_update_badge)
		_out_panel.close()
	_badge_out.visible = false
	var list: Array[Dictionary] = []
	for e: Variant in standings:
		list.append(e as Dictionary)
	var opponents: PackedStringArray = PackedStringArray()
	for e2: Dictionary in list:
		if int(e2["id"]) != session.local_id:
			opponents.append(String(e2["name"]))
	Leaderboard.submit_race(sim, {"place": session.local_place(), "players": list.size(), "opponents": opponents,
		"match_seed": int(session.config["match_seed"]), "real_seconds": float(game.real_time)})
	var verified: Dictionary = session.replicas_verified()
	var mp: MatchResultsPanel = MatchResultsPanel.new().setup(list, session.local_id, verified, Net.is_host() and Net.state == Net.State.IN_MATCH,
		sim.diff, sim.endless)
	mp.to_menu.connect(func() -> void:
		Net.leave()
		Audio.stop_loop("ambience/arena")
		Game.goto_scene("menu"))
	mp.to_lobby.connect(func() -> void:
		Net.back_to_lobby()
		Audio.stop_loop("ambience/arena")
		Game.goto_scene("lobby"))
	(game.ui_layer as CanvasLayer).add_child(mp)
	if Game.cli.has("bot"):
		_print_selftest(list, verified)


## Вывод для автотеста двух процессов (tools/mp_selftest.sh).
func _print_selftest(list: Array[Dictionary], verified: Dictionary) -> void:
	var sim: GameSim = game.sim
	var rep: Dictionary = Replay.simulate(sim.data, Replay.from_sim(sim, Game.version()))
	var all_ok: bool = bool(rep["ok"])
	for id: int in verified.keys():
		all_ok = all_ok and bool(verified[id])
	var lines: PackedStringArray = PackedStringArray()
	for e: Dictionary in list:
		lines.append("#%d %s волн %d жизней %d" % [int(e["place"]), String(e["name"]), int(e["waves_cleared"]), int(e["lives"])])
	print("MP-STANDINGS " + " | ".join(lines))
	print("MP-CHECK own_replay=%s replicas=%s" % [str(rep["ok"]), str(verified)])
	print("MP-OK" if all_ok and list.size() >= 2 else "MP-FAIL")
	Audio.stop_all()
	game.get_tree().create_timer(0.5).timeout.connect(func() -> void:
		Net.leave()
		game.get_tree().quit(0 if all_ok else 3))


func _screenshot(shot: String) -> void:
	var tree: SceneTree = game.get_tree()
	await tree.create_timer(14.0).timeout
	if shot == "race_watch":
		for id: int in session.replicas.keys():
			watch(id)
			break
	await tree.create_timer(6.0).timeout
	await Game.save_screenshot(shot)
	Net.leave()
	tree.quit()
