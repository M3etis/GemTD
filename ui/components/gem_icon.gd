class_name GemIcon
extends Control
## 2D-иконка гема: вид сверху той же огранки, что у 3D-гема (ArtKit.GEM_CUTS) — площадка, грани короны
## со светом сверху-слева, у изумруда ступени, у опала гладкий купол; свечение и блик — по качеству.

var gem_id: String = "ruby":
	set(v):
		gem_id = v
		queue_redraw()
var quality: int = 1:
	set(v):
		quality = v
		queue_redraw()
var glow: bool = true
## Если задан — рисуется эмблема спец-башни вместо гема; quality тогда = уровень (1..3).
var special_id: String = "":
	set(v):
		special_id = v
		queue_redraw()
## Если задан — рисуется плита слейта (data/slates.json): ромб с руной, у составного — двойная рамка.
var slate_id: String = "":
	set(v):
		slate_id = v
		queue_redraw()


func _draw() -> void:
	if not slate_id.is_empty():
		_draw_slate()
		return
	if not special_id.is_empty():
		_draw_special()
		return
	var s: float = minf(size.x, size.y)
	var c: Vector2 = size * 0.5
	var col: Color = UiTokens.gem_color(gem_id)
	if glow:
		var layers: int = 6
		for i: int in layers:
			var k: float = float(layers - i) / float(layers)
			draw_circle(c, s * (0.3 + 0.24 * k), Color(col, 0.035 * float(quality + 1) * (1.0 - k * 0.6)))
	var cut: String = String(ArtKit.GEM_CUTS.get(gem_id, "gem_cut_round")).trim_prefix("gem_cut_")
	var r: float = s * 0.5 * (0.78 + 0.05 * float(quality))
	var girdle: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in cut_outline(cut):
		girdle.append(c + p * r)
	match cut:
		"cabochon":
			_draw_dome(girdle, c, col)
		"emerald":
			_draw_steps(girdle, c, col)
		_:
			_draw_facets(girdle, c, col, cut == "round")
	var outline: PackedVector2Array = girdle.duplicate()
	outline.append(girdle[0])
	draw_polyline(outline, col.lightened(0.5), maxf(1.0, s * 0.022), true)
	# Блик полировки: у качества IV–V — звёздочка искры.
	var hl: Vector2 = c + Vector2(-0.3, -0.34) * r
	draw_circle(hl, s * 0.045, Color(1, 1, 1, 0.6))
	if quality >= 4:
		var k2: float = s * (0.09 + 0.03 * float(quality - 4))
		draw_line(hl - Vector2(k2, 0), hl + Vector2(k2, 0), Color(1, 1, 1, 0.75), maxf(1.0, s * 0.012), true)
		draw_line(hl - Vector2(0, k2), hl + Vector2(0, k2), Color(1, 1, 1, 0.75), maxf(1.0, s * 0.012), true)


## Свет сверху-слева: доля освещённости грани по направлению её середины от центра.
static func _lit(dir: Vector2) -> float:
	return clampf(0.5 + 0.5 * dir.normalized().dot(Vector2(-0.6, -0.8)), 0.0, 1.0)


## Огранки с короной (круг, маркиз, груша, триллиант, кушон, октагон): площадка и веер граней до рундиста.
func _draw_facets(girdle: PackedVector2Array, c: Vector2, col: Color, brilliant: bool) -> void:
	var n: int = girdle.size()
	var table: PackedVector2Array = PackedVector2Array()
	var star: PackedVector2Array = PackedVector2Array()
	for i: int in n:
		table.append(c + (girdle[i] - c) * 0.5)
		# Точка «звезды» между площадкой и рундистом — у бриллианта грани ломаются, как у настоящей огранки.
		var mid: Vector2 = (girdle[i] + girdle[(i + 1) % n]) * 0.5
		star.append(c + (mid - c) * (0.68 if brilliant else 0.6))
	for i2: int in n:
		var j: int = (i2 + 1) % n
		var d: Vector2 = (girdle[i2] + girdle[j]) * 0.5 - c
		var lit: float = _lit(d)
		var fc: Color = col.darkened(0.55 - 0.5 * lit).lerp(Color.WHITE, 0.16 * lit)
		draw_colored_polygon(PackedVector2Array([girdle[i2], girdle[j], star[i2]]), fc)
		var fc2: Color = col.darkened(0.4 - 0.45 * _lit(-d.orthogonal() + d)).lerp(Color.WHITE, 0.1 * lit)
		draw_colored_polygon(PackedVector2Array([girdle[i2], star[i2], table[i2]]), fc2)
		draw_colored_polygon(PackedVector2Array([star[i2], girdle[j], table[j], table[i2]]), col.darkened(0.3 - 0.35 * lit))
	draw_colored_polygon(table, col.lightened(0.12))
	var t_out: PackedVector2Array = table.duplicate()
	t_out.append(table[0])
	draw_polyline(t_out, Color(col.lightened(0.6), 0.55), maxf(1.0, minf(size.x, size.y) * 0.012), true)


