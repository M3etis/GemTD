class_name ChatPanel
extends VBoxContainer
## Чат «Гонки» в матче. Закрыт — последние сообщения поверх арены (каждое гаснет через LINE_SECONDS)
## и кнопка «Чат». Открыт (Enter) — история из Net.chat_log и поле ввода: Enter отправляет, Esc закрывает.
## Сообщение уходит через Net: хост пересылает его всем игрокам.

## Поле ввода получило или отдало клавиатуру (игра на это время выключает клавиши камеры).
signal typing_changed(on: bool)

const T := preload("res://ui/theme/ui_tokens.gd")
const WIDTH: float = 380.0
const FEED_LINES: int = 5
const LINE_SECONDS: float = 12.0
const FADE_SECONDS: float = 0.8

## Панель, которую закрытая лента не заслоняет (панель башни): при наложении лента почти прозрачна.
var avoid: Control
var _feed: VBoxContainer
var _open_btn: Button
var _box: PanelContainer
var _scroll: ScrollContainer
var _history: VBoxContainer
var _line: LineEdit
var _emoji: EmojiPicker
var _open: bool = false


func _init() -> void:
	theme = ThemeBuilder.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_constant_override("separation", T.SP_2)
	_feed = Ui.vbox(2)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)
	_open_btn = Ui.button(tr("MP_CHAT"), "GhostButton", "chat")
	_open_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# Без фокуса: иначе Space/Enter после клика снова нажимали бы кнопку.
	_open_btn.focus_mode = Control.FOCUS_NONE
	_open_btn.pressed.connect(open)
	add_child(_open_btn)
	_box = Ui.panel("GlassPanel")
	_box.visible = false
	add_child(_box)
	var col: VBoxContainer = Ui.vbox(T.SP_2)
	_box.add_child(col)
	col.add_child(Ui.label(tr("MP_CHAT"), "CapsLabel"))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(WIDTH - 32.0, 200)
	_scroll.focus_mode = Control.FOCUS_NONE
	_history = Ui.vbox(2)
	_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_history)
	col.add_child(_scroll)
	_line = LineEdit.new()
	_line.placeholder_text = tr("MP_CHAT_PLACEHOLDER_GAME")
	_line.max_length = NetProtocol.CHAT_MAX
	_line.text_submitted.connect(_on_submit)
	_line.gui_input.connect(_on_line_input)
	_line.focus_exited.connect(_on_focus_lost)
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_emoji = EmojiPicker.new()
	_emoji.picked.connect(func(e: String) -> void: EmojiPicker.insert_into(_line, e))
	col.add_child(_emoji)
	var input_row: HBoxContainer = Ui.hbox(T.SP_1)
	input_row.add_child(_line)
	input_row.add_child(_emoji.make_toggle())
	col.add_child(input_row)


func _ready() -> void:
	for m: Dictionary in Net.chat_log:
		_history.add_child(_line_label(String(m["sender"]), String(m["text"]), m["color"], false))
	Net.chat_received.connect(_on_message)


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_feed.visible = false
	_open_btn.visible = false
	_box.visible = true
	modulate.a = 1.0
	if _line.is_inside_tree():
		_line.grab_focus()
	typing_changed.emit(true)
	_scroll_down()


## Поле ввода потеряло фокус (клик по арене и т. п.) — чат закрывается. Кнопки эмодзи фокус не берут.
func _on_focus_lost() -> void:
	close()


func close() -> void:
	if not _open:
		return
	_open = false
	_emoji.visible = false
	_box.visible = false
	_feed.visible = true
	_open_btn.visible = true
	if _line.has_focus():
		_line.release_focus()
	typing_changed.emit(false)


func _on_submit(text: String) -> void:
	var clean: String = NetProtocol.sanitize_chat(text)
	_line.clear()
	# Сначала закрыть: своё сообщение (у хоста оно приходит сразу) тоже появится в ленте.
	close()
	if not clean.is_empty():
		Net.send_chat(clean)


## Esc закрывает чат и не доходит до игры (там он открыл бы меню паузы).
func _on_line_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu") or event.is_action_pressed("ui_cancel"):
		_line.accept_event()
		close()


func _on_message(sender: String, text: String, color: Color) -> void:
	_history.add_child(_line_label(sender, text, color, false))
	while _history.get_child_count() > NetProtocol.CHAT_HISTORY:
		var old: Node = _history.get_child(0)
		_history.remove_child(old)
		old.queue_free()
	if _open:
		_scroll_down()
	else:
		_add_feed(sender, text, color)
	var me: String = String(Net.players.get(Net.my_id(), {}).get("name", Net.my_name))
	if not sender.is_empty() and sender != me:
		Audio.play("sfx/ui/toast")


## Строка ленты поверх арены: с обводкой для читаемости, гаснет сама.
func _add_feed(sender: String, text: String, color: Color) -> void:
	var l: Label = _line_label(sender, text, color, true)
	_feed.add_child(l)
	while _feed.get_child_count() > FEED_LINES:
		var old: Node = _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()
	var tw: Tween = l.create_tween()
	tw.tween_interval(LINE_SECONDS)
	tw.tween_property(l, "modulate:a", 0.0, FADE_SECONDS)
	tw.tween_callback(l.queue_free)


func _line_label(sender: String, text: String, color: Color, outlined: bool) -> Label:
	var l: Label = Ui.label(("%s: %s" % [sender, text]) if not sender.is_empty() else text, "BodyLabel" if not sender.is_empty() else "DimLabel", true)
	l.custom_minimum_size = Vector2(WIDTH - 40.0, 0)
	if not sender.is_empty():
		l.add_theme_color_override("font_color", color.lightened(0.3))
	if outlined:
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return l


## К последнему сообщению — кадром позже, когда полоса прокрутки учтёт новые строки.
func _scroll_down() -> void:
	if is_inside_tree() and not get_tree().process_frame.is_connected(_apply_scroll):
		get_tree().process_frame.connect(_apply_scroll, CONNECT_ONE_SHOT)


func _apply_scroll() -> void:
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _process(delta: float) -> void:
	var dim: bool = not _open and avoid != null and avoid.visible and avoid.get_global_rect().intersects(get_global_rect())
	modulate.a = move_toward(modulate.a, 0.2 if dim else 1.0, delta * 4.0)
