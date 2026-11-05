class_name MatchResultsPanel
extends Modal
## Итоги матча «Гонка»: сложность, места, волны, жизни, очки; проверка реплик соперников.

signal to_lobby
signal to_menu


func setup(standings: Array[Dictionary], local_id: int, verified: Dictionary, can_lobby: bool, difficulty: Dictionary = {},
		endless: bool = false) -> MatchResultsPanel:
	close_on_escape = false
	var my_place: int = 0
	for e: Dictionary in standings:
		if int(e["id"]) == local_id:
			my_place = int(e["place"])
	var title: Label = Ui.label(tr("MP_RESULT_WIN") if my_place == 1 else (tr("MP_RESULT_PLACE") % my_place), "TitleLabel")
	title.add_theme_color_override("font_color", T.GOLD if my_place == 1 else T.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var sub_row: HBoxContainer = Ui.hbox(T.SP_2)
	sub_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sub_row.add_child(Ui.label(tr("MP_RESULT_SUB") % standings.size(), "CapsLabel"))
	if endless:
		sub_row.add_child(Ui.label("·", "CapsLabel"))
		var el: Label = Ui.label(tr("MP_RESULT_ENDLESS"), "CapsLabel")
		el.add_theme_color_override("font_color", T.ACCENT)
		sub_row.add_child(el)
	if not difficulty.is_empty():
		sub_row.add_child(Ui.label("·", "CapsLabel"))
		sub_row.add_child(Ui.difficulty_label(difficulty))
	body.add_child(sub_row)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", T.SP_5)
	grid.add_theme_constant_override("v_separation", T.SP_2)
	for key: String in ["LB_COL_RANK", "LB_COL_NAME", "LB_COL_WAVE", "MP_COL_LIVES", "LB_COL_SCORE", "MP_COL_CHECK"]:
		grid.add_child(Ui.label(tr(key), "CapsLabel"))
	for e: Dictionary in standings:
		var id: int = int(e["id"])
		var place: Label = Ui.label("#%d" % int(e["place"]), "NumberLabel")
		place.add_theme_color_override("font_color", [T.GOLD, Color("cfd8e6"), Color("e0a36b"), T.TEXT_DIM][clampi(int(e["place"]) - 1, 0, 3)])
		grid.add_child(place)
		var name_row: HBoxContainer = Ui.hbox(T.SP_2)
		var dot: ColorRect = ColorRect.new()
		dot.color = Color.html(String(e["color"]))
		dot.custom_minimum_size = Vector2(4, 18)
		name_row.add_child(dot)
		var nl: Label = Ui.label(String(e["name"]) + ("  (" + tr("MP_YOU") + ")" if id == local_id else ""), "BodyLabel")
		name_row.add_child(nl)
		if String(e["outcome"]) == "left":
			name_row.add_child(Ui.label(tr("MP_LEFT"), "FaintLabel"))
		grid.add_child(name_row)
		grid.add_child(Ui.label(str(int(e["waves_cleared"])), "NumberLabel"))
		grid.add_child(Ui.label(str(int(e["lives"])), "NumberLabel"))
		grid.add_child(Ui.label(T.format_number(float(e["score"])), "NumberLabel"))
		var ok: bool = id == local_id or bool(verified.get(id, false))
		var check: UiIcon = Ui.icon("check" if ok else "info", 16, T.SUCCESS if ok else T.WARNING)
		check.tooltip_text = tr("MP_CHECK_OK") if ok else tr("MP_CHECK_PENDING")
		check.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(check)
	var center: CenterContainer = CenterContainer.new()
	center.add_child(grid)
	body.add_child(center)
	var actions: HBoxContainer = Ui.hbox(T.SP_3)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	var menu: Button = Ui.button(tr("ACT_TO_MENU"), "GhostButton", "", "close")
	menu.pressed.connect(func() -> void: to_menu.emit())
	actions.add_child(menu)
	if can_lobby:
		var lobby: Button = Ui.button(tr("MP_TO_LOBBY"), "PrimaryButton", "confirm", "play")
		lobby.pressed.connect(func() -> void: to_lobby.emit())
		actions.add_child(lobby)
	body.add_child(actions)
	Audio.play("sfx/game/victory" if my_place == 1 else "sfx/game/defeat")
	return self
