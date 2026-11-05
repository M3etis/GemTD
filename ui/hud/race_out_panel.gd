class_name RaceOutPanel
extends Modal
## «Гонка»: локальный игрок выбыл (или прошёл все волны), а соперники ещё играют. Экран продолжения:
## результат, живая таблица игроков и выбор — наблюдать за полем соперника, остаться на своём поле,
## открыть меню или выйти. Матч продолжается без выбывшего; итоги появятся сами, когда закончат все.
## Закрытый экран снова открывается по Esc или кнопкой на плашке наблюдения.
## Таблица обновляется раз в 0.25 с: строки пересобираются, только когда меняется состав игроков,
## числа и статус обновляются на месте (как в OpponentsPanel).

signal watch_requested(id: int)
## «Остаться на своём поле»: окно закрывается, камера — на своём поле.
signal stay_requested
## «Меню»: окно закрывается, открывается меню паузы (настройки, Кодекс, выход).
signal menu_requested
signal leave_requested

var _grid: GridContainer
var _watch_box: VBoxContainer
## Состав строк таблицы и кнопок «Наблюдать»: пересобираются, только когда он меняется.
var _rows_key: String = ""
var _watch_key: String = ""
## Узлы строк для обновления на месте: id → {wave, lives, icon, status}.
var _row_nodes: Dictionary = {}
var _host: bool = false


func setup(victory: bool, waves_cleared: int, endless: bool, host: bool) -> RaceOutPanel:
	_host = host
	header(tr("MP_OUT_TITLE_FINISHED") if victory else tr("MP_OUT_TITLE"), "crown" if victory else "skull")
	var result: Label = Ui.label(tr("MP_OUT_RESULT") % waves_cleared, "SubheaderLabel")
	result.add_theme_color_override("font_color", T.SUCCESS if victory else T.DANGER)
	body.add_child(result)
	var text: Label = Ui.label(tr("MP_OUT_TEXT_ENDLESS") if endless else tr("MP_OUT_TEXT"), "DimLabel", true)
	text.custom_minimum_size = Vector2(460, 0)
	body.add_child(text)
	body.add_child(HSeparator.new())
	body.add_child(Ui.label(tr("MP_PLAYERS"), "CapsLabel"))
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", T.SP_5)
	_grid.add_theme_constant_override("v_separation", T.SP_2)
	body.add_child(_grid)
	_watch_box = Ui.vbox(T.SP_2)
	body.add_child(_watch_box)
	var actions: HBoxContainer = Ui.hbox(T.SP_3)
	actions.alignment = BoxContainer.ALIGNMENT_END
	var leave: Button = Ui.button(tr("MP_OUT_LEAVE"), "GhostButton", "", "close")
	leave.tooltip_text = tr("MP_OUT_LEAVE_HOST_TIP") if host else tr("MP_OUT_LEAVE_TIP")
	leave.pressed.connect(_on_leave)
	actions.add_child(leave)
	var menu: Button = Ui.button(tr("MP_OUT_MENU"), "GhostButton", "", "gear")
	menu.tooltip_text = tr("MP_OUT_MENU_TIP")
	menu.pressed.connect(func() -> void:
		close()
		menu_requested.emit())
	actions.add_child(menu)
	var stay: Button = Ui.button(tr("MP_OUT_STAY"), "Button", "", "back")
	stay.tooltip_text = tr("MP_OUT_STAY_TIP")
	stay.pressed.connect(func() -> void:
		close()
		stay_requested.emit())
	actions.add_child(stay)
	body.add_child(actions)
	return self


