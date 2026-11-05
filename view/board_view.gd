class_name BoardView
extends Node3D
## Арена: поле, чекпоинты, портал, цитадель, стены, гемы, путь и превью постановки.

const ABYSS_SHADER: Shader = preload("res://fx/shaders/abyss.gdshader")
const PORTAL_SHADER: Shader = preload("res://fx/shaders/portal.gdshader")
const PATH_SHADER: Shader = preload("res://fx/shaders/path.gdshader")
const RING_SHADER: Shader = preload("res://fx/shaders/ring.gdshader")
const GHOST_SHADER: Shader = preload("res://fx/shaders/ghost.gdshader")

const MAX_ROCKS: int = 1200
const GEM_SCALE: float = 1.45
## Окраска «дыхания» спец-башни по силуэту: rise — угли вверх, fall — иней вниз, orbit — вихрь.
const SPECIAL_AURA: Dictionary = {
	"beacon": "orbit", "crown": "rise", "ballista": "rise", "well": "fall", "bloom": "rise", "obelisk": "fall",
	"geode": "orbit", "spire": "orbit", "prism": "rise", "heart": "rise", "idol": "orbit", "banner": "rise", "blade": "fall",
}
## Длительность отдачи кристалла при выстреле, с.
const KICK_TIME: float = 0.16

var sim: GameSim
var width: int = 32
var height: int = 24
var board_mat: ShaderMaterial
var wall_mat: ShaderMaterial
var rock_mm: MultiMesh
var rock_cells: Array[Vector2i] = []
var rock_spawn: Dictionary = {}
var gem_nodes: Dictionary = {}
## Плиты слейтов по клеткам (клетка проходима — отдельно от gem_nodes).
var slate_nodes: Dictionary = {}
var path_mesh: MeshInstance3D
var preview_mesh: MeshInstance3D
var air_mesh: MeshInstance3D
var ghost: MeshInstance3D
var ghost_mat: ShaderMaterial
var range_ring: MeshInstance3D
var range_mat: ShaderMaterial
var aura_rings: Array[MeshInstance3D] = []
var citadel_mats: Array[ShaderMaterial] = []
var pad_mats: Array[ShaderMaterial] = []
var _time: float = 0.0
## Окружение за ареной (пересоздаётся при смене пресета графики).
var _env_root: Node3D
var _portal_cell: Vector2i = Vector2i.ZERO
var _portal_fx: Node3D


func setup(target: GameSim) -> void:
	sim = target
	width = sim.grid.width
	height = sim.grid.height
	_build_ground()
	_build_environment()
	_build_route_markers()
	_build_rocks()
	_build_path_meshes()
	_build_ghost()
	sync_from_sim()


static func to_world(p: Vector2, y: float = 0.0, w: int = 32, h: int = 24) -> Vector3:
	return Vector3(p.x - float(w) * 0.5, y, p.y - float(h) * 0.5)


func w(p: Vector2, y: float = 0.0) -> Vector3:
	return to_world(p, y, width, height)


func cell_world(c: Vector2i, y: float = 0.0) -> Vector3:
	return w(BoardGrid.center(c), y)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floorf(p.x + float(width) * 0.5)), int(floorf(p.z + float(height) * 0.5)))


# --- Построение ------------------------------------------------------------

func _build_ground() -> void:
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(width, height)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = plane
	board_mat = ArtKit.board_material(Vector2(width, height))
	var img: Image = Image.create(width, height, false, Image.FORMAT_R8)
	for y: int in height:
		for x: int in width:
			img.set_pixel(x, y, Color(1, 0, 0) if sim.grid.is_no_build(Vector2i(x, y)) else Color(0, 0, 0))
	board_mat.set_shader_parameter("zone_tex", ImageTexture.create_from_image(img))
	mi.material_override = board_mat
	add_child(mi)
	# Подложка и рамка арены.
	var under: MeshInstance3D = MeshInstance3D.new()
	var under_mesh: PlaneMesh = PlaneMesh.new()
	under_mesh.size = Vector2(width + 120, height + 120)
	under.mesh = under_mesh
	var under_mat: ShaderMaterial = ShaderMaterial.new()
	under_mat.shader = ABYSS_SHADER
	under_mat.set_shader_parameter("arena_half", Vector2(float(width) * 0.5 + 0.5, float(height) * 0.5 + 0.5))
	under.material_override = under_mat
	under.position.y = -0.4
	add_child(under)
	# Рамка: обсидиановый бортик с латунной кромкой (синий цвет в кадре оставлен только пути врагов).
	var frame_mat: ShaderMaterial = ArtKit.rock_material(ArtKit.OBSIDIAN, ArtKit.VEIN, 0.15)
	for side: int in 4:
		var horizontal: bool = side < 2
		var pos: Vector3 = Vector3(0.0 if horizontal else (float(width) * 0.5 + 0.12) * (1.0 if side == 2 else -1.0), -0.2,
			(float(height) * 0.5 + 0.12) * (1.0 if side == 0 else -1.0) if horizontal else 0.0)
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(width + 0.5 if horizontal else 0.25, 0.5, 0.25 if horizontal else height + 0.5)
		var b: MeshInstance3D = MeshInstance3D.new()
		b.mesh = box
		b.material_override = frame_mat
		b.position = pos
		add_child(b)
		var trim: BoxMesh = BoxMesh.new()
		trim.size = Vector3(width + 0.56 if horizontal else 0.3, 0.05, 0.3 if horizontal else height + 0.56)
		var t: MeshInstance3D = MeshInstance3D.new()
		t.mesh = trim
		t.material_override = ArtKit.brass_material()
		t.position = pos + Vector3(0, 0.26, 0)
		add_child(t)


## Окружение: обломки скал (сканы Poly Haven), парящие в бездне вокруг арены, и пыль (плотность — по пресету).
## Раскладка фиксированная (не зависит от seed): фон одинаковый во всех забегах и у всех игроков «Гонки».
const ABYSS_ROCKS: Array = [
	# [id, x, y, z, масштаб, поворот по Y, наклон]. Камера видит полосу ~5 м слева от поля, ~10 м справа
	# (под панелью волны) и узкую полосу за дальним краем — туда и ставятся крупные массы.
	["env_abyss_rockface_01", -21.5, -3.0, -6.0, 7.5, 0.4, 0.1],
	["env_abyss_boulder_01", -21.0, -2.6, 5.0, 5.5, 2.2, -0.2],
	["env_abyss_boulder_01", -19.5, -1.8, 12.5, 3.0, 1.0, 0.3],
	["env_abyss_boulder_01", -9.0, -4.0, -17.5, 6.5, 1.9, 0.2],
	["env_abyss_rockface_01", 7.0, -4.5, -18.5, 8.0, 2.6, -0.1],
	["env_abyss_boulder_01", 20.5, -2.4, -9.0, 4.5, 0.9, 0.3],
	["env_abyss_rockface_01", 23.0, -3.5, 4.0, 7.0, 5.1, 0.15],
	["env_abyss_boulder_01", 20.0, -2.0, 12.0, 3.2, 4.0, -0.25],
	["env_abyss_boulder_01", -14.0, -1.6, -15.0, 2.0, 3.3, 0.4],
	["env_abyss_boulder_01", 16.5, -1.8, -14.5, 1.8, 0.2, -0.3],
	# Дальний план: видны в меню и при отдалении камеры, тонут в тумане.
	["env_abyss_rockface_01", -30.0, -9.0, -28.0, 14.0, 1.2, 0.1],
	["env_abyss_boulder_01", 30.0, -10.0, -26.0, 12.0, 2.9, -0.15],
]


