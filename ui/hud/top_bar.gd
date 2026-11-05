class_name TopBar
extends PanelContainer
## Верхняя панель HUD: волна, сложность, жизни, золото, удача, длина пути, автостарт волны, скорость, пауза, seed.

signal speed_selected(speed: int)
signal autostart_toggled(on: bool)
signal pause_pressed
signal luck_pressed
signal menu_pressed
signal buy_life_pressed
signal codex_pressed

const T := preload("res://ui/theme/ui_tokens.gd")

var _wave: Label
var _wave_mod: Label
var _diff_box: HBoxContainer
var _diff: Label = null
var _lives: Label
var _lives_icon: UiIcon
var _buy_life: Button
var _gold: Label
var _gold_value: int = 0
var _luck: Label
var _luck_btn: Button
var _luck_cost: Label
var _path: Label
var _autostart: CheckBox
var _speed_btns: Array[Button] = []
var _speed_locked: bool = false
var _pause_btn: Button
var _pause_icon: UiIcon
var _seed: Label


func _init() -> void:
	theme_type_variation = "GlassPanel"
	material = Ui.glass_material()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row: HBoxContainer = Ui.hbox(T.SP_5)
	add_child(row)

	var wave_box: VBoxContainer = Ui.vbox(0)
	var wave_head: HBoxContainer = Ui.hbox(T.SP_3)
	wave_head.add_child(Ui.label(tr("HUD_WAVE"), "CapsLabel"))
	wave_head.add_child(Ui.spacer())
	# Сложность забега — в шапке блока волны, а не отдельным блоком: так панель не шире, чем была
	# (отдельный блок выталкивал кнопки за край при масштабе интерфейса 110 % и тексте 115 %).
	# В «Гонке» сложность задаёт хост, и видеть её должны все игроки.
	_diff_box = Ui.hbox(T.SP_2)
	_diff_box.add_child(Ui.label(tr("NG_DIFFICULTY"), "CapsLabel"))
	_diff_box.mouse_filter = Control.MOUSE_FILTER_PASS
	_diff_box.visible = false
	wave_head.add_child(_diff_box)
	wave_box.add_child(wave_head)
	var wave_line: HBoxContainer = Ui.hbox(T.SP_2)
	_wave = Ui.label("1/10", "BigNumberLabel")
	wave_line.add_child(_wave)
	_wave_mod = Ui.label("", "DimLabel")
	_wave_mod.size_flags_vertical = Control.SIZE_SHRINK_END
	wave_line.add_child(_wave_mod)
	wave_box.add_child(wave_line)
	row.add_child(wave_box)
	row.add_child(VSeparator.new())

	var lives_box: HBoxContainer = Ui.hbox(T.SP_2)
	_lives_icon = Ui.icon("heart", 22, T.LIFE)
	lives_box.add_child(_lives_icon)
	_lives = Ui.label("20", "BigNumberLabel")
	lives_box.add_child(_lives)
	lives_box.tooltip_text = tr("HUD_LIVES_TIP")
	lives_box.mouse_filter = Control.MOUSE_FILTER_PASS
	_buy_life = Ui.icon_button("heart", 12, "ChipButton", Vector2(28, 26))
	(_buy_life.get_child(0).get_child(0) as UiIcon).color = T.LIFE
	_buy_life.pressed.connect(func() -> void: buy_life_pressed.emit())
	lives_box.add_child(_buy_life)
	row.add_child(lives_box)

	var gold_box: HBoxContainer = Ui.hbox(T.SP_2)
	gold_box.add_child(Ui.icon("coin", 22, T.GOLD))
	_gold = Ui.label("0", "BigNumberLabel")
	_gold.add_theme_color_override("font_color", T.GOLD.lightened(0.3))
	gold_box.add_child(_gold)
	gold_box.tooltip_text = tr("HUD_GOLD_TIP")
	gold_box.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(gold_box)

	var luck_box: HBoxContainer = Ui.hbox(T.SP_2)
	luck_box.add_child(Ui.icon("luck", 20, T.ACCENT_2))
	var luck_text: VBoxContainer = Ui.vbox(0)
	luck_text.add_child(Ui.label(tr("HUD_LUCK"), "CapsLabel"))
	_luck = Ui.label("I", "NumberLabel")
	luck_text.add_child(_luck)
	luck_box.add_child(luck_text)
	_luck_btn = Ui.button("", "Button", "upgrade_luck", "arrow_up")
	_luck_cost = Ui.label("", "NumberLabel")
	_luck_cost.add_theme_font_size_override("font_size", T.FS_S)
	_luck_cost.add_theme_color_override("font_color", T.GOLD)
	(_luck_btn.get_child(0) as HBoxContainer).add_child(_luck_cost)
	(_luck_btn.get_child(0) as HBoxContainer).move_child(_luck_cost, 1)
	_luck_btn.pressed.connect(func() -> void: luck_pressed.emit())
	luck_box.add_child(_luck_btn)
	row.add_child(luck_box)

	var path_box: HBoxContainer = Ui.hbox(T.SP_2)
	path_box.add_child(Ui.icon("path", 18, T.ACCENT))
	_path = Ui.label("0", "NumberLabel")
	path_box.add_child(_path)
	path_box.tooltip_text = tr("HUD_PATH_TIP")
	path_box.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(path_box)

	row.add_child(Ui.spacer())

	# Без галочки следующая волна ждёт кнопки «Начать волну»; с ней — стартует после отсчёта.
	_autostart = CheckBox.new()
	_autostart.text = tr("HUD_AUTOSTART")
	_autostart.tooltip_text = tr("HUD_AUTOSTART_TIP")
	_autostart.focus_mode = Control.FOCUS_NONE
	_autostart.button_pressed = bool(Settings.get_value("gameplay", "autostart_wave"))
	_autostart.toggled.connect(func(on: bool) -> void:
		Audio.play("sfx/ui/click")
		autostart_toggled.emit(on))
	row.add_child(_autostart)

	var speeds: HBoxContainer = Ui.hbox(4)
	var group: ButtonGroup = ButtonGroup.new()
	for s: int in [1, 2, 4]:
		var b: Button = Button.new()
		b.theme_type_variation = "ChipButton"
		b.text = "%d×" % s
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(44, 32)
		b.button_pressed = s == 1
		b.tooltip_text = tr("HUD_SPEED_TIP") % [Settings.key_label("speed_down"), Settings.key_label("speed_up")]
		Ui.attach_feedback(b)
		b.pressed.connect(func() -> void: speed_selected.emit(s))
		speeds.add_child(b)
		_speed_btns.append(b)
	row.add_child(speeds)
	_pause_btn = Ui.icon_button("pause", 14, "ChipButton", Vector2(40, 32))
	_pause_icon = _pause_btn.get_child(0).get_child(0) as UiIcon
	_pause_btn.tooltip_text = tr("HUD_PAUSE_TIP") % Settings.key_label("pause")
	_pause_btn.pressed.connect(func() -> void: pause_pressed.emit())
	row.add_child(_pause_btn)

	var seed_box: HBoxContainer = Ui.hbox(4)
	seed_box.add_child(Ui.label(tr("HUD_SEED"), "CapsLabel"))
	_seed = Ui.label("", "NumberLabel")
	_seed.add_theme_font_size_override("font_size", T.FS_S)
	seed_box.add_child(_seed)
	var copy: Button = Ui.icon_button("copy", 14, "GhostButton", Vector2(30, 30))
	copy.tooltip_text = tr("HUD_COPY_SEED")
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_seed.text)
		Events.toast_requested.emit(tr("TOAST_SEED_COPIED") % _seed.text, "info"))
	seed_box.add_child(copy)
	row.add_child(seed_box)

	var codex: Button = Ui.icon_button("info", 18, "GhostButton", Vector2(36, 32))
	codex.tooltip_text = tr("HUD_CODEX_TIP") % Settings.key_label("codex")
	codex.pressed.connect(func() -> void: codex_pressed.emit())
	row.add_child(codex)
	var menu: Button = Ui.icon_button("gear", 18, "GhostButton", Vector2(36, 32))
	menu.tooltip_text = tr("HUD_MENU_TIP") % Settings.key_label("menu")
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	row.add_child(menu)


