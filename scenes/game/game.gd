extends Node
## Игровой экран: шаг симуляции с фиксированным тиком, ввод игрока → команды,
## события симуляции → визуал (BoardView/рендереры), подача (GamePresenter) и HUD.

const T := preload("res://ui/theme/ui_tokens.gd")
const VIGNETTE_SHADER: Shader = preload("res://fx/shaders/vignette.gdshader")
const SPEEDS: Array[int] = [1, 2, 4]

var data: GameData
var sim: GameSim
var bot: BotPlayer
var world: Node3D
var board: BoardView
var enemies: EnemyRenderer
var projectiles: ProjectileRenderer
var fx: FxLayer
var cam: CameraRig
var hud: Hud
var presenter: GamePresenter
var ui_layer: CanvasLayer
var vignette_mat: ShaderMaterial

var speed: int = 1
var paused: bool = false
var menu_open: bool = false
var acc: float = 0.0
var real_time: float = 0.0
var hover_cell: Vector2i = Vector2i(-1, -1)
var _preview_cache: Dictionary = {}
var _preview_version: int = -1
var selected_slot: int = -1
var selected_tower: Vector2i = Vector2i(-1, -1)
var selected_wall: Vector2i = Vector2i(-1, -1)
## Выбранный слейт и режим переноса (следующий клик по клетке перекладывает его).
var selected_slate: Vector2i = Vector2i(-1, -1)
var _moving_slate: bool = false
## Режим переноса выбранной башни: следующий клик по стене, башне или пустой клетке переносит её.
var _moving_tower: bool = false
## Подсветка цели переноса пересчитывается, только когда меняется клетка под курсором или состояние поля
## (любая успешная команда): проверка переноса башни на пустую клетку — это поиск пути.
var _move_hover_key: String = ""
var countdown: float = -1.0
var _last_count_tick: int = -1
var finished: bool = false
## Запись забега в лидерборде (для обновления после Испытания урона).
var _record_id: String = ""
var _test_bar: DamageTestBar
var _env: Environment
var _sun: DirectionalLight3D
var show_ranges: bool = false
var autoplay: bool = false
var _bot_timer: float = 0.0
var _hud_refresh: float = 0.0
var _screenshot: String = ""
var _board_forges: Array[Dictionary] = []
## «Гонка»: сессия матча и поле, которое сейчас показывается (своё или соперника).
var race: RaceSession = null
var view_sim: GameSim
var _race_refresh: float = 0.0
var race_ctl: RaceController = null
var replay_ctl: ReplayController = null
## Стресс-тест производительности (tests/perf/stress.tscn). Скрипт грузится по пути, а не по class_name:
## tests/ не входит в экспорт, и статическая ссылка сломала бы загрузку сцены в собранной игре.
const STRESS_SCRIPT: String = "res://tests/perf/perf_stress.gd"
var stress: RefCounted = null
## Обучение (три интерактивных раунда) и контекстные подсказки при первых событиях.
var tutorial: Tutorial = null
var hints: HintsController = null


func _ready() -> void:
	data = GameData.load_default()
	_screenshot = String(Game.cli.get("screenshot", ""))
	autoplay = Game.cli.has("autoplay") or Game.cli.has("bot")
	if Game.cli.has("load-stall"):
		# Автотест сети: долгая загрузка сцены (первая компиляция шейдеров) — главный поток стоит, ENet не опрашивается.
		OS.delay_msec(int(float(String(Game.cli["load-stall"])) * 1000.0))
	if not _create_sim():
		return
	view_sim = sim
	if autoplay or not _screenshot.is_empty():
		bot = BotPlayer.new(sim, String(Game.cli.get("strategy", "maze")), sim.seed_value)
		bot.auto_start_wave = race == null
	_prepare_screenshot_state()
	_build_world()
	_build_ui()
	presenter = GamePresenter.new(data, sim, board, fx, cam, hud)
	if race != null:
		_setup_race_ui()
		presenter.allow_slowmo = false
	if replay_ctl != null:
		replay_ctl.build_ui(hud)
		hud.tower_panel.read_only = true
	hud.top.set_autostart_visible(race == null and replay_ctl == null)
	_after_state_change()
	_sync_hud(false)
	sim.drain_events()
	Audio.play_loop("ambience/arena")
	Audio.music("combat" if sim.phase == GameSim.Phase.COMBAT else ("victory" if sim.phase == GameSim.Phase.VICTORY else "build"))
	if Game.cli.has("speed"):
		_set_speed(clampi(int(String(Game.cli["speed"])), 1, 4))
	if stress != null:
		_set_speed(4)
	hud.banner.show_banner(tr("BANNER_ROUND") % sim.round_index, tr("BANNER_ROUND_SUB"), T.ACCENT, 1.0)
	if bool(Game.run_config.get("tutorial", false)):
		tutorial = Tutorial.new(self)
	elif race == null and replay_ctl == null and stress == null and not autoplay and _screenshot.is_empty():
		hints = HintsController.new(self)
	if sim.phase == GameSim.Phase.CHOOSING:
		_select_slot(_best_default_slot())
	if not _screenshot.is_empty() and not _screenshot.begins_with("race"):
		_run_screenshot.call_deferred()


## Новый забег или загрузка сохранения. false — загрузка не удалась (уходим в меню).
func _create_sim() -> bool:
	var cfg: Dictionary = Game.run_config.duplicate()
	if String(cfg.get("mode", "")) == "replay":
		var rep: Dictionary = cfg["replay"]
		if int(rep.get("data_hash", -1)) != data.data_hash:
			Events.toast_requested.emit(tr("ERR_REPLAY_DATA_MISMATCH"), "error")
			Game.goto_scene.call_deferred("menu")
			return false
		sim = ReplayController.make_sim(data, rep)
		replay_ctl = ReplayController.new(self, rep, cfg.get("record", {}))
		return true
	if String(cfg.get("mode", "")) == "stress":
		var ps: GDScript = load(STRESS_SCRIPT)
		sim = ps.call("make_sim", data)
		stress = ps.new(self)
		return true
	if String(cfg.get("mode", "")) == "race":
		var race_cfg: Dictionary = cfg["race"]
		sim = GameSim.new(data, RaceSession.local_config(race_cfg))
		sim.start()
		race = RaceSession.new()
		race.name = "RaceSession"
		add_child(race)
		race.setup(data, race_cfg, sim)
		sim.command_listener = race.on_local_command
		return true
	if cfg.has("load_slot"):
		var save: Dictionary = Save.read(String(cfg["load_slot"]))
		var res: Dictionary = Save.restore(save)
		if not res["ok"]:
			Events.toast_requested.emit(tr(String(res["reason"])), "error")
			Game.goto_scene.call_deferred("menu")
			return false
		sim = res["sim"]
		var meta: Dictionary = save.get("meta", {})
		real_time = float(meta.get("real_seconds", 0.0))
		if cfg.has("verify_checksum"):
			print("saveload: checksum после загрузки %d, ожидался %d — %s" % [sim.checksum(), int(cfg["verify_checksum"]), "OK" if sim.checksum() == int(cfg["verify_checksum"]) else "MISMATCH"])
			_screenshot = "loaded"
		Game.run_config = {"seed": sim.seed_value, "difficulty": sim.difficulty_id, "daily": String(meta.get("daily", "")), "max_waves": sim.total_waves}
		Events.toast_requested.emit.call_deferred(tr("TOAST_LOADED"), "success")
		return true
	if bool(cfg.get("tutorial", false)):
		cfg.merge(Tutorial.config(), true)
	if Game.cli.has("seed") and not cfg.has("seed"):
		cfg["seed"] = RunRng.seed_from_text(String(Game.cli["seed"]))
	if not cfg.has("seed"):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.randomize()
		cfg["seed"] = rng.randi()
	if Game.cli.has("difficulty"):
		cfg["difficulty"] = String(Game.cli["difficulty"])
	if Game.cli.has("waves"):
		cfg["max_waves"] = int(String(Game.cli["waves"]))
	Game.run_config = cfg
	sim = GameSim.new(data, cfg)
	sim.start()
	return true


