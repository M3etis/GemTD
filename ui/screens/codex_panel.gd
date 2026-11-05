class_name CodexPanel
extends Modal
## Кодекс: спец-башни (рецепты, уровни, закрепление), слейты, гемы по качествам, враги, трейты и справка
## (правила раунда, волны и длина забега, золото, огранка и переносы, «Гонка», управление — числа из данных).

var _sim: GameSim
var _data: GameData


func _init() -> void:
	super._init()


func setup(sim: GameSim) -> CodexPanel:
	_sim = sim
	_data = GameData.load_default()
	header(tr("CODEX_TITLE"), "info")
	var tabs: TabContainer = TabContainer.new()
	tabs.custom_minimum_size = Vector2(980, 560)
	tabs.tab_changed.connect(func(_i: int) -> void: Audio.play("sfx/ui/tab_switch"))
	body.add_child(tabs)
	tabs.add_child(_scroll(tr("CODEX_TAB_SPECIALS"), _specials()))
	tabs.add_child(_scroll(tr("CODEX_TAB_SLATES"), _slates()))
	tabs.add_child(_scroll(tr("CODEX_TAB_GEMS"), _gems()))
	tabs.add_child(_scroll(tr("CODEX_TAB_ENEMIES"), _enemies()))
	tabs.add_child(_scroll(tr("CODEX_TAB_TRAITS"), _traits()))
	# Справка — последней: номера вкладок выше используют скриншоты (codextraits, codexenemies).
	tabs.add_child(_scroll(tr("CODEX_TAB_HELP"), _help()))
	return self


func _scroll(title: String, content: Control) -> ScrollContainer:
	var s: ScrollContainer = ScrollContainer.new()
	s.name = title
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var m: MarginContainer = Ui.margin(T.SP_3)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(content)
	s.add_child(m)
	return s


