class_name BossBar
extends PanelContainer
## Полоса HP босса вверху экрана: имя, HP, щит, отметки фаз.

const T := preload("res://ui/theme/ui_tokens.gd")
const BAR_W: float = 560.0

var _name: Label
var _phase: Label
var _value: Label
var _bar: Control
var _boss_id: int = -1
var _hp: float = 1.0
var _shield: float = 0.0
var _marks: Array = []


func _init() -> void:
	theme_type_variation = "GlassPanel"
	material = Ui.glass_material()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var v: VBoxContainer = Ui.vbox(T.SP_1)
	add_child(v)
	var head: HBoxContainer = Ui.hbox(T.SP_2)
	head.add_child(Ui.icon("boss", 18, T.BOSS.lightened(0.2)))
	_name = Ui.label("", "SubheaderLabel")
	_name.add_theme_color_override("font_color", T.BOSS.lightened(0.35))
	head.add_child(_name)
	_phase = Ui.label("", "CapsLabel")
	head.add_child(_phase)
	head.add_child(Ui.spacer())
	_value = Ui.label("", "NumberLabel")
	head.add_child(_value)
	v.add_child(head)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(BAR_W, 14)
	_bar.draw.connect(_draw_bar)
	v.add_child(_bar)


## Обновление по симуляции: главный из живых боссов — с наибольшим макс. HP (неуязвимый колосс не показывается).
## Не первый вышедший: в финале 62-й Матка Роя выходит раньше Короля и живёт рядом с ним, и полоса
## прятала бы HP, щит и фазы Короля — а на Extreme его утечка означает поражение.
func update_from(sim: GameSim) -> void:
	var boss: EnemyState = null
	for e: EnemyState in sim.enemies:
		if e.alive and e.boss and not e.immortal and (boss == null or e.max_hp > boss.max_hp):
			boss = e
	if boss == null:
		if visible:
			visible = false
		_boss_id = -1
		return
	if boss.id != _boss_id:
		_boss_id = boss.id
		var a: Dictionary = sim.data.archetype(boss.archetype)
		_name.text = TranslationServer.translate(String(a["name_key"]))
		if boss.finale:
			# Финал забега: босс элитный и крепче обычного (waves.json → lengths).
			_name.text = String(TranslationServer.translate("BOSS_FINALE")) % _name.text
		_marks.clear()
		for ph: Variant in boss.phases:
			var at: float = float((ph as Dictionary)["at"])
			if at < 0.999:
				_marks.append(at)
		visible = true
		Ui.pop_in(self, 0.0, Vector2(0, -12))
	_hp = clampf(boss.hp / boss.max_hp, 0.0, 1.0)
	_shield = clampf(boss.shield / boss.max_hp, 0.0, 1.0)
	_phase.text = String(TranslationServer.translate("BOSS_PHASE")) % (boss.phase_index if not boss.phases.is_empty() else 1) if boss.phases.size() > 1 else ""
	_value.text = "%s / %s" % [T.format_number(roundf(boss.hp)), T.format_number(roundf(boss.max_hp))]
	_bar.queue_redraw()


func _draw_bar() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, _bar.size)
	_bar.draw_rect(r, Color(0.04, 0.05, 0.08, 0.9))
	var fill: Rect2 = Rect2(r.position + Vector2(2, 2), Vector2((r.size.x - 4) * _hp, r.size.y - 4))
	_bar.draw_rect(fill, T.BOSS)
	_bar.draw_rect(Rect2(fill.position, Vector2(fill.size.x, fill.size.y * 0.4)), Color(1, 1, 1, 0.18))
	if _shield > 0.0:
		var sw: float = (r.size.x - 4) * minf(_shield, 1.0)
		_bar.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(sw, 4)), Color(0.55, 0.92, 1.0))
	for at: Variant in _marks:
		var x: float = 2.0 + (r.size.x - 4.0) * float(at)
		_bar.draw_line(Vector2(x, 0), Vector2(x, r.size.y), Color(1, 1, 1, 0.85), 2.0)
	_bar.draw_rect(r, Color(1, 1, 1, 0.22), false, 1.0)
