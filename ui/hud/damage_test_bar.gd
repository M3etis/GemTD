class_name DamageTestBar
extends PanelContainer
## Панель «Испытания урона»: оставшееся время, суммарный урон, текущий и средний DPS, прогресс.

const T := preload("res://ui/theme/ui_tokens.gd")
## Окно для «текущего» DPS, секунд.
const WINDOW: float = 1.0

var _time: Label
var _total: Label
var _dps: Label
var _avg: Label
var _bar: ProgressBar
var _samples: Array[Vector2] = []
var _duration: float = 60.0


func _init() -> void:
	theme_type_variation = "GlassPanel"
	material = Ui.glass_material()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v: VBoxContainer = Ui.vbox(T.SP_2)
	add_child(v)
	var head: HBoxContainer = Ui.hbox(T.SP_2)
	head.add_child(Ui.icon("target", 18, T.DANGER.lightened(0.3)))
	var title: Label = Ui.label(TranslationServer.translate("DT_TITLE"), "CapsLabel")
	title.add_theme_color_override("font_color", T.DANGER.lightened(0.35))
	head.add_child(title)
	head.add_child(Ui.spacer())
	_time = Ui.label("60.0", "NumberLabel")
	head.add_child(_time)
	v.add_child(head)
	var row: HBoxContainer = Ui.hbox(T.SP_6)
	_total = _stat(row, "DT_TOTAL")
	_dps = _stat(row, "DT_CURRENT")
	_avg = _stat(row, "DT_AVERAGE")
	v.add_child(row)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(420, 6)
	_bar.max_value = 1.0
	_bar.step = 0.0
	v.add_child(_bar)


func _stat(row: HBoxContainer, key: String) -> Label:
	var box: VBoxContainer = Ui.vbox(0)
	box.add_child(Ui.label(TranslationServer.translate(key), "CapsLabel"))
	var l: Label = Ui.label("0", "BigNumberLabel")
	box.add_child(l)
	box.custom_minimum_size = Vector2(120, 0)
	row.add_child(box)
	return l


func start(duration: float) -> void:
	_duration = duration
	_samples.clear()
	visible = true
	Ui.pop_in(self, 0.0, Vector2(0, -14))


## Обновление по состоянию симуляции (время испытания и накопленный урон).
func update_from(sim: GameSim) -> void:
	var t: float = sim.wave_time
	var dmg: float = sim.test_damage
	_samples.append(Vector2(t, dmg))
	while _samples.size() > 2 and _samples[0].x < t - WINDOW:
		_samples.remove_at(0)
	var cur: float = 0.0
	if _samples.size() >= 2 and _samples[-1].x > _samples[0].x:
		cur = (_samples[-1].y - _samples[0].y) / (_samples[-1].x - _samples[0].x)
	_time.text = "%.1f" % maxf(_duration - t, 0.0)
	_total.text = T.format_number(roundf(dmg))
	_dps.text = T.format_number(roundf(cur))
	_avg.text = T.format_number(roundf(dmg / maxf(t, 0.001)))
	_bar.value = clampf(t / _duration, 0.0, 1.0)
