class_name NewGamePanel
extends Modal
## Новая игра: выбор сложности (карточки), длины забега (20 / 42 / 62 волны) и seed (случайный / Seed дня / свой).

var _difficulty: String = "normal"
var _length: int = 62
var _length_btns: Dictionary = {}
var _cards: Dictionary = {}
var _seed_mode: int = 0
var _seed_edit: LineEdit
var _seed_btns: Array[Button] = []
var _tutorial: CheckButton


func _init() -> void:
	super._init()
	var data: GameData = GameData.load_default()
	_difficulty = data.default_difficulty
	header(tr("NG_TITLE"), "gem")
	body.add_child(Ui.label(tr("NG_DIFFICULTY"), "CapsLabel"))
	var row: HBoxContainer = Ui.hbox(T.SP_3)
	for id: String in data.difficulty_order:
		var d: Dictionary = data.difficulty(id)
		var card: Button = Button.new()
		card.toggle_mode = true
		card.custom_minimum_size = Vector2(200, 150)
		card.theme_type_variation = "Button"
		var v: VBoxContainer = Ui.vbox(4)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t: Label = Ui.label(tr(String(d["name_key"])), "SubheaderLabel")
		v.add_child(t)
		var desc: Label = Ui.label(tr(String(d["desc_key"])), "DimLabel", true)
		desc.custom_minimum_size = Vector2(170, 0)
		v.add_child(desc)
		v.add_child(Ui.spacer(false, true))
		var stats: HBoxContainer = Ui.hbox(T.SP_3)
		stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stats.add_child(Ui.icon("heart", 14, T.LIFE))
		stats.add_child(Ui.label(str(int(d["lives"])), "NumberLabel"))
		stats.add_child(Ui.icon("trophy", 14, T.GOLD))
		stats.add_child(Ui.label("×%s" % str(d["score_mult"]), "NumberLabel"))
		v.add_child(stats)
		var m: MarginContainer = Ui.margin(T.SP_3)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(v)
		card.add_child(m)
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		Ui.attach_feedback(card)
		card.pressed.connect(func() -> void: _select(id))
		row.add_child(card)
		_cards[id] = card
	body.add_child(row)
	_build_lengths(data)
	body.add_child(Ui.label(tr("NG_SEED"), "CapsLabel"))
	var seed_row: HBoxContainer = Ui.hbox(T.SP_2)
	var group: ButtonGroup = ButtonGroup.new()
	var modes: Array[String] = ["NG_SEED_RANDOM", "NG_SEED_DAILY", "NG_SEED_CUSTOM"]
	for i: int in modes.size():
		var b: Button = Button.new()
		b.theme_type_variation = "ChipButton"
		b.text = tr(modes[i])
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 36)
		b.button_pressed = i == 0
		Ui.attach_feedback(b)
		b.pressed.connect(func() -> void: _set_seed_mode(i))
		seed_row.add_child(b)
		_seed_btns.append(b)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = tr("NG_SEED_PLACEHOLDER")
	_seed_edit.custom_minimum_size = Vector2(240, 0)
	_seed_edit.editable = false
	_seed_edit.text_submitted.connect(func(_t: String) -> void: _start())
	seed_row.add_child(_seed_edit)
	body.add_child(seed_row)
	var daily: Label = Ui.label(tr("NG_DAILY_HINT") % [Game.today_iso(), RunRng.seed_to_text(RunRng.daily_seed(Game.today_iso()))], "FaintLabel")
	body.add_child(daily)
	_tutorial = CheckButton.new()
	_tutorial.text = tr("NG_TUTORIAL")
	_tutorial.tooltip_text = tr("NG_TUTORIAL_TIP")
	_tutorial.button_pressed = not bool(Settings.get_value("general", "tutorial_done"))
	body.add_child(_tutorial)
	var actions: HBoxContainer = Ui.hbox(T.SP_3)
	actions.alignment = BoxContainer.ALIGNMENT_END
	var cancel: Button = Ui.button(tr("ACT_CANCEL"), "GhostButton")
	cancel.pressed.connect(close)
	actions.add_child(cancel)
	var go: Button = Ui.button(tr("NG_START"), "PrimaryButton", "confirm", "play")
	go.pressed.connect(_start)
	actions.add_child(go)
	body.add_child(actions)
	_select(_difficulty)


## Длина забега: последняя волна — финальная, её боссы усилены (waves.json → lengths); короткий забег
## балансируется своим финалом. В подсказке — кто ждёт в финале.
func _build_lengths(data: GameData) -> void:
	var saved: int = int(Settings.get_value("general", "run_length"))
	_length = saved if data.run_lengths().has(saved) else data.default_run_length()
	body.add_child(Ui.label(tr("NG_LENGTH"), "CapsLabel"))
	var row: HBoxContainer = Ui.hbox(T.SP_2)
	var group: ButtonGroup = ButtonGroup.new()
	for n: int in data.run_lengths():
		var b: Button = Button.new()
		b.theme_type_variation = "ChipButton"
		b.text = tr(T.plural_key("NG_LENGTH_N", n)) % n
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = n == _length
		b.custom_minimum_size = Vector2(120, 36)
		b.tooltip_text = length_tip(data, n)
		Ui.attach_feedback(b)
		b.pressed.connect(func() -> void:
			_length = n
			Settings.set_value("general", "run_length", n))
		row.add_child(b)
		_length_btns[n] = b
	body.add_child(row)


## Подсказка длины: финальные боссы (усиленные — «элитный») и для коротких — что это середина кампании.
## Нестандартная длина (автотест `--waves=5`) — без финала и, возможно, без босса в последней волне.
static func length_tip(data: GameData, n: int) -> String:
	var cfg: Dictionary = data.run_length_cfg(n)
	if cfg.is_empty():
		return String(TranslationServer.translate("NG_LENGTH_TIP_CUSTOM")) % n
	var names: PackedStringArray = PackedStringArray()
	for grp: Dictionary in data.wave(n)["groups"]:
		var a: Dictionary = data.archetype(String(grp["type"]))
		if bool(a.get("boss", false)):
			names.append(TranslationServer.translate(String(a["name_key"])))
	var text: String = String(TranslationServer.translate("NG_LENGTH_TIP")) % [n, ", ".join(names)]
	var notes: String = Ui.finale_notes(data, cfg)
	return text if notes.is_empty() else text + " " + notes


func _select(id: String) -> void:
	_difficulty = id
	for k: String in _cards.keys():
		(_cards[k] as Button).set_pressed_no_signal(k == id)


func _set_seed_mode(i: int) -> void:
	_seed_mode = i
	_seed_edit.editable = i == 2
	if i == 2:
		_seed_edit.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("confirm") and not _seed_edit.has_focus():
		get_viewport().set_input_as_handled()
		_start()
		return
	super._unhandled_input(event)


func _start() -> void:
	if _tutorial.button_pressed:
		Audio.play("sfx/ui/confirm")
		Game.new_run({"tutorial": true})
		return
	var seed_value: int
	var daily: String = ""
	match _seed_mode:
		1:
			daily = Game.today_iso()
			seed_value = RunRng.daily_seed(daily)
		2:
			if _seed_edit.text.strip_edges().is_empty():
				Events.toast_requested.emit(tr("NG_SEED_EMPTY"), "error")
				return
			seed_value = RunRng.seed_from_text(_seed_edit.text)
		_:
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.randomize()
			seed_value = rng.randi()
	Audio.play("sfx/ui/confirm")
	Game.new_run({"seed": seed_value, "difficulty": _difficulty, "daily": daily, "max_waves": _length})
