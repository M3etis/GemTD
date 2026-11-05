class_name FxLayer
extends Node3D
## Эффекты: частицы (пул GPUParticles3D; в Compatibility — CPUParticles3D), лучи раскрытия,
## кольца и ударные волны с искажением, ядовитые лужи, числа урона и подписи.

const RING_SHADER: Shader = preload("res://fx/shaders/ring.gdshader")
const ADD_SHADER: Shader = preload("res://fx/shaders/additive.gdshader")
const POOL_SHADER: Shader = preload("res://fx/shaders/pool.gdshader")
const SHOCK_SHADER: Shader = preload("res://fx/shaders/shockwave.gdshader")
const FLIP_SHADER: Shader = preload("res://fx/shaders/flipbook.gdshader")
## Флипбуки Unity Labs (CC0, assets/vfx): сетка кадров, opacity (1 — дым заслоняет фон, меньше — огонь
## ещё и светит), luma — альфа из яркости (лист без альфы), основание внизу (столбы, пламя).
const FLIPBOOKS: Dictionary = {
	"explosion": {"tex": "vfx_explosion_01_5x5", "grid": Vector2(5, 5), "opacity": 1.0, "luma": 0.0, "bottom": 0.0},
	"smoke": {"tex": "vfx_smoke_wisp_01_8x8", "grid": Vector2(8, 8), "opacity": 1.0, "luma": 0.0, "bottom": 0.0},
	"dust": {"tex": "vfx_dust_column_01_16x4", "grid": Vector2(16, 4), "opacity": 1.0, "luma": 0.0, "bottom": 1.0},
	"fireball": {"tex": "vfx_fireball_01_8x8", "grid": Vector2(8, 8), "opacity": 0.55, "luma": 1.0, "bottom": 0.0},
	"flame": {"tex": "vfx_flame_01_16x4", "grid": Vector2(16, 4), "opacity": 0.55, "luma": 0.0, "bottom": 1.0},
}
## Одновременно живущих флипбуков — сверх лимита новые пропускаются (каждый — прозрачный квад с перекрытием).
const MAX_FLIPBOOKS: int = 24
const MAX_NUMBERS: int = 48
## Пулы одноразовых излучателей: [ёмкость, количество]. Малые — искры попаданий, большие — смерти, сплавы.
const SMALL_CAP: int = 16
const SMALL_COUNT: int = 64
const LARGE_CAP: int = 96
const LARGE_COUNT: int = 16
const VORTEX_COUNT: int = 4
## Бюджет на кадр: сколько мелких вспышек частиц и новых чисел урона можно запустить.
## При 300 врагах на 4× попаданий в кадр больше сотни; сверх бюджета мелкие эффекты пропускаются.
const BURST_BUDGET: int = 24
## Окно агрегации чисел урона по одной цели, секунд.
const AGGREGATE_TIME: float = 0.3
const NUMBER_BUDGET: int = 12

var board: BoardView
var _small: Array[Node3D] = []
var _large: Array[Node3D] = []
var _vortex: Array[Node3D] = []
## Compatibility (OpenGL): перезапуск GPUParticles3D там стоит ~8 мс, поэтому вспышки — на CPUParticles3D.
var _cpu: bool = false
var _small_i: int = 0
var _large_i: int = 0
var _vortex_i: int = 0
var _density: float = 1.0
var _burst_left: int = BURST_BUDGET
var _number_left: int = NUMBER_BUDGET
var _budget_scale: float = 1.0
var _numbers: Array[Label3D] = []
var _number_state: Array[Dictionary] = []
## Индекс подписи по id врага (агрегация чисел без перебора всех подписей).
var _number_by_key: Dictionary = {}
var _transients: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var show_numbers: bool = true
var _flip_quad: QuadMesh
var _flip_mats: Dictionary = {}
var _flip_alive: int = 0


