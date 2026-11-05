extends SceneTree
## Запекание врагов в VAT (vertex animation textures): готовые анимированные модели (Sketchfab CC BY 4.0,
## OpenGameArt и Universal Animation Library CC0 — авторы и лицензии в assets/LICENSES.md и CREDITS.md) превращаются
## в статичный меш + текстуры с позами по кадрам. Так до 300 врагов по-прежнему рисуются MultiMesh'ем,
## а шейдер fx/shaders/enemy_vat.gdshader проигрывает цикл ходьбы (полёта) и клип смерти.
## Источники лежат в art_src/models/ (папка с .gdignore и в .gitignore), ссылки на них — в SOURCES.
## Результат на модель (id — имя файла по соглашению char_enemy_<существо>_01):
##   assets/characters/enemies/<id>.res — ArrayMesh, все материалы слиты в один атлас:
##     VERTEX/NORMAL/TANGENT — поза первого кадра цикла (вперёд +X, основание в y = 0, ширина ≤ TARGET_WIDTH);
##     UV — атлас, UV2 — адрес вершины в VAT (столбец, строка внутри кадра);
##     custom_aabb — охват всех кадров (иначе MultiMesh отсекал бы взмахи крыльев);
##     meta: height, vat_pos (RGBAH: xyz), vat_nrm (RGBAH: окт. нормаль + окт. касательная), rows,
##           loop_frames, loop_time, death_frames, death_time, source.
##   assets/textures/characters/<id>_{albedo,normal,orm,emission}.jpg — атлас (ORM: R — AO, G — roughness, B — metallic).
## Запуск (с окном: в --headless скин не регистрируется у скелета и поза не запекается):
##   godot --path . -s res://tools/bake_enemy_vat.gd [-- --only=<id>]

const SRC: String = "res://art_src/models"
const OUT_MESH: String = "res://assets/characters/enemies"
const OUT_TEX: String = "res://assets/textures/characters"

## Ширина модели по большей горизонтальной оси и предел высоты (как у прежних мешей врагов).
const TARGET_WIDTH: float = 1.7
const MAX_HEIGHT: float = 1.9
## Ширина VAT: вершины дальше переносятся на следующую строку того же кадра.
const VAT_WIDTH: int = 2048
const ATLAS_PAD: int = 4

## UV текущей модели перевёрнуты по V (флаг flip_v в конфиге модели).
var _flip_v: bool = false
## Ретаргет (модель без своих клипов): скелет-источник, соответствие костей, поправки поз покоя.
var _rt: Dictionary = {}

## Откуда скачаны исходники.
const SOURCES: Dictionary = {
	"pachy": "https://sketchfab.com/3d-models/6eea5cee4afa4730bf75c6329a43e56d (GLB, текстуры 1K)",
	"raptor": "https://sketchfab.com/3d-models/8f1744af7b0847a2aabe3df90be802f0 (GLB, текстуры 1K)",
	"stego": "https://sketchfab.com/3d-models/ec254ea1554941fe8a131f62db0faf3d (GLB, текстуры 1K)",
	"bug": "https://sketchfab.com/3d-models/eca3cc1f85a64f70ba86cea09963d42c (GLB, текстуры 1K)",
	"drone": "https://sketchfab.com/3d-models/b214751af77b4609be858399923eea41 (GLB, текстуры 1K)",
	"pteran": "https://sketchfab.com/3d-models/6fe9ab8e42554c83bfc4ae1571007c0d (GLB, текстуры 1K)",
	"spider": "https://sketchfab.com/3d-models/6392e4cfb64d407182fdad2cea9e0abe (GLB, текстуры 1K)",
	"bat": "https://opengameart.org/content/vampire-bat-animated (bat_v5.blend → по GLB на клип: tools/blender_export_bat.py)",
	"queen": "https://sketchfab.com/3d-models/943c5865b9f94ce48ccea253382c0d77 (GLB, текстуры 1K)",
	"stonewisp": "https://sketchfab.com/3d-models/ca27ab932b21407ba30376340f4c4444 (GLB, текстуры 1K)",
	"troll": "https://sketchfab.com/3d-models/59e679e0da5c4906935b8841aefe6dc0 (GLB, текстуры 1K)",
	"hound": "https://sketchfab.com/3d-models/bd8290074df34eb99f174edb176fcc46 (GLB, текстуры 1K)",
	"knight": "https://sketchfab.com/3d-models/b7bba7eddb13470b88eb8b24531cb6b3 (GLB, текстуры 2K)",
	"ual": "https://quaternius.itch.io/universal-animation-library (Standard, CC0: Unreal-Godot/UAL1_Standard.glb, без root motion)",
	"shadowkin": "https://sketchfab.com/3d-models/7aab96637055455297d158584b1602cd (GLB, текстуры 1K)",
}

