extends TestCase
## Звуки, которые вызывает код, есть в манифесте (иначе событие молча не звучит и не видно в --audio-report).


func _manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://audio/audio_manifest.json"))
	return (parsed as Dictionary)["events"]


func _scripts(dir: String, out: PackedStringArray) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		if not sub.begins_with(".") and sub != "tests" and sub != "tools":
			_scripts(dir.path_join(sub), out)
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))


## Литеральные id из вызовов Audio.play / play_loop / music в коде игры (без шаблонов с %).
func _literal_ids(text: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for prefix: String in ["Audio.play(\"", "Audio.play_loop(\"", "Audio.music(\""]:
		var at: int = text.find(prefix)
		while at >= 0:
			var start: int = at + prefix.length()
			var end: int = text.find("\"", start)
			var id: String = text.substr(start, end - start)
			# Шаблоны (%s) и склейки ("sfx/traits/" + вид) проверяет test_dynamic_event_families_exist.
			if not id.contains("%") and not id.ends_with("/"):
				out.append(id if prefix != "Audio.music(\"" else "music/" + id)
			at = text.find(prefix, end)
	return out


func test_literal_events_exist() -> void:
	var events: Dictionary = _manifest()
	var files: PackedStringArray = PackedStringArray()
	_scripts("res://", files)
	var checked: int = 0
	for path: String in files:
		if path.ends_with("autoload/audio.gd"):
			continue
		for id: String in _literal_ids(FileAccess.get_file_as_string(path)):
			assert_true(events.has(id), "%s: нет события %s в манифесте" % [path.get_file(), id])
			checked += 1
	assert_true(checked > 50, "найдено вызовов: %d" % checked)


func test_dynamic_event_families_exist() -> void:
	var events: Dictionary = _manifest()
	var d: GameData = data()
	for arch: String in d.archetypes.keys():
		var a: Dictionary = d.archetype(arch)
		if bool(a["boss"]):
			continue
		for kind: String in ["death", "spawn", "hurt"]:
			assert_true(events.has("sfx/enemies/%s/%s" % [arch, kind]), "нет sfx/enemies/%s/%s" % [arch, kind])
	for sp: Dictionary in d.specials:
		var id: String = String(sp["id"])
		assert_true(events.has("sfx/specials/%s/upgrade" % id))
		if String(sp["attack"]) != "none":
			assert_true(events.has("sfx/specials/%s/attack" % id), "нет атаки " + id)
	for gem: String in d.gem_ids:
		assert_true(events.has("sfx/gems/%s/attack" % gem) and events.has("sfx/gems/%s/impact" % gem))
	for q: int in range(1, 6):
		assert_true(events.has("sfx/build/reveal/q%d" % q))
	# Виды заблокированных ударов и срабатываний трейтов (EnemyTraits._block / _proc).
	for kind: String in ["antimagic", "ethereal", "evasion", "refraction", "carapace", "blink", "rush", "hardening", "disarm", "thief"]:
		assert_true(events.has("sfx/traits/" + kind), "нет sfx/traits/" + kind)


func test_music_loop_flags() -> void:
	var events: Dictionary = _manifest()
	for name: String in MusicSynth.NAMES:
		var e: Dictionary = events.get("music/" + name, {})
		assert_false(e.is_empty(), "нет music/" + name)
		assert_eq(bool(e.get("loop", true)), MusicSynth.is_loop(name), "флаг петли music/" + name)
		assert_eq(String(e.get("bus", "")), "Music")
