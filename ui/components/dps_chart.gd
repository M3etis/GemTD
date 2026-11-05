class_name DpsChart
extends Control
## Столбчатый график DPS по волнам (итоги забега): воздушные волны и боссы подсвечены.

const T := preload("res://ui/theme/ui_tokens.gd")

var values: Array = []
var air_every: int = 4
var boss_waves: Array = []
var _hover: int = -1


func setup(dps: Array, air: int, bosses: Array) -> DpsChart:
	values = dps
	air_every = maxi(air, 1)
	boss_waves = bosses
	custom_minimum_size = Vector2(560, 110)
	mouse_filter = Control.MOUSE_FILTER_PASS
	return self


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not values.is_empty():
		var w: float = size.x / float(values.size())
		var i: int = clampi(int((event as InputEventMouseMotion).position.x / w), 0, values.size() - 1)
		if i != _hover:
			_hover = i
			tooltip_text = String(tr("RESULT_DPS_TIP")) % [i + 1, T.format_number(float(values[i]))]
			queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.03))
	if values.is_empty():
		return
	var peak: float = 1.0
	for v: Variant in values:
		peak = maxf(peak, float(v))
	var n: int = values.size()
	var w: float = size.x / float(n)
	for i: int in n:
		var wave: int = i + 1
		var h: float = (size.y - 14.0) * float(values[i]) / peak
		var col: Color = T.ACCENT
		if boss_waves.has(float(wave)) or boss_waves.has(wave):
			col = T.BOSS
		elif wave % air_every == 0:
			col = T.AIR
		if i == _hover:
			col = col.lightened(0.35)
		draw_rect(Rect2(Vector2(float(i) * w + 1.0, size.y - 12.0 - h), Vector2(maxf(w - 2.0, 1.0), h)), col)
		if wave % 5 == 0 or wave == 1:
			draw_string(T.font("num"), Vector2(float(i) * w, size.y), str(wave), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, T.TEXT_FAINT)