func setup(b: BoardView) -> void:
	board = b
	_rng.seed = 12345
	_cpu = Graphics.is_compatibility()
	apply_quality()
	for i: int in SMALL_COUNT:
		_small.append(_make_burst_emitter(SMALL_CAP))
	for i2: int in LARGE_COUNT:
		_large.append(_make_burst_emitter(LARGE_CAP))
	for i3: int in VORTEX_COUNT:
		_vortex.append(_make_vortex_emitter())
	for i4: int in MAX_NUMBERS:
		var l: Label3D = Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0009
		l.font = UiTokens.font("num")
		l.font_size = 30
		l.outline_size = 8
		l.outline_modulate = Color(0, 0, 0, 0.85)
		l.visible = false
		l.render_priority = 20
		l.outline_render_priority = 19
		add_child(l)
		_numbers.append(l)
		_number_state.append({"t": -1.0})


## Прогрев шейдеров: каждый тип эффекта рисуется один раз невидимым при загрузке арены,
## чтобы первый сплав или взрыв в игре не вызывал рывок из-за компиляции.
func prewarm(at: Vector3) -> void:
	ring(at, Color.BLACK, 0.5, 0.1)
	shockwave(at, Color.BLACK, 0.5, 0.1, 0.0)
	pool(at, Color.BLACK, 0.5, 0.1)
	beam(at, Color.BLACK, 0.5, 0.1)
	link(at, at + Vector3(0.5, 0, 0), Color.BLACK, 0.1)
	burst(at, Color.BLACK, 1, 0.1, 0.01, 0.1)
	burst(at, Color.BLACK, LARGE_CAP, 0.1, 0.01, 0.1)
	vortex(at, Color.BLACK, 0.3)
	for kind: String in FLIPBOOKS:
		flipbook(at, kind, 0.01, 0.1, Color(0, 0, 0, 0))


func apply_quality() -> void:
	_density = Graphics.particle_density()
	# В Compatibility (OpenGL) перезапуск излучателя заметно дороже — бюджет меньше.
	_budget_scale = 0.25 if Graphics.is_compatibility() else 1.0


func _make_burst_emitter(cap: int) -> Node3D:
	if _cpu:
		return _make_cpu_emitter(cap, false)
	var pm: ParticleProcessMaterial = ParticleKit.base_material(Color.WHITE)
	pm.direction = Vector3(0, 1, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.lifetime_randomness = 0.4
	var p: GPUParticles3D = ParticleKit.emitter(cap, 0.6, pm, true)
	p.visible = false
	add_child(p)
	return p


func _make_cpu_emitter(cap: int, vortex_shape: bool) -> CPUParticles3D:
	var c: CPUParticles3D = CPUParticles3D.new()
	c.amount = clampi(int(cap / 2.0), 4, 48)
	c.one_shot = true
	c.explosiveness = 1.0 if not vortex_shape else 0.6
	c.emitting = false
	c.lifetime = 0.6
	c.lifetime_randomness = 0.4
	c.mesh = ParticleKit.quad()
	c.direction = Vector3(0, 1, 0)
	c.damping_min = 1.0
	c.damping_max = 2.0
	c.color_ramp = ParticleKit.fade_ramp().gradient
	c.scale_amount_curve = ParticleKit.shrink_curve().curve
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vortex_shape:
		c.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		c.emission_ring_axis = Vector3(0, 1, 0)
		c.emission_ring_height = 0.2
		c.spread = 10.0
		c.initial_velocity_min = 0.6
		c.initial_velocity_max = 1.4
		c.radial_accel_min = -6.0
		c.radial_accel_max = -3.0
		c.tangential_accel_min = 3.0
		c.tangential_accel_max = 5.0
		c.scale_amount_min = 0.08
		c.scale_amount_max = 0.18
		c.lifetime = 0.9
	c.visible = false
	add_child(c)
	return c


func _make_vortex_emitter() -> Node3D:
	if _cpu:
		return _make_cpu_emitter(LARGE_CAP, true)
	var pm: ParticleProcessMaterial = ParticleKit.base_material(Color.WHITE)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 1, 0)
	pm.emission_ring_height = 0.2
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 10.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.orbit_velocity_min = 0.6
	pm.orbit_velocity_max = 1.0
	pm.radial_accel_min = -6.0
	pm.radial_accel_max = -3.0
	pm.scale_min = 0.08
	pm.scale_max = 0.18
	var p: GPUParticles3D = ParticleKit.emitter(LARGE_CAP, 0.9, pm, true)
	p.explosiveness = 0.6
	p.visible = false
	add_child(p)
	return p


