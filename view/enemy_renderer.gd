class_name EnemyRenderer
extends Node3D
## Отрисовка врагов через MultiMesh (по мешу на архетип) + полоски HP + анимация смерти.
## Модели с VAT (ArtKit.ENEMY_MODELS) проигрывают цикл ходьбы в шейдере: фаза идёт от пройденного пути
## (оглушённый враг замирает, замедленный перебирает ногами медленнее), летающие машут по времени.

const ENEMY_SHADER: Shader = preload("res://fx/shaders/enemy.gdshader")
const HP_SHADER: Shader = preload("res://fx/shaders/hpbar.gdshader")
const STATUS_SHADER: Shader = preload("res://fx/shaders/status_icon.gdshader")
const SHADOW_SHADER: Shader = preload("res://fx/shaders/blob_shadow.gdshader")
const STATUS_SIZE: float = 0.34
const MAX_STATUS: int = 3
const CAPACITY: int = 512
const FLY_HEIGHT: float = 1.05
const DEATH_TIME: float = 0.45
## Высокие процедурные меши: полоска HP выше (у моделей высота берётся из меша).
const BIG_MESHES: Array[String] = ["boss", "hive", "king", "colossus"]

var board: BoardView
var sim: GameSim
var _mm: Dictionary = {}
## Архетип → ключ MultiMesh: «vat:<модель>» (ArtKit.ENEMY_MODELS) или имя процедурного меша.
var _kind_of: Dictionary = {}
## Ключ → высота меша в долях размера (полоска HP и руны статусов над ним).
var _top: Dictionary = {}
var _hp_mm: MultiMesh
## Руны статусов над врагами и пятна теней под летающими.
var _status_mm: MultiMesh
var _shadow_mm: MultiMesh
var _flash: Dictionary = {}
var _dying: Array[Dictionary] = []
var _time: float = 0.0
var _colors: Dictionary = {}
## VAT-модели: ключ → путь за цикл (0 — цикл по времени), длительность цикла и клипа смерти.
var _stride: Dictionary = {}
var _loop_time: Dictionary = {}
var _death_time: Dictionary = {}
## Множитель размера модели (ArtKit.ENEMY_LOOK.scale), 1 — у прежних мешей.
var _scale: Dictionary = {}
## Состояние цикла у живых врагов: id → (фаза, прошлая позиция x, y).
var _anim: Dictionary = {}
var show_all_hp: bool = false
## Пятна теней и под наземными врагами — когда нет настоящих теней (Low, Compatibility):
## на светлом поле враг без тени словно висит в воздухе.
var _blob_ground: bool = false


## Пресет графики сменился: тени солнца включены или выключены.
func apply_quality() -> void:
	_blob_ground = not bool(Graphics.preset()["shadows"]) or Graphics.is_compatibility()


