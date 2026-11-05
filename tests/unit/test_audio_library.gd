extends TestCase

const ROOT: String = "user://test_audio"


func _wav(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var w: AudioStreamWAV = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(2200)
	w.data = bytes
	w.save_to_wav(ProjectSettings.globalize_path(path))


func _clean() -> void:
	var abs_root: String = ProjectSettings.globalize_path(ROOT)
	if DirAccess.dir_exists_absolute(abs_root):
		OS.move_to_trash(abs_root)


func _lib(sources: Array[Dictionary]) -> AudioLibrary:
	var lib: AudioLibrary = AudioLibrary.new()
	lib.manifest = {
		"defaults": {"bus": "SFX", "volume_db": 0.0, "mode": "replace", "fallback": ""},
		"events": {"sfx/a": {}, "sfx/b": {"fallback": "sfx/a"}, "sfx/c": {}},
	}
	lib.sources = sources
	lib.resolve_all()
	return lib


func test_builtin_pack_resolves_every_manifest_event() -> void:
	var lib: AudioLibrary = AudioLibrary.new()
	assert_true(lib.load_manifest("res://audio/audio_manifest.json"))
	lib.sources = [{"name": "builtin", "root": "res://audio", "builtin": true}] as Array[Dictionary]
	lib.resolve_all()
	for row: Dictionary in lib.report():
		assert_false(row["missing"], "нет звука для " + String(row["id"]))
	assert_eq(lib.streams_for("sfx/gems/ruby/attack").size(), 3)


func test_override_replaces_lower_priority() -> void:
	_clean()
	_wav(ROOT + "/pack/sfx/a/mine.wav")
	_wav(ROOT + "/base/sfx/a/x.wav")
	_wav(ROOT + "/base/sfx/a/y.wav")
	var lib: AudioLibrary = _lib([
		{"name": "pack", "root": ProjectSettings.globalize_path(ROOT + "/pack"), "builtin": false},
		{"name": "base", "root": ProjectSettings.globalize_path(ROOT + "/base"), "builtin": false},
	] as Array[Dictionary])
	assert_eq(lib.streams_for("sfx/a").size(), 1, "override должен заменить встроенные")
	assert_eq(String(lib.events["sfx/a"]["source"]), "pack")
	_clean()


func test_append_mode_and_event_config() -> void:
	_clean()
	_wav(ROOT + "/pack/sfx/a/mine.wav")
	var f: FileAccess = FileAccess.open(ROOT + "/pack/sfx/a/_event.json", FileAccess.WRITE)
	f.store_string('{"mode": "append", "volume_db": -3.5}')
	f.close()
	_wav(ROOT + "/base/sfx/a/x.wav")
	var lib: AudioLibrary = _lib([
		{"name": "pack", "root": ProjectSettings.globalize_path(ROOT + "/pack"), "builtin": false},
		{"name": "base", "root": ProjectSettings.globalize_path(ROOT + "/base"), "builtin": false},
	] as Array[Dictionary])
	assert_eq(lib.streams_for("sfx/a").size(), 2, "append добавляет к встроенным")
	assert_near(float(lib.params_for("sfx/a")["volume_db"]), -3.5)
	_clean()


func test_empty_override_falls_through_and_fallback_works() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT + "/pack/sfx/a"))
	_wav(ROOT + "/base/sfx/a/x.wav")
	var lib: AudioLibrary = _lib([
		{"name": "pack", "root": ProjectSettings.globalize_path(ROOT + "/pack"), "builtin": false},
		{"name": "base", "root": ProjectSettings.globalize_path(ROOT + "/base"), "builtin": false},
	] as Array[Dictionary])
	assert_eq(String(lib.events["sfx/a"]["source"]), "base", "пустая папка = встроенный звук")
	assert_eq(lib.streams_for("sfx/b").size(), 1, "sfx/b берёт fallback sfx/a")
	assert_true(lib.streams_for("sfx/c").is_empty())
	var missing: int = 0
	for row: Dictionary in lib.report():
		if row["missing"]:
			missing += 1
	assert_eq(missing, 1)
	_clean()
