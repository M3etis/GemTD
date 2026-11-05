class_name ReplayController
extends RefCounted
## Просмотр реплея в игровой сцене: команды применяются в свой тик, скорость 1–8×,
## переход к любой волне (быстрая пересимуляция до старта волны), пауза.

const T := preload("res://ui/theme/ui_tokens.gd")
const BUILD_DELAY: float = 0.35
const SPEEDS: Array[int] = [1, 2, 4, 8]

var game: Node
var replay: Dictionary
var record: Dictionary
var commands: Array = []
var index: int = 0
var speed: int = 1
var paused: bool = false
var _build_timer: float = 0.0
var _acc: float = 0.0
var _bar: PanelContainer
var _wave_label: Label
var _play_icon: UiIcon
var _speed_btns: Array[Button] = []
var _done_shown: bool = false


func _init(g: Node, rep: Dictionary, rec: Dictionary) -> void:
	game = g
	replay = rep
	record = rec
	commands = rep.get("commands", [])


static func make_sim(data: GameData, rep: Dictionary) -> GameSim:
	var sim: GameSim = GameSim.new(data, {"seed": int(rep["seed"]), "difficulty": String(rep["difficulty"]),
		"map": String(rep["map"]), "max_waves": int(rep["max_waves"]), "endless": bool(rep.get("endless", false))})
	sim.start()
	return sim


func build_ui(hud: Hud) -> void:
	hud.phase.hide_all()
	_bar = Ui.panel("GlassPanel")
	hud.add_child(_bar)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bar.offset_bottom = -Hud.MARGIN
	var row: HBoxContainer = Ui.hbox(T.SP_4)
	_bar.add_child(row)
	var info: VBoxContainer = Ui.vbox(0)
	info.add_child(Ui.label(tr_("REPLAY_TITLE"), "CapsLabel"))
	var who: String = String(record.get("name", "")) if not record.is_empty() else ""
	info.add_child(Ui.label("%s · seed %s" % [who, RunRng.seed_to_text(int(replay["seed"]))] if not who.is_empty() else "seed %s" % RunRng.seed_to_text(int(replay["seed"])), "SubheaderLabel"))
	row.add_child(info)
	var play: Button = Ui.icon_button("pause", 16, "ChipButton", Vector2(44, 36))
	_play_icon = play.get_child(0).get_child(0) as UiIcon
	play.tooltip_text = tr_("REPLAY_PLAY_TIP")
	play.pressed.connect(toggle_pause)
	row.add_child(play)
	var speeds: HBoxContainer = Ui.hbox(4)
	var group: ButtonGroup = ButtonGroup.new()
	for s: int in SPEEDS:
		var b: Button = Button.new()
		b.theme_type_variation = "ChipButton"
		b.text = "%d×" % s
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = s == speed
		b.custom_minimum_size = Vector2(44, 36)
		Ui.attach_feedback(b)
		b.pressed.connect(func() -> void: speed = s)
		speeds.add_child(b)
		_speed_btns.append(b)
	row.add_child(speeds)
	var prev: Button = Ui.icon_button("back", 14, "ChipButton", Vector2(40, 36))
	prev.tooltip_text = tr_("REPLAY_PREV")
	prev.pressed.connect(func() -> void: jump_to_wave(maxi(1, _current_wave() - 1)))
	row.add_child(prev)
	_wave_label = Ui.label("", "NumberLabel")
	_wave_label.custom_minimum_size = Vector2(110, 0)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_wave_label)
	var next: Button = Ui.icon_button("fast", 14, "ChipButton", Vector2(40, 36))
	next.tooltip_text = tr_("REPLAY_NEXT")
	next.pressed.connect(func() -> void: jump_to_wave(_current_wave() + 1))
	row.add_child(next)
	var exit: Button = Ui.button(tr_("REPLAY_EXIT"), "GhostButton", "menu", "close")
	exit.pressed.connect(_exit)
	row.add_child(exit)
	_refresh()


