class_name MeshFactory
extends RefCounted
## Процедурные low-poly меши с плоскими нормалями: гемы, стены, враги, постаменты.

static var _cache: Dictionary = {}

## Профили «токарных» тел: [Vector2(радиус, высота)], число граней, поворот.
const GEM_PROFILES: Dictionary = {
	"needle": {"profile": [Vector2(0.0, 0.0), Vector2(0.24, 0.36), Vector2(0.2, 0.86), Vector2(0.0, 1.15)], "sides": 6},
	"coil": {"profile": [Vector2(0.0, 0.0), Vector2(0.3, 0.42), Vector2(0.0, 0.86)], "sides": 4},
	"bud": {"profile": [Vector2(0.0, 0.0), Vector2(0.18, 0.3), Vector2(0.14, 0.62), Vector2(0.0, 0.8)], "sides": 5},
	"mortar": {"profile": [Vector2(0.0, 0.0), Vector2(0.3, 0.06), Vector2(0.42, 0.26), Vector2(0.42, 0.4), Vector2(0.24, 0.6), Vector2(0.0, 0.64)], "sides": 6},
	"spear": {"profile": [Vector2(0.0, 0.0), Vector2(0.16, 0.55), Vector2(0.0, 1.4)], "sides": 4},
	"halo": {"profile": [Vector2(0.0, 0.12), Vector2(0.2, 0.4), Vector2(0.0, 0.7)], "sides": 4},
	"lens": {"profile": [Vector2(0.0, 0.16), Vector2(0.3, 0.2), Vector2(0.44, 0.33), Vector2(0.32, 0.46), Vector2(0.0, 0.5)], "sides": 10},
	"octahedron": {"profile": [Vector2(0.0, 0.02), Vector2(0.38, 0.5), Vector2(0.26, 0.68), Vector2(0.0, 0.68)], "sides": 8},
}


## Тело вращения с гранями; нормали направлены от оси. axis_rot поворачивает готовую геометрию.
static func lathe(profile: Array, sides: int, phase: float = 0.0, basis: Basis = Basis.IDENTITY, offset: Vector3 = Vector3.ZERO) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_lathe_into(st, profile, sides, phase, basis, offset)
	return st.commit()


static func _lathe_into(st: SurfaceTool, profile: Array, sides: int, phase: float, basis: Basis, offset: Vector3) -> void:
	var ymin: float = INF
	var ymax: float = -INF
	for p: Vector2 in profile:
		ymin = minf(ymin, p.y)
		ymax = maxf(ymax, p.y)
	var centroid: Vector3 = Vector3(0, (ymin + ymax) * 0.5, 0)
	for k: int in profile.size() - 1:
		var p0: Vector2 = profile[k]
		var p1: Vector2 = profile[k + 1]
		for i: int in sides:
			var a0: float = phase + TAU * float(i) / float(sides)
			var a1: float = phase + TAU * float(i + 1) / float(sides)
			var v00: Vector3 = Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01: Vector3 = Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10: Vector3 = Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11: Vector3 = Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			if p0.x > 0.0001:
				_tri(st, v00, v01, v11 if p1.x > 0.0001 else v10, centroid, basis, offset)
			if p1.x > 0.0001:
				_tri(st, v00, v11, v10, centroid, basis, offset)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, centroid: Vector3, basis: Basis, offset: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	var center: Vector3 = (a + b + c) / 3.0
	if n.dot(center - centroid) < 0.0:
		n = -n
		var tmp: Vector3 = b
		b = c
		c = tmp
	var wn: Vector3 = (basis * n).normalized()
	# Godot: лицевая сторона — по часовой стрелке.
	for v: Vector3 in [a, c, b]:
		st.set_normal(wn)
		st.add_vertex(basis * v + offset)


