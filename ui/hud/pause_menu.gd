class_name PauseMenu
extends Modal
## Пауза: продолжить, сохранить, настройки, рестарт, выход в меню.

signal restart
signal quit_to_menu
signal save_pressed


func _init() -> void:
	super._init()


func setup(can_save: bool, race_mode: bool = false) -> PauseMenu:
	header(tr("MP_MENU_TITLE") if race_mode else tr("PAUSE_TITLE"), "pause")
	var col: VBoxContainer = Ui.vbox(T.SP_2)
	col.custom_minimum_size = Vector2(360, 0)
	var cont: Button = Ui.button(tr("ACT_RESUME"), "PrimaryButton", "menu", "play")
	cont.pressed.connect(close)
	col.add_child(cont)
	if not race_mode:
		var save: Button = Ui.button(tr("ACT_SAVE_GAME"), "Button", "", "copy")
		save.disabled = not can_save
		save.tooltip_text = "" if can_save else tr("TP_BUILD_ONLY")
		save.pressed.connect(func() -> void: save_pressed.emit())
		col.add_child(save)
	var settings: Button = Ui.button(tr("MENU_SETTINGS"), "Button", "", "gear")
	settings.pressed.connect(func() -> void: get_parent().add_child(SettingsPanel.new()))
	col.add_child(settings)
	if not race_mode:
		var rst: Button = Ui.button(tr("ACT_RESTART"), "Button", "restart", "arrow_up")
		rst.pressed.connect(func() -> void:
			Modal.confirm(get_parent(), tr("CONFIRM_RESTART_TITLE"), tr("CONFIRM_RESTART_TEXT"), tr("ACT_RESTART"), func() -> void: restart.emit()))
		col.add_child(rst)
	var quit: Button = Ui.button(tr("MP_LEAVE") if race_mode else tr("ACT_TO_MENU"), "GhostButton", "", "close")
	quit.pressed.connect(func() -> void:
		Modal.confirm(get_parent(), tr("MP_LEAVE_TITLE") if race_mode else tr("CONFIRM_QUIT_TITLE"), tr("MP_LEAVE_TEXT") if race_mode else tr("CONFIRM_QUIT_TEXT_SAVE"), tr("MP_LEAVE") if race_mode else tr("ACT_TO_MENU"), func() -> void: quit_to_menu.emit()))
	col.add_child(quit)
	body.add_child(col)
	cont.grab_focus.call_deferred()
	return self