## Строки панели игроков (RaceSession.board_rows): волна, жизни, статус; кнопки «Наблюдать» — за теми, кто в игре.
func update_rows(rows: Array[Dictionary]) -> void:
	var ids: PackedStringArray = PackedStringArray()
	var alive: Array[Dictionary] = []
	for r: Dictionary in rows:
		ids.append("%d:%s" % [int(r["id"]), bool(r["me"])])
		if not bool(r["me"]) and not bool(r.get("over", false)):
			alive.append(r)
	var rows_key: String = ",".join(ids)
	if rows_key != _rows_key:
		_rows_key = rows_key
		_rebuild_rows(rows)
	for r2: Dictionary in rows:
		_fill_row(r2)
	var alive_ids: PackedStringArray = PackedStringArray()
	for a: Dictionary in alive:
		alive_ids.append(str(int(a["id"])))
	var key: String = ",".join(alive_ids)
	if key != _watch_key:
		_watch_key = key
		_rebuild_watch(alive)


func _rebuild_rows(rows: Array[Dictionary]) -> void:
	for c: Node in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_row_nodes.clear()
	for key: String in ["LB_COL_NAME", "LB_COL_WAVE", "MP_COL_LIVES", "MP_COL_STATUS"]:
		_grid.add_child(Ui.label(tr(key), "CapsLabel"))
	for r: Dictionary in rows:
		var name_row: HBoxContainer = Ui.hbox(T.SP_2)
		var dot: ColorRect = ColorRect.new()
		dot.color = Color.html(String(r["color"]))
		dot.custom_minimum_size = Vector2(4, 18)
		name_row.add_child(dot)
		name_row.add_child(Ui.label(String(r["name"]) + ("  (" + tr("MP_YOU") + ")" if bool(r["me"]) else ""), "BodyLabel"))
		_grid.add_child(name_row)
		var wave: Label = Ui.label("", "NumberLabel")
		_grid.add_child(wave)
		var lives: Label = Ui.label("", "NumberLabel")
		_grid.add_child(lives)
		var status_row: HBoxContainer = Ui.hbox(T.SP_1)
		var icon: UiIcon = Ui.icon("dot", 14, T.TEXT_DIM)
		status_row.add_child(icon)
		var status: Label = Ui.label("", "DimLabel")
		status_row.add_child(status)
		_grid.add_child(status_row)
		_row_nodes[int(r["id"])] = {"wave": wave, "lives": lives, "icon": icon, "status": status}


func _fill_row(r: Dictionary) -> void:
	var n: Dictionary = _row_nodes.get(int(r["id"]), {})
	if n.is_empty():
		return
	(n["wave"] as Label).text = str(int(r["wave"]))
	(n["lives"] as Label).text = str(int(r["lives"]))
	var st: String = String(r["status"])
	var icon: UiIcon = n["icon"]
	icon.icon_name = String(OpponentsPanel.STATUS_ICON.get(st, "dot"))
	icon.color = T.DANGER if st == "out" else (T.GOLD if st == "victory" else T.TEXT_DIM)
	(n["status"] as Label).text = tr("MP_STATUS_" + st.to_upper())


func _rebuild_watch(alive: Array[Dictionary]) -> void:
	for c: Node in _watch_box.get_children():
		_watch_box.remove_child(c)
		c.queue_free()
	if alive.is_empty():
		_watch_box.add_child(Ui.label(tr("MP_OUT_NONE_LEFT"), "FaintLabel", true))
		return
	_watch_box.add_child(Ui.label(tr("MP_OUT_WATCH_TITLE"), "CapsLabel"))
	for i: int in alive.size():
		var id: int = int(alive[i]["id"])
		var b: Button = Ui.button(tr("MP_OUT_WATCH") % String(alive[i]["name"]), "PrimaryButton" if i == 0 else "Button", "", "target")
		b.pressed.connect(func() -> void:
			close()
			watch_requested.emit(id))
		_watch_box.add_child(b)


func _on_leave() -> void:
	if not _host:
		leave_requested.emit()
		return
	# Хост держит матч: если он выйдет, соединение пропадёт у всех.
	Modal.confirm(self, tr("MP_OUT_LEAVE_HOST_TITLE"), tr("MP_OUT_LEAVE_HOST_TIP"), tr("MP_OUT_LEAVE"), func() -> void: leave_requested.emit())