func _build_environment() -> void:
	if _env_root != null:
		_env_root.queue_free()
	_env_root = Node3D.new()
	_env_root.name = "Environment"
	add_child(_env_root)
	for spec: Array in ABYSS_ROCKS:
		var rock: Dictionary = ArtKit.abyss_rock(String(spec[0]))
		if rock["mesh"] == null:
			continue
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = rock["mesh"]
		mi.material_override = rock["mat"]
		mi.position = Vector3(float(spec[1]), float(spec[2]), float(spec[3]))
		mi.scale = Vector3.ONE * float(spec[4])
		mi.rotation = Vector3(float(spec[6]), float(spec[5]), float(spec[6]) * 0.5)
		_env_root.add_child(mi)
	var motes: int = int(Graphics.preset()["ambient_motes"])
	if motes > 0:
		var dust: GPUParticles3D = ParticleKit.motes(Vector3(float(width) * 0.5 + 4.0, 2.5, float(height) * 0.5 + 4.0), motes)
		dust.position = Vector3(0, 2.5, 0)
		_env_root.add_child(dust)


## Пресет графики сменился: свет башен, преломление, частицы, окружение.
func apply_quality() -> void:
	_build_environment()
	_build_portal_fx()
	sync_from_sim()


## Точки маршрута: квадратная плита на всю зону, где строить нельзя ((2r+1)² клеток, r — no_build_radius карты),
## светящееся кольцо и номер чекпоинта.
func _build_route_markers() -> void:
	var pts: Array[Vector2i] = sim.grid.route_points
	var r: int = int(sim.data.map(sim.map_id).get("no_build_radius", 1))
	var zone: float = float(2 * r + 1)
	for i: int in pts.size():
		var c: Vector2i = pts[i]
		var is_entry: bool = i == 0
		var is_exit: bool = i == pts.size() - 1
		# Зона у края поля обрезана границей — плита тоже (по ширине и высоте отдельно).
		var lo: Vector2i = Vector2i(maxi(c.x - r, 0), maxi(c.y - r, 0))
		var hi: Vector2i = Vector2i(mini(c.x + r, width - 1), mini(c.y + r, height - 1))
		var rect: Vector2 = Vector2(hi - lo + Vector2i.ONE)
		var pad: MeshInstance3D = MeshInstance3D.new()
		pad.mesh = MeshFactory.square_pad_mesh(zone - 0.08)
		pad.material_override = ArtKit.rock_material(ArtKit.OBSIDIAN, ArtKit.ICE if not is_exit else Color("ff7ad9"), 0.6)
		pad.position = w((Vector2(lo) + Vector2(hi + Vector2i.ONE)) * 0.5, 0.0)
		pad.scale = Vector3((rect.x - 0.08) / (zone - 0.08), 1.0, (rect.y - 0.08) / (zone - 0.08))
		add_child(pad)
		var ring: MeshInstance3D = MeshInstance3D.new()
		var rp: PlaneMesh = PlaneMesh.new()
		rp.size = Vector2(2.4, 2.4)
		ring.mesh = rp
		var rm: ShaderMaterial = ShaderMaterial.new()
		rm.shader = RING_SHADER
		rm.set_shader_parameter("color", Color("7cc4ff") if not is_exit else Color("ff7ad9"))
		rm.set_shader_parameter("intensity", 1.4)
		rm.set_shader_parameter("thickness", 0.06)
		ring.material_override = rm
		ring.position = cell_world(c, 0.11)
		add_child(ring)
		pad_mats.append(rm)
		if not is_entry and not is_exit:
			var lbl: Label3D = Label3D.new()
			lbl.text = str(i)
			lbl.font = UiTokens.font("heading_bold")
			lbl.font_size = 96
			lbl.pixel_size = 0.009
			lbl.modulate = Color("ece7dc")
			lbl.outline_size = 18
			lbl.outline_modulate = Color(0.03, 0.03, 0.05, 0.85)
			lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			lbl.rotation_degrees = Vector3(-90, 0, 0)
			lbl.position = cell_world(c, 0.13)
			lbl.shaded = false
			add_child(lbl)
	_build_portal(pts[0])
	_build_citadel(pts[pts.size() - 1])


func _build_portal(c: Vector2i) -> void:
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.62
	torus.outer_radius = 0.78
	torus.rings = 24
	torus.ring_segments = 6
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = torus
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color("101626")
	m.emission_enabled = true
	m.emission = Color("7cc4ff")
	m.emission_energy_multiplier = 2.2
	mi.material_override = m
	mi.position = cell_world(c, 0.85)
	mi.rotation_degrees = Vector3(90, 0, 0)
	mi.name = "Portal"
	add_child(mi)
	var light: OmniLight3D = OmniLight3D.new()
	light.light_color = Color("7cc4ff")
	light.light_energy = 1.6
	light.omni_range = 4.0
	light.position = cell_world(c, 1.2)
	add_child(light)
	_portal_cell = c
	_build_portal_fx()


## Диск-спираль и вихрь частиц внутри портала (обращён к камере: камера смотрит на поле сверху-спереди).
func _build_portal_fx() -> void:
	if _portal_fx != null:
		_portal_fx.queue_free()
	_portal_fx = Node3D.new()
	_portal_fx.name = "PortalFx"
	_portal_fx.position = cell_world(_portal_cell, 0.85)
	add_child(_portal_fx)
	var disc: MeshInstance3D = MeshInstance3D.new()
	var dp: PlaneMesh = PlaneMesh.new()
	dp.size = Vector2(1.3, 1.3)
	disc.mesh = dp
	var dm: ShaderMaterial = ShaderMaterial.new()
	dm.shader = PORTAL_SHADER
	disc.material_override = dm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.rotation_degrees = Vector3(90, 0, 0)
	_portal_fx.add_child(disc)
	var swirl: GPUParticles3D = ParticleKit.portal_swirl(Color("7cc4ff"))
	_portal_fx.add_child(swirl)


