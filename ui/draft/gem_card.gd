class_name GemCard
extends Control
## Карточка гема в панели выбора: иконка, качество, роль, статы, DPS против следующей волны.

signal chosen(slot: int)
signal activated(slot: int)
signal hovered(slot: int, on: bool)

const T := preload("res://ui/theme/ui_tokens.gd")
const CARD_SIZE: Vector2 = Vector2(228, 330)
const TEXT_WIDTH: float = 196.0

var slot: int = 0
var gem_id: String = ""
var quality: int = 1
var selected: bool = false
var _panel: PanelContainer
var _style: StyleBoxFlat
var _color: Color = Color.WHITE
var _lift: float = 0.0


## hints: {dupes: int, recipes: [{special, have, total}], upgrade: special_id}
func setup(data: GameData, cand: Dictionary, next_wave_air: bool, hints: Dictionary = {}) -> void:
	slot = int(cand["slot"])
	gem_id = String(cand["gem"])
	quality = int(cand["quality"])
	_color = T.gem_color(gem_id)
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel = PanelContainer.new()
	_style = ThemeBuilder.box(T.SURFACE_HI, T.R_L, T.GLASS_BORDER, 1, T.SP_4, T.SP_3)
	_style.shadow_color = Color(0, 0, 0, 0.45)
	_style.shadow_size = 14
	_panel.add_theme_stylebox_override("panel", _style)
	_panel.material = Ui.glass_material()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.size = CARD_SIZE
	add_child(_panel)
	var col: VBoxContainer = Ui.vbox(T.SP_2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(col)

	var top: HBoxContainer = Ui.hbox()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key: PanelContainer = Ui.hotkey("select_%d" % (slot + 1))
	top.add_child(key)
	top.add_child(Ui.spacer())
	var ql: Dictionary = data.quality(quality)
	var qlabel: Label = Ui.label("%s · %s" % [String(ql["roman"]), tr(String(ql["key"]))], "CapsLabel")
	qlabel.add_theme_color_override("font_color", T.quality_color(quality))
	top.add_child(qlabel)
	col.add_child(top)

	var icon: GemIcon = GemIcon.new()
	icon.gem_id = gem_id
	icon.quality = quality
	icon.custom_minimum_size = Vector2(0, 68)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(icon)

	var g: Dictionary = data.gem(gem_id)
	var name_l: Label = Ui.label(tr(String(g["name_key"])), "SubheaderLabel")
	name_l.add_theme_color_override("font_color", _color.lightened(0.2))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_l)
	var role: Label = Ui.label(tr(String(g["role_key"])), "DimLabel", true)
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	col.add_child(role)

	var pips: HBoxContainer = Ui.hbox(4)
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i: int in data.quality_count():
		var dot: UiIcon = Ui.icon("gem", 10, T.quality_color(quality) if i < quality else Color(1, 1, 1, 0.12))
		pips.add_child(dot)
	col.add_child(pips)

	var t: TowerState = TowerState.new()
	t.setup(data, 0, Vector2i.ZERO, gem_id, quality, 0)
	var stats: GridContainer = GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", T.SP_3)
	stats.add_theme_constant_override("v_separation", 2)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat(stats, tr("STAT_DAMAGE"), T.format_number(t.damage))
	_stat(stats, tr("STAT_ATTACK_SPEED"), "%.2f/%s" % [t.attack_speed, tr("UNIT_SEC")])
	_stat(stats, tr("STAT_RANGE"), "%.2f" % t.attack_range)
	var dps: float = TowerState.estimate_dps(data, gem_id, quality, next_wave_air)
	_stat(stats, tr("STAT_DPS_NEXT"), T.format_number(dps) if dps > 0.0 else tr("STAT_NO_TARGETS"), dps <= 0.0)
	col.add_child(stats)

	# Чипы переносятся на вторую строку, если не влезают («Магия» + «Земля + воздух» шире колонки):
	# иначе карточка распирается и наезжает на соседнюю.
	var tags: HFlowContainer = HFlowContainer.new()
	tags.add_theme_constant_override("h_separation", 6)
	tags.add_theme_constant_override("v_separation", 4)
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tags.alignment = FlowContainer.ALIGNMENT_CENTER
	tags.add_child(_chip(tr("DMG_" + String(g["damage_type"]).to_upper()), T.dtype_color(String(g["damage_type"])), String(T.DTYPE_ICON.get(String(g["damage_type"]), ""))))
	var targets: String = String(g["targets"])
	tags.add_child(_chip(tr("TARGETS_" + targets.to_upper()), T.AIR if targets != "ground" else T.TEXT_DIM))
	col.add_child(tags)
	var dupes: int = int(hints.get("dupes", 1))
	if dupes >= 2:
		var dl: Label = Ui.label(tr("CARD_DUPES") % dupes, "FaintLabel", true)
		dl.add_theme_color_override("font_color", T.ACCENT)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dl.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
		col.add_child(dl)
	var shown: int = 0
	for r: Dictionary in hints.get("recipes", []):
		if shown >= 2:
			break
		var sp: Dictionary = data.special(String(r["special"]))
		var ready_now: bool = int(r["have"]) >= int(r["total"])
		var rl: Label = Ui.label((tr("CARD_RECIPE_READY") if ready_now else tr("CARD_RECIPE")) % [tr(String(sp["name_key"])), int(r["have"]), int(r["total"])], "FaintLabel")
		rl.add_theme_color_override("font_color", T.GOLD if ready_now else T.TEXT_DIM)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rl.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
		col.add_child(rl)
		shown += 1
	if not String(hints.get("upgrade", "")).is_empty():
		var ul: Label = Ui.label(tr("CARD_UPGRADE_FIT") % tr(String(data.special(String(hints["upgrade"]))["name_key"])), "FaintLabel")
		ul.add_theme_color_override("font_color", T.SUCCESS)
		ul.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ul.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
		col.add_child(ul)
	tooltip_text = tr("CARD_TOOLTIP")
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)
	resized.connect(func() -> void: _panel.size = Vector2(size.x, maxf(size.y, _panel.get_combined_minimum_size().y)))
	_refresh_style()