## Модели. src — файл в art_src/models; loop/death — клипы (подстрока имени; death пустой — смерть только
## растворением); anims — отдельные FBX с клипами (Unreal/Unity-паки); tris — бюджет треугольников;
## atlas — сторона атласа; yaw — доворот в градусах, если модель смотрит не по +Z; scale — множитель размера;
## frames — кадров цикла (длинным клипам с несколькими шагами нужно больше LOOP_FRAMES);
## skip — материалы, чьи меши не берутся (глаза Bug и Pteran при скиннинге улетают от тела — ошибка привязки в исходнике);
## retarget — модель без своих клипов (Shadowkin: только T-поза, рыцарь — только Idle) берёт ходьбу и смерть
##   у другого скелета (Universal Animation Library, CC0): src/anims — источник и его клипы (без anims — клипы
##   самого src), map — кость модели → кость источника, aim — кость → её дочерняя (по направлению на неё
##   выравниваются позы покоя). Если скелеты смотрят в разные стороны, источник доворачивается сам (_align_source);
## grade — цветокоррекция альбедо по материалам: sat — насыщенность, gain — яркость, tint — оттенок;
## textures — карты для моделей без встроенных текстур (по имени материала): albedo, normal, emission.
## Карту эмиссии задавайте только там, где она светится в игре: у паков Unreal бывают светлые маски
## трещин под тёмный материал — у нас они горели бы прожилками по всей модели.
const MODELS: Dictionary = {
	"char_enemy_pachy_01": {"src": "enemy_pachy/pachy.glb", "loop": "Walk", "death": "KnockedOut", "tris": 2200, "atlas": 1024, "title": "PBR Pachycephalasaurus (Animated) by Ferocious Industries"},
	"char_enemy_raptor_01": {"src": "enemy_raptor/raptor.glb", "loop": "Sprint", "death": "Death_01", "tris": 2200, "atlas": 1024, "title": "PBR Velociraptor (Animated) by Ferocious Industries"},
	"char_enemy_stego_01": {"src": "enemy_stego/stego.glb", "loop": "Walk", "death": "Death", "tris": 2200, "atlas": 1024, "title": "PBR Stegasaurus (Animated) by Ferocious Industries"},
	"char_enemy_bug_01": {"src": "enemy_bug/bug.glb", "loop": "Walk Cycle Loop", "death": "", "tris": 2200, "atlas": 1024, "frames": 40, "skip": ["Eyes"], "title": "Blight Bug by HighPolyDensity"},
	"char_enemy_drone_01": {"src": "enemy_drone/drone.glb", "loop": "Walk", "death": "", "tris": 1400, "atlas": 1024, "frames": 40, "title": "Vampirical Blight Drone by HighPolyDensity"},
	"char_enemy_pteran_01": {"src": "enemy_pteran/pteran.glb", "loop": "Walk", "death": "", "tris": 2200, "atlas": 1024, "skip": ["Eyes"], "title": "Pteran - Humanoid Beetle by HighPolyDensity"},
	"char_enemy_spider_01": {"src": "enemy_spider/spider.glb", "loop": "Spider walking fast", "death": "", "tris": 1400, "atlas": 1024, "yaw": 180.0, "title": "Wolf Spider (Rigged) - (Rabidosa rabida) by Dreaming In Alternation 27"},
	"char_enemy_bat_01": {"src": "enemy_bat/bat_Bat_Flying.glb", "loop": "Animation", "death": "Bat_Die", "tris": 2000, "atlas": 1024, "title": "Vampire Bat (Animated) by rubberduck",
		"anims": {"Bat_Die": "enemy_bat/bat_Bat_Die.glb"},
		"textures": {"bat_parts": {"albedo": "enemy_bat/src/bat_parts.jpg"}}},
	"char_enemy_shadowkin_01": {"src": "enemy_shadowkin/shadowkin.glb", "loop": "Walk_Loop", "death": "Death01", "tris": 2200, "atlas": 1024,
		"title": "PBR Shadowkin Mage (Rigged) by Ferocious Industries",
		# Своих клипов нет: ходьба и смерть Universal Animation Library (CC0) переносятся на риг Character Creator.
		"retarget": {"src": "anim_ual/UAL1_Standard.glb", "hip": "CC_Base_Hip_03", "hang": ["Cloak"],
			"map": {"CC_Base_Hip_03": "pelvis", "CC_Base_Pelvis_04": "pelvis", "CC_Base_Waist_035": "spine_01", "CC_Base_Spine01_036": "spine_02",
				"CC_Base_Spine02_037": "spine_03", "CC_Base_Head_040": "Head",
				"CC_Base_L_Clavicle_051": "clavicle_l", "CC_Base_L_Upperarm_052": "upperarm_l", "CC_Base_L_Forearm_053": "lowerarm_l", "CC_Base_L_Hand_057": "hand_l",
				"CC_Base_R_Clavicle_079": "clavicle_r", "CC_Base_R_Upperarm_080": "upperarm_r", "CC_Base_R_Forearm_081": "lowerarm_r", "CC_Base_R_Hand_085": "hand_r",
				"CC_Base_L_Thigh_05": "thigh_l", "CC_Base_L_Calf_06": "calf_l", "CC_Base_L_Foot_07": "foot_l",
				"CC_Base_R_Thigh_020": "thigh_r", "CC_Base_R_Calf_021": "calf_r", "CC_Base_R_Foot_023": "foot_r"},
			"aim": {"CC_Base_Waist_035": "CC_Base_Spine01_036", "CC_Base_Spine01_036": "CC_Base_Spine02_037", "CC_Base_Spine02_037": "CC_Base_Head_040",
				"CC_Base_L_Clavicle_051": "CC_Base_L_Upperarm_052", "CC_Base_L_Upperarm_052": "CC_Base_L_Forearm_053", "CC_Base_L_Forearm_053": "CC_Base_L_Hand_057",
				"CC_Base_R_Clavicle_079": "CC_Base_R_Upperarm_080", "CC_Base_R_Upperarm_080": "CC_Base_R_Forearm_081", "CC_Base_R_Forearm_081": "CC_Base_R_Hand_085",
				"CC_Base_L_Thigh_05": "CC_Base_L_Calf_06", "CC_Base_L_Calf_06": "CC_Base_L_Foot_07",
				"CC_Base_R_Thigh_020": "CC_Base_R_Calf_021", "CC_Base_R_Calf_021": "CC_Base_R_Foot_023"}}},
	"char_boss_queen_01": {"src": "boss_queen/queen.glb", "loop": "Walk Cycle", "death": "", "tris": 6000, "atlas": 2048, "frames": 40, "title": "Vampirical Blight Queen by HighPolyDensity"},
	"char_boss_stonewisp_01": {"src": "boss_stonewisp/stonewisp.glb", "loop": "Swim", "death": "Die", "tris": 6000, "atlas": 2048, "frames": 64, "title": "Stonewisp - Mutant Stingray by HighPolyDensity"},
	"char_boss_troll_01": {"src": "boss_troll/troll.glb", "loop": "Walking", "death": "Death", "tris": 6000, "atlas": 2048, "title": "Troll by Timsblends"},
	# Каменный Страж — лавовый пёс из вулканического камня; клипа смерти нет — растворение с осколками.
	"char_boss_hound_01": {"src": "boss_hound/hound.glb", "loop": "Walk", "death": "", "tris": 6000, "atlas": 1024,
		"title": "Infernal Magma Hound - Free Lava Creature Asset by Yury Misiyuk"},
	# Обсидиановый Король — рыцарь в латах; свой клип только Idle, ходьба и смерть — из Universal Animation
	# Library (скелет UAL смотрит в +Z, рыцарь — в -Z: источник доворачивается сам). Копьё висит на кости у корня
	# (за кистью его вёл IK) — без него. Пластины доспеха (набедренники, наплечники, щитки стоп) идут за конечностью.
	"char_boss_knight_01": {"src": "boss_knight/knight.glb", "loop": "Walk_Loop", "death": "Death01", "tris": 6000, "atlas": 2048, "yaw": 180.0,
		"title": "Armored Guard Knight Rig by DM-913", "skip": ["Spear"],
		"retarget": {"src": "anim_ual/UAL1_Standard.glb", "hip": "Pelvis_76",
			"map": {"Pelvis_76": "pelvis", "Spine_55": "spine_02", "Torso_54": "spine_03", "Neck_1": "neck_01", "Head_0": "Head",
				"Shoulder.L_26": "clavicle_l", "Upperarm.L_25": "upperarm_l", "Bone_24": "lowerarm_l", "Forearm.L_23": "lowerarm_l", "Hand.L_22": "hand_l",
				"Shoulder.R_51": "clavicle_r", "Upperarm.R_50": "upperarm_r", "Bone.001_49": "lowerarm_r", "Forearm.R_48": "lowerarm_r", "Hand.R_47": "hand_r",
				"Thigh.L_60": "thigh_l", "Bone.002_59": "calf_l", "LowerLeg.L_58": "calf_l", "Foot.L_56": "foot_l",
				"Thigh.R_66": "thigh_r", "Bone.003_65": "calf_r", "LowerLeg.R_64": "calf_r", "Foot.R_62": "foot_r",
				"Thigh Armor.L_68": "thigh_l", "Thigh Armor.R_69": "thigh_r", "Shoulder Pad.L_52": "upperarm_l", "Shoulder Pad.R_53": "upperarm_r",
				"Foot Plate.L_57": "foot_l", "Foot Plate.R_63": "foot_r"},
			"aim": {"Spine_55": "Torso_54", "Torso_54": "Neck_1", "Neck_1": "Head_0",
				"Shoulder.L_26": "Upperarm.L_25", "Upperarm.L_25": "Bone_24", "Bone_24": "Hand.L_22", "Forearm.L_23": "Hand.L_22",
				"Shoulder.R_51": "Upperarm.R_50", "Upperarm.R_50": "Bone.001_49", "Bone.001_49": "Hand.R_47", "Forearm.R_48": "Hand.R_47",
				"Thigh.L_60": "Bone.002_59", "Bone.002_59": "Foot.L_56", "LowerLeg.L_58": "Foot.L_56",
				"Thigh.R_66": "Bone.003_65", "Bone.003_65": "Foot.R_62", "LowerLeg.R_64": "Foot.R_62"}},
		# Золочёные латы → тёмная бронза: оттенок золота сохраняется, яркость и насыщенность ниже (ART_DIRECTION.md: Обсидиановый Король).
		"grade": {"Guard": {"sat": 0.75, "gain": 0.62, "tint": "4a3a40"}}},
}

## Кристаллы (Раскольник и его Осколки) — процедурные, «из того же камня», что стены: шестигранные
## призмы с остриём на обсидиановом материале; прожилки светятся цветом архетипа. Анимация — кольцо
## спутников вокруг ядра (кластер) или прыжки (осколок); смерть — разлёт спутников и раскол.
const CRYSTALS: Dictionary = {
	"char_enemy_crystal_cluster_01": {"crystal": "cluster", "loop_time": 1.6, "frames": 24, "death_frames": 16,
		"title": "Procedural crystal cluster (GemTD, на материале ambientCG Rock035)"},
	"char_enemy_crystal_shard_01": {"crystal": "shard", "loop_time": 0.8, "frames": 16, "death_frames": 12,
		"title": "Procedural crystal shard (GemTD, на материале ambientCG Rock035)"},
}

## Кадров на цикл и на смерть (не больше, чем даёт клип при 30 кадрах/с).
const LOOP_FRAMES: int = 24
const DEATH_FRAMES: int = 20


func _initialize() -> void:
	var only: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_MESH))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_TEX))
	var failed: int = 0
	var all: Dictionary = MODELS.duplicate()
	all.merge(CRYSTALS)
	for id: String in all:
		if not only.is_empty() and id != only:
			continue
		var res: Dictionary = _bake_crystal(id, all[id]) if all[id].has("crystal") else await _bake(id, all[id])
		if not bool(res.get("ok", false)):
			failed += 1
			printerr("✗ %s: %s" % [id, res.get("reason", "?")])
		else:
			print("✓ %-24s %6d → %5d треуг., %5d верш., VAT %dx%d, высота %.2f, цикл «%s» %d кадр. %.2fс, шаг %.2f, смерть «%s» %d кадр."
				% [id, res["src_tris"], res["tris"], res["verts"], res["vat_w"], res["vat_h"], res["height"], res["loop"], res["loop_frames"], res["loop_time"], float(res.get("stride", 0.0)), res["death"], res["death_frames"]])
	quit(1 if failed > 0 else 0)


