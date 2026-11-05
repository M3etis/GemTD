extends SceneTree
## Подготовка ассетов арт-дирекшна: окружение (CC0: Poly Haven, ambientCG), огранки гемов и пьедестал
## (CC BY 4.0, Sketchfab) — авторы и лицензии в assets/LICENSES.md и CREDITS.md.
## Источники лежат в art_src/ (папка с .gdignore и в .gitignore): их заново скачивают по ссылкам из SOURCES.
## Результат:
##   assets/environment/*.res     — упрощённые меши (ArrayMesh с касательными; скалы бездны — с LOD);
##   assets/characters/gems/*.res — огранки гемов (стол вверх, калетта в y = 0, ширина 1);
##   assets/props/*.res, assets/textures/props/*.png — пьедестал гемов и его карты;
##   assets/textures/env/*.png    — карты: albedo (sRGB), normal (OpenGL, 8 бит), ORM (R — AO, G — roughness, B — доп. маска).
##   assets/vfx/*.png             — спрайты частиц (маски Kenney Particle Pack, CC0) и флипбуки (Unity Labs, CC0).
## Запуск: godot --headless --path . -s res://tools/bake_art_assets.gd (только VFX: -- --vfx)

const SRC: String = "res://art_src"
const OUT_MESH: String = "res://assets/environment"
const OUT_TEX: String = "res://assets/textures/env"

## Откуда скачаны исходники (для перезапекания и assets/LICENSES.md).
const SOURCES: Dictionary = {
	"moon_rock_02": "https://polyhaven.com/a/moon_rock_02 (glTF 2K)",
	"boulder_01": "https://polyhaven.com/a/boulder_01 (glTF 2K)",
	"rock_face_01": "https://polyhaven.com/a/rock_face_01 (glTF 2K)",
	"Tiles139": "https://ambientcg.com/view?id=Tiles139 (2K-PNG)",
	"Rock035": "https://ambientcg.com/view?id=Rock035 (2K-PNG)",
	"kloppenheim_07_puresky": "https://polyhaven.com/a/kloppenheim_07_puresky (HDR 4K)",
	"gems_21": "https://sketchfab.com/3d-models/gems-21-different-shapes-1fb35b1aefae4d819dde9de90162602a (GLB)",
	"pedestal_type_c": "https://sketchfab.com/3d-models/antique-classical-pedestal-stands-type-c-9e4d070d27f944ef93e28287ab893ab0 (GLB, текстуры 1K)",
	"gemstone_pack": "https://sketchfab.com/3d-models/gemstone-pack-68c4ec3dd23247188884243ad8bb2492 (GLB)",
	"kenney": "https://github.com/Calinou/kenney-particle-pack (Particle Pack 1.1, PNG 512)",
	"unitylabs": "https://unity.com/blog/engine-platform/free-vfx-image-sequences-flipbooks (<Имя>-flipbooks.zip, TGA)",
}

