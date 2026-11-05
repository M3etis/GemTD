class_name ArtKit
extends RefCounted
## Ассеты и материалы арт-дирекшна «Обсидиановая сокровищница» (ART_DIRECTION.md): палитра окружения,
## PBR-текстуры, меши сканов, HDRI. Источники и лицензии — assets/LICENSES.md, подготовка — tools/bake_art_assets.gd.
## Только визуал: цвета гемов и врагов в data/*.json не меняются (они входят в хеш данных).

const BOARD_SHADER: Shader = preload("res://fx/shaders/board.gdshader")
const ROCK_SHADER: Shader = preload("res://fx/shaders/rock.gdshader")

const TEX: String = "res://assets/textures/env/"
const MESH: String = "res://assets/environment/"
const SKY_HDRI: String = "res://assets/hdri/env_sky_night_01_4k.hdr"

## Палитра окружения и света (ART_DIRECTION.md §3, §5).
const INK: Color = Color("07080d")
const FOG: Color = Color("161a3a")
const LIMESTONE: Color = Color("d8d0bf")
const OBSIDIAN: Color = Color("15131c")
const VEIN: Color = Color("6e5bff")
const BRASS: Color = Color("c9a45c")
const ICE: Color = Color("7cc4ff")
const KEY_LIGHT: Color = Color("ffe2b8")
const RIM_LIGHT: Color = Color("8fb0ff")

## Готовые огранки гемов (Sketchfab «Gems (21 different shapes)» и «Gemstone Pack», CC BY 4.0).
## Силуэт в плане у каждого гема свой: это второй признак после цвета (палитра для дальтоников).
## Гем без огранки (или без файла) рисуется процедурным мешем MeshFactory.
const GEM_CUTS: Dictionary = {
	"ruby": "gem_cut_marquise", "sapphire": "gem_cut_cushion", "emerald": "gem_cut_emerald", "topaz": "gem_cut_pear",
	"amethyst": "gem_cut_trilliant", "aquamarine": "gem_cut_octagon", "opal": "gem_cut_cabochon", "diamond": "gem_cut_round",
}
## Огранка нормирована к ширине 1 — масштаб к размеру процедурного кристалла.
const CUT_SCALE: float = 0.56
## Наклон стола огранки к камере (она смотрит сверху-спереди под 57°): видна площадка и игра граней.
const CUT_TILT: float = -0.55
## Высота чаши колонны-пьедестала, куда садится кристалл.
const PEDESTAL_TOP: float = 0.74
## Спец-башни стоят на приземистом варианте той же колонны: высокая подняла бы и без того крупные
## силуэты над полем. Масштаб цоколя и высота его верха.
const PLINTH_SCALE: Vector3 = Vector3(1.3, 0.45, 1.3)
const PLINTH_TOP: float = 0.34
## Полировка по качеству I–V: «осколок» матовый, «призматический» — зеркальный.
const POLISH: Array[float] = [0.25, 0.5, 0.8, 0.92, 1.0]

const ENEMY_VAT_SHADER: Shader = preload("res://fx/shaders/enemy_vat.gdshader")
## Враги с запечённой анимацией (tools/bake_enemy_vat.gd: VAT + PBR-атлас): архетип → модель.
## Архетип без модели (или без файла) рисуется прежним мешем MeshFactory.
const ENEMY_MODELS: Dictionary = {
	"normal": "char_enemy_pachy_01", "fast": "char_enemy_raptor_01", "armored": "char_enemy_bug_01",
	"flying": "char_enemy_bat_01", "swarm": "char_enemy_spider_01", "regenerating": "char_enemy_stego_01",
	"shielded": "char_enemy_pteran_01", "minion": "char_enemy_drone_01", "arcane_resistant": "char_enemy_shadowkin_01",
	"splitter": "char_enemy_crystal_cluster_01", "splitling": "char_enemy_crystal_shard_01",
	"boss_stone": "char_boss_hound_01", "boss_sky": "char_boss_stonewisp_01", "boss_summoner": "char_boss_queen_01",
	"boss_final": "char_boss_knight_01", "colossus": "char_boss_troll_01",
}
## Ширина модели по большей горизонтальной оси (tools/bake_enemy_vat.gd, TARGET_WIDTH).
const ENEMY_WIDTH: float = 1.7
## Подстройки вида модели: stride — путь за цикл ходьбы в ширинах модели (шаг ног совпадает с ходом по полю;
## без него — замер бейкера, мета stride меша; у летающих — flap, цикл по времени), scale — множитель размера (тонкие силуэты: паук, раптор, мышь),
## tint — доля цвета архетипа, rim — цветной ободок, gain — яркость альбедо, glow — сила эмиссии атласа,
## glow_tint — эмиссия окрашивается цветом архетипа (маска прожилок у кристаллов).
## Поле светлое: альбедо приглушено, а ободок цвета архетипа обводит силуэт — враг читается и мелким.
const ENEMY_LOOK_DEFAULT: Dictionary = {"stride": 1.0, "scale": 1.0, "tint": 0.35, "rim": 0.8, "gain": 0.62, "glow": 1.0, "glow_tint": 0.0}
const ENEMY_LOOK: Dictionary = {
	"char_enemy_pachy_01": {"stride": 0.9},
	"char_enemy_raptor_01": {"stride": 1.6, "scale": 1.25},
	"char_enemy_stego_01": {"stride": 0.8},
	"char_enemy_bug_01": {"stride": 1.0, "gain": 0.5},
	"char_enemy_drone_01": {"stride": 1.0, "gain": 0.55},
	"char_enemy_pteran_01": {"stride": 0.7},
	"char_enemy_crystal_cluster_01": {"flap": 1.0, "glow": 2.4, "glow_tint": 1.0, "tint": 0.45, "gain": 1.0},
	"char_enemy_crystal_shard_01": {"stride": 1.1, "glow": 2.4, "glow_tint": 1.0, "tint": 0.45, "gain": 1.0},
	"char_enemy_spider_01": {"stride": 0.8, "scale": 1.6, "gain": 0.5},
	"char_enemy_bat_01": {"flap": 1.0, "scale": 1.35},
	"char_boss_hound_01": {"scale": 1.35, "glow": 2.4, "tint": 0.2, "gain": 0.75},
	"char_boss_stonewisp_01": {"flap": 1.0, "glow": 2.0, "gain": 0.7},
	"char_boss_queen_01": {"stride": 0.8, "gain": 0.6},
	"char_boss_knight_01": {"tint": 0.15, "gain": 0.8, "rim": 0.45},
	"char_boss_troll_01": {"stride": 0.7, "tint": 0.2, "gain": 0.7, "rim": 0.5},
}

