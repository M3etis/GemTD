extends Node
## Превью hero-ассетов для согласования арт-дирекшна: рубин I–V на колоннах-пьедесталах крупным планом,
## на полу арены, со светом и окружением игры. Сохраняет PNG в docs/art/after/.
## Запуск (нужно окно): godot --path . res://tools/art_preview.tscn
## Враги с VAT (ряд рядовых, ряд боссов, кадры цикла и смерти): godot --path . res://tools/art_preview.tscn -- --enemies
## Эффекты (спрайты Kenney, флипбуки Unity Labs) в ряд: godot --path . res://tools/art_preview.tscn -- --vfx
## Портреты врагов для Кодекса (assets/ui/portraits, прозрачный фон): godot --path . res://tools/art_preview.tscn -- --portraits

const OUT: String = "res://docs/art/after/hero_ruby_q1_q5.png"
const OUT_TOP: String = "res://docs/art/after/hero_ruby_game_camera.png"
const OUT_CLOSE: String = "res://docs/art/after/hero_ruby_closeup.png"
const OUT_ALL: String = "res://docs/art/after/gems_all_q4.png"
const OUT_ENEMIES: String = "res://docs/art/after/enemies_%s.png"

var _gems: Array[Node] = []


## Гем на колонне-пьедестале (как в BoardView._spawn_gem) с подсветкой с качества III.
func _spawn(world: Node3D, data: GameData, gem_id: String, q: int, at: Vector3) -> void:
	var ped: MeshInstance3D = MeshInstance3D.new()
	ped.mesh = ArtKit.pedestal_column()
	ped.material_override = ArtKit.pedestal_material()
	ped.position = at
	world.add_child(ped)
	_gems.append(ped)
	var gem: MeshInstance3D = MeshInstance3D.new()
	gem.mesh = ArtKit.gem_cut(gem_id)
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = Graphics.gem_shader()
	m.set_shader_parameter("gem_color", UiTokens.gem_color(gem_id))
	m.set_shader_parameter("dispersion", UiTokens.gem_dispersion(gem_id))
	m.set_shader_parameter("glow", float(data.quality(q)["glow"]))
	m.set_shader_parameter("polish", ArtKit.gem_polish(q))
	m.set_shader_parameter("phase", at.x * 1.7)
	gem.material_override = m
	gem.scale = Vector3.ONE * float(data.quality(q)["scale"]) * BoardView.GEM_SCALE * ArtKit.CUT_SCALE
	gem.position = at + Vector3(0, ArtKit.PEDESTAL_TOP + 0.02, 0)
	gem.rotation = Vector3(ArtKit.CUT_TILT, 0.4 * float(q) + at.x * 0.3, 0.0)
	world.add_child(gem)
	_gems.append(gem)
	if q >= 3:
		var light: OmniLight3D = OmniLight3D.new()
		light.light_color = UiTokens.gem_color(gem_id)
		light.light_energy = 0.35 * float(q - 2)
		light.omni_range = 1.6 + 0.4 * float(q)
		light.position = at + Vector3(0, ArtKit.PEDESTAL_TOP + 0.6, 0)
		world.add_child(light)
		_gems.append(light)