# --- Построение сцены --------------------------------------------------------

func _build_world() -> void:
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Graphics.make_environment("arena")
	world.add_child(env)
	_env = env.environment
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	# Тёплый ключ 4200 K сверху-слева и холодный контровой 9000 K (ART_DIRECTION.md §5).
	sun.light_color = ArtKit.KEY_LIGHT
	sun.light_energy = 1.15
	sun.rotation_degrees = Vector3(-55, -35, 0)
	Graphics.apply_sun(sun)
	world.add_child(sun)
	_sun = sun
	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.light_color = ArtKit.RIM_LIGHT
	rim.light_energy = 0.35
	rim.rotation_degrees = Vector3(-25, 150, 0)
	world.add_child(rim)
	_create_views(sim)
	cam = CameraRig.new()
	world.add_child(cam)
	cam.setup(sim.grid.width, sim.grid.height)
	cam.cam.current = true


## Визуал поля привязан к одной симуляции; при наблюдении за соперником пересоздаётся.
func _create_views(target: GameSim) -> void:
	board = BoardView.new()
	world.add_child(board)
	board.setup(target)
	enemies = EnemyRenderer.new()
	world.add_child(enemies)
	enemies.setup(board, target)
	projectiles = ProjectileRenderer.new()
	world.add_child(projectiles)
	projectiles.setup(board, target)
	fx = FxLayer.new()
	world.add_child(fx)
	fx.setup(board)
	fx.show_numbers = bool(Settings.get_value("gameplay", "damage_numbers"))
	fx.prewarm(board.cell_world(target.grid.route_points[0], 0.1))


func _bind_view(target: GameSim) -> void:
	if target == view_sim:
		return
	if view_sim != sim:
		view_sim.record_events = false
	view_sim.drain_events()
	for n: Node3D in [board, enemies, projectiles, fx]:
		n.queue_free()
	view_sim = target
	if view_sim != sim:
		view_sim.record_events = true
		view_sim.drain_events()
	_create_views(view_sim)
	board.set_lives_ratio(float(view_sim.lives) / float(maxi(view_sim.max_lives, 1)))
	presenter.sim = view_sim
	presenter.board = board
	presenter.fx = fx
	presenter.quiet_ui = view_sim != sim
	_deselect()
	board.set_preview(Vector2i(-1, -1), {})
	if view_sim == sim:
		_after_state_change()


## Замена симуляции целиком (перемотка реплея): визуал и HUD пересобираются.
func replace_sim(new_sim: GameSim) -> void:
	for n: Node3D in [board, enemies, projectiles, fx]:
		n.queue_free()
	sim = new_sim
	view_sim = new_sim
	_create_views(sim)
	board.set_lives_ratio(float(sim.lives) / float(maxi(sim.max_lives, 1)))
	presenter.sim = sim
	presenter.board = board
	presenter.fx = fx
	_deselect()
	_after_state_change()
	_sync_hud(false)


func _build_ui() -> void:
	var post: CanvasLayer = CanvasLayer.new()
	post.layer = 0
	add_child(post)
	var vig: ColorRect = ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_mat = ShaderMaterial.new()
	vignette_mat.shader = VIGNETTE_SHADER
	vig.material = vignette_mat
	post.add_child(vig)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	hud = Hud.new()
	ui_layer.add_child(hud)
	hud.top.set_seed(RunRng.seed_to_text(sim.seed_value))
	hud.top.set_difficulty(sim.diff)
	hud.top.speed_selected.connect(_set_speed)
	hud.top.autostart_toggled.connect(func(on: bool) -> void: Settings.set_value("gameplay", "autostart_wave", on))
	hud.top.pause_pressed.connect(_toggle_pause)
	hud.top.luck_pressed.connect(func() -> void: _command({"type": "upgrade_luck"}))
	hud.top.buy_life_pressed.connect(func() -> void: _command({"type": "buy_life"}))
	hud.top.menu_pressed.connect(_open_pause_menu)
	hud.top.codex_pressed.connect(_open_codex)
	hud.phase.card_selected.connect(_select_slot)
	hud.phase.card_hovered.connect(_on_card_hovered)
	hud.phase.action_pressed.connect(_on_action)
	hud.tower_panel.closed.connect(_deselect)
	hud.wave_panel.entry_clicked.connect(func(at: Vector3) -> void: cam.focus_on(at, cam.distance))
	hud.tower_panel.action_pressed.connect(_on_panel_action)
	Events.settings_changed.connect(func(section: String) -> void:
		if section == "gameplay":
			fx.show_numbers = bool(Settings.get_value("gameplay", "damage_numbers"))
			_apply_autostart()
		elif section == "video":
			Graphics.apply_environment(_env, "arena")
			Graphics.apply_sun(_sun)
			board.apply_quality()
			fx.apply_quality()
			enemies.apply_quality()
		elif section == "general":
			_refresh_tracker())


# --- Главный цикл --------------------------------------------------------------

func _process(delta: float) -> void:
	if not finished:
		real_time += delta
	if stress != null:
		stress.call("frame", delta)
	_run_bot(delta)
	_run_countdown(delta)
	var alpha: float = 1.0
	if replay_ctl != null:
		alpha = replay_ctl.update(delta) if not menu_open else 1.0
	elif sim.phase == GameSim.Phase.COMBAT and not paused and (not menu_open or race != null):
		acc += delta * float(speed)
		var steps: int = 0
		var max_steps: int = int(data.economy["sim"]["max_ticks_per_frame"])
		var t0: int = Time.get_ticks_usec()
		while acc >= sim.dt and steps < max_steps and sim.phase == GameSim.Phase.COMBAT:
			sim.step()
			acc -= sim.dt
			steps += 1
		if stress != null:
			stress.call("add_ticks", Time.get_ticks_usec() - t0, steps)
		if sim.damage_test and _test_bar != null:
			_test_bar.update_from(sim)
		if steps >= max_steps:
			acc = 0.0
		alpha = clampf(acc / sim.dt, 0.0, 1.0)
	else:
		acc = 0.0
	for e: Dictionary in sim.drain_events():
		_dispatch(e)
	if view_sim != sim:
		for e2: Dictionary in view_sim.drain_events():
			_dispatch_visual(e2)
		alpha = 1.0
	if race != null:
		_race_refresh -= delta
		if _race_refresh <= 0.0:
			_race_refresh = 0.25
			_refresh_race_hud()
	enemies.render(alpha, delta)
	hud.boss_bar.update_from(view_sim)
	projectiles.render(alpha, delta)
	enemies.show_all_hp = Input.is_action_pressed("show_hp")
	_update_hover()
	presenter.decay(delta)
	vignette_mat.set_shader_parameter("flash", presenter.flash if Settings.flashes() else 0.0)
	vignette_mat.set_shader_parameter("strength", 0.55 + 0.35 * presenter.darken)
	vignette_mat.set_shader_parameter("aberration", presenter.aberration if Settings.flashes() else 0.0)
	_hud_refresh -= delta
	if _hud_refresh <= 0.0:
		_hud_refresh = 0.1
		if sim.phase == GameSim.Phase.COMBAT and not sim.damage_test and replay_ctl == null:
			hud.phase.show_combat(sim.wave_number, sim.enemies.size(), sim.combat.schedule_index, sim.combat.schedule.size())
		_refresh_tower_stats()


func _run_bot(delta: float) -> void:
	if bot == null or not autoplay or finished or menu_open:
		return
	if sim.phase == GameSim.Phase.COMBAT or sim.is_over():
		return
	_bot_timer -= delta
	if _bot_timer > 0.0:
		return
	_bot_timer = 0.12 if sim.phase == GameSim.Phase.PLACING else 0.5
	countdown = -1.0
	bot.act()


## Отсчёт до волны идёт, только если стоит галочка автостарта (по умолчанию её нет — волну запускает
## игрок) и на поле нет готового сплава.
func _can_autostart() -> bool:
	return bool(Settings.get_value("gameplay", "autostart_wave")) and not autoplay and _board_forges.is_empty() and race == null and replay_ctl == null