## Меш гема. Качество читается по огранке: у I–II граней меньше, у IV–V больше граней и поясов огранки.
static func gem_mesh(silhouette: String, quality: int = 3) -> ArrayMesh:
	var q: int = clampi(quality, 1, 5)
	var key: String = "gem_%s_%d" % [silhouette, q]
	if _cache.has(key):
		return _cache[key]
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var def: Dictionary = GEM_PROFILES.get(silhouette, GEM_PROFILES["octahedron"])
	var sides: int = maxi(3, int(def["sides"]) + [-1, 0, 0, 2, 4][q - 1])
	var profile: Array = _facet_profile(def["profile"], maxi(0, q - 3))
	if silhouette == "bud":
		_lathe_into(st, profile, sides, 0.0, Basis.IDENTITY, Vector3.ZERO)
		for i: int in 5:
			var a: float = TAU * float(i) / 5.0
			var b: Basis = Basis(Vector3.UP, a) * Basis(Vector3.FORWARD, 0.5)
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.1, 0.22), Vector2(0.0, 0.62)], 4, 0.3, b, Vector3(cos(a) * 0.08, 0.02, sin(a) * 0.08))
	else:
		_lathe_into(st, profile, sides, PI / float(sides), Basis.IDENTITY, Vector3.ZERO)
	var m: ArrayMesh = st.commit()
	_cache[key] = m
	return m


## Дополнительные пояса огранки: каждый отрезок профиля делится, середина чуть выдвигается наружу.
static func _facet_profile(profile: Array, passes: int) -> Array:
	var out: Array = profile.duplicate()
	for p: int in passes:
		var next: Array = [out[0]]
		for i: int in range(1, out.size()):
			var a: Vector2 = out[i - 1]
			var b: Vector2 = out[i]
			var mid: Vector2 = (a + b) * 0.5
			if mid.x > 0.001:
				mid.x *= 1.05
			next.append(mid)
			next.append(b)
		out = next
	return out


