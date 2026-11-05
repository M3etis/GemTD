class_name SettingsPanel
extends Modal
## Настройки: звук (громкость, пак, папка, перезагрузка), графика, игра, язык.

const BUSES: Array[String] = ["Master", "Music", "SFX", "UI", "Ambience"]
const REMAP_ACTIONS: Array[String] = ["confirm", "select_1", "select_2", "select_3", "select_4", "select_5", "combine", "forge",
	"upgrade_luck", "break_wall", "pause", "restart", "menu", "forecast", "codex", "show_ranges", "show_hp", "chat", "speed_down", "speed_up",
	"camera_reset", "cam_left", "cam_right", "cam_up", "cam_down"]

var _report: Label
## Переназначение клавиш: действие, которое ждёт клавишу, и его кнопка.
var _listening: String = ""
var _listen_button: Button
var _key_buttons: Dictionary = {}


func _init() -> void:
	super._init()
	header(tr("SETTINGS_TITLE"), "gear")
	var tabs: TabContainer = TabContainer.new()
	tabs.custom_minimum_size = Vector2(640, 430)
	tabs.tab_changed.connect(func(_i: int) -> void: Audio.play("sfx/ui/tab_switch"))
	body.add_child(tabs)
	tabs.add_child(_audio_tab())
	tabs.add_child(_video_tab())
	tabs.add_child(_game_tab())
	tabs.add_child(_access_tab())
	tabs.add_child(_controls_tab())
	tabs.add_child(_lang_tab())
	Events.audio_reloaded.connect(_on_audio_reloaded)


func _page(title_key: String) -> VBoxContainer:
	var v: VBoxContainer = Ui.vbox(T.SP_3)
	v.name = tr(title_key)
	v.add_child(Ui.spacer(false, false))
	(v.get_child(0) as Control).custom_minimum_size = Vector2(0, T.SP_2)
	return v