## Взрыв частиц: count штук разлетаются от pos со скоростью speed; up — доля «вверх» (0 — плоско);
## look — спрайт частиц (ParticleKit.SPRITES).
func burst(pos: Vector3, color: Color, count: int, speed: float, size: float, life: float, gravity: float = 6.0, up: float = 1.0, look: String = "glow") -> void:
	var n: int = int(roundf(float(count) * _density))
	if n <= 0:
		return
	var node: Node3D
	var cap: int
	if n <= SMALL_CAP:
		if _burst_left <= 0:
			return
		_burst_left -= 1
		node = _small[_small_i]
		_small_i = (_small_i + 1) % _small.size()
		cap = SMALL_CAP
	else:
		node = _large[_large_i]
		_large_i = (_large_i + 1) % _large.size()
		cap = LARGE_CAP
	var spread: float = lerpf(95.0, 70.0, clampf(up, 0.0, 1.0))
	if node is CPUParticles3D:
		var c: CPUParticles3D = node
		c.color = color
		c.spread = spread
		c.initial_velocity_min = speed * 0.4
		c.initial_velocity_max = speed
		c.gravity = Vector3(0, -gravity, 0)
		c.scale_amount_min = size * 0.6
		c.scale_amount_max = size * 1.3
		c.lifetime = maxf(life, 0.05)
		c.mesh = ParticleKit.sprite_quad(look)
		c.global_position = pos
		c.visible = true
		c.restart()
		return
	var p: GPUParticles3D = node
	var pm: ParticleProcessMaterial = p.process_material
	pm.color = color
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -gravity, 0)
	pm.scale_min = size * 0.6
	pm.scale_max = size * 1.3
	p.lifetime = maxf(life, 0.05)
	p.amount_ratio = clampf(float(n) / float(cap), 0.0, 1.0)
	p.draw_pass_1 = ParticleKit.sprite_quad(look)
	p.global_position = pos
	p.visible = true
	p.restart()