static func tr_(key: String) -> String:
	return String(TranslationServer.translate(key))


func toggle_pause() -> void:
	paused = not paused
	_play_icon.icon_name = "play" if paused else "pause"


func set_speed_index(delta: int) -> void:
	var i: int = clampi(SPEEDS.find(speed) + delta, 0, SPEEDS.size() - 1)
	speed = SPEEDS[i]
	for b: Button in _speed_btns:
		b.set_pressed_no_signal(b.text == "%d×" % speed)


## Один кадр воспроизведения. Возвращает alpha для интерполяции визуала.
func update(delta: float) -> float:
	var sim: GameSim = game.sim
	if paused or sim.is_over() and index >= commands.size():
		if sim.is_over() and not _done_shown:
			_done_shown = true
			_show_done()
		return 1.0
	if sim.phase == GameSim.Phase.COMBAT:
		_acc += delta * float(speed)
		var steps: int = 0
		while _acc >= sim.dt and steps < 400 and sim.phase == GameSim.Phase.COMBAT:
			if index < commands.size() and int((commands[index] as Dictionary)["tick"]) <= sim.tick:
				_apply_next()
				continue
			sim.step()
			_acc -= sim.dt
			steps += 1
		_refresh()
		return clampf(_acc / sim.dt, 0.0, 1.0)
	_acc = 0.0
	_build_timer -= delta * float(speed)
	if _build_timer <= 0.0 and index < commands.size():
		_build_timer = BUILD_DELAY
		_apply_next()
		_refresh()
	return 1.0


func _apply_next() -> void:
	var cmd: Dictionary = commands[index]
	index += 1
	var res: Dictionary = (game.sim as GameSim).apply(cmd)
	if not res["ok"]:
		push_warning("Реплей: команда %s отклонена (%s)" % [cmd["type"], res["reason"]])


func _current_wave() -> int:
	var sim: GameSim = game.sim
	return sim.next_wave_number()


## Перемотка: быстрая пересимуляция до момента перед стартом волны n.
func jump_to_wave(n: int) -> void:
	var target: int = Replay.start_wave_index(replay, n)
	if target < 0:
		return
	var sim: GameSim = Replay.resimulate_until_command(game.data, replay, target)
	sim.drain_events()
	sim.record_events = true
	index = target
	_build_timer = 0.6
	_done_shown = false
	game.replace_sim(sim)
	_refresh()


func _refresh() -> void:
	if _wave_label == null:
		return
	var sim: GameSim = game.sim
	_wave_label.text = tr_("REPLAY_WAVE") % T.wave_fraction(_current_wave(), sim.total_waves)


func _show_done() -> void:
	var m: Modal = Modal.new()
	m.header(tr_("REPLAY_DONE"), "check")
	var sim: GameSim = game.sim
	var s: Dictionary = sim.summary()
	var l: Label = Ui.label(tr_("REPLAY_DONE_TEXT") % [T.wave_fraction(int(s["waves_cleared"]), int(s["total_waves"])), Scoring.compute(sim.data, s)], "BodyLabel", true)
	l.custom_minimum_size = Vector2(420, 0)
	m.body.add_child(l)
	var row: HBoxContainer = Ui.hbox(T.SP_3)
	row.alignment = BoxContainer.ALIGNMENT_END
	var again: Button = Ui.button(tr_("REPLAY_AGAIN"), "Button", "", "arrow_up")
	again.pressed.connect(func() -> void:
		m.close()
		jump_to_wave(1))
	row.add_child(again)
	var out: Button = Ui.button(tr_("REPLAY_EXIT"), "PrimaryButton", "", "close")
	out.pressed.connect(_exit)
	row.add_child(out)
	m.body.add_child(row)
	(game.ui_layer as CanvasLayer).add_child(m)


func _exit() -> void:
	Audio.stop_loop("ambience/arena")
	Game.goto_scene("menu")