## Галочка автостарта изменилась (верхняя панель или настройки): запустить или отменить отсчёт.
func _apply_autostart() -> void:
	hud.top.set_autostart(bool(Settings.get_value("gameplay", "autostart_wave")))
	if sim.phase != GameSim.Phase.READY or race != null or replay_ctl != null:
		return
	if not _can_autostart():
		countdown = -1.0
	elif countdown < 0.0:
		countdown = float(data.economy["countdown_seconds"])
		_last_count_tick = -1
	hud.phase.show_ready(sim.round_index, countdown, countdown >= 0.0)


func _run_countdown(delta: float) -> void:
	if countdown < 0.0 or sim.phase != GameSim.Phase.READY or menu_open or paused:
		return
	countdown -= delta
	var whole: int = ceili(countdown)
	if whole != _last_count_tick and whole > 0:
		_last_count_tick = whole
		Audio.play("sfx/waves/countdown")
	hud.phase.show_ready(sim.round_index, countdown, true)
	if countdown <= 0.0:
		countdown = -1.0
		_start_wave()


# --- Ввод ----------------------------------------------------------------------

## Tab: прогноз волн (одиночная игра) или переключение наблюдения за соперниками («Гонка»).
## Enter в «Гонке» — открыть чат (пока он открыт, Enter достаётся полю ввода).
## Обрабатывается в _input: иначе Tab забирает навигация фокуса интерфейса, а Enter — кнопка в фокусе.
func _input(event: InputEvent) -> void:
	var chat: ChatPanel = race_ctl.chat if race_ctl != null else null
	if chat != null and chat.is_open():
		return
	if chat != null and event.is_action_pressed("chat") and _chat_allowed():
		get_viewport().set_input_as_handled()
		chat.open()
		return
	if not event.is_action_pressed("forecast") or menu_open or _modal_count() > 0:
		return
	get_viewport().set_input_as_handled()
	if race_ctl != null:
		race_ctl.watch_next()
	else:
		hud.forecast.toggle(data, sim.next_wave_number(), sim.wave_limit(), sim.diff, sim.finale_for(sim.total_waves))


func _unhandled_input(event: InputEvent) -> void:
	if finished or menu_open:
		return
	if replay_ctl != null:
		if event.is_action_pressed("confirm") or event.is_action_pressed("pause"):
			replay_ctl.toggle_pause()
		elif event.is_action_pressed("speed_up"):
			replay_ctl.set_speed_index(1)
		elif event.is_action_pressed("speed_down"):
			replay_ctl.set_speed_index(-1)
		elif event.is_action_pressed("menu"):
			replay_ctl._exit()
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var cell: Vector2i = _cell_under_mouse((event as InputEventMouseButton).position)
			if sim.tower_by_cell.has(cell):
				_select_tower(cell)
			elif sim.slate_by_cell.has(cell):
				_select_slate(cell)
			else:
				_deselect()
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_click(_cell_under_mouse(mb.position))
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_deselect()
	elif event.is_action_pressed("confirm") and sim.phase == GameSim.Phase.READY:
		# Оставить гем можно только кнопкой «Оставить»: Space и повторный клик раньше оставляли не тот гем.
		get_viewport().set_input_as_handled()
		_start_wave()
	elif event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		if _moving_slate:
			_cancel_slate_move()
		elif _moving_tower:
			_cancel_tower_move()
		elif view_sim != sim and race_ctl != null and not race_ctl._finished_local:
			race_ctl.watch(race.local_id)
		elif selected_tower.x >= 0 or selected_wall.x >= 0 or selected_slate.x >= 0:
			_deselect()
		elif race_ctl != null and race_ctl.can_open_out_panel():
			# Выбыл, матч идёт: Esc — экран продолжения (наблюдать, остаться, выйти); меню паузы — его кнопкой.
			race_ctl.open_out_panel()
		else:
			_open_pause_menu()
	elif event.is_action_pressed("pause"):
		_toggle_pause()
	elif event.is_action_pressed("upgrade_luck"):
		_command({"type": "upgrade_luck"})
	elif event.is_action_pressed("speed_up"):
		_set_speed(SPEEDS[mini(SPEEDS.find(speed) + 1, SPEEDS.size() - 1)])
	elif event.is_action_pressed("speed_down"):
		_set_speed(SPEEDS[maxi(SPEEDS.find(speed) - 1, 0)])
	elif event.is_action_pressed("restart"):
		Modal.confirm(ui_layer, tr("CONFIRM_RESTART_TITLE"), tr("CONFIRM_RESTART_TEXT"), tr("ACT_RESTART"), _restart_same_seed)
	elif event.is_action_pressed("show_ranges"):
		show_ranges = not show_ranges
		board.show_all_ranges(show_ranges)
	elif event.is_action_pressed("codex"):
		_open_codex()
	elif event.is_action_pressed("combine"):
		_hotkey_action("combine")
	elif event.is_action_pressed("forge"):
		_hotkey_action("forge")
	elif event.is_action_pressed("break_wall") and selected_wall.x >= 0:
		_on_panel_action("break")
	else:
		for i: int in 5:
			if event.is_action_pressed("select_%d" % (i + 1)) and sim.phase == GameSim.Phase.CHOOSING:
				_select_slot(i)


## C / F: первое подходящее действие (Combine ×4 → ×2; Forge для выбранного гема или на поле).
func _hotkey_action(kind: String) -> void:
	if sim.phase == GameSim.Phase.CHOOSING:
		for a: Dictionary in ChoiceLogic.actions_for(sim, selected_slot):
			if String(a["id"]).begins_with(kind) and not bool(a.get("disabled", false)):
				_on_action(String(a["id"]))
				return
	if kind == "forge" and not _board_forges.is_empty():
		var o: Dictionary = _board_forges[0]
		var cell: Vector2i = o["cell"]
		_on_action("board_forge:%d:%d:%s" % [cell.x, cell.y, String(o["special"])])
		return
	Events.toast_requested.emit(tr("ERR_NO_" + kind.to_upper()), "error")


func _cell_under_mouse(screen: Vector2) -> Vector2i:
	var p: Variant = cam.ground_point(screen)
	if p == null:
		return Vector2i(-1, -1)
	return board.world_to_cell(p)


func _update_hover() -> void:
	var over_ui: bool = get_viewport().gui_get_hovered_control() != null
	var cell: Vector2i = Vector2i(-1, -1)
	if not over_ui and not menu_open and not finished:
		cell = _cell_under_mouse(get_viewport().get_mouse_position())
		if not sim.grid.in_bounds(cell):
			cell = Vector2i(-1, -1)
	if _moving_slate and not (sim.is_build_phase() and selected_slate.x >= 0 and sim.slate_by_cell.has(selected_slate)):
		_cancel_slate_move()
	if _moving_tower and not (sim.is_build_phase() and selected_tower.x >= 0 and sim.tower_by_cell.has(selected_tower)):
		_cancel_tower_move()
	if _moving_slate or _moving_tower:
		var key: String = "%s:%s:%s:%d" % [_moving_tower, cell, selected_tower if _moving_tower else selected_slate, sim.command_log.size()]
		if key == _move_hover_key:
			return
		_move_hover_key = key
	if _moving_slate:
		# Перенос слейта: кольцо радиуса под курсором — зелёное, если туда можно положить.
		var ms: TowerState = sim.slate_by_cell[selected_slate]
		var ok: bool = cell.x >= 0 and SlateCommands.can_move(sim, selected_slate, cell).is_empty()
		board.show_range(cell if cell.x >= 0 else selected_slate, ms.base_range, T.SUCCESS if ok else T.DANGER)
		return
	if _moving_tower:
		# Перенос башни: радиус атаки под курсором — зелёный, если туда можно (стена, башня или пустая клетка).
		var mt: TowerState = sim.tower_by_cell[selected_tower]
		var can: bool = cell.x >= 0 and BuildCommands.can_move_tower(sim, selected_tower, cell).is_empty()
		board.show_range(cell if cell.x >= 0 else selected_tower, mt.attack_range, T.SUCCESS if can else T.DANGER)
		board.set_preview(cell if can and sim.grid.get_cell(cell) == BoardGrid.Cell.EMPTY else Vector2i(-1, -1), {"ok": true})
		return
	_move_hover_key = ""
	var placing: bool = sim.phase == GameSim.Phase.PLACING and not autoplay and view_sim == sim
	if not placing or (cell.x >= 0 and sim.grid.get_cell(cell) != BoardGrid.Cell.EMPTY):
		if hover_cell.x >= 0:
			board.set_preview(Vector2i(-1, -1), {})
		hover_cell = Vector2i(-1, -1)
		_update_hover_range(cell)
		return
	if cell == hover_cell and _preview_version == sim.route.version:
		return
	hover_cell = cell
	if _preview_version != sim.route.version:
		_preview_cache.clear()
		_preview_version = sim.route.version
	if cell.x < 0:
		board.set_preview(cell, {})
		_update_hover_range(cell)
		return
	if not _preview_cache.has(cell):
		_preview_cache[cell] = sim.preview_place(cell)
	board.set_preview(cell, _preview_cache[cell])
	_update_hover_range(Vector2i(-1, -1))