## Справка: правила, которых нет в остальных вкладках. Цены и множители — из economy.json и waves.json,
## клавиши — текущая раскладка (Settings), поэтому текст не расходится с игрой после правок баланса.
func _help() -> Control:
	var col: VBoxContainer = Ui.vbox(T.SP_3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var eco: Dictionary = _data.economy
	_help_section(col, "HELP_ROUND_TITLE", [tr("HELP_ROUND") % [_keys(["select_1", "select_5"], "–"), _keys(["combine"]), _keys(["forge"])]])
	var lengths: PackedStringArray = PackedStringArray()
	for n: int in _data.run_lengths():
		lengths.append("• " + NewGamePanel.length_tip(_data, n))
	var bosses: PackedStringArray = PackedStringArray()
	for b: Variant in _data.waves_cfg["boss_waves"]:
		bosses.append(str(int(b)))
	var waves: Array = [tr("HELP_WAVES") % [int(_data.waves_cfg["air_every"]), ", ".join(bosses)], "\n".join(lengths)]
	if _sim != null:
		waves.append(tr("HELP_CURRENT_ENDLESS") if _sim.endless else tr("HELP_CURRENT_RUN") % _sim.total_waves)
	_help_section(col, "HELP_WAVES_TITLE", waves)
	var pol: Dictionary = eco["polish"]
	var total: float = 0.0
	for i: int in int(pol["max_level"]):
		total += roundf(float(pol["base_cost"]) * pow(float(pol["growth"]), float(i)))
	_help_section(col, "HELP_GOLD_TITLE", [
		tr("HELP_GOLD") % [_keys(["upgrade_luck"]), _data.luck_roman(_data.max_luck()), int(eco["buy_life"]["base"]), int(eco["buy_life"]["step"]),
			_keys(["break_wall"]), int(eco["break_wall"]["base"]), int(eco["break_wall"]["step"]), roundi(float(eco["sell_refund"]) * 100.0)],
		tr("HELP_POLISH") % [roundi(float(pol["damage_per_level"]) * 100.0), int(pol["max_level"]), int(pol["base_cost"]), String.num(float(pol["growth"])),
			T.format_number(total)],
		tr("HELP_MOVE") % [int(eco["tower_move"]["base"]), int(eco["tower_move"]["step"]), int(eco["slate_move"]["base"]), int(eco["slate_move"]["step"])],
	])
	var endless: Dictionary = _data.waves_cfg["endless"]
	_help_section(col, "HELP_RACE_TITLE", [tr("HELP_RACE") % [_data.wave_count(), roundi(float(endless["count_growth"]) * 100.0),
		String.num(float(endless["armor_growth"])), roundi(float(endless["speed_growth"]) * 100.0), roundi(float(endless["speed_cap"]) * 100.0)]])
	_help_section(col, "HELP_CONTROLS_TITLE", [tr("HELP_CONTROLS_FIXED")])
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", T.SP_4)
	grid.add_theme_constant_override("v_separation", 4)
	for spec: Array in [[["confirm"], "HELP_KEY_START"], [["select_1", "select_5"], "HELP_KEY_SELECT"], [["combine"], "KEY_ACT_COMBINE"],
			[["forge"], "KEY_ACT_FORGE"], [["break_wall"], "KEY_ACT_BREAK_WALL"], [["upgrade_luck"], "KEY_ACT_UPGRADE_LUCK"],
			[["speed_down", "speed_up"], "HELP_KEY_SPEED"], [["pause"], "KEY_ACT_PAUSE"], [["forecast"], "KEY_ACT_FORECAST"],
			[["codex"], "KEY_ACT_CODEX"], [["show_ranges"], "KEY_ACT_SHOW_RANGES"], [["show_hp"], "KEY_ACT_SHOW_HP"],
			[["chat"], "KEY_ACT_CHAT"], [["camera_reset"], "KEY_ACT_CAMERA_RESET"], [["restart"], "KEY_ACT_RESTART"], [["menu"], "KEY_ACT_MENU"]]:
		var key: PanelContainer = PanelContainer.new()
		key.theme_type_variation = "ChipPanel"
		key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		key.add_child(Ui.label(_keys(spec[0], " / " if spec[0].size() == 2 and String(spec[0][0]).begins_with("speed") else "–"), "CapsLabel"))
		grid.add_child(key)
		var l: Label = Ui.label(tr(String(spec[1])), "BodyLabel")
		l.custom_minimum_size = Vector2(330, 0)
		grid.add_child(l)
	col.add_child(grid)
	return col


func _help_section(col: VBoxContainer, title_key: String, paragraphs: Array) -> void:
	var t: Label = Ui.label(tr(title_key), "SubheaderLabel")
	t.add_theme_color_override("font_color", T.ACCENT)
	col.add_child(t)
	for p: Variant in paragraphs:
		var l: Label = Ui.label(String(p), "BodyLabel", true)
		l.custom_minimum_size = Vector2(900, 0)
		col.add_child(l)


## Клавиши действий в текущей раскладке: «1–5», «Z / X», «C».
static func _keys(actions: Array, sep: String = " / ") -> String:
	var out: PackedStringArray = PackedStringArray()
	for a: Variant in actions:
		var k: String = Settings.key_label(String(a))
		if not k.is_empty():
			out.append(k)
	return sep.join(out)


func _specials() -> Control:
	var col: VBoxContainer = Ui.vbox(T.SP_3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var intro: Label = Ui.label(tr("CODEX_SPECIALS_INTRO") % String.num(BuildCommands.merge_inherit(_data)), "DimLabel", true)
	intro.custom_minimum_size = Vector2(900, 0)
	col.add_child(intro)
	var pinned: Array[String] = Settings.pinned_recipes()
	var pins: Dictionary = {}
	for sp: Dictionary in _data.specials:
		var id: String = String(sp["id"])
		var card: PanelContainer = PanelContainer.new()
		card.theme_type_variation = "CardPanel"
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row: HBoxContainer = Ui.hbox(T.SP_4)
		var icon: GemIcon = GemIcon.new()
		icon.special_id = id
		icon.quality = 3
		icon.custom_minimum_size = Vector2(72, 72)
		row.add_child(icon)
		var v: VBoxContainer = Ui.vbox(4)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_row: HBoxContainer = Ui.hbox(T.SP_2)
		var nl: Label = Ui.label(tr(String(sp["name_key"])), "SubheaderLabel")
		nl.add_theme_color_override("font_color", Color.html(String(sp["color"])).lightened(0.2))
		name_row.add_child(nl)
		name_row.add_child(Ui.label(tr(String(sp["role_key"])), "DimLabel"))
		var built: Array[TowerState] = RecipeBook.built(_sim, id) if _sim != null else ([] as Array[TowerState])
		if not built.is_empty():
			# Как в трекере: рецепт уже собран в этом забеге (сколько таких спец-башен на поле).
			name_row.add_child(Ui.icon("check", 14, T.SUCCESS))
			var bl: Label = Ui.label(tr("TRACKER_BUILT") if built.size() == 1 else tr("TRACKER_BUILT_N") % built.size(), "CapsLabel")
			bl.add_theme_color_override("font_color", T.SUCCESS)
			name_row.add_child(bl)
		name_row.add_child(Ui.spacer())
		var pin: Button = Button.new()
		pin.theme_type_variation = "ChipButton"
		pin.toggle_mode = true
		pin.button_pressed = pinned.has(id)
		pin.text = tr("CODEX_PIN")
		pin.tooltip_text = tr("CODEX_PIN_TIP")
		Ui.attach_feedback(pin)
		pins[id] = pin
		# Отслеживать можно несколько рецептов; сверх Settings.MAX_PINNED снимается самый старый.
		pin.toggled.connect(func(on: bool) -> void:
			var dropped: String = Settings.set_recipe_pinned(id, on)
			if not dropped.is_empty():
				(pins[dropped] as Button).set_pressed_no_signal(false)
				Events.toast_requested.emit(tr("TOAST_PIN_LIMIT") % [Settings.MAX_PINNED, tr(String(_data.special(dropped)["name_key"]))], "info")
			else:
				Events.toast_requested.emit(tr("TOAST_PINNED") % tr(String(sp["name_key"])) if on else tr("TOAST_UNPINNED"), "info"))
		name_row.add_child(pin)
		v.add_child(name_row)
		var rec: HBoxContainer = Ui.hbox(T.SP_2)
		rec.add_child(Ui.label(tr("CODEX_RECIPE"), "CapsLabel"))
		var prog: Dictionary = RecipeBook.progress(_sim, id, true) if _sim != null else {}
		var parts: Array = prog.get("parts", [])
		var recipe: Array = sp["recipe"]
		for i: int in recipe.size():
			var comp: Dictionary = recipe[i]
			var chip: PanelContainer = PanelContainer.new()
			chip.theme_type_variation = "ChipPanel"
			var h: HBoxContainer = Ui.hbox(4)
			var gi: GemIcon = GemIcon.new()
			gi.gem_id = String(comp["gem"])
			gi.quality = int(comp["quality"])
			gi.glow = false
			gi.custom_minimum_size = Vector2(20, 20)
			h.add_child(gi)
			h.add_child(Ui.label("%s %s" % [tr(String(_data.gem(String(comp["gem"]))["name_key"])), String(_data.quality(int(comp["quality"]))["roman"])], "BodyLabel"))
			if i < parts.size() and bool(parts[i]["owned"]):
				# Как в трекере: галочка — уже башня, зелёная точка — пока только кандидат раунда.
				h.add_child(Ui.icon("dot" if bool(parts[i]["candidate"]) else "check", 12, T.SUCCESS))
			chip.add_child(h)
			rec.add_child(chip)
		v.add_child(rec)
		var levels: GridContainer = GridContainer.new()
		levels.columns = 3
		levels.add_theme_constant_override("h_separation", T.SP_4)
		for lvl: int in range(1, 4):
			var lv: VBoxContainer = Ui.vbox(2)
			lv.custom_minimum_size = Vector2(250, 0)
			var head: String = tr("TP_LEVEL") % [lvl, 3]
			if lvl > 1:
				head += " · " + SpecialText.upgrade_text(_data, id, lvl)
			var hl: Label = Ui.label(head, "CapsLabel")
			hl.add_theme_color_override("font_color", T.GOLD if lvl == 3 else T.TEXT_DIM)
			lv.add_child(hl)
			for line: String in SpecialText.describe(_data, id, lvl):
				var ll: Label = Ui.label("• " + line, "DimLabel", true)
				ll.custom_minimum_size = Vector2(250, 0)
				lv.add_child(ll)
			levels.add_child(lv)
		v.add_child(levels)
		row.add_child(v)
		card.add_child(row)
		col.add_child(card)
	return col


## Слейты: рецепт, эффекты, отметка «на поле» в этом забеге.
func _slates() -> Control:
	var col: VBoxContainer = Ui.vbox(T.SP_3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var intro: Label = Ui.label(tr("CODEX_SLATES_INTRO"), "DimLabel", true)
	intro.custom_minimum_size = Vector2(900, 0)
	col.add_child(intro)
	for sl: Dictionary in _data.slates:
		var id: String = String(sl["id"])
		var card: PanelContainer = PanelContainer.new()
		card.theme_type_variation = "CardPanel"
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row: HBoxContainer = Ui.hbox(T.SP_4)
		var icon: GemIcon = GemIcon.new()
		icon.slate_id = id
		icon.custom_minimum_size = Vector2(64, 64)
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(icon)
		var v: VBoxContainer = Ui.vbox(4)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_row: HBoxContainer = Ui.hbox(T.SP_2)
		var nl: Label = Ui.label(tr(String(sl["name_key"])), "SubheaderLabel")
		nl.add_theme_color_override("font_color", Color.html(String(sl["color"])).lightened(0.2))
		name_row.add_child(nl)
		name_row.add_child(Ui.label(tr(String(sl["role_key"])), "DimLabel"))
		var on_board: int = 0
		if _sim != null:
			for s: TowerState in _sim.slates:
				on_board += 1 if s.slate_id == id else 0
		if on_board > 0:
			name_row.add_child(Ui.icon("check", 14, T.SUCCESS))
			var bl: Label = Ui.label(tr("TRACKER_BUILT") if on_board == 1 else tr("TRACKER_BUILT_N") % on_board, "CapsLabel")
			bl.add_theme_color_override("font_color", T.SUCCESS)
			name_row.add_child(bl)
		v.add_child(name_row)
		var rec: Label = Ui.label(tr("SLATE_RECIPE") % SlateText.recipe_text(_data, id), "BodyLabel", true)
		rec.custom_minimum_size = Vector2(760, 0)
		v.add_child(rec)
		for line: String in SlateText.describe(_data, id):
			var ll: Label = Ui.label("• " + line, "DimLabel", true)
			ll.custom_minimum_size = Vector2(760, 0)
			v.add_child(ll)
		row.add_child(v)
		card.add_child(row)
		col.add_child(card)
	return col


func _gems() -> Control:
	var col: VBoxContainer = Ui.vbox(T.SP_2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for g: Dictionary in _data.gems:
		var id: String = String(g["id"])
		var card: PanelContainer = PanelContainer.new()
		card.theme_type_variation = "InsetPanel"
		var row: HBoxContainer = Ui.hbox(T.SP_4)
		var icon: GemIcon = GemIcon.new()
		icon.gem_id = id
		icon.quality = 3
		icon.custom_minimum_size = Vector2(52, 52)
		row.add_child(icon)
		var v: VBoxContainer = Ui.vbox(2)
		v.custom_minimum_size = Vector2(260, 0)
		var nl: Label = Ui.label(tr(String(g["name_key"])), "SubheaderLabel")
		nl.add_theme_color_override("font_color", T.gem_color(id).lightened(0.2))
		v.add_child(nl)
		var rl: Label = Ui.label(tr(String(g["role_key"])), "DimLabel", true)
		rl.custom_minimum_size = Vector2(260, 0)
		v.add_child(rl)
		v.add_child(Ui.label("%s · %s" % [tr("DMG_" + String(g["damage_type"]).to_upper()), tr("TARGETS_" + String(g["targets"]).to_upper())], "CapsLabel"))
		row.add_child(v)
		var grid: GridContainer = GridContainer.new()
		grid.columns = _data.quality_count() + 1
		grid.add_theme_constant_override("h_separation", T.SP_4)
		grid.add_child(Ui.label("", "CapsLabel"))
		for q: int in range(1, _data.quality_count() + 1):
			var ql: Label = Ui.label(String(_data.quality(q)["roman"]), "CapsLabel")
			ql.add_theme_color_override("font_color", T.quality_color(q))
			grid.add_child(ql)
		for stat: String in ["STAT_DAMAGE", "STAT_ATTACK_SPEED", "STAT_RANGE"]:
			grid.add_child(Ui.label(tr(stat), "DimLabel"))
			for q2: int in range(1, _data.quality_count() + 1):
				var t: TowerState = TowerState.new()
				t.setup(_data, 0, Vector2i.ZERO, id, q2, 0)
				var val: String
				match stat:
					"STAT_DAMAGE":
						val = T.format_number(t.damage)
					"STAT_ATTACK_SPEED":
						val = "%.2f" % t.attack_speed
					_:
						val = "%.2f" % t.attack_range
				grid.add_child(Ui.label(val, "NumberLabel"))
		row.add_child(grid)
		card.add_child(row)
		col.add_child(card)
	return col


func _enemies() -> Control:
	var col: VBoxContainer = Ui.vbox(T.SP_2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid: GridContainer = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", T.SP_5)
	grid.add_theme_constant_override("v_separation", T.SP_2)
	for key: String in ["CODEX_EN_NAME", "CODEX_EN_HP", "CODEX_EN_SPEED", "CODEX_EN_ARMOR", "CODEX_EN_BOUNTY", "CODEX_EN_TAGS"]:
		grid.add_child(Ui.label(tr(key), "CapsLabel"))
	for id: String in _data.archetypes.keys():
		var a: Dictionary = _data.archetypes[id]
		var name_row: HBoxContainer = Ui.hbox(T.SP_2)
		# Портрет модели (tools/art_preview.gd -- --portraits); без файла — прежняя цветная метка.
		var portrait_path: String = "res://assets/ui/portraits/ui_portrait_%s.png" % id
		if ResourceLoader.exists(portrait_path):
			var pr: TextureRect = TextureRect.new()
			pr.texture = load(portrait_path)
			pr.custom_minimum_size = Vector2(48, 48)
			pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			name_row.add_child(pr)
		if a["boss"] or a["flying"] or not ResourceLoader.exists(portrait_path):
			name_row.add_child(Ui.icon("boss" if a["boss"] else ("air" if a["flying"] else "dot"), 14, Color.html(String(a["color"]))))
		var nl: Label = Ui.label(tr(String(a["name_key"])), "BodyLabel")
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(nl)
		grid.add_child(name_row)
		grid.add_child(Ui.label("×%s" % str(a["hp_mult"]), "NumberLabel"))
		grid.add_child(Ui.label("%.1f" % float(a["speed"]), "NumberLabel"))
		grid.add_child(Ui.label("%s %d" % [tr("ARMOR_" + String(a["armor_type"]).to_upper()), int(a["armor"])], "DimLabel"))
		grid.add_child(Ui.label(str(int(a["bounty"])), "NumberLabel"))
		var tags: PackedStringArray = PackedStringArray()
		if a["flying"]:
			tags.append(tr("TAG_FLYING"))
		if a["boss"]:
			tags.append(tr("TAG_BOSS"))
		for t: Variant in a["traits"]:
			tags.append(tr(String(_data.trait_cfg(String(t)).get("name_key", ""))))
		if float(a["shield_pct"]) > 0.0:
			tags.append(tr("TAG_SHIELD") % roundi(float(a["shield_pct"]) * 100.0))
		for dt: Variant in (a["resist"] as Dictionary).keys():
			tags.append(tr("TAG_RESIST") % [tr("DMG_" + String(dt).to_upper()), roundi((1.0 - float(a["resist"][dt])) * 100.0)])
		if not (a["split"] as Dictionary).is_empty():
			tags.append(tr("TAG_SPLIT") % int(a["split"]["count"]))
		var ab: Dictionary = a["abilities"]
		if ab.has("summon"):
			tags.append(tr("TAG_SUMMON"))
		if ab.has("phases"):
			tags.append(tr("TAG_PHASES") % (ab["phases"] as Array).size())
		if bool(a["immortal"]):
			tags.append(tr("TAG_IMMORTAL"))
		var tl: Label = Ui.label(", ".join(tags), "DimLabel", true)
		tl.custom_minimum_size = Vector2(300, 0)
		grid.add_child(tl)
	col.add_child(grid)
	var note: Label = Ui.label(tr("CODEX_EN_NOTE"), "FaintLabel", true)
	note.text += " " + tr("CODEX_ELITE_NOTE") % [_data.economy["elite"]["hp_mult"], int(_data.economy["elite"]["leak_mult"])]
	note.custom_minimum_size = Vector2(900, 0)
	col.add_child(note)
	return col


## Трейты: эффект, контрплей и волны, где они встречаются.
func _traits() -> Control:
	var col: VBoxContainer = Ui.vbox(T.SP_2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var waves_with: Dictionary = {}
	for n: int in range(1, _data.wave_count() + 1):
		for t: Variant in WaveSpawner.summary(_data, n)["traits"]:
			if not waves_with.has(t):
				waves_with[t] = []
			(waves_with[t] as Array).append(str(n))
	var ids: Array = _data.traits.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		var wa: Array = waves_with.get(a, ["99"])
		var wb: Array = waves_with.get(b, ["99"])
		return int(wa[0]) < int(wb[0]))
	for id: Variant in ids:
		var cfg: Dictionary = _data.trait_cfg(String(id))
		var card: PanelContainer = PanelContainer.new()
		card.theme_type_variation = "InsetPanel"
		var row: HBoxContainer = Ui.hbox(T.SP_3)
		row.add_child(Ui.icon(String(cfg.get("icon", "info")), 22, T.WARNING))
		var v: VBoxContainer = Ui.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(Ui.label(tr(String(cfg["name_key"])), "SubheaderLabel"))
		var d: Label = Ui.label(tr(String(cfg["desc_key"])), "BodyLabel", true)
		d.custom_minimum_size = Vector2(640, 0)
		v.add_child(d)
		var c: Label = Ui.label(tr("WAVE_COUNTER") % tr(String(cfg["counter_key"])), "DimLabel", true)
		c.add_theme_color_override("font_color", T.SUCCESS.lightened(0.2))
		v.add_child(c)
		row.add_child(v)
		var w: PackedStringArray = PackedStringArray(waves_with.get(id, []))
		var wl: Label = Ui.label(tr("CODEX_TRAIT_WAVES") % (", ".join(w) if not w.is_empty() else "—"), "FaintLabel", true)
		wl.custom_minimum_size = Vector2(200, 0)
		row.add_child(wl)
		card.add_child(row)
		col.add_child(card)
	return col
