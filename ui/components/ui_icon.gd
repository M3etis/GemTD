class_name UiIcon
extends Control
## Иконки интерфейса: набор Lucide (ISC, assets/ui/icons, единая линия 1.75 на сетке 24),
## растеризуется из SVG под фактический размер, поэтому чёткий при любом масштабе UI.
## Имена без файла рисуются запасными векторными фигурами ниже.

const ICON_DIR: String = "res://assets/ui/icons/ui_icon_%s.svg"
## Синонимы имён (данные и экраны используют оба варианта).
const ALIASES: Dictionary = {"luck": "sparkle", "air": "wing", "boss": "crown", "armored": "shield", "rush": "bolt",
	"ground": "foot", "damage": "swords", "range": "target"}

static var _sources: Dictionary = {}
static var _sized: Dictionary = {}

var icon_name: String = "dot":
	set(v):
		icon_name = v
		queue_redraw()
var color: Color = Color.WHITE:
	set(v):
		color = v
		queue_redraw()


## SVG иконки, растеризованный под размер px (кэш по имени и размеру).
static func lucide(name: String, px: float) -> Texture2D:
	var id: String = String(ALIASES.get(name, name))
	if not _sources.has(id):
		var path: String = ICON_DIR % id
		var src: String = ""
		if ResourceLoader.exists(path):
			var t: DPITexture = load(path) as DPITexture
			if t != null:
				src = t.get_source()
		_sources[id] = src
	if String(_sources[id]).is_empty():
		return null
	var key: String = "%s@%d" % [id, roundi(px)]
	if not _sized.has(key):
		_sized[key] = DPITexture.create_from_string(String(_sources[id]), maxf(px, 4.0) / 24.0)
	return _sized[key]


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	var o: Vector2 = (size - Vector2(s, s)) * 0.5
	var tex: Texture2D = lucide(icon_name, s)
	if tex != null:
		draw_texture_rect(tex, Rect2(o, Vector2(s, s)), false, color)
		return
	var w: float = maxf(1.5, s * 0.1)
	match icon_name:
		"heart":
			var pts: PackedVector2Array = PackedVector2Array()
			for i: int in 40:
				var t: float = TAU * float(i) / 40.0
				var x: float = 16.0 * pow(sin(t), 3.0)
				var y: float = 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
				pts.append(o + Vector2(0.5 + x / 36.0, 0.47 - y / 36.0) * s)
			draw_colored_polygon(pts, color)
		"coin":
			draw_circle(o + Vector2(0.5, 0.5) * s, s * 0.44, color)
			draw_circle(o + Vector2(0.5, 0.5) * s, s * 0.3, color.darkened(0.35))
			_poly(o, s, [Vector2(0.5, 0.3), Vector2(0.66, 0.5), Vector2(0.5, 0.7), Vector2(0.34, 0.5)], color.lightened(0.2))
		"gem":
			_poly(o, s, [Vector2(0.25, 0.18), Vector2(0.75, 0.18), Vector2(0.94, 0.4), Vector2(0.5, 0.9), Vector2(0.06, 0.4)], color)
			draw_polyline(_pts(o, s, [Vector2(0.06, 0.4), Vector2(0.94, 0.4)]), color.darkened(0.4), w * 0.6)
			draw_polyline(_pts(o, s, [Vector2(0.35, 0.4), Vector2(0.5, 0.9), Vector2(0.65, 0.4)]), color.darkened(0.3), w * 0.5)
		"luck", "sparkle":
			_poly(o, s, [Vector2(0.5, 0.04), Vector2(0.6, 0.4), Vector2(0.96, 0.5), Vector2(0.6, 0.6), Vector2(0.5, 0.96), Vector2(0.4, 0.6), Vector2(0.04, 0.5), Vector2(0.4, 0.4)], color)
		"pause":
			draw_rect(Rect2(o + Vector2(0.22, 0.18) * s, Vector2(0.18, 0.64) * s), color)
			draw_rect(Rect2(o + Vector2(0.6, 0.18) * s, Vector2(0.18, 0.64) * s), color)
		"play":
			_poly(o, s, [Vector2(0.28, 0.16), Vector2(0.84, 0.5), Vector2(0.28, 0.84)], color)
		"back":
			_poly(o, s, [Vector2(0.9, 0.2), Vector2(0.5, 0.5), Vector2(0.9, 0.8)], color)
			_poly(o, s, [Vector2(0.5, 0.2), Vector2(0.1, 0.5), Vector2(0.5, 0.8)], color)
		"fast":
			_poly(o, s, [Vector2(0.1, 0.2), Vector2(0.5, 0.5), Vector2(0.1, 0.8)], color)
			_poly(o, s, [Vector2(0.5, 0.2), Vector2(0.9, 0.5), Vector2(0.5, 0.8)], color)
		"clock":
			draw_arc(o + Vector2(0.5, 0.5) * s, s * 0.4, 0.0, TAU, 32, color, w)
			draw_polyline(_pts(o, s, [Vector2(0.5, 0.25), Vector2(0.5, 0.5), Vector2(0.68, 0.6)]), color, w)
		"copy":
			draw_rect(Rect2(o + Vector2(0.3, 0.3) * s, Vector2(0.55, 0.55) * s), color, false, w)
			draw_polyline(_pts(o, s, [Vector2(0.15, 0.68), Vector2(0.15, 0.15), Vector2(0.68, 0.15)]), color, w)
		"gear":
			var c: Vector2 = o + Vector2(0.5, 0.5) * s
			var pts2: PackedVector2Array = PackedVector2Array()
			for i: int in 32:
				var a: float = TAU * float(i) / 32.0
				var r: float = s * (0.46 if (i >> 1) % 2 == 0 else 0.34)
				pts2.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts2, color)
			draw_circle(c, s * 0.15, color.darkened(0.6))
		"trophy":
			_poly(o, s, [Vector2(0.22, 0.12), Vector2(0.78, 0.12), Vector2(0.72, 0.45), Vector2(0.56, 0.58), Vector2(0.56, 0.74), Vector2(0.7, 0.88), Vector2(0.3, 0.88), Vector2(0.44, 0.74), Vector2(0.44, 0.58), Vector2(0.28, 0.45)], color)
			draw_arc(o + Vector2(0.2, 0.28) * s, s * 0.12, PI * 0.5, PI * 1.5, 12, color, w * 0.8)
			draw_arc(o + Vector2(0.8, 0.28) * s, s * 0.12, -PI * 0.5, PI * 0.5, 12, color, w * 0.8)
		"close":
			draw_line(o + Vector2(0.22, 0.22) * s, o + Vector2(0.78, 0.78) * s, color, w * 1.2, true)
			draw_line(o + Vector2(0.78, 0.22) * s, o + Vector2(0.22, 0.78) * s, color, w * 1.2, true)
		"wing", "air":
			_poly(o, s, [Vector2(0.08, 0.62), Vector2(0.45, 0.3), Vector2(0.92, 0.18), Vector2(0.7, 0.42), Vector2(0.86, 0.44), Vector2(0.6, 0.6), Vector2(0.74, 0.64), Vector2(0.4, 0.74)], color)
		"crown", "boss":
			_poly(o, s, [Vector2(0.1, 0.78), Vector2(0.1, 0.3), Vector2(0.32, 0.52), Vector2(0.5, 0.18), Vector2(0.68, 0.52), Vector2(0.9, 0.3), Vector2(0.9, 0.78)], color)
		"shield", "armored":
			_poly(o, s, [Vector2(0.5, 0.08), Vector2(0.86, 0.22), Vector2(0.8, 0.6), Vector2(0.5, 0.92), Vector2(0.2, 0.6), Vector2(0.14, 0.22)], color)
		"bolt", "rush":
			_poly(o, s, [Vector2(0.58, 0.04), Vector2(0.2, 0.56), Vector2(0.46, 0.56), Vector2(0.38, 0.96), Vector2(0.8, 0.42), Vector2(0.54, 0.42)], color)
		"swarm":
			for p: Vector2 in [Vector2(0.3, 0.38), Vector2(0.68, 0.32), Vector2(0.5, 0.7), Vector2(0.22, 0.72), Vector2(0.8, 0.68)]:
				draw_circle(o + p * s, s * 0.11, color)
		"ground", "foot":
			draw_rect(Rect2(o + Vector2(0.1, 0.7) * s, Vector2(0.8, 0.12) * s), color)
			_poly(o, s, [Vector2(0.3, 0.66), Vector2(0.5, 0.2), Vector2(0.7, 0.66)], color)
		"check":
			draw_polyline(_pts(o, s, [Vector2(0.16, 0.52), Vector2(0.4, 0.76), Vector2(0.86, 0.26)]), color, w * 1.3, true)
		"arrow_up":
			_poly(o, s, [Vector2(0.5, 0.1), Vector2(0.85, 0.5), Vector2(0.62, 0.5), Vector2(0.62, 0.9), Vector2(0.38, 0.9), Vector2(0.38, 0.5), Vector2(0.15, 0.5)], color)
		"arrow_down":
			_poly(o, s, [Vector2(0.5, 0.9), Vector2(0.15, 0.5), Vector2(0.38, 0.5), Vector2(0.38, 0.1), Vector2(0.62, 0.1), Vector2(0.62, 0.5), Vector2(0.85, 0.5)], color)
		"path":
			draw_polyline(_pts(o, s, [Vector2(0.1, 0.85), Vector2(0.1, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 0.15), Vector2(0.9, 0.15)]), color, w, true)
			draw_circle(o + Vector2(0.9, 0.15) * s, s * 0.09, color)
		"skull":
			draw_circle(o + Vector2(0.5, 0.44) * s, s * 0.34, color)
			draw_rect(Rect2(o + Vector2(0.32, 0.6) * s, Vector2(0.36, 0.26) * s), color)
			draw_circle(o + Vector2(0.38, 0.44) * s, s * 0.08, color.darkened(0.8))
			draw_circle(o + Vector2(0.62, 0.44) * s, s * 0.08, color.darkened(0.8))
		"sound":
			_poly(o, s, [Vector2(0.1, 0.38), Vector2(0.3, 0.38), Vector2(0.55, 0.15), Vector2(0.55, 0.85), Vector2(0.3, 0.62), Vector2(0.1, 0.62)], color)
			draw_arc(o + Vector2(0.55, 0.5) * s, s * 0.2, -0.9, 0.9, 10, color, w * 0.8)
			draw_arc(o + Vector2(0.55, 0.5) * s, s * 0.34, -0.9, 0.9, 12, color, w * 0.8)
		"swords", "damage":
			draw_line(o + Vector2(0.15, 0.15) * s, o + Vector2(0.85, 0.85) * s, color, w * 1.2, true)
			draw_line(o + Vector2(0.85, 0.15) * s, o + Vector2(0.15, 0.85) * s, color, w * 1.2, true)
			draw_line(o + Vector2(0.62, 0.78) * s, o + Vector2(0.78, 0.62) * s, color, w * 1.4, true)
			draw_line(o + Vector2(0.22, 0.62) * s, o + Vector2(0.38, 0.78) * s, color, w * 1.4, true)
		"target", "range":
			draw_arc(o + Vector2(0.5, 0.5) * s, s * 0.4, 0.0, TAU, 32, color, w * 0.8)
			draw_arc(o + Vector2(0.5, 0.5) * s, s * 0.2, 0.0, TAU, 24, color, w * 0.8)
			draw_circle(o + Vector2(0.5, 0.5) * s, s * 0.06, color)
		"speed":
			draw_arc(o + Vector2(0.5, 0.62) * s, s * 0.38, PI, TAU, 24, color, w)
			draw_line(o + Vector2(0.5, 0.62) * s, o + Vector2(0.74, 0.36) * s, color, w, true)
		"info":
			draw_arc(o + Vector2(0.5, 0.5) * s, s * 0.42, 0.0, TAU, 32, color, w * 0.8)
			draw_rect(Rect2(o + Vector2(0.45, 0.42) * s, Vector2(0.1, 0.32) * s), color)
			draw_circle(o + Vector2(0.5, 0.3) * s, s * 0.06, color)
		"flame":
			# Язык пламени: широкое основание, острая вершина, тёмная сердцевина.
			var flame: PackedVector2Array = PackedVector2Array([o + Vector2(0.5, 0.08) * s, o + Vector2(0.72, 0.45) * s, o + Vector2(0.78, 0.66) * s,
				o + Vector2(0.66, 0.86) * s, o + Vector2(0.5, 0.92) * s, o + Vector2(0.34, 0.86) * s, o + Vector2(0.22, 0.66) * s,
				o + Vector2(0.3, 0.42) * s, o + Vector2(0.4, 0.55) * s])
			draw_colored_polygon(flame, color)
			draw_circle(o + Vector2(0.5, 0.72) * s, s * 0.12, color.darkened(0.4))
		"snowflake":
			for k2: int in 3:
				var a2: float = PI * float(k2) / 3.0
				var d: Vector2 = Vector2(cos(a2), sin(a2)) * s * 0.4
				draw_line(o + Vector2(0.5, 0.5) * s - d, o + Vector2(0.5, 0.5) * s + d, color, w, true)
			draw_circle(o + Vector2(0.5, 0.5) * s, s * 0.08, color)
		"leaf":
			var leaf: PackedVector2Array = PackedVector2Array()
			for k3: int in 20:
				var t3: float = TAU * float(k3) / 20.0
				leaf.append(o + Vector2(0.5 + 0.22 * sin(t3), 0.5 - 0.38 * cos(t3)) * s)
			var rot: Transform2D = Transform2D(0.6, o + Vector2(0.5, 0.5) * s)
			var rotated: PackedVector2Array = PackedVector2Array()
			for p: Vector2 in leaf:
				rotated.append(rot * (p - o - Vector2(0.5, 0.5) * s))
			draw_colored_polygon(rotated, color)
			draw_line(o + Vector2(0.3, 0.78) * s, o + Vector2(0.66, 0.26) * s, color.darkened(0.45), maxf(1.0, w * 0.6), true)
		_:
			draw_circle(o + Vector2(0.5, 0.5) * s, s * 0.25, color)


func _pts(o: Vector2, s: float, unit: Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in unit:
		out.append(o + p * s)
	return out


func _poly(o: Vector2, s: float, unit: Array, c: Color) -> void:
	draw_colored_polygon(_pts(o, s, unit), c)
