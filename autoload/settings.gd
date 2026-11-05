extends Node
## Настройки игрока (user://settings.cfg) и раскладка клавиш по умолчанию.

const PATH_DEFAULT: String = "user://settings.cfg"
const DEFAULTS: Dictionary = {
	"audio": {"Master": 0.9, "Music": 0.7, "SFX": 0.85, "UI": 0.8, "Ambience": 0.6, "pack": "custom"},
	"video": {"window_mode": "windowed", "vsync": true, "preset": "high", "render_scale": 0.0, "fps_limit": 0, "ui_scale": 1.0},
	"gameplay": {"damage_numbers": true, "reduce_motion": false, "autostart_wave": false, "screen_shake": true, "cinematic_zoom": true,
		"hints": true, "flashes": true, "confirmations": true},
	"accessibility": {"colorblind": false, "text_scale": 1.0, "sound_captions": false},
	"general": {"locale": "", "player_name": "", "tutorial_done": false, "hints_seen": [], "pinned_recipe": "", "pinned_recipes": [], "last_ip": "",
		"run_length": 0, "log_collapsed": false},
}
## Сколько рецептов можно отслеживать одновременно (место в HUD).
const MAX_PINNED: int = 4
## Действие → клавиши (Key). Переназначение — через секцию [input] (этап 6).
const BINDINGS: Dictionary = {
	"confirm": [KEY_SPACE],
	"select_1": [KEY_1], "select_2": [KEY_2], "select_3": [KEY_3], "select_4": [KEY_4], "select_5": [KEY_5],
	"upgrade_luck": [KEY_U],
	"pause": [KEY_P],
	"restart": [KEY_R],
	"menu": [KEY_ESCAPE],
	"speed_down": [KEY_Z],
	"speed_up": [KEY_X],
	"camera_reset": [KEY_HOME],
	"show_ranges": [KEY_H],
	"combine": [KEY_C],
	"forge": [KEY_F],
	"break_wall": [KEY_B],
	"codex": [KEY_G],
	"forecast": [KEY_TAB],
	"show_hp": [KEY_ALT],
	"chat": [KEY_ENTER, KEY_KP_ENTER],
	"cam_left": [KEY_A, KEY_LEFT],
	"cam_right": [KEY_D, KEY_RIGHT],
	"cam_up": [KEY_W, KEY_UP],
	"cam_down": [KEY_S, KEY_DOWN],
}

var cfg: ConfigFile = ConfigFile.new()
## Автопрогоны и скриншоты используют отдельный файл, чтобы не менять настройки игрока.
var path: String = PATH_DEFAULT


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--autoplay" or arg.begins_with("--screenshot") or arg == "--bot":
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://dev"))
			path = "user://dev/settings_%d.cfg" % OS.get_process_id() if arg == "--bot" else "user://dev/settings.cfg"
	cfg.load(path)
	_register_input()
	apply_locale()
	apply_video()
	apply_accessibility()


func get_value(section: String, key: String) -> Variant:
	var fallback: Variant = (DEFAULTS.get(section, {}) as Dictionary).get(key)
	var v: Variant = cfg.get_value(section, key, fallback)
	if fallback == null or typeof(v) == typeof(fallback):
		return v
	# 60 и 60.0 — одно и то же (слайдеры пишут float); остальное — файл правили руками: берём значение по умолчанию.
	if fallback is float and v is int:
		return float(v)
	if fallback is int and v is float:
		return int(v)
	return fallback


func set_value(section: String, key: String, value: Variant) -> void:
	cfg.set_value(section, key, value)
	save()
	match section:
		"video":
			apply_video()
		"accessibility":
			apply_accessibility()
		"general":
			if key == "locale":
				apply_locale()
	Events.settings_changed.emit(section)


## Атомарная запись: во временный файл, затем переименование (сбой посреди записи не портит настройки).
func save() -> void:
	var tmp: String = path + ".tmp"
	var err: Error = cfg.save(tmp)
	if err == OK:
		err = DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("Не удалось сохранить настройки: " + error_string(err))


func reduce_motion() -> bool:
	return bool(get_value("gameplay", "reduce_motion"))


## Тряска камеры: отключается отдельно или вместе с «уменьшить анимации».
func screen_shake() -> bool:
	return bool(get_value("gameplay", "screen_shake")) and not reduce_motion()


## Кинематографичный зум при создании спец-башни.
func cinematic_zoom() -> bool:
	return bool(get_value("gameplay", "cinematic_zoom")) and not reduce_motion()


