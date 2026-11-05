extends SceneTree
## Запуск: godot --headless --path . -s res://tests/run_all.gd [-- --filter=имя]
## Код выхода 1 при любом провале.

const DIRS: Array[String] = ["res://tests/unit", "res://tests/integration"]


func _initialize() -> void:
	var filter: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.substr(9)
	var total: int = 0
	var failed: int = 0
	var started: int = Time.get_ticks_msec()
	for dir: String in DIRS:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var files: PackedStringArray = DirAccess.get_files_at(dir)
		files.sort()
		for file: String in files:
			if not file.ends_with(".gd") or not file.begins_with("test_"):
				continue
			var script: GDScript = load("%s/%s" % [dir, file]) as GDScript
			if script == null:
				print("✗ не удалось загрузить %s" % file)
				failed += 1
				continue
			var inst: Object = script.new()
			for m: Dictionary in script.get_script_method_list():
				var name: String = m["name"]
				if not name.begins_with("test_"):
					continue
				if not filter.is_empty() and not (file + "::" + name).contains(filter):
					continue
				total += 1
				inst.set("current_test", "%s::%s" % [file.get_basename(), name])
				var before: int = (inst.get("failures") as PackedStringArray).size()
				var t0: int = Time.get_ticks_msec()
				inst.call(name)
				var fails: PackedStringArray = inst.get("failures")
				if fails.size() > before:
					failed += 1
					print("✗ %s::%s" % [file.get_basename(), name])
					for i: int in range(before, fails.size()):
						print("    " + fails[i])
				else:
					print("✓ %s::%s (%d мс)" % [file.get_basename(), name, Time.get_ticks_msec() - t0])
	print("")
	print("Итого: %d тестов, провалено %d, %.1f с" % [total, failed, float(Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if failed > 0 or total == 0 else 0)
