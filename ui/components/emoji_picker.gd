class_name EmojiPicker
extends PanelContainer
## Эмодзи для чата «Гонки» (в матче и в лобби): сетка кнопок, клик вставляет эмодзи в поле ввода.
## Кнопки не берут фокус — поле ввода остаётся активным, и чат в матче не закрывается.
## Эмодзи рисует системный шрифт (Apple Color Emoji) через запасные шрифты Godot: в Inter их нет.

signal picked(emoji: String)

const T := preload("res://ui/theme/ui_tokens.gd")
const COLUMNS: int = 8
const EMOJI: Array[String] = [
	"😀", "😂", "😅", "😎", "🤔", "😮", "😢", "😡",
	"👍", "👎", "👏", "🙏", "💪", "🙌", "👀", "🎉",
	"🔥", "💎", "👑", "💀", "⚡", "🛡️", "🏆", "🍀",
	"❤️", "⭐", "🚀", "🐢", "😈", "🤯", "🎯", "💰",
]


func _init() -> void:
	theme_type_variation = "ChipPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var grid: GridContainer = GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	add_child(grid)
	for e: String in EMOJI:
		var b: Button = Button.new()
		b.flat = true
		b.text = e
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(36, 34)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func() -> void:
			Audio.play("sfx/ui/click")
			picked.emit(e))
		grid.add_child(b)


## Кнопка «🙂», которая показывает и прячет панель.
func make_toggle() -> Button:
	var b: Button = Button.new()
	b.theme_type_variation = "GhostButton"
	b.text = "🙂"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(38, 32)
	b.add_theme_font_size_override("font_size", 18)
	b.tooltip_text = TranslationServer.translate("CHAT_EMOJI")
	b.pressed.connect(func() -> void:
		visible = not visible
		Audio.play("sfx/ui/click"))
	return b


## Вставить эмодзи в поле ввода у курсора, не превышая лимит длины поля.
static func insert_into(line: LineEdit, emoji: String) -> void:
	if line.max_length > 0 and line.text.length() + emoji.length() > line.max_length:
		return
	line.insert_text_at_caret(emoji)
	if line.is_inside_tree() and line.is_visible_in_tree():
		line.grab_focus()