func _bake(id: String, cfg: Dictionary) -> Dictionary:
	_flip_v = bool(cfg.get("flip_v", false))
	var scene: Node3D = _load_scene(SRC.path_join(String(cfg["src"])))
	if scene == null:
		return {"reason": "не открылся " + String(cfg["src"])}
	root.add_child(scene)
	await process_frame
	await process_frame
	var ap: AnimationPlayer = _player(scene, cfg)
	var src_scene: Node3D = null
	if cfg.has("retarget"):
		var rcfg: Dictionary = cfg["retarget"]
		src_scene = _load_scene(SRC.path_join(String(rcfg["src"])))
		if src_scene == null:
			scene.queue_free()
			return {"reason": "не открылся источник ретаргета " + String(rcfg["src"])}
		root.add_child(src_scene)
		await process_frame
		await process_frame
		# Собственная поза модели (Shadowkin: ActionPose) — основа для костей вне ретаргета: плащ висит, а не торчит.
		var base_pose: Dictionary = {}
		if ap != null and not ap.get_animation_list().is_empty():
			await _pose(scene, ap, ap.get_animation_list()[0], 0.0)
			var tsk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
			for b: int in tsk.get_bone_count():
				base_pose[b] = tsk.get_bone_pose(b)
			ap.stop()
		ap = _player(src_scene, rcfg)
		_align_source(src_scene, scene, rcfg)
		_rt = _retarget_setup(src_scene, scene, rcfg)
		_rt["base"] = base_pose
	if ap == null:
		_release(scene, src_scene)
		return {"reason": "нет анимаций"}
	var loop_name: String = _find_anim(ap, String(cfg["loop"]))
	var death_name: String = _find_anim(ap, String(cfg.get("death", ""))) if not String(cfg.get("death", "")).is_empty() else ""
	if loop_name.is_empty():
		_release(scene, src_scene)
		return {"reason": "нет клипа " + String(cfg["loop"]) + " среди " + str(ap.get_animation_list())}
	var mis: Array[MeshInstance3D] = []
	var skip: Array = cfg.get("skip", [])
	for n: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi0: MeshInstance3D = n
		if mi0.mesh == null or not mi0.visible:
			continue
		var mname: String = mi0.get_active_material(0).resource_name if mi0.get_active_material(0) != null else ""
		if skip.any(func(w: String) -> bool: return mname.contains(w)):
			continue
		mis.append(mi0)
	# Материалы → ячейки атласа.
	var mats: Array[Dictionary] = _collect_materials(mis, cfg)
	# Кадр 0 цикла: топология и UV. Скин регистрируется у скелета только после кадра в дереве.
	await _pose(scene, ap, loop_name, 0.0)
	await process_frame
	var base: Dictionary = _posed(scene, mis, mats)
	var src_tris: int = (base["index"] as PackedInt32Array).size() / 3
	var atlas: Dictionary = _build_atlas(id, mats, base, int(cfg.get("atlas", 1024)))
	# Ориентация и нормировка по кадру 0.
	var rot: Basis = Basis(Vector3.UP, PI * 0.5 + deg_to_rad(float(cfg.get("yaw", 0.0))))
	var ab: AABB = _aabb(base["verts"], rot)
	var width: float = maxf(ab.size.x, ab.size.z)
	var k: float = TARGET_WIDTH / maxf(width, 0.0001)
	if ab.size.y * k > MAX_HEIGHT:
		k = MAX_HEIGHT / ab.size.y
	k *= float(cfg.get("scale", 1.0))
	var center: Vector3 = Vector3(ab.position.x + ab.size.x * 0.5, ab.position.y, ab.position.z + ab.size.z * 0.5)
	var norm: Transform3D = Transform3D(rot.scaled(Vector3(k, k, k)), Vector3.ZERO)
	norm.origin = -center * k
	# Упрощение по позе кадра 0 (вершины сохраняются из исходных — их позы есть во всех кадрах).
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _xf_points(base["verts"], norm)
	arrays[Mesh.ARRAY_NORMAL] = _xf_dirs(base["normals"], norm.basis)
	arrays[Mesh.ARRAY_TEX_UV] = atlas["uv"]
	arrays[Mesh.ARRAY_INDEX] = base["index"]
	var idx: PackedInt32Array = _simplified_indices(arrays, int(cfg.get("tris", 2000)))
	# Уплотнение: только вершины, на которые ссылается упрощённый индекс.
	var remap: Dictionary = {}
	var keep: PackedInt32Array = PackedInt32Array()
	var new_idx: PackedInt32Array = PackedInt32Array()
	new_idx.resize(idx.size())
	for i: int in idx.size():
		var v: int = idx[i]
		if not remap.has(v):
			remap[v] = keep.size()
			keep.append(v)
		new_idx[i] = int(remap[v])
	var uv_atlas: PackedVector2Array = _pick2(atlas["uv"], keep)
	# Кадры: цикл (без последнего — он совпадает с первым) и смерть (с последним).
	var frames: Array[Dictionary] = []
	var loop_len: float = ap.get_animation(loop_name).length
	var loop_n: int = int(cfg["frames"]) if cfg.has("frames") else clampi(int(round(loop_len * 30.0)), 8, LOOP_FRAMES)
	var drift: Vector3 = await _loop_drift(scene, ap, loop_name, mis, mats, norm)
	for f: int in loop_n:
		var t: float = loop_len * float(f) / float(loop_n)
		await _pose(scene, ap, loop_name, t)
		frames.append(_frame(scene, mis, mats, norm, keep, new_idx, uv_atlas, drift * (float(f) / float(loop_n))))
	var death_n: int = 0
	var death_len: float = 0.0
	if not death_name.is_empty():
		death_len = ap.get_animation(death_name).length
		death_n = clampi(int(round(death_len * 30.0)), 6, DEATH_FRAMES)
		for f2: int in death_n:
			await _pose(scene, ap, death_name, death_len * float(f2) / float(death_n - 1))
			frames.append(_frame(scene, mis, mats, norm, keep, new_idx, uv_atlas, Vector3.ZERO))
	_release(scene, src_scene)
	var stride: float = _measure_stride(frames, loop_n) if not bool(cfg.get("flap", false)) else 0.0
	var res: Dictionary = _write_model(id, cfg, frames, new_idx, uv_atlas, loop_n, loop_len, death_n, death_len, bool(atlas["emission"]), stride)
	res["src_tris"] = src_tris
	res["loop"] = loop_name
	res["death"] = death_name if not death_name.is_empty() else "—"
	res["stride"] = stride
	return res


## Сцены модели и источника ретаргета — из дерева, состояние ретаргета — сброшено. На любом выходе из _bake:
## иначе следующая модель в общем прогоне вызвала бы _retarget() на уже освобождённых скелетах.
func _release(scene: Node3D, src_scene: Node3D) -> void:
	scene.queue_free()
	if src_scene != null:
		src_scene.queue_free()
	_rt = {}


## Путь за цикл ходьбы в ширинах модели (ArtKit: шаг ног совпадает с ходом по полю). Клип идёт на месте,
## поэтому опорная нога скользит назад со скоростью хода. Между соседними кадрами цикла берётся медиана
## смещения по X (модель смотрит в +X) вершин у земли в этом кадре — нижний 1 % высоты от минимума кадра.
## Для двуногих замер устойчив (Заговорённый, рыцарь: 0.8–0.9 при любом пороге); у старых моделей шаг подобран
## вручную в ArtKit.ENEMY_LOOK и важнее меты.
func _measure_stride(frames: Array[Dictionary], loop_n: int) -> float:
	var lo: float = INF
	var hi: float = -INF
	for f: int in loop_n:
		for p: Vector3 in frames[f]["pos"]:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
	var eps: float = (hi - lo) * 0.01
	var total: float = 0.0
	for f2: int in loop_n:
		var a: PackedVector3Array = frames[f2]["pos"]
		var b: PackedVector3Array = frames[(f2 + 1) % loop_n]["pos"]
		var floor_y: float = INF
		for p2: Vector3 in a:
			floor_y = minf(floor_y, p2.y)
		var dx: PackedFloat32Array = PackedFloat32Array()
		for i: int in a.size():
			if a[i].y - floor_y < eps:
				dx.append(b[i].x - a[i].x)
		if not dx.is_empty():
			dx.sort()
			total += dx[dx.size() / 2]
	return maxf(-total, 0.0) / TARGET_WIDTH