static var _cache: Dictionary = {}


static func _tex(name: String) -> Texture2D:
	var path: String = TEX + name + ".png"
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


## Пол арены (известняк Tiles139).
static func board_material(board_size: Vector2) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = BOARD_SHADER
	m.set_shader_parameter("board_size", board_size)
	m.set_shader_parameter("albedo_tex", _tex("env_arena_floor_01_albedo_2k"))
	m.set_shader_parameter("normal_tex", _tex("env_arena_floor_01_normal_2k"))
	m.set_shader_parameter("orm_tex", _tex("env_arena_floor_01_orm_2k"))
	# Ночной HDRI и тёплый ключ дают камню розоватый отлив — тон чуть сдвинут к жёлтому известняку #D8D0BF.
	m.set_shader_parameter("tint", Color(1.05, 1.03, 0.97))
	return m


## Обсидиан (Rock035 трипланарно). vein — цвет тлеющих прожилок, base — тон камня.
static func rock_material(base: Color = OBSIDIAN, vein: Color = VEIN, vein_energy: float = 0.35) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = ROCK_SHADER
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("vein_color", vein)
	m.set_shader_parameter("vein_energy", vein_energy)
	m.set_shader_parameter("albedo_tex", _tex("env_wall_obsidian_01_albedo_2k"))
	m.set_shader_parameter("normal_tex", _tex("env_wall_obsidian_01_normal_2k"))
	m.set_shader_parameter("orm_tex", _tex("env_wall_obsidian_01_orm_2k"))
	return m


## Материал блока стены: обсидиан + собственная нормаль скана по UV.
static func wall_material() -> ShaderMaterial:
	var m: ShaderMaterial = rock_material(OBSIDIAN, VEIN, 0.3)
	var dn: Texture2D = _tex("env_wall_block_01_normal_1k")
	if dn != null:
		m.set_shader_parameter("use_uv_detail", true)
		m.set_shader_parameter("detail_normal", dn)
		m.set_shader_parameter("detail_orm", _tex("env_wall_block_01_orm_1k"))
	return m


## Блок стены (скан moon_rock_02, упрощён до ~400 треугольников). Нет файла — процедурный блок.
static func wall_mesh() -> Mesh:
	var path: String = MESH + "env_wall_block_01.res"
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else MeshFactory.rock_mesh()
	return _cache[path]


## Скалы бездны (Poly Haven boulder_01, rock_face_01): тёмная тонировка, чтобы фон не спорил с полем.
static func abyss_rock(id: String) -> Dictionary:
	var path: String = MESH + id + ".res"
	if not _cache.has(path):
		var mesh: Mesh = load(path) if ResourceLoader.exists(path) else null
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_texture = _tex(id + "_albedo_1k")
		m.albedo_color = Color("24262e")
		m.normal_enabled = true
		m.normal_texture = _tex(id + "_normal_1k")
		m.ao_enabled = true
		m.ao_texture = _tex(id + "_orm_1k")
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness_texture = _tex(id + "_orm_1k")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_cache[path] = {"mesh": mesh, "mat": m}
	return _cache[path]


## Латунь: кромка рамки поля, пояски пьедесталов.
static func brass_material() -> StandardMaterial3D:
	if not _cache.has("brass"):
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = BRASS
		m.metallic = 1.0
		m.roughness = 0.38
		_cache["brass"] = m
	return _cache["brass"]