func _update_hover_range(cell: Vector2i) -> void:
	if selected_tower.x >= 0 or selected_slate.x >= 0:
		return
	var t: TowerState = sim.tower_by_cell.get(cell) as TowerState
	if t != null:
		board.show_range(cell, t.attack_range, board.tower_color(t))
		return
	if sim.phase == GameSim.Phase.CHOOSING:
		var cand: Dictionary = sim.candidate_at(cell)
		if cand.is_empty() and selected_slot >= 0 and selected_slot < sim.candidates.size():
			cand = sim.candidates[selected_slot]
		if not cand.is_empty():
			_show_candidate_range(cand)
			return
	board.show_range(Vector2i(-1, -1), 0.0, Color.WHITE)


func _show_candidate_range(cand: Dictionary) -> void:
	var g: Dictionary = data.gem(String(cand["gem"]))
	board.show_range(cand["cell"], float(g["range"]) + float(data.quality(int(cand["quality"]))["range_bonus"]), T.gem_color(String(cand["gem"])))


func _on_click(cell: Vector2i) -> void:
	if not sim.grid.in_bounds(cell) or view_sim != sim:
		return
	if _moving_slate:
		if sim.is_build_phase() and selected_slate.x >= 0:
			# Не вышло (занято, не хватает золота) — режим переноса остаётся: можно выбрать другую клетку.
			_moving_slate = not _command({"type": "move_slate", "x": selected_slate.x, "y": selected_slate.y, "to_x": cell.x, "to_y": cell.y})
			return
		# Волна началась — переносить уже нельзя: клик обрабатывается как обычный.
		_cancel_slate_move()
	if _moving_tower:
		if sim.is_build_phase() and selected_tower.x >= 0:
			board.set_preview(Vector2i(-1, -1), {})
			_moving_tower = not _command({"type": "move_tower", "x": selected_tower.x, "y": selected_tower.y, "to_x": cell.x, "to_y": cell.y})
			return
		_cancel_tower_move()
	if sim.phase == GameSim.Phase.CHOOSING:
		var cand: Dictionary = sim.candidate_at(cell)
		if not cand.is_empty():
			# Повторный клик гем не оставляет — только кнопка «Оставить» (случайный выбор не того гема).
			if int(cand["slot"]) != selected_slot:
				_select_slot(int(cand["slot"]))
			return
	# Слейт лежит под стеной или башней: клик выбирает их, а слейт открывается кнопкой в их панели.
	if sim.tower_by_cell.has(cell):
		_select_tower(cell)
		return
	if sim.grid.get_cell(cell) == BoardGrid.Cell.ROCK:
		_select_wall(cell)
		return
	if sim.phase == GameSim.Phase.PLACING and not autoplay:
		# Слейт строительству не мешает: камень ставится прямо на него. Панель слейта при расстановке —
		# если камень сюда не встанет (перекроет путь); в остальных фазах клик по слейту открывает её.
		if sim.slate_by_cell.has(cell) and not bool(sim.preview_place(cell)["ok"]):
			_select_slate(cell)
			return
		_deselect()
		_command({"type": "place", "x": cell.x, "y": cell.y})
		return
	if sim.slate_by_cell.has(cell):
		_select_slate(cell)
		return
	_deselect()


func _select_tower(cell: Vector2i) -> void:
	selected_wall = Vector2i(-1, -1)
	selected_slate = Vector2i(-1, -1)
	_moving_slate = false
	_moving_tower = false
	selected_tower = cell
	var t: TowerState = sim.tower_by_cell[cell]
	hud.show_tower(sim, t)
	board.show_range(cell, t.attack_range, board.tower_color(t))
	Audio.play("sfx/ui/click")


func _select_wall(cell: Vector2i) -> void:
	selected_tower = Vector2i(-1, -1)
	selected_slate = Vector2i(-1, -1)
	_moving_slate = false
	_moving_tower = false
	selected_wall = cell
	hud.show_wall(sim, cell)
	board.show_range(cell, 0.7, T.WARNING)
	Audio.play("sfx/ui/click")


## Выход из режима переноса: кольцо радиуса возвращается на сам слейт.
func _cancel_slate_move() -> void:
	_moving_slate = false
	var s: TowerState = sim.slate_by_cell.get(selected_slate) as TowerState
	if s != null:
		board.show_range(s.cell, s.base_range, Color.html(String(data.slate(s.slate_id)["color"])))


## Выход из режима переноса башни: радиус возвращается на саму башню.
func _cancel_tower_move() -> void:
	_moving_tower = false
	board.set_preview(Vector2i(-1, -1), {})
	var t: TowerState = sim.tower_by_cell.get(selected_tower) as TowerState
	if t != null:
		board.show_range(t.cell, t.attack_range, board.tower_color(t))


## Слейт: панель с эффектами и кнопками (переложить, объединить, продать), кольцо радиуса на поле.
func _select_slate(cell: Vector2i) -> void:
	selected_tower = Vector2i(-1, -1)
	selected_wall = Vector2i(-1, -1)
	_moving_slate = false
	_moving_tower = false
	selected_slate = cell
	var s: TowerState = sim.slate_by_cell[cell]
	hud.show_slate(sim, s)
	board.show_range(cell, s.base_range, Color.html(String(data.slate(s.slate_id)["color"])))
	Audio.play("sfx/ui/click")


func _deselect() -> void:
	_moving_slate = false
	if _moving_tower:
		_moving_tower = false
		board.set_preview(Vector2i(-1, -1), {})
	if selected_tower.x < 0 and selected_wall.x < 0 and selected_slate.x < 0:
		return
	selected_tower = Vector2i(-1, -1)
	selected_wall = Vector2i(-1, -1)
	selected_slate = Vector2i(-1, -1)
	hud.hide_tower()
	board.show_range(Vector2i(-1, -1), 0.0, Color.WHITE)


# --- Команды -----------------------------------------------------------------

func _command(cmd: Dictionary) -> bool:
	if replay_ctl != null:
		return false
	var res: Dictionary = sim.apply(cmd)
	if not res["ok"]:
		var reason: String = String(res["reason"])
		if reason == "ERR_BLOCKS_PATH" and int(res.get("segment", -1)) >= 0:
			var seg: int = int(res["segment"])
			Events.toast_requested.emit(tr("ERR_BLOCKS_SEGMENT") % [_route_name(seg), _route_name(seg + 1)], "error")
		else:
			Events.toast_requested.emit(tr(reason), "error")
		Audio.play("sfx/build/invalid")
		return false
	return true


func _route_name(i: int) -> String:
	if i == 0:
		return tr("ROUTE_ENTRANCE")
	if i == sim.grid.route_points.size() - 1:
		return tr("ROUTE_EXIT")
	return "C%d" % i