## Отслеживаемые рецепты (id спец-башен) в порядке закрепления, не больше MAX_PINNED.
## Прежнее одиночное значение pinned_recipe читается как первый элемент списка.
func pinned_recipes() -> Array[String]:
	var out: Array[String] = []
	var legacy: String = String(get_value("general", "pinned_recipe"))
	if not legacy.is_empty():
		out.append(legacy)
	for v: Variant in get_value("general", "pinned_recipes"):
		if v is String and not String(v).is_empty() and not out.has(String(v)):
			out.append(String(v))
	return out.slice(0, MAX_PINNED)


## Закрепляет или открепляет рецепт. Если список полон — снимается самый старый; его id возвращается.
func set_recipe_pinned(id: String, on: bool) -> String:
	var list: Array[String] = pinned_recipes()
	var dropped: String = ""
	if on and not list.has(id):
		list.append(id)
		if list.size() > MAX_PINNED:
			dropped = list.pop_front()
	elif not on:
		list.erase(id)
	cfg.set_value("general", "pinned_recipe", "")
	set_value("general", "pinned_recipes", list)
	return dropped


## Заменяет отслеживаемый рецепт другим на том же месте списка (предложение трекера).
func replace_pinned_recipe(old_id: String, new_id: String) -> void:
	var list: Array[String] = pinned_recipes()
	var i: int = list.find(old_id)
	if i < 0 or list.has(new_id):
		return
	list[i] = new_id
	cfg.set_value("general", "pinned_recipe", "")
	set_value("general", "pinned_recipes", list)


func player_name() -> String:
	var n: String = String(get_value("general", "player_name")).strip_edges()
	return n if not n.is_empty() else tr("DEFAULT_PLAYER_NAME")


func apply_locale() -> void:
	var loc: String = String(get_value("general", "locale"))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--locale="):
			loc = arg.substr(9)
	if loc.is_empty():
		loc = "ru" if OS.get_locale_language() == "ru" else "en"
	TranslationServer.set_locale(loc)
	Events.locale_changed.emit(loc)


## Палитра для дальтоников и масштаб текста (доступность).
func apply_accessibility() -> void:
	UiTokens.colorblind = bool(get_value("accessibility", "colorblind"))
	ThemeBuilder.apply_text_scale(clampf(float(get_value("accessibility", "text_scale")), 0.8, 1.6))


## Вспышки экрана (потеря жизни, хроматическая аберрация у боссов).
func flashes() -> bool:
	return bool(get_value("gameplay", "flashes")) and not reduce_motion()


func apply_video() -> void:
	if DisplayServer.get_name() == "headless":
		return
	get_tree().root.content_scale_factor = clampf(float(get_value("video", "ui_scale")), 0.7, 1.6)
	Engine.max_fps = int(get_value("video", "fps_limit"))
	Graphics.apply_viewport(get_tree().root)
	var mode: String = String(get_value("video", "window_mode"))
	match mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(get_value("video", "vsync")) else DisplayServer.VSYNC_DISABLED)


## Клавиши действия из [input]; испорченная запись (не массив кодов клавиш) заменяется раскладкой по умолчанию.
func keys_for(action: String) -> Array:
	var v: Variant = cfg.get_value("input", action, BINDINGS[action])
	if not (v is Array):
		return BINDINGS[action].duplicate()
	for k: Variant in v:
		if not (k is int or k is float):
			return BINDINGS[action].duplicate()
	return v


func _register_input() -> void:
	for action: String in BINDINGS.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var keys: Array = keys_for(action)
		for k: Variant in keys:
			var ev: InputEventKey = InputEventKey.new()
			ev.physical_keycode = int(k) as Key
			InputMap.action_add_event(action, ev)


## Переназначение: основная клавиша действия заменяется; если клавиша была у другого действия,
## она у него снимается (дополнительные клавиши, например стрелки камеры, сохраняются).
func set_binding(action: String, keycode: Key) -> String:
	var taken_by: String = ""
	for other: String in BINDINGS.keys():
		if other == action:
			continue
		var keys: Array = keys_for(other).duplicate()
		if keys.has(int(keycode)):
			keys.erase(int(keycode))
			cfg.set_value("input", other, keys)
			taken_by = other
	var mine: Array = keys_for(action).duplicate()
	if mine.is_empty():
		mine.append(int(keycode))
	else:
		mine[0] = int(keycode)
	cfg.set_value("input", action, mine)
	save()
	_register_input()
	Events.settings_changed.emit("input")
	return taken_by


func reset_bindings() -> void:
	if cfg.has_section("input"):
		cfg.erase_section("input")
	save()
	_register_input()
	Events.settings_changed.emit("input")


## Подпись клавиши для подсказок на кнопках.
func key_label(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k: InputEventKey = ev
			if DisplayServer.get_name() == "headless":
				return OS.get_keycode_string(k.physical_keycode)
			var code: Key = DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode)
			return OS.get_keycode_string(code if code != KEY_NONE else k.physical_keycode)
	return ""
