class_name Modal
extends Control
## Модальное окно поверх экрана: затемнение + стеклянная панель. Закрывается по Esc.

signal closed

const T := preload("res://ui/theme/ui_tokens.gd")

var panel: PanelContainer
var body: VBoxContainer
var _dim: ColorRect
var close_on_escape: bool = true


func _init() -> void:
	theme = ThemeBuilder.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.015, 0.03, 0.62)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = Ui.panel("GlassPanel")
	center.add_child(panel)
	var m: MarginContainer = Ui.margin(T.SP_4)
	panel.add_child(m)
	body = Ui.vbox(T.SP_3)
	m.add_child(body)


func _ready() -> void:
	modulate.a = 0.0
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.96, 0.96)
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 1.0, T.dur(T.T_BASE))
	tw.parallel().tween_property(panel, "scale", Vector2.ONE, T.dur(T.T_SLOW)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Audio.play("sfx/ui/panel_open")
	_focus_first.call_deferred()


## Клавиатура: если фокус не внутри окна, он переходит на первый интерактивный элемент.
func _focus_first() -> void:
	if not is_inside_tree():
		return
	var owner: Control = get_viewport().gui_get_focus_owner()
	if owner != null and is_ancestor_of(owner):
		return
	# Главная кнопка окна важнее первого поля ввода: иначе Space/Enter уйдут в текстовое поле.
	var first: Control = _find_primary(body)
	if first == null:
		first = _find_focusable(body)
	if first != null:
		first.grab_focus()


static func _find_primary(n: Node) -> Control:
	for c: Node in n.get_children():
		var b: Button = c as Button
		if b != null and b.theme_type_variation == "PrimaryButton" and b.is_visible_in_tree() and not b.disabled:
			return b
		var deep: Control = _find_primary(c)
		if deep != null:
			return deep
	return null


static func _find_focusable(n: Node) -> Control:
	for c: Node in n.get_children():
		var ctl: Control = c as Control
		if ctl != null and ctl.focus_mode == Control.FOCUS_ALL and ctl.is_visible_in_tree() and not (ctl is BaseButton and (ctl as BaseButton).disabled):
			return ctl
		var deep: Control = _find_focusable(c)
		if deep != null:
			return deep
	return null


func close() -> void:
	Audio.play("sfx/ui/panel_close")
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, T.dur(T.T_FAST))
	tw.tween_callback(func() -> void:
		closed.emit()
		queue_free())


func _unhandled_input(event: InputEvent) -> void:
	if close_on_escape and event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		close()


func header(text: String, icon_name: String = "") -> void:
	var row: HBoxContainer = Ui.hbox(T.SP_3)
	if not icon_name.is_empty():
		row.add_child(Ui.icon(icon_name, 26, T.ACCENT))
	row.add_child(Ui.label(text, "HeaderLabel"))
	row.add_child(Ui.spacer())
	var x: Button = Ui.icon_button("close", 14, "GhostButton", Vector2(36, 36))
	x.tooltip_text = tr("ACT_CLOSE") + " (Esc)"
	x.pressed.connect(close)
	row.add_child(x)
	body.add_child(row)


## Диалог подтверждения. on_confirm вызывается при «Да».
static func confirm(parent: Node, title: String, text: String, confirm_text: String, on_confirm: Callable, danger: bool = true) -> Modal:
	# Настройка «Подтверждения» выключена: действие выполняется сразу.
	if not bool(Settings.get_value("gameplay", "confirmations")):
		on_confirm.call()
		return null
	var m: Modal = Modal.new()
	m.header(title, "info")
	var l: Label = Ui.label(text, "BodyLabel", true)
	l.custom_minimum_size = Vector2(420, 0)
	m.body.add_child(l)
	var row: HBoxContainer = Ui.hbox(T.SP_3)
	row.alignment = BoxContainer.ALIGNMENT_END
	var no: Button = Ui.button(TranslationServer.translate("ACT_CANCEL"), "GhostButton")
	no.pressed.connect(m.close)
	row.add_child(no)
	var yes: Button = Ui.button(confirm_text, "DangerButton" if danger else "PrimaryButton")
	yes.pressed.connect(func() -> void:
		m.close()
		on_confirm.call())
	row.add_child(yes)
	m.body.add_child(row)
	parent.add_child(m)
	yes.grab_focus.call_deferred()
	return m
