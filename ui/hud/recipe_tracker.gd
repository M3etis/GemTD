class_name RecipeTracker
extends PanelContainer
## Отслеживаемые рецепты (из Кодекса, до Settings.MAX_PINNED): по строке на рецепт — прогресс компонентов
## на поле и среди кандидатов раунда, у каждой своя кнопка «Не отслеживать».

const T := preload("res://ui/theme/ui_tokens.gd")

## Отступ трекера от низа окна и от панели, которую он не должен перекрывать (превью волны и журнал).
const BOTTOM_MARGIN: float = 16.0
const GAP: float = 12.0

## Панель над трекером (Hud.wave_panel): трекер растёт вверх только до неё, дальше список прокручивается.
var avoid: Control
var _title: Label
var _scroll: ScrollContainer
var _list: VBoxContainer


func _init() -> void:
	theme_type_variation = "GlassPanel"
	material = Ui.glass_material()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col: VBoxContainer = Ui.vbox(T.SP_2)
	add_child(col)
	_title = Ui.label(tr("TRACKER_TITLE"), "CapsLabel")
	col.add_child(_title)
	# До четырёх рецептов (Settings.MAX_PINNED) с подсказками замены выше места под превью волны:
	# список прокручивается, а не налезает на неё.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_list = Ui.vbox(T.SP_2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	visible = false


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	if avoid != null:
		avoid.resized.connect(_fit)
		avoid.visibility_changed.connect(_fit)


## Высота списка по содержимому, но не выше места между панелью avoid и низом окна.
func _fit() -> void:
	if not is_inside_tree():
		return
	var need: Vector2 = _list.get_combined_minimum_size()
	var top: float = 104.0
	if avoid != null and avoid.is_visible_in_tree():
		top = maxf(top, avoid.get_global_rect().end.y + GAP)
	var frame: float = get_theme_stylebox("panel").get_minimum_size().y if get_theme_stylebox("panel") != null else 0.0
	var room: float = maxf(120.0, get_viewport_rect().size.y - BOTTOM_MARGIN - top - frame - _title.get_combined_minimum_size().y - float(T.SP_2))
	# Список не влезает — появится вертикальная полоса прокрутки: ширину под неё добавляем, иначе она
	# закрыла бы правый край строк (кнопки «Не отслеживать»).
	var bar: float = _scroll.get_v_scroll_bar().get_combined_minimum_size().x + float(T.SP_1) if need.y > room else 0.0
	_scroll.custom_minimum_size = Vector2(need.x + bar, minf(need.y, room))
	# Привязан к правому нижнему углу: высота и ширина — от нижнего и правого края (и вниз, и вверх).
	var ms: Vector2 = get_combined_minimum_size()
	offset_top = offset_bottom - ms.y
	offset_left = offset_right - ms.x


## Возвращает метки компонентов для подсветки на поле: [{cell, color}] — цвет спец-башни рецепта.
func update_from(sim: GameSim) -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	var specials: Array[String] = []
	for id: String in Settings.pinned_recipes():
		if not sim.data.special(id).is_empty():
			specials.append(id)
	for c: Node in _list.get_children():
		c.queue_free()
	visible = not specials.is_empty()
	if specials.is_empty():
		return marks
	_title.text = tr("TRACKER_TITLE") if specials.size() == 1 else tr("TRACKER_TITLE_MANY")
	var swaps: Dictionary = RecipeBook.replacements(sim, specials)
	for i: int in specials.size():
		if i > 0:
			_list.add_child(HSeparator.new())
		marks.append_array(_entry(sim, specials[i], String(swaps.get(specials[i], ""))))
	_fit.call_deferred()
	return marks


