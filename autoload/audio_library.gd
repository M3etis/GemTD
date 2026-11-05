class_name AudioLibrary
extends RefCounted
## Разрешение звуковых событий по папкам (§9 PROMPT.md).
## Событие = папка; все аудиофайлы в ней — варианты. Источники перебираются по приоритету,
## побеждает первый непустой; `_event.json` с "mode": "append" добавляет и следующие источники.

const EXTENSIONS: PackedStringArray = ["ogg", "wav", "mp3"]
const EVENT_CONFIG: String = "_event.json"
const MAX_FALLBACK_DEPTH: int = 4

var manifest: Dictionary = {}
## [{name, root, builtin}] — от высшего приоритета к встроенному паку.
var sources: Array[Dictionary] = []
## id → {streams, files, source, params}
var events: Dictionary = {}


func load_manifest(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("Audio: нет манифеста " + path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Audio: манифест повреждён " + path)
		return false
	manifest = parsed
	return true


func event_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray((manifest.get("events", {}) as Dictionary).keys())
	ids.sort()
	return ids


func resolve_all() -> void:
	events.clear()
	for id: String in event_ids():
		events[id] = resolve(id)


func resolve(id: String) -> Dictionary:
	var params: Dictionary = (manifest.get("defaults", {}) as Dictionary).duplicate()
	params.merge(manifest.get("events", {}).get(id, {}), true)
	var streams: Array[AudioStream] = []
	var files: PackedStringArray = PackedStringArray()
	var used_source: String = ""
	for src: Dictionary in sources:
		var dir: String = String(src["root"]).path_join(id)
		var found: PackedStringArray = list_audio_files(dir, bool(src["builtin"]))
		if found.is_empty():
			continue
		var cfg: Dictionary = read_event_config(dir)
		if used_source.is_empty():
			params.merge(cfg, true)
			used_source = String(src["name"])
		for f: String in found:
			var s: AudioStream = load_stream(dir.path_join(f), bool(src["builtin"]))
			if s != null:
				streams.append(s)
				files.append(dir.path_join(f))
		if String(cfg.get("mode", params.get("mode", "replace"))) != "append":
			break
	return {"streams": streams, "files": files, "source": used_source, "params": params}


## Варианты события с учётом fallback из манифеста.
func streams_for(id: String) -> Array[AudioStream]:
	var current: String = id
	for i: int in MAX_FALLBACK_DEPTH:
		var e: Dictionary = events.get(current, {})
		var arr: Array[AudioStream] = e.get("streams", [] as Array[AudioStream])
		if not arr.is_empty():
			return arr
		current = String(e.get("params", {}).get("fallback", ""))
		if current.is_empty():
			break
	return [] as Array[AudioStream]


func params_for(id: String) -> Dictionary:
	var e: Dictionary = events.get(id, {})
	if e.is_empty():
		var p: Dictionary = (manifest.get("defaults", {}) as Dictionary).duplicate()
		return p
	return e["params"]


func report() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in event_ids():
		var e: Dictionary = events.get(id, {})
		var count: int = (e.get("streams", []) as Array).size()
		# optional: событию можно молчать (во встроенном паке пусто, звук даёт только звуковой пак).
		var optional: bool = bool(params_for(id).get("optional", false))
		out.append({"id": id, "source": String(e.get("source", "")), "files": count,
			"fallback": String(e.get("params", {}).get("fallback", "")), "missing": count == 0 and streams_for(id).is_empty() and not optional})
	return out


static func list_audio_files(dir: String, builtin: bool) -> PackedStringArray:
	var names: PackedStringArray
	if builtin:
		if not DirAccess.dir_exists_absolute(dir):
			return PackedStringArray()
		names = ResourceLoader.list_directory(dir)
	else:
		if not DirAccess.dir_exists_absolute(dir):
			return PackedStringArray()
		names = DirAccess.get_files_at(dir)
	var out: PackedStringArray = PackedStringArray()
	for n: String in names:
		if n.ends_with("/") or n.begins_with("."):
			continue
		if EXTENSIONS.has(n.get_extension().to_lower()):
			out.append(n)
	out.sort()
	return out


static func read_event_config(dir: String) -> Dictionary:
	var path: String = dir.path_join(EVENT_CONFIG)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_warning("Audio: не удалось прочитать " + path)
	return {}


static func load_stream(path: String, builtin: bool) -> AudioStream:
	if builtin:
		return load(path) as AudioStream
	match path.get_extension().to_lower():
		"wav":
			return AudioStreamWAV.load_from_file(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
	return null
