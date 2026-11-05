class_name ResultsPanel
extends Modal
## Итоги забега: исход, статистика, лучшая башня, очки и место в таблице лидеров.

signal replay_seed
signal new_game
signal to_menu
signal watch_replay
signal damage_test

var _record_id: String = ""


## test — итог Испытания урона ({record, rank, best}) или {}; can_test — показывать кнопку испытания.
func setup(data: GameData, summary: Dictionary, submit: Dictionary, test: Dictionary = {}, can_test: bool = true) -> void:
	close_on_escape = false
	var victory: bool = String(summary["outcome"]) == "victory"
	var rec: Dictionary = submit.get("record", {})
	_record_id = String(rec.get("id", ""))
	var title: Label = Ui.label(tr("RESULT_VICTORY") if victory else tr("RESULT_DEFEAT"), "TitleLabel")
	title.add_theme_color_override("font_color", T.SUCCESS.lightened(0.3) if victory else T.DANGER.lightened(0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var d: Dictionary = data.difficulty(String(summary["difficulty"]))
	var sub: Label = Ui.label(tr("RESULT_SUB") % [tr(String(d["name_key"])), RunRng.seed_to_text(int(summary["seed"]))], "CapsLabel")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(sub)

	var score_box: VBoxContainer = Ui.vbox(0)
	score_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var score: Label = Ui.label("0", "TitleLabel")
	score.add_theme_font_override("font", T.font("num"))
	score.add_theme_font_size_override("font_size", 64)
	score.add_theme_color_override("font_color", T.ACCENT)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_box.add_child(score)
	var rank_text: String = tr("RESULT_RANK") % int(submit.get("rank", 0)) if int(submit.get("rank", -1)) > 0 else ""
	var rank: Label = Ui.label(rank_text, "SubheaderLabel")
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_box.add_child(rank)
	if bool(submit.get("best", false)):
		var badge: PanelContainer = PanelContainer.new()
		badge.theme_type_variation = "ChipPanel"
		badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var bl: Label = Ui.label(tr("RESULT_NEW_RECORD"), "CapsLabel")
		bl.add_theme_color_override("font_color", T.GOLD)
		bl.add_theme_font_size_override("font_size", 14)
		badge.add_child(bl)
		score_box.add_child(badge)
		badge.ready.connect(func() -> void:
			Ui.punch(badge, 1.25)
			Audio.play("sfx/game/new_record"))
	body.add_child(score_box)
	var final_score: float = float(rec.get("score", 0))
	score.ready.connect(func() -> void:
		Ui.tween_number(score, 0.0, final_score, 1.4, func(v: float) -> String: return T.format_number(roundf(v))))

	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", T.SP_5)
	grid.add_theme_constant_override("v_separation", T.SP_2)
	_stat(grid, "RESULT_WAVES", T.wave_fraction(int(summary["waves_cleared"]), int(summary["total_waves"])))
	_stat(grid, "RESULT_KILLS", str(int(summary["kills"])))
	_stat(grid, "RESULT_LEAKS", str(int(summary["leaks"])))
	_stat(grid, "RESULT_GOLD", str(int(summary["gold_earned"])))
	_stat(grid, "RESULT_DAMAGE", T.format_number(float(summary["total_damage"])))
	_stat(grid, "RESULT_PEAK_DPS", T.format_number(float(summary["peak_dps"])))
	_stat(grid, "RESULT_TIME", T.format_time(float(summary["combat_seconds"])))
	_stat(grid, "RESULT_PATH", "%d" % int(roundf(float(summary["max_path_length"]))))
	var center: CenterContainer = CenterContainer.new()
	center.add_child(grid)
	body.add_child(center)

	var dps: Array = summary.get("wave_dps", [])
	if dps.size() >= 2:
		var chart_box: VBoxContainer = Ui.vbox(4)
		chart_box.add_child(Ui.label(tr("RESULT_DPS_CHART"), "CapsLabel"))
		chart_box.add_child(DpsChart.new().setup(dps, int(data.waves_cfg["air_every"]), data.waves_cfg["boss_waves"]))
		var cc: CenterContainer = CenterContainer.new()
		cc.add_child(chart_box)
		body.add_child(cc)

	var best: Dictionary = summary.get("best_tower", {})
	if not best.is_empty():
		var bt: PanelContainer = PanelContainer.new()
		bt.theme_type_variation = "InsetPanel"
		var row: HBoxContainer = Ui.hbox(T.SP_3)
		var ic: GemIcon = GemIcon.new()
		var is_sp: bool = not String(best.get("special", "")).is_empty()
		if is_sp:
			ic.special_id = String(best["special"])
			ic.quality = int(best.get("level", 1))
		else:
			ic.gem_id = String(best["gem"])
			ic.quality = int(best["quality"])
		ic.custom_minimum_size = Vector2(44, 44)
		row.add_child(ic)
		var v: VBoxContainer = Ui.vbox(0)
		v.add_child(Ui.label(tr("RESULT_BEST_TOWER"), "CapsLabel"))
		var nm: Label
		if is_sp:
			var sp: Dictionary = data.special(String(best["special"]))
			nm = Ui.label("%s · %s" % [tr(String(sp["name_key"])), tr("TP_LEVEL") % [int(best.get("level", 1)), 3]], "SubheaderLabel")
			nm.add_theme_color_override("font_color", Color.html(String(sp["color"])).lightened(0.2))
		else:
			var g: Dictionary = data.gem(String(best["gem"]))
			nm = Ui.label("%s %s" % [tr(String(g["name_key"])), String(data.quality(int(best["quality"]))["roman"])], "SubheaderLabel")
			nm.add_theme_color_override("font_color", T.gem_color(String(best["gem"])).lightened(0.2))
		v.add_child(nm)
		row.add_child(v)
		row.add_child(Ui.spacer())
		var dmg: Label = Ui.label(T.format_number(float(best["damage"])), "BigNumberLabel")
		row.add_child(dmg)
		bt.add_child(row)
		body.add_child(bt)

	if bool(summary.get("damage_test_done", false)):
		body.add_child(_test_result(summary, test))

	var used: Dictionary = summary.get("specials", {})
	if not used.is_empty():
		var sp_row: HBoxContainer = Ui.hbox(T.SP_2)
		sp_row.alignment = BoxContainer.ALIGNMENT_CENTER
		sp_row.add_child(Ui.label(tr("RESULT_SPECIALS"), "CapsLabel"))
		for id: String in used.keys():
			var chip: PanelContainer = PanelContainer.new()
			chip.theme_type_variation = "ChipPanel"
			var h: HBoxContainer = Ui.hbox(4)
			var gi: GemIcon = GemIcon.new()
			gi.special_id = id
			gi.quality = int(used[id])
			gi.glow = false
			gi.custom_minimum_size = Vector2(24, 24)
			h.add_child(gi)
			h.add_child(Ui.label(tr(String(data.special(id)["name_key"])), "BodyLabel"))
			chip.add_child(h)
			sp_row.add_child(chip)
		body.add_child(sp_row)

	var name_row: HBoxContainer = Ui.hbox(T.SP_2)
	name_row.add_child(Ui.label(tr("RESULT_NAME"), "DimLabel"))
	var le: LineEdit = LineEdit.new()
	le.text = String(rec.get("name", ""))
	le.max_length = 24
	le.custom_minimum_size = Vector2(240, 0)
	le.text_changed.connect(func(t: String) -> void:
		var clean: String = t.strip_edges()
		if clean.is_empty():
			return
		Settings.set_value("general", "player_name", clean)
		Leaderboard.rename(_record_id, clean))
	name_row.add_child(le)
	name_row.add_child(Ui.spacer())
	var verify: Label = Ui.label(tr("RESULT_VERIFY_PENDING"), "FaintLabel")
	name_row.add_child(verify)
	Events.leaderboard_updated.connect(func(id: String) -> void:
		if id == _record_id and is_instance_valid(verify):
			var r: Dictionary = Leaderboard.find(id)
			verify.text = tr("RESULT_VERIFY_OK") if String(r.get("verify_state", "")) == "ok" else tr("RESULT_VERIFY_FAILED"))
	body.add_child(name_row)

	var actions: HBoxContainer = Ui.hbox(T.SP_3)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	var menu: Button = Ui.button(tr("ACT_TO_MENU"), "GhostButton", "menu")
	menu.pressed.connect(func() -> void: to_menu.emit())
	actions.add_child(menu)
	var watch: Button = Ui.button(tr("ACT_WATCH_REPLAY"), "Button", "", "play")
	watch.pressed.connect(func() -> void: watch_replay.emit())
	actions.add_child(watch)
	var again: Button = Ui.button(tr("ACT_REPLAY_SEED"), "Button", "restart")
	again.pressed.connect(func() -> void: replay_seed.emit())
	actions.add_child(again)
	var can_run_test: bool = victory and can_test and not bool(summary.get("damage_test_done", false))
	if can_run_test:
		var dt: Button = Ui.button(tr("DT_START"), "PrimaryButton", "", "target")
		dt.tooltip_text = tr("DT_START_TIP")
		dt.pressed.connect(func() -> void: damage_test.emit())
		actions.add_child(dt)
	var fresh: Button = Ui.button(tr("ACT_NEW_GAME"), "Button" if can_run_test else "PrimaryButton", "confirm", "play")
	fresh.pressed.connect(func() -> void: new_game.emit())
	actions.add_child(fresh)
	body.add_child(actions)
	Audio.play("sfx/game/victory" if victory else "sfx/game/defeat")


func _test_result(summary: Dictionary, test: Dictionary) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.theme_type_variation = "InsetPanel"
	var row: HBoxContainer = Ui.hbox(T.SP_4)
	row.add_child(Ui.icon("target", 28, T.DANGER.lightened(0.3)))
	var v: VBoxContainer = Ui.vbox(0)
	v.add_child(Ui.label(tr("DT_TITLE"), "CapsLabel"))
	var rank: int = int(test.get("rank", -1))
	var line: String = tr("DT_RESULT_LINE") % T.format_number(float(summary["damage_test_damage"]))
	if rank > 0:
		line += " · " + tr("DT_RANK") % rank
	v.add_child(Ui.label(line, "BodyLabel"))
	row.add_child(v)
	row.add_child(Ui.spacer())
	var dps: Label = Ui.label(tr("LB_DPS_VALUE") % T.format_number(float(summary["damage_test_dps"])), "BigNumberLabel")
	dps.add_theme_color_override("font_color", T.DANGER.lightened(0.3))
	row.add_child(dps)
	if bool(test.get("best", false)):
		var badge: Label = Ui.label(tr("RESULT_NEW_RECORD"), "CapsLabel")
		badge.add_theme_color_override("font_color", T.GOLD)
		row.add_child(badge)
	p.add_child(row)
	return p


func _stat(grid: GridContainer, key: String, value: String) -> void:
	var v: VBoxContainer = Ui.vbox(0)
	v.add_child(Ui.label(tr(key), "CapsLabel"))
	v.add_child(Ui.label(value, "BigNumberLabel"))
	v.custom_minimum_size = Vector2(130, 0)
	grid.add_child(v)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("confirm"):
		get_viewport().set_input_as_handled()
		new_game.emit()
	elif event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
		replay_seed.emit()
	elif event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		to_menu.emit()
