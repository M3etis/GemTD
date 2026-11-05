extends Node
## Главное меню: живой 3D-фон с кристаллами, заголовок с бликом, пункты меню, лучший результат.

const T := preload("res://ui/theme/ui_tokens.gd")
const SHIMMER: Shader = preload("res://fx/shaders/title_shimmer.gdshader")

var _pivot: Node3D
var _gems: Array[Node3D] = []
var _time: float = 0.0
var _ui: Control
var _layer: CanvasLayer


func _ready() -> void:
	_build_backdrop()
	_build_ui()
	Audio.play_loop("ambience/arena")
	Audio.music("menu")
	var shot: String = String(Game.cli.get("screenshot", ""))
	if shot in ["menu", "leaderboard", "settings", "settingsvideo", "settingsaccess", "settingscontrols", "soundbrowser", "newgame", "codexmenu", "lbdetail", "credits", "licenses", "raceout"]:
		_screenshot(shot)


func _build_backdrop() -> void:
	var world: Node3D = Node3D.new()
	add_child(world)
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Graphics.make_environment("menu")
	world.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_color = Color("aab8ff")
	sun.light_energy = 0.6
	sun.rotation_degrees = Vector3(-50, -30, 0)
	Graphics.apply_sun(sun)
	world.add_child(sun)
	Events.settings_changed.connect(func(section: String) -> void:
		if section == "video":
			Graphics.apply_environment(env.environment, "menu")
			Graphics.apply_sun(sun))
	var disc: MeshInstance3D = MeshInstance3D.new()
	disc.mesh = MeshFactory.lathe([Vector2(0.0, 0.0), Vector2(9.0, 0.0), Vector2(9.0, 0.3), Vector2(8.4, 0.45), Vector2(0.0, 0.45)], 12, 0.0)
	disc.material_override = ArtKit.rock_material(ArtKit.OBSIDIAN, ArtKit.VEIN, 0.4)
	disc.position.y = -0.45
	world.add_child(disc)
	_pivot = Node3D.new()
	world.add_child(_pivot)
	var data: GameData = GameData.load_default()
	var ids: PackedStringArray = data.gem_ids
	for i: int in ids.size():
		var a: float = TAU * float(i) / float(ids.size())
		var root: Node3D = Node3D.new()
		var r: float = 4.6
		root.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
		var mi: MeshInstance3D = MeshInstance3D.new()
		var cut: Mesh = ArtKit.gem_cut(ids[i])
		mi.mesh = cut if cut != null else MeshFactory.gem_mesh(String(data.gem(ids[i])["silhouette"]), 5)
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = Graphics.gem_shader()
		m.set_shader_parameter("gem_color", T.gem_color(ids[i]))
		m.set_shader_parameter("dispersion", T.gem_dispersion(ids[i]))
		m.set_shader_parameter("glow", 1.6)
		m.set_shader_parameter("polish", 1.0)
		m.set_shader_parameter("phase", float(i) * 1.3)
		mi.material_override = m
		# Огранка нормирована к ширине 1: в меню крупнее, чтобы не теряться среди процедурных кристаллов.
		mi.scale = Vector3.ONE * (1.4 if cut != null else 1.5)
		if cut != null:
			mi.rotation.x = ArtKit.CUT_TILT
		root.add_child(mi)
		# Колонна-пьедестал, как у гемов на арене (нет файла — прежний процедурный цоколь).
		var ped: MeshInstance3D = MeshInstance3D.new()
		var column: Mesh = ArtKit.pedestal_column()
		ped.mesh = column if column != null else MeshFactory.pedestal_mesh()
		ped.material_override = ArtKit.pedestal_material() if column != null else ArtKit.rock_material(ArtKit.OBSIDIAN, T.gem_color(ids[i]), 0.8)
		ped.scale = Vector3(1.6, 0.8, 1.6) if column != null else Vector3(1.6, 1.0, 1.6)
		ped.position.y = -0.05
		root.add_child(ped)
		var light: OmniLight3D = OmniLight3D.new()
		light.light_color = T.gem_color(ids[i])
		light.light_energy = 0.8
		light.omni_range = 3.0
		light.position.y = 1.0
		root.add_child(light)
		_pivot.add_child(root)
		_gems.append(mi)
	# Сердце цитадели в центре стола — крупный бриллиант (огранка G1), а не процедурный октаэдр.
	var center: MeshInstance3D = MeshInstance3D.new()
	var heart: Mesh = ArtKit.gem_cut("diamond")
	center.mesh = heart if heart != null else MeshFactory.gem_mesh("octahedron")
	var cm: ShaderMaterial = ShaderMaterial.new()
	cm.shader = Graphics.gem_shader()
	cm.set_shader_parameter("gem_color", Color("ff7ad9"))
	cm.set_shader_parameter("glow", 2.2)
	cm.set_shader_parameter("polish", 1.0)
	cm.set_shader_parameter("dispersion", 0.6)
	center.material_override = cm
	center.scale = Vector3.ONE * (2.6 if heart != null else 3.2)
	if heart != null:
		center.rotation.x = ArtKit.CUT_TILT
	_pivot.add_child(center)
	_gems.append(center)
	var cam: Camera3D = Camera3D.new()
	cam.fov = 40.0
	cam.position = Vector3(6.5, 5.2, 11.5)
	world.add_child(cam)
	cam.look_at(Vector3(-4.2, 0.6, 0.0), Vector3.UP)
	cam.current = true


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = ThemeBuilder.get_theme()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_ui)
	var grad: GradientTexture2D = GradientTexture2D.new()
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(0.02, 0.025, 0.04, 0.96))
	g.add_point(0.45, Color(0.02, 0.025, 0.04, 0.8))
	g.set_color(g.get_point_count() - 1, Color(0.02, 0.025, 0.04, 0.0))
	grad.gradient = g
	grad.fill_from = Vector2(0, 0.5)
	grad.fill_to = Vector2(0.72, 0.5)
	var tr_shade: TextureRect = TextureRect.new()
	tr_shade.texture = grad
	tr_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr_shade.stretch_mode = TextureRect.STRETCH_SCALE
	tr_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(tr_shade)

	var col: VBoxContainer = Ui.vbox(T.SP_3)
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 120
	col.offset_right = 760
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_ui.add_child(col)
	var kicker: Label = Ui.label(tr("MENU_KICKER"), "CapsLabel")
	kicker.add_theme_color_override("font_color", T.ACCENT)
	kicker.add_theme_font_size_override("font_size", 14)
	col.add_child(kicker)
	var title: Label = Ui.label(tr("APP_TITLE"), "TitleLabel")
	title.add_theme_font_size_override("font_size", 96)
	var sm: ShaderMaterial = ShaderMaterial.new()
	sm.shader = SHIMMER
	title.material = sm
	col.add_child(title)
	var tagline: Label = Ui.label(tr("MENU_TAGLINE"), "DimLabel", true)
	tagline.add_theme_font_size_override("font_size", 18)
	tagline.custom_minimum_size = Vector2(560, 0)
	col.add_child(tagline)
	col.add_child(Ui.spacer(false, false))
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	col.add_child(gap)
	# Пункты меню без подсказок клавиш: Enter/Space по-прежнему открывают первый пункт, но чипы не нужны.
	var buttons: VBoxContainer = Ui.vbox(T.SP_2)
	buttons.custom_minimum_size = Vector2(340, 0)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var auto: Dictionary = Save.read(Save.AUTOSAVE)
	var play: Button
	if Save.compatible(auto):
		var m: Dictionary = auto.get("meta", {})
		play = Ui.button(tr("MENU_CONTINUE"), "PrimaryButton", "", "play")
		play.tooltip_text = tr("MENU_CONTINUE_TIP") % [int(m.get("round", 1)), int(m.get("wave_total", 0)), int(m.get("lives", 0))]
		play.pressed.connect(func() -> void: Game.new_run({"load_slot": Save.AUTOSAVE}))
		buttons.add_child(play)
		var ng: Button = Ui.button(tr("MENU_NEW_GAME"), "Button", "", "gem")
		ng.pressed.connect(_open_new_game)
		buttons.add_child(ng)
	else:
		play = Ui.button(tr("MENU_NEW_GAME"), "PrimaryButton", "", "play")
		play.pressed.connect(_open_new_game)
		buttons.add_child(play)
	var any_slot: bool = false
	for slot: String in Save.SLOTS:
		any_slot = any_slot or Save.exists(slot)
	if any_slot:
		var load: Button = Ui.button(tr("MENU_LOAD"), "Button", "", "copy")
		load.pressed.connect(func() -> void:
			var p: SaveSlotsPanel = SaveSlotsPanel.new().setup("load")
			p.load_requested.connect(func(slot: String) -> void: Game.new_run({"load_slot": slot}))
			_ui.add_child(p))
		buttons.add_child(load)
	var mp: Button = Ui.button(tr("MENU_MULTIPLAYER"), "Button", "", "swords")
	mp.pressed.connect(func() -> void:
		Audio.stop_loop("ambience/arena")
		Game.goto_scene("lobby"))
	buttons.add_child(mp)
	var codex: Button = Ui.button(tr("MENU_CODEX"), "Button", "", "info")
	codex.pressed.connect(func() -> void: _ui.add_child(CodexPanel.new().setup(null)))
	buttons.add_child(codex)
	var lb: Button = Ui.button(tr("MENU_LEADERBOARD"), "Button", "", "trophy")
	lb.pressed.connect(func() -> void: _ui.add_child(LeaderboardPanel.new()))
	buttons.add_child(lb)
	var st: Button = Ui.button(tr("MENU_SETTINGS"), "Button", "", "gear")
	st.pressed.connect(func() -> void: _ui.add_child(SettingsPanel.new()))
	buttons.add_child(st)
	var cr: Button = Ui.button(tr("MENU_CREDITS"), "GhostButton", "", "info")
	cr.pressed.connect(func() -> void: _ui.add_child(CreditsPanel.new()))
	buttons.add_child(cr)
	var q: Button = Ui.button(tr("MENU_QUIT"), "GhostButton", "", "close")
	q.pressed.connect(Game.quit_game)
	buttons.add_child(q)
	for b: Node in buttons.get_children():
		(b as Control).size_flags_horizontal = Control.SIZE_FILL
	col.add_child(buttons)
	Ui.stagger(buttons.get_children(), 0.05, 0.2)
	play.grab_focus.call_deferred()

	var best: Dictionary = Leaderboard.personal_best("classic", "")
	if not best.is_empty():
		var card: PanelContainer = Ui.panel("GlassPanel")
		card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		card.grow_vertical = Control.GROW_DIRECTION_BEGIN
		card.offset_right = -48
		card.offset_bottom = -48
		var v: VBoxContainer = Ui.vbox(2)
		v.add_child(Ui.label(tr("MENU_BEST"), "CapsLabel"))
		var sc: Label = Ui.label(T.format_number(float(best["score"])), "BigNumberLabel")
		sc.add_theme_color_override("font_color", T.ACCENT)
		v.add_child(sc)
		var dd: Dictionary = GameData.load_default().difficulty(String(best["difficulty"]))
		v.add_child(Ui.label(tr("MENU_BEST_SUB") % [T.wave_fraction(int(best["waves_cleared"]), int(best["total_waves"])), tr(String(dd.get("name_key", "")))], "DimLabel"))
		card.add_child(v)
		_ui.add_child(card)
		Ui.pop_in(card, 0.5, Vector2.ZERO)
	var toasts: ToastLayer = ToastLayer.new()
	_ui.add_child(toasts)
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toasts.offset_top = 32
	var ver: Label = Ui.label("v%s · Godot %s" % [Game.version(), Engine.get_version_info()["string"]], "FaintLabel")
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.offset_left = 24
	ver.offset_bottom = -16
	_ui.add_child(ver)


