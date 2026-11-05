class_name Tutorial
extends RefCounted
## Обучение (§8.5 PROMPT.md): три интерактивных раунда — установка камней и Keep, Combine, рецепт.
## Выпадение гемов первых раундов задаётся заранее (GameSim.config.draft_overrides), поэтому шаги
## всегда выполнимы. Шаги переключаются по событиям симуляции; обучение можно пропустить.

const T := preload("res://ui/theme/ui_tokens.gd")
## Гемы раундов обучения: 2 — пара рубинов для Combine, 3 — полный рецепт Венца Пепла.
const DRAFTS: Dictionary = {
	"1": [["amethyst", 1], ["ruby", 1], ["diamond", 1], ["sapphire", 1], ["topaz", 1]],
	"2": [["ruby", 1], ["ruby", 1], ["diamond", 1], ["opal", 1], ["sapphire", 1]],
	"3": [["ruby", 1], ["topaz", 1], ["emerald", 1], ["aquamarine", 1], ["amethyst", 1]],
}
## Шаги: текст, событие, которое завершает шаг, подсвечиваемая кнопка выбора.
const STEPS: Array[Dictionary] = [
	{"key": "TUT_PLACE", "until": "choice_ready"},
	{"key": "TUT_KEEP", "until": "ready_for_wave", "highlight": "keep"},
	{"key": "TUT_START", "until": "wave_started"},
	{"key": "TUT_WATCH", "until": "round_started"},
	{"key": "TUT_PLACE2", "until": "choice_ready"},
	{"key": "TUT_COMBINE", "until": "ready_for_wave", "highlight": "combine2"},
	{"key": "TUT_START", "until": "wave_started"},
	{"key": "TUT_WATCH2", "until": "round_started"},
	{"key": "TUT_PLACE3", "until": "choice_ready"},
	{"key": "TUT_FORGE", "until": "ready_for_wave", "highlight": "forge"},
	{"key": "TUT_START", "until": "wave_started"},
	{"key": "TUT_LAST", "until": "wave_cleared"},
]

var game: Node
var step: int = 0
var active: bool = true
var _card: PanelContainer
var _text: Label
var _progress: Label


func _init(g: Node) -> void:
	game = g
	var hud: Hud = g.hud
	_card = PanelContainer.new()
	_card.theme_type_variation = "GlassPanel"
	_card.material = Ui.glass_material()
	var v: VBoxContainer = Ui.vbox(T.SP_2)
	var head: HBoxContainer = Ui.hbox(T.SP_2)
	head.add_child(Ui.icon("info", 18, T.ACCENT))
	head.add_child(Ui.label(TranslationServer.translate("TUT_TITLE"), "CapsLabel"))
	head.add_child(Ui.spacer())
	_progress = Ui.label("", "FaintLabel")
	head.add_child(_progress)
	v.add_child(head)
	_text = Ui.label("", "BodyLabel", true)
	_text.custom_minimum_size = Vector2(380, 0)
	v.add_child(_text)
	var skip: Button = Ui.button(TranslationServer.translate("TUT_SKIP"), "GhostButton", "", "close")
	skip.size_flags_horizontal = Control.SIZE_SHRINK_END
	skip.pressed.connect(func() -> void: finish(false))
	v.add_child(skip)
	_card.add_child(v)
	hud.add_child(_card)
	_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_card.offset_left = Hud.MARGIN
	_card.offset_top = 104
	_show()


static func config() -> Dictionary:
	return {"seed": 7700, "difficulty": "easy", "tutorial": true, "draft_overrides": DRAFTS}


func on_event(e: Dictionary) -> void:
	if not active:
		return
	var type: String = String(e["type"])
	var cur: Dictionary = STEPS[step]
	if type == "gem_kept" and cur.get("highlight", "") != "keep" and step < STEPS.size():
		# Игрок выбрал Keep вместо подсказанного действия — не блокируем обучение.
		Events.toast_requested.emit(TranslationServer.translate("TUT_OTHER_CHOICE"), "info")
	if type == String(cur["until"]):
		step += 1
		if step >= STEPS.size():
			finish(true)
			return
		_show()


## Подсвечиваемая кнопка текущего шага (id действия выбора или префикс "forge").
func highlight() -> String:
	return String(STEPS[step].get("highlight", "")) if active and step < STEPS.size() else ""


func _show() -> void:
	_text.text = TranslationServer.translate(String(STEPS[step]["key"]))
	_progress.text = "%d / %d" % [step + 1, STEPS.size()]
	Ui.pop_in(_card, 0.0, Vector2(-12, 0))
	Audio.play("sfx/ui/toast")


func finish(completed: bool) -> void:
	if not active:
		return
	active = false
	Settings.set_value("general", "tutorial_done", true)
	_card.queue_free()
	if not completed:
		Events.toast_requested.emit(TranslationServer.translate("TUT_SKIPPED"), "info")
		return
	var m: Modal = Modal.new()
	m.header(TranslationServer.translate("TUT_DONE_TITLE"), "check")
	var l: Label = Ui.label(TranslationServer.translate("TUT_DONE_TEXT"), "BodyLabel", true)
	l.custom_minimum_size = Vector2(460, 0)
	m.body.add_child(l)
	var row: HBoxContainer = Ui.hbox(T.SP_3)
	row.alignment = BoxContainer.ALIGNMENT_END
	var menu: Button = Ui.button(TranslationServer.translate("ACT_TO_MENU"), "GhostButton", "", "close")
	menu.pressed.connect(func() -> void:
		Audio.stop_loop("ambience/arena")
		Game.goto_scene("menu"))
	row.add_child(menu)
	var keep: Button = Ui.button(TranslationServer.translate("TUT_CONTINUE"), "Button", "", "play")
	keep.pressed.connect(m.close)
	row.add_child(keep)
	var real: Button = Ui.button(TranslationServer.translate("TUT_REAL_GAME"), "PrimaryButton", "", "gem")
	real.pressed.connect(func() -> void:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.randomize()
		Game.new_run({"seed": rng.randi(), "difficulty": "normal"}))
	row.add_child(real)
	m.body.add_child(row)
	(game.ui_layer as CanvasLayer).add_child(m)
	Audio.play("sfx/game/new_record")