const OUT_VFX: String = "res://assets/vfx"
## VFX: mask — маска (яркость × альфа) в L и A: частицы смешиваются premultiplied — светят и чуть заслоняют
## светлый пол (чистое сложение на нём уходит в белое), цвет даёт частица;
## rgba — как есть (флипбуки с альфой: дым, взрыв, пламя); rgb — без альфы, для сложения (огненный шар).
## Имя флипбука кончается сеткой кадров (5x5, 8x8, 16x4) — её читает FxLayer.
const VFX: Dictionary = {
	"vfx_spark_flare_01": {"src": "vfx/kenney/flare_01.png", "size": 256, "mode": "mask"},
	"vfx_spark_star_01": {"src": "vfx/kenney/star_04.png", "size": 256, "mode": "mask"},
	"vfx_spark_glow_01": {"src": "vfx/kenney/circle_05.png", "size": 128, "mode": "mask"},
	"vfx_bolt_01": {"src": "vfx/kenney/spark_06.png", "size": 256, "mode": "mask"},
	"vfx_streak_01": {"src": "vfx/kenney/trace_06.png", "size": 256, "mode": "mask"},
	"vfx_twirl_01": {"src": "vfx/kenney/twirl_02.png", "size": 256, "mode": "mask"},
	"vfx_smoke_puff_01": {"src": "vfx/kenney/smoke_04.png", "size": 256, "mode": "rgba"},
	"vfx_explosion_01_5x5": {"src": "vfx/unitylabs/Explosion01-light/Explosion01-light_5x5.tga", "mode": "rgba"},
	"vfx_smoke_wisp_01_8x8": {"src": "vfx/unitylabs/WispySmoke01/WispySmoke01_8x8.tga", "mode": "rgba"},
	"vfx_dust_column_01_16x4": {"src": "vfx/unitylabs/DiscSmoke01/DiscSmoke01_16x4.tga", "mode": "rgba"},
	"vfx_fireball_01_8x8": {"src": "vfx/unitylabs/FireBall02/FireBall02_8x8.tga", "mode": "rgb"},
	"vfx_flame_01_16x4": {"src": "vfx/unitylabs/Flame02/Flame02_16x4.tga", "mode": "rgba"},
}

## Меши: footprint — размер по XZ, height — по Y (0 — пропорционально), tris — бюджет, lods — строить ли LOD,
## square — насколько вытянуть круглый в плане скан к квадрату (0 — как есть, 1 — квадрат).
## Блок стены рисуется MultiMesh до 1200 раз, поэтому одна ступень упрощения без LOD; квадратный план
## нужен, чтобы соседние блоки смыкались в сплошную стену лабиринта, а не рассыпались галькой.
const MESHES: Dictionary = {
	"env_wall_block_01": {"src": "moon_rock_02/moon_rock_02_2k.gltf", "footprint": 0.96, "height": 0.62, "tris": 600, "lods": false, "square": 0.9},
	"env_abyss_boulder_01": {"src": "boulder_01/boulder_01_2k.gltf", "footprint": 1.0, "height": 0.0, "tris": 12000, "lods": true},
	"env_abyss_rockface_01": {"src": "rock_face_01/rock_face_01_2k.gltf", "footprint": 1.0, "height": 0.0, "tris": 20000, "lods": true},
	# Огранки гемов (node — часть имени меша в наборе). Грани плоские, упрощение не нужно (80–250 треуг.).
	# Силуэт в плане у каждого гема свой (подсказка не только цветом — палитра для дальтоников).
	"gem_cut_marquise": {"src": "gems_21/gems_21_different_shapes.glb", "node": "Marquise", "gem": true, "out": "res://assets/characters/gems",
		"footprint": 1.0, "height": 0.0, "tris": 100000, "lods": false},
	"gem_cut_cushion": {"src": "gems_21/gems_21_different_shapes.glb", "node": "Cushion", "gem": true, "out": "res://assets/characters/gems",
		"footprint": 1.0, "height": 0.0, "tris": 100000, "lods": false},
	"gem_cut_emerald": {"src": "gems_21/gems_21_different_shapes.glb", "node": "Emerald", "gem": true, "out": "res://assets/characters/gems",
		"footprint": 1.0, "height": 0.0, "tris": 100000, "lods": false},
	"gem_cut_pear": {"src": "gems_21/gems_21_different_shapes.glb", "node": "Pear (tear)", "gem": true, "out": "res://assets/characters/gems",
		"footprint": 1.0, "height": 0.0, "tris": 100000, "lods": false},
	"gem_cut_trilliant": {"src": "gems_21/gems_21_different_shapes.glb", "node": "Trilliant", "gem": true, "out": "res://assets/characters/gems",
		"footprint": 1.0, "height": 0.0, "tris": 100000, "lods": false},
	"gem_cut_octagon": {"src": "gems_21/gems_21_different_shapes.glb", "node": "Octagon", "gem": true, "out": "res://assets/characters/gems",
		"footprint": 1.0, "height": 0.0, "tris": 100000, "lods": false},
	"gem_cut_round": {"src": "gems_21/gems_21_different_shapes.glb", "node": "Classic Round", "gem": true, "out": "res://assets/characters/gems",
		"footprint": 1.0, "height": 0.0, "tris": 100000, "lods": false},
	# Кабошон опала (Gemstone Pack, единственный меш на 640 треугольников): гладкий купол, грани не нужны.
	"gem_cut_cabochon": {"src": "gemstone_pack/gemstone_pack.glb", "node": "Object_4", "gem": true, "smooth": true, "out": "res://assets/characters/gems",
		"footprint": 1.0, "height": 0.0, "tris": 100000, "lods": false},
	# Пьедестал: каменный вариант колонны; до 60 на поле (и ещё раз в тенях) — бюджет ~3K треугольников.
	"prop_pedestal_column_01": {"src": "pedestal_type_c/antique_classical_pedestal_stands_type_c.glb", "node": "Object_4", "out": "res://assets/props",
		"footprint": 0.62, "height": 0.0, "tris": 3000, "lods": false, "textures": "prop_pedestal_column_01"},
}


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--vfx"):
		_vfx()
		quit()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_MESH))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_TEX))
	var failed: int = 0
	for id: String in MESHES:
		var r: Dictionary = _bake_mesh(id, MESHES[id])
		if not bool(r["ok"]):
			failed += 1
			printerr("✗ %s: %s" % [id, r["reason"]])
		else:
			print("✓ %-24s %6d → %5d треуг., LOD %d, размер %s" % [id, int(r["tris"]), int(r["final"]), int(r["lods"]), r["size"]])
	_textures()
	_vfx()
	quit(1 if failed > 0 else 0)


