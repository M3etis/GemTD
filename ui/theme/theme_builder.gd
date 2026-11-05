class_name ThemeBuilder
extends RefCounted
## Собирает Theme из UiTokens. Все стили интерфейса — здесь, сцены не задают цвета вручную.

const T := preload("res://ui/theme/ui_tokens.gd")

static var _theme: Theme = null
## Исходные размеры шрифтов темы: [имя, тип, размер] — для масштаба текста (доступность).
static var _base_sizes: Array = []
static var _text_scale: float = 1.0


static func get_theme() -> Theme:
	if _theme == null:
		_theme = build()
		for type: StringName in _theme.get_font_size_type_list():
			for name: StringName in _theme.get_font_size_list(type):
				_base_sizes.append([name, type, _theme.get_font_size(name, type)])
		_base_sizes.append(["", "", _theme.default_font_size])
		apply_text_scale(_text_scale)
	return _theme


## Масштаб текста: тема меняется на месте, поэтому все экраны, использующие её, обновляются сразу.
static func apply_text_scale(scale: float) -> void:
	_text_scale = scale
	if _theme == null:
		return
	for e: Array in _base_sizes:
		var size: int = roundi(float(e[2]) * scale)
		if String(e[1]).is_empty():
			_theme.default_font_size = size
		else:
			_theme.set_font_size(e[0], e[1], size)


static func box(bg: Color, radius: int = T.R_M, border: Color = Color(0, 0, 0, 0), border_w: int = 0, pad_h: int = T.SP_4, pad_v: int = T.SP_2) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	s.anti_aliasing = true
	s.corner_detail = 10
	return s


## 9-slice рамка из SVG (assets/ui/<name>.svg, DPITexture — чёткая при любом масштабе UI).
## Нет файла — запасной StyleBoxFlat с тем же цветом, чтобы интерфейс не ломался.
static func frame(name: String, margin: int, pad_h: int, pad_v: int, fallback: Color = T.SURFACE) -> StyleBox:
	var path: String = T.UI_DIR + name + ".svg"
	if not ResourceLoader.exists(path):
		return box(fallback, T.R_M, T.GLASS_BORDER, 1, pad_h, pad_v)
	var s: StyleBoxTexture = StyleBoxTexture.new()
	s.texture = load(path)
	s.set_texture_margin_all(margin)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	return s


static func icon(name: String) -> Texture2D:
	var path: String = T.UI_DIR + name + ".svg"
	return load(path) if ResourceLoader.exists(path) else null