func setup(b: BoardView, target: GameSim) -> void:
	board = b
	sim = target
	apply_quality()
	for id: String in sim.data.archetypes.keys():
		_colors[id] = Color.html(String(sim.data.archetypes[id]["color"]))
	var meshes: Dictionary = {"blob": MeshFactory.enemy_mesh("blob")}
	_top["blob"] = 1.15
	var mats: Dictionary = {}
	for id2: String in sim.data.archetypes.keys():
		var vat: ArrayMesh = ArtKit.enemy_vat(id2)
		if vat != null:
			var vk: String = "vat:" + vat.resource_name
			_kind_of[id2] = vk
			if not meshes.has(vk):
				meshes[vk] = vat
				mats[vk] = ArtKit.enemy_vat_material(vat)
				_top[vk] = float(vat.get_meta("height", 1.15))
				var look: Dictionary = ArtKit.enemy_look(vat.resource_name)
				_stride[vk] = 0.0 if look.has("flap") else ArtKit.enemy_stride(vat) * ArtKit.ENEMY_WIDTH
				_scale[vk] = float(look["scale"])
				_loop_time[vk] = maxf(float(vat.get_meta("loop_time", 1.0)) / float(look.get("flap", 1.0)), 0.05)
				_death_time[vk] = float(vat.get_meta("death_time", 0.0)) if int(vat.get_meta("death_frames", 0)) > 0 else 0.0
			continue
		# Архетип без VAT-модели (новый, ещё не запечённый) — процедурный меш из data.
		var k: String = String(sim.data.archetypes[id2]["mesh"])
		_kind_of[id2] = k
		if meshes.has(k):
			continue
		meshes[k] = MeshFactory.enemy_mesh(k)
		_top[k] = 1.45 if BIG_MESHES.has(k) else 1.15
	for kind: String in meshes:
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = meshes[kind]
		mm.instance_count = CAPACITY
		mm.visible_instance_count = 0
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var m: ShaderMaterial = mats.get(kind, null)
		if m == null:
			m = ShaderMaterial.new()
			m.shader = ENEMY_SHADER
		mmi.material_override = m
		add_child(mmi)
		_mm[kind] = mm
	_hp_mm = MultiMesh.new()
	_hp_mm.transform_format = MultiMesh.TRANSFORM_3D
	_hp_mm.use_custom_data = true
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.62, 0.085)
	_hp_mm.mesh = quad
	_hp_mm.instance_count = CAPACITY
	_hp_mm.visible_instance_count = 0
	var hp_mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	hp_mmi.multimesh = _hp_mm
	var hm: ShaderMaterial = ShaderMaterial.new()
	hm.shader = HP_SHADER
	hm.render_priority = 10
	hp_mmi.material_override = hm
	hp_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hp_mmi)
	var sq: QuadMesh = QuadMesh.new()
	sq.size = Vector2(STATUS_SIZE, STATUS_SIZE)
	_status_mm = _overlay_mm(sq, STATUS_SHADER, CAPACITY * MAX_STATUS, 11)
	var pl: PlaneMesh = PlaneMesh.new()
	pl.size = Vector2(1, 1)
	_shadow_mm = _overlay_mm(pl, SHADOW_SHADER, CAPACITY, 0)


func _overlay_mm(mesh: Mesh, shader: Shader, count: int, priority: int) -> MultiMesh:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = shader
	m.render_priority = priority
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


func on_event(e: Dictionary) -> void:
	match String(e["type"]):
		"hit":
			_flash[int(e["enemy_id"])] = _time
		"enemy_died":
			var a: Dictionary = sim.data.archetypes.get(String(e["archetype"]), {})
			var eid: int = int(e.get("enemy_id", -1))
			var dead: EnemyState = sim.enemy_by_id.get(eid) as EnemyState
			var kind: String = String(_kind_of.get(String(e["archetype"]), "blob"))
			# Клип смерти идёт целиком (не дольше 1.6 с, у боссов — 2.4 с); без клипа — короткое растворение.
			var clip: float = float(_death_time.get(kind, 0.0))
			var dur: float = clampf(clip, 0.6, 2.4 if bool(a.get("boss", false)) else 1.6) if clip > 0.0 else DEATH_TIME
			var st: Vector3 = _anim.get(eid, Vector3.ZERO)
			_anim.erase(eid)
			_dying.append({"pos": e["pos"], "kind": kind, "color": Color.html(String(a.get("color", "#ffffff"))),
				"size": float(a.get("size", 0.3)), "flying": bool(e["flying"]), "t": _time, "heading": dead.heading if dead != null else 0.0,
				"dur": dur, "clip": clip > 0.0, "phase": st.x})