## Кнопки фазы выбора и подсказки о сплаве.
func _on_action(id: String) -> void:
	var parts: PackedStringArray = id.split(":")
	match parts[0]:
		"keep":
			if selected_slot < 0 or selected_slot >= sim.candidates.size():
				Events.toast_requested.emit(tr("ERR_SELECT_GEM"), "error")
				return
			var cell: Vector2i = sim.candidates[selected_slot]["cell"]
			_command({"type": "keep", "x": cell.x, "y": cell.y})
		"downgrade":
			if selected_slot < 0 or selected_slot >= sim.candidates.size():
				return
			var dc: Vector2i = sim.candidates[selected_slot]["cell"]
			_command({"type": "downgrade", "x": dc.x, "y": dc.y})
		"start":
			_start_wave()
		"combine2", "combine4":
			var c2: Vector2i = sim.candidates[selected_slot]["cell"]
			_command({"type": "combine", "x": c2.x, "y": c2.y, "count": 2 if parts[0] == "combine2" else 4})
		"forge":
			var c3: Vector2i = sim.candidates[selected_slot]["cell"]
			_command({"type": "forge", "x": c3.x, "y": c3.y, "special": parts[1]})
		"upgrade3":
			var with_cell: Vector2i = sim.candidates[selected_slot]["cell"]
			_command({"type": "upgrade_special", "x": int(parts[1]), "y": int(parts[2]), "with_x": with_cell.x, "with_y": with_cell.y})
		"board_forge":
			_command({"type": "forge", "x": int(parts[1]), "y": int(parts[2]), "special": parts[3]})
		"slate":
			var c4: Vector2i = sim.candidates[selected_slot]["cell"]
			_command({"type": "make_slate", "x": c4.x, "y": c4.y, "slate": parts[1]})


## Кнопки панели башни/стены.
func _on_panel_action(id: String) -> void:
	if replay_ctl != null and id != "open_slate":
		return
	var parts: PackedStringArray = id.split(":")
	var c: Vector2i = selected_tower if selected_tower.x >= 0 else (selected_slate if selected_slate.x >= 0 else selected_wall)
	match parts[0]:
		"slate_move":
			_moving_slate = true
			Events.toast_requested.emit(tr("TOAST_MOVE_SLATE") % SlateCommands.move_cost(sim), "info")
		"tower_move":
			_moving_tower = true
			Events.toast_requested.emit(tr("TOAST_MOVE_TOWER") % BuildCommands.tower_move_cost(sim), "info")
		"polish":
			_command({"type": "polish", "x": c.x, "y": c.y})
		"open_slate":
			if sim.slate_by_cell.has(c):
				_select_slate(c)
		"slate_combine":
			_command({"type": "combine_slates", "x": c.x, "y": c.y, "with_x": int(parts[1]), "with_y": int(parts[2])})
		"target":
			_command({"type": "set_targeting", "x": c.x, "y": c.y, "mode": parts[1]})
		"toggle":
			var t: TowerState = sim.tower_by_cell.get(c) as TowerState
			if t != null:
				_command({"type": "toggle_tower", "x": c.x, "y": c.y, "enabled": not t.enabled})
		"upgrade":
			_command({"type": "upgrade_special", "x": c.x, "y": c.y})
		"merge":
			var with_x: int = int(parts[1])
			var with_y: int = int(parts[2])
			Modal.confirm(ui_layer, tr("CONFIRM_MERGE_TITLE"), tr("CONFIRM_MERGE_TEXT") % String.num(BuildCommands.merge_inherit(data)), tr("ACT_MERGE_SHORT"),
				func() -> void: _command({"type": "merge_special", "x": c.x, "y": c.y, "with_x": with_x, "with_y": with_y}), false)
		"forge":
			_command({"type": "forge", "x": c.x, "y": c.y, "special": parts[1]})
		"sell":
			# Слейт может лежать под башней (одна клетка): что продавать — решает открытая панель, а не клетка.
			var slate_panel: bool = selected_slate.x >= 0
			var t2: TowerState = (sim.slate_by_cell.get(c) if slate_panel else sim.tower_by_cell.get(c)) as TowerState
			if t2 == null:
				return
			var do_sell: Callable = func() -> void:
				if _command({"type": "sell_slate" if slate_panel else "sell", "x": c.x, "y": c.y}):
					_deselect()
			if t2.is_slate():
				# Слейт не становится стеной: клетка остаётся проходимой.
				Modal.confirm(ui_layer, tr("CONFIRM_SELL_SLATE_TITLE"), tr("CONFIRM_SELL_SLATE_TEXT") % t2.sell_value(data), tr("ACT_SELL") % t2.sell_value(data), do_sell)
			elif t2.is_special() or t2.quality >= 3:
				Modal.confirm(ui_layer, tr("CONFIRM_SELL_TITLE"), tr("CONFIRM_SELL_TEXT") % t2.sell_value(data), tr("ACT_SELL") % t2.sell_value(data), do_sell)
			else:
				do_sell.call()
		"break":
			if _command({"type": "break_wall", "x": c.x, "y": c.y}):
				_deselect()


func _select_slot(slot: int) -> void:
	if sim.phase != GameSim.Phase.CHOOSING or slot < 0 or slot >= sim.candidates.size():
		return
	selected_slot = slot
	hud.phase.select_card(slot)
	hud.phase.set_actions(ChoiceLogic.actions_for(sim, slot), tutorial.highlight() if tutorial != null else "")
	var cand: Dictionary = sim.candidates[slot]
	board.set_selected_candidate(cand["cell"])
	if selected_tower.x < 0:
		_show_candidate_range(cand)


func _on_card_hovered(slot: int, on: bool) -> void:
	if not on or slot >= sim.candidates.size():
		_update_hover_range(Vector2i(-1, -1))
		return
	_show_candidate_range(sim.candidates[slot])


func _start_wave() -> void:
	if sim.phase != GameSim.Phase.READY:
		return
	if race != null:
		Events.toast_requested.emit(tr("MP_WAIT_OTHERS"), "info")
		return
	countdown = -1.0
	_deselect()
	_command({"type": "start_wave"})


func _set_speed(s: int) -> void:
	if race != null:
		if Net.is_host():
			race.request_speed(s)
		else:
			hud.top.set_speed(speed)
			Events.toast_requested.emit(tr("MP_HOST_ONLY"), "info")
		return
	apply_speed(s)
	if paused:
		_toggle_pause()


func apply_speed(s: int) -> void:
	speed = s
	hud.top.set_speed(s)


func _toggle_pause() -> void:
	if race != null:
		if not race.request_pause(not paused):
			Events.toast_requested.emit(tr("MP_HOST_ONLY") if not Net.is_host() else tr("MP_NO_PAUSES"), "info")
		return
	apply_pause(not paused)


func apply_pause(on: bool) -> void:
	paused = on
	hud.top.set_paused(paused)
	Events.toast_requested.emit(tr("TOAST_PAUSED") if paused else tr("TOAST_RESUMED"), "info")


func _open_modal(m: Modal) -> void:
	_moving_slate = false
	_moving_tower = false
	menu_open = true
	cam.input_enabled = false
	m.closed.connect(func() -> void:
		menu_open = _modal_count() > 1
		cam.input_enabled = not menu_open)
	ui_layer.add_child(m)


func _modal_count() -> int:
	var n: int = 0
	for c: Node in ui_layer.get_children():
		if c is Modal and not c.is_queued_for_deletion():
			n += 1
	return n


## Чат открывается Enter, если не мешает окно: итоги матча не мешают (там самое время для «gg»),
## остальные окна (пауза, Кодекс, подтверждения) сами ждут Enter.
func _chat_allowed() -> bool:
	for c: Node in ui_layer.get_children():
		if c is Modal and not c.is_queued_for_deletion() and not (c is MatchResultsPanel or c is RaceOutPanel):
			return false
	return true


func _open_pause_menu() -> void:
	if menu_open or finished:
		return
	var pm: PauseMenu = PauseMenu.new()
	pm.setup(Save.can_save(sim) and race == null, race != null)
	pm.restart.connect(_restart_same_seed)
	pm.save_pressed.connect(_open_save_slots)
	pm.quit_to_menu.connect(func() -> void:
		if race != null:
			Net.leave()
		Audio.stop_loop("ambience/arena")
		Game.goto_scene("menu"))
	_open_modal(pm)