func set_wave(n: int, total: int, modifier: String, air: bool, boss: bool) -> void:
	_wave.text = T.wave_fraction(n, total)
	var mod: String = tr("MOD_" + modifier.to_upper())
	if boss:
		_wave_mod.add_theme_color_override("font_color", T.BOSS)
	elif air:
		_wave_mod.add_theme_color_override("font_color", T.AIR)
	else:
		_wave_mod.add_theme_color_override("font_color", T.TEXT_DIM)
	_wave_mod.text = mod


## Сложность забега (`difficulty.json`): название цветом уровня, в подсказке — описание, жизни, HP врагов
## (с разгоном — «100 % → X % к N-й волне»: так верно и для множителя ниже 1) и множитель очков.
func set_difficulty(d: Dictionary) -> void:
	_diff_box.visible = not d.is_empty()
	if d.is_empty():
		return
	if _diff != null:
		_diff.queue_free()
	_diff = Ui.difficulty_label(d)
	_diff_box.add_child(_diff)
	var hp: int = roundi(100.0 * float(d["hp_mult"]))
	var ramp: int = int(d.get("hp_ramp_waves", 0))
	var stats: String = tr("HUD_DIFFICULTY_TIP_RAMP") % [int(d["lives"]), hp, ramp + 1, str(d["score_mult"])] if ramp > 0 \
		else tr("HUD_DIFFICULTY_TIP") % [int(d["lives"]), hp, str(d["score_mult"])]
	_diff_box.tooltip_text = "%s — %s\n%s" % [tr(String(d["name_key"])), tr(String(d["desc_key"])), stats]


