class_name PhaseBar
extends VBoxContainer
## Нижняя часть HUD: статус фазы, карточки гемов, кнопки действий выбора
## (Keep / Combine / Forge / усиление) и подсказка о доступном сплаве на поле.

signal card_selected(slot: int)
signal card_hovered(slot: int, on: bool)
## id действия: keep, start, combine2, combine4, forge:<special>, upgrade3:<x>:<y>, board_forge:<x>:<y>:<special>
signal action_pressed(id: String)

const T := preload("res://ui/theme/ui_tokens.gd")

var _cards_row: HBoxContainer
var _cards: Array[GemCard] = []
var _alert: PanelContainer
var _alert_label: Label
var _alert_actions: HBoxContainer
var _status: PanelContainer
var _title: Label
var _hint: Label
var _pips: HBoxContainer
var _progress: ProgressBar
var _actions: HBoxContainer
var _mode: String = ""


func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", T.SP_3)
	_cards_row = Ui.hbox(T.SP_3)
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_row.visible = false
	add_child(_cards_row)
	_alert = Ui.panel("GlassPanel")
	_alert.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var arow: HBoxContainer = Ui.hbox(T.SP_3)
	arow.add_child(Ui.icon("sparkle", 18, T.GOLD))
	_alert_label = Ui.label("", "BodyLabel")
	_alert_label.add_theme_color_override("font_color", T.GOLD.lightened(0.3))
	arow.add_child(_alert_label)
	_alert_actions = Ui.hbox(T.SP_2)
	arow.add_child(_alert_actions)
	_alert.add_child(arow)
	_alert.visible = false
	add_child(_alert)
	_status = Ui.panel("GlassPanel")
	_status.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_status.custom_minimum_size = Vector2(640, 0)
	add_child(_status)
	var row: HBoxContainer = Ui.hbox(T.SP_4)
	_status.add_child(row)
	var texts: VBoxContainer = Ui.vbox(2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = Ui.label("", "SubheaderLabel")
	texts.add_child(_title)
	_hint = Ui.label("", "DimLabel")
	texts.add_child(_hint)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 6)
	_progress.visible = false
	texts.add_child(_progress)
	row.add_child(texts)
	_pips = Ui.hbox(6)
	_pips.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_pips)
	_actions = Ui.hbox(T.SP_2)
	row.add_child(_actions)


## Кнопки действий: [{id, text, icon, variation, action, tooltip, disabled}].
## highlight — префикс id кнопки, которую подсвечивает обучение (пульсирующее свечение).
func set_actions(list: Array[Dictionary], highlight: String = "") -> void:
	for c: Node in _actions.get_children():
		c.queue_free()
	for a: Dictionary in list:
		var b: Button = _make_button(a)
		_actions.add_child(b)
		if not highlight.is_empty() and String(a["id"]).begins_with(highlight) and not b.disabled:
			_pulse(b)


