class_name Banner
extends Control
## Крупный баннер по центру: старт волны, воздушная волна, босс, раунд.

const T := preload("res://ui/theme/ui_tokens.gd")

var _strip: ColorRect
var _title: Label
var _sub: Label
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_strip = ColorRect.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Плотнее, чем раньше: поле теперь светлое, и полупрозрачная полоса над ним выглядела серой.
	_strip.color = Color(0.03, 0.035, 0.06, 0.78)
	add_child(_strip)
	_title = Ui.label("", "HeaderLabel")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 56)
	add_child(_title)
	_sub = Ui.label("", "CapsLabel")
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_size_override("font_size", 14)
	add_child(_sub)
	visible = false


func show_banner(title: String, sub: String, color: Color, hold: float = 1.2) -> void:
	visible = true
	var vs: Vector2 = get_viewport_rect().size
	var h: float = vs.y
	var strip_h: float = 132.0
	_strip.position = Vector2(0, h * 0.36 - strip_h * 0.5)
	_strip.size = Vector2(vs.x, strip_h)
	_title.text = title
	_title.add_theme_color_override("font_color", color.lightened(0.25))
	_title.position = Vector2(0, h * 0.36 - 46)
	_title.size = Vector2(vs.x, 70)
	_sub.text = sub
	_sub.add_theme_color_override("font_color", color)
	_sub.position = Vector2(0, h * 0.36 + 26)
	_sub.size = Vector2(vs.x, 24)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 0.0
	_title.position.x = -60.0
	_sub.position.x = 60.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, T.dur(0.22))
	_tween.parallel().tween_property(_title, "position:x", 0.0, T.dur(0.5)).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_sub, "position:x", 0.0, T.dur(0.5)).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(hold)
	_tween.tween_property(self, "modulate:a", 0.0, T.dur(0.4))
	_tween.tween_callback(func() -> void: visible = false)
