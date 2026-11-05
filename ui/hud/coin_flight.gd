class_name CoinFlight
extends Control
## Монеты летят от убитого врага к счётчику золота (§8.4). Все монеты — один узел, один _draw и одна
## заранее нарисованная текстура: draw_circle / draw_colored_polygon триангулируют фигуру на CPU при
## каждом вызове (~12 мкс), а монеты перерисовываются каждый кадр; draw_texture_rect — ~0.3 мкс.
## Прежний вариант (Control-иконка с твином на каждую монету) стоил ~0.8 мс кадра в стресс-тесте.

const T := preload("res://ui/theme/ui_tokens.gd")
## Монет в полёте одновременно не больше MAX_COINS (в большом бою убийств десятки в секунду).
const MAX_COINS: int = 24
const FLIGHT: float = 0.6
const STAGGER: float = 0.04
const SIZE: float = 16.0

## {start, mid, to, t}: t < 0 — монета ещё ждёт своей очереди (веер вылета).
var _coins: Array[Dictionary] = []
static var _texture: ImageTexture


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(false)


func in_flight() -> int:
	return _coins.size()


## from и to — точки экрана; лишние монеты сверх MAX_COINS не запускаются.
func spawn(from: Vector2, to: Vector2, count: int) -> void:
	for i: int in mini(count, MAX_COINS - _coins.size()):
		var start: Vector2 = from + Vector2(randf_range(-14.0, 14.0), randf_range(-10.0, 10.0))
		var mid: Vector2 = start.lerp(to, 0.5) + Vector2(randf_range(-60.0, 60.0), -80.0)
		_coins.append({"start": start, "mid": mid, "to": to, "t": -STAGGER * float(i)})
	if not _coins.is_empty():
		set_process(true)


func _process(delta: float) -> void:
	for i: int in range(_coins.size() - 1, -1, -1):
		var c: Dictionary = _coins[i]
		c["t"] = float(c["t"]) + delta
		if float(c["t"]) >= FLIGHT:
			_coins.remove_at(i)
	queue_redraw()
	if _coins.is_empty():
		set_process(false)


func _draw() -> void:
	var tex: ImageTexture = coin_texture()
	for c: Dictionary in _coins:
		var t: float = float(c["t"])
		if t < 0.0:
			continue
		# Квадратичная кривая Безье с ускорением к концу (как sine-in у прежнего твина).
		var k: float = 1.0 - cos(clampf(t / FLIGHT, 0.0, 1.0) * PI * 0.5)
		var mid: Vector2 = c["mid"]
		var p: Vector2 = (c["start"] as Vector2).lerp(mid, k).lerp(mid.lerp(c["to"], k), k)
		var s: float = SIZE * (1.0 - 0.4 * k)
		draw_texture_rect(tex, Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), false)


## Монета как у иконки «coin»: золотой круг, тёмная середина, светлый ромб; рисуется один раз, 32×32 со сглаживанием.
static func coin_texture() -> ImageTexture:
	if _texture != null:
		return _texture
	var n: int = 32
	var img: Image = Image.create(n, n, false, Image.FORMAT_RGBA8)
	var half: float = float(n) * 0.5
	for y: int in n:
		for x: int in n:
			var q: Vector2 = Vector2(float(x) + 0.5 - half, float(y) + 0.5 - half)
			var d: float = q.length()
			var col: Color = T.GOLD.lerp(T.GOLD.darkened(0.35), clampf(0.3 * float(n) - d + 0.5, 0.0, 1.0))
			var diamond: float = 1.0 - (absf(q.x) / (0.16 * float(n)) + absf(q.y) / (0.2 * float(n)))
			col = col.lerp(T.GOLD.lightened(0.2), clampf(diamond * 6.0, 0.0, 1.0))
			col.a = clampf(0.44 * float(n) - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, col)
	_texture = ImageTexture.create_from_image(img)
	return _texture