func _ready() -> void:
	var root: Window = get_tree().root
	var world: Node3D = Node3D.new()
	add_child(world)
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Graphics.make_environment("arena")
	world.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_color = ArtKit.KEY_LIGHT
	sun.light_energy = 1.15
	sun.rotation_degrees = Vector3(-55, -35, 0)
	Graphics.apply_sun(sun)
	world.add_child(sun)
	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.light_color = ArtKit.RIM_LIGHT
	rim.light_energy = 0.35
	rim.rotation_degrees = Vector3(-25, 150, 0)
	world.add_child(rim)
	# Пол 12×6 клеток и ряд стен позади.
	var floor_mi: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(12, 6)
	floor_mi.mesh = plane
	var bm: ShaderMaterial = ArtKit.board_material(Vector2(12, 6))
	bm.set_shader_parameter("zone_tex", ImageTexture.create_from_image(Image.create(12, 6, false, Image.FORMAT_R8)))
	bm.set_shader_parameter("grid_visibility", 0.0)
	floor_mi.material_override = bm
	world.add_child(floor_mi)
	var wall: MultiMesh = MultiMesh.new()
	wall.transform_format = MultiMesh.TRANSFORM_3D
	wall.mesh = ArtKit.wall_mesh()
	wall.instance_count = 9
	for i: int in 9:
		var turn: float = float(i % 4) * PI * 0.5
		wall.set_instance_transform(i, Transform3D(Basis(Vector3.UP, turn), Vector3(float(i) - 4.0, 0.0, -1.5)))
	var wmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	wmi.multimesh = wall
	wmi.material_override = ArtKit.wall_material()
	world.add_child(wmi)
	var data: GameData = GameData.load_default()
	if OS.get_cmdline_user_args().has("--enemies"):
		await _enemies(world, data, root)
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--portraits"):
		await _portraits(data)
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--vfx"):
		await _vfx(world, root)
		get_tree().quit()
		return
	for q: int in range(1, 6):
		_spawn(world, data, "ruby", q, Vector3(float(q - 3) * 1.6, 0.0, 0.5))
	var cam: Camera3D = Camera3D.new()
	cam.fov = 34.0
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 4.2, 8.2), Vector3(0.0, 0.7, 0.3))
	cam.current = true
	Graphics.apply_viewport(root)
	for i: int in 45:
		await get_tree().process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT))
	print("preview: " + OUT)
	# Крупный план IV–V (меню, Forge-зум).
	cam.look_at_from_position(Vector3(2.4, 2.0, 3.6), Vector3(2.4, 0.75, 0.5))
	for i: int in 20:
		await get_tree().process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_CLOSE))
	print("preview: " + OUT_CLOSE)
	# Все восемь гемов (качество IV) — проверка силуэтов и цветов рядом друг с другом.
	for g: Node in _gems:
		g.queue_free()
	_gems.clear()
	var ids: PackedStringArray = data.gem_ids
	for i: int in ids.size():
		_spawn(world, data, String(ids[i]), 4, Vector3(float(i) - 3.5, 0.0, 0.5) * Vector3(1.25, 1, 1))
	cam.look_at_from_position(Vector3(0.0, 4.4, 10.6), Vector3(0.0, 0.6, 0.3))
	for i: int in 20:
		await get_tree().process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_ALL))
	print("preview: " + OUT_ALL)
	# Тот же ряд под игровой камерой (57°, ~45 м) — как рубины видны в бою.
	cam.look_at_from_position(Vector3(0.0, 37.4, 24.3), Vector3(0.0, 0.0, 0.0))
	cam.fov = 34.0
	for i: int in 20:
		await get_tree().process_frame
	var full: Image = root.get_texture().get_image()
	var w: int = full.get_width()
	var h: int = full.get_height()
	full.get_region(Rect2i(w / 2 - w / 6, h / 2 - h / 8, w / 3, h / 4)).save_png(ProjectSettings.globalize_path(OUT_TOP))
	print("preview: " + OUT_TOP)
	get_tree().quit()


## Модель врага одним экземпляром MultiMesh — как в EnemyRenderer (цвет архетипа, фаза клипа в custom.w).
func _enemy(world: Node3D, data: GameData, arch: String, at: Vector3, yaw: float, phase: float) -> MultiMesh:
	var mesh: ArrayMesh = ArtKit.enemy_vat(arch)
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	# Как в EnemyRenderer: размер архетипа × подстройка scale модели.
	var sz: float = float(data.archetypes[arch]["size"]) * 2.0 * float(ArtKit.enemy_look(mesh.resource_name)["scale"])
	var y: float = EnemyRenderer.FLY_HEIGHT if bool(data.archetypes[arch]["flying"]) else 0.0
	mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sz), at + Vector3(0, y, 0)))
	mm.set_instance_color(0, Color.html(String(data.archetypes[arch]["color"])))
	mm.set_instance_custom_data(0, Color(0, 0, 0, phase))
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = ArtKit.enemy_vat_material(mesh)
	world.add_child(mmi)
	_gems.append(mmi)
	return mm