## Ступенчатая огранка (изумрудная): концентрические ступени вместо веера граней.
func _draw_steps(girdle: PackedVector2Array, c: Vector2, col: Color) -> void:
	var steps: Array[float] = [1.0, 0.8, 0.62]
	for si: int in steps.size():
		var outer: float = steps[si]
		var inner: float = steps[si + 1] if si + 1 < steps.size() else 0.0
		if inner <= 0.0:
			break
		for i: int in girdle.size():
			var j: int = (i + 1) % girdle.size()
			var a: Vector2 = c + (girdle[i] - c) * outer
			var b: Vector2 = c + (girdle[j] - c) * outer
			var lit: float = _lit((a + b) * 0.5 - c)
			var fc: Color = col.darkened(0.5 - 0.48 * lit - 0.08 * float(si)).lerp(Color.WHITE, 0.14 * lit)
			draw_colored_polygon(PackedVector2Array([a, b, c + (girdle[j] - c) * inner, c + (girdle[i] - c) * inner]), fc)
	var table: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in girdle:
		table.append(c + (p - c) * 0.62)
	draw_colored_polygon(table, col.lightened(0.08))


## Кабошон: гладкий купол — кольца от тёмного края к светлой середине, сдвинутой к свету.
func _draw_dome(girdle: PackedVector2Array, c: Vector2, col: Color) -> void:
	var rings: int = 9
	for k: int in rings:
		var f: float = 1.0 - float(k) / float(rings)
		var centre: Vector2 = c + Vector2(-0.12, -0.14) * (1.0 - f) * minf(size.x, size.y) * 0.5
		var ring: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in girdle:
			ring.append(centre + (p - c) * f)
		draw_colored_polygon(ring, col.darkened(0.5 * f * f).lerp(Color.WHITE, 0.25 * (1.0 - f) * (1.0 - f)))


## Контур огранки в плане (как у 3D-огранок ArtKit.GEM_CUTS), радиус ~1, y вниз.
static func cut_outline(cut: String) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	match cut:
		"marquise":
			# Лодочка: две дуги, сходящиеся остриями вверху и внизу (x ~ 1 − y² — острие, а не скругление).
			for i: int in 11:
				var y: float = -1.0 + 2.0 * float(i) / 10.0
				out.append(Vector2(0.58 * (1.0 - y * y), y * 0.98))
			for i2: int in range(9, 0, -1):
				var y2: float = -1.0 + 2.0 * float(i2) / 10.0
				out.append(Vector2(-0.58 * (1.0 - y2 * y2), y2 * 0.98))
		"pear":
			# Капля: остриё вверху, скруглённое основание.
			out.append(Vector2(0.0, -1.0))
			for i: int in 15:
				var a: float = deg_to_rad(-25.0 + 230.0 * float(i) / 14.0)
				out.append(Vector2(cos(a), sin(a)) * 0.64 + Vector2(0.0, 0.3))
		"trilliant":
			# Треугольник с выпуклыми сторонами.
			for v: int in 3:
				var a0: float = -PI / 2.0 + TAU * float(v) / 3.0
				var a1: float = a0 + TAU / 3.0
				var p0: Vector2 = Vector2(cos(a0), sin(a0)) * 0.98
				var p1: Vector2 = Vector2(cos(a1), sin(a1)) * 0.98
				for i: int in 5:
					var t2: float = float(i) / 5.0
					var mid: Vector2 = p0.lerp(p1, t2)
					out.append(mid + mid.normalized() * 0.16 * sin(PI * t2))
		"cushion":
			for i: int in 24:
				var t3: float = TAU * float(i) / 24.0
				var cx: float = cos(t3)
				var cy: float = sin(t3)
				out.append(Vector2(signf(cx) * pow(absf(cx), 0.55), signf(cy) * pow(absf(cy), 0.55)) * 0.82)
		"emerald":
			var w: float = 0.62
			var h: float = 0.9
			var k: float = 0.22
			out = PackedVector2Array([Vector2(-w + k, -h), Vector2(w - k, -h), Vector2(w, -h + k), Vector2(w, h - k),
				Vector2(w - k, h), Vector2(-w + k, h), Vector2(-w, h - k), Vector2(-w, -h + k)])
		"octagon":
			for i: int in 8:
				var t4: float = TAU * float(i) / 8.0 + PI / 8.0
				out.append(Vector2(cos(t4), sin(t4)) * 0.9)
		"cabochon":
			for i: int in 24:
				var t5: float = TAU * float(i) / 24.0
				out.append(Vector2(cos(t5) * 0.7, sin(t5) * 0.88))
		_:
			for i: int in 16:
				var t6: float = TAU * float(i) / 16.0 + PI / 16.0
				out.append(Vector2(cos(t6), sin(t6)) * 0.88)
	return out