func _write_model(id: String, cfg: Dictionary, frames: Array[Dictionary], new_idx: PackedInt32Array, uv_atlas: PackedVector2Array,
		loop_n: int, loop_len: float, death_n: int, death_len: float, emission: bool, stride: float = 0.0) -> Dictionary:
	var nv: int = (frames[0]["pos"] as PackedVector3Array).size()
	var rows: int = ceili(float(nv) / VAT_WIDTH)
	var vat_w: int = mini(nv, VAT_WIDTH)
	# Основание: нижняя точка кадра 0 цикла — в y = 0.
	var f0: Dictionary = frames[0]
	var lift: float = INF
	for p: Vector3 in f0["pos"]:
		lift = minf(lift, p.y)
	var all_box: AABB = AABB(Vector3.ZERO, Vector3.ZERO)
	var first: bool = true
	for fr: Dictionary in frames:
		var pos: PackedVector3Array = fr["pos"]
		for i2: int in pos.size():
			pos[i2].y -= lift
			all_box = AABB(pos[i2], Vector3.ZERO) if first else all_box.expand(pos[i2])
			first = false
		fr["pos"] = pos
	# VAT: позиции и окт-нормали/касательные, по кадрам.
	var total: int = frames.size()
	var vat_pos: Image = Image.create(vat_w, total * rows, false, Image.FORMAT_RGBAH)
	var vat_nrm: Image = Image.create(vat_w, total * rows, false, Image.FORMAT_RGBAH)
	for fi: int in total:
		var fr2: Dictionary = frames[fi]
		var p2: PackedVector3Array = fr2["pos"]
		var n2: PackedVector3Array = fr2["nrm"]
		var t2: PackedVector3Array = fr2["tan"]
		for vi: int in nv:
			var x: int = vi % VAT_WIDTH
			var y: int = fi * rows + vi / VAT_WIDTH
			vat_pos.set_pixel(x, y, Color(p2[vi].x, p2[vi].y, p2[vi].z, 1.0))
			var on: Vector2 = _oct(n2[vi])
			var ot: Vector2 = _oct(t2[vi])
			vat_nrm.set_pixel(x, y, Color(on.x, on.y, ot.x, ot.y))
	# Меш в позе кадра 0.
	var out_arrays: Array = []
	out_arrays.resize(Mesh.ARRAY_MAX)
	out_arrays[Mesh.ARRAY_VERTEX] = f0["pos"]
	out_arrays[Mesh.ARRAY_NORMAL] = f0["nrm"]
	var tang: PackedFloat32Array = PackedFloat32Array()
	var tw: PackedFloat32Array = f0["tw"]
	for vi2: int in nv:
		var tv: Vector3 = (f0["tan"] as PackedVector3Array)[vi2]
		tang.append_array([tv.x, tv.y, tv.z, tw[vi2]])
	out_arrays[Mesh.ARRAY_TANGENT] = tang
	out_arrays[Mesh.ARRAY_TEX_UV] = uv_atlas
	var addr: PackedVector2Array = PackedVector2Array()
	for vi3: int in nv:
		addr.append(Vector2(float(vi3 % VAT_WIDTH), float(vi3 / VAT_WIDTH)))
	out_arrays[Mesh.ARRAY_TEX_UV2] = addr
	out_arrays[Mesh.ARRAY_INDEX] = new_idx
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
	mesh.custom_aabb = all_box.grow(0.02)
	mesh.resource_name = id
	var mesh_box: AABB = mesh.get_aabb()
	var height: float = _aabb(f0["pos"], Basis.IDENTITY).size.y
	mesh.set_meta("height", height)
	mesh.set_meta("vat_pos", ImageTexture.create_from_image(vat_pos))
	mesh.set_meta("vat_nrm", ImageTexture.create_from_image(vat_nrm))
	mesh.set_meta("rows", rows)
	mesh.set_meta("loop_frames", loop_n)
	mesh.set_meta("loop_time", loop_len)
	mesh.set_meta("death_frames", death_n)
	mesh.set_meta("death_time", death_len)
	mesh.set_meta("emission", emission)
	if stride > 0.0:
		mesh.set_meta("stride", stride)
	mesh.set_meta("source", String(cfg["title"]))
	var err: Error = ResourceSaver.save(mesh, OUT_MESH.path_join(id + ".res"), ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		return {"reason": "сохранение: " + error_string(err)}
	return {"ok": true, "tris": new_idx.size() / 3, "verts": nv, "vat_w": vat_w, "vat_h": total * rows,
		"height": height, "loop_frames": loop_n, "loop_time": loop_len, "death_frames": death_n, "box": mesh_box}


# --- Кристаллы -----------------------------------------------------------------

func _bake_crystal(id: String, cfg: Dictionary) -> Dictionary:
	var kind: String = cfg["crystal"]
	var parts: Array[Dictionary] = _crystal_parts(kind)
	# Общий список вершин: у каждой — номер части (её трансформ меняется по кадрам).
	var lpos: PackedVector3Array = PackedVector3Array()
	var lnrm: PackedVector3Array = PackedVector3Array()
	var uv: PackedVector2Array = PackedVector2Array()
	var part_of: PackedInt32Array = PackedInt32Array()
	var idx: PackedInt32Array = PackedInt32Array()
	for pi: int in parts.size():
		var g: Dictionary = _prism(float(parts[pi]["r"]), float(parts[pi]["h"]), float(parts[pi]["tip"]), pi)
		var off: int = lpos.size()
		lpos.append_array(g["pos"])
		lnrm.append_array(g["nrm"])
		uv.append_array(g["uv"])
		for _i: int in (g["pos"] as PackedVector3Array).size():
			part_of.append(pi)
		for ix: int in g["idx"]:
			idx.append(off + ix)
	var loop_n: int = int(cfg["frames"])
	var death_n: int = int(cfg["death_frames"])
	var raw: Array[Dictionary] = []
	for f: int in loop_n:
		raw.append(_crystal_pose(kind, parts, lpos, lnrm, part_of, float(f) / float(loop_n), -1.0))
	for f2: int in death_n:
		raw.append(_crystal_pose(kind, parts, lpos, lnrm, part_of, 0.0, float(f2) / float(death_n - 1)))
	# Нормировка как у моделей: ширина TARGET_WIDTH по кадру 0.
	var ab: AABB = _aabb(raw[0]["pos"], Basis.IDENTITY)
	var k: float = TARGET_WIDTH / maxf(maxf(ab.size.x, ab.size.z), 0.0001)
	if ab.size.y * k > MAX_HEIGHT:
		k = MAX_HEIGHT / ab.size.y
	var frames: Array[Dictionary] = []
	for r: Dictionary in raw:
		var pos: PackedVector3Array = r["pos"]
		for i: int in pos.size():
			pos[i] = Vector3(pos[i].x - ab.get_center().x, pos[i].y, pos[i].z - ab.get_center().z) * k
		frames.append(_with_tangents(pos, r["nrm"], uv, idx))
	_crystal_textures(id)
	var res: Dictionary = _write_model(id, cfg, frames, idx, uv, loop_n, float(cfg["loop_time"]), death_n, 0.9, true)
	res["src_tris"] = idx.size() / 3
	res["loop"] = kind
	res["death"] = "раскол"
	return res


## Части кристалла: r — радиус призмы, h — высота грани, tip — высота острия, at — место основания,
## tilt — наклон наружу (радианы), yaw — направление наклона.
func _crystal_parts(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if kind == "cluster":
		out.append({"r": 0.2, "h": 0.72, "tip": 0.34, "at": Vector3.ZERO, "tilt": 0.0, "yaw": 0.0})
		var sizes: Array[float] = [1.0, 0.8, 0.95, 0.75, 0.88]
		for i: int in 5:
			var a: float = TAU * float(i) / 5.0 + 0.3
			var sz: float = sizes[i]
			out.append({"r": 0.13 * sz, "h": 0.42 * sz, "tip": 0.2 * sz, "at": Vector3(cos(a), 0.0, sin(a)) * 0.24, "tilt": 0.55 + 0.1 * sz, "yaw": a})
	else:
		out.append({"r": 0.17, "h": 0.5, "tip": 0.26, "at": Vector3.ZERO, "tilt": 0.18, "yaw": PI})
		out.append({"r": 0.07, "h": 0.16, "tip": 0.08, "at": Vector3(0.16, 0.0, 0.1), "tilt": 0.7, "yaw": 0.6})
		out.append({"r": 0.06, "h": 0.12, "tip": 0.07, "at": Vector3(-0.05, 0.0, -0.17), "tilt": 0.8, "yaw": -1.9})
	return out


## Шестигранная призма с остриём, грани плоские (своя нормаль у каждой). Основание в y = 0 чуть уже верха.
func _prism(r: float, h: float, tip: float, seed: int) -> Dictionary:
	var pos: PackedVector3Array = PackedVector3Array()
	var nrm: PackedVector3Array = PackedVector3Array()
	var uv: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()
	var rnd: RandomNumberGenerator = RandomNumberGenerator.new()
	rnd.seed = 7919 + seed
	var top: Array[Vector3] = []
	var bot: Array[Vector3] = []
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0 + rnd.randf_range(-0.12, 0.12)
		var rr: float = r * rnd.randf_range(0.85, 1.1)
		top.append(Vector3(cos(a) * rr, h, sin(a) * rr))
		bot.append(Vector3(cos(a) * rr * 0.8, 0.0, sin(a) * rr * 0.8))
	var apex: Vector3 = Vector3(rnd.randf_range(-0.2, 0.2) * r, h + tip, rnd.randf_range(-0.2, 0.2) * r)
	var u0: float = rnd.randf()
	var tri: Callable = func(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
		var n: Vector3 = (b - a).cross(c - a).normalized()
		var base: int = pos.size()
		pos.append_array([a, b, c])
		nrm.append_array([n, n, n])
		uv.append_array([ua, ub, uc])
		idx.append_array([base, base + 2, base + 1])
	var span: float = h + tip
	for i2: int in 6:
		var j: int = (i2 + 1) % 6
		var ua: float = u0 + float(i2) / 6.0 * 0.6
		var ub: float = u0 + float(i2 + 1) / 6.0 * 0.6
		var vb: float = 0.0
		var vt: float = h / span * 0.8
		tri.call(bot[i2], bot[j], top[j], Vector2(ua, vb), Vector2(ub, vb), Vector2(ub, vt))
		tri.call(bot[i2], top[j], top[i2], Vector2(ua, vb), Vector2(ub, vt), Vector2(ua, vt))
		tri.call(top[i2], top[j], apex, Vector2(ua, vt), Vector2(ub, vt), Vector2((ua + ub) * 0.5, 0.8))
		tri.call(bot[j], bot[i2], Vector3.ZERO, Vector2(ub, 0.9), Vector2(ua, 0.9), Vector2((ua + ub) * 0.5, 1.0))
	return {"pos": pos, "nrm": nrm, "uv": uv, "idx": idx}


## Поза кристалла в фазе цикла p [0, 1) или на доле d [0, 1] клипа смерти (d < 0 — цикл).
func _crystal_pose(kind: String, parts: Array[Dictionary], lpos: PackedVector3Array, lnrm: PackedVector3Array,
		part_of: PackedInt32Array, p: float, d: float) -> Dictionary:
	var xf: Array[Transform3D] = []
	for i: int in parts.size():
		var pt: Dictionary = parts[i]
		var yaw: float = float(pt["yaw"])
		var tilt: float = float(pt["tilt"])
		var at: Vector3 = pt["at"]
		var t: Transform3D = Transform3D.IDENTITY
		if kind == "cluster":
			if i == 0:
				# Ядро медленно вращается (шесть граней — цикл замыкается за 1/6 оборота) и дышит.
				var spin: float = (TAU / 6.0) * p
				var lift: float = 0.03 * sin(TAU * p)
				var squash: float = 1.0 if d < 0.0 else 1.0 - 0.7 * d
				t = Transform3D(Basis(Vector3.UP, spin).scaled(Vector3(1.0, squash, 1.0)), Vector3(0.0, lift - (0.0 if d < 0.0 else 0.08 * d), 0.0))
			else:
				# Спутники идут по кругу (пять — 1/5 оборота за цикл) и покачиваются, при смерти разлетаются.
				var orbit: float = (TAU / 5.0) * p
				var bob: float = 0.05 * sin(TAU * (p + float(i) / 5.0))
				var lean: float = tilt + 0.08 * sin(TAU * (p + float(i) / 5.0))
				var out_d: float = 0.0 if d < 0.0 else 0.9 * (1.0 - pow(1.0 - d, 2.0))
				var arc: float = 0.0 if d < 0.0 else 0.55 * d - 0.9 * d * d
				var b: Basis = Basis(Vector3.UP, -yaw) * Basis(Vector3.BACK, -lean)
				if d >= 0.0:
					b = Basis(Vector3.UP, -yaw) * Basis(Vector3.BACK, -lean - 2.5 * d)
				var place: Vector3 = Basis(Vector3.UP, -orbit) * (at + at.normalized() * out_d) + Vector3(0.0, bob + arc, 0.0)
				t = Transform3D(Basis(Vector3.UP, -orbit) * b, place)
		else:
			# Осколок прыгает (два прыжка за цикл) и клюёт вперёд на приземлении; при смерти заваливается и тонет.
			var hop: float = 0.16 * absf(sin(TAU * p))
			var pitch: float = 0.12 * cos(2.0 * TAU * p)
			var b2: Basis = Basis(Vector3.UP, -yaw) * Basis(Vector3.BACK, -tilt)
			if d >= 0.0:
				hop = -0.25 * d
				pitch = -1.3 * d
			t = Transform3D(Basis(Vector3.BACK, pitch) * b2, Basis(Vector3.BACK, pitch) * at + Vector3(0.0, hop, 0.0))
		xf.append(t)
	var pos: PackedVector3Array = PackedVector3Array()
	var nrm: PackedVector3Array = PackedVector3Array()
	pos.resize(lpos.size())
	nrm.resize(lpos.size())
	for v: int in lpos.size():
		var tv: Transform3D = xf[part_of[v]]
		pos[v] = tv * lpos[v]
		nrm[v] = (tv.basis.orthonormalized() * lnrm[v]).normalized()
	return {"pos": pos, "nrm": nrm}


## Материал кристаллов: обсидиан Rock035 потемнее и глаже, эмиссия — маска прожилок (окрашивается цветом архетипа).
func _crystal_textures(id: String) -> void:
	var t: String = "res://assets/textures/env/env_wall_obsidian_01_%s_2k.png"
	var alb: Image = Image.load_from_file(ProjectSettings.globalize_path(t % "albedo"))
	var nrm: Image = Image.load_from_file(ProjectSettings.globalize_path(t % "normal"))
	var orm: Image = Image.load_from_file(ProjectSettings.globalize_path(t % "orm"))
	for img: Image in [alb, nrm, orm]:
		img.convert(Image.FORMAT_RGB8)
		img.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	var out_orm: Image = Image.create(1024, 1024, false, Image.FORMAT_RGB8)
	var emi: Image = Image.create(1024, 1024, false, Image.FORMAT_RGB8)
	# Прожилки в маске тонкие (в среднем 2 % площади) — в игровом масштабе их не видно. Поэтому свечение
	# = слабый внутренний свет + чёткие прожилки + размытое гало вокруг них.
	var soft: Image = orm.duplicate() as Image
	soft.resize(48, 48, Image.INTERPOLATE_BILINEAR)
	soft.resize(1024, 1024, Image.INTERPOLATE_BILINEAR)
	var soft_max: float = 0.001
	for y0: int in range(0, 1024, 8):
		for x0: int in range(0, 1024, 8):
			soft_max = maxf(soft_max, soft.get_pixel(x0, y0).b)
	for y: int in 1024:
		for x: int in 1024:
			var o: Color = orm.get_pixel(x, y)
			alb.set_pixel(x, y, alb.get_pixel(x, y) * 0.55)
			out_orm.set_pixel(x, y, Color(1.0, 0.1 + 0.25 * o.g, 0.0))
			var vein: float = clampf((o.b - 0.15) * 3.0, 0.0, 1.0)
			var halo: float = soft.get_pixel(x, y).b / soft_max
			var e: float = clampf(0.1 + vein * 0.9 + halo * halo * 0.55, 0.0, 1.0)
			emi.set_pixel(x, y, Color(e, e, e))
	_save(alb, id + "_albedo")
	_save(nrm, id + "_normal")
	_save(out_orm, id + "_orm")
	_save(emi, id + "_emission")


# --- Сцена и анимации ----------------------------------------------------------

func _load_scene(path: String) -> Node3D:
	var abs: String = ProjectSettings.globalize_path(path)
	var fbx: bool = abs.get_extension().to_lower() == "fbx"
	var doc: GLTFDocument = FBXDocument.new() if fbx else GLTFDocument.new()
	var state: GLTFState = FBXState.new() if fbx else GLTFState.new()
	if doc.append_from_file(abs, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


## Плеер с клипами: свой у glTF, у FBX-паков клипы лежат в отдельных файлах (дорожки «Skeleton3D:кость»).
func _player(scene: Node3D, cfg: Dictionary) -> AnimationPlayer:
	var players: Array[Node] = scene.find_children("*", "AnimationPlayer", true, false)
	var ap: AnimationPlayer = players[0] if not players.is_empty() else null
	var extra: Dictionary = cfg.get("anims", {})
	if extra.is_empty():
		return ap
	if ap == null:
		ap = AnimationPlayer.new()
		scene.add_child(ap)
	var lib: AnimationLibrary = AnimationLibrary.new()
	for clip: String in extra:
		var src: Node3D = _load_scene(SRC.path_join(String(extra[clip])))
		if src == null:
			continue
		var sp: Array[Node] = src.find_children("*", "AnimationPlayer", true, false)
		if not sp.is_empty():
			var p: AnimationPlayer = sp[0]
			var a: Animation = (p.get_animation(p.get_animation_list()[0]) as Animation).duplicate(true)
			# Дорожки контрол-рига (Character1_Ctrl_*) в сцене меша не существуют — убираем.
			for t: int in range(a.get_track_count() - 1, -1, -1):
				if not String(a.track_get_path(t)).contains("Skeleton3D:"):
					a.remove_track(t)
			lib.add_animation(clip, a)
		src.free()
	ap.add_animation_library("vat", lib)
	return ap


func _find_anim(ap: AnimationPlayer, want: String) -> String:
	for n: String in ap.get_animation_list():
		var short: String = n.get_slice("/", n.get_slice_count("/") - 1)
		short = short.get_slice("|", short.get_slice_count("|") - 1)
		if short == want:
			return n
	for n2: String in ap.get_animation_list():
		if n2.contains(want):
			return n2
	return ""


## Поза применяется к скелету только на кадре движка — поэтому после seek ждём кадр.
## При ретаргете клип играет у скелета-источника, а поза переносится на модель.
func _pose(scene: Node3D, ap: AnimationPlayer, anim: String, t: float) -> void:
	ap.play(anim)
	ap.seek(t, true)
	ap.pause()
	await process_frame
	if not _rt.is_empty():
		_retarget()
	for sk: Node in scene.find_children("*", "Skeleton3D", true, false):
		(sk as Skeleton3D).force_update_all_bone_transforms()


## Источник ретаргета доворачивается вокруг Y так, чтобы смотреть туда же, куда модель: угол — по горизонтальным
## позициям покоя сопоставленных костей относительно таза (наименьшие квадраты), с шагом 90° — риги выровнены по осям.
## Иначе дельты поворотов источника легли бы на модель зеркально: шаг вперёд стал бы шагом назад.
func _align_source(src_scene: Node3D, tgt_scene: Node3D, rcfg: Dictionary) -> void:
	var s: Skeleton3D = src_scene.find_children("*", "Skeleton3D", true, false)[0]
	var t: Skeleton3D = tgt_scene.find_children("*", "Skeleton3D", true, false)[0]
	var hip_t: int = t.find_bone(String(rcfg["hip"]))
	var hip_s: int = s.find_bone(String(rcfg["map"].get(String(rcfg["hip"]), "")))
	if hip_t < 0 or hip_s < 0:
		return
	var sw: Transform3D = s.global_transform
	var tw: Transform3D = t.global_transform
	var t0: Vector3 = tw * t.get_bone_global_rest(hip_t).origin
	var s0: Vector3 = sw * s.get_bone_global_rest(hip_s).origin
	var dot: float = 0.0
	var cross: float = 0.0
	for tn: String in rcfg["map"]:
		var tb: int = t.find_bone(tn)
		var sb: int = s.find_bone(String(rcfg["map"][tn]))
		if tb < 0 or sb < 0:
			continue
		var tv: Vector3 = tw * t.get_bone_global_rest(tb).origin - t0
		var sv: Vector3 = sw * s.get_bone_global_rest(sb).origin - s0
		dot += tv.x * sv.x + tv.z * sv.z
		cross += tv.x * sv.z - tv.z * sv.x
	var turn: float = snappedf(atan2(cross, dot), PI * 0.5)
	if absf(turn) > 0.01:
		src_scene.rotation.y += turn
		print("  ретаргет: источник довёрнут на %d°" % roundi(rad_to_deg(turn)))


func _retarget_setup(src_scene: Node3D, tgt_scene: Node3D, rcfg: Dictionary) -> Dictionary:
	var s: Skeleton3D = src_scene.find_children("*", "Skeleton3D", true, false)[0]
	var t: Skeleton3D = tgt_scene.find_children("*", "Skeleton3D", true, false)[0]
	var map: Dictionary = {}
	for tn: String in rcfg["map"]:
		var tb: int = t.find_bone(tn)
		var sb: int = s.find_bone(String(rcfg["map"][tn]))
		if tb < 0 or sb < 0:
			printerr("  ретаргет: нет кости %s → %s" % [tn, rcfg["map"][tn]])
			continue
		map[tb] = sb
	var sw: Transform3D = s.global_transform
	var tw: Transform3D = t.global_transform
	# Поправка позы покоя: поворот, совмещающий направление кости модели (на дочернюю) с направлением у источника.
	var fix: Dictionary = {}
	var aim: Dictionary = rcfg.get("aim", {})
	for tn2: String in aim:
		var tb2: int = t.find_bone(tn2)
		var tc: int = t.find_bone(String(aim[tn2]))
		if not map.has(tb2) or not map.has(tc):
			continue
		var dt: Vector3 = (tw * t.get_bone_global_rest(tc).origin - tw * t.get_bone_global_rest(tb2).origin).normalized()
		var ds: Vector3 = (sw * s.get_bone_global_rest(int(map[tc])).origin - sw * s.get_bone_global_rest(int(map[tb2])).origin).normalized()
		fix[tb2] = Quaternion(dt, ds)
	# Кости без своей поправки (кисть, стопа, голова) наследуют её от ближайшего предка.
	for b: int in t.get_bone_count():
		if fix.has(b):
			continue
		var p: int = t.get_bone_parent(b)
		fix[b] = fix.get(p, Quaternion.IDENTITY)
	# Свисающие части без клипов (плащ Shadowkin в позе покоя торчит назад доской): корни цепочек
	# доворачиваются так, чтобы цепочка шла вниз и чуть назад.
	var hang: Dictionary = {}
	for word: String in rcfg.get("hang", []):
		for b2: int in t.get_bone_count():
			var p2: int = t.get_bone_parent(b2)
			if not t.get_bone_name(b2).contains(word) or (p2 >= 0 and t.get_bone_name(p2).contains(word)):
				continue
			var kids: PackedInt32Array = t.get_bone_children(b2)
			if kids.is_empty():
				continue
			var dir: Vector3 = (t.get_bone_global_rest(kids[0]).origin - t.get_bone_global_rest(b2).origin).normalized()
			var want: Vector3 = (tw.basis.inverse() * Vector3(0.0, -1.0, -0.3)).normalized()
			hang[b2] = Quaternion(dir, want)
	var hip: int = t.find_bone(String(rcfg["hip"]))
	var ratio: float = (tw * t.get_bone_global_rest(hip).origin).y / maxf((sw * s.get_bone_global_rest(int(map[hip])).origin).y, 0.001)
	var order: Array[int] = []
	_bone_order(t, -1, order)
	return {"s": s, "t": t, "map": map, "fix": fix, "hip": hip, "ratio": ratio, "order": order, "hang": hang}


func _bone_order(sk: Skeleton3D, parent: int, out: Array[int]) -> void:
	var kids: PackedInt32Array = sk.get_parentless_bones() if parent < 0 else sk.get_bone_children(parent)
	for b: int in kids:
		out.append(b)
		_bone_order(sk, b, out)


## Мировой поворот кости источника относительно её покоя переносится на кость модели (с поправкой покоя);
## бедро ещё и смещается — на смещение таза источника в масштабе роста.
func _retarget() -> void:
	var s: Skeleton3D = _rt["s"]
	var t: Skeleton3D = _rt["t"]
	s.force_update_all_bone_transforms()
	var sw: Transform3D = s.global_transform
	var tw: Transform3D = t.global_transform
	var sq: Quaternion = sw.basis.get_rotation_quaternion()
	var tq_inv: Quaternion = tw.basis.get_rotation_quaternion().inverse()
	var map: Dictionary = _rt["map"]
	var glob: Dictionary = {}
	for b: int in _rt["order"]:
		var p: int = t.get_bone_parent(b)
		var pg: Transform3D = glob[p] if p >= 0 else Transform3D.IDENTITY
		var g: Transform3D = pg * (_rt["base"].get(b, t.get_bone_rest(b)) as Transform3D)
		if _rt["hang"].has(b):
			g.basis = Basis(_rt["hang"][b] as Quaternion) * g.basis
		if map.has(b):
			var sb: int = map[b]
			var d: Quaternion = (sq * s.get_bone_global_pose(sb).basis.get_rotation_quaternion()) * (sq * s.get_bone_global_rest(sb).basis.get_rotation_quaternion()).inverse()
			var rest_w: Quaternion = tw.basis.get_rotation_quaternion() * t.get_bone_global_rest(b).basis.get_rotation_quaternion()
			g.basis = Basis(tq_inv * (d * (_rt["fix"][b] as Quaternion) * rest_w)).scaled(t.get_bone_global_rest(b).basis.get_scale())
			if b == int(_rt["hip"]):
				var delta: Vector3 = sw * s.get_bone_global_pose(sb).origin - sw * s.get_bone_global_rest(sb).origin
				g.origin = tw.affine_inverse() * (tw * t.get_bone_global_rest(b).origin + delta * float(_rt["ratio"]))
		glob[b] = g
		var local: Transform3D = pg.affine_inverse() * g
		t.set_bone_pose_position(b, local.origin)
		t.set_bone_pose_rotation(b, local.basis.get_rotation_quaternion())


## Все меши в текущей позе, слитые в один список вершин (в координатах сцены).
func _posed(scene: Node3D, mis: Array[MeshInstance3D], mats: Array[Dictionary]) -> Dictionary:
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var mat_of: PackedInt32Array = PackedInt32Array()
	var index: PackedInt32Array = PackedInt32Array()
	for mi: MeshInstance3D in mis:
		var skinned: bool = mi.skin != null or not mi.skeleton.is_empty()
		var mesh: ArrayMesh = mi.bake_mesh_from_current_skeleton_pose() if skinned else mi.mesh as ArrayMesh
		if mesh == null:
			continue
		var xf: Transform3D = scene.global_transform.affine_inverse() * mi.global_transform
		for s: int in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if ix.is_empty():
				for i: int in v.size():
					ix.append(i)
			var mat_i: int = _mat_index(mats, mi.get_active_material(s))
			var off: int = verts.size()
			for i2: int in v.size():
				verts.append(xf * v[i2])
				normals.append((xf.basis * (nr[i2] if i2 < nr.size() else Vector3.UP)).normalized())
				var t: Vector2 = uv[i2] if i2 < uv.size() else Vector2.ZERO
				uvs.append(Vector2(t.x, 1.0 - t.y) if _flip_v else t)
				mat_of.append(mat_i)
			for i3: int in ix:
				index.append(off + i3)
	return {"verts": verts, "normals": normals, "uvs": uvs, "mat": mat_of, "index": index}


## Снос корня за цикл (клипы с перемещением): вычитается линейно, чтобы цикл шёл на месте.
func _loop_drift(scene: Node3D, ap: AnimationPlayer, anim: String, mis: Array[MeshInstance3D], mats: Array[Dictionary], norm: Transform3D) -> Vector3:
	await _pose(scene, ap, anim, 0.0)
	var a: Vector3 = _centroid(_xf_points(_posed(scene, mis, mats)["verts"], norm))
	await _pose(scene, ap, anim, ap.get_animation(anim).length - 0.0001)
	var b: Vector3 = _centroid(_xf_points(_posed(scene, mis, mats)["verts"], norm))
	var d: Vector3 = b - a
	d.y = 0.0
	return d if d.length() > 0.05 else Vector3.ZERO


func _frame(scene: Node3D, mis: Array[MeshInstance3D], mats: Array[Dictionary], norm: Transform3D, keep: PackedInt32Array,
		idx: PackedInt32Array, uv: PackedVector2Array, drift: Vector3) -> Dictionary:
	var posed: Dictionary = _posed(scene, mis, mats)
	var pos: PackedVector3Array = _pick3(_xf_points(posed["verts"], norm), keep)
	for i: int in pos.size():
		pos[i] -= drift
	var nrm: PackedVector3Array = _pick3(_xf_dirs(posed["normals"], norm.basis), keep)
	return _with_tangents(pos, nrm, uv, idx)


## Касательные — заново по позе кадра (MikkTSpace): normal map остаётся верной при любом изгибе.
func _with_tangents(pos: PackedVector3Array, nrm: PackedVector3Array, uv: PackedVector2Array, idx: PackedInt32Array) -> Dictionary:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var st: SurfaceTool = SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_tangents()
	var out: Array = st.commit_to_arrays()
	var tf: PackedFloat32Array = out[Mesh.ARRAY_TANGENT]
	var tan: PackedVector3Array = PackedVector3Array()
	var tw: PackedFloat32Array = PackedFloat32Array()
	var opos: PackedVector3Array = out[Mesh.ARRAY_VERTEX]
	if opos.size() != pos.size():
		push_error("SurfaceTool изменил число вершин: %d → %d" % [pos.size(), opos.size()])
	for i2: int in pos.size():
		tan.append(Vector3(tf[i2 * 4], tf[i2 * 4 + 1], tf[i2 * 4 + 2]).normalized())
		tw.append(tf[i2 * 4 + 3])
	return {"pos": pos, "nrm": nrm, "tan": tan, "tw": tw}


# --- Материалы и атлас ----------------------------------------------------------

## Материалы мешей → описания карт (Image или null) и площадь поверхности (для размера ячейки атласа).
func _collect_materials(mis: Array[MeshInstance3D], cfg: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tex_cfg: Dictionary = cfg.get("textures", {})
	for mi: MeshInstance3D in mis:
		for s: int in mi.mesh.get_surface_count():
			var m: Material = mi.get_active_material(s)
			if _mat_index(out, m) >= 0:
				continue
			var d: Dictionary = {"mat": m, "name": m.resource_name if m != null else "none", "area": 0.0}
			var bm: BaseMaterial3D = m as BaseMaterial3D
			d["color"] = bm.albedo_color if bm != null else Color.WHITE
			d["albedo"] = _img(bm.albedo_texture) if bm != null else null
			d["normal"] = _img(bm.normal_texture) if bm != null and bm.normal_enabled else null
			d["rough_img"] = _img(bm.roughness_texture) if bm != null else null
			d["rough_ch"] = bm.roughness_texture_channel if bm != null else 0
			d["rough"] = bm.roughness if bm != null else 0.7
			d["metal_img"] = _img(bm.metallic_texture) if bm != null else null
			d["metal_ch"] = bm.metallic_texture_channel if bm != null else 0
			d["metal"] = bm.metallic if bm != null else 0.0
			d["ao_img"] = _img(bm.ao_texture) if bm != null and bm.ao_enabled else null
			d["ao_ch"] = bm.ao_texture_channel if bm != null else 0
			d["emission"] = _img(bm.emission_texture) if bm != null and bm.emission_enabled else null
			d["emission_color"] = bm.emission * bm.emission_energy_multiplier if bm != null and bm.emission_enabled else Color.BLACK
			d["grade"] = {}
			var grades: Dictionary = cfg.get("grade", {})
			for gk: String in grades:
				if String(d["name"]).to_lower().contains(gk.to_lower()):
					d["grade"] = grades[gk]
			# Карты из конфига (модель без встроенных текстур): ключ — часть имени материала.
			for key: String in tex_cfg:
				if String(d["name"]).to_lower().contains(key.to_lower()):
					var t: Dictionary = tex_cfg[key]
					var load_img: Callable = func(k: String) -> Image:
						if not t.has(k):
							return null
						var img: Image = Image.load_from_file(ProjectSettings.globalize_path(SRC.path_join(String(t[k]))))
						if img == null:
							printerr("  нет карты " + String(t[k]))
						return img
					if t.has("albedo"):
						d["albedo"] = load_img.call("albedo")
						d["color"] = Color.WHITE
					if t.has("normal"):
						d["normal"] = load_img.call("normal")
					if t.has("emission"):
						d["emission"] = load_img.call("emission")
						d["emission_color"] = Color.WHITE
			out.append(d)
	return out


func _mat_index(mats: Array[Dictionary], m: Material) -> int:
	for i: int in mats.size():
		if mats[i]["mat"] == m:
			return i
	return -1


func _img(t: Texture2D) -> Image:
	if t == null:
		return null
	var img: Image = t.get_image()
	if img != null and img.is_compressed():
		img.decompress()
	return img


## Атлас: материалы делят квадрат пропорционально площади своей поверхности (бинарная treemap-раскладка
## без пустот: самый крупный материал не теряет разрешение из-за мелких — глаз, зубов).
func _build_atlas(id: String, mats: Array[Dictionary], base: Dictionary, size: int) -> Dictionary:
	var verts: PackedVector3Array = base["verts"]
	var index: PackedInt32Array = base["index"]
	var mat_of: PackedInt32Array = base["mat"]
	for i: int in range(0, index.size(), 3):
		var a: Vector3 = verts[index[i]]
		var area: float = (verts[index[i + 1]] - a).cross(verts[index[i + 2]] - a).length() * 0.5
		mats[mat_of[index[i]]]["area"] = float(mats[mat_of[index[i]]]["area"]) + area
	var total: float = 0.0
	var used: Array[int] = []
	for mi: int in mats.size():
		if float(mats[mi]["area"]) > 0.0:
			used.append(mi)
			total += float(mats[mi]["area"])
	# Вес не меньше 6 % — мелкие детали (когти, зубы) всё же получают читаемую ячейку.
	var weights: Dictionary = {}
	for mi2: int in used:
		weights[mi2] = maxf(float(mats[mi2]["area"]), total * 0.06)
	used.sort_custom(func(x: int, y: int) -> bool: return float(weights[x]) > float(weights[y]))
	var cells: Dictionary = {}
	_treemap(used, weights, Rect2i(0, 0, size, size), cells)
	var albedo: Image = Image.create(size, size, false, Image.FORMAT_RGB8)
	var normal: Image = Image.create(size, size, false, Image.FORMAT_RGB8)
	var orm: Image = Image.create(size, size, false, Image.FORMAT_RGB8)
	var emission: Image = Image.create(size, size, false, Image.FORMAT_RGB8)
	albedo.fill(Color(0.5, 0.5, 0.5))
	normal.fill(Color(0.5, 0.5, 1.0))
	orm.fill(Color(1.0, 0.8, 0.0))
	emission.fill(Color.BLACK)
	var has_emission: bool = false
	var has_normal: bool = false
	for mi3: int in cells:
		var cell: Rect2i = cells[mi3]
		var m2: Dictionary = mats[mi3]
		var s2: Vector2i = cell.size
		albedo.blit_rect(_cell_albedo(m2, s2), Rect2i(Vector2i.ZERO, s2), cell.position)
		normal.blit_rect(_cell_normal(m2, s2), Rect2i(Vector2i.ZERO, s2), cell.position)
		has_normal = has_normal or m2["normal"] != null
		orm.blit_rect(_cell_orm(m2, s2), Rect2i(Vector2i.ZERO, s2), cell.position)
		var em: Image = _cell_emission(m2, s2)
		if em != null:
			emission.blit_rect(em, Rect2i(Vector2i.ZERO, s2), cell.position)
			has_emission = true
	var uvs: PackedVector2Array = base["uvs"]
	var out_uv: PackedVector2Array = PackedVector2Array()
	out_uv.resize(uvs.size())
	var overflow: float = 0.0
	for vi: int in uvs.size():
		var c: Rect2i = cells.get(mat_of[vi], Rect2i(0, 0, 1, 1))
		var uv: Vector2 = uvs[vi]
		overflow = maxf(overflow, maxf(maxf(-uv.x, uv.x - 1.0), maxf(-uv.y, uv.y - 1.0)))
		uv = uv.clamp(Vector2.ZERO, Vector2.ONE)
		var inner: Vector2 = Vector2(c.size - Vector2i(ATLAS_PAD * 2, ATLAS_PAD * 2))
		out_uv[vi] = (Vector2(c.position) + Vector2(ATLAS_PAD, ATLAS_PAD) + uv * inner) / float(size)
	if overflow > 0.02:
		print("  %s: UV выходят за [0, 1] на %.2f — обрезаны" % [id, overflow])
	_save(albedo, id + "_albedo")
	# Без карт нормалей у исходника атлас был бы плоским: файл не пишется, шейдер берёт плоскую нормаль (hint_normal).
	if has_normal:
		_save(normal, id + "_normal")
	else:
		_remove_map(id + "_normal")
	_save(orm, id + "_orm")
	if has_emission:
		_save(emission, id + "_emission")
	else:
		_remove_map(id + "_emission")
	var layout: Array[String] = []
	for mi4: int in cells:
		layout.append("%s %dx%d" % [mats[mi4]["name"], (cells[mi4] as Rect2i).size.x, (cells[mi4] as Rect2i).size.y])
	print("  атлас %d: %s" % [size, ", ".join(layout)])
	return {"uv": out_uv, "emission": has_emission}


## Делит прямоугольник между материалами (отсортированы по убыванию веса): две группы примерно
## равного веса, разрез поперёк длинной стороны — пропорционально весу.
func _treemap(items: Array[int], weights: Dictionary, rect: Rect2i, out: Dictionary) -> void:
	if items.size() == 1:
		out[items[0]] = rect
		return
	var total: float = 0.0
	for it: int in items:
		total += float(weights[it])
	var k: int = 1
	var acc: float = float(weights[items[0]])
	while k < items.size() - 1 and acc + float(weights[items[k]]) <= total * 0.5:
		acc += float(weights[items[k]])
		k += 1
	var a: Array[int] = items.slice(0, k)
	var b: Array[int] = items.slice(k)
	var f: float = acc / total
	if rect.size.x >= rect.size.y:
		var w: int = clampi(int(round(rect.size.x * f)), 1, rect.size.x - 1)
		_treemap(a, weights, Rect2i(rect.position, Vector2i(w, rect.size.y)), out)
		_treemap(b, weights, Rect2i(rect.position + Vector2i(w, 0), Vector2i(rect.size.x - w, rect.size.y)), out)
	else:
		var h: int = clampi(int(round(rect.size.y * f)), 1, rect.size.y - 1)
		_treemap(a, weights, Rect2i(rect.position, Vector2i(rect.size.x, h)), out)
		_treemap(b, weights, Rect2i(rect.position + Vector2i(0, h), Vector2i(rect.size.x, rect.size.y - h)), out)


## Карта материала, вписанная в ячейку с полем ATLAS_PAD (края ячейки — растянутая кайма).
func _fit_cell(img: Image, s: Vector2i) -> Image:
	var inner: Vector2i = s - Vector2i(ATLAS_PAD * 2, ATLAS_PAD * 2)
	var im: Image = img.duplicate() as Image
	if im.get_format() != Image.FORMAT_RGBA8:
		im.convert(Image.FORMAT_RGBA8)
	im.resize(inner.x, inner.y, Image.INTERPOLATE_LANCZOS)
	var out: Image = Image.create(s.x, s.y, false, Image.FORMAT_RGBA8)
	var bleed: Image = im.duplicate() as Image
	bleed.resize(s.x, s.y, Image.INTERPOLATE_BILINEAR)
	out.blit_rect(bleed, Rect2i(Vector2i.ZERO, s), Vector2i.ZERO)
	out.blit_rect(im, Rect2i(Vector2i.ZERO, inner), Vector2i(ATLAS_PAD, ATLAS_PAD))
	return out


func _flat(s: Vector2i, c: Color) -> Image:
	var img: Image = Image.create(s.x, s.y, false, Image.FORMAT_RGB8)
	img.fill(c)
	return img


func _cell_albedo(m: Dictionary, s: Vector2i) -> Image:
	var col: Color = m["color"]
	if m["albedo"] == null:
		return _flat(s, Color(col.r, col.g, col.b))
	var img: Image = _fit_cell(m["albedo"], s)
	var g: Dictionary = m["grade"]
	if not col.is_equal_approx(Color.WHITE) or not g.is_empty():
		var sat: float = float(g.get("sat", 1.0))
		var gain: float = float(g.get("gain", 1.0))
		var tint: Color = Color.html(String(g.get("tint", "ffffff")))
		for y: int in s.y:
			for x: int in s.x:
				var c: Color = img.get_pixel(x, y) * Color(col.r, col.g, col.b, 1.0)
				if not g.is_empty():
					var l: float = c.get_luminance()
					c = Color(lerpf(l, c.r, sat), lerpf(l, c.g, sat), lerpf(l, c.b, sat)) * gain
					c = Color(c.r * tint.r * 2.0, c.g * tint.g * 2.0, c.b * tint.b * 2.0).clamp()
				img.set_pixel(x, y, c)
	img.convert(Image.FORMAT_RGB8)
	return img


func _cell_normal(m: Dictionary, s: Vector2i) -> Image:
	if m["normal"] == null:
		return _flat(s, Color(0.5, 0.5, 1.0))
	var img: Image = _fit_cell(m["normal"], s)
	img.convert(Image.FORMAT_RGB8)
	return img


func _cell_orm(m: Dictionary, s: Vector2i) -> Image:
	var ao: Image = _fit_cell(m["ao_img"], s) if m["ao_img"] != null else null
	var rg: Image = _fit_cell(m["rough_img"], s) if m["rough_img"] != null else null
	var mt: Image = _fit_cell(m["metal_img"], s) if m["metal_img"] != null else null
	var out: Image = Image.create(s.x, s.y, false, Image.FORMAT_RGB8)
	var rough_k: float = float(m["rough"])
	var metal_k: float = float(m["metal"])
	for y: int in s.y:
		for x: int in s.x:
			var o: float = _ch(ao.get_pixel(x, y), int(m["ao_ch"])) if ao != null else 1.0
			var r: float = _ch(rg.get_pixel(x, y), int(m["rough_ch"])) if rg != null else 1.0
			var mm: float = _ch(mt.get_pixel(x, y), int(m["metal_ch"])) if mt != null else 1.0
			out.set_pixel(x, y, Color(o, clampf(r * rough_k, 0.0, 1.0), clampf(mm * metal_k, 0.0, 1.0)))
	return out


func _cell_emission(m: Dictionary, s: Vector2i) -> Image:
	var ec: Color = m["emission_color"]
	if m["emission"] == null:
		if ec.get_luminance() < 0.01:
			return null
		return _flat(s, Color(ec.r, ec.g, ec.b).clamp())
	var img: Image = _fit_cell(m["emission"], s)
	img.convert(Image.FORMAT_RGB8)
	return img


static func _ch(c: Color, ch: int) -> float:
	match ch:
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return c.g
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return c.b
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return c.a
		BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE:
			return c.get_luminance()
	return c.r


## Атласы — JPG: в PNG карты боссов весили бы по 5–7 МБ (всего ~130 МБ в репозитории), а в игре они
## всё равно сжимаются в VRAM (BPTC/ASTC). Normal map — с качеством повыше: блочность видна в бликах.
func _save(img: Image, name: String) -> void:
	var path: String = OUT_TEX.path_join(name + ".jpg")
	var err: Error = img.save_jpg(path, 0.95 if name.ends_with("_normal") else 0.9)
	if err != OK:
		printerr("✗ " + path)


## Карта, которой у модели больше нет (прошлое запекание), удаляется вместе с .import — иначе ArtKit подхватил бы её.
func _remove_map(name: String) -> void:
	var path: String = ProjectSettings.globalize_path(OUT_TEX.path_join(name + ".jpg"))
	for f: String in [path, path + ".import"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


# --- Геометрия -----------------------------------------------------------------

## Упрощение до бюджета (как в tools/bake_art_assets.gd): самый подробный LOD движка, что в него укладывается.
func _simplified_indices(arrays: Array, budget: int) -> PackedInt32Array:
	var full: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if full.size() / 3 <= budget:
		return full
	var im: ImporterMesh = ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	im.generate_lods(25.0, 60.0, [])
	var best: PackedInt32Array = full
	for l: int in im.get_surface_lod_count(0):
		var idx: PackedInt32Array = im.get_surface_lod_indices(0, l)
		if idx.size() / 3 <= budget and (best == full or idx.size() > best.size()):
			best = idx
	return best


static func _xf_points(p: PackedVector3Array, xf: Transform3D) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	out.resize(p.size())
	for i: int in p.size():
		out[i] = xf * p[i]
	return out


static func _xf_dirs(d: PackedVector3Array, b: Basis) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	out.resize(d.size())
	for i: int in d.size():
		out[i] = (b * d[i]).normalized()
	return out


static func _pick3(src: PackedVector3Array, keep: PackedInt32Array) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	out.resize(keep.size())
	for i: int in keep.size():
		out[i] = src[keep[i]]
	return out


static func _pick2(src: PackedVector2Array, keep: PackedInt32Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(keep.size())
	for i: int in keep.size():
		out[i] = src[keep[i]]
	return out


static func _aabb(p: PackedVector3Array, b: Basis) -> AABB:
	var box: AABB = AABB(b * p[0], Vector3.ZERO)
	for v: Vector3 in p:
		box = box.expand(b * v)
	return box


static func _centroid(p: PackedVector3Array) -> Vector3:
	var c: Vector3 = Vector3.ZERO
	for v: Vector3 in p:
		c += v
	return c / float(maxi(p.size(), 1))


## Октаэдральная упаковка единичного вектора в два числа [-1, 1].
static func _oct(n: Vector3) -> Vector2:
	var v: Vector3 = n / (absf(n.x) + absf(n.y) + absf(n.z))
	var o: Vector2 = Vector2(v.x, v.z)
	if v.y < 0.0:
		o = Vector2((1.0 - absf(v.z)) * signf(v.x if v.x != 0.0 else 1.0), (1.0 - absf(v.x)) * signf(v.z if v.z != 0.0 else 1.0))
	return o