func _shot(root: Window, cam: Camera3D, from: Vector3, to: Vector3, name: String) -> void:
	cam.look_at_from_position(from, to)
	for i: int in 12:
		await get_tree().process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_ENEMIES % name))
	print("preview: " + OUT_ENEMIES % name)


func _enemies(world: Node3D, data: GameData, root: Window) -> void:
	var cam: Camera3D = Camera3D.new()
	cam.fov = 34.0
	world.add_child(cam)
	cam.current = true
	Graphics.apply_viewport(root)
	var regular: Array[String] = []
	var bosses: Array[String] = []
	for arch: String in ArtKit.ENEMY_MODELS:
		if ArtKit.enemy_vat(arch) == null:
			continue
		(bosses if bool(data.archetypes[arch]["boss"]) else regular).append(arch)
	# Рядовые в профиль (смотрят по +X), фаза четверть цикла.
	for i: int in regular.size():
		_enemy(world, data, regular[i], Vector3((float(i) - float(regular.size() - 1) * 0.5) * 1.35, 0.0, 0.6), 0.0, 0.25)
	for i: int in 30:
		await get_tree().process_frame
	await _shot(root, cam, Vector3(0.0, 2.2, 8.6), Vector3(0.0, 0.45, 0.4), "regular_side")
	# Те же — три четверти спереди.
	for mmi: Node in _gems:
		var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
		var xf: Transform3D = mm.get_instance_transform(0)
		mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, -PI * 0.25).scaled(xf.basis.get_scale()), xf.origin))
	await _shot(root, cam, Vector3(0.0, 2.2, 8.6), Vector3(0.0, 0.45, 0.4), "regular_front")
	# Под игровой камерой (57°, ~45 м) — так враги видны в бою.
	await _shot(root, cam, Vector3(0.0, 37.4, 24.3), Vector3(0.0, 0.0, 0.0), "regular_game")
	for g: Node in _gems:
		g.queue_free()
	_gems.clear()
	for i: int in bosses.size():
		_enemy(world, data, bosses[i], Vector3((float(i) - float(bosses.size() - 1) * 0.5) * 2.3, 0.0, 0.4), -PI * 0.25, 0.25)
	await _shot(root, cam, Vector3(0.0, 3.4, 11.5), Vector3(0.0, 0.9, 0.3), "bosses")
	# Кадры цикла и смерти одной модели: --enemy=<архетип>.
	var one: String = "normal"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--enemy="):
			one = a.substr(8)
	for g2: Node in _gems:
		g2.queue_free()
	_gems.clear()
	var phases: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0]
	var k: float = maxf(float(data.archetypes[one]["size"]) / 0.32, 1.0)
	for i: int in phases.size():
		_enemy(world, data, one, Vector3((float(i) - 3.0) * 1.4 * k, 0.0, 0.5), 0.0, phases[i])
	await _shot(root, cam, Vector3(0.0, 2.0 * k, 8.0 * k), Vector3(0.0, 0.4 * k, 0.4), "frames_" + one)
	# Крупный план первого кадра три четверти спереди.
	var mm1: MultiMesh = _enemy(world, data, one, Vector3(0.0, 0.0, 3.0 * k), -PI * 0.3, 0.1)
	await _shot(root, cam, Vector3(0.0, 1.2 * k, 6.2 * k), Vector3(0.0, 0.5 * k, 3.0 * k), "close_" + one)
	mm1.instance_count = 0