func _draw_special() -> void:
	var s: float = minf(size.x, size.y)
	var c: Vector2 = size * 0.5
	var sp: Dictionary = GameData.load_default().special(special_id)
	var col: Color = Color.html(String(sp.get("color", "#ffffff")))
	if glow:
		for i: int in 6:
			var k: float = float(6 - i) / 6.0
			draw_circle(c, s * (0.32 + 0.2 * k), Color(col, 0.06 * (1.0 - k * 0.5)))
	var hex: PackedVector2Array = PackedVector2Array()
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0 - PI / 2.0
		hex.append(c + Vector2(cos(a), sin(a)) * s * 0.44)
	draw_colored_polygon(hex, col.darkened(0.72))
	var outline: PackedVector2Array = hex.duplicate()
	outline.append(hex[0])
	draw_polyline(outline, col.lightened(0.25), maxf(1.5, s * 0.035), true)
	var inner: PackedVector2Array = PackedVector2Array()
	match String(sp.get("silhouette", "")):
		"beacon":
			for i: int in 16:
				var a2: float = TAU * float(i) / 16.0
				inner.append(c + Vector2(cos(a2) * 0.2, sin(a2) * 0.13) * s)
			draw_arc(c, s * 0.27, 0.0, TAU, 24, col.lightened(0.3), maxf(1.0, s * 0.025), true)
		"crown":
			inner = PackedVector2Array([c + Vector2(-0.24, 0.14) * s, c + Vector2(-0.24, -0.1) * s, c + Vector2(-0.12, 0.02) * s, c + Vector2(0.0, -0.2) * s, c + Vector2(0.12, 0.02) * s, c + Vector2(0.24, -0.1) * s, c + Vector2(0.24, 0.14) * s])
		"ballista":
			inner = PackedVector2Array([c + Vector2(0.0, -0.3) * s, c + Vector2(0.09, 0.0) * s, c + Vector2(0.04, 0.24) * s, c + Vector2(-0.04, 0.24) * s, c + Vector2(-0.09, 0.0) * s])
		"well":
			draw_arc(c, s * 0.2, 0.0, TAU, 24, col.lightened(0.2), maxf(2.0, s * 0.06), true)
			inner = PackedVector2Array([c + Vector2(0.0, -0.12) * s, c + Vector2(0.06, 0.0) * s, c + Vector2(0.0, 0.12) * s, c + Vector2(-0.06, 0.0) * s])
		"bloom":
			for i: int in 6:
				var a3: float = TAU * float(i) / 6.0
				draw_circle(c + Vector2(cos(a3), sin(a3)) * s * 0.14, s * 0.08, col)
			inner = PackedVector2Array()
			draw_circle(c, s * 0.08, col.lightened(0.4))
		"obelisk":
			inner = PackedVector2Array([c + Vector2(0.0, -0.3) * s, c + Vector2(0.08, -0.18) * s, c + Vector2(0.07, 0.24) * s, c + Vector2(-0.07, 0.24) * s, c + Vector2(-0.08, -0.18) * s])
			for k2: int in 3:
				draw_line(c + Vector2(-0.04, -0.08 + 0.1 * float(k2)) * s, c + Vector2(0.04, -0.04 + 0.1 * float(k2)) * s, col.darkened(0.5), maxf(1.0, s * 0.02))
		"geode":
			draw_arc(c, s * 0.2, PI * 0.15, PI * 1.85, 20, col.lightened(0.2), maxf(2.0, s * 0.05), true)
			inner = PackedVector2Array([c + Vector2(0.0, -0.1) * s, c + Vector2(0.07, 0.04) * s, c + Vector2(0.0, 0.12) * s, c + Vector2(-0.07, 0.04) * s])
			for k3: int in 3:
				var a4: float = TAU * float(k3) / 3.0 + 0.4
				draw_circle(c + Vector2(cos(a4), sin(a4)) * s * 0.3, s * 0.03, col.lightened(0.3))
		"spire":
			inner = PackedVector2Array([c + Vector2(0.0, -0.32) * s, c + Vector2(0.05, 0.22) * s, c + Vector2(-0.05, 0.22) * s])
			for k4: int in 3:
				var y: float = -0.12 + 0.12 * float(k4)
				draw_arc(c + Vector2(0.0, y) * s, s * (0.09 + 0.03 * float(k4)), PI * 0.1, PI * 0.9, 10, col.lightened(0.3), maxf(1.0, s * 0.025), true)
		"prism":
			inner = PackedVector2Array([c + Vector2(0.0, -0.28) * s, c + Vector2(0.24, 0.16) * s, c + Vector2(-0.24, 0.16) * s])
			draw_line(c + Vector2(0.0, -0.28) * s, c + Vector2(0.0, 0.16) * s, col.lightened(0.5), maxf(1.0, s * 0.02))
		"heart":
			draw_circle(c + Vector2(-0.09, -0.06) * s, s * 0.11, col.lightened(0.15))
			draw_circle(c + Vector2(0.09, -0.06) * s, s * 0.11, col.lightened(0.15))
			inner = PackedVector2Array([c + Vector2(-0.2, -0.03) * s, c + Vector2(0.2, -0.03) * s, c + Vector2(0.0, 0.22) * s])
		"idol":
			draw_circle(c + Vector2(0.0, -0.14) * s, s * 0.1, col.lightened(0.3))
			inner = PackedVector2Array([c + Vector2(-0.12, 0.22) * s, c + Vector2(-0.07, -0.02) * s, c + Vector2(0.07, -0.02) * s, c + Vector2(0.12, 0.22) * s])
		"banner":
			draw_line(c + Vector2(-0.12, -0.28) * s, c + Vector2(-0.12, 0.26) * s, col.lightened(0.4), maxf(1.5, s * 0.04))
			inner = PackedVector2Array([c + Vector2(-0.1, -0.26) * s, c + Vector2(0.22, -0.18) * s, c + Vector2(0.12, -0.04) * s, c + Vector2(0.22, 0.08) * s, c + Vector2(-0.1, 0.04) * s])
		"blade":
			inner = PackedVector2Array([c + Vector2(0.0, -0.32) * s, c + Vector2(0.06, -0.22) * s, c + Vector2(0.05, 0.12) * s, c + Vector2(-0.05, 0.12) * s, c + Vector2(-0.06, -0.22) * s])
			draw_line(c + Vector2(-0.16, 0.13) * s, c + Vector2(0.16, 0.13) * s, col.lightened(0.4), maxf(1.5, s * 0.045))
			draw_line(c + Vector2(0.0, 0.13) * s, c + Vector2(0.0, 0.24) * s, col.lightened(0.2), maxf(1.5, s * 0.04))
	if inner.size() >= 3:
		draw_colored_polygon(inner, col.lightened(0.15))
	for i: int in 3:
		var pc: Vector2 = c + Vector2((float(i) - 1.0) * s * 0.12, s * 0.36)
		draw_circle(pc, s * 0.035, UiTokens.GOLD if i < quality else Color(1, 1, 1, 0.18))