func _build_citadel(c: Vector2i) -> void:
	var root: Node3D = Node3D.new()
	root.name = "Citadel"
	root.position = cell_world(c, 0.08)
	add_child(root)
	var spec: Array = [[Vector3(0, 0, 0), 1.7, 0.0], [Vector3(0.45, 0, 0.2), 1.1, 0.5], [Vector3(-0.42, 0, 0.25), 1.2, -0.4], [Vector3(0.2, 0, -0.42), 0.9, 0.3], [Vector3(-0.25, 0, -0.38), 0.8, -0.6]]
	for s: Array in spec:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = MeshFactory.gem_mesh("needle")
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = Graphics.gem_shader()
		m.set_shader_parameter("gem_color", Color("ff7ad9"))
		m.set_shader_parameter("glow", 1.4)
		m.set_shader_parameter("phase", float(s[2]) * 3.0)
		mi.material_override = m
		citadel_mats.append(m)
		mi.position = s[0]
		mi.scale = Vector3.ONE * float(s[1])
		mi.rotation = Vector3(float(s[2]) * 0.25, float(s[2]), float(s[2]) * 0.2)
		root.add_child(mi)
	var light: OmniLight3D = OmniLight3D.new()
	light.light_color = Color("ff7ad9")
	light.light_energy = 2.0
	light.omni_range = 5.0
	light.position = Vector3(0, 1.4, 0)
	light.name = "CitadelLight"
	root.add_child(light)


func _build_rocks() -> void:
	rock_mm = MultiMesh.new()
	rock_mm.transform_format = MultiMesh.TRANSFORM_3D
	rock_mm.mesh = ArtKit.wall_mesh()
	rock_mm.instance_count = MAX_ROCKS
	rock_mm.visible_instance_count = 0
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.multimesh = rock_mm
	wall_mat = ArtKit.wall_material()
	mmi.material_override = wall_mat
	add_child(mmi)


func _build_path_meshes() -> void:
	path_mesh = _path_instance(Color("1f5fd6"), 0.55, 0.2)
	preview_mesh = _path_instance(Color("15a34a"), 0.9, 0.24)
	preview_mesh.visible = false
	air_mesh = _path_instance(Color("c27c0e"), 0.45, 0.12)
	air_mesh.visible = false


func _path_instance(color: Color, intensity: float, width_m: float) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = PATH_SHADER
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("intensity", intensity)
	mi.material_override = m
	mi.set_meta("width", width_m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _build_ghost() -> void:
	ghost = MeshInstance3D.new()
	ghost.mesh = ArtKit.wall_mesh()
	ghost_mat = ShaderMaterial.new()
	ghost_mat.shader = GHOST_SHADER
	ghost_mat.set_shader_parameter("tint", Color("7cc4ff"))
	ghost_mat.set_shader_parameter("intensity", 0.35)
	ghost.material_override = ghost_mat
	ghost.visible = false
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ghost)
	range_ring = MeshInstance3D.new()
	var rp: PlaneMesh = PlaneMesh.new()
	rp.size = Vector2(2, 2)
	range_ring.mesh = rp
	range_mat = ShaderMaterial.new()
	range_mat.shader = RING_SHADER
	range_ring.material_override = range_mat
	range_ring.visible = false
	add_child(range_ring)


# --- Синхронизация -----------------------------------------------------------

func sync_from_sim() -> void:
	rock_cells = sim.rocks.duplicate()
	rock_spawn.clear()
	_update_rocks_mm()
	for k: Variant in gem_nodes.keys():
		(gem_nodes[k] as Node3D).queue_free()
	gem_nodes.clear()
	for t: TowerState in sim.towers:
		if t.is_special():
			_spawn_special(t.cell, t.special_id, t.level, false)
		else:
			_spawn_gem(t.cell, t.gem_id, t.quality, false, false)
		_refresh_tower_state(t)
	for cand: Dictionary in sim.candidates:
		_spawn_gem(cand["cell"], cand["gem"], int(cand["quality"]), true, false)
	for k2: Variant in slate_nodes.keys():
		(slate_nodes[k2] as Node3D).queue_free()
	slate_nodes.clear()
	for sl: TowerState in sim.slates:
		_spawn_slate(sl.cell, sl.slate_id, false)
	rebuild_path()
	_set_grid_visible(sim.phase != GameSim.Phase.COMBAT, true)


## Сетка клеток нужна только при строительстве; в бою поле читается по швам плит.
func _set_grid_visible(v: bool, instant: bool = false) -> void:
	var target: float = 1.0 if v else 0.0
	if instant:
		board_mat.set_shader_parameter("grid_visibility", target)
		return
	var from: float = float(board_mat.get_shader_parameter("grid_visibility"))
	create_tween().tween_method(func(x: float) -> void: board_mat.set_shader_parameter("grid_visibility", x), from, target, 0.6)


## Прожилки обсидиана вспыхивают, когда лабиринт меняет путь врагов.
func _pulse_veins() -> void:
	if wall_mat == null:
		return
	create_tween().tween_method(func(x: float) -> void: wall_mat.set_shader_parameter("vein_pulse", x), 1.0, 0.0, 1.2)


func rebuild_path() -> void:
	var pts: PackedVector3Array = PackedVector3Array()
	for p: Vector2 in sim.route.ground_points:
		pts.append(w(p, 0.03))
	path_mesh.mesh = MeshFactory.ribbon(pts, float(path_mesh.get_meta("width")))
	var air: PackedVector3Array = PackedVector3Array()
	for p: Vector2 in sim.route.air_points:
		air.append(w(p, 1.05))
	air_mesh.mesh = MeshFactory.ribbon(air, float(air_mesh.get_meta("width")))


func show_air_path(v: bool) -> void:
	air_mesh.visible = v


func set_preview(cell: Vector2i, preview: Dictionary) -> void:
	if cell.x < 0:
		board_mat.set_shader_parameter("hover_cell", Vector2(-100, -100))
		ghost.visible = false
		preview_mesh.visible = false
		return
	var ok: bool = bool(preview.get("ok", false))
	var col: Color = UiTokens.SUCCESS if ok else UiTokens.DANGER
	board_mat.set_shader_parameter("hover_cell", Vector2(cell))
	board_mat.set_shader_parameter("hover_color", col)
	ghost.visible = sim.grid.in_bounds(cell)
	ghost.position = cell_world(cell, 0.0)
	ghost_mat.set_shader_parameter("tint", col)
	var cells: Array = preview.get("cells", [])
	if ok and not cells.is_empty():
		var pts: PackedVector3Array = PackedVector3Array()
		for c: Vector2i in cells:
			pts.append(cell_world(c, 0.045))
		preview_mesh.mesh = MeshFactory.ribbon(pts, float(preview_mesh.get_meta("width")))
		var delta: float = float(preview.get("delta", 0.0))
		(preview_mesh.material_override as ShaderMaterial).set_shader_parameter("color", UiTokens.SUCCESS if delta > 0.01 else UiTokens.ACCENT)
		preview_mesh.visible = delta > 0.01
	else:
		preview_mesh.visible = false


func show_range(cell: Vector2i, radius: float, color: Color) -> void:
	if cell.x < 0 or radius <= 0.0:
		range_ring.visible = false
		return
	range_ring.visible = true
	range_ring.position = cell_world(cell, 0.06)
	range_ring.scale = Vector3(radius, 1.0, radius)
	range_mat.set_shader_parameter("color", color)
	range_mat.set_shader_parameter("thickness", 0.025 / maxf(radius * 0.25, 0.3))