## Строка рецепта: эмблема, имя, отметка «собран», компоненты с отметкой «оставлен» / «на поле», счётчик,
## кнопка открепления; если камней рецепта на поле нет — предложение заменить его (swap_to).
func _entry(sim: GameSim, special: String, swap_to: String) -> Array[Dictionary]:
	var sp: Dictionary = sim.data.special(special)
	var col: Color = Color.html(String(sp["color"]))
	var row: HBoxContainer = Ui.hbox(T.SP_2)
	var icon: GemIcon = GemIcon.new()
	icon.special_id = special
	icon.quality = 1
	icon.glow = false
	icon.custom_minimum_size = Vector2(32, 32)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var body: VBoxContainer = Ui.vbox(4)
	var head: HBoxContainer = Ui.hbox(T.SP_2)
	var name_l: Label = Ui.label(tr(String(sp["name_key"])), "BodyLabel")
	name_l.add_theme_color_override("font_color", col.lightened(0.2))
	head.add_child(name_l)
	var built: Array[TowerState] = RecipeBook.built(sim, special)
	if not built.is_empty():
		head.add_child(_built_badge(sim, built))
	head.add_child(Ui.spacer())
	var unpin: Button = Ui.icon_button("close", 10, "GhostButton", Vector2(24, 24))
	unpin.tooltip_text = tr("TRACKER_UNPIN")
	unpin.pressed.connect(func() -> void: Settings.set_recipe_pinned(special, false))
	head.add_child(unpin)
	body.add_child(head)
	var chips: HBoxContainer = Ui.hbox(T.SP_2)
	var prog: Dictionary = RecipeBook.progress(sim, special, true)
	for part: Dictionary in prog["parts"]:
		var chip: PanelContainer = PanelContainer.new()
		chip.theme_type_variation = "ChipPanel"
		var h: HBoxContainer = Ui.hbox(4)
		var gi: GemIcon = GemIcon.new()
		gi.gem_id = String(part["gem"])
		gi.quality = int(part["quality"])
		gi.glow = false
		gi.custom_minimum_size = Vector2(20, 20)
		h.add_child(gi)
		h.add_child(Ui.label(String(sim.data.quality(int(part["quality"]))["roman"]), "CapsLabel"))
		# Галочка — компонент уже оставлен (башня); зелёная точка — он лежит на поле среди кандидатов
		# раунда, но ещё не выбран; серая — его нет.
		var kept: bool = bool(part["owned"]) and not bool(part["candidate"])
		var on_board: bool = bool(part["candidate"])
		h.add_child(Ui.icon("check" if kept else "dot", 12, T.SUCCESS if kept or on_board else T.TEXT_FAINT))
		chip.add_child(h)
		var gem_name: String = tr(String(sim.data.gem(String(part["gem"]))["name_key"]))
		chip.tooltip_text = gem_name + ("\n" + tr("TRACKER_ON_BOARD") if on_board else "")
		chips.add_child(chip)
	body.add_child(chips)
	body.add_child(Ui.label(tr("TRACKER_PROGRESS") % [int(prog["kept"]), int(prog["total"])], "FaintLabel"))
	if not swap_to.is_empty():
		body.add_child(_swap_hint(sim, special, swap_to))
	row.add_child(body)
	_list.add_child(row)
	var marks: Array[Dictionary] = []
	for t: TowerState in sim.towers:
		if not t.is_special() and _is_part(prog["parts"], t.gem_id, t.quality):
			marks.append({"cell": t.cell, "color": col})
	for cand: Dictionary in sim.candidates:
		if _is_part(prog["parts"], String(cand["gem"]), int(cand["quality"])):
			marks.append({"cell": cand["cell"], "color": col})
	return marks


## Отметка «собран»: сколько таких спец-башен на поле; подсказка — можно ли их слить.
func _built_badge(sim: GameSim, built: Array[TowerState]) -> Control:
	var box: HBoxContainer = Ui.hbox(4)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(Ui.icon("check", 12, T.SUCCESS))
	var merged: bool = built.size() == 1 and built[0].is_merged()
	var text: String = tr("TRACKER_BUILT") if built.size() == 1 else tr("TRACKER_BUILT_N") % built.size()
	if merged:
		text = tr("TRACKER_MERGED")
	var l: Label = Ui.label(text, "CapsLabel")
	l.add_theme_color_override("font_color", T.GOLD if merged else T.SUCCESS)
	box.add_child(l)
	var mult: String = String.num(BuildCommands.merge_inherit(sim.data))
	var can_merge: bool = false
	for t: TowerState in built:
		can_merge = can_merge or BuildCommands.merge_partner(sim, t) != null
	if merged:
		box.tooltip_text = tr("TRACKER_MERGED_TIP") % mult
	elif can_merge:
		box.tooltip_text = tr("TRACKER_BUILT_MERGE_TIP") % mult
	else:
		box.tooltip_text = tr("TRACKER_BUILT_TIP") % mult
	return box


## Камней рецепта на поле нет: кнопка «отслеживать вместо него» рецепт, компоненты которого уже есть.
func _swap_hint(sim: GameSim, special: String, other: String) -> Control:
	var box: VBoxContainer = Ui.vbox(4)
	var note: Label = Ui.label(tr("TRACKER_NONE_ON_BOARD"), "FaintLabel", true)
	note.custom_minimum_size = Vector2(220, 0)
	note.add_theme_color_override("font_color", T.WARNING)
	box.add_child(note)
	var prog: Dictionary = RecipeBook.progress(sim, other, true)
	var b: Button = Ui.button(tr("TRACKER_SWAP") % [tr(String(sim.data.special(other)["name_key"])), int(prog["have"]), int(prog["total"])], "GhostButton", "", "target")
	b.tooltip_text = tr("TRACKER_SWAP_TIP")
	b.pressed.connect(func() -> void: Settings.replace_pinned_recipe(special, other))
	box.add_child(b)
	return box


static func _is_part(parts: Array, gem: String, quality: int) -> bool:
	for p: Dictionary in parts:
		if String(p["gem"]) == gem and int(p["quality"]) == quality:
			return true
	return false
