extends Node
## Аудио-менеджер. Код игры знает только id событий: Audio.play("sfx/ui/click").
## Файлы ищутся по папкам (см. AudioLibrary и docs/AUDIO_MODDING.md):
##   1) --audio-dir=<путь>  2) <папка рядом с .app>/audio_override  3) user://sound_packs/<пак>  4) res://audio

const MANIFEST_PATH: String = "res://audio/audio_manifest.json"
const BUILTIN_ROOT: String = "res://audio"
const PACKS_ROOT: String = "user://sound_packs"
const POOL_SIZE: int = 40
const README_NAME: String = "README.txt"
## Кроссфейд музыкальных состояний, секунд (§9.4: 1–2 с).
const MUSIC_FADE: float = 1.5
## Панорама боевых звуков: лево / право — отдельные шины с панорамированием, отправка в SFX.
const PAN_BUSES: Dictionary = {"SFX_L": -0.45, "SFX_R": 0.45}

## Сыграно событие (для визуальных подсказок к звукам — доступность).
signal played(id: String)

var library: AudioLibrary = AudioLibrary.new()
var _pool: Array[AudioStreamPlayer] = []
## Учёт голосов пула (свободные, звучащие, приоритет важных звуков) — см. VoicePool.
var voices: VoicePool
var _last_ms: Dictionary = {}
var _last_index: Dictionary = {}
var _loops: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Headless-режим (автотесты, бот): звук не воспроизводится — фиктивный драйвер не освобождает потоки.
var _silent: bool = false
## Музыка: два плеера для кроссфейда, текущее состояние (menu, build, combat, boss, victory, defeat).
var _music: Array[AudioStreamPlayer] = []
var _music_active: int = 0
var music_state: String = ""
## Прослушивание события в звуковом браузере (музыка и звуки — через один плеер).
var _preview: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_silent = DisplayServer.get_name() == "headless"
	_rng.randomize()
	_ensure_buses()
	for i: int in POOL_SIZE:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		add_child(p)
		p.tree_exiting.connect(func() -> void:
			p.stop()
			p.stream = null)
		_pool.append(p)
	voices = VoicePool.new(_pool)
	for p2: AudioStreamPlayer in _pool:
		p2.finished.connect(voices.release.bind(p2))
	for i2: int in 2:
		var mp: AudioStreamPlayer = AudioStreamPlayer.new()
		mp.name = "Music%d" % i2
		mp.bus = "Music"
		add_child(mp)
		_music.append(mp)
	_preview = AudioStreamPlayer.new()
	_preview.name = "Preview"
	add_child(_preview)
	library.load_manifest(MANIFEST_PATH)
	ensure_user_pack(active_pack())
	reload()
	apply_volumes()
	Events.settings_changed.connect(_on_settings_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop_all()


## Останавливает все звуки и отпускает потоки (перед выходом из игры).
func stop_all() -> void:
	for p: AudioStreamPlayer in _pool:
		p.stop()
		p.stream = null
	if voices != null:
		voices.reset()
	for mp: AudioStreamPlayer in _music:
		mp.stop()
		mp.stream = null
	if _preview != null:
		_preview.stop()
		_preview.stream = null
	music_state = ""
	for id: String in _loops.keys():
		var lp: AudioStreamPlayer = _loops[id]
		lp.stop()
		lp.stream = null
		lp.queue_free()
	_loops.clear()


func _exit_tree() -> void:
	# Останавливаем воспроизведение, иначе AudioServer держит поток до выхода (leak at exit).
	for p: AudioStreamPlayer in _pool:
		p.stop()
		p.stream = null
	for mp: AudioStreamPlayer in _music:
		mp.stop()
		mp.stream = null
	for id: String in _loops.keys():
		var lp: AudioStreamPlayer = _loops[id]
		lp.stop()
		lp.stream = null
	_loops.clear()
	library.events.clear()


func active_pack() -> String:
	return String(Settings.get_value("audio", "pack"))


func pack_dir(pack: String) -> String:
	return ProjectSettings.globalize_path(PACKS_ROOT.path_join(pack))


func available_packs() -> PackedStringArray:
	var root: String = ProjectSettings.globalize_path(PACKS_ROOT)
	var out: PackedStringArray = PackedStringArray()
	if DirAccess.dir_exists_absolute(root):
		out = DirAccess.get_directories_at(root)
	if not out.has("custom"):
		out.append("custom")
	out.sort()
	return out


func source_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--audio-dir="):
			out.append({"name": "cli", "root": arg.substr(12), "builtin": false})
	if OS.has_feature("template"):
		# Экспортированная сборка: <папка>/Gem Tower Defense.app/Contents/MacOS/<exe>
		var exe_dir: String = OS.get_executable_path().get_base_dir()
		var portable: String = exe_dir.path_join("../../..").simplify_path().path_join("audio_override") if OS.get_name() == "macOS" else exe_dir.path_join("audio_override")
		out.append({"name": "portable", "root": portable, "builtin": false})
	out.append({"name": "pack:" + active_pack(), "root": pack_dir(active_pack()), "builtin": false})
	out.append({"name": "builtin", "root": BUILTIN_ROOT, "builtin": true})
	return out


## Перечитывает все папки без перезапуска игры.
func reload() -> void:
	library.sources = source_list()
	library.resolve_all()
	for id: String in _loops.keys():
		var p: AudioStreamPlayer = _loops[id]
		var streams: Array[AudioStream] = library.streams_for(id)
		if not streams.is_empty():
			p.stream = streams[0]
			p.play()
	if not music_state.is_empty():
		var state: String = music_state
		music_state = ""
		music(state)
	Events.audio_reloaded.emit(library.report())


## Звуковое событие. pan — положение источника по горизонтали экрана (−1 слева … 1 справа),
## используется для боевых звуков; звуки интерфейса не панорамируются.
func play(id: String, volume_offset_db: float = 0.0, pitch: float = 1.0, pan: float = 0.0) -> void:
	played.emit(id)
	if _silent or voices == null:
		return
	# Антиспам первым: в большом бою большинство вызовов отсекается здесь, без поиска потоков.
	var params: Dictionary = library.params_for(id)
	var now: int = Time.get_ticks_msec()
	var cooldown: int = int(params.get("cooldown_ms", 0))
	if cooldown > 0 and now - int(_last_ms.get(id, -100000)) < cooldown:
		return
	if voices.active(id) >= int(params.get("max_voices", 4)):
		return
	var streams: Array[AudioStream] = library.streams_for(id)
	if streams.is_empty():
		return
	var player: AudioStreamPlayer = voices.take(id)
	if player == null:
		return
	_last_ms[id] = now
	var index: int = _pick_index(id, streams.size())
	player.stream = streams[index]
	var bus: String = String(params.get("bus", "SFX"))
	if bus == "SFX" and absf(pan) > 0.34:
		bus = "SFX_L" if pan < 0.0 else "SFX_R"
	player.bus = bus
	player.volume_db = float(params.get("volume_db", 0.0)) + volume_offset_db
	var jitter: float = float(params.get("pitch_jitter", 0.0))
	player.pitch_scale = pitch * (1.0 + _rng.randf_range(-jitter, jitter))
	voices.claim(player, id)
	player.play()


## Зацикленное событие (эмбиент). Повторяет поток по окончании — работает с любым форматом.
func play_loop(id: String) -> void:
	if _loops.has(id) or _silent:
		return
	var streams: Array[AudioStream] = library.streams_for(id)
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.name = "Loop_" + id.replace("/", "_")
	var params: Dictionary = library.params_for(id)
	p.bus = String(params.get("bus", "Ambience"))
	p.volume_db = float(params.get("volume_db", 0.0))
	add_child(p)
	p.finished.connect(p.play)
	p.tree_exiting.connect(func() -> void:
		p.stop()
		p.stream = null)
	_loops[id] = p
	if not streams.is_empty():
		p.stream = streams[0]
		p.play()


## Музыкальное состояние: menu, build, combat, boss, victory, defeat — с кроссфейдом.
## Победа и поражение играют один раз; остальные треки зациклены.
func music(state: String) -> void:
	if _silent or state == music_state:
		return
	music_state = state
	var cur: AudioStreamPlayer = _music[_music_active]
	if cur.playing:
		var out: Tween = create_tween()
		out.tween_property(cur, "volume_db", -60.0, MUSIC_FADE)
		out.tween_callback(cur.stop)
	var id: String = "music/" + state
	var streams: Array[AudioStream] = library.streams_for(id)
	if streams.is_empty():
		return
	var params: Dictionary = library.params_for(id)
	var stream: AudioStream = streams[_pick_index(id, streams.size())]
	_set_loop(stream, bool(params.get("loop", true)))
	_music_active = 1 - _music_active
	var next: AudioStreamPlayer = _music[_music_active]
	next.stream = stream
	next.bus = String(params.get("bus", "Music"))
	next.volume_db = -60.0
	next.play()
	var fade: Tween = create_tween()
	fade.tween_property(next, "volume_db", float(params.get("volume_db", 0.0)), MUSIC_FADE)


static func _set_loop(stream: AudioStream, loop: bool) -> void:
	if stream is AudioStreamWAV:
		var w: AudioStreamWAV = stream
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		w.loop_begin = 0
		var bytes_per_frame: int = (2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if w.stereo else 1)
		w.loop_end = w.data.size() / bytes_per_frame if w.format != AudioStreamWAV.FORMAT_IMA_ADPCM and w.format != AudioStreamWAV.FORMAT_QOA else 0
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = loop


## Прослушать событие целиком (звуковой браузер): следующий вариант, без антиспама.
func preview(id: String) -> void:
	if _silent:
		return
	var streams: Array[AudioStream] = library.streams_for(id)
	_preview.stop()
	if streams.is_empty():
		return
	var params: Dictionary = library.params_for(id)
	var stream: AudioStream = streams[_pick_index("preview:" + id, streams.size())]
	if id.begins_with("music/"):
		_set_loop(stream, false)
	_preview.stream = stream
	_preview.bus = String(params.get("bus", "SFX"))
	_preview.volume_db = float(params.get("volume_db", 0.0))
	_preview.play()


func stop_preview() -> void:
	_preview.stop()


func stop_loop(id: String) -> void:
	if not _loops.has(id):
		return
	var p: AudioStreamPlayer = _loops[id]
	_loops.erase(id)
	var tw: Tween = create_tween()
	tw.tween_property(p, "volume_db", -60.0, 0.6)
	tw.tween_callback(p.queue_free)


func _pick_index(id: String, count: int) -> int:
	if count <= 1:
		return 0
	var last: int = int(_last_index.get(id, -1))
	var i: int = _rng.randi_range(0, count - 2)
	if i >= last:
		i += 1
	i = clampi(i, 0, count - 1)
	_last_index[id] = i
	return i


func _ensure_buses() -> void:
	for bus: String in ["Music", "SFX", "UI", "Ambience"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var idx: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")
	for pan_bus: String in PAN_BUSES.keys():
		if AudioServer.get_bus_index(pan_bus) == -1:
			AudioServer.add_bus()
			var pi: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(pi, pan_bus)
			AudioServer.set_bus_send(pi, "SFX")
			var panner: AudioEffectPanner = AudioEffectPanner.new()
			panner.pan = float(PAN_BUSES[pan_bus])
			AudioServer.add_bus_effect(pi, panner)


func apply_volumes() -> void:
	for bus: String in ["Master", "Music", "SFX", "UI", "Ambience"]:
		var idx: int = AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		var lin: float = clampf(float(Settings.get_value("audio", bus)), 0.0, 1.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(lin, 0.0001)))
		AudioServer.set_bus_mute(idx, lin <= 0.001)


func _on_settings_changed(section: String) -> void:
	if section == "audio":
		apply_volumes()


## Создаёт дерево пустых папок событий и README, чтобы игроку было куда класть файлы.
func ensure_user_pack(pack: String) -> void:
	var root: String = pack_dir(pack)
	DirAccess.make_dir_recursive_absolute(root)
	for id: String in library.event_ids():
		DirAccess.make_dir_recursive_absolute(root.path_join(id))
	# README переписывается каждый запуск: список событий растёт вместе с игрой.
	var f: FileAccess = FileAccess.open(root.path_join(README_NAME), FileAccess.WRITE)
	if f != null:
		f.store_string(_readme_text())


func open_sounds_folder() -> void:
	ensure_user_pack(active_pack())
	OS.shell_open(pack_dir(active_pack()))


func report() -> Array[Dictionary]:
	return library.report()


func print_report() -> void:
	var missing: int = 0
	print("Аудио-источники (по приоритету):")
	for s: Dictionary in library.sources:
		print("  %-14s %s" % [s["name"], s["root"]])
	print("")
	print("%-40s %-16s %s" % ["Событие", "Источник", "Файлов"])
	for row: Dictionary in library.report():
		var src: String = String(row["source"]) if not String(row["source"]).is_empty() else ("fallback→" + String(row["fallback"]) if not String(row["fallback"]).is_empty() else "—")
		print("%-40s %-16s %d%s" % [row["id"], src, row["files"], "   ПРОПУСК" if row["missing"] else ""])
		if row["missing"]:
			missing += 1
	print("")
	print("Событий: %d, без звука: %d" % [library.report().size(), missing])


func _readme_text() -> String:
	var lines: PackedStringArray = PackedStringArray([
		"Gem Tower Defense — пользовательский звуковой пак",
		"",
		"Каждая папка — одно звуковое событие. Положите в неё один или несколько файлов",
		".ogg / .wav / .mp3 — они заменят встроенные звуки (если файлов несколько,",
		"игра выбирает случайный, не повторяя подряд). Пустая папка = встроенный звук.",
		"",
		"Чтобы добавить свои варианты к встроенным, положите в папку _event.json:",
		'  {"mode": "append"}',
		"В _event.json также можно задать: volume_db, pitch_jitter, cooldown_ms, max_voices, bus.",
		"",
		"После замены нажмите «Перезагрузить звуки» в Настройки → Звук (перезапуск не нужен).",
		"Звуковой браузер там же показывает источник каждого события и даёт его прослушать.",
		"",
		"--- English ---",
		"Every folder is one sound event. Put one or more .ogg / .wav / .mp3 files into it —",
		"they replace the built-in sound (with several files the game picks a random one,",
		"never the same twice in a row). An empty folder means the built-in sound.",
		"To add your variants to the built-in ones, put _event.json into the folder:",
		'  {"mode": "append"}',
		"_event.json may also set volume_db, pitch_jitter, cooldown_ms, max_voices, bus.",
		"Then press «Reload sounds» in Settings → Sound (no restart needed); the sound browser",
		"there shows the source of every event and lets you listen to it.",
		"",
		"События / Events:",
	])
	for id: String in library.event_ids():
		lines.append("  " + id)
	return "\n".join(lines) + "\n"