func _audio_tab() -> Control:
	var page: VBoxContainer = _page("SETTINGS_TAB_AUDIO")
	for bus: String in BUSES:
		var row: HBoxContainer = Ui.hbox(T.SP_3)
		var l: Label = Ui.label(tr("BUS_" + bus.to_upper()), "BodyLabel")
		l.custom_minimum_size = Vector2(200, 0)
		row.add_child(l)
		var s: HSlider = HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.01
		s.value = float(Settings.get_value("audio", bus))
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.custom_minimum_size = Vector2(260, 24)
		var val: Label = Ui.label("%d%%" % int(s.value * 100.0), "NumberLabel")
		val.custom_minimum_size = Vector2(56, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		s.value_changed.connect(func(v: float) -> void:
			val.text = "%d%%" % int(v * 100.0)
			Settings.set_value("audio", bus, v))
		s.drag_ended.connect(func(_c: bool) -> void: Audio.play("sfx/ui/click" if bus != "Ambience" else "sfx/ui/toast"))
		row.add_child(s)
		row.add_child(val)
		page.add_child(row)
	page.add_child(HSeparator.new())
	var pack_row: HBoxContainer = Ui.hbox(T.SP_3)
	var pl: Label = Ui.label(tr("SETTINGS_SOUND_PACK"), "BodyLabel")
	pl.custom_minimum_size = Vector2(200, 0)
	pack_row.add_child(pl)
	var packs: OptionButton = OptionButton.new()
	var list: PackedStringArray = Audio.available_packs()
	for i: int in list.size():
		packs.add_item(list[i], i)
		if list[i] == Audio.active_pack():
			packs.select(i)
	packs.item_selected.connect(func(i: int) -> void:
		Settings.set_value("audio", "pack", list[i])
		Audio.ensure_user_pack(list[i])
		Audio.reload())
	pack_row.add_child(packs)
	page.add_child(pack_row)
	var hint: Label = Ui.label(tr("SETTINGS_SOUND_HINT"), "DimLabel", true)
	hint.custom_minimum_size = Vector2(600, 0)
	page.add_child(hint)
	var btns: HBoxContainer = Ui.hbox(T.SP_3)
	var open: Button = Ui.button(tr("SETTINGS_OPEN_SOUNDS"), "Button", "", "sound")
	open.pressed.connect(Audio.open_sounds_folder)
	btns.add_child(open)
	var reload: Button = Ui.button(tr("SETTINGS_RELOAD_SOUNDS"), "Button", "", "arrow_up")
	reload.pressed.connect(func() -> void:
		Audio.reload()
		Audio.play("sfx/ui/confirm"))
	btns.add_child(reload)
	var browse: Button = Ui.button(tr("SB_OPEN"), "Button", "", "play")
	browse.pressed.connect(func() -> void: get_parent().add_child(SoundBrowser.new()))
	btns.add_child(browse)
	page.add_child(btns)
	_report = Ui.label("", "DimLabel", true)
	_report.custom_minimum_size = Vector2(600, 0)
	page.add_child(_report)
	_on_audio_reloaded(Audio.report())
	return page


func _on_audio_reloaded(report: Array) -> void:
	if _report == null:
		return
	var custom: int = 0
	var missing: int = 0
	for row: Dictionary in report:
		if String(row["source"]) != "builtin" and not String(row["source"]).is_empty():
			custom += 1
		if bool(row["missing"]):
			missing += 1
	_report.text = tr("SETTINGS_SOUND_REPORT") % [report.size(), custom, missing, Audio.pack_dir(Audio.active_pack())]


func _video_tab() -> Control:
	var page: VBoxContainer = _page("SETTINGS_TAB_VIDEO")
	var mode_row: HBoxContainer = Ui.hbox(T.SP_3)
	var ml: Label = Ui.label(tr("SETTINGS_WINDOW_MODE"), "BodyLabel")
	ml.custom_minimum_size = Vector2(200, 0)
	mode_row.add_child(ml)
	var mode: OptionButton = OptionButton.new()
	mode.add_item(tr("WINDOW_WINDOWED"), 0)
	mode.add_item(tr("WINDOW_FULLSCREEN"), 1)
	mode.select(1 if String(Settings.get_value("video", "window_mode")) == "fullscreen" else 0)
	mode.item_selected.connect(func(i: int) -> void: Settings.set_value("video", "window_mode", "fullscreen" if i == 1 else "windowed"))
	mode_row.add_child(mode)
	page.add_child(mode_row)
	page.add_child(_toggle("video", "vsync", "SETTINGS_VSYNC"))
	var presets: Array = []
	for id: String in Graphics.ORDER:
		presets.append([id, "GFX_PRESET_" + id.to_upper()])
	page.add_child(_choice("video", "preset", "SETTINGS_GFX_PRESET", presets))
	var scales: Array = [[0.0, "GFX_SCALE_AUTO"], [1.0, "100%"], [0.9, "90%"], [0.75, "75%"], [0.6, "60%"], [0.5, "50%"]]
	page.add_child(_choice("video", "render_scale", "SETTINGS_RENDER_SCALE", scales))
	var fps: Array = [[0, "GFX_FPS_UNLIMITED"], [30, "30"], [60, "60"], [120, "120"]]
	page.add_child(_choice("video", "fps_limit", "SETTINGS_FPS_LIMIT", fps))
	var hint: Label = Ui.label(tr("SETTINGS_GFX_HINT") % RenderingServer.get_current_rendering_method(), "FaintLabel", true)
	hint.custom_minimum_size = Vector2(560, 0)
	page.add_child(hint)
	return page


## Выпадающий список: options — [[значение, ключ перевода или текст], …].
func _choice(section: String, key: String, label_key: String, options: Array) -> HBoxContainer:
	var row: HBoxContainer = Ui.hbox(T.SP_3)
	var l: Label = Ui.label(tr(label_key), "BodyLabel")
	l.custom_minimum_size = Vector2(200, 0)
	row.add_child(l)
	var opt: OptionButton = OptionButton.new()
	var current: Variant = Settings.get_value(section, key)
	for i: int in options.size():
		opt.add_item(tr(String(options[i][1])), i)
		if str(options[i][0]) == str(current):
			opt.select(i)
	opt.item_selected.connect(func(i: int) -> void:
		Audio.play("sfx/ui/click")
		Settings.set_value(section, key, options[i][0]))
	row.add_child(opt)
	return row


func _game_tab() -> Control:
	var page: VBoxContainer = _page("SETTINGS_TAB_GAME")
	page.add_child(_toggle("gameplay", "autostart_wave", "SETTINGS_AUTOSTART"))
	page.add_child(_toggle("gameplay", "damage_numbers", "SETTINGS_DAMAGE_NUMBERS"))
	page.add_child(_toggle("gameplay", "reduce_motion", "SETTINGS_REDUCE_MOTION"))
	page.add_child(_toggle("gameplay", "screen_shake", "SETTINGS_SCREEN_SHAKE"))
	page.add_child(_toggle("gameplay", "cinematic_zoom", "SETTINGS_CINEMATIC_ZOOM"))
	page.add_child(_toggle("gameplay", "hints", "SETTINGS_HINTS"))
	page.add_child(_toggle("gameplay", "confirmations", "SETTINGS_CONFIRMATIONS"))
	var name_row: HBoxContainer = Ui.hbox(T.SP_3)
	var nl: Label = Ui.label(tr("SETTINGS_PLAYER_NAME"), "BodyLabel")
	nl.custom_minimum_size = Vector2(200, 0)
	name_row.add_child(nl)
	var le: LineEdit = LineEdit.new()
	le.text = String(Settings.get_value("general", "player_name"))
	le.placeholder_text = tr("DEFAULT_PLAYER_NAME")
	le.max_length = 24
	le.custom_minimum_size = Vector2(260, 0)
	le.text_changed.connect(func(t: String) -> void: Settings.set_value("general", "player_name", t.strip_edges()))
	name_row.add_child(le)
	page.add_child(name_row)
	return page


## Доступность: палитра для дальтоников, масштаб интерфейса и текста, вспышки, подписи к звукам.
func _access_tab() -> Control:
	var page: VBoxContainer = _page("SETTINGS_TAB_ACCESS")
	page.add_child(_toggle("accessibility", "colorblind", "SETTINGS_COLORBLIND"))
	var scales: Array = [[0.8, "80%"], [0.9, "90%"], [1.0, "100%"], [1.1, "110%"], [1.25, "125%"], [1.5, "150%"]]
	page.add_child(_choice("video", "ui_scale", "SETTINGS_UI_SCALE", scales))
	var texts: Array = [[1.0, "100%"], [1.15, "115%"], [1.3, "130%"], [1.5, "150%"]]
	page.add_child(_choice("accessibility", "text_scale", "SETTINGS_TEXT_SCALE", texts))
	page.add_child(_toggle("gameplay", "flashes", "SETTINGS_FLASHES"))
	page.add_child(_toggle("accessibility", "sound_captions", "SETTINGS_SOUND_CAPTIONS"))
	var hint: Label = Ui.label(tr("SETTINGS_ACCESS_HINT"), "FaintLabel", true)
	hint.custom_minimum_size = Vector2(560, 0)
	page.add_child(hint)
	return page


## Управление: переназначение клавиш. Кнопка ждёт следующую клавишу, Esc отменяет.


func _controls_tab() -> Control:
	var page: VBoxContainer = _page("SETTINGS_TAB_CONTROLS")
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", T.SP_5)
	grid.add_theme_constant_override("v_separation", 4)
	for action: String in REMAP_ACTIONS:
		var l: Label = Ui.label(tr("KEY_ACT_" + action.to_upper()), "BodyLabel")
		l.custom_minimum_size = Vector2(320, 0)
		grid.add_child(l)
		var b: Button = Button.new()
		b.theme_type_variation = "ChipButton"
		b.custom_minimum_size = Vector2(160, 30)
		b.text = Settings.key_label(action)
		b.pressed.connect(func() -> void: _listen(action, b))
		grid.add_child(b)
		_key_buttons[action] = b
	scroll.add_child(grid)
	page.add_child(scroll)
	# Мышь и зум клавишами-сочетаниями не переназначаются — перечислены отдельно.
	var fixed: Label = Ui.label(tr("SETTINGS_KEYS_FIXED"), "FaintLabel", true)
	fixed.custom_minimum_size = Vector2(600, 0)
	page.add_child(fixed)
	var reset: Button = Ui.button(tr("SETTINGS_KEYS_RESET"), "GhostButton", "", "back")
	reset.pressed.connect(func() -> void:
		Settings.reset_bindings()
		_refresh_keys())
	page.add_child(reset)
	return page


func _listen(action: String, b: Button) -> void:
	if _listen_button != null:
		_listen_button.text = Settings.key_label(_listening)
	_listening = action
	_listen_button = b
	b.text = tr("SETTINGS_KEYS_PRESS")


func _input(event: InputEvent) -> void:
	if _listening.is_empty() or not event is InputEventKey:
		return
	var k: InputEventKey = event
	if not k.pressed or k.echo:
		return
	get_viewport().set_input_as_handled()
	var action: String = _listening
	_listening = ""
	_listen_button = null
	if k.physical_keycode == KEY_ESCAPE:
		_refresh_keys()
		return
	var taken: String = Settings.set_binding(action, k.physical_keycode)
	if not taken.is_empty():
		Events.toast_requested.emit(tr("SETTINGS_KEYS_MOVED") % tr("KEY_ACT_" + taken.to_upper()), "warning")
	Audio.play("sfx/ui/confirm")
	_refresh_keys()


func _refresh_keys() -> void:
	for action: String in _key_buttons.keys():
		(_key_buttons[action] as Button).text = Settings.key_label(action) if not Settings.key_label(action).is_empty() else "—"


func _lang_tab() -> Control:
	var page: VBoxContainer = _page("SETTINGS_TAB_LANGUAGE")
	var row: HBoxContainer = Ui.hbox(T.SP_3)
	var ll: Label = Ui.label(tr("SETTINGS_LANGUAGE"), "BodyLabel")
	ll.custom_minimum_size = Vector2(200, 0)
	row.add_child(ll)
	var opt: OptionButton = OptionButton.new()
	opt.add_item("Русский", 0)
	opt.add_item("English", 1)
	opt.select(0 if TranslationServer.get_locale().begins_with("ru") else 1)
	opt.item_selected.connect(func(i: int) -> void:
		Settings.set_value("general", "locale", "ru" if i == 0 else "en")
		Events.toast_requested.emit(tr("TOAST_LANGUAGE_APPLIED"), "info"))
	row.add_child(opt)
	page.add_child(row)
	return page


func _toggle(section: String, key: String, label_key: String) -> CheckButton:
	var c: CheckButton = CheckButton.new()
	c.text = tr(label_key)
	c.button_pressed = bool(Settings.get_value(section, key))
	c.toggled.connect(func(v: bool) -> void:
		Audio.play("sfx/ui/click")
		Settings.set_value(section, key, v))
	return c
