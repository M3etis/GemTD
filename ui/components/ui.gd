class_name Ui
extends RefCounted
## Фабрика компонентов дизайн-системы и общие анимации интерфейса.

const T := preload("res://ui/theme/ui_tokens.gd")
const GLASS_SHADER: Shader = preload("res://fx/shaders/glass.gdshader")

static var _glass_material: ShaderMaterial = null


static func glass_material() -> ShaderMaterial:
	if _glass_material == null:
		_glass_material = ShaderMaterial.new()
		_glass_material.shader = GLASS_SHADER
		_glass_material.set_shader_parameter("tint", T.GLASS_TINT)
	return _glass_material


static func label(text: String, variation: String = "", wrap: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	if not variation.is_empty():
		l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Название уровня сложности (`difficulty.json`) цветом уровня — в HUD и в итогах «Гонки».
static func difficulty_label(d: Dictionary, variation: String = "CapsLabel") -> Label:
	var l: Label = label(TranslationServer.translate(String(d.get("name_key", ""))), variation)
	l.add_theme_color_override("font_color", T.difficulty_color(String(d.get("id", ""))))
	return l


## Что особенного в финале забега стандартной длины (waves.json → lengths): элитные боссы и утечка
## финального босса — с перечнем сложностей, где её можно пережить. Пусто — финал обычный.
static func finale_notes(data: GameData, cfg: Dictionary) -> String:
	if cfg.is_empty():
		return ""
	var out: PackedStringArray = PackedStringArray()
	if bool(cfg["finale_elite"]) or float(cfg["finale_hp_mult"]) != 1.0:
		out.append(TranslationServer.translate("FINALE_ELITE"))
	var leak: int = int(cfg["finale_leak"])
	if leak > 0:
		var survive: PackedStringArray = PackedStringArray()
		for id: String in data.difficulty_order:
			var d: Dictionary = data.difficulty(id)
			if int(d["lives"]) > leak and not bool(d["boss_leak_instant_defeat"]):
				survive.append(TranslationServer.translate(String(d["name_key"])))
		if survive.is_empty():
			out.append(String(TranslationServer.translate("FINALE_LEAK_ALL")) % leak)
		else:
			out.append(String(TranslationServer.translate("FINALE_LEAK")) % [leak, ", ".join(survive)])
	return " ".join(out)


static func panel(variation: String = "GlassPanel", glass: bool = true) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.theme_type_variation = variation
	if glass:
		p.material = glass_material()
	return p


static func vbox(sep: int = T.SP_2) -> VBoxContainer:
	var b: VBoxContainer = VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func hbox(sep: int = T.SP_2) -> HBoxContainer:
	var b: HBoxContainer = HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func margin(all: int) -> MarginContainer:
	var m: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, all)
	return m


static func spacer(expand_h: bool = true, expand_v: bool = false) -> Control:
	var c: Control = Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand_h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand_v:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func icon(name: String, px: int = 18, color: Color = T.TEXT) -> UiIcon:
	var i: UiIcon = UiIcon.new()
	i.icon_name = name
	i.color = color
	i.custom_minimum_size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


static func hotkey(action: String, on_light: bool = false) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.theme_type_variation = "ChipPanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l: Label = label(Settings.key_label(action), "CapsLabel")
	l.add_theme_font_size_override("font_size", 11)
	if on_light:
		p.add_theme_stylebox_override("panel", ThemeBuilder.box(Color(0, 0, 0, 0.16), T.R_S, Color(0, 0, 0, 0.2), 1, T.SP_2, 2))
		l.add_theme_color_override("font_color", Color(T.BG, 0.75))
	p.add_child(l)
	return p


## Квадратная кнопка с иконкой по центру.
static func icon_button(icon_name: String, px: int = 16, variation: String = "GhostButton", box_size: Vector2 = Vector2(36, 32)) -> Button:
	var b: Button = Button.new()
	b.theme_type_variation = variation
	b.custom_minimum_size = box_size
	var c: CenterContainer = CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(c)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var i: UiIcon = icon(icon_name, px, T.TEXT_DIM if variation == "GhostButton" else T.TEXT)
	i.name = "Icon"
	c.add_child(i)
	attach_feedback(b)
	return b


