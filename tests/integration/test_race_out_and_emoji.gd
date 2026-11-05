extends TestCase
## «Гонка» после выбывания: экран продолжения (таблица, «Наблюдать за …», выход) и эмодзи в чате.


func _rows(other_over: bool) -> Array[Dictionary]:
	return [
		{"id": 1, "name": "Я", "color": "#7cc4ff", "lives": 0, "wave": 14, "status": "out", "me": true, "gold": 0, "over": true},
		{"id": 2, "name": "Аня", "color": "#ff7ad9", "lives": 18, "wave": 15, "status": "combat", "me": false, "gold": 40, "over": other_over},
		{"id": 3, "name": "Борис", "color": "#4ade80", "lives": 7, "wave": 15, "status": "build", "me": false, "gold": 12, "over": false},
	] as Array[Dictionary]


func _buttons(n: Node, out: Array[Button]) -> Array[Button]:
	for c: Node in n.get_children():
		if c is Button:
			out.append(c as Button)
		_buttons(c, out)
	return out


func test_out_panel_lists_players_and_watch_buttons() -> void:
	var p: RaceOutPanel = RaceOutPanel.new().setup(false, 13, true, false)
	p.update_rows(_rows(false))
	var box: VBoxContainer = p.get("_watch_box")
	var watch: Array[Button] = _buttons(box, [] as Array[Button])
	assert_eq(watch.size(), 2, "наблюдать можно за двумя, кто ещё играет")
	var picked: Array[int] = []
	p.watch_requested.connect(func(id: int) -> void: picked.append(id))
	watch[1].pressed.emit()
	assert_eq(picked, [3] as Array[int])
	var grid: GridContainer = p.get("_grid")
	assert_eq(grid.get_child_count(), 4 * 4, "заголовок и три игрока по четыре колонки")
	p.update_rows(_rows(true))
	assert_eq(String(p.get("_watch_key")), "3", "выбывший соперник пропал из кнопок")
	p.free()


func test_out_panel_leave_for_guest_and_host() -> void:
	var guest: RaceOutPanel = RaceOutPanel.new().setup(true, 42, false, false)
	var left: Array[bool] = []
	guest.leave_requested.connect(func() -> void: left.append(true))
	guest.call("_on_leave")
	assert_eq(left, [true], "гость выходит сразу")
	guest.free()


func test_emoji_insert_respects_limit() -> void:
	var line: LineEdit = LineEdit.new()
	line.max_length = 4
	line.text = "gg"
	line.caret_column = 2
	EmojiPicker.insert_into(line, "🔥")
	assert_eq(line.text, "gg🔥")
	EmojiPicker.insert_into(line, "👍")
	assert_eq(line.text, "gg🔥👍")
	EmojiPicker.insert_into(line, "🎉")
	assert_eq(line.text, "gg🔥👍", "сверх лимита не вставляется")
	line.free()
	var picker: EmojiPicker = EmojiPicker.new()
	var grid: GridContainer = picker.get_child(0) as GridContainer
	assert_eq(grid.get_child_count(), EmojiPicker.EMOJI.size())
	for b: Node in grid.get_children():
		assert_eq((b as Button).focus_mode, Control.FOCUS_NONE, "кнопки эмодзи не забирают фокус у поля ввода")
	var toggle: Button = picker.make_toggle()
	assert_false(picker.visible)
	toggle.pressed.emit()
	assert_true(picker.visible)
	toggle.free()
	picker.free()
	assert_eq(NetProtocol.sanitize_chat("gg 🔥🎉"), "gg 🔥🎉", "эмодзи проходят очистку сообщения")


## Таблица обновляется на месте: те же узлы, новые числа; пересборка — только при смене состава игроков.
func test_out_panel_updates_in_place() -> void:
	var p: RaceOutPanel = RaceOutPanel.new().setup(false, 13, false, false)
	var rows: Array[Dictionary] = _rows(false)
	p.update_rows(rows)
	var grid: GridContainer = p.get("_grid")
	var first: Node = grid.get_child(5)
	var nodes: Dictionary = p.get("_row_nodes")
	assert_eq((nodes[2]["wave"] as Label).text, "15")
	rows[1]["wave"] = 16
	rows[1]["status"] = "build"
	p.update_rows(rows)
	assert_eq(grid.get_child(5), first, "строки не пересобраны")
	assert_eq((nodes[2]["wave"] as Label).text, "16")
	assert_eq((nodes[2]["icon"] as UiIcon).icon_name, String(OpponentsPanel.STATUS_ICON["build"]))
	var menu: Array[bool] = []
	p.menu_requested.connect(func() -> void: menu.append(true))
	for b: Button in _buttons(p.body, [] as Array[Button]):
		var labels: Array[Node] = b.find_children("*", "Label", true, false)
		if not labels.is_empty() and (labels[0] as Label).text == p.tr("MP_OUT_MENU"):
			b.pressed.emit()
	assert_eq(menu, [true], "кнопка «Меню» открывает меню паузы")
	p.free()


## Кодекс → «Справка»: последняя вкладка, тексты собраны из данных (без «%» неподставленных форматов),
## для забега — его длина, для бесконечной гонки — своя строка.
func test_codex_help_tab() -> void:
	for sim: GameSim in [null, new_sim(1, {"max_waves": 20}), new_sim(2, {"endless": true})]:
		var c: CodexPanel = CodexPanel.new().setup(sim)
		var tabs: TabContainer = c.find_children("*", "TabContainer", true, false)[0] as TabContainer
		assert_eq(tabs.get_tab_count(), 6)
		var help: Control = tabs.get_child(tabs.get_tab_count() - 1) as Control
		var text: PackedStringArray = PackedStringArray()
		for l: Node in help.find_children("*", "Label", true, false):
			text.append((l as Label).text)
		var all: String = "\n".join(text)
		assert_false(all.contains("%d") or all.contains("%s"), "форматы подставлены")
		assert_true(all.contains("20") and all.contains("42") and all.contains("62"), "три длины забега")
		if sim != null and sim.endless:
			assert_true(all.contains(c.tr("HELP_CURRENT_ENDLESS")))
		elif sim != null:
			assert_true(all.contains(c.tr("HELP_CURRENT_RUN") % 20))
		c.free()
