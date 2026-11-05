extends Node
## Мультиплеер: создание игры, поиск в LAN, подключение по IP, комната лобби (игроки, настройки, чат).
## CLI для автотеста: --mp-host [--port=N] --bot  |  --mp-join=IP [--port=N] --bot

const T := preload("res://ui/theme/ui_tokens.gd")

var _ui: Control
var _content: Control
var _status: Label
var _lan_list: VBoxContainer
var _chat_log: VBoxContainer
var _chat_scroll: ScrollContainer
var _players_box: VBoxContainer
var _settings_box: VBoxContainer
var _start_btn: Button
var _ready_btn: Button
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _port_edit: LineEdit
var _mode: String = ""
var _bot_started: bool = false


func _ready() -> void:
	Audio.music("menu")
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = ThemeBuilder.get_theme()
	add_child(_ui)
	var bg: ColorRect = ColorRect.new()
	bg.color = T.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(bg)
	var glow: TextureRect = TextureRect.new()
	var grad: GradientTexture2D = GradientTexture2D.new()
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(0.25, 0.4, 0.9, 0.22))
	g.set_color(1, Color(0, 0, 0, 0))
	grad.gradient = g
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.0)
	grad.fill_to = Vector2(1.0, 0.9)
	glow.texture = grad
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(glow)
	var toasts: ToastLayer = ToastLayer.new()
	_ui.add_child(toasts)
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toasts.offset_top = 24
	Net.lobby_updated.connect(_on_lobby_updated)
	Net.state_changed.connect(_rebuild)
	Net.match_started.connect(_on_match_started)
	Net.connection_failed.connect(func(reason: String) -> void:
		Events.toast_requested.emit(tr(reason), "error")
		_rebuild())
	Net.disconnected.connect(func(reason: String) -> void:
		Events.toast_requested.emit(tr(reason), "error")
		_rebuild())
	Net.chat_received.connect(_on_chat)
	Net.discovery.hosts_changed.connect(_refresh_lan)
	_rebuild()
	Audio.play_loop("ambience/arena")
	_cli_autostart.call_deferred()


func _exit_tree() -> void:
	Net.discovery.stop_listen()


func _rebuild() -> void:
	var mode: String = "room" if Net.state == Net.State.LOBBY else "hub"
	if mode == _mode and _content != null:
		return
	_mode = mode
	if _content != null:
		_content.queue_free()
	_content = MarginContainer.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		_content.add_theme_constant_override("margin_" + side, 96)
	for side2: String in ["top", "bottom"]:
		_content.add_theme_constant_override("margin_" + side2, 64)
	_ui.add_child(_content)
	_ui.move_child(_content, 2)
	if mode == "room":
		Net.discovery.stop_listen()
		_build_room()
		_on_lobby_updated()
	else:
		_build_hub()
		if not Net.discovery.start_listen():
			_lan_note(tr("MP_LAN_BUSY"))
	Ui.pop_in(_content, 0.0, Vector2.ZERO)


# --- Хаб ------------------------------------------------------------------

