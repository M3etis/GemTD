class_name ParticleKit
extends RefCounted
## Фабрика GPUParticles3D: спрайты частиц и готовые «рецепты» постоянных эффектов
## (искры гемов V, дыхание спец-башен, вихрь портала, пыль над ареной).
## Спрайты — маски Kenney Particle Pack (CC0, assets/vfx, tools/bake_art_assets.gd -- --vfx), цвет даёт частица:
## glow — мягкое пятно, flare — блик с тонким крестом, star — звезда-искра, bolt — молния, twirl — завиток.
## Плотность умножается на пресет графики (Graphics.particle_density).

const SPRITES: Dictionary = {
	"glow": "vfx_spark_glow_01", "flare": "vfx_spark_flare_01", "star": "vfx_spark_star_01",
	"bolt": "vfx_bolt_01", "twirl": "vfx_twirl_01", "streak": "vfx_streak_01",
}
## Размер квада под спрайт: у масок поля и яркое ядро меньше кадра — частица того же scale
## должна выглядеть как прежнее мягкое пятно во весь квад.
const SPRITE_SIZE: Dictionary = {"glow": 1.25, "flare": 3.0, "star": 2.4, "bolt": 1.6, "twirl": 1.6, "streak": 1.6}

static var _draw_mat: StandardMaterial3D
static var _sprite_quads: Dictionary = {}
static var _soft_tex: GradientTexture2D
static var _fade_ramp: GradientTexture1D
static var _shrink_curve: CurveTexture


## Мягкий круглый аддитивный billboard-спрайт; цвет берётся из частицы.
static func draw_material() -> StandardMaterial3D:
	if _draw_mat == null:
		_soft_tex = GradientTexture2D.new()
		_soft_tex.fill = GradientTexture2D.FILL_RADIAL
		_soft_tex.fill_from = Vector2(0.5, 0.5)
		_soft_tex.fill_to = Vector2(0.5, 0.0)
		_soft_tex.width = 64
		_soft_tex.height = 64
		var g: Gradient = Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.55))
		_soft_tex.gradient = g
		_draw_mat = StandardMaterial3D.new()
		_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_draw_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		# Без этого billboard-частицы игнорируют свой масштаб и рисуются размером 1 м.
		_draw_mat.billboard_keep_scale = true
		_draw_mat.vertex_color_use_as_albedo = true
		_draw_mat.albedo_texture = _soft_tex
		_draw_mat.disable_receive_shadows = true
	return _draw_mat


## Спрайт частиц по имени (SPRITES) или null — тогда мягкий круг.
static func sprite(name: String) -> Texture2D:
	var path: String = "res://assets/vfx/%s.png" % String(SPRITES.get(name, ""))
	return load(path) as Texture2D if SPRITES.has(name) and ResourceLoader.exists(path) else null


## Квад частицы со спрайтом. Маска в L и A, смешивание premultiplied: частица светит и на 60 % заслоняет
## фон — на светлом поле чистое сложение уходило в белое и искры пропадали.
static func sprite_quad(name: String) -> QuadMesh:
	if not _sprite_quads.has(name):
		var q: QuadMesh = quad()
		var tex: Texture2D = sprite(name)
		if tex != null:
			q.size = Vector2.ONE * float(SPRITE_SIZE.get(name, 1.0))
			var m: StandardMaterial3D = draw_material().duplicate() as StandardMaterial3D
			m.albedo_texture = tex
			m.blend_mode = BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA
			m.albedo_color = Color(1.0, 1.0, 1.0, 0.6)
			q.material = m
		_sprite_quads[name] = q
	return _sprite_quads[name]


static func quad() -> QuadMesh:
	var q: QuadMesh = QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = draw_material()
	return q


## Затухание к чёрному (для аддитивного смешивания это и есть исчезновение).
static func fade_ramp() -> GradientTexture1D:
	if _fade_ramp == null:
		var g: Gradient = Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(0, 0, 0, 0))
		g.add_point(0.6, Color(0.75, 0.75, 0.75, 1))
		_fade_ramp = GradientTexture1D.new()
		_fade_ramp.gradient = g
	return _fade_ramp


static func shrink_curve() -> CurveTexture:
	if _shrink_curve == null:
		var c: Curve = Curve.new()
		c.add_point(Vector2(0.0, 1.0))
		c.add_point(Vector2(1.0, 0.35))
		_shrink_curve = CurveTexture.new()
		_shrink_curve.curve = c
	return _shrink_curve