func _open_new_game() -> void:
	_ui.add_child(NewGamePanel.new())


func _process(delta: float) -> void:
	_time += delta
	_pivot.rotation.y += delta * 0.12
	for i: int in _gems.size():
		var g: Node3D = _gems[i]
		g.position.y = 0.6 + sin(_time * 1.3 + float(i)) * 0.15
		g.rotation.y += delta * 0.4


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("confirm") and _ui.get_child_count() > 0 and not (_ui.get_child(_ui.get_child_count() - 1) is Modal):
		get_viewport().set_input_as_handled()
		if Save.compatible(Save.read(Save.AUTOSAVE)):
			Game.new_run({"load_slot": Save.AUTOSAVE})
		else:
			_open_new_game()


func _screenshot(kind: String) -> void:
	match kind:
		"leaderboard":
			_ui.add_child(LeaderboardPanel.new())
		"settings":
			_ui.add_child(SettingsPanel.new())
		"settingsvideo", "settingsaccess", "settingscontrols":
			var sp: SettingsPanel = SettingsPanel.new()
			_ui.add_child(sp)
			var tabs: TabContainer = sp.find_children("*", "TabContainer", true, false)[0] as TabContainer
			tabs.current_tab = {"settingsvideo": 1, "settingsaccess": 3, "settingscontrols": 4}[kind]
		"soundbrowser":
			_ui.add_child(SoundBrowser.new())
		"newgame":
			_ui.add_child(NewGamePanel.new())
		"raceout":
			# Экран продолжения «Гонки» после выбывания — с примером таблицы (сам матч для снимка не нужен).
			var rp: RaceOutPanel = RaceOutPanel.new().setup(false, 37, true, false)
			rp.update_rows([
				{"id": 1, "name": Settings.player_name(), "color": "#7cc4ff", "lives": 0, "wave": 38, "status": "out", "me": true, "over": true},
				{"id": 2, "name": "Аня", "color": "#ff7ad9", "lives": 14, "wave": 41, "status": "combat", "me": false, "over": false},
				{"id": 3, "name": "Борис", "color": "#4ade80", "lives": 3, "wave": 41, "status": "combat", "me": false, "over": false},
			] as Array[Dictionary])
			_ui.add_child(rp)
		"codexmenu":
			_ui.add_child(CodexPanel.new().setup(null))
		"credits", "licenses":
			var cp: CreditsPanel = CreditsPanel.new()
			_ui.add_child(cp)
			if kind == "licenses":
				cp.add_child(cp._licenses_modal())
		"lbdetail":
			var lb: LeaderboardPanel = LeaderboardPanel.new()
			_ui.add_child(lb)
			var rows: Array[Dictionary] = Leaderboard.ranking("classic")
			if not rows.is_empty():
				lb._open_id = String(rows[0]["id"])
				lb._refresh()
	await get_tree().create_timer(1.6).timeout
	await Game.save_screenshot(kind)
	get_tree().quit()