func _build_hub() -> void:
	var col: VBoxContainer = Ui.vbox(T.SP_4)
	_content.add_child(col)
	col.add_child(_title_row(tr("MP_TITLE"), tr("MP_SUBTITLE")))
	var name_row: HBoxContainer = Ui.hbox(T.SP_3)
	name_row.add_child(Ui.label(tr("SETTINGS_PLAYER_NAME"), "CapsLabel"))
	_name_edit = LineEdit.new()
	_name_edit.text = Settings.player_name()
	_name_edit.max_length = NetProtocol.NAME_MAX
	_name_edit.custom_minimum_size = Vector2(280, 0)
	_name_edit.text_changed.connect(func(t: String) -> void: Settings.set_value("general", "player_name", t.strip_edges()))
	name_row.add_child(_name_edit)
	col.add_child(name_row)
	var row: HBoxContainer = Ui.hbox(T.SP_5)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	var host_card: PanelContainer = Ui.panel("GlassPanel")
	host_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hv: VBoxContainer = Ui.vbox(T.SP_3)
	host_card.add_child(hv)
	hv.add_child(Ui.label(tr("MP_HOST_TITLE"), "HeaderLabel"))
	var hint: Label = Ui.label(tr("MP_HOST_HINT"), "DimLabel", true)
	hint.custom_minimum_size = Vector2(420, 0)
	hv.add_child(hint)
	var port_row: HBoxContainer = Ui.hbox(T.SP_2)
	port_row.add_child(Ui.label(tr("MP_PORT"), "CapsLabel"))
	_port_edit = LineEdit.new()
	_port_edit.text = str(NetProtocol.DEFAULT_PORT)
	_port_edit.custom_minimum_size = Vector2(120, 0)
	port_row.add_child(_port_edit)
	hv.add_child(port_row)
	var addrs: PackedStringArray = LanDiscovery.local_addresses()
	var ip_row: HBoxContainer = Ui.hbox(T.SP_2)
	ip_row.add_child(Ui.label(tr("MP_MY_IP") % (", ".join(addrs) if not addrs.is_empty() else "127.0.0.1"), "DimLabel"))
	var copy: Button = Ui.icon_button("copy", 14, "GhostButton", Vector2(30, 30))
	copy.tooltip_text = tr("MP_COPY_IP")
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(addrs[0] if not addrs.is_empty() else "127.0.0.1")
		Events.toast_requested.emit(tr("MP_IP_COPIED"), "info"))
	ip_row.add_child(copy)
	hv.add_child(ip_row)
	hv.add_child(Ui.spacer(false, true))
	var host_btn: Button = Ui.button(tr("MP_HOST_BTN"), "PrimaryButton", "", "play")
	host_btn.pressed.connect(_do_host)
	hv.add_child(host_btn)
	host_btn.grab_focus.call_deferred()
	row.add_child(host_card)

	var join_card: PanelContainer = Ui.panel("GlassPanel")
	join_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var jv: VBoxContainer = Ui.vbox(T.SP_3)
	join_card.add_child(jv)
	jv.add_child(Ui.label(tr("MP_JOIN_TITLE"), "HeaderLabel"))
	jv.add_child(Ui.label(tr("MP_LAN_GAMES"), "CapsLabel"))
	_lan_list = Ui.vbox(T.SP_2)
	_lan_list.custom_minimum_size = Vector2(0, 160)
	jv.add_child(_lan_list)
	_refresh_lan()
	jv.add_child(HSeparator.new())
	jv.add_child(Ui.label(tr("MP_DIRECT"), "CapsLabel"))
	var direct: HBoxContainer = Ui.hbox(T.SP_2)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "192.168.1.20"
	_ip_edit.text = String(Settings.get_value("general", "last_ip")) if Settings.get_value("general", "last_ip") != null else ""
	_ip_edit.custom_minimum_size = Vector2(240, 0)
	_ip_edit.text_submitted.connect(func(_t: String) -> void: _do_join(_ip_edit.text, int(_port_edit.text)))
	direct.add_child(_ip_edit)
	var join_btn: Button = Ui.button(tr("MP_JOIN_BTN"), "Button", "", "arrow_up")
	join_btn.pressed.connect(func() -> void: _do_join(_ip_edit.text, int(_port_edit.text)))
	direct.add_child(join_btn)
	jv.add_child(direct)
	_status = Ui.label("", "DimLabel", true)
	_status.custom_minimum_size = Vector2(420, 0)
	jv.add_child(_status)
	row.add_child(join_card)

	var back: Button = Ui.button(tr("ACT_TO_MENU"), "GhostButton", "menu", "close")
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_back_to_menu)
	col.add_child(back)


func _title_row(title: String, sub: String) -> VBoxContainer:
	var v: VBoxContainer = Ui.vbox(2)
	var k: Label = Ui.label(sub, "CapsLabel")
	k.add_theme_color_override("font_color", T.ACCENT)
	v.add_child(k)
	v.add_child(Ui.label(title, "TitleLabel"))
	return v


func _lan_note(text: String) -> void:
	if _lan_list == null:
		return
	for c: Node in _lan_list.get_children():
		c.queue_free()
	_lan_list.add_child(Ui.label(text, "FaintLabel", true))