func _pulse(b: Button) -> void:
	if Settings.reduce_motion():
		b.modulate = Color(1.35, 1.35, 1.35)
		return
	var tw: Tween = b.create_tween().set_loops()
	tw.tween_property(b, "modulate", Color(1.5, 1.5, 1.5), 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_property(b, "modulate", Color.WHITE, 0.45).set_trans(Tween.TRANS_SINE)


func _make_button(a: Dictionary) -> Button:
	var b: Button = Ui.button(String(a.get("text", "")), String(a.get("variation", "Button")), String(a.get("action", "")), String(a.get("icon", "")))
	b.tooltip_text = String(a.get("tooltip", ""))
	b.disabled = bool(a.get("disabled", false))
	var id: String = String(a["id"])
	b.pressed.connect(func() -> void: action_pressed.emit(id))
	return b


## Подсказка о рецепте, который можно сплавить из башен на поле.
func show_board_forge(options: Array[Dictionary], data: GameData) -> void:
	for c: Node in _alert_actions.get_children():
		c.queue_free()
	if options.is_empty():
		_alert.visible = false
		return
	var names: PackedStringArray = PackedStringArray()
	for o: Dictionary in options:
		var n: String = tr(String(data.special(String(o["special"]))["name_key"]))
		if not names.has(n):
			names.append(n)
	_alert_label.text = tr("FORGE_ALERT") % ", ".join(names)
	var first: bool = true
	for o: Dictionary in options:
		var cell: Vector2i = o["cell"]
		var sp: String = String(o["special"])
		_alert_actions.add_child(_make_button({
			"id": "board_forge:%d:%d:%s" % [cell.x, cell.y, sp],
			"text": tr("ACT_FORGE_NAMED") % tr(String(data.special(sp)["name_key"])),
			"icon": "sparkle", "variation": "PrimaryButton" if first else "Button",
			"action": "forge" if first else "",
		}))
		first = false
		if _alert_actions.get_child_count() >= 3:
			break
	if not _alert.visible:
		_alert.visible = true
		Ui.pop_in(_alert, 0.0, Vector2.ZERO)
		Audio.play("sfx/ui/toast")


func show_placing(round_index: int, placed: int, total: int) -> void:
	_cards_row.visible = false
	_clear_cards()
	_title.text = tr("PHASE_BUILD") % round_index
	_hint.text = tr("PHASE_BUILD_HINT") % (total - placed)
	_progress.visible = false
	set_actions([] as Array[Dictionary])
	_set_pips(placed, total, T.ACCENT)
	if _mode != "placing":
		Ui.pop_in(_status, 0.0, Vector2.ZERO)
	_mode = "placing"
	_status.visible = true


func show_choosing(data: GameData, candidates: Array[Dictionary], next_air: bool, selected_slot: int, hints: Array[Dictionary]) -> void:
	_mode = "choosing"
	_status.visible = true
	_title.text = tr("PHASE_CHOOSE")
	_hint.text = tr("PHASE_CHOOSE_HINT")
	_progress.visible = false
	_pips.visible = false
	_clear_cards()
	_cards_row.visible = true
	for i: int in candidates.size():
		var card: GemCard = GemCard.new()
		card.setup(data, candidates[i], next_air, hints[i] if i < hints.size() else {})
		card.chosen.connect(func(s: int) -> void: card_selected.emit(s))
		# Двойной клик по карточке только выбирает гем: оставить его можно лишь кнопкой «Оставить».
		card.activated.connect(func(s: int) -> void: card_selected.emit(s))
		card.hovered.connect(func(s: int, on: bool) -> void: card_hovered.emit(s, on))
		_cards_row.add_child(card)
		_cards.append(card)
	Ui.stagger(_cards, 0.05)
	select_card(selected_slot)


func select_card(slot: int) -> void:
	for c: GemCard in _cards:
		c.set_selected(c.slot == slot)


func show_ready(wave: int, seconds_left: float, autostart: bool) -> void:
	if _mode != "ready":
		set_actions([{"id": "start", "text": tr("ACT_START_WAVE"), "icon": "play", "variation": "PrimaryButton", "action": "confirm"}] as Array[Dictionary])
	_mode = "ready"
	_status.visible = true
	_cards_row.visible = false
	_clear_cards()
	_pips.visible = false
	_progress.visible = false
	_title.text = tr("PHASE_READY") % wave
	_hint.text = (tr("PHASE_READY_COUNTDOWN") % ceili(maxf(seconds_left, 0.0))) if autostart else tr("PHASE_READY_HINT")


## «Гонка»: игрок готов, ждём остальных.
func show_waiting(wave: int, ready_n: int, total: int, timer_text: String) -> void:
	_mode = "waiting"
	_status.visible = true
	_cards_row.visible = false
	_pips.visible = false
	_progress.visible = false
	set_actions([] as Array[Dictionary])
	_title.text = tr("PHASE_READY") % wave
	_hint.text = tr("MP_WAITING") % [ready_n, total] + ("  ·  " + timer_text if not timer_text.is_empty() else "")


func show_combat(wave: int, alive: int, spawned: int, total: int) -> void:
	if _mode != "combat":
		_cards_row.visible = false
		_clear_cards()
		_pips.visible = false
		set_actions([] as Array[Dictionary])
		# Сплав доступен и в бою: строку сплава показывает/прячет show_board_forge.
		_progress.visible = true
		_mode = "combat"
	_status.visible = true
	_title.text = tr("PHASE_COMBAT") % wave
	var remaining: int = alive + (total - spawned)
	_hint.text = tr("PHASE_COMBAT_HINT") % remaining
	_progress.max_value = maxf(float(total), 1.0)
	_progress.value = float(total - remaining)


func hide_all() -> void:
	_mode = "hidden"
	_cards_row.visible = false
	_clear_cards()
	_status.visible = false
	_alert.visible = false


func _set_pips(filled: int, total: int, color: Color) -> void:
	_pips.visible = true
	for c: Node in _pips.get_children():
		c.queue_free()
	for i: int in total:
		var ic: UiIcon = Ui.icon("gem", 18, color if i < filled else Color(1, 1, 1, 0.14))
		_pips.add_child(ic)
		if i == filled - 1:
			ic.ready.connect(func() -> void: Ui.punch(ic, 1.5))


func _clear_cards() -> void:
	for c: GemCard in _cards:
		c.queue_free()
	_cards.clear()
