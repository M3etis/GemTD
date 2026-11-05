extends TestCase
## Код игры не зависит от папок, исключённых из экспорта (tests/, tools/, docs/ — см. export_presets.cfg).
## Иначе в редакторе всё работает, а в собранном .app скрипт не компилируется и сцена не грузится.

## Пути в исключённых папках, которые игра грузит только в служебных режимах из редактора.
const ALLOWED_PATHS: Array[String] = ["res://tests/perf/perf_stress.gd", "res://docs/screenshots"]


func _excluded_dirs() -> PackedStringArray:
	var cfg: ConfigFile = ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK, "нет export_presets.cfg")
	var out: PackedStringArray = PackedStringArray()
	for f: String in String(cfg.get_value("preset.0", "exclude_filter", "")).split(",", false):
		var d: String = f.strip_edges().trim_suffix("/*")
		if not d.contains("*") and DirAccess.dir_exists_absolute("res://" + d):
			out.append(d)
	return out


func _files(dir: String, exts: Array[String], skip: PackedStringArray, out: PackedStringArray) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		var rel: String = dir.path_join(sub).trim_prefix("res://")
		if not sub.begins_with(".") and not skip.has(rel):
			_files(dir.path_join(sub), exts, skip, out)
	for f: String in DirAccess.get_files_at(dir):
		if exts.has(f.get_extension()):
			out.append(dir.path_join(f))


## Текст скрипта без комментариев: имя класса в комментарии не ломает экспорт.
func _code(path: String) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		var hash_at: int = line.find("#")
		lines.append(line if hash_at < 0 else line.substr(0, hash_at))
	return "\n".join(lines)


func test_excluded_dirs_are_known() -> void:
	var dirs: PackedStringArray = _excluded_dirs()
	assert_true(dirs.has("tests") and dirs.has("tools"), "tests/ и tools/ должны быть исключены из экспорта: %s" % [dirs])


func test_runtime_does_not_use_excluded_classes() -> void:
	var excluded: PackedStringArray = _excluded_dirs()
	var dev_scripts: PackedStringArray = PackedStringArray()
	for d: String in excluded:
		_files("res://" + d, ["gd"], PackedStringArray(), dev_scripts)
	var classes: PackedStringArray = PackedStringArray()
	for path: String in dev_scripts:
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			if line.begins_with("class_name "):
				classes.append(line.substr(11).strip_edges().split(" ")[0])
	assert_true(classes.size() >= 2, "не нашлись class_name в исключённых папках")
	var runtime: PackedStringArray = PackedStringArray()
	_files("res://", ["gd"], excluded, runtime)
	var regex: RegEx = RegEx.create_from_string("\\b(" + "|".join(classes) + ")\\b")
	for path: String in runtime:
		var m: RegExMatch = regex.search(_code(path))
		assert_true(m == null, "%s ссылается на %s из исключённой из экспорта папки" % [path, m.get_string() if m != null else ""])


func test_runtime_does_not_load_excluded_paths() -> void:
	var excluded: PackedStringArray = _excluded_dirs()
	var runtime: PackedStringArray = PackedStringArray()
	_files("res://", ["gd", "tscn", "tres"], excluded, runtime)
	for path: String in runtime:
		var text: String = _code(path) if path.ends_with(".gd") else FileAccess.get_file_as_string(path)
		for d: String in excluded:
			var at: int = text.find("res://" + d + "/")
			while at >= 0:
				var end: int = text.find("\"", at)
				var ref: String = text.substr(at, end - at)
				var ok: bool = false
				for allowed: String in ALLOWED_PATHS:
					ok = ok or ref.begins_with(allowed)
				assert_true(ok, "%s грузит %s — этого файла нет в экспорте" % [path, ref])
				at = text.find("res://" + d + "/", at + 1)