func _refresh_lan() -> void:
	if _lan_list == null or not is_instance_valid(_lan_list) or _mode != "hub":
		return
	for c: Node in _lan_list.get_children():
		c.queue_free()
	if Net.discovery.hosts.is_empty():
		_lan_list.add_child(Ui.label(tr("MP_LAN_EMPTY"), "FaintLabel", true))
		return
	for key: String in Net.discovery.hosts.keys():
		var h: Dictionary = Net.discovery.hosts[key]
		var card: PanelContainer = PanelContainer.new()
		card.theme_type_variation = "CardPanel"
		var r: HBoxContainer = Ui.hbox(T.SP_3)
		var v: VBoxContainer = Ui.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(Ui.label(String(h.get("name", "?")), "SubheaderLabel"))
		v.add_child(Ui.label("%s:%d · %d/%d · v%s" % [h["ip"], int(h["port"]), int(h.get("players", 0)), int(h.get("max", 4)), String(h.get("version", "?"))], "DimLabel"))
		r.add_child(v)
		var b: Button = Ui.button(tr("MP_JOIN_BTN"), "PrimaryButton", "", "arrow_up")
		b.disabled = not bool(h.get("open", true)) or int(h.get("players", 0)) >= int(h.get("max", 4)) or String(h.get("version", "")) != Game.version()
		var ip: String = String(h["ip"])
		var port: int = int(h["port"])
		b.pressed.connect(func() -> void: _do_join(ip, port))
		r.add_child(b)
		card.add_child(r)
		_lan_list.add_child(card)


func _do_host() -> void:
	var port: int = int(_port_edit.text) if _port_edit != null and _port_edit.text.is_valid_int() else NetProtocol.DEFAULT_PORT
	var err: Error = Net.host(port, Settings.player_name())
	if err != OK:
		Events.toast_requested.emit(tr("NET_ERR_HOST") % [port, error_string(err)], "error")


func _do_join(ip: String, port: int) -> void:
	var addr: String = ip.strip_edges()
	if addr.is_empty():
		Events.toast_requested.emit(tr("MP_ENTER_IP"), "error")
		return
	Settings.set_value("general", "last_ip", addr)
	var err: Error = Net.join(addr, port if port > 0 else NetProtocol.DEFAULT_PORT, Settings.player_name())
	if err != OK:
		Events.toast_requested.emit(tr("NET_ERR_CONNECT"), "error")
		return
	if _status != null:
		_status.text = tr("MP_CONNECTING") % addr


# --- Комната ---------------------------------------------------------------

func _build_room() -> void:
	var col: VBoxContainer = Ui.vbox(T.SP_4)
	_content.add_child(col)
	col.add_child(_title_row(String(Net.settings.get("match_name", "")), tr("MP_ROOM_SUB")))
	var row: HBoxContainer = Ui.hbox(T.SP_5)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	var left: PanelContainer = Ui.panel("GlassPanel")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lv: VBoxContainer = Ui.vbox(T.SP_3)
	left.add_child(lv)
	lv.add_child(Ui.label(tr("MP_PLAYERS"), "CapsLabel"))
	_players_box = Ui.vbox(T.SP_2)
	lv.add_child(_players_box)
	lv.add_child(HSeparator.new())
	lv.add_child(Ui.label(tr("MP_CHAT"), "CapsLabel"))
	_chat_scroll = ScrollContainer.new()
	_chat_scroll.custom_minimum_size = Vector2(0, 180)
	_chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log = Ui.vbox(2)
	_chat_scroll.add_child(_chat_log)
	lv.add_child(_chat_scroll)
	# История из Net: комната пересобирается при смене состояния, а после матча чат продолжается.
	for m: Dictionary in Net.chat_log:
		_add_chat_line(String(m["sender"]), String(m["text"]), m["color"])
	_scroll_chat_down()
	var chat_in: LineEdit = LineEdit.new()
	chat_in.placeholder_text = tr("MP_CHAT_PLACEHOLDER")
	chat_in.max_length = NetProtocol.CHAT_MAX
	chat_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var emoji: EmojiPicker = EmojiPicker.new()
	emoji.picked.connect(func(e: String) -> void: EmojiPicker.insert_into(chat_in, e))
	chat_in.text_submitted.connect(func(t: String) -> void:
		Net.send_chat(t)
		chat_in.clear()
		emoji.visible = false)
	lv.add_child(emoji)
	var chat_row: HBoxContainer = Ui.hbox(T.SP_1)
	chat_row.add_child(chat_in)
	chat_row.add_child(emoji.make_toggle())
	lv.add_child(chat_row)
	row.add_child(left)
	var right: PanelContainer = Ui.panel("GlassPanel")
	right.custom_minimum_size = Vector2(520, 0)
	_settings_box = Ui.vbox(T.SP_3)
	right.add_child(_settings_box)
	row.add_child(right)
	var actions: HBoxContainer = Ui.hbox(T.SP_3)
	var leave: Button = Ui.button(tr("MP_LEAVE_LOBBY"), "GhostButton", "menu", "close")
	leave.pressed.connect(func() -> void:
		Net.leave()
		_rebuild())
	actions.add_child(leave)
	actions.add_child(Ui.spacer())
	if Net.is_host():
		_start_btn = Ui.button(tr("MP_START"), "PrimaryButton", "confirm", "play")
		_start_btn.pressed.connect(Net.start_match)
		actions.add_child(_start_btn)
		_start_btn.grab_focus.call_deferred()
	else:
		_ready_btn = Ui.button(tr("MP_READY"), "PrimaryButton", "confirm", "check")
		_ready_btn.pressed.connect(func() -> void:
			var me: Dictionary = Net.players.get(Net.my_id(), {})
			Net.set_ready(not bool(me.get("ready", false))))
		actions.add_child(_ready_btn)
		_ready_btn.grab_focus.call_deferred()
	col.add_child(actions)