## Статичная часть меша спец-башни (вращающиеся кольца и осколки добавляет BoardView).
static func special_mesh(kind: String) -> ArrayMesh:
	var key: String = "special_" + kind
	if _cache.has(key):
		return _cache[key]
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"beacon":
			_lathe_into(st, [Vector2(0.0, 0.5), Vector2(0.36, 0.56), Vector2(0.5, 0.72), Vector2(0.36, 0.88), Vector2(0.0, 0.94)], 12, 0.0, Basis.IDENTITY, Vector3.ZERO)
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.08, 0.1), Vector2(0.04, 0.5), Vector2(0.0, 0.52)], 4, 0.0, Basis.IDENTITY, Vector3.ZERO)
		"crown":
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.2, 0.18), Vector2(0.16, 0.42), Vector2(0.0, 0.52)], 6, 0.0, Basis.IDENTITY, Vector3.ZERO)
			for i: int in 7:
				var a: float = TAU * float(i) / 7.0
				var b: Basis = Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, -0.42)
				_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.08, 0.12), Vector2(0.0, 0.72)], 3, 0.0, b, Vector3(cos(a) * 0.34, 0.05, sin(a) * 0.34))
		"ballista":
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.18, 0.5), Vector2(0.12, 1.2), Vector2(0.0, 1.85)], 4, PI / 4.0, Basis.IDENTITY, Vector3.ZERO)
			for i: int in 3:
				var a2: float = TAU * float(i) / 3.0
				var b2: Basis = Basis(Vector3.UP, -a2) * Basis(Vector3.FORWARD, -0.75)
				_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.06, 0.15), Vector2(0.0, 0.62)], 3, 0.0, b2, Vector3(cos(a2) * 0.18, 0.1, sin(a2) * 0.18))
		"well":
			_lathe_into(st, [Vector2(0.38, 0.0), Vector2(0.58, 0.0), Vector2(0.6, 0.3), Vector2(0.52, 0.38), Vector2(0.4, 0.38), Vector2(0.38, 0.08)], 6, PI / 6.0, Basis.IDENTITY, Vector3.ZERO)
			_lathe_into(st, [Vector2(0.0, 0.2), Vector2(0.2, 0.55), Vector2(0.0, 0.95)], 4, 0.0, Basis.IDENTITY, Vector3.ZERO)
		"bloom":
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.18, 0.22), Vector2(0.14, 0.5), Vector2(0.0, 0.62)], 6, 0.0, Basis.IDENTITY, Vector3.ZERO)
			for i: int in 6:
				var a3: float = TAU * float(i) / 6.0
				var b3: Basis = Basis(Vector3.UP, -a3) * Basis(Vector3.FORWARD, -1.05)
				_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.16, 0.25), Vector2(0.1, 0.55), Vector2(0.0, 0.7)], 4, 0.3, b3, Vector3(cos(a3) * 0.1, 0.12, sin(a3) * 0.1))
		"obelisk":
			# Четырёхгранный обелиск с пирамидальной вершиной и рунными гранями-«зубцами».
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.3, 0.0), Vector2(0.24, 1.25), Vector2(0.27, 1.32), Vector2(0.0, 1.62)], 4, PI / 4.0, Basis.IDENTITY, Vector3.ZERO)
			for i: int in 4:
				var a4: float = TAU * float(i) / 4.0
				_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.07, 0.08), Vector2(0.0, 0.3)], 3, 0.0, Basis(Vector3.UP, -a4), Vector3(cos(a4) * 0.3, 0.55 + 0.25 * float(i % 2), sin(a4) * 0.3))
		"geode":
			# Расколотая жеода: две половинки-чаши с кристаллами внутри.
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.42, 0.12), Vector2(0.5, 0.42), Vector2(0.36, 0.5), Vector2(0.3, 0.3), Vector2(0.0, 0.22)], 7, 0.0, Basis.IDENTITY, Vector3.ZERO)
			for i: int in 5:
				var a5: float = TAU * float(i) / 5.0
				var b5: Basis = Basis(Vector3.UP, -a5) * Basis(Vector3.FORWARD, -0.35)
				_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.07, 0.1), Vector2(0.0, 0.42)], 4, 0.0, b5, Vector3(cos(a5) * 0.15, 0.25, sin(a5) * 0.15))
		"spire":
			# Шпиль-катушка: тонкая игла с утолщениями-витками.
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.22, 0.05), Vector2(0.12, 0.3), Vector2(0.2, 0.5), Vector2(0.1, 0.75), Vector2(0.17, 0.95), Vector2(0.07, 1.25), Vector2(0.0, 1.9)], 6, 0.0, Basis.IDENTITY, Vector3.ZERO)
		"prism":
			# Треугольная призма-лезвие, повёрнутая ребром вверх.
			_lathe_into(st, [Vector2(0.0, 0.1), Vector2(0.42, 0.45), Vector2(0.42, 0.85), Vector2(0.0, 1.35)], 3, 0.0, Basis.IDENTITY, Vector3.ZERO)
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.12, 0.08), Vector2(0.0, 0.16)], 3, PI / 3.0, Basis.IDENTITY, Vector3.ZERO)
		"heart":
			# Каменное сердце: массивное ядро и наросты.
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.38, 0.12), Vector2(0.55, 0.45), Vector2(0.48, 0.8), Vector2(0.22, 1.0), Vector2(0.0, 0.92)], 6, 0.0, Basis.IDENTITY, Vector3.ZERO)
			for i: int in 4:
				var a6: float = TAU * float(i) / 4.0 + 0.4
				_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.12, 0.08), Vector2(0.0, 0.3)], 4, 0.0, Basis(Vector3.UP, -a6) * Basis(Vector3.FORWARD, -1.0), Vector3(cos(a6) * 0.42, 0.55, sin(a6) * 0.42))
		"idol":
			# Идол: постамент, «тело» и голова-диск.
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.3, 0.0), Vector2(0.22, 0.2), Vector2(0.26, 0.7), Vector2(0.14, 0.82), Vector2(0.0, 0.84)], 6, 0.0, Basis.IDENTITY, Vector3.ZERO)
			_lathe_into(st, [Vector2(0.0, -0.06), Vector2(0.3, -0.04), Vector2(0.3, 0.04), Vector2(0.0, 0.06)], 10, 0.0, Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 1.1, 0.0))
		"banner":
			# Кристаллическое знамя: древко и полотнище из граней.
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.06, 0.0), Vector2(0.05, 1.7), Vector2(0.0, 1.85)], 4, 0.0, Basis.IDENTITY, Vector3.ZERO)
			_lathe_into(st, [Vector2(0.0, -0.4), Vector2(0.5, -0.05), Vector2(0.3, 0.35), Vector2(0.0, 0.4)], 4, 0.0, Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 0.18)), Vector3(0.32, 1.25, 0.0))
		"blade":
			# Клинок-монолит: длинное лезвие острием вверх и гарда.
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.14, 0.05), Vector2(0.12, 0.3), Vector2(0.0, 0.32)], 4, PI / 4.0, Basis.IDENTITY, Vector3.ZERO)
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.45, 0.04), Vector2(0.0, 0.08)], 4, PI / 4.0, Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 0.25)), Vector3(0.0, 0.3, 0.0))
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.24, 0.1), Vector2(0.2, 1.4), Vector2(0.0, 1.95)], 4, PI / 4.0, Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 0.3)), Vector3(0.0, 0.36, 0.0))
		_:
			_lathe_into(st, GEM_PROFILES["octahedron"]["profile"], 8, 0.0, Basis.IDENTITY, Vector3.ZERO)
	var m: ArrayMesh = st.commit()
	_cache[key] = m
	return m


