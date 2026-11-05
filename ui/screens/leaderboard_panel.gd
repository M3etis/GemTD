class_name LeaderboardPanel
extends Modal
## Таблица лидеров (§10 PROMPT.md): категории, фильтры (сложность, версия, только мои),
## карточка записи (реплей, seed, экспорт), импорт результата друга, сводка «Гонки».

const COLS: Array[int] = [56, 190, 120, 90, 110, 110, 150, 40]

var _tabs: TabBar
var _diff: OptionButton
var _version: OptionButton
var _mine: CheckButton
var _list: VBoxContainer
var _summary: Label
var _category: String = "classic"
## Заголовок колонки метрики: очки, время, DPS — по категории.
var _metric_head: Label
var _diff_ids: PackedStringArray = PackedStringArray()
var _open_id: String = ""


func _init() -> void:
	super._init()
	header(tr("LB_TITLE"), "trophy")
	_tabs = TabBar.new()
	_tabs.clip_tabs = false
	for c: String in Leaderboard.CATEGORIES:
		_tabs.add_tab(tr("LB_CAT_" + c.to_upper()))
	_tabs.tab_changed.connect(func(i: int) -> void:
		Audio.play("sfx/ui/tab_switch")
		_category = Leaderboard.CATEGORIES[i]
		_open_id = ""
		_refresh())
	body.add_child(_tabs)
	var bar: HBoxContainer = Ui.hbox(T.SP_3)
	_diff = OptionButton.new()
	_diff.add_item(tr("LB_ALL_DIFFICULTIES"), 0)
	_diff_ids.append("")
	var data: GameData = GameData.load_default()
	for i: int in data.difficulty_order.size():
		var id: String = data.difficulty_order[i]
		_diff.add_item(tr(String(data.difficulty(id)["name_key"])), i + 1)
		_diff_ids.append(id)
	_diff.item_selected.connect(func(_i: int) -> void: _refresh())
	bar.add_child(_diff)
	_version = OptionButton.new()
	_version.add_item(tr("LB_ALL_VERSIONS"), 0)
	_version.add_item(tr("LB_THIS_VERSION") % Game.version(), 1)
	_version.item_selected.connect(func(_i: int) -> void: _refresh())
	bar.add_child(_version)
	_mine = CheckButton.new()
	_mine.text = tr("LB_ONLY_MINE")
	_mine.toggled.connect(func(_v: bool) -> void: _refresh())
	bar.add_child(_mine)
	bar.add_child(Ui.spacer())
	var imp: Button = Ui.button(tr("LB_IMPORT"), "Button", "", "arrow_up")
	imp.tooltip_text = tr("LB_IMPORT_TIP")
	imp.pressed.connect(_import)
	bar.add_child(imp)
	body.add_child(bar)
	_summary = Ui.label("", "DimLabel")
	body.add_child(_summary)
	var head: HBoxContainer = Ui.hbox(0)
	var keys: Array[String] = ["LB_COL_RANK", "LB_COL_NAME", "LB_COL_SCORE", "LB_COL_WAVE", "LB_COL_DIFF", "LB_COL_SEED", "LB_COL_DATE", ""]
	for i: int in COLS.size():
		var l: Label = Ui.label(tr(keys[i]) if not keys[i].is_empty() else "", "CapsLabel")
		l.custom_minimum_size = Vector2(COLS[i], 0)
		head.add_child(l)
		if i == 2:
			_metric_head = l
	body.add_child(head)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(980, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = Ui.vbox(4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	body.add_child(scroll)
	Events.leaderboard_updated.connect(func(_id: String) -> void: _refresh())
	_refresh()


func _rows() -> Array[Dictionary]:
	var diff: String = _diff_ids[maxi(_diff.selected, 0)]
	var all: Array[Dictionary] = Leaderboard.ranking(_category, diff, Game.today_iso() if _category == "daily" else "")
	var out: Array[Dictionary] = []
	var me: String = String(Leaderboard.profile.get("uuid", ""))
	for r: Dictionary in all:
		if _version.selected == 1 and String(r.get("version", "")) != Game.version():
			continue
		if _mine.button_pressed and String(r.get("profile", "")) != me:
			continue
		out.append(r)
	return out


func _refresh() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	if _metric_head != null:
		_metric_head.text = tr(String({"speed": "LB_COL_TIME", "damage": "LB_COL_DPS"}.get(_category, "LB_COL_SCORE")))
	if _category == "race":
		var rs: Dictionary = Leaderboard.race_summary()
		_summary.text = tr("LB_RACE_SUMMARY") % [int(rs["matches"]), int(rs["wins"]), float(rs["avg_place"])]
		_summary.visible = true
	else:
		_summary.visible = false
	var rows: Array[Dictionary] = _rows()
	if rows.is_empty():
		var empty: VBoxContainer = Ui.vbox(T.SP_2)
		empty.alignment = BoxContainer.ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(960, 240)
		var ic: UiIcon = Ui.icon("trophy", 48, T.TEXT_FAINT)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		empty.add_child(ic)
		var l: Label = Ui.label(tr("LB_EMPTY_" + _category.to_upper()), "DimLabel")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_child(l)
		_list.add_child(empty)
		return
	var me: String = String(Leaderboard.profile.get("uuid", ""))
	var items: Array = []
	for i: int in mini(rows.size(), 50):
		var r: Dictionary = rows[i]
		var b: Button = Button.new()
		b.theme_type_variation = "ChipButton"
		b.toggle_mode = true
		b.button_pressed = String(r["id"]) == _open_id
		b.custom_minimum_size = Vector2(960, 36)
		var line: HBoxContainer = Ui.hbox(0)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rank_color: Color = [T.GOLD, Color("cfd8e6"), Color("e0a36b")][i] if i < 3 else T.TEXT_DIM
		var race: bool = _category == "race"
		_cell(line, ("#%d/%d" % [int(r.get("place", 0)), int(r.get("players", 0))]) if race else "#%d" % (i + 1), 0, "NumberLabel", rank_color)
		var name_color: Color = T.ACCENT if String(r.get("profile", "")) == me else T.TEXT
		_cell(line, String(r["name"]) + (" ⇩" if bool(r.get("imported", false)) else ""), 1, "BodyLabel", name_color)
		var metric: String = T.format_number(float(r["score"]))
		var metric_color: Color = T.ACCENT
		if _category == "speed":
			metric = T.format_time(float(r["combat_seconds"]))
			metric_color = T.SUCCESS
		elif _category == "damage":
			metric = tr("LB_DPS_VALUE") % T.format_number(float(r.get("damage_dps", 0)))
			metric_color = T.DANGER.lightened(0.25)
		_cell(line, metric, 2, "NumberLabel", metric_color)
		_cell(line, T.wave_fraction(int(r["waves_cleared"]), int(r["total_waves"])), 3, "NumberLabel", T.SUCCESS if String(r["outcome"]) == "victory" else T.TEXT_DIM)
		var dd: Dictionary = GameData.load_default().difficulty(String(r["difficulty"]))
		_cell(line, tr(String(dd.get("name_key", ""))), 4, "DimLabel", T.TEXT_DIM)
		_cell(line, RunRng.seed_to_text(int(r["seed"])), 5, "DimLabel", T.TEXT_DIM)
		_cell(line, String(r["date"]).substr(0, 16).replace("T", " "), 6, "DimLabel", T.TEXT_FAINT)
		var state: String = String(r.get("verify_state", "pending"))
		var vi: UiIcon = Ui.icon("check" if state == "ok" else ("close" if state == "failed" else "clock"), 16, T.SUCCESS if state == "ok" else (T.DANGER if state == "failed" else T.TEXT_FAINT))
		vi.custom_minimum_size = Vector2(COLS[7], 16)
		line.add_child(vi)
		b.add_child(line)
		line.set_anchors_preset(Control.PRESET_FULL_RECT)
		line.offset_left = 8
		b.tooltip_text = tr("LB_VERIFY_" + state.to_upper())
		Ui.attach_feedback(b)
		var rid: String = String(r["id"])
		b.pressed.connect(func() -> void:
			_open_id = "" if _open_id == rid else rid
			_refresh())
		_list.add_child(b)
		items.append(b)
		if rid == _open_id:
			_list.add_child(_detail(r))
	Ui.stagger(items, 0.015)


func _detail(r: Dictionary) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.theme_type_variation = "CardPanel"
	var v: VBoxContainer = Ui.vbox(T.SP_2)
	p.add_child(v)
	var stats: HBoxContainer = Ui.hbox(T.SP_5)
	for pair: Array in [["RESULT_KILLS", str(int(r["kills"]))], ["RESULT_LEAKS", str(int(r["leaks"]))], ["RESULT_DAMAGE", T.format_number(float(r["total_damage"]))],
			["RESULT_PEAK_DPS", T.format_number(float(r["peak_dps"]))], ["RESULT_TIME", T.format_time(float(r["combat_seconds"]))]]:
		var s: VBoxContainer = Ui.vbox(0)
		s.add_child(Ui.label(tr(String(pair[0])), "CapsLabel"))
		s.add_child(Ui.label(String(pair[1]), "NumberLabel"))
		stats.add_child(s)
	v.add_child(stats)
	var data: GameData = GameData.load_default()
	var build: HBoxContainer = Ui.hbox(T.SP_2)
	build.add_child(Ui.label(tr("LB_BUILD"), "CapsLabel"))
	for sp: String in (r.get("specials", {}) as Dictionary).keys():
		var gi: GemIcon = GemIcon.new()
		gi.special_id = sp
		gi.quality = int(r["specials"][sp])
		gi.custom_minimum_size = Vector2(28, 28)
		gi.tooltip_text = tr(String(data.special(sp).get("name_key", "")))
		gi.mouse_filter = Control.MOUSE_FILTER_PASS
		build.add_child(gi)
	for gem: String in (r.get("gems_used", {}) as Dictionary).keys():
		var g2: GemIcon = GemIcon.new()
		g2.gem_id = gem
		g2.quality = 2
		g2.glow = false
		g2.custom_minimum_size = Vector2(22, 22)
		g2.tooltip_text = "%s ×%d" % [tr(String(data.gem(gem).get("name_key", ""))), int(r["gems_used"][gem])]
		g2.mouse_filter = Control.MOUSE_FILTER_PASS
		build.add_child(g2)
	v.add_child(build)
	if String(r.get("mode", "")) == "race":
		var opp: PackedStringArray = PackedStringArray(r.get("opponents", []))
		v.add_child(Ui.label(tr("LB_OPPONENTS") % ", ".join(opp), "DimLabel"))
	var actions: HBoxContainer = Ui.hbox(T.SP_2)
	var compatible: bool = int(r.get("data_hash", -1)) == data.data_hash
	var watch: Button = Ui.button(tr("ACT_WATCH_REPLAY"), "PrimaryButton", "", "play")
	watch.disabled = not compatible
	watch.tooltip_text = "" if compatible else tr("ERR_REPLAY_DATA_MISMATCH")
	watch.pressed.connect(func() -> void:
		var rep: Dictionary = Leaderboard.load_replay(r)
		if rep.is_empty():
			Events.toast_requested.emit(tr("ERR_REPLAY_MISSING"), "error")
			return
		Game.new_run({"mode": "replay", "replay": rep, "record": r}))
	actions.add_child(watch)
	var play: Button = Ui.button(tr("ACT_PLAY_SEED"), "Button", "", "gem")
	play.pressed.connect(func() -> void: Game.new_run({"seed": int(r["seed"]), "difficulty": String(r["difficulty"]), "daily": String(r.get("daily", ""))}))
	actions.add_child(play)
	var copy: Button = Ui.button(tr("HUD_COPY_SEED"), "GhostButton", "", "copy")
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(RunRng.seed_to_text(int(r["seed"])))
		Events.toast_requested.emit(tr("TOAST_SEED_COPIED") % RunRng.seed_to_text(int(r["seed"])), "info"))
	actions.add_child(copy)
	var exp: Button = Ui.button(tr("LB_EXPORT"), "GhostButton", "", "arrow_up")
	exp.tooltip_text = tr("LB_EXPORT_TIP")
	exp.pressed.connect(func() -> void: _export(String(r["id"]), String(r["name"])))
	actions.add_child(exp)
	v.add_child(actions)
	return p


func _cell(row: HBoxContainer, text: String, col: int, variation: String, color: Color) -> void:
	var l: Label = Ui.label(text, variation)
	l.add_theme_color_override("font_color", color)
	if variation == "NumberLabel":
		l.add_theme_font_size_override("font_size", T.FS_M)
	l.custom_minimum_size = Vector2(COLS[col], 0)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(l)


func _file_dialog(mode: FileDialog.FileMode) -> FileDialog:
	var fd: FileDialog = FileDialog.new()
	fd.use_native_dialog = true
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = mode
	fd.filters = PackedStringArray(["*.gtdx ; Gem Tower Defense"])
	fd.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	add_child(fd)
	return fd


func _export(id: String, who: String) -> void:
	var fd: FileDialog = _file_dialog(FileDialog.FILE_MODE_SAVE_FILE)
	fd.current_file = "gemtd-%s-%s.gtdx" % [who.validate_filename(), id]
	fd.file_selected.connect(func(path: String) -> void:
		var err: Error = Leaderboard.export_record(id, path)
		Events.toast_requested.emit(tr("LB_EXPORTED") % path.get_file() if err == OK else tr("ERR_EXPORT") % error_string(err), "success" if err == OK else "error"))
	fd.popup_centered(Vector2i(900, 600))


func _import() -> void:
	var fd: FileDialog = _file_dialog(FileDialog.FILE_MODE_OPEN_FILE)
	fd.file_selected.connect(func(path: String) -> void:
		var res: Dictionary = Leaderboard.import_file(path)
		if res["ok"]:
			Events.toast_requested.emit(tr("LB_IMPORTED") % String(res["record"]["name"]), "success")
			_open_id = String(res["record"]["id"])
			_refresh()
		else:
			Events.toast_requested.emit(tr(String(res["reason"])), "error"))
	fd.popup_centered(Vector2i(900, 600))