func _on_lobby_updated() -> void:
	if _mode != "room" or _players_box == null:
		return
	for c: Node in _players_box.get_children():
		c.queue_free()
	var ids: Array = Net.players.keys()
	ids.sort()
	for i: int in int(Net.settings.get("max_players", 4)):
		var card: PanelContainer = PanelContainer.new()
		card.theme_type_variation = "CardPanel" if i < ids.size() else "InsetPanel"
		var r: HBoxContainer = Ui.hbox(T.SP_3)
		if i < ids.size():
			var p: Dictionary = Net.players[ids[i]]
			var bar: ColorRect = ColorRect.new()
			bar.color = Color.html(String(p["color"]))
			bar.custom_minimum_size = Vector2(6, 28)
			r.add_child(bar)
			var n: Label = Ui.label(String(p["name"]) + ("  (" + tr("MP_YOU") + ")" if int(ids[i]) == Net.my_id() else ""), "SubheaderLabel")
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(n)
			if int(ids[i]) == 1:
				r.add_child(Ui.label(tr("MP_HOST_BADGE"), "CapsLabel"))
			var ready: bool = bool(p["ready"])
			r.add_child(Ui.icon("check" if ready else "clock", 18, T.SUCCESS if ready else T.TEXT_FAINT))
			if Net.is_host() and int(ids[i]) != 1:
				var pid: int = int(ids[i])
				var kick: Button = Ui.icon_button("close", 12, "GhostButton", Vector2(30, 30))
				kick.tooltip_text = tr("MP_KICK")
				kick.pressed.connect(func() -> void: Net.kick(pid))
				r.add_child(kick)
		else:
			r.add_child(Ui.label(tr("MP_SLOT_FREE"), "FaintLabel"))
		card.add_child(r)
		_players_box.add_child(card)
	_build_settings()
	if _start_btn != null:
		_start_btn.disabled = not Net.can_start()
		_start_btn.tooltip_text = "" if Net.can_start() else tr("MP_START_NEED")
	if _ready_btn != null:
		var me: Dictionary = Net.players.get(Net.my_id(), {})
		var row: HBoxContainer = _ready_btn.get_child(0) as HBoxContainer
		for c2: Node in row.get_children():
			if c2 is Label:
				(c2 as Label).text = tr("MP_NOT_READY") if bool(me.get("ready", false)) else tr("MP_READY")
	_cli_lobby_step()