func render(alpha: float, delta: float) -> void:
	_time += delta
	var counts: Dictionary = {}
	for kind: String in _mm.keys():
		counts[kind] = 0
	var hp_count: int = 0
	var status_count: int = 0
	var shadow_count: int = 0
	var now: float = sim.wave_time
	for e: EnemyState in sim.enemies:
		if not e.alive:
			continue
		var kind: String = String(_kind_of.get(e.archetype, "blob"))
		var mm: MultiMesh = _mm.get(kind, _mm["blob"])
		var i: int = int(counts.get(kind, 0))
		if i >= CAPACITY:
			continue
		counts[kind] = i + 1
		var p: Vector2 = e.prev_pos.lerp(e.pos, alpha)
		var y: float = FLY_HEIGHT + sin(_time * 3.0 + float(e.id)) * 0.06 if e.flying else 0.0
		var sz: float = e.size * 2.0 * float(_scale.get(kind, 1.0))
		var vat: bool = _loop_time.has(kind)
		var bob: float = 1.0 + (sin(_time * 10.0 + float(e.id) * 1.7) * 0.06 if not e.flying and not vat else 0.0)
		var phase: float = 0.0
		if vat:
			phase = _advance(e, kind, p, sz, delta)
		var basis: Basis = Basis(Vector3.UP, -e.heading).scaled(Vector3(sz, sz * bob, sz))
		mm.set_instance_transform(i, Transform3D(basis, board.w(p, y)))
		var col: Color = _colors.get(e.archetype, Color.WHITE)
		if e.golden:
			col = UiTokens.GOLD
		elif e.elite:
			col = col.lerp(Color(1.0, 0.92, 0.7), 0.35)
		# Альфа цвета = «призрачность»: невидимый под Покровом враг рисуется полупрозрачным.
		col.a = 0.35 if not e.visible else 1.0
		mm.set_instance_color(i, col)
		var flash: float = clampf(1.0 - (_time - float(_flash.get(e.id, -10.0))) / 0.12, 0.0, 1.0)
		var slow: float = 1.0 if e.current_slow(now) > 0.0 else 0.0
		var poison: float = 2.0 if not e.poison.is_empty() else 0.0
		mm.set_instance_custom_data(i, Color(flash, 0.0, slow + poison, phase))
		var hurt: bool = e.hp < e.max_hp - 0.01
		var top: float = y + sz * float(_top.get(kind, 1.15)) + 0.15
		if (hurt or show_all_hp or e.boss or e.shield > 0.0) and hp_count < CAPACITY and not e.immortal:
			_hp_mm.set_instance_transform(hp_count, Transform3D(Basis.IDENTITY, board.w(p, top)))
			_hp_mm.set_instance_custom_data(hp_count, Color(clampf(e.hp / e.max_hp, 0.0, 1.0), 1.0 if e.visible else 0.4, 2.4 if e.boss else 1.0, 1.0 if e.boss else 0.0))
			hp_count += 1
			# Щит — отдельная голубая полоска над HP (style 2 в шейдере).
			if e.shield > 0.0 and hp_count < CAPACITY:
				_hp_mm.set_instance_transform(hp_count, Transform3D(Basis.IDENTITY, board.w(p, top + 0.11)))
				_hp_mm.set_instance_custom_data(hp_count, Color(clampf(e.shield / maxf(e.max_shield, 0.001), 0.0, 1.0), 1.0, 2.4 if e.boss else 1.0, 2.0))
				hp_count += 1
		status_count = _statuses(e, board.w(p, top + 0.32), now, status_count)
		if (e.flying or _blob_ground) and shadow_count < CAPACITY:
			var ss: float = sz * (1.3 if e.flying else 1.05)
			_shadow_mm.set_instance_transform(shadow_count, Transform3D(Basis.IDENTITY.scaled(Vector3(ss, 1.0, ss)), board.w(p, 0.04)))
			shadow_count += 1
	_status_mm.visible_instance_count = status_count
	_shadow_mm.visible_instance_count = shadow_count
	# Умирающие: dissolve на месте.
	var keep: Array[Dictionary] = []
	for d: Dictionary in _dying:
		var t: float = (_time - float(d["t"])) / float(d["dur"])
		if t >= 1.0:
			continue
		keep.append(d)
		var kind2: String = d["kind"]
		var mm2: MultiMesh = _mm.get(kind2, _mm["blob"])
		var j: int = int(counts.get(kind2, 0))
		if j >= CAPACITY:
			continue
		counts[kind2] = j + 1
		var clip: bool = bool(d["clip"])
		var sz2: float = float(d["size"]) * 2.0 * float(_scale.get(kind2, 1.0)) * (1.0 if clip else 1.0 + t * 0.25)
		var y2: float = (FLY_HEIGHT * (1.0 - smoothstep(0.0, 0.7, t)) if clip else FLY_HEIGHT - t * 0.8) if d["flying"] else 0.0
		mm2.set_instance_transform(j, Transform3D(Basis(Vector3.UP, -float(d["heading"])).scaled(Vector3(sz2, sz2, sz2)), board.w(d["pos"], y2)))
		mm2.set_instance_color(j, d["color"])
		# С клипом: падение за первые 75 %, растворение — в конце; без клипа — растворение сразу.
		var fade: float = clampf((t - 0.6) / 0.4, 0.0, 1.0) if clip else clampf(t * 1.1, 0.0, 1.0)
		var ph: float = 1.0 + clampf(t / 0.75, 0.0, 1.0) if clip else float(d["phase"])
		mm2.set_instance_custom_data(j, Color(0.4 * (1.0 - t) if not clip else 0.0, fade, 0.0, ph))
	_dying = keep
	for kind: String in _mm.keys():
		(_mm[kind] as MultiMesh).visible_instance_count = int(counts[kind])
	_hp_mm.visible_instance_count = hp_count
	if _flash.size() > 2048:
		_flash.clear()
	# Ушедшие с поля (утечка) не умирают — их циклы чистятся пачкой.
	if _anim.size() > 600:
		var alive: Dictionary = {}
		for e2: EnemyState in sim.enemies:
			if e2.alive and _anim.has(e2.id):
				alive[e2.id] = _anim[e2.id]
		_anim = alive


