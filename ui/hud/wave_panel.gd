class_name WavePanel
extends PanelContainer
## Правая панель: превью следующей волны и журнал событий. Журнал сворачивается кнопкой в его заголовке
## (Settings general.log_collapsed — помнится между забегами).

const T := preload("res://ui/theme/ui_tokens.gd")
const MAX_LOG: int = 9
## Сколько записей журнала хранится (показываются последние MAX_LOG по фильтру).
const KEEP_LOG: int = 60
const FILTERS: Array[String] = ["all", "combat", "build", "economy"]

## Клик по записи журнала: перевести камеру к месту события.
signal entry_clicked(at: Vector3)

var _title: Label
var _kind_icon: UiIcon
var _kind: Label
var _groups: VBoxContainer
var _hp: Label
var _advice: Label
var _traits: HFlowContainer
var _recommend: HBoxContainer
var _log: VBoxContainer
var _entries: Array[Dictionary] = []
var _filter: String = "all"
var _filter_btns: Array[Button] = []
var _log_body: VBoxContainer
var _log_toggle: Button


func _init() -> void:
	theme_type_variation = "GlassPanel"
	material = Ui.glass_material()
	custom_minimum_size = Vector2(320, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col: VBoxContainer = Ui.vbox(T.SP_2)
	add_child(col)
	col.add_child(Ui.label(tr("WAVE_PREVIEW_TITLE"), "CapsLabel"))
	var head: HBoxContainer = Ui.hbox(T.SP_2)
	_kind_icon = Ui.icon("ground", 22, T.TEXT)
	head.add_child(_kind_icon)
	_title = Ui.label("", "SubheaderLabel")
	head.add_child(_title)
	head.add_child(Ui.spacer())
	_kind = Ui.label("", "CapsLabel")
	head.add_child(_kind)
	col.add_child(head)
	_groups = Ui.vbox(4)
	col.add_child(_groups)
	_traits = HFlowContainer.new()
	_traits.add_theme_constant_override("h_separation", 4)
	_traits.add_theme_constant_override("v_separation", 4)
	_traits.custom_minimum_size = Vector2(288, 0)
	col.add_child(_traits)
	_hp = Ui.label("", "DimLabel")
	col.add_child(_hp)
	_recommend = Ui.hbox(T.SP_1)
	col.add_child(_recommend)
	_advice = Ui.label("", "DimLabel", true)
	_advice.custom_minimum_size = Vector2(288, 0)
	_advice.add_theme_color_override("font_color", T.AIR)
	col.add_child(_advice)
	col.add_child(HSeparator.new())
	var log_head: HBoxContainer = Ui.hbox(T.SP_2)
	log_head.add_child(Ui.label(tr("LOG_TITLE"), "CapsLabel"))
	log_head.add_child(Ui.spacer())
	_log_toggle = Ui.icon_button("arrow_up", 12, "GhostButton", Vector2(28, 24))
	_log_toggle.focus_mode = Control.FOCUS_NONE
	_log_toggle.pressed.connect(func() -> void: set_log_collapsed(not _log_body.visible))
	log_head.add_child(_log_toggle)
	col.add_child(log_head)
	_log_body = Ui.vbox(T.SP_2)
	col.add_child(_log_body)
	var chips: HBoxContainer = Ui.hbox(4)
	var group: ButtonGroup = ButtonGroup.new()
	for f: String in FILTERS:
		var b: Button = Button.new()
		b.theme_type_variation = "ChipButton"
		b.text = tr("LOG_FILTER_" + f.to_upper())
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = f == _filter
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", T.FS_XS)
		b.pressed.connect(func() -> void:
			_filter = f
			_render_log())
		chips.add_child(b)
		_filter_btns.append(b)
	_log_body.add_child(chips)
	_log = Ui.vbox(6)
	_log_body.add_child(_log)
	set_log_collapsed(bool(Settings.get_value("general", "log_collapsed")), false)


## Свернуть или развернуть журнал (save — запомнить в настройках).
func set_log_collapsed(on: bool, save: bool = true) -> void:
	_log_body.visible = not on
	(_log_toggle.find_child("Icon", true, false) as UiIcon).icon_name = "arrow_down" if on else "arrow_up"
	_log_toggle.tooltip_text = tr("LOG_SHOW") if on else tr("LOG_HIDE")
	if save:
		Settings.set_value("general", "log_collapsed", on)
	# Панель привязана к верхнему краю: после сворачивания её высота уменьшается (верх на месте).
	offset_bottom = offset_top + get_combined_minimum_size().y


func is_log_collapsed() -> bool:
	return not _log_body.visible


func show_wave(data: GameData, summary: Dictionary, diff: Dictionary) -> void:
	var n: int = int(summary["wave"])
	_title.text = tr("WAVE_N") % n
	var air: bool = bool(summary["air"])
	var boss: bool = bool(summary["boss"])
	_kind_icon.icon_name = "boss" if boss else ("air" if air else "ground")
	_kind_icon.color = T.BOSS if boss else (T.AIR if air else T.TEXT_DIM)
	_kind.text = tr("WAVE_KIND_BOSS") if boss else (tr("WAVE_KIND_AIR") if air else tr("WAVE_KIND_GROUND"))
	if bool(summary.get("finale", false)):
		_kind.text = tr("WAVE_KIND_FINALE")
	_kind.add_theme_color_override("font_color", _kind_icon.color)
	var cycle: int = int(summary.get("cycle", 0))
	if cycle > 0:
		# Бесконечная «Гонка»: номер круга рядом с номером волны.
		_title.text = tr("WAVE_N_CYCLE") % [n, cycle + 1]
	for c: Node in _groups.get_children():
		c.queue_free()
	for grp: Dictionary in summary["groups"]:
		var a: Dictionary = data.archetypes[grp["type"]]
		var row: HBoxContainer = Ui.hbox(T.SP_2)
		var icon_name: String = "boss" if a["boss"] else ("air" if a["flying"] else ("armored" if String(grp["type"]) == "armored" else ("swarm" if String(grp["type"]) == "swarm" else ("rush" if String(grp["type"]) == "fast" else "dot"))))
		row.add_child(Ui.icon(icon_name, 16, Color.html(String(a["color"]))))
		row.add_child(Ui.label(tr(String(a["name_key"])), "BodyLabel"))
		if bool(grp.get("elite", false)):
			var el: Label = Ui.label(tr("WAVE_ELITE"), "CapsLabel")
			el.add_theme_color_override("font_color", T.GOLD)
			row.add_child(el)
		row.add_child(Ui.spacer())
		var cnt: Label = Ui.label("×%d" % int(grp["count"]), "NumberLabel")
		cnt.add_theme_font_size_override("font_size", T.FS_M)
		row.add_child(cnt)
		_groups.add_child(row)
	for c2: Node in _traits.get_children():
		c2.queue_free()
	for t: Variant in summary.get("traits", []):
		_traits.add_child(_trait_chip(data, String(t)))
	_traits.visible = _traits.get_child_count() > 0
	_fill_recommend(data, summary)
	_hp.text = tr("WAVE_HP") % T.format_number(float(summary["base_hp"]) * data.difficulty_hp_mult(diff, n))
	if air:
		_advice.text = tr("WAVE_ADVICE_AIR")
	elif boss:
		_advice.text = tr("WAVE_ADVICE_BOSS")
	else:
		_advice.text = ""
	if bool(summary.get("finale", false)):
		var notes: String = Ui.finale_notes(data, summary.get("finale_cfg", {}))
		_advice.text = tr("WAVE_ADVICE_FINALE") + ("" if notes.is_empty() else " " + notes)
	if cycle > 0:
		var extra: String = tr("WAVE_ADVICE_CYCLE") % [cycle + 1, roundi((data.endless_count_mult(n) - 1.0) * 100.0),
			String.num(data.endless_armor_bonus(n)), roundi((data.endless_speed_mult(n) - 1.0) * 100.0)]
		_advice.text = extra if _advice.text.is_empty() else _advice.text + "\n" + extra
	_advice.visible = not _advice.text.is_empty()
	Ui.pop_in(_groups, 0.0, Vector2.ZERO)


## Чип трейта: иконка + название, в подсказке — эффект и контрплей.
static func _trait_chip(data: GameData, id: String) -> PanelContainer:
	var cfg: Dictionary = data.trait_cfg(id)
	var chip: PanelContainer = PanelContainer.new()
	chip.theme_type_variation = "ChipPanel"
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	var h: HBoxContainer = Ui.hbox(4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(Ui.icon(String(cfg.get("icon", "info")), 13, T.WARNING))
	var l: Label = Ui.label(TranslationServer.translate(String(cfg.get("name_key", id))), "BodyLabel")
	l.add_theme_font_size_override("font_size", T.FS_S)
	h.add_child(l)
	chip.add_child(h)
	chip.tooltip_text = Ui.tooltip_text([TranslationServer.translate(String(cfg.get("name_key", id))),
		TranslationServer.translate(String(cfg.get("desc_key", ""))),
		String(TranslationServer.translate("WAVE_COUNTER")) % TranslationServer.translate(String(cfg.get("counter_key", "")))])
	return chip


## «Эффективно»: типы урона с лучшим средним множителем против брони волны (иммунитеты исключены).
func _fill_recommend(data: GameData, summary: Dictionary) -> void:
	for c: Node in _recommend.get_children():
		c.queue_free()
	var scores: Dictionary = {}
	var total: float = 0.0
	for grp: Dictionary in summary["groups"]:
		var a: Dictionary = data.archetypes[grp["type"]]
		var weight: float = float(grp["count"]) * float(a["hp_mult"]) * (float(data.economy["elite"]["hp_mult"]) if bool(grp.get("elite", false)) else 1.0)
		total += weight
		var immune: Dictionary = {}
		var evasive: bool = false
		for t: Variant in grp["traits"]:
			for dt0: Variant in data.trait_cfg(String(t)).get("immune", []):
				immune[String(dt0)] = true
			evasive = evasive or String(t) == "evasion"
		for dt: String in data.damage_types:
			if dt == "pure":
				continue
			var m: float = 0.0 if immune.has(dt) else data.damage_mult(dt, String(a["armor_type"])) * float((a["resist"] as Dictionary).get(dt, 1.0))
			if evasive and (dt == "physical" or dt == "pierce"):
				m *= 0.8
			scores[dt] = float(scores.get(dt, 0.0)) + m * weight
	if total <= 0.0:
		_recommend.visible = false
		return
	var order: Array = scores.keys()
	order.sort_custom(func(x: Variant, y: Variant) -> bool: return float(scores[x]) > float(scores[y]))
	_recommend.add_child(Ui.label(tr("WAVE_EFFECTIVE"), "CapsLabel"))
	for dt2: Variant in order.slice(0, 3):
		_recommend.add_child(Ui.icon(String(T.DTYPE_ICON.get(String(dt2), "dot")), 12, T.dtype_color(String(dt2)).lightened(0.2)))
		var l: Label = Ui.label(tr("DMG_" + String(dt2).to_upper()), "BodyLabel")
		l.add_theme_color_override("font_color", T.dtype_color(String(dt2)).lightened(0.2))
		l.add_theme_font_size_override("font_size", T.FS_S)
		_recommend.add_child(l)
	_recommend.visible = true


## Запись журнала. category — combat / build / economy (фильтры), at — место события (клик переводит камеру).
## Добавляется одна строка сверху: в большом бою записей (утечки, MVP) несколько в секунду,
## и перестройка всех строк с переносом текста стоила ~1 мс на запись.
func log_event(text: String, icon_name: String, color: Color, category: String = "combat", at: Variant = null) -> void:
	var e: Dictionary = {"text": text, "icon": icon_name, "color": color, "category": category, "at": at}
	_entries.push_front(e)
	if _entries.size() > KEEP_LOG:
		_entries.resize(KEEP_LOG)
	if _filter != "all" and category != _filter:
		return
	var item: Control = _make_row(e)
	_log.add_child(item)
	_log.move_child(item, 0)
	while _log.get_child_count() > MAX_LOG:
		var last: Node = _log.get_child(_log.get_child_count() - 1)
		_log.remove_child(last)
		last.queue_free()
	_fade_rows()
	Ui.pop_in(item, 0.0, Vector2.ZERO)


## Полная перестройка — только при смене фильтра.
func _render_log() -> void:
	for c: Node in _log.get_children():
		_log.remove_child(c)
		c.queue_free()
	var shown: int = 0
	for e: Dictionary in _entries:
		if _filter != "all" and String(e["category"]) != _filter:
			continue
		_log.add_child(_make_row(e))
		shown += 1
		if shown >= MAX_LOG:
			break
	_fade_rows()


## Старые записи постепенно тускнеют.
func _fade_rows() -> void:
	for i: int in _log.get_child_count():
		(_log.get_child(i) as Control).modulate = Color(1, 1, 1, 1.0 - float(i) * 0.08)


func _make_row(e: Dictionary) -> Control:
	var row: HBoxContainer = Ui.hbox(T.SP_2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(Ui.icon(String(e["icon"]), 14, e["color"]))
	var l: Label = Ui.label(String(e["text"]), "DimLabel", true)
	l.custom_minimum_size = Vector2(260, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if e["at"] == null:
		return row
	# Запись с местом события кликабельна: камера переходит туда.
	var pc: PanelContainer = PanelContainer.new()
	pc.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pc.tooltip_text = tr("LOG_CLICK_TIP")
	pc.add_child(row)
	var at: Vector3 = e["at"]
	pc.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			Audio.play("sfx/ui/click")
			entry_clicked.emit(at))
	pc.mouse_entered.connect(func() -> void: l.add_theme_color_override("font_color", T.TEXT))
	pc.mouse_exited.connect(func() -> void: l.remove_theme_color_override("font_color"))
	return pc