func _build_settings() -> void:
	for c: Node in _settings_box.get_children():
		c.queue_free()
	var s: Dictionary = Net.settings
	var data: GameData = GameData.load_default()
	var host: bool = Net.is_host()
	_settings_box.add_child(Ui.label(tr("MP_SETTINGS"), "CapsLabel"))
	_setting_row(tr("NG_DIFFICULTY"), _choice(data.difficulty_order, String(s["difficulty"]), func(id: String) -> String: return tr(String(data.difficulty(id)["name_key"])),
		func(v: String) -> void: Net.update_settings({"difficulty": v}), host))
	var seeds: PackedStringArray = PackedStringArray(["random", "daily", "custom"])
	_setting_row(tr("NG_SEED"), _choice(seeds, String(s["seed_mode"]), func(id: String) -> String: return tr("NG_SEED_" + id.to_upper()),
		func(v: String) -> void: Net.update_settings({"seed_mode": v}), host))
	if String(s["seed_mode"]) == "custom":
		var le: LineEdit = LineEdit.new()
		le.text = String(s["seed_text"])
		le.editable = host
		le.custom_minimum_size = Vector2(220, 0)
		le.text_submitted.connect(func(t: String) -> void: Net.update_settings({"seed_text": t}))
		le.focus_exited.connect(func() -> void:
			if host and le.text != String(Net.settings["seed_text"]):
				Net.update_settings({"seed_text": le.text}))
		_setting_row(tr("NG_SEED_CUSTOM"), le)
	var waves: PackedStringArray = PackedStringArray()
	# Длины забега (20, 42 — первый акт, 62 — вся игра) с усиленным финалом и «∞»: волны идут по кругу и
	# крепнут, пока жив хоть один игрок. Нестандартное число (автотест --waves=5) тоже показывается.
	var options: Array[int] = data.run_lengths()
	if not options.has(int(s["waves"])) and int(s["waves"]) != NetProtocol.ENDLESS_WAVES:
		options.append(int(s["waves"]))
		options.sort()
	options.append(NetProtocol.ENDLESS_WAVES)
	for w: int in options:
		waves.append(str(w))
	var waves_row: Control = _choice(waves, str(int(s["waves"])), func(id: String) -> String:
			return tr("MP_WAVES_ENDLESS") if int(id) == NetProtocol.ENDLESS_WAVES else id,
		func(v: String) -> void: Net.update_settings({"waves": int(v)}), host)
	for b: Node in waves_row.get_children():
		var n: int = int((b as Button).text) if (b as Button).text.is_valid_int() else NetProtocol.ENDLESS_WAVES
		(b as Button).tooltip_text = tr("MP_WAVES_ENDLESS_TIP") if n == NetProtocol.ENDLESS_WAVES else NewGamePanel.length_tip(data, n)
	_setting_row(tr("MP_WAVES"), waves_row)
	var timers: PackedStringArray = PackedStringArray()
	for t: int in NetProtocol.BUILD_TIMERS:
		timers.append(str(t))
	_setting_row(tr("MP_TIMER_SETTING"), _choice(timers, str(int(s["timer"])), func(id: String) -> String: return (tr("MP_TIMER_SEC") % int(id)) if int(id) > 0 else tr("MP_TIMER_NONE"),
		func(v: String) -> void: Net.update_settings({"timer": int(v)}), host))
	var fair: CheckButton = CheckButton.new()
	fair.text = tr("MP_FAIR")
	fair.tooltip_text = tr("MP_FAIR_TIP")
	fair.button_pressed = bool(s["fair"])
	fair.disabled = not host
	fair.toggled.connect(func(v: bool) -> void: Net.update_settings({"fair": v}))
	_settings_box.add_child(fair)
	var note: Label = Ui.label(tr("MP_RULES"), "FaintLabel", true)
	note.custom_minimum_size = Vector2(480, 0)
	_settings_box.add_child(note)


func _setting_row(title: String, control: Control) -> void:
	var r: HBoxContainer = Ui.hbox(T.SP_3)
	var l: Label = Ui.label(title, "BodyLabel")
	l.custom_minimum_size = Vector2(180, 0)
	r.add_child(l)
	r.add_child(control)
	_settings_box.add_child(r)