## Эффекты боя в ряд, как их зовёт GamePresenter: искры попаданий, искры раскрытия, дым смерти,
## взрыв босса, пыль Сердца Землетрясения, пламя Венца Пепла, огненный шар. Два снимка: 0.3 с и 0.9 с.
func _vfx(world: Node3D, root: Window) -> void:
	var fx: FxLayer = FxLayer.new()
	world.add_child(fx)
	fx.setup(null)
	var cam: Camera3D = Camera3D.new()
	cam.fov = 34.0
	world.add_child(cam)
	cam.current = true
	Graphics.apply_viewport(root)
	for i: int in 20:
		await get_tree().process_frame
	var x0: float = -3.9
	var dx: float = 1.3
	fx.burst(Vector3(x0, 0.6, 0.5), UiTokens.GOLD, 16, 2.5, 0.12, 0.8, 4.0, 1.0, "flare")
	fx.burst(Vector3(x0 + dx, 0.6, 0.5), UiTokens.gem_color("ruby"), 40, 3.0, 0.16, 0.9, 3.0, 1.0, "star")
	fx.flipbook(Vector3(x0 + dx * 2.0, 0.4, 0.5), "smoke", 1.4, 0.9, Color(0.6, 0.56, 0.55, 0.7))
	fx.flipbook(Vector3(x0 + dx * 3.0, 0.9, 0.5), "explosion", 2.4, 1.6, Color.WHITE, 1.3)
	fx.flipbook(Vector3(x0 + dx * 4.0, 0.0, 0.5), "dust", 1.6, 1.3, Color(0.72, 0.66, 0.58, 0.75))
	fx.flipbook(Vector3(x0 + dx * 5.0, 0.0, 0.5), "flame", 1.4, 0.9, Color("ff7a3d"), 1.2)
	fx.flipbook(Vector3(x0 + dx * 6.0, 0.6, 0.5), "fireball", 1.2, 1.0, Color.WHITE, 1.2)
	cam.look_at_from_position(Vector3(0.0, 5.0, 9.0), Vector3(0.0, 0.5, 0.4))
	await get_tree().create_timer(0.3).timeout
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://docs/art/after/vfx_lineup_a.png"))
	await get_tree().create_timer(0.6).timeout
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://docs/art/after/vfx_lineup_b.png"))
	print("preview: docs/art/after/vfx_lineup_{a,b}.png")


## Портрет каждого архетипа: модель в позе шага три четверти спереди, свет арены, прозрачный фон, 192 px.
func _portraits(data: GameData) -> void:
	var dir: String = "res://assets/ui/portraits"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(384, 384)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Graphics.make_environment("arena").duplicate() as Environment
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.glow_enabled = false
	env.environment.fog_enabled = false
	vp.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_color = ArtKit.KEY_LIGHT
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-40, -20, 0)
	vp.add_child(sun)
	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.light_color = ArtKit.RIM_LIGHT
	rim.light_energy = 0.6
	rim.rotation_degrees = Vector3(-20, 160, 0)
	vp.add_child(rim)
	var cam: Camera3D = Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	cam.current = true
	for arch: String in ArtKit.ENEMY_MODELS:
		var mesh: ArrayMesh = ArtKit.enemy_vat(arch)
		if mesh == null:
			continue
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D.IDENTITY)
		mm.set_instance_color(0, Color.html(String(data.archetypes[arch]["color"])))
		mm.set_instance_custom_data(0, Color(0, 0, 0, 0.15))
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = ArtKit.enemy_vat_material(mesh)
		vp.add_child(mmi)
		var box: AABB = mesh.get_aabb()
		var c: Vector3 = box.get_center()
		var r: float = box.size.length() * 0.5
		var dist: float = r / tan(deg_to_rad(cam.fov * 0.5)) * 1.05
		cam.look_at_from_position(c + Vector3(0.75, 0.45, 0.85).normalized() * dist, c)
		for i: int in 8:
			await get_tree().process_frame
		var img: Image = vp.get_texture().get_image()
		img.resize(192, 192, Image.INTERPOLATE_LANCZOS)
		img.save_png(ProjectSettings.globalize_path(dir.path_join("ui_portrait_%s.png" % arch)))
		print("portrait: " + arch)
		mmi.queue_free()