# --- Меши --------------------------------------------------------------------

func _bake_mesh(id: String, cfg: Dictionary) -> Dictionary:
	var doc: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var err: Error = doc.append_from_file(SRC.path_join("models").path_join(String(cfg["src"])), state)
	if err != OK:
		return {"ok": false, "reason": "glTF: " + error_string(err)}
	var scene: Node = doc.generate_scene(state)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var only: String = String(cfg.get("node", ""))
	for mi: MeshInstance3D in _mesh_instances(scene):
		# Имя узла: точное совпадение или префикс до «_» (в наборе огранок узлы — «Marquise_Gem_Topaze_0»).
		if not only.is_empty() and String(mi.name) != only and not String(mi.name).begins_with(only + "_"):
			continue
		for s: int in mi.mesh.get_surface_count():
			st.append_from(mi.mesh, s, mi.global_transform if mi.is_inside_tree() else _chain(mi))
		if cfg.has("textures"):
			_material_textures(mi.get_active_material(0), String(cfg["textures"]))
	scene.free()
	st.index()
	var arrays: Array = st.commit_to_arrays()
	# Лишние каналы сканов (TEXCOORD_2/3 → CUSTOM, кости) не нужны и ломают пересборку поверхности.
	for k: int in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		arrays[k] = null
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return {"ok": false, "reason": "пустой меш"}
	if bool(cfg.get("gem", false)):
		_orient_gem(arrays)
		if not bool(cfg.get("smooth", false)):
			arrays = _flat_facets(arrays)
		verts = arrays[Mesh.ARRAY_VERTEX]
	var square: float = float(cfg.get("square", 0.0))
	if square > 0.0:
		_squarify(verts, square)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = _smooth_normals(arrays)
	# Нормировка: основание в y = 0, центр по XZ, размер по footprint/height.
	var aabb: AABB = AABB(verts[0], Vector3.ZERO)
	for v: Vector3 in verts:
		aabb = aabb.expand(v)
	var fp: float = float(cfg["footprint"])
	var sx: float = fp / maxf(aabb.size.x, 0.001)
	var sz: float = fp / maxf(aabb.size.z, 0.001)
	var uniform: float = fp / maxf(maxf(aabb.size.x, aabb.size.z), 0.001)
	var hy: float = float(cfg["height"])
	var scale: Vector3 = Vector3(sx, hy / maxf(aabb.size.y, 0.001), sz) if hy > 0.0 else Vector3.ONE * uniform
	var center: Vector3 = Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i: int in verts.size():
		verts[i] = (verts[i] - center) * scale
		# Неравномерный масштаб: нормали — через обратную транспонированную матрицу.
		normals[i] = (normals[i] / scale).normalized()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var src_tris: int = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	arrays[Mesh.ARRAY_INDEX] = _simplified_indices(arrays, int(cfg["tris"]))
	# Касательные для карт нормалей (в исходниках Poly Haven их нет).
	var st2: SurfaceTool = SurfaceTool.new()
	st2.create_from_arrays(arrays)
	st2.generate_tangents()
	var final_arrays: Array = st2.commit_to_arrays()
	var mesh: ArrayMesh
	var lod_count: int = 0
	if bool(cfg["lods"]):
		var im: ImporterMesh = ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, final_arrays)
		im.generate_lods(25.0, 60.0, [])
		lod_count = im.get_surface_lod_count(0)
		mesh = im.get_mesh()
	else:
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, final_arrays)
	var out_dir: String = String(cfg.get("out", OUT_MESH))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var path: String = out_dir.path_join(id + ".res")
	err = ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		return {"ok": false, "reason": "сохранение: " + error_string(err)}
	var final_tris: int = (final_arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return {"ok": true, "tris": src_tris, "final": final_tris, "lods": lod_count, "size": str(mesh.get_aabb().size.snapped(Vector3.ONE * 0.01))}


## Огранка «столом» вверх: самая тонкая ось камня становится Y, площадка (много вершин на краю оси) — сверху,
## калетта — снизу; длинная сторона в плане — по X.
func _orient_gem(arrays: Array) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var aabb: AABB = AABB(verts[0], Vector3.ZERO)
	for v: Vector3 in verts:
		aabb = aabb.expand(v)
	var depth: int = aabb.size.min_axis_index()
	var lo: float = aabb.position[depth]
	var hi: float = aabb.end[depth]
	var tol: float = (hi - lo) * 0.03
	var n_lo: int = 0
	var n_hi: int = 0
	for v: Vector3 in verts:
		n_lo += 1 if v[depth] < lo + tol else 0
		n_hi += 1 if v[depth] > hi - tol else 0
	var up: Vector3 = Vector3.ZERO
	up[depth] = 1.0 if n_hi >= n_lo else -1.0
	var rest: Array[int] = [0, 1, 2]
	rest.erase(depth)
	var long_axis: int = rest[0] if aabb.size[rest[0]] >= aabb.size[rest[1]] else rest[1]
	var x: Vector3 = Vector3.ZERO
	x[long_axis] = 1.0
	var z: Vector3 = x.cross(up)
	# Базис: мировые X/Y/Z камня → x / up / z.
	var b: Basis = Basis(x, up, z).transposed()
	for i: int in verts.size():
		verts[i] = b * verts[i]
		normals[i] = (b * normals[i]).normalized()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals


## Плоские грани: у каждого треугольника своя нормаль наружу (в наборе нормали местами сглажены и перевёрнуты),
## иначе шейдер не видит граней и камень выглядит пластиковым.
func _flat_facets(arrays: Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var c: Vector3 = Vector3.ZERO
	for v: Vector3 in verts:
		c += v
	c /= float(verts.size())
	var ov: PackedVector3Array = PackedVector3Array()
	var on: PackedVector3Array = PackedVector3Array()
	var ou: PackedVector2Array = PackedVector2Array()
	for t: int in range(0, idx.size(), 3):
		var a: Vector3 = verts[idx[t]]
		var b: Vector3 = verts[idx[t + 1]]
		var d: Vector3 = verts[idx[t + 2]]
		var n: Vector3 = (b - a).cross(d - a)
		if n.length_squared() < 1e-14:
			continue
		n = n.normalized()
		var order: Array[int] = [idx[t], idx[t + 1], idx[t + 2]]
		# Godot: лицевая сторона — по часовой стрелке при взгляде снаружи, нормаль — от центра камня.
		if n.dot((a + b + d) / 3.0 - c) < 0.0:
			n = -n
		else:
			order = [idx[t], idx[t + 2], idx[t + 1]]
		for k: int in order:
			ov.append(verts[k])
			on.append(n)
			ou.append(uvs[k] if not uvs.is_empty() else Vector2.ZERO)
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = ov
	out[Mesh.ARRAY_NORMAL] = on
	out[Mesh.ARRAY_TEX_UV] = ou
	var inds: PackedInt32Array = PackedInt32Array()
	for i: int in ov.size():
		inds.append(i)
	out[Mesh.ARRAY_INDEX] = inds
	return out


## Карты материала glTF → albedo, normal и ORM (R — AO, G — roughness, B — metallic) 1K в assets/textures/props.
func _material_textures(mat: Material, name: String) -> void:
	var m: BaseMaterial3D = mat as BaseMaterial3D
	if m == null:
		printerr("✗ у %s нет PBR-материала" % name)
		return
	var dir: String = "res://assets/textures/props"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if m.albedo_texture != null:
		_save_to(_fit(m.albedo_texture.get_image(), Image.FORMAT_RGB8), dir, name + "_albedo_1k")
	if m.normal_texture != null:
		_save_to(_fit(m.normal_texture.get_image(), Image.FORMAT_RGB8), dir, name + "_normal_1k")
	var mr: Image = _fit(m.roughness_texture.get_image(), Image.FORMAT_RGB8) if m.roughness_texture != null else null
	if mr != null:
		# glTF metallicRoughness: G — roughness, B — metallic; AO в наборе нет → R = 1.
		var d: PackedByteArray = mr.get_data()
		for i: int in range(0, d.size(), 3):
			d[i] = 255
		_save_to(Image.create_from_data(mr.get_width(), mr.get_height(), false, Image.FORMAT_RGB8, d), dir, name + "_orm_1k")


func _fit(img: Image, format: Image.Format) -> Image:
	if img.is_compressed():
		img.decompress()
	if img.get_format() != format:
		img.convert(format)
	if img.get_width() > 1024:
		img.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	return img


func _save_to(img: Image, dir: String, name: String) -> void:
	var path: String = dir.path_join(name + ".png")
	var err: Error = img.save_png(path)
	print(("✓ " if err == OK else "✗ ") + path + " %dx%d" % [img.get_width(), img.get_height()])


## Круг в плане → квадрат: точка на радиусе r уходит на сторону квадрата с половиной r (вдоль своего луча).
func _squarify(verts: PackedVector3Array, k: float) -> void:
	var c: Vector3 = Vector3.ZERO
	for v: Vector3 in verts:
		c += v
	c /= float(verts.size())
	for i: int in verts.size():
		var d: Vector2 = Vector2(verts[i].x - c.x, verts[i].z - c.z)
		var m: float = maxf(absf(d.x), absf(d.y))
		if m > 1e-6:
			var f: float = lerpf(1.0, d.length() / m, k)
			verts[i] = Vector3(c.x + d.x * f, verts[i].y, c.z + d.y * f)


func _smooth_normals(arrays: Array) -> PackedVector3Array:
	var st: SurfaceTool = SurfaceTool.new()
	var a: Array = arrays.duplicate()
	a[Mesh.ARRAY_NORMAL] = null
	a[Mesh.ARRAY_TANGENT] = null
	st.create_from_arrays(a)
	st.generate_normals()
	return st.commit_to_arrays()[Mesh.ARRAY_NORMAL]


func _mesh_instances(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c: Node in n.get_children():
		out.append_array(_mesh_instances(c))
	return out


## Сцена glTF вне дерева: global_transform недоступен, собираем цепочку локальных преобразований.
func _chain(n: Node3D) -> Transform3D:
	var t: Transform3D = n.transform
	var p: Node = n.get_parent()
	while p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


## Упрощение до бюджета (как в tools/bake_enemy_vat.gd): самый подробный LOD движка, что в него укладывается.
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


# --- VFX ---------------------------------------------------------------------

func _vfx() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_VFX))
	for id: String in VFX:
		var cfg: Dictionary = VFX[id]
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(SRC.path_join(String(cfg["src"]))))
		if img == null:
			printerr("✗ нет " + String(cfg["src"]))
			continue
		img.convert(Image.FORMAT_RGBA8)
		if cfg.has("size") and img.get_width() != int(cfg["size"]):
			img.resize(int(cfg["size"]), int(cfg["size"]), Image.INTERPOLATE_LANCZOS)
		match String(cfg["mode"]):
			"mask":
				var m: Image = Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_LA8)
				for y: int in img.get_height():
					for x: int in img.get_width():
						var c: Color = img.get_pixel(x, y)
						var v: float = c.get_luminance() * c.a
						m.set_pixel(x, y, Color(v, v, v, v))
				img = m
			"rgb":
				img.convert(Image.FORMAT_RGB8)
		var path: String = OUT_VFX.path_join(id + ".png")
		var err: Error = img.save_png(path)
		print(("✓ " if err == OK else "✗ ") + path + " %dx%d" % [img.get_width(), img.get_height()])


