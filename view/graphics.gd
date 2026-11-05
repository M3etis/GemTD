class_name Graphics
extends RefCounted
## Пресеты качества графики (Low / Medium / High / Ultra) и общий «тёмный» вид окружения арены и меню.
## Это настройки рендера, а не баланс игры, поэтому они живут в коде (см. DECISIONS).
## В Compatibility-рендере (OpenGL) недоступные эффекты отключаются автоматически.

const ORDER: Array[String] = ["low", "medium", "high", "ultra"]
const DEFAULT: String = "high"
const GEM_PLAIN: Shader = preload("res://fx/shaders/gem.gdshader")
const GEM_REFRACT: Shader = preload("res://fx/shaders/gem_refract.gdshader")
const PRESETS: Dictionary = {
	"low": {"glow": false, "ssao": false, "ssil": false, "fog": false, "msaa": Viewport.MSAA_DISABLED, "taa": false, "fxaa": true,
		"shadows": false, "shadow_size": 1024, "particles": 0.4, "tower_lights": false, "render_scale": 0.75, "refraction": false,
		"ambient_motes": 0},
	"medium": {"glow": true, "ssao": false, "ssil": false, "fog": false, "msaa": Viewport.MSAA_2X, "taa": false, "fxaa": false,
		"shadows": true, "shadow_size": 2048, "particles": 0.7, "tower_lights": true, "render_scale": 0.9, "refraction": true,
		"ambient_motes": 120},
	"high": {"glow": true, "ssao": true, "ssil": false, "fog": true, "msaa": Viewport.MSAA_2X, "taa": false, "fxaa": false,
		"shadows": true, "shadow_size": 4096, "particles": 1.0, "tower_lights": true, "render_scale": 1.0, "refraction": true,
		"ambient_motes": 240},
	"ultra": {"glow": true, "ssao": true, "ssil": true, "fog": true, "msaa": Viewport.MSAA_4X, "taa": true, "fxaa": false,
		"shadows": true, "shadow_size": 8192, "particles": 1.35, "tower_lights": true, "render_scale": 1.0, "refraction": true,
		"ambient_motes": 400},
}


## Пресет из настроек; `--preset=low|medium|high|ultra` в командной строке перекрывает его (замеры, скриншоты).
static func preset_id() -> String:
	var cli: Dictionary = Game.parse_cli(OS.get_cmdline_user_args())
	var id: String = String(cli.get("preset", Settings.get_value("video", "preset")))
	return id if PRESETS.has(id) else DEFAULT


## Параметры пресета. В Compatibility (OpenGL) каждый точечный источник — отдельный проход по объектам,
## а чтение экранной текстуры копирует буфер: свет башен и преломление там выключаются.
static func preset() -> Dictionary:
	var p: Dictionary = PRESETS[preset_id()]
	if is_compatibility():
		p = p.duplicate()
		p["tower_lights"] = false
		p["refraction"] = false
	return p


static func is_compatibility() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


static func particle_density() -> float:
	return float(preset()["particles"])


## Масштаб 3D-рендера: настройка игрока (0 — по пресету).
static func render_scale() -> float:
	var s: float = float(Settings.get_value("video", "render_scale"))
	return clampf(s, 0.5, 1.0) if s > 0.0 else float(preset()["render_scale"])


## Сглаживание и масштаб рендера — на уровне окна.
static func apply_viewport(vp: Viewport) -> void:
	var p: Dictionary = preset()
	vp.msaa_3d = int(p["msaa"]) as Viewport.MSAA
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if bool(p["fxaa"]) else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = bool(p["taa"]) and not is_compatibility()
	var scale: float = render_scale()
	vp.scaling_3d_scale = scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if scale >= 0.999 or is_compatibility() else Viewport.SCALING_3D_MODE_FSR


## Общий вид окружения: фон, туман, тонмаппинг AgX, мягкое тонирование. look — "arena" или "menu".
static func make_environment(look: String) -> Environment:
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = UiTokens.BG
	# Фоновый свет и отражения — от ночного HDRI (ART_DIRECTION.md §5): тени индиго, а не чёрные.
	# Фон остаётся своим цветом: камера горизонта не видит.
	e.sky = ArtKit.sky(1.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_color = Color("262a45")
	e.ambient_light_sky_contribution = 0.55
	e.ambient_light_energy = 0.9 if look == "arena" else 0.8
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.05
	e.glow_intensity = 0.85 if look == "arena" else 1.0
	e.glow_bloom = 0.06 if look == "arena" else 0.1
	e.glow_hdr_threshold = 0.85 if look == "arena" else 0.8
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.set_glow_level(0, 0.0)
	e.set_glow_level(1, 1.0)
	e.set_glow_level(2, 0.8)
	e.set_glow_level(3, 0.6)
	e.set_glow_level(4, 0.4)
	e.ssao_radius = 1.2
	e.ssao_intensity = 1.6
	e.ssil_radius = 3.0
	e.ssil_intensity = 0.6
	e.fog_light_color = ArtKit.FOG
	e.fog_light_energy = 1.0
	# Туман только за ареной: камера в ~45 м от поля, дальний край поля — около 55 м.
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_depth_begin = 56.0 if look == "arena" else 6.0
	e.fog_depth_end = 110.0 if look == "arena" else 30.0
	e.fog_depth_curve = 1.4
	# Грейдинг: чуть больше контраста, насыщенность почти нейтральная — цвет несут гемы, а не окружение.
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.05
	e.adjustment_contrast = 1.08
	e.adjustment_brightness = 1.0
	apply_environment(e, look)
	return e


static func apply_environment(e: Environment, look: String = "arena") -> void:
	var p: Dictionary = preset()
	var compat: bool = is_compatibility()
	e.glow_enabled = bool(p["glow"])
	e.ssao_enabled = bool(p["ssao"]) and not compat
	e.ssil_enabled = bool(p["ssil"]) and not compat
	# В меню мягкий туман нужен на любом пресете — он и есть «фон» сцены.
	e.fog_enabled = bool(p["fog"]) or look == "menu"


## Шейдер кристаллов: с преломлением (экранная текстура) на Medium+ или простой на Low.
static func gem_shader() -> Shader:
	return GEM_REFRACT if bool(preset()["refraction"]) else GEM_PLAIN


static func apply_sun(sun: DirectionalLight3D) -> void:
	var p: Dictionary = preset()
	sun.shadow_enabled = bool(p["shadows"])
	sun.directional_shadow_max_distance = 60.0
	RenderingServer.directional_shadow_atlas_set_size(int(p["shadow_size"]), true)