static func coin_mesh() -> ArrayMesh:
	if not _cache.has("coin"):
		_cache["coin"] = lathe([Vector2(0.0, -0.08), Vector2(0.5, -0.06), Vector2(0.5, 0.06), Vector2(0.0, 0.08)], 8, 0.0)
	return _cache["coin"]


static func rock_mesh() -> ArrayMesh:
	if not _cache.has("rock"):
		_cache["rock"] = lathe([Vector2(0.0, 0.0), Vector2(0.6, 0.0), Vector2(0.65, 0.06), Vector2(0.65, 0.42), Vector2(0.55, 0.54), Vector2(0.0, 0.57)], 4, PI / 4.0)
	return _cache["rock"]


static func pedestal_mesh() -> ArrayMesh:
	if not _cache.has("pedestal"):
		_cache["pedestal"] = lathe([Vector2(0.0, 0.0), Vector2(0.46, 0.0), Vector2(0.46, 0.08), Vector2(0.36, 0.16), Vector2(0.0, 0.16)], 6, PI / 6.0)
	return _cache["pedestal"]


## Квадратная плита точки маршрута со стороной side (м) и скошенной кромкой: вращение профиля по 4 граням, повёрнутый на 45°.
static func square_pad_mesh(side: float) -> ArrayMesh:
	var key: String = "square_pad_%.2f" % side
	if not _cache.has(key):
		var r: float = side * 0.5 * sqrt(2.0)
		var bevel: float = 0.1 * sqrt(2.0)
		_cache[key] = lathe([Vector2(0.0, 0.0), Vector2(r, 0.0), Vector2(r, 0.035), Vector2(r - bevel, 0.065), Vector2(0.0, 0.065)], 4, PI / 4.0)
	return _cache[key]


static func projectile_mesh() -> ArrayMesh:
	if not _cache.has("projectile"):
		_cache["projectile"] = lathe([Vector2(0.0, -0.5), Vector2(0.5, 0.0), Vector2(0.0, 0.5)], 4, 0.0)
	return _cache["projectile"]


static func shard_mesh() -> ArrayMesh:
	if not _cache.has("shard"):
		_cache["shard"] = lathe([Vector2(0.0, -0.5), Vector2(0.35, -0.1), Vector2(0.0, 0.6)], 3, 0.0)
	return _cache["shard"]