func show_all_ranges(v: bool) -> void:
	for r: MeshInstance3D in aura_rings:
		r.queue_free()
	aura_rings.clear()
	if not v:
		return
	for t: TowerState in sim.towers:
		var mi: MeshInstance3D = MeshInstance3D.new()
		var rp: PlaneMesh = PlaneMesh.new()
		rp.size = Vector2(2, 2)
		mi.mesh = rp
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = RING_SHADER
		m.set_shader_parameter("color", tower_color(t))
		m.set_shader_parameter("intensity", 0.6)
		m.set_shader_parameter("thickness", 0.02)
		mi.material_override = m
		mi.position = cell_world(t.cell, 0.05)
		mi.scale = Vector3(t.attack_range, 1, t.attack_range)
		add_child(mi)
		aura_rings.append(mi)


## Цитадель тускнеет и покрывается трещинами по мере потери жизней.
func set_lives_ratio(r: float) -> void:
	var k: float = clampf(r, 0.0, 1.0)
	for m: ShaderMaterial in citadel_mats:
		m.set_shader_parameter("dim", lerpf(0.25, 1.0, k))
		m.set_shader_parameter("cracks", 1.0 - k)
	var light: OmniLight3D = get_node_or_null("Citadel/CitadelLight") as OmniLight3D
	if light != null:
		light.light_energy = lerpf(0.5, 2.0, k)


# --- События ---------------------------------------------------------------