static func emitter(amount: int, lifetime: float, pm: ParticleProcessMaterial, one_shot: bool, look: String = "glow") -> GPUParticles3D:
	var p: GPUParticles3D = GPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = 1.0 if one_shot else 0.0
	p.process_material = pm
	p.draw_pass_1 = sprite_quad(look)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 10, 12))
	p.emitting = not one_shot
	return p


static func base_material(color: Color) -> ParticleProcessMaterial:
	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.color = color
	pm.color_ramp = fade_ramp()
	pm.scale_curve = shrink_curve()
	pm.gravity = Vector3.ZERO
	return pm


static func scaled(amount: int) -> int:
	return maxi(1, int(roundf(float(amount) * Graphics.particle_density())))


## Мерцающие искры вокруг гема V качества.
static func sparkle(color: Color, radius: float) -> GPUParticles3D:
	var pm: ParticleProcessMaterial = base_material(color.lightened(0.35))
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = radius
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.scale_min = 0.05
	pm.scale_max = 0.11
	var p: GPUParticles3D = emitter(scaled(14), 1.6, pm, false, "star")
	p.local_coords = true
	return p


## «Дыхание» спец-башни: kind — rise (угли вверх), fall (иней вниз), orbit (вихрь вокруг).
static func aura(color: Color, kind: String) -> GPUParticles3D:
	var pm: ParticleProcessMaterial = base_material(color)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 1, 0)
	pm.emission_ring_radius = 0.55
	pm.emission_ring_inner_radius = 0.2
	pm.emission_ring_height = 0.1
	pm.scale_min = 0.06
	pm.scale_max = 0.14
	match kind:
		"fall":
			pm.direction = Vector3(0, -1, 0)
			pm.spread = 25.0
			pm.initial_velocity_min = 0.1
			pm.initial_velocity_max = 0.3
			pm.emission_ring_height = 0.2
		"orbit":
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 10.0
			pm.initial_velocity_min = 0.1
			pm.initial_velocity_max = 0.25
			pm.orbit_velocity_min = 0.25
			pm.orbit_velocity_max = 0.45
		_:
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 15.0
			pm.initial_velocity_min = 0.35
			pm.initial_velocity_max = 0.7
	var p: GPUParticles3D = emitter(scaled(18), 1.8, pm, false, {"fall": "star", "orbit": "glow"}.get(kind, "flare"))
	p.local_coords = true
	if kind == "fall":
		p.position.y = 1.4
	return p


## Вихрь портала: частицы по кольцу закручиваются к центру.
static func portal_swirl(color: Color) -> GPUParticles3D:
	var pm: ParticleProcessMaterial = base_material(color)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 0, 1)
	pm.emission_ring_radius = 0.7
	pm.emission_ring_inner_radius = 0.6
	pm.emission_ring_height = 0.05
	pm.orbit_velocity_min = 0.4
	pm.orbit_velocity_max = 0.7
	pm.radial_accel_min = -1.2
	pm.radial_accel_max = -0.6
	pm.scale_min = 0.05
	pm.scale_max = 0.12
	pm.particle_flag_disable_z = false
	var p: GPUParticles3D = emitter(scaled(40), 1.4, pm, false)
	p.local_coords = true
	return p


## Пыль над ареной: медленно дрейфующие светящиеся пылинки в объёме поля.
static func motes(extents: Vector3, amount: int) -> GPUParticles3D:
	# Яркость ниже порога glow: иначе bloom раздувает пылинки в крупные пятна.
	var pm: ParticleProcessMaterial = base_material(Color(0.3, 0.42, 0.85))
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0.3, 1, 0.1)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.2
	pm.turbulence_enabled = not Graphics.is_compatibility()
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 6.0
	pm.scale_min = 0.03
	pm.scale_max = 0.07
	var c: Gradient = Gradient.new()
	c.set_color(0, Color(0, 0, 0, 0))
	c.add_point(0.3, Color(0.8, 0.8, 0.8, 1))
	c.set_color(c.get_point_count() - 1, Color(0, 0, 0, 0))
	var ramp: GradientTexture1D = GradientTexture1D.new()
	ramp.gradient = c
	pm.color_ramp = ramp
	var p: GPUParticles3D = emitter(maxi(1, amount), 9.0, pm, false)
	p.visibility_aabb = AABB(-extents - Vector3(2, 2, 2), extents * 2.0 + Vector3(4, 6, 4))
	p.preprocess = 6.0
	return p