# --- Текстуры ----------------------------------------------------------------

func _textures() -> void:
	var t: String = SRC.path_join("textures")
	# Пол арены: Tiles139 — 6×6 плит на текстуру, одна плита = одна клетка.
	_save(_load(t + "/Tiles139/Tiles139_2K-PNG_Color.png", Image.FORMAT_RGB8), "env_arena_floor_01_albedo_2k")
	_save(_load(t + "/Tiles139/Tiles139_2K-PNG_NormalGL.png", Image.FORMAT_RGB8), "env_arena_floor_01_normal_2k")
	var height: Image = _load(t + "/Tiles139/Tiles139_2K-PNG_Displacement.png", Image.FORMAT_L8)
	var rough: Image = _load(t + "/Tiles139/Tiles139_2K-PNG_Roughness.png", Image.FORMAT_L8)
	_save(_orm(_ao_from_height(height), rough, height), "env_arena_floor_01_orm_2k")
	# Обсидиан стен: Rock035, в B — маска светлых прожилок (по ним идёт эмиссия жил).
	var albedo: Image = _load(t + "/Rock035/Rock035_2K-PNG_Color.png", Image.FORMAT_RGB8)
	_save(albedo, "env_wall_obsidian_01_albedo_2k")
	_save(_load(t + "/Rock035/Rock035_2K-PNG_NormalGL.png", Image.FORMAT_RGB8), "env_wall_obsidian_01_normal_2k")
	_save(_orm(_load(t + "/Rock035/Rock035_2K-PNG_AmbientOcclusion.png", Image.FORMAT_L8),
		_load(t + "/Rock035/Rock035_2K-PNG_Roughness.png", Image.FORMAT_L8), _vein_mask(albedo)), "env_wall_obsidian_01_orm_2k")
	# Сканы Poly Haven: нормаль и ARM (= ORM: AO, roughness, metallic) по UV меша.
	var m: String = SRC.path_join("models")
	_save(_load(m + "/moon_rock_02/textures/moon_rock_02_nor_gl_2k.jpg", Image.FORMAT_RGB8, 1024), "env_wall_block_01_normal_1k")
	_save(_load(m + "/moon_rock_02/textures/moon_rock_02_arm_2k.jpg", Image.FORMAT_RGB8, 1024), "env_wall_block_01_orm_1k")
	for id: String in ["boulder_01", "rock_face_01"]:
		var name: String = "env_abyss_boulder_01" if id == "boulder_01" else "env_abyss_rockface_01"
		_save(_load("%s/%s/textures/%s_diff_2k.jpg" % [m, id, id], Image.FORMAT_RGB8, 1024), name + "_albedo_1k")
		_save(_load("%s/%s/textures/%s_nor_gl_2k.jpg" % [m, id, id], Image.FORMAT_RGB8, 1024), name + "_normal_1k")
		_save(_load("%s/%s/textures/%s_arm_2k.jpg" % [m, id, id], Image.FORMAT_RGB8, 1024), name + "_orm_1k")
	# HDRI копируется как есть; размер в VRAM ограничивает импорт (process/size_limit).
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/hdri"))
	DirAccess.copy_absolute(ProjectSettings.globalize_path(SRC + "/hdri/kloppenheim_07_puresky_4k.hdr"),
		ProjectSettings.globalize_path("res://assets/hdri/env_sky_night_01_4k.hdr"))