func _draw_slate() -> void:
	var s: float = minf(size.x, size.y)
	var c: Vector2 = size * 0.5
	var sl: Dictionary = GameData.load_default().slate(slate_id)
	var col: Color = Color.html(String(sl.get("color", "#ffffff")))
	if glow:
		for i: int in 6:
			var k: float = float(6 - i) / 6.0
			draw_circle(c, s * (0.3 + 0.2 * k), Color(col, 0.05 * (1.0 - k * 0.5)))
	var r: float = s * 0.44
	var slab: PackedVector2Array = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	draw_colored_polygon(slab, col.darkened(0.75))
	var outline: PackedVector2Array = slab.duplicate()
	outline.append(slab[0])
	draw_polyline(outline, col.lightened(0.2), maxf(1.5, s * 0.035), true)
	if String(sl.get("kind", "")) == "combo":
		var r2: float = s * 0.32
		var inner_frame: PackedVector2Array = PackedVector2Array([c + Vector2(0, -r2), c + Vector2(r2, 0), c + Vector2(0, r2), c + Vector2(-r2, 0), c + Vector2(0, -r2)])
		draw_polyline(inner_frame, col, maxf(1.0, s * 0.025), true)
	var rune: float = s * 0.16
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -rune), c + Vector2(rune * 0.6, 0), c + Vector2(0, rune), c + Vector2(-rune * 0.6, 0)]), col.lightened(0.25))
