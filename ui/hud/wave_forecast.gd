class_name WaveForecast
extends PanelContainer
## Прогноз волн (Tab): три ближайшие волны — тип, состав, элита и трейты.

const T := preload("res://ui/theme/ui_tokens.gd")
const COUNT: int = 3

var _col: VBoxContainer


func _init() -> void:
	theme_type_variation = "GlassPanel"
	material = Ui.glass_material()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_col = Ui.vbox(T.SP_3)
	add_child(_col)


## finale — усиление боссов последней волны total (GameSim.finale_for), {} — без него.
func toggle(data: GameData, from_wave: int, total: int, diff: Dictionary, finale: Dictionary = {}) -> void:
	visible = not visible
	if not visible:
		Audio.play("sfx/ui/panel_close")
		return
	for c: Node in _col.get_children():
		c.queue_free()
	var head: HBoxContainer = Ui.hbox(T.SP_2)
	head.add_child(Ui.label(tr("FORECAST_TITLE"), "CapsLabel"))
	head.add_child(Ui.spacer())
	head.add_child(Ui.hotkey("forecast"))
	_col.add_child(head)
	for n: int in range(from_wave, mini(from_wave + COUNT, total + 1)):
		_col.add_child(_wave_block(data, WaveSpawner.summary(data, n, finale if n == total else {}), data.difficulty_hp_mult(diff, n)))
	Ui.pop_in(self, 0.0, Vector2(14, 0))
	Audio.play("sfx/ui/panel_open")


func _wave_block(data: GameData, s: Dictionary, hp_mult: float) -> VBoxContainer:
	var v: VBoxContainer = Ui.vbox(4)
	var air: bool = bool(s["air"])
	var boss: bool = bool(s["boss"])
	var title: HBoxContainer = Ui.hbox(T.SP_2)
	title.add_child(Ui.icon("boss" if boss else ("air" if air else "ground"), 16, T.BOSS if boss else (T.AIR if air else T.TEXT_DIM)))
	title.add_child(Ui.label(tr("WAVE_N") % int(s["wave"]), "SubheaderLabel"))
	title.add_child(Ui.spacer())
	title.add_child(Ui.label(tr("WAVE_HP") % T.format_number(float(s["base_hp"]) * hp_mult), "FaintLabel"))
	v.add_child(title)
	for grp: Dictionary in s["groups"]:
		var a: Dictionary = data.archetypes[grp["type"]]
		var row: HBoxContainer = Ui.hbox(T.SP_2)
		row.add_child(Ui.label("×%d" % int(grp["count"]), "NumberLabel"))
		row.add_child(Ui.label(tr(String(a["name_key"])), "BodyLabel"))
		if bool(grp.get("elite", false)):
			var el: Label = Ui.label(tr("WAVE_ELITE"), "CapsLabel")
			el.add_theme_color_override("font_color", T.GOLD)
			row.add_child(el)
		v.add_child(row)
	var traits: Array = s["traits"]
	if not traits.is_empty():
		var flow: HFlowContainer = HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 4)
		flow.custom_minimum_size = Vector2(300, 0)
		for t: Variant in traits:
			flow.add_child(WavePanel._trait_chip(data, String(t)))
		v.add_child(flow)
	return v