func _open_codex() -> void:
	if finished or _modal_count() > 0:
		return
	_open_modal(CodexPanel.new().setup(sim))


func _open_save_slots() -> void:
	var p: SaveSlotsPanel = SaveSlotsPanel.new().setup("save")
	p.save_requested.connect(func(slot: String) -> void:
		if Save.save_run(sim, slot, _save_meta()):
			Events.toast_requested.emit(tr("TOAST_SAVED"), "success")
		else:
			Events.toast_requested.emit(tr("ERR_SAVE_FAILED"), "error"))
	_open_modal(p)


func _save_meta() -> Dictionary:
	return {"real_seconds": real_time, "daily": String(Game.run_config.get("daily", ""))}


func _restart_same_seed() -> void:
	Save.delete(Save.AUTOSAVE)
	Game.new_run({"seed": sim.seed_value, "difficulty": sim.difficulty_id, "daily": String(Game.run_config.get("daily", "")), "max_waves": sim.total_waves})


# --- Гонка -------------------------------------------------------------------------

func _setup_race_ui() -> void:
	race_ctl = RaceController.new(self)


func _race_event(e: Dictionary) -> void:
	race_ctl.on_event(e)


func _refresh_race_hud() -> void:
	race_ctl.refresh()


# --- События симуляции ---------------------------------------------------------

func _dispatch_visual(e: Dictionary) -> void:
	board.on_event(e)
	enemies.on_event(e)
	projectiles.on_event(e)
	presenter.present(e)


func _dispatch(e: Dictionary) -> void:
	if view_sim == sim:
		_dispatch_visual(e)
	_update_music(e)
	if tutorial != null:
		tutorial.on_event(e)
	if hints != null:
		hints.on_event(e)
	if race != null:
		_race_event(e)
	match String(e["type"]):
		"gem_revealed", "luck_upgraded", "round_started", "wave_started":
			_sync_hud(true)
			if String(e["type"]) == "round_started" or String(e["type"]) == "wave_started":
				# Кнопки панели (огранка, перенос, продажа) доступны только при строительстве.
				_refresh_selection_panel()
			if String(e["type"]) == "round_started" and not autoplay and race == null and replay_ctl == null and stress == null and tutorial == null:
				Save.save_run(sim, Save.AUTOSAVE, _save_meta())
		"choice_ready":
			selected_slot = -1
			_sync_hud(true)
			if not autoplay and _screenshot.is_empty():
				_select_slot(_best_default_slot())
		"ready_for_wave":
			selected_slot = -1
			board.show_range(Vector2i(-1, -1), 0.0, Color.WHITE)
			_after_state_change()
			if _can_autostart():
				countdown = float(data.economy["countdown_seconds"])
				_last_count_tick = -1
			_sync_hud(true)
		"tower_moved":
			_after_state_change()
			if selected_tower == e["from"]:
				_select_tower(e["to"])
			elif selected_tower == e["to"] and sim.tower_by_cell.has(selected_tower):
				_select_tower(selected_tower)
		"special_forged", "tower_sold", "special_upgraded", "special_merged", "wall_broken", "tower_changed", "mvp_awarded":
			_after_state_change()
			if selected_tower.x >= 0 and not sim.tower_by_cell.has(selected_tower):
				_deselect()
			elif selected_tower.x >= 0:
				hud.show_tower(sim, sim.tower_by_cell[selected_tower])
			if String(e["type"]) == "special_forged" and not bool(e.get("one_hit", false)) and sim.phase == GameSim.Phase.READY:
				_sync_hud(true)
		"slate_made", "slates_combined", "slate_moved", "slate_sold":
			_after_state_change()
			if String(e["type"]) == "slate_moved" and selected_slate == e["from"]:
				selected_slate = e["to"]
			if selected_slate.x >= 0 and sim.slate_by_cell.has(selected_slate):
				_select_slate(selected_slate)
			elif selected_slate.x >= 0:
				_deselect()
		"path_changed":
			hud.top.set_path_length(sim.route.ground_length)
		"lives_changed":
			hud.top.set_lives(sim.lives, int(e["delta"]) < 0)
			board.set_lives_ratio(float(sim.lives) / float(maxi(sim.max_lives, 1)))
			_sync_economy()
		"gold_changed":
			hud.top.set_gold(sim.gold, true)
			_sync_economy()
			if sim.is_build_phase():
				_refresh_selection_panel()
		"wave_cleared":
			enemies.clear()
			projectiles.clear()
			_refresh_tower_stats()
		"game_over":
			_on_game_over(bool(e["victory"]))
		"damage_test_finished":
			_on_damage_test_finished()


## Музыкальные состояния следуют за своим полем: строительство, бой, босс, победа, поражение.
func _update_music(e: Dictionary) -> void:
	match String(e["type"]):
		"round_started", "wave_cleared":
			Audio.music("build")
		"wave_started":
			Audio.music("boss" if bool(e["boss"]) else "combat")
		"damage_test_started":
			Audio.music("combat")
		"game_over":
			Audio.music("victory" if bool(e["victory"]) else "defeat")


func _best_default_slot() -> int:
	var best: int = 0
	var best_dps: float = -1.0
	var air: bool = data.is_air_wave(sim.round_index)
	for cand: Dictionary in sim.candidates:
		var d: float = TowerState.estimate_dps(data, String(cand["gem"]), int(cand["quality"]), air)
		if not RecipeBook.available_at(sim, cand["cell"]).is_empty():
			d += 100000.0
		if d > best_dps:
			best_dps = d
			best = int(cand["slot"])
	return best


## После изменений поля: доступные сплавы, трекер рецепта, подсветка компонентов.
func _after_state_change() -> void:
	_board_forges = ChoiceLogic.board_forges(sim)
	# Сплав — в любой момент матча, и в бою (в Испытании урона board_forges пуст).
	if not sim.is_over() and replay_ctl == null:
		hud.phase.show_board_forge(_board_forges, data)
	_refresh_tracker()


## Трекер рецептов и метки на поле: компоненты отслеживаемых рецептов и повторы среди кандидатов.
func _refresh_tracker() -> void:
	board.set_recipe_marks(hud.tracker.update_from(sim))
	board.set_duplicate_marks()


# --- HUD -----------------------------------------------------------------------

func _sync_hud(animate: bool) -> void:
	var n: int = sim.next_wave_number()
	var w: Dictionary = data.wave(n)
	hud.top.set_wave(n, sim.total_waves, String(w["modifier"]), data.is_air_wave(n), data.is_boss_wave(n))
	hud.top.set_lives(sim.lives, false)
	hud.top.set_gold(sim.gold, animate)
	hud.top.set_path_length(sim.route.ground_length)
	_sync_economy()
	hud.wave_panel.show_wave(data, WaveSpawner.summary(data, n, sim.finale_for(n)), sim.diff)
	if replay_ctl != null:
		hud.phase.hide_all()
		_refresh_tracker()
		return
	match sim.phase:
		GameSim.Phase.PLACING:
			hud.phase.show_placing(sim.round_index, sim.candidates.size(), sim.rocks_per_round)
		GameSim.Phase.CHOOSING:
			hud.phase.show_choosing(data, sim.candidates, data.is_air_wave(sim.round_index), selected_slot, ChoiceLogic.card_hints(sim))
			hud.phase.set_actions(ChoiceLogic.actions_for(sim, selected_slot), tutorial.highlight() if tutorial != null else "")
		GameSim.Phase.READY:
			hud.phase.show_ready(sim.round_index, countdown, countdown >= 0.0)
		GameSim.Phase.COMBAT:
			if sim.damage_test:
				hud.phase.hide_all()
			else:
				hud.phase.show_combat(sim.wave_number, sim.enemies.size(), sim.combat.schedule_index, sim.combat.schedule.size())
		_:
			hud.phase.hide_all()
	if not sim.is_over():
		hud.phase.show_board_forge(_board_forges, data)
	_refresh_tracker()


