class_name SoundBrowser
extends Modal
## Звуковой браузер (§9.4): все события пака, их источник (свой пак, --audio-dir, встроенный, fallback),
## число вариантов и кнопка прослушивания. Поиск по id.

var _list: VBoxContainer
var _search: LineEdit
var _rows: Array[Dictionary] = []


func _init() -> void:
	super._init()
	header(tr("SB_TITLE"), "sound")
	var top: HBoxContainer = Ui.hbox(T.SP_3)
	_search = LineEdit.new()
	_search.placeholder_text = tr("SB_SEARCH")
	_search.custom_minimum_size = Vector2(360, 0)
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _fill())
	top.add_child(_search)
	top.add_child(Ui.spacer())
	var reload: Button = Ui.button(tr("SETTINGS_RELOAD_SOUNDS"), "GhostButton", "", "arrow_up")
	reload.pressed.connect(func() -> void:
		Audio.reload()
		_load())
	top.add_child(reload)
	body.add_child(top)
	var head: HBoxContainer = Ui.hbox(0)
	for pair: Array in [["SB_COL_EVENT", 420], ["SB_COL_SOURCE", 200], ["SB_COL_FILES", 80], ["", 60]]:
		var l: Label = Ui.label(tr(String(pair[0])) if not String(pair[0]).is_empty() else "", "CapsLabel")
		l.custom_minimum_size = Vector2(int(pair[1]), 0)
		head.add_child(l)
	body.add_child(head)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(780, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = Ui.vbox(2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	body.add_child(scroll)
	var hint: Label = Ui.label(tr("SB_HINT") % Audio.pack_dir(Audio.active_pack()), "FaintLabel", true)
	hint.custom_minimum_size = Vector2(780, 0)
	body.add_child(hint)
	closed.connect(Audio.stop_preview)
	_load()


func _ready() -> void:
	super._ready()
	_search.grab_focus.call_deferred()


func _load() -> void:
	_rows = Audio.report()
	_fill()


func _fill() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	var q: String = _search.text.strip_edges().to_lower()
	for row: Dictionary in _rows:
		var id: String = String(row["id"])
		if not q.is_empty() and not id.to_lower().contains(q):
			continue
		var line: HBoxContainer = Ui.hbox(0)
		var name: Label = Ui.label(id, "BodyLabel")
		name.custom_minimum_size = Vector2(420, 0)
		name.clip_text = true
		line.add_child(name)
		var src: String = String(row["source"])
		var text: String
		var color: Color = T.TEXT_DIM
		if src == "builtin":
			text = tr("SB_SRC_BUILTIN")
		elif not src.is_empty():
			text = tr("SB_SRC_CUSTOM") % src.trim_prefix("pack:")
			color = T.SUCCESS
		elif not String(row["fallback"]).is_empty():
			text = tr("SB_SRC_FALLBACK") % String(row["fallback"]).get_file()
			color = T.WARNING
		else:
			text = tr("SB_SRC_MISSING")
			color = T.DANGER
		var sl: Label = Ui.label(text, "DimLabel")
		sl.add_theme_color_override("font_color", color)
		sl.custom_minimum_size = Vector2(200, 0)
		sl.clip_text = true
		line.add_child(sl)
		var fl: Label = Ui.label(str(int(row["files"])), "NumberLabel")
		fl.custom_minimum_size = Vector2(80, 0)
		line.add_child(fl)
		var play: Button = Ui.icon_button("play", 14, "ChipButton", Vector2(44, 28))
		play.tooltip_text = tr("SB_PLAY")
		play.pressed.connect(func() -> void: Audio.preview(id))
		line.add_child(play)
		_list.add_child(line)