## Огранка гема или null (тогда — процедурный меш).
static func gem_cut(gem_id: String) -> Mesh:
	if not GEM_CUTS.has(gem_id):
		return null
	var path: String = "res://assets/characters/gems/%s.res" % String(GEM_CUTS[gem_id])
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


static func gem_polish(quality: int) -> float:
	return POLISH[clampi(quality, 1, 5) - 1]


## Колонна-пьедестал (Sketchfab «Antique Classical Pedestal Stands Type C», CC BY 4.0) или null.
static func pedestal_column() -> Mesh:
	var path: String = "res://assets/props/prop_pedestal_column_01.res"
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


## Камень колонны затемнён до базальта: светлый мрамор сливался бы со светлым полем.
static func pedestal_material() -> StandardMaterial3D:
	if not _cache.has("pedestal_mat"):
		var m: StandardMaterial3D = StandardMaterial3D.new()
		var tex: String = "res://assets/textures/props/prop_pedestal_column_01_%s_1k.png"
		m.albedo_texture = load(tex % "albedo")
		m.albedo_color = Color("4a4750")
		m.normal_enabled = true
		m.normal_texture = load(tex % "normal")
		m.roughness_texture = load(tex % "orm")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic_texture = load(tex % "orm")
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.metallic = 1.0
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_cache["pedestal_mat"] = m
	return _cache["pedestal_mat"]


## Латунный поясок шестигранного цоколя (пьедесталы гемов): radius — по граням, y — высота пояска.
static func brass_band(radius: float, y: float) -> MeshInstance3D:
	if not _cache.has("band_%.2f" % radius):
		var c: CylinderMesh = CylinderMesh.new()
		c.top_radius = radius
		c.bottom_radius = radius
		c.height = 0.035
		c.radial_segments = 6
		c.rings = 1
		_cache["band_%.2f" % radius] = c
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = _cache["band_%.2f" % radius]
	mi.material_override = brass_material()
	mi.position.y = y
	mi.rotation.y = PI / 6.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Модель врага с VAT для архетипа или null.
static func enemy_vat(archetype: String) -> ArrayMesh:
	if not ENEMY_MODELS.has(archetype):
		return null
	var path: String = "res://assets/characters/enemies/%s.res" % String(ENEMY_MODELS[archetype])
	if not _cache.has(path):
		_cache[path] = load(path) as ArrayMesh if ResourceLoader.exists(path) else null
	return _cache[path]


static func enemy_look(model_id: String) -> Dictionary:
	var look: Dictionary = ENEMY_LOOK_DEFAULT.duplicate()
	look.merge(ENEMY_LOOK.get(model_id, {}), true)
	return look


## Путь за цикл ходьбы в ширинах модели: подстройка ENEMY_LOOK, иначе замер бейкера (мета stride), иначе 1.
static func enemy_stride(mesh: ArrayMesh) -> float:
	var own: Dictionary = ENEMY_LOOK.get(mesh.resource_name, {})
	if own.has("stride"):
		return float(own["stride"])
	return float(mesh.get_meta("stride", ENEMY_LOOK_DEFAULT["stride"]))


## Материал VAT-врага: позы из меты меша, карты атласа из assets/textures/characters.
static func enemy_vat_material(mesh: ArrayMesh) -> ShaderMaterial:
	var id: String = mesh.resource_name
	var look: Dictionary = enemy_look(id)
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = ENEMY_VAT_SHADER
	m.set_shader_parameter("vat_pos", mesh.get_meta("vat_pos"))
	m.set_shader_parameter("vat_nrm", mesh.get_meta("vat_nrm"))
	m.set_shader_parameter("rows", int(mesh.get_meta("rows", 1)))
	m.set_shader_parameter("loop_frames", int(mesh.get_meta("loop_frames", 1)))
	m.set_shader_parameter("death_frames", int(mesh.get_meta("death_frames", 0)))
	var tex: String = "res://assets/textures/characters/%s_%s.jpg"
	for map: String in ["albedo", "normal", "orm", "emission"]:
		if ResourceLoader.exists(tex % [id, map]):
			m.set_shader_parameter(map + "_tex", load(tex % [id, map]))
	m.set_shader_parameter("emission_energy", float(look["glow"]) if bool(mesh.get_meta("emission", false)) else 0.0)
	m.set_shader_parameter("emission_tint", float(look["glow_tint"]))
	m.set_shader_parameter("tint", float(look["tint"]))
	m.set_shader_parameter("rim", float(look["rim"]))
	m.set_shader_parameter("albedo_gain", float(look["gain"]))
	return m


## Небо HDRI — только для фонового освещения и отражений: камера горизонта не видит, фон остаётся своим.
static func sky(energy: float) -> Sky:
	var s: Sky = Sky.new()
	var pm: PanoramaSkyMaterial = PanoramaSkyMaterial.new()
	pm.panorama = load(SKY_HDRI) if ResourceLoader.exists(SKY_HDRI) else null
	pm.energy_multiplier = energy
	s.sky_material = pm
	s.radiance_size = Sky.RADIANCE_SIZE_128
	return s
