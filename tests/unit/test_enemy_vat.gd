extends TestCase
## Модели врагов с VAT (tools/bake_enemy_vat.gd): меш в бюджете треугольников, основание на земле,
## адреса вершин внутри VAT, позы по кадрам действительно разные, у материала есть карты атласа.

## До ~300 рядовых на поле (и столько же в проходе теней), боссы — по одному.
const MAX_TRIS: int = 2300
const MAX_TRIS_BOSS: int = 6200


func test_every_archetype_has_a_vat_model() -> void:
	for id: String in data().archetypes.keys():
		assert_true(ArtKit.ENEMY_MODELS.has(id), "у архетипа %s нет модели в ArtKit.ENEMY_MODELS" % id)


func test_vat_models_fit_the_contract() -> void:
	for id: String in ArtKit.ENEMY_MODELS:
		var m: ArrayMesh = ArtKit.enemy_vat(id)
		assert_true(m != null, "нет VAT-модели для %s" % id)
		if m == null:
			continue
		assert_eq(m.get_surface_count(), 1, "%s: все материалы в одном атласе" % id)
		var arrays: Array = m.surface_get_arrays(0)
		var tris: int = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var budget: int = MAX_TRIS_BOSS if bool(data().archetypes[id]["boss"]) else MAX_TRIS
		# Нижняя граница — кристаллы Раскольника: шестигранники с плоскими гранями.
		assert_true(tris >= 60 and tris <= budget, "%s: %d треугольников" % [id, tris])
		assert_true(float(m.get_meta("height", 0.0)) > 0.1, "%s: нет высоты" % id)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var box: AABB = AABB(verts[0], Vector3.ZERO)
		for v: Vector3 in verts:
			box = box.expand(v)
		assert_near(box.position.y, 0.0, 0.01, "%s стоит на земле" % id)
		assert_true(absf(box.get_center().x) < 0.3 and absf(box.get_center().z) < 0.3, "%s по центру клетки" % id)
		assert_true(m.custom_aabb.grow(0.001).encloses(box), "%s: охват анимации включает позу кадра 0" % id)
		var pos: Image = (m.get_meta("vat_pos") as Texture2D).get_image()
		var nrm: Texture2D = m.get_meta("vat_nrm")
		var rows: int = int(m.get_meta("rows", 0))
		var loop_n: int = int(m.get_meta("loop_frames", 0))
		var death_n: int = int(m.get_meta("death_frames", 0))
		assert_true(rows >= 1 and loop_n >= 8, "%s: кадров цикла %d" % [id, loop_n])
		assert_eq(pos.get_height(), (loop_n + death_n) * rows, "%s: высота VAT = кадры × строки" % id)
		assert_eq(Vector2i(nrm.get_width(), nrm.get_height()), pos.get_size(), "%s: VAT нормалей того же размера" % id)
		assert_true(float(m.get_meta("loop_time", 0.0)) > 0.0, "%s: длительность цикла" % id)
		if death_n > 0:
			assert_true(float(m.get_meta("death_time", 0.0)) > 0.0, "%s: длительность клипа смерти" % id)
		var addr: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var inside: bool = true
		for a: Vector2 in addr:
			if a.x != floorf(a.x) or a.y != floorf(a.y) or a.x >= pos.get_width() or a.y >= rows:
				inside = false
				break
		assert_true(inside, "%s: адреса вершин (UV2) — целые и внутри VAT" % id)
		# Позы четверти и середины цикла отличаются от первого кадра — анимация действительно запечена
		# (у осколка два прыжка за цикл, его середина совпадает с началом).
		var moved: float = 0.0
		for f: int in [loop_n / 4, loop_n / 2]:
			for x: int in pos.get_width():
				var p0: Color = pos.get_pixel(x, 0)
				var p1: Color = pos.get_pixel(x, f * rows)
				moved = maxf(moved, Vector3(p0.r - p1.r, p0.g - p1.g, p0.b - p1.b).length())
		assert_true(moved > 0.02, "%s: кадры цикла различаются (%.3f)" % [id, moved])


func test_vat_materials_have_atlas_maps() -> void:
	for id: String in ArtKit.ENEMY_MODELS:
		var m: ArrayMesh = ArtKit.enemy_vat(id)
		if m == null:
			continue
		var mat: ShaderMaterial = ArtKit.enemy_vat_material(m)
		for p: String in ["vat_pos", "vat_nrm", "albedo_tex", "orm_tex"]:
			assert_true(mat.get_shader_parameter(p) != null, "%s: нет %s" % [id, p])
		# Атласа нормалей нет, если у исходника не было карт нормалей (рыцарь): шейдер берёт плоскую нормаль.
		var nrm: String = "res://assets/textures/characters/%s_normal.jpg" % m.resource_name
		assert_eq(mat.get_shader_parameter("normal_tex") != null, ResourceLoader.exists(nrm), "%s: normal_tex и файл атласа" % id)
		assert_eq(int(mat.get_shader_parameter("loop_frames")), int(m.get_meta("loop_frames")), "%s: кадры цикла в материале" % id)


## Шаг цикла: ручная подстройка ArtKit.ENEMY_LOOK или замер бейкера (мета stride) — у шагающих он есть всегда.
func test_walkers_have_stride() -> void:
	for id: String in ArtKit.ENEMY_MODELS:
		var m: ArrayMesh = ArtKit.enemy_vat(id)
		if m == null or ArtKit.enemy_look(m.resource_name).has("flap"):
			continue
		var own: bool = (ArtKit.ENEMY_LOOK.get(m.resource_name, {}) as Dictionary).has("stride")
		assert_true(own or m.has_meta("stride"), "%s: нет ни подстройки шага, ни замера" % id)
		assert_true(ArtKit.enemy_stride(m) > 0.1, "%s: шаг %.2f" % [id, ArtKit.enemy_stride(m)])