## Кнопка дизайн-системы. Если задан action — справа подсказка клавиши; icon_name — иконка слева.
static func button(text: String, variation: String = "", action: String = "", icon_name: String = "") -> Button:
	var b: Button = Button.new()
	if not variation.is_empty():
		b.theme_type_variation = variation
	if action.is_empty() and icon_name.is_empty():
		b.text = text
	else:
		var row: HBoxContainer = hbox(T.SP_2)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		if not icon_name.is_empty():
			var fg: Color = T.BG if variation == "PrimaryButton" else T.TEXT
			row.add_child(icon(icon_name, 16, fg))
		if not text.is_empty():
			var l: Label = label(text)
			l.add_theme_font_override("font", T.font("ui_bold" if variation == "PrimaryButton" else "ui_medium"))
			if variation == "PrimaryButton":
				l.add_theme_color_override("font_color", T.BG)
			row.add_child(l)
		if not action.is_empty() and not Settings.key_label(action).is_empty():
			row.add_child(hotkey(action, variation == "PrimaryButton"))
		b.add_child(row)
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		var big: bool = variation == "PrimaryButton" or variation == "DangerButton"
		var pad_x: float = float(T.SP_5 * 2) if big else float(T.SP_4 * 2)
		var pad_y: float = float(T.SP_3 * 2) if big else float(T.SP_2 * 2)
		row.minimum_size_changed.connect(func() -> void:
			b.custom_minimum_size = row.get_combined_minimum_size() + Vector2(pad_x, pad_y))
		b.custom_minimum_size = row.get_combined_minimum_size() + Vector2(pad_x, pad_y)
	attach_feedback(b)
	return b


## Звук и микро-анимации для любой кнопки.
static func attach_feedback(b: BaseButton) -> void:
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			Audio.play("sfx/ui/hover")
			_scale_to(b, 1.03))
	b.mouse_exited.connect(func() -> void: _scale_to(b, 1.0))
	b.button_down.connect(func() -> void: _scale_to(b, 0.97))
	b.button_up.connect(func() -> void: _scale_to(b, 1.03 if b.is_hovered() else 1.0))
	b.pressed.connect(func() -> void: Audio.play("sfx/ui/click"))
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)


static func _scale_to(c: Control, s: float) -> void:
	if not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	var tw: Tween = c.create_tween()
	tw.tween_property(c, "scale", Vector2(s, s), T.dur(T.T_FAST)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Появление: прозрачность + сдвиг снизу.
static func pop_in(c: Control, delay: float = 0.0, offset: Vector2 = Vector2(0, 14)) -> void:
	c.modulate.a = 0.0
	var tw: Tween = c.create_tween()
	tw.tween_interval(T.dur(delay))
	tw.tween_property(c, "modulate:a", 1.0, T.dur(T.T_SLOW)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if offset != Vector2.ZERO and not (c.get_parent() is Container):
		var target: Vector2 = c.position
		c.position = target + offset
		tw.parallel().tween_property(c, "position", target, T.dur(T.T_SLOW)).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


static func stagger(items: Array, step: float = 0.035, start: float = 0.0) -> void:
	for i: int in items.size():
		pop_in(items[i] as Control, start + step * float(i), Vector2.ZERO)


## Плавный «счётчик» числа в Label.
static func tween_number(l: Label, from: float, to: float, duration: float, fmt: Callable) -> void:
	var tw: Tween = l.create_tween()
	tw.tween_method(func(v: float) -> void: l.text = fmt.call(v), from, to, T.dur(duration)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


static func punch(c: Control, amount: float = 1.12) -> void:
	c.pivot_offset = c.size * 0.5
	var tw: Tween = c.create_tween()
	tw.tween_property(c, "scale", Vector2(amount, amount), T.dur(0.08)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, T.dur(0.25)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func shake(c: Control, strength: float = 6.0) -> void:
	if Settings.reduce_motion():
		return
	var base: Vector2 = c.position
	var tw: Tween = c.create_tween()
	for i: int in 5:
		var k: float = strength * (1.0 - float(i) / 5.0)
		tw.tween_property(c, "position", base + Vector2(k if i % 2 == 0 else -k, 0), 0.035)
	tw.tween_property(c, "position", base, 0.04)


static func tooltip_text(lines: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for l: Variant in lines:
		parts.append(String(l))
	return "\n".join(parts)