## Меши врагов: единичный размер, «вперёд» = +X.
static func enemy_mesh(kind: String) -> ArrayMesh:
	var key: String = "enemy_" + kind
	if _cache.has(key):
		return _cache[key]
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var forward: Basis = Basis(Vector3.FORWARD, -PI * 0.5)
	match kind:
		"dart":
			_lathe_into(st, [Vector2(0.0, -0.7), Vector2(0.42, -0.2), Vector2(0.0, 0.9)], 3, 0.0, forward, Vector3(0, 0.45, 0))
		"shell":
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.85, 0.08), Vector2(0.95, 0.32), Vector2(0.62, 0.6), Vector2(0.0, 0.68)], 6, 0.0, Basis.IDENTITY, Vector3.ZERO)
		"wing":
			_lathe_into(st, [Vector2(0.0, -0.6), Vector2(0.3, -0.1), Vector2(0.0, 0.7)], 4, PI / 4.0, forward, Vector3.ZERO)
			_lathe_into(st, [Vector2(0.0, -0.5), Vector2(0.5, 0.0), Vector2(0.0, 0.5)], 3, 0.0, Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(0.5, 1.6, 0.08)), Vector3(-0.1, 0.0, 0.0))
		"boss":
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.7, 0.18), Vector2(0.92, 0.58), Vector2(0.72, 0.98), Vector2(0.36, 1.22), Vector2(0.0, 1.3)], 8, 0.0, Basis.IDENTITY, Vector3.ZERO)
			for i: int in 6:
				var a: float = TAU * float(i) / 6.0
				var b: Basis = Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, -1.1)
				_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.12, 0.1), Vector2(0.0, 0.55)], 3, 0.0, b, Vector3(cos(a) * 0.75, 0.75, sin(a) * 0.75))
		"spike":
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.6, 0.12), Vector2(0.72, 0.5), Vector2(0.5, 0.86), Vector2(0.0, 0.96)], 5, 0.0, Basis.IDENTITY, Vector3.ZERO)
			for i: int in 5:
				var a: float = TAU * float(i) / 5.0
				_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.12, 0.08), Vector2(0.0, 0.5)], 3, 0.0, Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, -1.2), Vector3(cos(a) * 0.62, 0.5, sin(a) * 0.62))
		"hive":
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.62, 0.1), Vector2(0.86, 0.4), Vector2(0.8, 0.72), Vector2(0.5, 1.02), Vector2(0.18, 1.14), Vector2(0.0, 1.1)], 9, 0.0, Basis.IDENTITY, Vector3.ZERO)
			for i: int in 8:
				var a2: float = TAU * float(i) / 8.0
				_lathe_into(st, [Vector2(0.0, -0.12), Vector2(0.14, 0.0), Vector2(0.0, 0.12)], 5, 0.0, Basis.IDENTITY, Vector3(cos(a2) * 0.82, 0.45 + 0.25 * float(i % 2), sin(a2) * 0.82))
		"king":
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.72, 0.16), Vector2(0.94, 0.55), Vector2(0.8, 0.95), Vector2(0.42, 1.2), Vector2(0.0, 1.26)], 8, 0.0, Basis.IDENTITY, Vector3.ZERO)
			for i: int in 8:
				var a3: float = TAU * float(i) / 8.0
				_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.09, 0.08), Vector2(0.0, 0.48 + 0.18 * float(i % 2))], 4, 0.0, Basis.IDENTITY, Vector3(cos(a3) * 0.4, 1.12, sin(a3) * 0.4))
			for i: int in 2:
				var side: float = -1.0 if i == 0 else 1.0
				_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.2, 0.2), Vector2(0.0, 0.7)], 4, 0.0, Basis(Vector3.FORWARD, side * 1.1), Vector3(0.0, 0.7, side * 0.85))
		"colossus":
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.7, 0.0), Vector2(0.78, 0.3), Vector2(0.62, 0.9), Vector2(0.7, 1.15), Vector2(0.4, 1.45), Vector2(0.0, 1.5)], 4, PI / 4.0, Basis.IDENTITY, Vector3.ZERO)
		_:
			_lathe_into(st, [Vector2(0.0, 0.0), Vector2(0.6, 0.12), Vector2(0.78, 0.48), Vector2(0.56, 0.86), Vector2(0.0, 1.0)], 7, 0.0, Basis.IDENTITY, Vector3.ZERO)
	var m: ArrayMesh = st.commit()
	_cache[key] = m
	return m


## Лента вдоль ломаной на высоте y; UV.x = пройденная длина, UV.y = поперёк (0..1).
static func ribbon(points: PackedVector3Array, width: float) -> ArrayMesh:
	var m: ArrayMesh = ArrayMesh.new()
	if points.size() < 2:
		return m
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var dist: float = 0.0
	for i: int in points.size():
		var dir: Vector3
		if i == 0:
			dir = points[1] - points[0]
		elif i == points.size() - 1:
			dir = points[i] - points[i - 1]
		else:
			dir = (points[i + 1] - points[i - 1])
		dir.y = 0.0
		dir = dir.normalized()
		var side: Vector3 = Vector3(-dir.z, 0.0, dir.x) * width * 0.5
		if i > 0:
			dist += points[i].distance_to(points[i - 1])
		verts.append(points[i] - side)
		verts.append(points[i] + side)
		uvs.append(Vector2(dist, 0.0))
		uvs.append(Vector2(dist, 1.0))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
	var idx: PackedInt32Array = PackedInt32Array()
	for i: int in points.size() - 1:
		var a: int = i * 2
		idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