func _sync_economy() -> void:
	var cost: int = data.luck_cost(sim.luck)
	var names: Array = []
	for i: int in data.quality_count():
		var ql: Dictionary = data.quality(i + 1)
		names.append("%s %s" % [String(ql["roman"]), tr(String(ql["key"]))])
	hud.top.set_luck(sim.luck, data.luck_roman(sim.luck), cost, cost >= 0 and sim.gold >= cost, data.luck_chances(sim.luck), names)
	var life_cost: int = BuildCommands.buy_life_cost(sim)
	hud.top.set_buy_life(sim.lives < sim.max_lives and sim.is_build_phase(), life_cost, sim.gold >= life_cost)
	if sim.phase == GameSim.Phase.CHOOSING and selected_slot >= 0:
		hud.phase.set_actions(ChoiceLogic.actions_for(sim, selected_slot), tutorial.highlight() if tutorial != null else "")


## Пересобрать панель выбранной башни, слейта или стены (цены и доступность кнопок).
func _refresh_selection_panel() -> void:
	if not hud.tower_panel.visible:
		return
	if selected_tower.x >= 0 and sim.tower_by_cell.has(selected_tower):
		hud.show_tower(sim, sim.tower_by_cell[selected_tower])
	elif selected_slate.x >= 0 and sim.slate_by_cell.has(selected_slate):
		hud.show_slate(sim, sim.slate_by_cell[selected_slate])
	elif selected_wall.x >= 0 and sim.grid.get_cell(selected_wall) == BoardGrid.Cell.ROCK:
		hud.show_wall(sim, selected_wall)


func _refresh_tower_stats() -> void:
	if selected_tower.x >= 0 and hud.tower_panel.visible:
		var t: TowerState = sim.tower_by_cell.get(selected_tower) as TowerState
		if t != null:
			hud.tower_panel.refresh(t)
	elif selected_slate.x >= 0 and hud.tower_panel.visible:
		var s: TowerState = sim.slate_by_cell.get(selected_slate) as TowerState
		if s != null:
			hud.tower_panel.refresh(s)


# --- Конец забега ------------------------------------------------------------

func _on_game_over(victory: bool) -> void:
	if replay_ctl != null:
		return
	if race_ctl != null:
		race_ctl.on_local_over(sim.summary(), victory)
		hud.phase.hide_all()
		hud.hide_tower()
		return
	finished = true
	countdown = -1.0
	hud.phase.hide_all()
	hud.hide_tower()
	Save.delete(Save.AUTOSAVE)
	var summary: Dictionary = sim.summary()
	var submit: Dictionary
	if bool(Game.run_config.get("tutorial", false)):
		# Забег обучения (гемы заданы заранее) в таблицу лидеров не идёт.
		submit = {"record": {"score": Scoring.compute(data, summary), "name": Settings.player_name()}}
	else:
		submit = Leaderboard.submit(sim, {"real_seconds": real_time, "daily": String(Game.run_config.get("daily", ""))})
	_record_id = String(submit["record"].get("id", ""))
	Game.last_result = {"summary": summary, "submit": submit}
	hud.banner.show_banner(tr("RESULT_VICTORY") if victory else tr("RESULT_DEFEAT"), "", T.SUCCESS if victory else T.DANGER, 0.8)
	if autoplay and _screenshot.is_empty():
		print("autoplay: %s, волн %d/%d, очки %d, checksum %d" % [summary["outcome"], int(summary["waves_cleared"]), int(summary["total_waves"]), int(submit["record"]["score"]), int(summary["checksum"])])
	await get_tree().create_timer(1.3 if _screenshot.is_empty() else 0.1).timeout
	_show_results(summary, submit, {})


## Итоги забега. test — результат Испытания урона ({record, rank, best}) или {}.
func _show_results(summary: Dictionary, submit: Dictionary, test: Dictionary) -> void:
	var rp: ResultsPanel = ResultsPanel.new()
	rp.setup(data, summary, submit, test, (autoplay == false or not _screenshot.is_empty()) and not _record_id.is_empty())
	rp.damage_test.connect(func() -> void:
		rp.close()
		_start_damage_test())
	rp.watch_replay.connect(func() -> void:
		Game.new_run({"mode": "replay", "replay": Replay.from_sim(sim, Game.version()), "record": submit.get("record", {})}))
	rp.replay_seed.connect(_restart_same_seed)
	rp.new_game.connect(func() -> void:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.randomize()
		Game.new_run({"seed": rng.randi(), "difficulty": sim.difficulty_id, "max_waves": sim.total_waves}))
	rp.to_menu.connect(func() -> void:
		Audio.stop_loop("ambience/arena")
		Game.goto_scene("menu"))
	ui_layer.add_child(rp)


# --- Испытание урона ------------------------------------------------------------

func _start_damage_test() -> void:
	if not _command({"type": "start_damage_test"}):
		return
	if _test_bar == null:
		_test_bar = DamageTestBar.new()
		hud.add_child(_test_bar)
		_test_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_test_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_test_bar.offset_top = 96
	_test_bar.start(sim.damage_test_duration())
	hud.phase.hide_all()
	hud.banner.show_banner(tr("DT_TITLE"), tr("DT_BANNER_SUB") % int(sim.damage_test_duration()), T.DANGER, 1.4)
	Audio.play("sfx/game/damage_test_start")


func _on_damage_test_finished() -> void:
	if _test_bar != null:
		_test_bar.visible = false
	var test: Dictionary = Leaderboard.submit_damage_test(_record_id, sim)
	var summary: Dictionary = sim.summary()
	hud.banner.show_banner(tr("DT_DONE") % T.format_number(float(summary["damage_test_dps"])), "", T.GOLD, 1.0)
	Audio.play("sfx/game/damage_test_end")
	if autoplay and _screenshot.is_empty():
		print("autoplay: испытание урона, DPS %d, урон %d" % [int(summary["damage_test_dps"]), int(summary["damage_test_damage"])])
	await get_tree().create_timer(1.2 if _screenshot.is_empty() else 0.1).timeout
	var rec: Dictionary = Leaderboard.find(_record_id)
	_show_results(summary, {"record": rec, "rank": Leaderboard.rank_of(_record_id, "classic", String(rec.get("difficulty", "")))}, test)


# --- Скриншоты для самопроверки ------------------------------------------------

func _prepare_screenshot_state() -> void:
	match _screenshot:
		"combat":
			while sim.round_index < 6 and not sim.is_over():
				if sim.phase == GameSim.Phase.COMBAT:
					sim.step()
				else:
					bot.act()
			bot.play_build_phase()
		"results":
			bot.run_to_end()
		"saveload":
			while sim.round_index < 4 and not sim.is_over():
				if sim.phase == GameSim.Phase.COMBAT:
					sim.step()
				else:
					bot.act()
			bot.act()
			bot.act()
		"boss":
			# Финальный босс: доигрываем до последней волны с боссом (на Easy, чтобы бот дожил) и ждём, пока выйдет
			# последний из её боссов (в финале 62-й Король выходит после Матки Роя), и ещё 14 с боя.
			var boss_wave: int = int((data.waves_cfg["boss_waves"] as Array).max())
			_advance_to_round(boss_wave)
			bot.play_build_phase()
			var last_boss_at: float = 0.0
			for grp: Dictionary in data.wave(boss_wave)["groups"]:
				if bool(data.archetype(String(grp["type"]))["boss"]):
					last_boss_at = maxf(last_boss_at, float(grp["delay"]))
			while sim.phase == GameSim.Phase.COMBAT and sim.wave_time < last_boss_at + 14.0:
				sim.step()
		"stress":
			_advance_to_round(27)
			bot.play_build_phase()
		"forge":
			# Раунд, где выпал полный рецепт Венца Пепла (Рубин I + Топаз I + Изумруд I): сплав одним раундом.
			_advance_to_round(3)
			var recipe: Array = [["ruby", 1], ["topaz", 1], ["emerald", 1], ["amethyst", 1], ["opal", 1]]
			while sim.phase == GameSim.Phase.PLACING:
				bot.act()
			for i: int in sim.candidates.size():
				sim.candidates[i]["gem"] = String(recipe[i][0])
				sim.candidates[i]["quality"] = int(recipe[i][1])
		"vfx":
			# Крупный план: плотная волна со статусами (яд, замедление, оглушение) у лабиринта 19-го раунда.
			_advance_to_round(19)
			bot.play_build_phase()
		"damagetest":
			bot.run_to_end()
		"wavetraits":
			_advance_to_round(33)
		"codextraits", "codexspecials", "codexenemies", "codexhelp":
			_advance_to_round(9)
		"forecast":
			_advance_to_round(18)
		"tower", "codex":
			while sim.round_index < 9 and not sim.is_over():
				if sim.phase == GameSim.Phase.COMBAT:
					sim.step()
				else:
					bot.act()
	sim.drain_events()


