class_name ProjectileRenderer
extends Node3D
## Снаряды (MultiMesh, вытянуты по направлению полёта) и цепные молнии (ленты).

const ADD_SHADER: Shader = preload("res://fx/shaders/additive.gdshader")
const TRAIL_SHADER: Shader = preload("res://fx/shaders/trail.gdshader")
## Длина следа: доля пути за секунду, но не длиннее TRAIL_MAX.
const TRAIL_K: float = 0.07
const TRAIL_MAX: float = 1.3
const CAPACITY: int = 1024
const HEIGHT: float = 0.65
const BOLT_TIME: float = 0.16

var board: BoardView
var sim: GameSim
var _mm: MultiMesh
var _trail_mm: MultiMesh
var _colors: Dictionary = {}
var _bolts: Array[Dictionary] = []
var _bolt_mesh: ImmediateMesh
var _time: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(b: BoardView, target: GameSim) -> void:
	board = b
	sim = target
	for id: String in sim.data.gem_ids:
		_colors[id] = UiTokens.gem_color(id)
	for id2: String in sim.data.special_ids:
		_colors[id2] = Color.html(String(sim.data.special(id2)["color"]))
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = MeshFactory.projectile_mesh()
	_mm.instance_count = CAPACITY
	_mm.visible_instance_count = 0
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = ADD_SHADER
	m.set_shader_parameter("intensity", 3.0)
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_trail_mm = MultiMesh.new()
	_trail_mm.transform_format = MultiMesh.TRANSFORM_3D
	_trail_mm.use_colors = true
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(1, 1)
	_trail_mm.mesh = plane
	_trail_mm.instance_count = CAPACITY
	_trail_mm.visible_instance_count = 0
	var tmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	tmi.multimesh = _trail_mm
	var tm: ShaderMaterial = ShaderMaterial.new()
	tm.shader = TRAIL_SHADER
	tmi.material_override = tm
	tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tmi)
	_bolt_mesh = ImmediateMesh.new()
	var bmi: MeshInstance3D = MeshInstance3D.new()
	bmi.mesh = _bolt_mesh
	var bm: ShaderMaterial = ShaderMaterial.new()
	bm.shader = ADD_SHADER
	bm.set_shader_parameter("intensity", 2.6)
	bmi.material_override = bm
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bmi)


func on_event(e: Dictionary) -> void:
	if String(e["type"]) == "lightning":
		var pts: PackedVector2Array = e["points"]
		var flags: Array = e["flying"]
		var world: PackedVector3Array = PackedVector3Array()
		for i: int in pts.size():
			var y: float = 0.9
			if i > 0 and i - 1 < flags.size():
				y = EnemyRenderer.FLY_HEIGHT + 0.25 if bool(flags[i - 1]) else 0.35
			world.append(board.w(pts[i], y))
		var sp: String = String(e.get("special", ""))
		_bolts.append({"pts": world, "t": _time, "seed": _rng.randi(), "color": _colors.get(sp if not sp.is_empty() else "sapphire", Color.CYAN)})


func render(alpha: float, delta: float) -> void:
	_time += delta
	var n: int = 0
	for p: ProjectileState in sim.projectiles:
		if not p.alive or n >= CAPACITY:
			continue
		var pos2: Vector2 = p.prev_pos.lerp(p.pos, alpha)
		var dir2: Vector2 = (p.target_pos - p.pos)
		var y: float = HEIGHT if not p.target_flying else lerpf(HEIGHT, EnemyRenderer.FLY_HEIGHT, 0.6)
		var dir: Vector3 = Vector3(dir2.x, 0.0, dir2.y)
		var basis: Basis = Basis.IDENTITY
		if dir.length_squared() > 0.0001:
			basis = Basis.looking_at(dir.normalized(), Vector3.UP)
		var size: float = 0.1 + 0.025 * float(p.quality)
		basis = basis * Basis.IDENTITY.scaled(Vector3(size, size, size * 3.2)) * Basis(Vector3.RIGHT, PI * 0.5)
		var head: Vector3 = board.w(pos2, y)
		var col: Color = _colors.get(p.gem_id, Color.WHITE)
		_mm.set_instance_transform(n, Transform3D(basis, head))
		_mm.set_instance_color(n, col)
		if dir.length_squared() > 0.0001:
			var back: Vector3 = -dir.normalized()
			var trail_len: float = minf(p.speed * TRAIL_K, TRAIL_MAX)
			var side: Vector3 = back.cross(Vector3.UP).normalized() * (size * 1.4)
			var tb: Basis = Basis(side, Vector3.UP, back * trail_len)
			_trail_mm.set_instance_transform(n, Transform3D(tb, head + back * trail_len * 0.5))
			_trail_mm.set_instance_color(n, col)
		else:
			_trail_mm.set_instance_transform(n, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), head))
		n += 1
	_mm.visible_instance_count = n
	_trail_mm.visible_instance_count = n
	_draw_bolts()


func _draw_bolts() -> void:
	_bolt_mesh.clear_surfaces()
	var alive: Array[Dictionary] = []
	for b: Dictionary in _bolts:
		if _time - float(b["t"]) < BOLT_TIME:
			alive.append(b)
	_bolts = alive
	if _bolts.is_empty():
		return
	_bolt_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: Dictionary in _bolts:
		var col: Color = b["color"]
		var k: float = 1.0 - (_time - float(b["t"])) / BOLT_TIME
		var pts: PackedVector3Array = b["pts"]
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = int(b["seed"]) + int(_time * 30.0)
		for i: int in pts.size() - 1:
			var a: Vector3 = pts[i]
			var c: Vector3 = pts[i + 1]
			var segs: int = maxi(3, int(a.distance_to(c) * 3.0))
			var prev: Vector3 = a
			for s: int in range(1, segs + 1):
				var t: float = float(s) / float(segs)
				var p: Vector3 = a.lerp(c, t)
				if s < segs:
					p += Vector3(rng.randf_range(-0.18, 0.18), rng.randf_range(-0.1, 0.1), rng.randf_range(-0.18, 0.18))
				_quad(prev, p, 0.07 * k + 0.02, Color(col.lightened(0.4), k))
				prev = p
	_bolt_mesh.surface_end()


func _quad(a: Vector3, b: Vector3, width: float, c: Color) -> void:
	var d: Vector3 = b - a
	var side: Vector3 = Vector3(-d.z, 0.0, d.x).normalized() * width
	if side.length_squared() < 0.00001:
		side = Vector3(width, 0, 0)
	for v: Vector3 in [a - side, b - side, a + side, a + side, b - side, b + side]:
		_bolt_mesh.surface_set_color(c)
		_bolt_mesh.surface_add_vertex(v)


func clear() -> void:
	_bolts.clear()
	_mm.visible_instance_count = 0
	_trail_mm.visible_instance_count = 0
	_bolt_mesh.clear_surfaces()