## Флипбук-billboard (FLIPBOOKS): kind — вид, size — сторона квада в метрах, time — длительность клипа.
## Плотность частиц пресета прореживает и флипбуки (Low — каждый второй дым).
func flipbook(pos: Vector3, kind: String, size: float, time: float, color: Color = Color.WHITE, intensity: float = 1.0) -> void:
	if _flip_alive >= MAX_FLIPBOOKS or not FLIPBOOKS.has(kind):
		return
	if _density < 0.99 and _rng.randf() > _density and size > 0.05:
		return
	if not _flip_mats.has(kind):
		var cfg: Dictionary = FLIPBOOKS[kind]
		var path: String = "res://assets/vfx/%s.png" % String(cfg["tex"])
		if not ResourceLoader.exists(path):
			return
		var m0: ShaderMaterial = ShaderMaterial.new()
		m0.shader = FLIP_SHADER
		m0.set_shader_parameter("sheet", load(path))
		m0.set_shader_parameter("grid", cfg["grid"])
		m0.set_shader_parameter("opacity", float(cfg["opacity"]))
		m0.set_shader_parameter("luma_alpha", float(cfg["luma"]))
		m0.set_shader_parameter("pivot_bottom", float(cfg["bottom"]))
		_flip_mats[kind] = m0
	if _flip_quad == null:
		_flip_quad = QuadMesh.new()
		_flip_quad.size = Vector2.ONE
	var m: ShaderMaterial = (_flip_mats[kind] as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("intensity", intensity)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = _flip_quad
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.scale = Vector3.ONE * size
	add_child(mi)
	_flip_alive += 1
	_transients.append({"node": mi, "mat": m, "t": 0.0, "dur": time, "kind": "flip"})


## Вихрь Combine/Forge: частицы по кольцу радиуса radius закручиваются к центру и поднимаются.
func vortex(pos: Vector3, color: Color, radius: float) -> void:
	var node: Node3D = _vortex[_vortex_i]
	_vortex_i = (_vortex_i + 1) % _vortex.size()
	if node is CPUParticles3D:
		var c: CPUParticles3D = node
		c.color = color
		c.emission_ring_radius = radius
		c.emission_ring_inner_radius = radius * 0.8
		c.global_position = pos
		c.visible = true
		c.restart()
		return
	var p: GPUParticles3D = node
	var pm: ParticleProcessMaterial = p.process_material
	pm.color = color
	pm.emission_ring_radius = radius
	pm.emission_ring_inner_radius = radius * 0.8
	p.amount_ratio = clampf(_density, 0.1, 1.0)
	p.global_position = pos
	p.visible = true
	p.restart()


func ring(pos: Vector3, color: Color, radius: float, time: float = 0.45) -> void:
	var mi: MeshInstance3D = _plane(RING_SHADER)
	var m: ShaderMaterial = mi.material_override
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("thickness", 0.12)
	mi.position = pos
	_transients.append({"node": mi, "mat": m, "t": 0.0, "dur": time, "kind": "ring", "radius": radius})


## Ударная волна с искажением изображения (крупные взрывы, фазы босса, Combine/Forge).
func shockwave(pos: Vector3, color: Color, radius: float, time: float = 0.6, strength: float = 0.035) -> void:
	if Settings.reduce_motion() and strength > 0.0:
		ring(pos, color, radius, time)
		return
	var mi: MeshInstance3D = _plane(SHOCK_SHADER)
	var m: ShaderMaterial = mi.material_override
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("strength", strength)
	mi.position = pos
	mi.scale = Vector3(radius, 1, radius)
	_transients.append({"node": mi, "mat": m, "t": 0.0, "dur": time, "kind": "shock"})


func pool(pos: Vector3, color: Color, radius: float, time: float) -> void:
	var mi: MeshInstance3D = _plane(POOL_SHADER)
	var m: ShaderMaterial = mi.material_override
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("seed", _rng.randf() * 10.0)
	mi.position = pos
	mi.scale = Vector3(radius, 1, radius)
	_transients.append({"node": mi, "mat": m, "t": 0.0, "dur": time, "kind": "pool"})


func _plane(shader: Shader) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var p: PlaneMesh = PlaneMesh.new()
	p.size = Vector2(2, 2)
	mi.mesh = p
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = shader
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func beam(pos: Vector3, color: Color, height: float, time: float = 0.9) -> void:
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.18
	cyl.bottom_radius = 0.32
	cyl.height = height
	cyl.radial_segments = 12
	cyl.rings = 1
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = cyl
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = ADD_SHADER
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("intensity", 1.6)
	m.set_shader_parameter("fade_y", 1.0)
	mi.material_override = m
	mi.position = pos + Vector3(0, height * 0.5, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_transients.append({"node": mi, "mat": m, "t": 0.0, "dur": time, "kind": "beam"})


## Светящаяся нить между двумя точками (лучи рецепта при Forge).
func link(a: Vector3, b: Vector3, color: Color, time: float = 0.7) -> void:
	var d: Vector3 = b - a
	var len: float = d.length()
	if len < 0.01:
		return
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.07, 0.07, len)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = box
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = ADD_SHADER
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("intensity", 2.4)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.look_at_from_position((a + b) * 0.5, b, Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT)
	_transients.append({"node": mi, "mat": m, "t": 0.0, "dur": time, "kind": "link"})


## Число урона. key — id врага: частые попадания по одной цели складываются в одно растущее число
## (при большой плотности боя числа не превращаются в кашу).
func number(pos: Vector3, value: float, color: Color, crit: bool, key: int = -1) -> void:
	if not show_numbers:
		return
	if key >= 0 and _number_by_key.has(key):
		var now: float = Time.get_ticks_msec() / 1000.0
		var i: int = int(_number_by_key[key])
		var st: Dictionary = _number_state[i]
		if int(st.get("key", -1)) == key and now - float(st["t"]) < AGGREGATE_TIME:
			var total: float = float(st["value"]) + value
			var is_crit: bool = crit or bool(st["crit"])
			st["value"] = total
			st["crit"] = is_crit
			st["t"] = now
			var l: Label3D = _numbers[i]
			l.text = UiTokens.format_number(total) + ("!" if is_crit else "")
			l.font_size = 40 if is_crit else 30
			if is_crit:
				l.modulate = Color("fff1a8")
			return
	var idx: int = _float_text(pos, UiTokens.format_number(value) + ("!" if crit else ""), color.lightened(0.25) if not crit else Color("fff1a8"), 40 if crit else 28, crit)
	if idx >= 0:
		_number_state[idx]["key"] = key
		_number_state[idx]["value"] = value
		if key >= 0:
			_number_by_key[key] = idx


## Всплывающая подпись над врагом («Иммунитет», «Уклонение»…), живёт как число урона.
func text(pos: Vector3, value: String, color: Color) -> void:
	if not show_numbers:
		return
	_float_text(pos, value, color, 24, false)


## Возвращает индекс использованной подписи или −1 (бюджет кадра исчерпан).
func _float_text(pos: Vector3, value: String, color: Color, font_size: int, crit: bool) -> int:
	if _number_left <= 0 and not crit:
		return -1
	_number_left -= 1
	var best: int = -1
	var oldest: float = INF
	for i: int in _numbers.size():
		var t: float = float(_number_state[i]["t"])
		if t < 0.0:
			best = i
			break
		if t < oldest:
			oldest = t
			best = i
	if best < 0:
		return -1
	var l: Label3D = _numbers[best]
	l.text = value
	l.modulate = color
	l.font_size = font_size
	l.position = pos + Vector3(_rng.randf_range(-0.2, 0.2), 0.0, _rng.randf_range(-0.1, 0.1))
	l.visible = true
	_number_state[best] = {"t": Time.get_ticks_msec() / 1000.0, "start": l.position, "crit": crit}
	return best


func _process(delta: float) -> void:
	_burst_left = maxi(1, int(float(BURST_BUDGET) * _budget_scale))
	_number_left = maxi(1, int(float(NUMBER_BUDGET) * _budget_scale))
	var now: float = Time.get_ticks_msec() / 1000.0
	for i: int in _numbers.size():
		var st: Dictionary = _number_state[i]
		if float(st["t"]) < 0.0:
			continue
		var age: float = now - float(st["t"])
		var dur: float = 0.95 if bool(st.get("crit", false)) else 0.7
		var l: Label3D = _numbers[i]
		if age > dur:
			l.visible = false
			_number_by_key.erase(int(st.get("key", -1)))
			_number_state[i] = {"t": -1.0}
			continue
		l.position = (st["start"] as Vector3) + Vector3(0, 0.25 + age * 1.1, 0)
		l.modulate.a = 1.0 - smoothstep(dur * 0.55, dur, age)
		var pop: float = 1.0 + 0.5 * maxf(0.0, 1.0 - age * 8.0) if bool(st.get("crit", false)) else 1.0
		l.scale = Vector3.ONE * pop
	var alive: Array[Dictionary] = []
	for t: Dictionary in _transients:
		t["t"] = float(t["t"]) + delta
		var k2: float = float(t["t"]) / float(t["dur"])
		var node: MeshInstance3D = t["node"]
		if k2 >= 1.0:
			node.queue_free()
			if String(t["kind"]) == "flip":
				_flip_alive -= 1
			continue
		alive.append(t)
		var mat: ShaderMaterial = t["mat"]
		match String(t["kind"]):
			"pool":
				mat.set_shader_parameter("intensity", minf(1.0, k2 * 8.0) * (1.0 - smoothstep(0.75, 1.0, k2)))
			"ring":
				var r: float = float(t["radius"]) * ease(k2, 0.35)
				node.scale = Vector3(maxf(r, 0.01), 1, maxf(r, 0.01))
				mat.set_shader_parameter("intensity", 2.0 * (1.0 - k2))
			"shock":
				mat.set_shader_parameter("progress", ease(k2, 0.4))
			"link":
				mat.set_shader_parameter("intensity", 2.4 * (1.0 - k2 * k2))
			"flip":
				mat.set_shader_parameter("progress", k2)
			_:
				node.scale = Vector3(1.0 - k2 * 0.6, 1.0, 1.0 - k2 * 0.6)
				mat.set_shader_parameter("intensity", 1.8 * (1.0 - k2) * (1.0 - k2))
	_transients = alive