## Фаза цикла VAT-модели: от пройденного пути (шаг за цикл — stride ширин модели), у летающих — от времени.
func _advance(e: EnemyState, kind: String, p: Vector2, sz: float, delta: float) -> float:
	var st: Vector3 = _anim.get(e.id, Vector3(fmod(float(e.id) * 0.618, 1.0), p.x, p.y))
	var stride: float = float(_stride[kind]) * sz
	var step: float = p.distance_to(Vector2(st.y, st.z))
	var d: float = step / stride if stride > 0.0 else delta / float(_loop_time[kind])
	# Скачок позиции (перемотка повтора, телепорт) не прокручивает цикл.
	if step > 1.5:
		d = 0.0
	var ph: float = fposmod(st.x + d, 1.0)
	_anim[e.id] = Vector3(ph, p.x, p.y)
	return ph


## Руны статусов в ряд над полоской HP: яд, замедление, оглушение, снижение брони, метка/уязвимость.
func _statuses(e: EnemyState, at: Vector3, now: float, count: int) -> int:
	var kinds: Array[int] = []
	if not e.poison.is_empty() or now < e.blight_until:
		kinds.append(0)
	if e.current_slow(now) > 0.0:
		kinds.append(1)
	if e.is_stunned(now):
		kinds.append(2)
	if now < e.shred_until and e.shred > 0.0:
		kinds.append(3)
	if now < e.vuln_until or now < e.mark_until:
		kinds.append(4)
	var n: int = mini(kinds.size(), MAX_STATUS)
	for i: int in n:
		if count >= _status_mm.instance_count:
			break
		var x: float = (float(i) - float(n - 1) * 0.5) * STATUS_SIZE * 1.1
		_status_mm.set_instance_transform(count, Transform3D(Basis.IDENTITY, at + Vector3(x, 0.0, 0.0)))
		_status_mm.set_instance_custom_data(count, Color(float(kinds[i]), 0.0, 0.0, 0.0))
		count += 1
	return count


func clear() -> void:
	_dying.clear()
	_flash.clear()
	_anim.clear()
	for kind: String in _mm.keys():
		(_mm[kind] as MultiMesh).visible_instance_count = 0
	_hp_mm.visible_instance_count = 0
	_status_mm.visible_instance_count = 0
	_shadow_mm.visible_instance_count = 0
