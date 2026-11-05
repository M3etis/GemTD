class_name OpponentsPanel
extends PanelContainer
## «Гонка»: игроки матча — жизни, золото, волна, статус; клик — наблюдать за полем соперника,
## клик по золоту соперника — передать ему золото.
## Обновляется раз в 0.25 с: строки пересобираются, только когда меняется их состав (игроки, кнопка
## золота, значок наблюдения), а числа и статус обновляются на месте — иначе клик, попавший на
## пересборку, терялся бы, а наведение каждый раз заново проигрывало бы звук.

signal watch_requested(id: int)
signal gift_requested(id: int)

const T := preload("res://ui/theme/ui_tokens.gd")
const STATUS_ICON: Dictionary = {"build": "gem", "ready": "check", "combat": "swords", "out": "skull", "victory": "crown", "left": "close"}

var watching: int = -1
var _list: VBoxContainer
var _title: Label
## Состав строк, из которого они собраны; другой состав — пересборка.
var _layout: String = ""
## Узлы строк для обновления на месте: id → {button, status, lives, wave, gold}.
var _row_nodes: Dictionary = {}


func _init() -> void:
	theme_type_variation = "GlassPanel"
	material = Ui.glass_material()
	custom_minimum_size = Vector2(380, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col: VBoxContainer = Ui.vbox(T.SP_2)
	add_child(col)
	_title = Ui.label(tr("MP_PLAYERS"), "CapsLabel")
	col.add_child(_title)
	_list = Ui.vbox(4)
	col.add_child(_list)
	visible = false


func update_rows(rows: Array[Dictionary], timer_text: String) -> void:
	visible = true
	_title.text = tr("MP_PLAYERS") + ("  ·  " + timer_text if not timer_text.is_empty() else "")
	var me_over: bool = false
	for r0: Dictionary in rows:
		me_over = me_over or (bool(r0["me"]) and bool(r0.get("over", false)))
	var layout: PackedStringArray = PackedStringArray()
	for r: Dictionary in rows:
		layout.append("%d:%s:%s:%s" % [int(r["id"]), bool(r["me"]), _can_gift(r, me_over), bool(r.get("watching_me", false))])
	var key: String = ",".join(layout)
	if key != _layout:
		_layout = key
		_rebuild(rows, me_over)
	for r2: Dictionary in rows:
		_fill(r2)


static func _can_gift(r: Dictionary, me_over: bool) -> bool:
	return not bool(r["me"]) and not bool(r.get("over", false)) and not me_over


func _rebuild(rows: Array[Dictionary], me_over: bool) -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	_row_nodes.clear()
	for r: Dictionary in rows:
		var id: int = int(r["id"])
		var b: Button = Button.new()
		b.theme_type_variation = "ChipButton"
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(356, 34)
		b.tooltip_text = tr("MP_WATCH_TIP") if not bool(r["me"]) else tr("MP_BACK_TIP")
		var row: HBoxContainer = Ui.hbox(T.SP_2)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bar: ColorRect = ColorRect.new()
		bar.color = Color.html(String(r["color"]))
		bar.custom_minimum_size = Vector2(4, 22)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bar)
		var status: UiIcon = Ui.icon("dot", 14, T.TEXT_DIM)
		row.add_child(status)
		var n: Label = Ui.label(String(r["name"]) + ("  (" + tr("MP_YOU") + ")" if bool(r["me"]) else ""), "BodyLabel")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(n)
		if bool(r.get("watching_me", false)):
			# Этот соперник сейчас смотрит ваше поле.
			row.add_child(Ui.icon("target", 12, T.ACCENT))
			b.tooltip_text += "\n" + tr("MP_WATCHING_YOU")
		var gold: Label = Ui.label("", "NumberLabel")
		row.add_child(_gold_chip(id, gold, _can_gift(r, me_over)))
		row.add_child(Ui.icon("heart", 12, T.LIFE))
		var lives: Label = Ui.label("", "NumberLabel")
		lives.add_theme_font_size_override("font_size", T.FS_S)
		row.add_child(lives)
		var w: Label = Ui.label("", "CapsLabel")
		row.add_child(w)
		b.add_child(row)
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 8
		row.offset_right = -8
		Ui.attach_feedback(b)
		b.pressed.connect(func() -> void: watch_requested.emit(id))
		_list.add_child(b)
		_row_nodes[id] = {"button": b, "status": status, "lives": lives, "wave": w, "gold": gold}


## Числа и статус строки — на месте, без пересборки.
func _fill(r: Dictionary) -> void:
	var id: int = int(r["id"])
	var n: Dictionary = _row_nodes.get(id, {})
	if n.is_empty():
		return
	(n["button"] as Button).set_pressed_no_signal(id == watching or (watching < 0 and bool(r["me"])))
	var status: String = String(r["status"])
	var icon: UiIcon = n["status"]
	icon.icon_name = String(STATUS_ICON.get(status, "dot"))
	icon.color = T.GOLD if status == "victory" else T.TEXT_DIM
	(n["lives"] as Label).text = str(int(r["lives"]))
	(n["wave"] as Label).text = tr("MP_WAVE_SHORT") % int(r["wave"])
	(n["gold"] as Label).text = str(int(r.get("gold", 0)))


## Золото игрока; у соперника в игре это кнопка «Передать золото».
func _gold_chip(id: int, gold: Label, can_gift: bool) -> Control:
	var h: HBoxContainer = Ui.hbox(3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(Ui.icon("coin", 12, T.GOLD))
	gold.add_theme_font_size_override("font_size", T.FS_S)
	gold.add_theme_color_override("font_color", T.GOLD)
	h.add_child(gold)
	if not can_gift:
		return h
	var b: Button = Button.new()
	b.theme_type_variation = "GhostButton"
	b.custom_minimum_size = Vector2(72, 26)
	b.tooltip_text = tr("MP_GIFT_TIP")
	b.add_child(h)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	Ui.attach_feedback(b)
	# После attach_feedback (он включает фокус): иначе Space после клика снова нажимал бы кнопку.
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: gift_requested.emit(id))
	return b
