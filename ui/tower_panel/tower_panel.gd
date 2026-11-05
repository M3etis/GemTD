class_name TowerPanel
extends PanelContainer
## Панель выбранной башни или стены: статы, MVP, эффекты спец-башни, приоритет цели,
## улучшение, огранка, перенос, сплав, продажа; для стены — разрушение. Если под башней или стеной
## лежит слейт — кнопка, открывающая его панель.

signal closed
## target:<mode>, toggle, upgrade, polish, tower_move, open_slate, sell, forge:<special>, break, slate_move
signal action_pressed(id: String)

const T := preload("res://ui/theme/ui_tokens.gd")
## Верхняя граница панели — под верхней панелью HUD (как у превью волны), и отступ снизу.
const TOP_LIMIT: float = 104.0
const BOTTOM_MARGIN: float = 16.0

var tower_id: int = -1
var wall_cell: Vector2i = Vector2i(-1, -1)
## Только просмотр (реплей): все кнопки действий выключены — команды в реплее не применяются.
var read_only: bool = false
var _close_btn: Button
var _scroll: ScrollContainer
var _body: VBoxContainer
var _grid: GridContainer
var _buttons: Dictionary = {}


func _init() -> void:
	theme_type_variation = "GlassPanel"
	material = Ui.glass_material()
	custom_minimum_size = Vector2(320, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Длинное описание спец-башни (три уровня, эффекты, кнопки) выше окна: панель растёт вверх от низа
	# экрана и уезжала за верхний край. Теперь высота ограничена, остальное прокручивается.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_body = Ui.vbox(T.SP_2)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)


## Высота по содержимому, но не выше места между верхней панелью HUD и низом окна.
func _fit() -> void:
	if not is_inside_tree():
		return
	var need: Vector2 = _body.get_combined_minimum_size()
	var frame: float = get_theme_stylebox("panel").get_minimum_size().y if get_theme_stylebox("panel") != null else 0.0
	var room: float = maxf(160.0, get_viewport_rect().size.y - TOP_LIMIT - BOTTOM_MARGIN - frame)
	_scroll.custom_minimum_size = Vector2(need.x, minf(need.y, room))


func _clear() -> void:
	for c: Node in _body.get_children():
		c.queue_free()
	_buttons.clear()
	_grid = null


func _header(icon: Control, title: String, title_color: Color, sub: String, sub_color: Color) -> void:
	var head: HBoxContainer = Ui.hbox(T.SP_3)
	head.add_child(icon)
	var names: VBoxContainer = Ui.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n: Label = Ui.label(title, "SubheaderLabel")
	n.add_theme_color_override("font_color", title_color)
	names.add_child(n)
	var q: Label = Ui.label(sub, "CapsLabel")
	q.add_theme_color_override("font_color", sub_color)
	names.add_child(q)
	head.add_child(names)
	var close: Button = Ui.icon_button("close", 12, "GhostButton", Vector2(28, 28))
	_close_btn = close
	close.tooltip_text = tr("ACT_CLOSE") + " (Esc)"
	close.pressed.connect(func() -> void: closed.emit())
	head.add_child(close)
	_body.add_child(head)


func _btn(id: String, text: String, variation: String, icon_name: String, action: String = "", tip: String = "") -> Button:
	var b: Button = Ui.button(text, variation, action, icon_name)
	b.tooltip_text = tip
	b.pressed.connect(func() -> void: action_pressed.emit(id))
	_buttons[id] = b
	return b


func show_tower(sim: GameSim, t: TowerState) -> void:
	_clear()
	tower_id = t.id
	wall_cell = Vector2i(-1, -1)
	var data: GameData = sim.data
	var icon: GemIcon = GemIcon.new()
	icon.custom_minimum_size = Vector2(56, 56)
	var role: String
	if t.is_special():
		var sp: Dictionary = data.special(t.special_id)
		icon.special_id = t.special_id
		icon.quality = t.level
		var sub: String = tr("TP_LEVEL") % [t.level, 3]
		if t.is_merged():
			sub += " · " + tr("TP_MERGED") % [String.num(t.merge_inherit), t.merge_level]
		_header(icon, tr(String(sp["name_key"])), Color.html(String(sp["color"])).lightened(0.2), sub, T.GOLD)
		role = tr(String(sp["role_key"]))
	else:
		icon.gem_id = t.gem_id
		icon.quality = t.quality
		var g: Dictionary = data.gem(t.gem_id)
		var ql: Dictionary = data.quality(t.quality)
		_header(icon, tr(String(g["name_key"])), T.gem_color(t.gem_id).lightened(0.2), "%s · %s" % [String(ql["roman"]), tr(String(ql["key"]))], T.quality_color(t.quality))
		role = tr(String(g["role_key"]))
	var role_l: Label = Ui.label(role, "DimLabel", true)
	role_l.custom_minimum_size = Vector2(288, 0)
	_body.add_child(role_l)
	if t.mvp > 0:
		var mvp: Label = Ui.label(tr("TP_MVP") % [t.mvp, int(roundf(float(t.mvp) * t.mvp_damage_per_stack * 100.0))], "CapsLabel")
		mvp.add_theme_color_override("font_color", T.GOLD)
		_body.add_child(mvp)
	if t.is_special():
		for line: String in SpecialText.describe(data, t.special_id, t.level):
			var fl: Label = Ui.label("• " + line, "BodyLabel", true)
			fl.custom_minimum_size = Vector2(288, 0)
			fl.add_theme_font_size_override("font_size", T.FS_S)
			_body.add_child(fl)
		if t.is_merged():
			var ml: Label = Ui.label("• " + tr("TP_MERGED_NOTE") % [String.num(t.merge_inherit), t.merge_level], "BodyLabel", true)
			ml.custom_minimum_size = Vector2(288, 0)
			ml.add_theme_font_size_override("font_size", T.FS_S)
			ml.add_theme_color_override("font_color", T.GOLD)
			_body.add_child(ml)
	_body.add_child(HSeparator.new())
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", T.SP_4)
	_body.add_child(_grid)
	refresh(t)
	if t.attack_kind == "projectile" or t.attack_kind == "lightning":
		_body.add_child(Ui.label(tr("TP_TARGETING"), "CapsLabel"))
		var chips: HBoxContainer = Ui.hbox(4)
		var group: ButtonGroup = ButtonGroup.new()
		for mode: String in TowerState.TARGETING_MODES:
			var b: Button = Button.new()
			b.theme_type_variation = "ChipButton"
			b.text = tr("TARGET_" + mode.to_upper())
			b.toggle_mode = true
			b.button_group = group
			b.button_pressed = t.targeting == mode
			b.tooltip_text = tr("TARGET_TIP_" + mode.to_upper())
			Ui.attach_feedback(b)
			b.pressed.connect(func() -> void: action_pressed.emit("target:" + mode))
			chips.add_child(b)
		_body.add_child(chips)
		var stop: CheckButton = CheckButton.new()
		stop.text = tr("TP_ENABLED")
		stop.button_pressed = t.enabled
		stop.tooltip_text = tr("TP_ENABLED_TIP")
		stop.toggled.connect(func(_v: bool) -> void: action_pressed.emit("toggle"))
		_body.add_child(stop)
	var build: bool = sim.is_build_phase()
	if t.is_special() and t.level < 3:
		_body.add_child(HSeparator.new())
		_body.add_child(Ui.label(tr("TP_NEXT_LEVEL") % (t.level + 1), "CapsLabel"))
		for line2: String in SpecialText.describe(data, t.special_id, t.level + 1):
			var nl: Label = Ui.label("• " + line2, "DimLabel", true)
			nl.custom_minimum_size = Vector2(288, 0)
			_body.add_child(nl)
		var up: Dictionary = BuildCommands.next_upgrade(sim, t)
		var req: Label = Ui.label(tr("TP_REQUIRES") % SpecialText.upgrade_text(data, t.special_id, t.level + 1), "FaintLabel", true)
		req.custom_minimum_size = Vector2(288, 0)
		_body.add_child(req)
		if String(up.get("gem", "")).is_empty():
			var ub: Button = _btn("upgrade", tr("ACT_UPGRADE") % int(up["gold"]), "PrimaryButton", "arrow_up")
			ub.disabled = not build or sim.gold < int(up["gold"])
			ub.tooltip_text = tr("TP_BUILD_ONLY") if not build else (tr("ERR_NOT_ENOUGH_GOLD") if sim.gold < int(up["gold"]) else "")
			_body.add_child(ub)
	var partner: TowerState = BuildCommands.merge_partner(sim, t)
	if partner != null:
		var mult: String = String.num(BuildCommands.merge_inherit(data))
		_body.add_child(HSeparator.new())
		var mb: Button = _btn("merge:%d:%d" % [partner.cell.x, partner.cell.y], tr("ACT_MERGE") % mult, "PrimaryButton", "arrow_up")
		mb.disabled = not build
		mb.tooltip_text = tr("TP_MERGE_TIP") % [partner.level, mult] if build else tr("TP_BUILD_ONLY")
		_body.add_child(mb)
	# Сплав — в любой момент матча (и в бою), кроме Испытания урона (как BuildCommands.forge).
	if not t.is_special() and not sim.is_over() and not sim.damage_test:
		for o: Dictionary in RecipeBook.available_at(sim, t.cell):
			var sp2: String = String(o["special"])
			_body.add_child(_btn("forge:" + sp2, tr("ACT_FORGE_NAMED") % tr(String(data.special(sp2)["name_key"])), "PrimaryButton", "sparkle", "forge"))
	_polish_section(sim, t, build)
	var move_cost: int = BuildCommands.tower_move_cost(sim)
	var mv: Button = _btn("tower_move", tr("ACT_MOVE_TOWER") % move_cost, "Button", "path")
	mv.disabled = not build or sim.gold < move_cost
	mv.tooltip_text = tr("TP_BUILD_ONLY") if not build else (tr("ACT_MOVE_TOWER_TIP") if sim.gold >= move_cost else tr("ERR_NOT_ENOUGH_GOLD"))
	_body.add_child(mv)
	_slate_link(sim, t.cell)
	var sell: Button = _btn("sell", tr("ACT_SELL") % t.sell_value(data), "GhostButton", "coin")
	sell.disabled = not build
	sell.tooltip_text = tr("TP_SELL_TIP") if build else tr("TP_BUILD_ONLY")
	_body.add_child(sell)
	_lock_if_read_only()
	_fit()
	_fit.call_deferred()


## Огранка: уровень и прибавка урона, кнопка следующего уровня с ценой (растёт с каждым уровнем).
func _polish_section(sim: GameSim, t: TowerState, build: bool) -> void:
	var cfg: Dictionary = sim.data.economy["polish"]
	var per: int = int(roundf(float(cfg["damage_per_level"]) * 100.0))
	_body.add_child(HSeparator.new())
	if not t.deals_damage():
		var no: Label = Ui.label(tr("TP_POLISH_NO_DAMAGE"), "FaintLabel", true)
		no.custom_minimum_size = Vector2(288, 0)
		_body.add_child(no)
		return
	var head: HBoxContainer = Ui.hbox(T.SP_2)
	head.add_child(Ui.icon("gem", 14, T.ACCENT))
	var title: Label = Ui.label(tr("TP_POLISH") % [t.polish, int(cfg["max_level"])], "CapsLabel")
	title.tooltip_text = tr("TP_POLISH_TIP") % per
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	head.add_child(title)
	head.add_child(Ui.spacer())
	if t.polish > 0:
		var bonus: Label = Ui.label("+%d%%" % (t.polish * per), "NumberLabel")
		bonus.add_theme_color_override("font_color", T.ACCENT)
		head.add_child(bonus)
	_body.add_child(head)
	var cost: int = BuildCommands.polish_cost(sim, t)
	if cost < 0:
		_body.add_child(Ui.label(tr("TP_POLISH_MAX"), "FaintLabel"))
		return
	var b: Button = _btn("polish", tr("ACT_POLISH") % [per, cost], "Button", "sparkle")
	b.disabled = not build or sim.gold < cost
	b.tooltip_text = tr("TP_BUILD_ONLY") if not build else (tr("TP_POLISH_TIP") % per if sim.gold >= cost else tr("ERR_NOT_ENOUGH_GOLD"))
	_body.add_child(b)


## Слейт под башней или стеной: клик по клетке выбирает их, а слейт открывается этой кнопкой.
func _slate_link(sim: GameSim, cell: Vector2i) -> void:
	var under: TowerState = sim.slate_by_cell.get(cell) as TowerState
	if under == null:
		return
	var sl: Dictionary = sim.data.slate(under.slate_id)
	var b: Button = _btn("open_slate", tr("TP_SLATE_UNDER") % tr(String(sl["name_key"])), "GhostButton", "gem")
	b.tooltip_text = tr("TP_SLATE_UNDER_TIP")
	_body.add_child(b)


## Реплей: кнопки панели (кроме закрытия) выключены, иначе «Перенести» включал бы режим переноса,
## который в реплее не завершить, а «Огранить» и «Продать» молча ничего не делали бы.
func _lock_if_read_only() -> void:
	if not read_only:
		return
	for n: Node in _body.find_children("*", "BaseButton", true, false):
		var b: BaseButton = n as BaseButton
		# Закрыть и открыть слейт под башней — просмотр, а не команда: остаются.
		if b != _close_btn and b != _buttons.get("open_slate"):
			b.disabled = true
			b.tooltip_text = tr("TP_REPLAY_READ_ONLY")


func refresh(t: TowerState) -> void:
	if _grid == null:
		return
	for c: Node in _grid.get_children():
		c.queue_free()
	if t.is_slate():
		_slate_rows(t)
		return
	match t.attack_kind:
		"none":
			pass
		"aura_slow":
			pass
		_:
			_row(tr("STAT_DAMAGE"), T.format_number(t.effective_damage()) + (" (+%d%%)" % int(roundf((t.damage_mult() - 1.0) * 100.0)) if t.damage_mult() > 1.001 else ""))
			var aps: String = "%.2f" % t.effective_attack_speed()
			if t.aura_speed_bonus > 0.0:
				aps += " (+%d%%)" % int(roundf(t.aura_speed_bonus * 100.0))
			_row(tr("STAT_ATTACK_SPEED"), aps)
			_row(tr("STAT_DAMAGE_TYPE"), tr("DMG_" + t.damage_type.to_upper()))
	var rng: String = "%.2f" % t.attack_range
	if t.aura_range_bonus > 0.0:
		rng += " (+%.1f)" % t.aura_range_bonus
	_row(tr("STAT_RANGE"), rng)
	if t.attack_kind != "none":
		_row(tr("STAT_TARGETS"), tr("TARGETS_" + ("BOTH" if t.hits_air and t.hits_ground else ("GROUND" if t.hits_ground else "AIR"))))
		_row(tr("STAT_WAVE_DAMAGE"), T.format_number(t.wave_damage))
		_row(tr("STAT_TOTAL_DAMAGE"), T.format_number(t.total_damage))
		_row(tr("STAT_KILLS"), str(t.kills))


## Слейт: эффекты из slates.json, рецепт, кнопки «Переложить (1 раз)», «Объединить в …», «Продать».
func show_slate(sim: GameSim, s: TowerState) -> void:
	_clear()
	tower_id = s.id
	wall_cell = Vector2i(-1, -1)
	var data: GameData = sim.data
	var sl: Dictionary = data.slate(s.slate_id)
	var col: Color = Color.html(String(sl["color"]))
	var icon: GemIcon = GemIcon.new()
	icon.slate_id = s.slate_id
	icon.custom_minimum_size = Vector2(56, 56)
	_header(icon, tr(String(sl["name_key"])), col.lightened(0.2), tr("SLATE_COMBO" if String(sl["kind"]) == "combo" else "SLATE_BASE"), T.GOLD)
	var role: Label = Ui.label(tr(String(sl["role_key"])), "DimLabel", true)
	role.custom_minimum_size = Vector2(288, 0)
	_body.add_child(role)
	for line: String in SlateText.describe(data, s.slate_id):
		var fl: Label = Ui.label("• " + line, "BodyLabel", true)
		fl.custom_minimum_size = Vector2(288, 0)
		fl.add_theme_font_size_override("font_size", T.FS_S)
		_body.add_child(fl)
	var rec: Label = Ui.label(tr("SLATE_RECIPE") % SlateText.recipe_text(data, s.slate_id), "FaintLabel", true)
	rec.custom_minimum_size = Vector2(288, 0)
	_body.add_child(rec)
	var info: Label = Ui.label(tr("SLATE_INFO"), "FaintLabel", true)
	info.custom_minimum_size = Vector2(288, 0)
	_body.add_child(info)
	_body.add_child(HSeparator.new())
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", T.SP_4)
	_body.add_child(_grid)
	refresh(s)
	var build: bool = sim.is_build_phase()
	var partner: TowerState = SlateBook.combine_partner(sim, s)
	if partner != null:
		var combo: String = SlateBook.combo_of(data, s.slate_id, partner.slate_id)
		var cb: Button = _btn("slate_combine:%d:%d" % [partner.cell.x, partner.cell.y], tr("ACT_COMBINE_SLATES") % tr(String(data.slate(combo)["name_key"])), "PrimaryButton", "sparkle")
		cb.disabled = not build
		cb.tooltip_text = tr("ACT_COMBINE_SLATES_TIP") if build else tr("TP_BUILD_ONLY")
		_body.add_child(cb)
	var move_cost: int = SlateCommands.move_cost(sim)
	var mv: Button = _btn("slate_move", tr("ACT_MOVE_SLATE") % move_cost, "Button", "path")
	mv.disabled = not build or sim.gold < move_cost
	mv.tooltip_text = tr("TP_BUILD_ONLY") if not build else (tr("ACT_MOVE_SLATE_TIP") if sim.gold >= move_cost else tr("ERR_NOT_ENOUGH_GOLD"))
	_body.add_child(mv)
	var sell: Button = _btn("sell", tr("ACT_SELL") % s.sell_value(data), "GhostButton", "coin")
	sell.disabled = not build
	sell.tooltip_text = tr("TP_SELL_TIP") if build else tr("TP_BUILD_ONLY")
	_body.add_child(sell)
	_lock_if_read_only()
	_fit()
	_fit.call_deferred()


func _slate_rows(s: TowerState) -> void:
	var sl: Dictionary = GameData.load_default().slate(s.slate_id)
	_row(tr("STAT_RADIUS"), "%.1f" % float(sl["radius"]))
	_row(tr("STAT_INTERVAL"), "%.1f" % float(sl["interval"]))
	_row(tr("STAT_TARGETS"), tr("TARGETS_" + String(sl["targets"]).to_upper()))
	_row(tr("STAT_TOTAL_DAMAGE"), T.format_number(s.total_damage))
	_row(tr("STAT_KILLS"), str(s.kills))


func show_wall(sim: GameSim, cell: Vector2i) -> void:
	_clear()
	tower_id = -1
	wall_cell = cell
	var icon: UiIcon = Ui.icon("shield", 40, T.TEXT_DIM)
	_header(icon, tr("WALL_TITLE"), T.TEXT, tr("WALL_SUB"), T.TEXT_DIM)
	var info: Label = Ui.label(tr("WALL_INFO"), "DimLabel", true)
	info.custom_minimum_size = Vector2(288, 0)
	_body.add_child(info)
	var res: Dictionary = _path_without(sim, cell)
	if res["ok"]:
		var delta: float = float(res["length"]) - sim.route.ground_length
		var dl: Label = Ui.label(tr("WALL_PATH_DELTA") % int(roundf(delta)), "BodyLabel")
		dl.add_theme_color_override("font_color", T.WARNING if delta < -0.5 else T.TEXT_DIM)
		_body.add_child(dl)
	var cost: int = BuildCommands.break_wall_cost(sim)
	var b: Button = _btn("break", tr("ACT_BREAK_WALL") % cost, "DangerButton", "close", "break_wall")
	var build: bool = sim.is_build_phase()
	b.disabled = not build or sim.gold < cost
	b.tooltip_text = tr("TP_BUILD_ONLY") if not build else (tr("ERR_NOT_ENOUGH_GOLD") if sim.gold < cost else "")
	_body.add_child(b)
	_slate_link(sim, cell)
	_lock_if_read_only()
	_fit()
	_fit.call_deferred()


func _path_without(sim: GameSim, cell: Vector2i) -> Dictionary:
	sim.grid.astar.set_point_solid(cell, false)
	var res: Dictionary = sim.route.compute()
	sim.grid.astar.set_point_solid(cell, true)
	if not res["ok"]:
		return {"ok": false}
	return {"ok": true, "length": RoutePlanner.path_length(RoutePlanner.cells_to_points(res["cells"]))}


func _row(a: String, b: String) -> void:
	_grid.add_child(Ui.label(a, "DimLabel"))
	var v: Label = Ui.label(b, "NumberLabel")
	v.add_theme_font_size_override("font_size", T.FS_M)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_grid.add_child(v)
