extends Node
## Навигация между экранами, параметры забега и аргументы командной строки.
## CLI (после «--»): --autoplay --seed=N --waves=N --strategy=maze --difficulty=normal
##                   --visual --screenshot=<menu|build|draft|combat|results|leaderboard|settings>
##                   --audio-report --audio-dir=<путь>

const SCENES: Dictionary = {
	"menu": "res://scenes/main_menu/main_menu.tscn",
	"game": "res://scenes/game/game.tscn",
	"lobby": "res://scenes/lobby/lobby.tscn",
}
const TRANSITION_SHADER: Shader = preload("res://fx/post/transition.gdshader")

var cli: Dictionary = {}
var run_config: Dictionary = {}
var last_result: Dictionary = {}
var _layer: CanvasLayer
var _cover: ColorRect
var _busy: bool = false
var _pending: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cli = parse_cli(OS.get_cmdline_user_args())
	get_tree().root.theme = ThemeBuilder.get_theme()
	# Закрытие окна идёт через quit_game(): сначала гасим звук, иначе аудиопоток держит ресурсы при выходе.
	get_tree().set_auto_accept_quit(false)
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_cover = ColorRect.new()
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = TRANSITION_SHADER
	_cover.material = mat
	_cover.visible = false
	_layer.add_child(_cover)


static func parse_cli(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for a: String in args:
		if not a.begins_with("--"):
			continue
		var body: String = a.substr(2)
		var eq: int = body.find("=")
		if eq >= 0:
			out[body.substr(0, eq)] = body.substr(eq + 1)
		else:
			out[body] = true
	return out


func version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))


func new_run(cfg: Dictionary) -> void:
	run_config = cfg.duplicate(true)
	goto_scene("game")


## Короткое замедление времени (раскрытие редкого гема). Живёт в автозагрузке: таймер не теряется
## при смене сцены, а смена сцены всегда возвращает нормальную скорость.
func slow_motion(scale: float, seconds: float) -> void:
	if Engine.time_scale < 1.0:
		return
	Engine.time_scale = scale
	get_tree().create_timer(seconds, true, false, true).timeout.connect(func() -> void: Engine.time_scale = 1.0)


func goto_scene(key: String) -> void:
	Engine.time_scale = 1.0
	if _busy:
		# Переход уже идёт — выполним запрошенный следом, а не потеряем его.
		_pending = key
		return
	_busy = true
	var path: String = SCENES.get(key, key)
	var fast: bool = Settings.reduce_motion() or cli.has("screenshot")
	var mat: ShaderMaterial = _cover.material
	_cover.visible = true
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	if not fast:
		mat.set_shader_parameter("progress", 0.0)
		var tw: Tween = create_tween()
		tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("progress", v), 0.0, 1.0, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		await tw.finished
	else:
		mat.set_shader_parameter("progress", 1.0)
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	if not fast:
		var tw2: Tween = create_tween()
		tw2.tween_method(func(v: float) -> void: mat.set_shader_parameter("progress", v), 1.0, 0.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		await tw2.finished
	_cover.visible = false
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
	if not _pending.is_empty():
		var next: String = _pending
		_pending = ""
		goto_scene(next)


func _exit_tree() -> void:
	# Статические кэши держат ресурсы до выхода — освобождаем, чтобы не было «leaked at exit».
	get_tree().root.theme = null
	ThemeBuilder._theme = null
	UiTokens._fonts.clear()
	MeshFactory._cache.clear()
	Ui._glass_material = null
	GameData.clear_cache()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


func quit_game(code: int = 0) -> void:
	Audio.stop_all()
	await get_tree().create_timer(0.25, true, false, true).timeout
	get_tree().quit(code)


## Сохраняет PNG текущего кадра в docs/screenshots (для самопроверки агента).
## В экспортированной игре — в user://dev/screenshots: бандл .app подписан и только для чтения.
func save_screenshot(name: String) -> String:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	# Английская версия интерфейса — в отдельную папку (скриншоты RU и EN, §15 этап 6).
	var root: String = "user://dev/screenshots" if OS.has_feature("template") else "res://docs/screenshots"
	var dir: String = ProjectSettings.globalize_path(root + ("/en" if TranslationServer.get_locale().begins_with("en") else ""))
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = dir.path_join(name + ".png")
	img.save_png(path)
	print("screenshot: " + path)
	Audio.stop_all()
	await get_tree().create_timer(0.25, true, false, true).timeout
	return path


func today_iso() -> String:
	return Time.get_date_string_from_system()
