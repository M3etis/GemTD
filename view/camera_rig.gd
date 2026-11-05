class_name CameraRig
extends Node3D
## Камера 2.5D: фиксированный наклон, плавный зум, панорама WASD/стрелками/средней кнопкой.
## Зум: колесо, Ctrl/Cmd + колесо или прокрутка тачпада и Magic Mouse (в macOS она приходит жестом
## панорамы, без Ctrl двигает камеру), щипок, Ctrl/Cmd + «+» / «−»; Ctrl/Cmd + 0 — исходный зум.

const PITCH_DEG: float = 57.0
const FOV: float = 34.0
## Ближе — в кадре около восьми клеток по высоте (башня и её соседи), дальше — всё поле с запасом по краям.
const MIN_DIST: float = 14.0
const MAX_DIST: float = 54.0
const PAN_SPEED: float = 16.0
## Шаг зума колесом и клавишами (доля дистанции).
const ZOOM_STEP: float = 0.1

var cam: Camera3D
var target: Vector3 = Vector3.ZERO
var distance: float = 34.0
var _goal_target: Vector3 = Vector3.ZERO
var _goal_distance: float = 34.0
var _default_distance: float = 34.0
var _half: Vector2 = Vector2(16, 12)
var _dragging: bool = false
var _shake: float = 0.0
var input_enabled: bool = true
## Кинематографичный наезд (Forge): до какого времени держать фокус и куда вернуться.
var _focus_until: float = -1.0
var _saved_target: Vector3 = Vector3.ZERO
var _saved_distance: float = 34.0


func setup(board_w: int, board_h: int) -> void:
	_half = Vector2(board_w, board_h) * 0.5
	cam = Camera3D.new()
	cam.fov = FOV
	cam.near = 0.1
	cam.far = 200.0
	add_child(cam)
	_default_distance = clampf(float(board_h) * 1.86, MIN_DIST, MAX_DIST)
	reset(true)


func reset(instant: bool = false) -> void:
	_goal_target = Vector3(2.6, 0, 1.4)
	_goal_distance = _default_distance
	if instant:
		target = _goal_target
		distance = _goal_distance
		_apply()


## Тряска — только для боссов и крупных взрывов (§7 PROMPT.md); отключается в настройках.
func add_shake(amount: float) -> void:
	if not Settings.screen_shake():
		return
	_shake = minf(_shake + amount, 0.6)


## Короткий наезд камеры на точку (создание спец-башни). Отключается настройкой «Кинематографичный зум».
func focus_punch(point: Vector3, hold: float = 0.7) -> void:
	if not Settings.cinematic_zoom():
		return
	if _focus_until < 0.0:
		_saved_target = _goal_target
		_saved_distance = _goal_distance
	_focus_until = Time.get_ticks_msec() / 1000.0 + hold
	_goal_target = Vector3(point.x, 0.0, point.z)
	_goal_distance = clampf(_saved_distance * 0.55, MIN_DIST, MAX_DIST)


## Плавно навести камеру на точку с заданной дистанцией (скриншоты, наблюдение).
func focus_on(point: Vector3, dist: float) -> void:
	_end_focus(false)
	_goal_target = Vector3(point.x, 0.0, point.z)
	_goal_distance = clampf(dist, MIN_DIST, MAX_DIST)
	_clamp_goal()


func _end_focus(restore: bool) -> void:
	if _focus_until < 0.0:
		return
	_focus_until = -1.0
	if restore:
		_goal_target = _saved_target
		_goal_distance = _saved_distance


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton or event is InputEventMagnifyGesture or event is InputEventPanGesture:
		_end_focus(true)
	if event is InputEventKey and (event as InputEventKey).pressed and _zoom_modifier(event as InputEventKey):
		var ke: InputEventKey = event
		match ke.keycode:
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				zoom_by(1.0 - ZOOM_STEP)
				get_viewport().set_input_as_handled()
			KEY_MINUS, KEY_KP_SUBTRACT:
				zoom_by(1.0 + ZOOM_STEP)
				get_viewport().set_input_as_handled()
			KEY_0, KEY_KP_0:
				_end_focus(false)
				_goal_distance = _default_distance
				get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_by(1.0 - ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_by(1.0 + ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mm: InputEventMouseMotion = event
		var k: float = distance / 900.0
		_goal_target += Vector3(-mm.relative.x * k, 0, -mm.relative.y * k * 1.2)
		_clamp_goal()
	elif event is InputEventMagnifyGesture:
		var mg: InputEventMagnifyGesture = event
		_goal_distance = clampf(_goal_distance / mg.factor, MIN_DIST, MAX_DIST)
	elif event is InputEventPanGesture:
		var pg: InputEventPanGesture = event
		if pg.ctrl_pressed or pg.meta_pressed:
			# Ctrl + прокрутка тачпада / Magic Mouse — зум (вверх — ближе), как Ctrl + колесо.
			zoom_by(1.0 + clampf(pg.delta.y * 0.04, -0.25, 0.25))
			return
		_goal_target += Vector3(pg.delta.x, 0, pg.delta.y) * distance * 0.01
		_clamp_goal()


## Зум: множитель дистанции (< 1 — ближе), в пределах MIN_DIST…MAX_DIST.
func zoom_by(k: float) -> void:
	_goal_distance = clampf(_goal_distance * k, MIN_DIST, MAX_DIST)


static func _zoom_modifier(ke: InputEventKey) -> bool:
	return (ke.ctrl_pressed or ke.meta_pressed) and not ke.alt_pressed


func _process(delta: float) -> void:
	if _focus_until >= 0.0 and Time.get_ticks_msec() / 1000.0 >= _focus_until:
		_end_focus(true)
	if input_enabled:
		var move: Vector2 = Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
		if move != Vector2.ZERO:
			_goal_target += Vector3(move.x, 0, move.y) * PAN_SPEED * delta * (distance / _default_distance)
			_clamp_goal()
		if Input.is_action_just_pressed("camera_reset"):
			reset()
	var k: float = 1.0 - exp(-delta * 10.0)
	target = target.lerp(_goal_target, k)
	distance = lerpf(distance, _goal_distance, k)
	_shake = maxf(0.0, _shake - delta * 1.8)
	_apply()


func _clamp_goal() -> void:
	_goal_target.x = clampf(_goal_target.x, -_half.x, _half.x)
	_goal_target.z = clampf(_goal_target.z, -_half.y, _half.y)


func _apply() -> void:
	var pitch: float = deg_to_rad(PITCH_DEG)
	var offset: Vector3 = Vector3(0, sin(pitch), cos(pitch)) * distance
	var jitter: Vector3 = Vector3.ZERO
	if _shake > 0.0:
		var t: float = Time.get_ticks_msec() * 0.05
		jitter = Vector3(sin(t * 1.7), sin(t * 2.3), cos(t * 1.9)) * _shake * 0.35
	cam.position = target + offset + jitter
	cam.look_at(target + jitter * 0.5, Vector3.UP)


## Точка на плоскости y=0 под экранной координатой (или null).
func ground_point(screen_pos: Vector2) -> Variant:
	var origin: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return null
	var t: float = -origin.y / dir.y
	if t < 0.0:
		return null
	return origin + dir * t
