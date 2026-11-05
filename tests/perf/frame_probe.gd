extends RefCounted
## Разбивка кадра для стресс-теста: где тратится время CPU (скрипты, физика, подготовка рендера) и GPU,
## сколько отрисовок и узлов. В конце — перепись узлов с включённым _process по скриптам и классам.

var _vp: RID
var _n: int = 0
var _sum: Dictionary = {}
const MONITORS: Dictionary = {
	"process_ms": Performance.TIME_PROCESS,
	"physics_ms": Performance.TIME_PHYSICS_PROCESS,
	"nav_ms": Performance.TIME_NAVIGATION_PROCESS,
}
const COUNTS: Dictionary = {
	"draw_calls": Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME,
	"objects": Performance.RENDER_TOTAL_OBJECTS_IN_FRAME,
	"primitives": Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME,
	"nodes": Performance.OBJECT_NODE_COUNT,
	"objects_alive": Performance.OBJECT_COUNT,
	"orphans": Performance.OBJECT_ORPHAN_NODE_COUNT,
}


## Отметки времени внутри кадра (мкс): первый и последний _process, начало и конец отрисовки.
var _t_first: int = 0
var _t_last: int = 0
var _t_pre: int = 0
var _t_post: int = 0


func _init(vp: Viewport) -> void:
	_vp = vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	var first: Node = Node.new()
	first.name = "ProbeFirst"
	first.process_priority = -1000000000
	first.process_mode = Node.PROCESS_MODE_ALWAYS
	first.set_script(_Mark)
	first.set("probe", self)
	first.set("which", 0)
	var last: Node = Node.new()
	last.name = "ProbeLast"
	last.process_priority = 1000000000
	last.process_mode = Node.PROCESS_MODE_ALWAYS
	last.set_script(_Mark)
	last.set("probe", self)
	last.set("which", 1)
	vp.get_tree().root.add_child.call_deferred(first)
	vp.get_tree().root.add_child.call_deferred(last)
	RenderingServer.frame_pre_draw.connect(func() -> void: _t_pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func() -> void: _t_post = Time.get_ticks_usec())


## Сегменты прошлого кадра (мс): узлы (_process всех узлов), хвост process (твины, отложенные вызовы,
## перерисовка Control) до начала отрисовки, отрисовка, остаток до следующего кадра (физика, ввод, аудио).
func mark(which: int) -> void:
	var now: int = Time.get_ticks_usec()
	if which == 0:
		if _t_first > 0 and _t_last > _t_first and _t_pre > _t_last and _t_post > _t_pre:
			_add("seg_nodes_ms", float(_t_last - _t_first) / 1000.0)
			_add("seg_flush_ms", float(_t_pre - _t_last) / 1000.0)
			_add("seg_draw_ms", float(_t_post - _t_pre) / 1000.0)
			_add("seg_rest_ms", float(now - _t_post) / 1000.0)
			_add("seg_frames", 1.0)
		_t_first = now
	else:
		_t_last = now


const _MARK_SRC: String = """extends Node
var probe: RefCounted
var which: int = 0
func _process(_d: float) -> void:
	probe.call("mark", which)
"""
static var _Mark: GDScript = _make_mark()


static func _make_mark() -> GDScript:
	var g: GDScript = GDScript.new()
	g.source_code = _MARK_SRC
	g.reload()
	return g


func sample() -> void:
	_n += 1
	for k: String in MONITORS:
		_add(k, Performance.get_monitor(MONITORS[k]) * 1000.0)
	for k: String in COUNTS:
		_add(k, Performance.get_monitor(COUNTS[k]))
	_add("render_cpu_ms", RenderingServer.viewport_get_measured_render_time_cpu(_vp) + RenderingServer.get_frame_setup_time_cpu())
	_add("render_gpu_ms", RenderingServer.viewport_get_measured_render_time_gpu(_vp))


func _add(k: String, v: float) -> void:
	_sum[k] = float(_sum.get(k, 0.0)) + v


func report() -> Dictionary:
	var out: Dictionary = {}
	var segs: float = maxf(float(_sum.get("seg_frames", 0.0)), 1.0)
	for k: String in _sum:
		if k == "seg_frames":
			continue
		out[k] = snappedf(float(_sum[k]) / (segs if k.begins_with("seg_") else float(maxi(_n, 1))), 0.01)
	return out


## Узлы с включённым _process / _physics_process: скрипт (или класс) → количество, по убыванию.
static func census(root: Node) -> Array:
	var counts: Dictionary = {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children(true):
			stack.append(c)
		if not (n.is_processing() or n.is_physics_processing() or n.is_processing_internal()):
			continue
		var s: Script = n.get_script() as Script
		var key: String = (s.resource_path.get_file() if s != null and not s.resource_path.is_empty() else "<" + n.get_class() + ">")
		if n.is_processing_internal() and not n.is_processing():
			key += " (internal)"
		counts[key] = int(counts.get(key, 0)) + 1
	var rows: Array = []
	for k: String in counts:
		rows.append([k, counts[k]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	return rows