## Скриншоты: доигрывает ботом до начала раунда n (фаза строительства).
func _advance_to_round(n: int) -> void:
	while sim.round_index < n and not sim.is_over():
		if sim.phase == GameSim.Phase.COMBAT:
			sim.step()
		else:
			bot.act()
	if sim.is_over():
		push_error("screenshot %s: бот не дожил до раунда %d" % [_screenshot, n])


func _run_screenshot() -> void:
	match _screenshot:
		"boss":
			_set_speed(1)
			await get_tree().create_timer(3.0).timeout
		"forecast":
			await get_tree().create_timer(0.6).timeout
			hud.forecast.toggle(data, sim.next_wave_number(), sim.wave_limit(), sim.diff, sim.finale_for(sim.total_waves))
			hud.wave_panel.log_event(tr("LOG_BOSS_WAVE") % 20, "boss", T.BOSS, "combat", board.cell_world(sim.grid.route_points[0]))
			await get_tree().create_timer(1.0).timeout
		"tutorial":
			# Обучение: камни ставятся командами игрока, шаги переключаются по событиям.
			await get_tree().create_timer(0.8).timeout
			for i: int in 5:
				var rc: Vector2i = bot.choose_rock_cell()
				_command({"type": "place", "x": rc.x, "y": rc.y})
				await get_tree().create_timer(0.25).timeout
			_select_slot(1)
			await get_tree().create_timer(1.2).timeout
			print("tutorial: шаг %d, гемы %s" % [tutorial.step, str(sim.candidates.map(func(c: Dictionary) -> String: return "%s%d" % [c["gem"], c["quality"]]))])
		"forge":
			await get_tree().create_timer(1.0).timeout
			var fc: Vector2i = sim.candidates[0]["cell"]
			_command({"type": "forge", "x": fc.x, "y": fc.y, "special": "cinder_crown"})
			await get_tree().create_timer(0.7).timeout
		"vfx":
			_set_speed(1)
			await get_tree().create_timer(5.5).timeout
			var center: Vector2 = Vector2.ZERO
			for e: EnemyState in sim.enemies:
				center += e.pos
			if not sim.enemies.is_empty():
				center /= float(sim.enemies.size())
			cam.focus_on(board.w(center), 22.0)
			await get_tree().create_timer(1.6).timeout
		"stress":
			# 200+ врагов на поле: к волне добавляются группы прямо в расписание (только для проверки производительности).
			_command({"type": "start_wave"})
			var kinds: Array[String] = ["swarm", "normal", "fast", "armored", "flying", "regenerating"]
			for i: int in 180:
				sim.combat.schedule.append({"time": 0.5 + float(i) * 0.03, "type": kinds[i % kinds.size()], "hp_mult": 6.0,
					"traits": [], "elite": i % 17 == 0, "order": 1000 + i})
			sim.combat.schedule.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["time"]) < float(b["time"]))
			_set_speed(1)
			await get_tree().create_timer(7.0).timeout
			print("stress: врагов %d, снарядов %d, FPS %d" % [sim.enemies.size(), sim.projectiles.size(), Engine.get_frames_per_second()])
		"damagetest":
			_on_game_over(sim.phase == GameSim.Phase.VICTORY)
			await get_tree().create_timer(0.6).timeout
			for m: Node in ui_layer.get_children():
				if m is ResultsPanel:
					(m as ResultsPanel).close()
			_start_damage_test()
			await get_tree().create_timer(9.0).timeout
		"wavetraits":
			await get_tree().create_timer(1.2).timeout
		"codexspecials":
			# Конец списка спец-башен: эмблемы и описания поздних рецептов.
			_open_codex()
			await get_tree().create_timer(0.4).timeout
			for m3: Node in ui_layer.get_children():
				if m3 is CodexPanel:
					var sc: ScrollContainer = (m3 as CodexPanel).find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
					sc.scroll_vertical = 100000
			await get_tree().create_timer(1.0).timeout
		"codextraits", "codexenemies", "codexhelp":
			_open_codex()
			await get_tree().create_timer(0.3).timeout
			for m2: Node in ui_layer.get_children():
				if m2 is CodexPanel:
					var tabs: TabContainer = (m2 as CodexPanel).find_children("*", "TabContainer", true, false)[0] as TabContainer
					tabs.current_tab = {"codextraits": 4, "codexenemies": 3, "codexhelp": tabs.get_tab_count() - 1}[_screenshot]
			await get_tree().create_timer(1.2).timeout
		"build":
			# Ставим камни настоящими кликами мыши — проверка пути ввода игрока.
			await get_tree().create_timer(0.6).timeout
			var to_window: Vector2 = Vector2(get_window().size) / get_viewport().get_visible_rect().size
			for i: int in 3:
				var cell: Vector2i = bot.choose_rock_cell()
				var at: Vector2 = cam.cam.unproject_position(board.cell_world(cell)) * to_window
				var click: InputEventMouseButton = InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = true
				click.position = at
				click.global_position = at
				Input.parse_input_event(click)
				var release: InputEventMouseButton = click.duplicate()
				release.pressed = false
				Input.parse_input_event(release)
				await get_tree().create_timer(0.35).timeout
			if sim.candidates.size() != 3:
				push_error("screenshot build: клики не поставили камни (%d/3)" % sim.candidates.size())
			await get_tree().create_timer(0.5).timeout
			var target: Vector2i = bot.choose_rock_cell()
			get_viewport().warp_mouse(cam.cam.unproject_position(board.cell_world(target)))
			print("build: кликами поставлено %d/3 камней" % sim.candidates.size())
			await get_tree().create_timer(1.2).timeout
		"draft":
			while sim.phase == GameSim.Phase.PLACING:
				bot.act()
			await get_tree().create_timer(0.3).timeout
			_select_slot(_best_default_slot())
			await get_tree().create_timer(1.5).timeout
		"combat":
			_set_speed(2)
			await get_tree().create_timer(7.0).timeout
		"results":
			_on_game_over(sim.phase == GameSim.Phase.VICTORY)
			await get_tree().create_timer(3.4).timeout
		"tower":
			var pick: Vector2i = sim.towers[0].cell
			for t: TowerState in sim.towers:
				if t.is_special():
					pick = t.cell
					break
			_select_tower(pick)
			await get_tree().create_timer(1.5).timeout
		"codex":
			Settings.set_value("general", "pinned_recipe", "")
			Settings.set_value("general", "pinned_recipes", ["cinder_crown", "beacon_lens", "skypiercer", "frostwell"])
			_open_codex()
			await get_tree().create_timer(1.5).timeout
		"saveload":
			Save.save_run(sim, "slot1", _save_meta())
			print("saveload: сохранено в slot1, раунд %d, checksum %d" % [sim.round_index, sim.checksum()])
			Game.new_run({"load_slot": "slot1", "verify_checksum": sim.checksum()})
			return
		"loaded":
			await get_tree().create_timer(1.5).timeout
		"replay":
			replay_ctl.speed = 4
			await get_tree().create_timer(9.0).timeout
	await Game.save_screenshot(_screenshot)
	get_tree().quit()