func _choice(ids: PackedStringArray, current: String, label_of: Callable, on_pick: Callable, editable: bool) -> Control:
	var box: HBoxContainer = Ui.hbox(4)
	var group: ButtonGroup = ButtonGroup.new()
	for id: String in ids:
		var b: Button = Button.new()
		b.theme_type_variation = "ChipButton"
		b.text = String(label_of.call(id))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = id == current
		b.disabled = not editable and id != current
		b.custom_minimum_size = Vector2(0, 30)
		if editable:
			Ui.attach_feedback(b)
			b.pressed.connect(func() -> void:
				if id != current:
					on_pick.call(id))
		box.add_child(b)
	return box


func _on_chat(sender: String, text: String, color: Color) -> void:
	if _chat_log == null or not is_instance_valid(_chat_log):
		return
	_add_chat_line(sender, text, color)
	Audio.play("sfx/ui/toast")
	_scroll_chat_down()


func _add_chat_line(sender: String, text: String, color: Color) -> void:
	var l: Label = Ui.label(("%s: %s" % [sender, text]) if not sender.is_empty() else text, "BodyLabel" if not sender.is_empty() else "DimLabel", true)
	if not sender.is_empty():
		l.add_theme_color_override("font_color", color.lightened(0.3))
	l.custom_minimum_size = Vector2(560, 0)
	_chat_log.add_child(l)


## К последнему сообщению — кадром позже, когда полоса прокрутки учтёт новые строки.
func _scroll_chat_down() -> void:
	await get_tree().process_frame
	if is_instance_valid(_chat_scroll):
		_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)


func _on_match_started(config: Dictionary) -> void:
	Audio.stop_loop("ambience/arena")
	Game.run_config = {"mode": "race", "race": config}
	Game.goto_scene("game")


func _back_to_menu() -> void:
	Net.leave()
	Audio.stop_loop("ambience/arena")
	Game.goto_scene("menu")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu") and _mode == "hub":
		get_viewport().set_input_as_handled()
		_back_to_menu()


# --- Автотест через CLI ----------------------------------------------------------

func _cli_autostart() -> void:
	if String(Game.cli.get("screenshot", "")) == "lobby":
		Net.host(NetProtocol.DEFAULT_PORT + 20, Settings.player_name())
		_on_chat("", tr("NET_PLAYER_JOINED") % Settings.player_name(), T.TEXT_DIM)
		await get_tree().create_timer(2.0).timeout
		await Game.save_screenshot("lobby")
		Net.leave()
		get_tree().quit()
		return
	var port: int = int(String(Game.cli.get("port", str(NetProtocol.DEFAULT_PORT))))
	if Game.cli.has("name"):
		Settings.set_value("general", "player_name", String(Game.cli["name"]))
	if Game.cli.has("mp-host") and Net.state == Net.State.OFFLINE:
		var err: Error = Net.host(port, Settings.player_name())
		print("mp-host: порт %d → %s" % [port, error_string(err)])
		var patch: Dictionary = {"waves": int(String(Game.cli.get("waves", "5"))), "timer": 60}
		if Game.cli.has("seed"):
			patch["seed_mode"] = "custom"
			patch["seed_text"] = String(Game.cli["seed"])
		if Game.cli.has("difficulty"):
			# Без проверки опечатка дала бы лобби без выбранной сложности и матч на Normal (запасной уровень).
			var diff_id: String = String(Game.cli["difficulty"])
			var known: PackedStringArray = GameData.load_default().difficulty_order
			if known.has(diff_id):
				patch["difficulty"] = diff_id
			else:
				printerr("mp-host: неизвестная сложность «%s», есть: %s" % [diff_id, ", ".join(known)])
		Net.update_settings(patch)
	elif Game.cli.has("mp-join") and Net.state == Net.State.OFFLINE:
		var err2: Error = Net.join(String(Game.cli["mp-join"]), port, Settings.player_name())
		print("mp-join: %s:%d → %s" % [String(Game.cli["mp-join"]), port, error_string(err2)])


func _cli_lobby_step() -> void:
	if not Game.cli.has("bot"):
		return
	if Game.cli.has("mp-join") and not bool(Net.players.get(Net.my_id(), {}).get("ready", false)):
		Net.set_ready(true)
	if Game.cli.has("mp-host") and Net.can_start() and not _bot_started:
		_bot_started = true
		print("mp-host: игроков %d, старт матча" % Net.players.size())
		Net.start_match()