func _ready() -> void:
	var need: float = _panel.get_combined_minimum_size().y
	custom_minimum_size = Vector2(CARD_SIZE.x, maxf(CARD_SIZE.y, need))
	_panel.size = custom_minimum_size


func _stat(grid: GridContainer, name: String, value: String, warn: bool = false) -> void:
	var a: Label = Ui.label(name, "DimLabel")
	var b: Label = Ui.label(value, "NumberLabel")
	b.add_theme_font_size_override("font_size", T.FS_M)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if warn:
		b.add_theme_color_override("font_color", T.WARNING)
	grid.add_child(a)
	grid.add_child(b)


## Чип; icon_name — значок (у типов урона), чтобы различие не держалось только на цвете.
func _chip(text: String, color: Color, icon_name: String = "") -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.theme_type_variation = "ChipPanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row: HBoxContainer = Ui.hbox(3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not icon_name.is_empty():
		row.add_child(Ui.icon(icon_name, 11, color))
	var l: Label = Ui.label(text, "CapsLabel")
	l.add_theme_color_override("font_color", color)
	row.add_child(l)
	p.add_child(row)
	return p


func set_selected(v: bool) -> void:
	selected = v
	_refresh_style()
	_animate_lift(-14.0 if selected else (-6.0 if is_hovered_card() else 0.0))


func is_hovered_card() -> bool:
	return get_global_rect().has_point(get_global_mouse_position())


func _refresh_style() -> void:
	if _style == null:
		return
	_style.border_color = _color.lightened(0.2) if selected else T.GLASS_BORDER
	_style.set_border_width_all(2 if selected else 1)
	_style.shadow_color = Color(_color, 0.45) if selected else Color(0, 0, 0, 0.45)
	_style.shadow_size = 26 if selected else 14
	_style.bg_color = T.SURFACE_HI.lerp(_color.darkened(0.7), 0.35 if selected else 0.0)


func _animate_lift(target: float) -> void:
	var setter: Callable = func(v: float) -> void:
		_lift = v
		_panel.position.y = v
	var tw: Tween = create_tween()
	tw.tween_method(setter, _lift, target, T.dur(T.T_BASE)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_enter() -> void:
	Audio.play("sfx/ui/hover")
	hovered.emit(slot, true)
	if not selected:
		_animate_lift(-6.0)


func _on_exit() -> void:
	hovered.emit(slot, false)
	if not selected:
		_animate_lift(0.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if mb.double_click:
				activated.emit(slot)
			else:
				Audio.play("sfx/ui/click")
				chosen.emit(slot)
			accept_event()