func _load(path: String, format: Image.Format, size: int = 0) -> Image:
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		printerr("✗ нет файла " + path)
		return Image.create(4, 4, false, format)
	if img.get_format() != format:
		img.convert(format)
	if size > 0 and img.get_width() != size:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return img


func _save(img: Image, name: String) -> void:
	var path: String = OUT_TEX.path_join(name + ".png")
	var err: Error = img.save_png(path)
	print(("✓ " if err == OK else "✗ ") + path + " %dx%d" % [img.get_width(), img.get_height()])


func _orm(r: Image, g: Image, b: Image) -> Image:
	var rd: PackedByteArray = r.get_data()
	var gd: PackedByteArray = g.get_data()
	var bd: PackedByteArray = b.get_data()
	var out: PackedByteArray = PackedByteArray()
	out.resize(rd.size() * 3)
	for i: int in rd.size():
		out[i * 3] = rd[i]
		out[i * 3 + 1] = gd[i]
		out[i * 3 + 2] = bd[i]
	return Image.create_from_data(r.get_width(), r.get_height(), false, Image.FORMAT_RGB8, out)


## AO из карты высот: швы и сколы ниже поверхности плиты темнеют.
func _ao_from_height(h: Image) -> Image:
	var d: PackedByteArray = h.get_data()
	var lo: int = _percentile(d, 0.02)
	var hi: int = _percentile(d, 0.6)
	var out: PackedByteArray = PackedByteArray()
	out.resize(d.size())
	for i: int in d.size():
		var k: float = clampf(float(d[i] - lo) / float(maxi(hi - lo, 1)), 0.0, 1.0)
		out[i] = int(255.0 * lerpf(0.45, 1.0, k * k * (3.0 - 2.0 * k)))
	return Image.create_from_data(h.get_width(), h.get_height(), false, Image.FORMAT_L8, out)


## Маска прожилок: самые светлые 4 % пикселей альбедо с мягким краем.
func _vein_mask(albedo: Image) -> Image:
	var l: Image = albedo.duplicate()
	l.convert(Image.FORMAT_L8)
	var d: PackedByteArray = l.get_data()
	var lo: int = _percentile(d, 0.96)
	var hi: int = _percentile(d, 0.995)
	for i: int in d.size():
		d[i] = int(255.0 * clampf(float(d[i] - lo) / float(maxi(hi - lo, 1)), 0.0, 1.0))
	return Image.create_from_data(l.get_width(), l.get_height(), false, Image.FORMAT_L8, d)


static func _percentile(d: PackedByteArray, q: float) -> int:
	var hist: PackedInt32Array = PackedInt32Array()
	hist.resize(256)
	for v: int in d:
		hist[v] += 1
	var target: int = int(float(d.size()) * q)
	var acc: int = 0
	for v: int in 256:
		acc += hist[v]
		if acc >= target:
			return v
	return 255