func set_lives(v: int, animate: bool) -> void:
	_lives.text = str(v)
	if animate:
		Ui.punch(_lives, 1.3)
		Ui.punch(_lives_icon, 1.4)
		Ui.shake(_lives_icon, 5.0)
		_lives.add_theme_color_override("font_color", T.LIFE)
		var tw: Tween = _lives.create_tween()
		tw.tween_interval(0.4)
		tw.tween_callback(func() -> void: _lives.remove_theme_color_override("font_color"))


func set_buy_life(visible_now: bool, cost: int, can_afford: bool) -> void:
	_buy_life.visible = visible_now
	_buy_life.disabled = not can_afford
	_buy_life.tooltip_text = tr("HUD_BUY_LIFE_TIP") % cost + ("" if can_afford else "\n" + tr("ERR_NOT_ENOUGH_GOLD"))


## Центр счётчика золота на экране — сюда летят монеты.
func gold_anchor() -> Vector2:
	return _gold.get_global_rect().get_center()


func set_gold(v: int, animate: bool) -> void:
	if animate and v > _gold_value:
		Ui.tween_number(_gold, float(_gold_value), float(v), 0.35, func(x: float) -> String: return str(int(roundf(x))))
		Ui.punch(_gold, 1.08)
	else:
		_gold.text = str(v)
	_gold_value = v


func set_luck(level: int, roman: String, cost: int, can_afford: bool, chances: Array, quality_names: Array) -> void:
	_luck.text = roman
	_luck_btn.disabled = cost < 0 or not can_afford
	_luck_cost.text = str(cost) if cost >= 0 else tr("HUD_MAX")
	var lines: PackedStringArray = PackedStringArray([tr("LUCK_TIP_TITLE") % roman])
	for i: int in chances.size():
		if float(chances[i]) > 0.0:
			lines.append("  %s — %d%%" % [quality_names[i], int(chances[i])])
	if cost >= 0:
		lines.append("")
		lines.append(tr("LUCK_TIP_COST") % cost)
		if not can_afford:
			lines.append(tr("LUCK_TIP_NO_GOLD"))
	lines.append(tr("LUCK_TIP_WARN"))
	_luck_btn.tooltip_text = "\n".join(lines)


func set_path_length(v: float) -> void:
	_path.text = tr("HUD_PATH_VALUE") % int(roundf(v))


func set_speed(s: int) -> void:
	for b: Button in _speed_btns:
		b.set_pressed_no_signal(b.text == "%d×" % s)
	_apply_speed_lock()


func set_autostart(on: bool) -> void:
	_autostart.set_pressed_no_signal(on)


## В «Гонке» и реплее волны запускает не игрок — галочка скрыта.
func set_autostart_visible(v: bool) -> void:
	_autostart.visible = v


## Скорость задаёт не игрок (клиент «Гонки»): текущая кнопка остаётся подсвеченной, остальные недоступны.
func set_speed_enabled(v: bool) -> void:
	_speed_locked = not v
	_apply_speed_lock()


func _apply_speed_lock() -> void:
	for b: Button in _speed_btns:
		b.disabled = _speed_locked and not b.button_pressed
		b.tooltip_text = tr("MP_SPEED_HOST") if _speed_locked else tr("HUD_SPEED_TIP") % [Settings.key_label("speed_down"), Settings.key_label("speed_up")]


func set_paused(p: bool) -> void:
	_pause_icon.icon_name = "play" if p else "pause"


func set_seed(text: String) -> void:
	_seed.text = text


func flash_luck() -> void:
	Ui.punch(_luck, 1.4)