static func build() -> Theme:
	var th: Theme = Theme.new()
	th.default_font = T.font("ui")
	th.default_font_size = T.FS_M

	# --- Текст
	th.set_color("font_color", "Label", T.TEXT)
	th.set_constant("line_spacing", "Label", 2)
	_label_variation(th, "TitleLabel", "heading_bold", T.FS_HERO, T.TEXT)
	_label_variation(th, "HeaderLabel", "heading_bold", T.FS_XXL, T.TEXT)
	_label_variation(th, "SubheaderLabel", "ui_bold", T.FS_L, T.TEXT)
	_label_variation(th, "BodyLabel", "ui", T.FS_M, T.TEXT)
	_label_variation(th, "DimLabel", "ui", T.FS_S, T.TEXT_DIM)
	_label_variation(th, "FaintLabel", "ui", T.FS_XS, T.TEXT_FAINT)
	_label_variation(th, "CapsLabel", "caps", T.FS_XS, T.TEXT_DIM)
	_label_variation(th, "NumberLabel", "num", T.FS_L, T.TEXT)
	_label_variation(th, "BigNumberLabel", "num", T.FS_XL, T.TEXT)
	th.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))
	# Заголовки поверх 3D-сцены (баннер раунда, финальные экраны) — с тёмной обводкой.
	for v: String in ["TitleLabel", "HeaderLabel"]:
		th.set_color("font_outline_color", v, Color(0.02, 0.02, 0.04, 0.7))
		th.set_constant("outline_size", v, 6)

	# --- Кнопки
	_button_style(th, "Button", T.SURFACE_HI, T.GLASS_BORDER, T.TEXT, T.ACCENT)
	th.set_font("font", "Button", T.font("ui_medium"))
	th.set_font_size("font_size", "Button", T.FS_M)
	th.set_constant("h_separation", "Button", T.SP_2)

	th.add_type("PrimaryButton")
	th.set_type_variation("PrimaryButton", "Button")
	th.set_stylebox("normal", "PrimaryButton", frame("ui_btn_primary_normal", 10, T.SP_5, T.SP_3, T.ACCENT))
	th.set_stylebox("hover", "PrimaryButton", frame("ui_btn_primary_hover", 10, T.SP_5, T.SP_3, T.ACCENT))
	th.set_stylebox("pressed", "PrimaryButton", frame("ui_btn_primary_pressed", 10, T.SP_5, T.SP_3, T.ACCENT))
	th.set_stylebox("hover_pressed", "PrimaryButton", frame("ui_btn_primary_pressed", 10, T.SP_5, T.SP_3, T.ACCENT))
	th.set_stylebox("focus", "PrimaryButton", box(Color(0, 0, 0, 0), T.R_M, Color.WHITE, 2))
	th.set_stylebox("disabled", "PrimaryButton", frame("ui_btn_primary_disabled", 10, T.SP_5, T.SP_3, T.ACCENT_DEEP))
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		th.set_color(c, "PrimaryButton", T.BG)
	th.set_color("font_disabled_color", "PrimaryButton", T.TEXT_FAINT)
	th.set_font("font", "PrimaryButton", T.font("ui_bold"))

	th.add_type("GhostButton")
	th.set_type_variation("GhostButton", "Button")
	th.set_stylebox("normal", "GhostButton", box(Color(0, 0, 0, 0), T.R_M, Color(0, 0, 0, 0), 0, T.SP_3, T.SP_2))
	th.set_stylebox("hover", "GhostButton", box(Color(1, 1, 1, 0.06), T.R_M, Color(0, 0, 0, 0), 0, T.SP_3, T.SP_2))
	th.set_stylebox("pressed", "GhostButton", box(Color(1, 1, 1, 0.1), T.R_M, Color(0, 0, 0, 0), 0, T.SP_3, T.SP_2))
	th.set_stylebox("focus", "GhostButton", box(Color(0, 0, 0, 0), T.R_M, T.ACCENT, 1))
	th.set_color("font_color", "GhostButton", T.TEXT_DIM)
	th.set_color("font_hover_color", "GhostButton", T.TEXT)

	th.add_type("DangerButton")
	th.set_type_variation("DangerButton", "Button")
	th.set_stylebox("normal", "DangerButton", frame("ui_btn_danger_normal", 10, T.SP_5, T.SP_3, T.DANGER.darkened(0.55)))
	th.set_stylebox("hover", "DangerButton", frame("ui_btn_danger_hover", 10, T.SP_5, T.SP_3, T.DANGER.darkened(0.35)))
	th.set_stylebox("pressed", "DangerButton", box(T.DANGER.darkened(0.6), T.R_M, T.DANGER, 1, T.SP_5, T.SP_3))

	th.add_type("ChipButton")
	th.set_type_variation("ChipButton", "Button")
	th.set_stylebox("normal", "ChipButton", box(Color(1, 1, 1, 0.04), T.R_S, Color(1, 1, 1, 0.08), 1, T.SP_2, T.SP_1))
	th.set_stylebox("hover", "ChipButton", box(Color(1, 1, 1, 0.09), T.R_S, T.BORDER_STRONG, 1, T.SP_2, T.SP_1))
	th.set_stylebox("pressed", "ChipButton", box(T.ACCENT.darkened(0.55), T.R_S, T.ACCENT, 1, T.SP_2, T.SP_1))
	th.set_stylebox("hover_pressed", "ChipButton", box(T.ACCENT.darkened(0.45), T.R_S, T.ACCENT, 1, T.SP_2, T.SP_1))
	# Кольцо фокуса — навигация с клавиатуры видна на всех кнопках.
	th.set_stylebox("focus", "ChipButton", box(Color(0, 0, 0, 0), T.R_S, T.ACCENT, 1))
	th.set_color("font_color", "ChipButton", T.TEXT_DIM)
	th.set_color("font_pressed_color", "ChipButton", T.TEXT)
	th.set_color("font_hover_pressed_color", "ChipButton", T.TEXT)
	th.set_font("font", "ChipButton", T.font("num"))
	th.set_font_size("font_size", "ChipButton", T.FS_S)

	# --- Панели
	# Панели: чернильное стекло с латунной волосяной линией и уголками (9-slice из SVG).
	th.set_stylebox("panel", "PanelContainer", frame("ui_panel_glass", 16, T.SP_4, T.SP_4))
	th.add_type("GlassPanel")
	th.set_type_variation("GlassPanel", "PanelContainer")
	th.set_stylebox("panel", "GlassPanel", frame("ui_panel_glass", 16, T.SP_4, T.SP_4))
	th.add_type("CardPanel")
	th.set_type_variation("CardPanel", "PanelContainer")
	th.set_stylebox("panel", "CardPanel", frame("ui_panel_card", 10, T.SP_3, T.SP_3, T.SURFACE_HI))
	th.add_type("InsetPanel")
	th.set_type_variation("InsetPanel", "PanelContainer")
	th.set_stylebox("panel", "InsetPanel", frame("ui_panel_inset", 10, T.SP_3, T.SP_2, Color(0, 0, 0, 0.25)))
	th.add_type("ChipPanel")
	th.set_type_variation("ChipPanel", "PanelContainer")
	th.set_stylebox("panel", "ChipPanel", box(Color(1, 1, 1, 0.06), T.R_S, Color(1, 1, 1, 0.08), 1, T.SP_2, 2))

	# --- Поля ввода
	var le: StyleBoxFlat = box(T.SURFACE_LOW, T.R_M, T.GLASS_BORDER, 1, T.SP_3, T.SP_2)
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), T.R_M, T.ACCENT, 2))
	th.set_stylebox("read_only", "LineEdit", le)
	th.set_color("font_color", "LineEdit", T.TEXT)
	th.set_color("font_placeholder_color", "LineEdit", T.TEXT_FAINT)
	th.set_color("caret_color", "LineEdit", T.ACCENT)
	th.set_color("selection_color", "LineEdit", T.ACCENT.darkened(0.5))
	th.set_font("font", "LineEdit", T.font("num"))
	# Многострочный текст только для чтения (лицензии).
	th.set_stylebox("normal", "TextEdit", le)
	th.set_stylebox("focus", "TextEdit", box(T.SURFACE_LOW, T.R_M, T.BORDER_STRONG, 1, T.SP_3, T.SP_2))
	th.set_stylebox("read_only", "TextEdit", le)
	th.set_color("font_color", "TextEdit", T.TEXT)
	th.set_color("font_readonly_color", "TextEdit", T.TEXT_DIM)
	th.set_color("selection_color", "TextEdit", T.ACCENT.darkened(0.5))
	th.set_font_size("font_size", "TextEdit", T.FS_S)

	# --- Слайдеры, чекбоксы, выпадающие списки
	th.set_stylebox("slider", "HSlider", box(Color(1, 1, 1, 0.08), 3, Color(0, 0, 0, 0), 0, 0, 3))
	th.set_stylebox("grabber_area", "HSlider", box(T.ACCENT.darkened(0.2), 3, Color(0, 0, 0, 0), 0, 0, 3))
	th.set_stylebox("grabber_area_highlight", "HSlider", box(T.ACCENT, 3, Color(0, 0, 0, 0), 0, 0, 3))
	th.set_icon("grabber", "HSlider", icon("ui_slider_grabber"))
	th.set_icon("grabber_highlight", "HSlider", icon("ui_slider_grabber_hl"))
	th.set_icon("checked", "CheckButton", icon("ui_toggle_on"))
	th.set_icon("unchecked", "CheckButton", icon("ui_toggle_off"))
	th.set_icon("checked_disabled", "CheckButton", icon("ui_toggle_on"))
	th.set_icon("unchecked_disabled", "CheckButton", icon("ui_toggle_off"))
	th.set_icon("checked", "CheckBox", icon("ui_check_on"))
	th.set_icon("unchecked", "CheckBox", icon("ui_check_off"))
	th.set_icon("arrow", "OptionButton", icon("ui_select_arrow"))
	th.set_color("font_color", "CheckBox", T.TEXT)
	th.set_color("font_hover_color", "CheckBox", T.TEXT)
	th.set_color("font_pressed_color", "CheckBox", T.TEXT)
	th.set_color("font_color", "CheckButton", T.TEXT)
	th.set_color("font_hover_color", "CheckButton", T.TEXT)
	th.set_color("font_pressed_color", "CheckButton", T.TEXT)
	for t: String in ["CheckBox", "CheckButton"]:
		th.set_stylebox("normal", t, box(Color(0, 0, 0, 0), T.R_M, Color(0, 0, 0, 0), 0, T.SP_2, T.SP_1))
		th.set_stylebox("hover", t, box(Color(1, 1, 1, 0.05), T.R_M, Color(0, 0, 0, 0), 0, T.SP_2, T.SP_1))
		th.set_stylebox("pressed", t, box(Color(0, 0, 0, 0), T.R_M, Color(0, 0, 0, 0), 0, T.SP_2, T.SP_1))
		th.set_stylebox("hover_pressed", t, box(Color(1, 1, 1, 0.05), T.R_M, Color(0, 0, 0, 0), 0, T.SP_2, T.SP_1))
		th.set_stylebox("focus", t, box(Color(0, 0, 0, 0), T.R_M, T.ACCENT, 1))
	_button_style(th, "OptionButton", T.SURFACE_LOW, T.GLASS_BORDER, T.TEXT, T.ACCENT)
	th.set_stylebox("panel", "PopupMenu", box(T.SURFACE, T.R_M, T.GLASS_BORDER, 1, T.SP_2, T.SP_2))
	th.set_stylebox("hover", "PopupMenu", box(T.ACCENT.darkened(0.6), T.R_S, Color(0, 0, 0, 0), 0))
	th.set_color("font_color", "PopupMenu", T.TEXT_DIM)
	th.set_color("font_hover_color", "PopupMenu", T.TEXT)

	# --- Тултипы
	th.set_stylebox("panel", "TooltipPanel", frame("ui_panel_card", 10, T.SP_3, T.SP_2, T.SURFACE_LOW))
	th.set_color("font_color", "TooltipLabel", T.TEXT)
	th.set_font("font", "TooltipLabel", T.font("ui"))
	th.set_font_size("font_size", "TooltipLabel", T.FS_S)

	# --- Прокрутка, вкладки, прогресс, разделители
	for sb: String in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", sb, box(Color(0, 0, 0, 0), 3, Color(0, 0, 0, 0), 0, 3, 3))
		th.set_stylebox("grabber", sb, box(Color(1, 1, 1, 0.12), 3, Color(0, 0, 0, 0), 0, 3, 3))
		th.set_stylebox("grabber_highlight", sb, box(Color(1, 1, 1, 0.22), 3, Color(0, 0, 0, 0), 0, 3, 3))
		th.set_stylebox("grabber_pressed", sb, box(T.ACCENT.darkened(0.3), 3, Color(0, 0, 0, 0), 0, 3, 3))
	th.set_stylebox("tab_selected", "TabBar", box(T.ACCENT.darkened(0.6), T.R_S, T.ACCENT, 1, T.SP_4, T.SP_2))
	th.set_stylebox("tab_unselected", "TabBar", box(Color(0, 0, 0, 0), T.R_S, Color(0, 0, 0, 0), 0, T.SP_4, T.SP_2))
	th.set_stylebox("tab_hovered", "TabBar", box(Color(1, 1, 1, 0.06), T.R_S, Color(0, 0, 0, 0), 0, T.SP_4, T.SP_2))
	th.set_stylebox("tab_focus", "TabBar", box(Color(0, 0, 0, 0), T.R_S, T.ACCENT, 1))
	th.set_color("font_selected_color", "TabBar", T.TEXT)
	th.set_color("font_unselected_color", "TabBar", T.TEXT_DIM)
	th.set_color("font_hovered_color", "TabBar", T.TEXT)
	th.set_font("font", "TabBar", T.font("ui_medium"))
	# TabContainer (настройки, кодекс) не наследует стили TabBar — задаются отдельно.
	for k: String in ["tab_selected", "tab_unselected", "tab_hovered", "tab_focus"]:
		th.set_stylebox(k, "TabContainer", th.get_stylebox(k, "TabBar"))
	th.set_stylebox("panel", "TabContainer", box(Color(0, 0, 0, 0.18), T.R_M, T.BORDER, 1, T.SP_4, T.SP_4))
	th.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	th.set_color("font_selected_color", "TabContainer", T.TEXT)
	th.set_color("font_unselected_color", "TabContainer", T.TEXT_DIM)
	th.set_color("font_hovered_color", "TabContainer", T.TEXT)
	th.set_font("font", "TabContainer", T.font("ui_medium"))
	th.set_constant("side_margin", "TabContainer", 0)
	th.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.06), 4, Color(0, 0, 0, 0), 0, 0, 0))
	th.set_stylebox("fill", "ProgressBar", box(T.ACCENT, 4, Color(0, 0, 0, 0), 0, 0, 0))
	var sep: StyleBoxLine = StyleBoxLine.new()
	sep.color = T.BORDER
	sep.thickness = 1
	th.set_stylebox("separator", "HSeparator", sep)
	var vsep: StyleBoxLine = StyleBoxLine.new()
	vsep.color = T.BORDER
	vsep.thickness = 1
	vsep.vertical = true
	th.set_stylebox("separator", "VSeparator", vsep)
	th.set_constant("separation", "HSeparator", T.SP_3)
	th.set_constant("separation", "VBoxContainer", T.SP_2)
	th.set_constant("separation", "HBoxContainer", T.SP_2)
	return th