func on_event(e: Dictionary) -> void:
	match String(e["type"]):
		"gem_revealed":
			_spawn_gem(e["cell"], e["gem"], int(e["quality"]), true, true)
			_refresh_slate_cover(e["cell"])
		"gem_kept":
			if bool(e.get("downgraded", false)):
				# Понижение: огранка и размер зависят от качества — кристалл пересоздаётся башней.
				_spawn_gem(e["cell"], String(e["gem"]), int(e["quality"]), false, true)
				return
			var n: Node3D = gem_nodes.get(e["cell"]) as Node3D
			if n != null:
				n.set_meta("candidate", false)
				n.set_meta("lift", n.get_meta("lift_kept", 0.2))
				var m: ShaderMaterial = n.get_meta("mat")
				m.set_shader_parameter("hologram", 0.0)
				var tw: Tween = create_tween()
				tw.tween_method(func(v: float) -> void: m.set_shader_parameter("pulse", v), 1.2, 0.0, 0.7)
				var ped: Node3D = n.get_node("Pedestal") as Node3D
				ped.visible = true
				ped.scale = Vector3(0.2, 0.2, 0.2)
				create_tween().tween_property(ped, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				_rise(n)
		"wall_formed":
			var c: Vector2i = e["cell"]
			var n2: Node3D = gem_nodes.get(c) as Node3D
			if n2 != null:
				gem_nodes.erase(c)
				_shrink_free(n2, 0.3)
			rock_cells.append(c)
			rock_spawn[c] = _time + 0.18
			_update_rocks_mm()
			_refresh_slate_cover(c)
		"path_changed":
			rebuild_path()
			_pulse_veins()
		"round_started":
			_set_grid_visible(true)
		"wave_started":
			_set_grid_visible(false)
		"gems_combined":
			var cc: Vector2i = e["cell"]
			for from: Vector2i in e["from"]:
				_fly_crystal(from, cc, String(e["gem"]), int(e["quality"]) - 1)
			_spawn_gem(cc, String(e["gem"]), int(e["quality"]), false, true)
		"special_forged":
			var fc: Vector2i = e["cell"]
			for part: Dictionary in e["parts"]:
				if part["cell"] != fc:
					_fly_crystal(part["cell"], fc, String(part["gem"]), int(part["quality"]))
			_spawn_special(fc, String(e["special"]), 1, true)
		"special_upgraded", "special_merged":
			_spawn_special(e["cell"], String(e["special"]), int(e["level"]), true)
			var t2: TowerState = sim.tower_by_cell.get(e["cell"]) as TowerState
			if t2 != null:
				_refresh_tower_state(t2)
		"slate_made":
			var sc: Vector2i = e["cell"]
			var gn: Node3D = gem_nodes.get(sc) as Node3D
			if gn != null:
				gem_nodes.erase(sc)
				_shrink_free(gn, 0.25)
			_spawn_slate(sc, String(e["slate"]), true)
		"slates_combined":
			_free_slate(e["from"])
			_spawn_slate(e["cell"], String(e["slate"]), true)
		"slate_moved":
			var mn: Node3D = slate_nodes.get(e["from"]) as Node3D
			if mn != null:
				slate_nodes.erase(e["from"])
				slate_nodes[e["to"]] = mn
				create_tween().tween_property(mn, "position", cell_world(e["to"], 0.0), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				_refresh_slate_cover(e["to"])
		"tower_moved":
			_on_tower_moved(e)
		"tower_polished":
			var tp: TowerState = sim.tower_by_cell.get(e["cell"]) as TowerState
			if tp != null:
				_refresh_tower_state(tp)
				var gn2: Node3D = gem_nodes.get(tp.cell) as Node3D
				if gn2 != null:
					gn2.set_meta("kick", _time)
		"slate_sold":
			_free_slate(e["cell"])
		"wall_broken":
			var wc: Vector2i = e["cell"]
			rock_cells.erase(wc)
			rock_spawn.erase(wc)
			_update_rocks_mm()
			_refresh_slate_cover(wc)
		"mvp_awarded", "tower_changed":
			var t3: TowerState = sim.tower_by_cell.get(e["cell"]) as TowerState
			if t3 != null:
				_refresh_tower_state(t3)


## Трейт «Обезоруживание»: башни тускнеют на время отключения.
func mark_disarmed(ids: Array, duration: float) -> void:
	for id: Variant in ids:
		var t: TowerState = sim.tower_by_id.get(int(id)) as TowerState
		if t == null or not gem_nodes.has(t.cell):
			continue
		var m: ShaderMaterial = (gem_nodes[t.cell] as Node3D).get_meta("mat")
		m.set_shader_parameter("dim", 0.3)
		var cell: Vector2i = t.cell
		get_tree().create_timer(duration).timeout.connect(func() -> void:
			var t2: TowerState = sim.tower_by_cell.get(cell) as TowerState
			if t2 != null:
				_refresh_tower_state(t2))


## Появление башни: кристалл поднимается из плиты со вспышкой.
func _rise(root: Node3D, delay: float = 0.0) -> void:
	var crystal: Node3D = root.get_node_or_null("Crystal") as Node3D
	if crystal == null or Settings.reduce_motion():
		return
	root.set_meta("rise_t", _time + delay)


## Выстрел: короткая отдача кристалла и вспышка свечения.
func tower_attack(tower_id: int) -> void:
	var t: TowerState = sim.tower_by_id.get(tower_id) as TowerState
	if t == null:
		return
	var n: Node3D = gem_nodes.get(t.cell) as Node3D
	if n != null:
		n.set_meta("kick", _time)


func tower_color(t: TowerState) -> Color:
	if t.is_special():
		return Color.html(String(sim.data.special(t.special_id)["color"]))
	return UiTokens.gem_color(t.gem_id)


## Звёзды MVP над башней, отметка слитой спец-башни и затемнение отключённой башни.
func _refresh_tower_state(t: TowerState) -> void:
	var n: Node3D = gem_nodes.get(t.cell) as Node3D
	if n == null:
		return
	var m: ShaderMaterial = n.get_meta("mat")
	m.set_shader_parameter("dim", 1.0 if t.enabled else 0.3)
	if t.is_merged() and n.get_node_or_null("Merged") == null:
		var ml: Label3D = Label3D.new()
		ml.name = "Merged"
		ml.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		ml.font = UiTokens.font("num")
		ml.font_size = 56
		ml.pixel_size = 0.004
		ml.outline_size = 10
		ml.modulate = tower_color(t).lightened(0.35)
		ml.position = Vector3(0, 1.95, 0)
		ml.no_depth_test = true
		ml.text = "+%s×L%d" % [String.num(t.merge_inherit), t.merge_level]
		n.add_child(ml)
	_refresh_polish_label(n, t)
	var lbl: Label3D = n.get_node_or_null("Mvp") as Label3D
	if t.mvp <= 0:
		if lbl != null:
			lbl.queue_free()
		return
	if lbl == null:
		lbl = Label3D.new()
		lbl.name = "Mvp"
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font = UiTokens.font("num")
		lbl.font_size = 64
		lbl.pixel_size = 0.004
		lbl.outline_size = 10
		lbl.modulate = UiTokens.GOLD
		lbl.position = Vector3(0, 1.65 if t.is_special() else 1.35, 0)
		lbl.no_depth_test = true
		n.add_child(lbl)
	lbl.text = "★%d" % t.mvp


## Огранка: «◆N» над башней (ниже звёзд MVP), цвет акцента.
func _refresh_polish_label(n: Node3D, t: TowerState) -> void:
	var pl: Label3D = n.get_node_or_null("Polish") as Label3D
	if t.polish <= 0:
		if pl != null:
			pl.queue_free()
		return
	if pl == null:
		pl = Label3D.new()
		pl.name = "Polish"
		pl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		pl.font = UiTokens.font("num")
		pl.font_size = 52
		pl.pixel_size = 0.004
		pl.outline_size = 10
		pl.modulate = UiTokens.ACCENT.lightened(0.2)
		pl.no_depth_test = true
		n.add_child(pl)
	pl.position = Vector3(0, (1.65 if t.is_special() else 1.35) + (0.28 if t.mvp > 0 else 0.0), 0)
	pl.text = "◆%d" % t.polish


## Перенос башни: кристалл перелетает в новую клетку; со стеной или башней они меняются местами.
func _on_tower_moved(e: Dictionary) -> void:
	var from: Vector2i = e["from"]
	var to: Vector2i = e["to"]
	var a: Node3D = gem_nodes.get(from) as Node3D
	var b: Node3D = gem_nodes.get(to) as Node3D
	gem_nodes.erase(from)
	gem_nodes.erase(to)
	if a != null:
		gem_nodes[to] = a
		_slide(a, to)
	match String(e["swap"]):
		"wall":
			rock_cells.erase(to)
			rock_spawn.erase(to)
			rock_cells.append(from)
			rock_spawn[from] = _time + 0.15
			_update_rocks_mm()
		"tower":
			if b != null:
				gem_nodes[from] = b
				_slide(b, from)
	_refresh_slate_cover(from)
	_refresh_slate_cover(to)
	for c: Vector2i in [from, to]:
		var t: TowerState = sim.tower_by_cell.get(c) as TowerState
		if t != null:
			_refresh_tower_state(t)


## Узел башни плавно перелетает в клетку (дугой над полем).
func _slide(n: Node3D, to: Vector2i) -> void:
	var start: Vector3 = n.position
	var end: Vector3 = cell_world(to, 0.0)
	var mid: Vector3 = (start + end) * 0.5 + Vector3(0, 1.2, 0)
	var tw: Tween = create_tween()
	tw.tween_method(func(k: float) -> void: n.position = start.lerp(mid, k).lerp(mid.lerp(end, k), k), 0.0, 1.0, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Кристалл, перелетающий из клетки в клетку (Combine / Forge).
func _fly_crystal(from: Vector2i, to: Vector2i, gem: String, quality: int) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var cut: Mesh = ArtKit.gem_cut(gem)
	mi.mesh = cut if cut != null else MeshFactory.gem_mesh(String(sim.data.gem(gem).get("silhouette", "octahedron")), maxi(quality, 1))
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = Graphics.gem_shader()
	m.set_shader_parameter("gem_color", UiTokens.gem_color(gem))
	m.set_shader_parameter("dispersion", UiTokens.gem_dispersion(gem))
	m.set_shader_parameter("glow", 2.5)
	m.set_shader_parameter("pulse", 0.6)
	mi.material_override = m
	var s: float = float(sim.data.quality(maxi(quality, 1))["scale"]) * GEM_SCALE * 0.8 * (ArtKit.CUT_SCALE if cut != null else 1.0)
	mi.scale = Vector3(s, s, s)
	mi.position = cell_world(from, 0.3)
	add_child(mi)
	var start: Vector3 = cell_world(from, 0.3)
	var end: Vector3 = cell_world(to, 0.6)
	var mid: Vector3 = (start + end) * 0.5 + Vector3(0, 1.6, 0)
	var fly: Callable = func(k: float) -> void:
		mi.position = start.lerp(mid, k).lerp(mid.lerp(end, k), k)
		mi.rotation.y = k * TAU
	var tw: Tween = create_tween()
	tw.tween_method(fly, 0.0, 1.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(mi.queue_free)


## Кольца у компонентов отслеживаемых рецептов: элемент — клетка (золотое кольцо) или {cell, color} —
## кольцо цвета спец-башни, когда рецептов несколько. Клетка из двух рецептов рисуется один раз.
func set_recipe_marks(marks: Array) -> void:
	for n: Node in get_children():
		if n.has_meta("recipe_mark"):
			n.queue_free()
	var seen: Dictionary = {}
	for mk: Variant in marks:
		var c: Vector2i = (mk as Dictionary)["cell"] if mk is Dictionary else mk as Vector2i
		if seen.has(c):
			continue
		seen[c] = true
		var mi: MeshInstance3D = MeshInstance3D.new()
		var rp: PlaneMesh = PlaneMesh.new()
		rp.size = Vector2(2, 2)
		mi.mesh = rp
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = RING_SHADER
		m.set_shader_parameter("color", (mk as Dictionary).get("color", UiTokens.GOLD) if mk is Dictionary else UiTokens.GOLD)
		m.set_shader_parameter("intensity", 1.2)
		m.set_shader_parameter("thickness", 0.12)
		mi.material_override = m
		mi.position = cell_world(c, 0.07)
		mi.scale = Vector3(0.62, 1, 0.62)
		mi.set_meta("recipe_mark", true)
		add_child(mi)


## Повторы среди кандидатов раунда (тот же гем и качество — их можно объединить): у каждого из группы
## кольцо цвета гема шире кольца рецепта и значок «×N» над кристаллом.
func set_duplicate_marks() -> void:
	for n: Node in get_children():
		if n.has_meta("dupe_mark"):
			n.queue_free()
	for k: Variant in gem_nodes.keys():
		var g: Node3D = gem_nodes[k]
		if g.has_meta("dupe"):
			g.remove_meta("dupe")
			(g.get_meta("mat") as ShaderMaterial).set_shader_parameter("pulse", 0.0)
	var groups: Dictionary = {}
	for cand: Dictionary in sim.candidates:
		var key: String = "%s:%d" % [String(cand["gem"]), int(cand["quality"])]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(cand["cell"])
	for key: String in groups.keys():
		var cells: Array = groups[key]
		if cells.size() < 2:
			continue
		var col: Color = UiTokens.gem_color(key.get_slice(":", 0))
		for c: Vector2i in cells:
			# Кристалл повтора мягко пульсирует (см. _process) — пару видно и без значка.
			var gn: Node3D = gem_nodes.get(c) as Node3D
			if gn != null:
				gn.set_meta("dupe", true)
			var mi: MeshInstance3D = MeshInstance3D.new()
			var rp: PlaneMesh = PlaneMesh.new()
			rp.size = Vector2(2, 2)
			mi.mesh = rp
			var m: ShaderMaterial = ShaderMaterial.new()
			m.shader = RING_SHADER
			m.set_shader_parameter("color", col)
			m.set_shader_parameter("intensity", 2.6)
			m.set_shader_parameter("thickness", 0.16)
			mi.material_override = m
			mi.position = cell_world(c, 0.08)
			mi.scale = Vector3(0.9, 1, 0.9)
			mi.set_meta("dupe_mark", true)
			add_child(mi)
			var lbl: Label3D = Label3D.new()
			lbl.text = "×%d" % cells.size()
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.font = UiTokens.font("heading_bold")
			lbl.font_size = 96
			lbl.pixel_size = 0.011
			lbl.outline_size = 26
			lbl.modulate = col.lightened(0.25)
			lbl.outline_modulate = Color(0.03, 0.03, 0.05, 0.92)
			lbl.no_depth_test = true
			lbl.shaded = false
			lbl.position = cell_world(c, 1.75)
			lbl.set_meta("dupe_mark", true)
			add_child(lbl)


func _spawn_special(c: Vector2i, special: String, level: int, animate: bool) -> void:
	if gem_nodes.has(c):
		(gem_nodes[c] as Node3D).queue_free()
	var sp: Dictionary = sim.data.special(special)
	var col: Color = Color.html(String(sp["color"]))
	var root: Node3D = Node3D.new()
	root.position = cell_world(c, 0.0)
	add_child(root)
	gem_nodes[c] = root
	var ped: MeshInstance3D = MeshInstance3D.new()
	ped.name = "Pedestal"
	var plinth: Mesh = ArtKit.pedestal_column()
	# Подъём кристалла, колец, орбит и света над старым цоколем (верх старого цоколя — 0.22).
	var lift: float = 0.0
	if plinth != null:
		ped.mesh = plinth
		ped.material_override = ArtKit.pedestal_material()
		ped.scale = ArtKit.PLINTH_SCALE
		lift = ArtKit.PLINTH_TOP - 0.22
	else:
		ped.mesh = MeshFactory.pedestal_mesh()
		ped.material_override = ArtKit.rock_material(ArtKit.OBSIDIAN, col, 0.6)
		ped.scale = Vector3(1.15, 1.4, 1.15)
	root.add_child(ped)
	var crystal: MeshInstance3D = MeshInstance3D.new()
	crystal.name = "Crystal"
	var silhouette: String = String(sp["silhouette"])
	crystal.mesh = MeshFactory.special_mesh(silhouette)
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = Graphics.gem_shader()
	m.set_shader_parameter("gem_color", col)
	m.set_shader_parameter("glow", 1.4 + 0.5 * float(level))
	m.set_shader_parameter("phase", float(c.x * 5 + c.y))
	crystal.material_override = m
	var s: float = (1.05 + 0.12 * float(level - 1)) * GEM_SCALE
	crystal.scale = Vector3(s, s, s)
	crystal.position.y = 0.22 + lift
	root.add_child(crystal)
	root.set_meta("base_scale", s)
	root.set_meta("lift", 0.2 + lift)
	root.set_meta("lift_kept", 0.2 + lift)
	var ring_count: int = 0
	if silhouette == "beacon" or silhouette == "spire":
		ring_count = 2
	elif level >= 3 or silhouette == "obelisk":
		ring_count = 1
	for i: int in ring_count:
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = 0.52 + 0.16 * float(i)
		torus.outer_radius = 0.58 + 0.16 * float(i)
		torus.rings = 24
		torus.ring_segments = 4
		var ring: MeshInstance3D = MeshInstance3D.new()
		ring.name = "Ring%d" % i if i > 0 else "Ring"
		ring.mesh = torus
		ring.material_override = m
		ring.position.y = 0.95 * s * 0.6 + 0.3 + lift
		ring.rotation_degrees = Vector3(65.0 * float(i + 1), 0, 20.0 * float(i))
		ring.scale = Vector3(s, s, s) * 0.75
		root.add_child(ring)
	# Орбиты: осколки у колодца и жеоды, монетный вихрь у идола.
	var orbit_count: int = {"well": 3, "geode": 5, "idol": 6}.get(silhouette, 0)
	for i: int in orbit_count:
		var shard: MeshInstance3D = MeshInstance3D.new()
		shard.name = "Orbit%d" % i
		shard.mesh = MeshFactory.coin_mesh() if silhouette == "idol" else MeshFactory.shard_mesh()
		shard.material_override = m
		shard.scale = Vector3.ONE * (0.22 if silhouette == "idol" else 0.28)
		shard.set_meta("orbit", float(i) * TAU / float(orbit_count))
		shard.set_meta("orbit_r", 0.75 if silhouette == "geode" else 0.6)
		shard.set_meta("orbit_y", 0.9 + lift)
		root.add_child(shard)
	root.set_meta("silhouette", silhouette)
	if bool(Graphics.preset()["tower_lights"]):
		var light: OmniLight3D = OmniLight3D.new()
		light.light_color = col
		light.light_energy = 0.9 + 0.35 * float(level)
		light.omni_range = 2.6 + 0.4 * float(level)
		light.position.y = 1.1 + lift
		root.add_child(light)
	var aura_fx: GPUParticles3D = ParticleKit.aura(col, String(SPECIAL_AURA.get(silhouette, "rise")))
	aura_fx.amount_ratio = clampf(0.5 + 0.25 * float(level), 0.0, 1.0)
	root.add_child(aura_fx)
	var aura_radius: float = 0.0
	match String(sp["attack"]):
		"aura_damage":
			aura_radius = float(sim.data.special_effect(special, "burn_radius", level, 0.0))
		"aura_slow":
			aura_radius = float(sim.data.special_effect(special, "slow_radius", level, 0.0))
		"none":
			aura_radius = float(sim.data.special_effect(special, "aura_radius", level, 0.0))
	if aura_radius > 0.0:
		var aura: MeshInstance3D = _ground_ring(col, aura_radius, 0.45, 0.04)
		aura.name = "Aura"
		root.add_child(aura)
	root.set_meta("mat", m)
	root.set_meta("candidate", false)
	root.set_meta("special", true)
	root.set_meta("phase", float(c.x * 1.7 + c.y * 0.3))
	if animate:
		root.scale = Vector3(0.05, 0.05, 0.05)
		var tw: Tween = create_tween()
		tw.tween_interval(0.35)
		tw.tween_property(root, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_method(func(v: float) -> void: m.set_shader_parameter("pulse", v), 2.2, 0.0, 1.2)
		_rise(root, 0.35)


func _spawn_gem(c: Vector2i, gem: String, quality: int, candidate: bool, animate: bool) -> void:
	if gem_nodes.has(c):
		(gem_nodes[c] as Node3D).queue_free()
	var root: Node3D = Node3D.new()
	root.position = cell_world(c, 0.0)
	add_child(root)
	gem_nodes[c] = root
	var ql: Dictionary = sim.data.quality(quality)
	var ped: MeshInstance3D = MeshInstance3D.new()
	ped.name = "Pedestal"
	# Готовая огранка и колонна-пьедестал, где они есть (ArtKit.GEM_CUTS), иначе — процедурные.
	var cut: Mesh = ArtKit.gem_cut(gem)
	var column: Mesh = ArtKit.pedestal_column() if cut != null else null
	if column != null:
		ped.mesh = column
		ped.material_override = ArtKit.pedestal_material()
	else:
		ped.mesh = MeshFactory.pedestal_mesh()
		ped.material_override = ArtKit.rock_material(ArtKit.OBSIDIAN, UiTokens.gem_color(gem), 0.6)
		ped.add_child(ArtKit.brass_band(0.47, 0.07))
	ped.visible = not candidate
	root.add_child(ped)
	var lift: float = ArtKit.PEDESTAL_TOP if column != null else 0.2
	var crystal: MeshInstance3D = MeshInstance3D.new()
	crystal.name = "Crystal"
	var silhouette: String = String(sim.data.gem(gem).get("silhouette", "octahedron"))
	crystal.mesh = cut if cut != null else MeshFactory.gem_mesh(silhouette, quality)
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = Graphics.gem_shader()
	m.set_shader_parameter("gem_color", UiTokens.gem_color(gem))
	m.set_shader_parameter("dispersion", UiTokens.gem_dispersion(gem))
	m.set_shader_parameter("glow", float(ql["glow"]))
	m.set_shader_parameter("phase", float(c.x * 7 + c.y * 3))
	m.set_shader_parameter("hologram", 1.0 if candidate else 0.0)
	m.set_shader_parameter("polish", ArtKit.gem_polish(quality) if cut != null else 1.0)
	crystal.material_override = m
	crystal.position.y = 0.2 if candidate else lift
	var s: float = float(ql["scale"]) * GEM_SCALE * (ArtKit.CUT_SCALE if cut != null else 1.0)
	crystal.scale = Vector3(s, s, s)
	if cut != null:
		crystal.rotation.x = ArtKit.CUT_TILT
	root.add_child(crystal)
	if silhouette == "coil" or silhouette == "halo":
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = 0.34
		torus.outer_radius = 0.4
		torus.rings = 20
		torus.ring_segments = 4
		var ring: MeshInstance3D = MeshInstance3D.new()
		ring.name = "Ring"
		ring.mesh = torus
		ring.material_override = m
		ring.position.y = 0.55 * s + 0.2
		ring.scale = Vector3(s, s, s)
		ring.rotation_degrees = Vector3(0 if silhouette == "halo" else 70, 0, 0)
		root.add_child(ring)
	if quality >= 5 and not candidate:
		var sp: GPUParticles3D = ParticleKit.sparkle(UiTokens.gem_color(gem), 0.55)
		sp.position.y = lift + 0.4
		root.add_child(sp)
	if quality >= 3 and bool(Graphics.preset()["tower_lights"]):
		var light: OmniLight3D = OmniLight3D.new()
		light.light_color = UiTokens.gem_color(gem)
		light.light_energy = 0.35 * float(quality - 2)
		light.omni_range = 1.6 + 0.4 * float(quality)
		light.position.y = lift + 0.6
		light.shadow_enabled = false
		root.add_child(light)
	root.set_meta("mat", m)
	root.set_meta("candidate", candidate)
	root.set_meta("phase", float(c.x * 1.3 + c.y * 0.7))
	# Высота кристалла: кандидат парит над плитой, башня сидит в чаше пьедестала.
	root.set_meta("lift_kept", lift)
	root.set_meta("lift", 0.2 if candidate else lift)
	root.set_meta("base_scale", s)
	if animate:
		root.scale = Vector3(0.05, 0.05, 0.05)
		var tw: Tween = create_tween()
		tw.tween_property(root, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_method(func(v: float) -> void: m.set_shader_parameter("pulse", v), 1.6, 0.0, 0.9)


func set_selected_candidate(c: Vector2i) -> void:
	for k: Variant in gem_nodes.keys():
		var n: Node3D = gem_nodes[k]
		if not bool(n.get_meta("candidate", false)):
			continue
		var m: ShaderMaterial = n.get_meta("mat")
		m.set_shader_parameter("hologram", 0.0 if k == c else 1.0)
		m.set_shader_parameter("dim", 1.25 if k == c else 0.75)


func gem_node(c: Vector2i) -> Node3D:
	return gem_nodes.get(c) as Node3D


func _update_rocks_mm() -> void:
	rock_mm.visible_instance_count = mini(rock_cells.size(), MAX_ROCKS)
	for i: int in rock_mm.visible_instance_count:
		rock_mm.set_instance_transform(i, _rock_xform(rock_cells[i]))


func _rock_xform(c: Vector2i) -> Transform3D:
	var k: float = 1.0
	if rock_spawn.has(c):
		k = clampf((_time - float(rock_spawn[c])) / 0.35, 0.0, 1.0)
		k = ease(k, 0.4)
	var h: float = 0.9 + 0.2 * fposmod(sin(float(c.x * 12 + c.y * 7)) * 43.0, 1.0)
	# Поворот на 0/90/180/270° — соседние блоки скана не выглядят одинаковыми.
	var turn: float = float(posmod(c.x * 7 + c.y * 13, 4)) * PI * 0.5
	var b: Basis = Basis(Vector3.UP, turn).scaled(Vector3(1.0, maxf(h * k, 0.02), 1.0))
	return Transform3D(b, cell_world(c, 0.0))


func _process(delta: float) -> void:
	_time += delta
	for k: Variant in gem_nodes.keys():
		var n: Node3D = gem_nodes[k]
		var crystal: Node3D = n.get_node_or_null("Crystal") as Node3D
		if crystal == null:
			continue
		var ph: float = float(n.get_meta("phase", 0.0))
		crystal.position.y = float(n.get_meta("lift", 0.2)) + sin(_time * 1.6 + ph) * 0.05
		var base_s: float = float(n.get_meta("base_scale", crystal.scale.x))
		var rise_k: float = 1.0
		if n.has_meta("rise_t"):
			rise_k = clampf((_time - float(n.get_meta("rise_t"))) / 0.5, 0.0, 1.0)
			crystal.position.y -= (1.0 - ease(rise_k, 0.3)) * 0.9
			if rise_k >= 1.0:
				n.remove_meta("rise_t")
		if n.has_meta("dupe"):
			(n.get_meta("mat") as ShaderMaterial).set_shader_parameter("pulse", 0.25 + 0.25 * sin(_time * 4.0))
		var kick: float = clampf(1.0 - (_time - float(n.get_meta("kick", -10.0))) / KICK_TIME, 0.0, 1.0)
		if kick > 0.0:
			crystal.position.y -= 0.07 * kick
			crystal.scale = Vector3.ONE * base_s * (1.0 + 0.1 * kick)
			(n.get_meta("mat") as ShaderMaterial).set_shader_parameter("pulse", 0.5 * kick)
		elif n.has_meta("kick"):
			crystal.scale = Vector3.ONE * base_s
			(n.get_meta("mat") as ShaderMaterial).set_shader_parameter("pulse", 0.0)
			n.remove_meta("kick")
		match String(n.get_meta("silhouette", "")):
			"prism":
				crystal.rotation.y += delta * 1.6
			"heart":
				var beat: float = 1.0 + maxf(0.0, sin(_time * 4.2 + ph)) * 0.07
				crystal.scale = Vector3.ONE * float(n.get_meta("base_scale", 1.0)) * beat
			"banner":
				crystal.rotation.y = sin(_time * 0.9 + ph) * 0.35
			"blade", "obelisk":
				crystal.rotation.y += delta * 0.15
			_:
				crystal.rotation.y += delta * 0.35
		for child: Node in n.get_children():
			var c3: Node3D = child as Node3D
			if c3 == null:
				continue
			if child.name.begins_with("Ring"):
				c3.rotate_object_local(Vector3.UP, -delta * 1.2)
			elif child.has_meta("orbit"):
				var a: float = float(child.get_meta("orbit")) + _time * 1.4
				var r: float = float(child.get_meta("orbit_r", 0.6))
				c3.position = Vector3(cos(a) * r, float(child.get_meta("orbit_y", 0.9)) + sin(_time * 2.0 + a) * 0.1, sin(a) * r)
				c3.rotation.y = -a
	if not rock_spawn.is_empty():
		var done: Array = []
		for i: int in rock_cells.size():
			var c: Vector2i = rock_cells[i]
			if rock_spawn.has(c):
				rock_mm.set_instance_transform(i, _rock_xform(c))
				if float(rock_spawn[c]) + 0.36 < _time:
					done.append(c)
		for c: Variant in done:
			rock_spawn.erase(c)
	var portal: Node3D = get_node_or_null("Portal") as Node3D
	if portal != null:
		portal.rotate_object_local(Vector3.UP, delta * 0.6)


## Плита слейта: обсидиан с прожилкой цвета слейта, светящаяся руна (у составного — с рамкой) и
## кольцо радиуса действия на земле. Клетка проходима: плита низкая, враги идут прямо по ней.
func _spawn_slate(c: Vector2i, slate: String, animate: bool) -> void:
	_free_slate(c)
	var sl: Dictionary = sim.data.slate(slate)
	var col: Color = Color.html(String(sl["color"]))
	var root: Node3D = Node3D.new()
	root.position = cell_world(c, 0.0)
	add_child(root)
	slate_nodes[c] = root
	var slab: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.86, 0.07, 0.86)
	slab.mesh = box
	slab.material_override = ArtKit.rock_material(ArtKit.OBSIDIAN, col, 0.9)
	slab.position.y = 0.035
	root.add_child(slab)
	var rune_mat: StandardMaterial3D = StandardMaterial3D.new()
	rune_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rune_mat.albedo_color = col
	rune_mat.emission_enabled = true
	rune_mat.emission = col
	rune_mat.emission_energy_multiplier = 2.0
	var rune: MeshInstance3D = MeshInstance3D.new()
	var rb: BoxMesh = BoxMesh.new()
	rb.size = Vector3(0.3, 0.02, 0.3)
	rune.mesh = rb
	rune.material_override = rune_mat
	rune.position.y = 0.08
	rune.rotation_degrees.y = 45.0
	root.add_child(rune)
	# Значок над стеной или башней, если они стоят на слейте: сам слейт под ними не виден.
	var badge: MeshInstance3D = MeshInstance3D.new()
	badge.name = "Badge"
	var bb: BoxMesh = BoxMesh.new()
	bb.size = Vector3(0.22, 0.04, 0.22)
	badge.mesh = bb
	badge.material_override = rune_mat
	badge.position = Vector3(0.3, 1.25, 0.3)
	badge.rotation_degrees = Vector3(0.0, 45.0, 0.0)
	badge.visible = false
	root.add_child(badge)
	if String(sl["kind"]) == "combo":
		var frame: MeshInstance3D = MeshInstance3D.new()
		var tm: TorusMesh = TorusMesh.new()
		tm.inner_radius = 0.3
		tm.outer_radius = 0.34
		tm.rings = 4
		tm.ring_segments = 4
		frame.mesh = tm
		frame.material_override = rune_mat
		frame.position.y = 0.08
		frame.scale = Vector3(1.0, 0.25, 1.0)
		root.add_child(frame)
	root.add_child(_ground_ring(col, float(sl["radius"]), 0.3, 0.03))
	_refresh_slate_cover(c)
	if animate:
		root.scale = Vector3(0.2, 0.2, 0.2)
		create_tween().tween_property(root, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Слейт под камнем, стеной или башней: над ними светится значок слейта.
func _refresh_slate_cover(c: Vector2i) -> void:
	var n: Node3D = slate_nodes.get(c) as Node3D
	if n == null:
		return
	var badge: Node3D = n.get_node_or_null("Badge") as Node3D
	if badge != null:
		badge.visible = sim.grid.get_cell(c) != BoardGrid.Cell.EMPTY


func _free_slate(c: Vector2i) -> void:
	var n: Node3D = slate_nodes.get(c) as Node3D
	if n == null:
		return
	slate_nodes.erase(c)
	_shrink_free(n, 0.25)


## Кольцо радиуса на земле (аура спец-башни, радиус слейта).
func _ground_ring(col: Color, radius: float, intensity: float, y: float) -> MeshInstance3D:
	var ring: MeshInstance3D = MeshInstance3D.new()
	var ap: PlaneMesh = PlaneMesh.new()
	ap.size = Vector2(2, 2)
	ring.mesh = ap
	var am: ShaderMaterial = ShaderMaterial.new()
	am.shader = RING_SHADER
	am.set_shader_parameter("color", col)
	am.set_shader_parameter("intensity", intensity)
	am.set_shader_parameter("thickness", 0.02)
	ring.material_override = am
	ring.position.y = y
	ring.scale = Vector3(radius, 1, radius)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ring


## Узел сжимается в точку и удаляется (стена из башни, кандидат под слейтом, проданный слейт).
func _shrink_free(n: Node3D, time: float) -> void:
	var tw: Tween = create_tween()
	tw.tween_property(n, "scale", Vector3(0.05, 0.05, 0.05), time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(n.queue_free)
