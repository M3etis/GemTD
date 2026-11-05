class_name SaveSlotsPanel
extends Modal
## Слоты сохранений: режим "save" (3 ручных слота) или "load" (автосейв + слоты).

signal save_requested(slot: String)
signal load_requested(slot: String)

var _mode: String = "load"
var _list: VBoxContainer


func _init() -> void:
	super._init()


func setup(mode: String) -> SaveSlotsPanel:
	_mode = mode
	header(tr("SAVE_TITLE") if mode == "save" else tr("LOAD_TITLE"), "copy")
	_list = Ui.vbox(T.SP_2)
	_list.custom_minimum_size = Vector2(640, 0)
	body.add_child(_list)
	_refresh()
	return self


func _refresh() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	var slots: Array[String] = []
	if _mode == "load":
		slots.append(Save.AUTOSAVE)
	slots.append_array(Save.SLOTS)
	for slot: String in slots:
		_list.add_child(_row(slot))


func _row(slot: String) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.theme_type_variation = "CardPanel"
	var row: HBoxContainer = Ui.hbox(T.SP_3)
	var info: VBoxContainer = Ui.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title: String = tr("SAVE_AUTOSAVE") if slot == Save.AUTOSAVE else tr("SAVE_SLOT") % (Save.SLOTS.find(slot) + 1)
	info.add_child(Ui.label(title, "SubheaderLabel"))
	var save: Dictionary = Save.read(slot)
	var compatible: bool = Save.compatible(save)
	if save.is_empty():
		info.add_child(Ui.label(tr("SAVE_EMPTY"), "DimLabel"))
	else:
		var m: Dictionary = save.get("meta", {})
		var d: Dictionary = GameData.load_default().difficulty(String(save["difficulty"]))
		info.add_child(Ui.label(tr("SAVE_META") % [int(m.get("round", 1)), int(m.get("wave_total", 0)), int(m.get("lives", 0)), int(m.get("gold", 0)), tr(String(d.get("name_key", "")))], "DimLabel"))
		info.add_child(Ui.label("%s · seed %s" % [String(m.get("date", "")).replace("T", " ").left(16), RunRng.seed_to_text(int(save["seed"]))], "FaintLabel"))
		if not compatible:
			var w: Label = Ui.label(tr("ERR_SAVE_INCOMPATIBLE"), "DimLabel")
			w.add_theme_color_override("font_color", T.WARNING)
			info.add_child(w)
	row.add_child(info)
	if _mode == "save":
		var b: Button = Ui.button(tr("ACT_SAVE"), "PrimaryButton", "", "check")
		b.pressed.connect(func() -> void:
			if save.is_empty():
				save_requested.emit(slot)
				close()
			else:
				Modal.confirm(get_parent(), tr("SAVE_OVERWRITE_TITLE"), tr("SAVE_OVERWRITE_TEXT"), tr("ACT_SAVE"), func() -> void:
					save_requested.emit(slot)
					close(), false))
		row.add_child(b)
	else:
		var lb: Button = Ui.button(tr("ACT_LOAD"), "PrimaryButton", "", "play")
		lb.disabled = save.is_empty() or not compatible
		lb.pressed.connect(func() -> void:
			load_requested.emit(slot)
			close())
		row.add_child(lb)
	if not save.is_empty() and slot != Save.AUTOSAVE:
		var del: Button = Ui.icon_button("close", 12, "GhostButton", Vector2(32, 32))
		del.tooltip_text = tr("ACT_DELETE")
		del.pressed.connect(func() -> void:
			Modal.confirm(get_parent(), tr("SAVE_DELETE_TITLE"), tr("SAVE_DELETE_TEXT"), tr("ACT_DELETE"), func() -> void:
				Save.delete(slot)
				_refresh()))
		row.add_child(del)
	p.add_child(row)
	return p