static func _label_variation(th: Theme, name: String, font_kind: String, size: int, color: Color) -> void:
	th.add_type(name)
	th.set_type_variation(name, "Label")
	th.set_font("font", name, T.font(font_kind))
	th.set_font_size("font_size", name, size)
	th.set_color("font_color", name, color)


## Кнопки — 9-slice из SVG во всех состояниях: normal, hover, pressed, disabled, focus.
static func _button_style(th: Theme, type: String, bg: Color, _border: Color, fg: Color, accent: Color) -> void:
	th.set_stylebox("normal", type, frame("ui_btn_normal", 10, T.SP_4, T.SP_2, bg))
	th.set_stylebox("hover", type, frame("ui_btn_hover", 10, T.SP_4, T.SP_2, bg.lightened(0.08)))
	th.set_stylebox("pressed", type, frame("ui_btn_pressed", 10, T.SP_4, T.SP_2, bg.darkened(0.2)))
	th.set_stylebox("hover_pressed", type, frame("ui_btn_pressed", 10, T.SP_4, T.SP_2, bg.darkened(0.1)))
	th.set_stylebox("disabled", type, frame("ui_btn_disabled", 10, T.SP_4, T.SP_2, bg.darkened(0.3)))
	th.set_stylebox("focus", type, frame("ui_btn_focus", 10, 0, 0, Color(0, 0, 0, 0)))
	th.set_color("font_color", type, fg)
	th.set_color("font_hover_color", type, Color.WHITE)
	th.set_color("font_pressed_color", type, accent.lightened(0.3))
	th.set_color("font_focus_color", type, fg)
	th.set_color("font_hover_pressed_color", type, Color.WHITE)
	th.set_color("font_disabled_color", type, T.TEXT_FAINT)
