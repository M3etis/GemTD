extends TestCase
## Хранение данных игрока (этап 7): настройки, сейвы, реплеи и таблица лидеров переживают порчу файлов
## без ошибок скрипта — с понятной причиной отказа или значениями по умолчанию.
## Все файлы — во временной папке user://dev/, настройки и рекорды игрока не трогаются.

const TMP_DIR: String = "user://dev/test_persistence"


func _tmp(file: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	var path: String = TMP_DIR.path_join(file)
	for suffix: String in ["", ".tmp", ".bak", ".corrupt"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	return path


func _write(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## Временно подменяет файл настроек.
func _with_settings(path: String, body: Callable) -> void:
	var old_path: String = Settings.path
	var old_cfg: ConfigFile = Settings.cfg
	Settings.path = path
	Settings.cfg = ConfigFile.new()
	Settings.cfg.load(path)
	body.call()
	Settings.path = old_path
	Settings.cfg = old_cfg


func _build_phase_sim() -> GameSim:
	var sim: GameSim = new_sim(91, {"max_waves": 3, "record_events": false})
	var bot: BotPlayer = BotPlayer.new(sim, "maze", 91)
	while sim.round_index < 2:
		if sim.phase == GameSim.Phase.COMBAT:
			sim.step()
		else:
			bot.act()
	return sim


func test_settings_roundtrip_is_atomic() -> void:
	var path: String = _tmp("settings.cfg")
	_with_settings(path, func() -> void:
		Settings.cfg.set_value("audio", "Music", 0.25)
		Settings.cfg.set_value("gameplay", "hints", false)
		Settings.cfg.set_value("general", "hints_seen", ["air_wave"])
		Settings.save()
		assert_false(FileAccess.file_exists(path + ".tmp"), "временный файл не остаётся")
		var again: ConfigFile = ConfigFile.new()
		assert_eq(again.load(path), OK)
		assert_near(float(again.get_value("audio", "Music")), 0.25)
		assert_eq(again.get_value("gameplay", "hints"), false)
		assert_eq(again.get_value("general", "hints_seen"), ["air_wave"]))


func test_hand_edited_settings_fall_back_to_defaults() -> void:
	var path: String = _tmp("settings_bad.cfg")
	_write(path, "[video]\nvsync=\"yes\"\nfps_limit=60.0\nui_scale=\"big\"\n\n[accessibility]\ntext_scale=1\n\n[input]\npause=32\nconfirm=[\"space\"]\nforge=[70]\n")
	_with_settings(path, func() -> void:
		assert_eq(Settings.get_value("video", "vsync"), true, "строка вместо bool → по умолчанию")
		assert_eq(Settings.get_value("video", "fps_limit"), 60, "60.0 → 60")
		assert_eq(Settings.get_value("video", "ui_scale"), 1.0)
		assert_eq(typeof(Settings.get_value("accessibility", "text_scale")), TYPE_FLOAT)
		assert_eq(Settings.keys_for("pause"), Settings.BINDINGS["pause"], "не массив → раскладка по умолчанию")
		assert_eq(Settings.keys_for("confirm"), Settings.BINDINGS["confirm"], "не коды клавиш → по умолчанию")
		assert_eq(Settings.keys_for("forge"), [70], "корректная переназначенная клавиша сохраняется"))


func test_garbage_settings_file_gives_defaults() -> void:
	var path: String = _tmp("settings_garbage.cfg")
	_write(path, "\u0001\u0002 [[[ это не конфиг")
	_with_settings(path, func() -> void:
		assert_eq(Settings.get_value("audio", "Master"), Settings.DEFAULTS["audio"]["Master"])
		assert_eq(Settings.get_value("video", "preset"), "high")
		assert_eq(Settings.keys_for("menu"), Settings.BINDINGS["menu"]))


func test_save_slots_roundtrip_and_tampering() -> void:
	var old_dir: String = Save.save_dir
	_tmp("slot1.json")
	_tmp("slot2.json")
	Save.save_dir = TMP_DIR
	var sim: GameSim = _build_phase_sim()
	assert_true(Save.save_run(sim, "slot1", {"real_seconds": 12.5}), "сейв в фазе строительства")
	assert_false(FileAccess.file_exists(Save.path_for("slot1") + ".tmp"), "временный файл не остаётся")
	var good: Dictionary = Save.read("slot1")
	var res: Dictionary = Save.restore(good)
	assert_true(res["ok"], String(res["reason"]))
	if res["ok"]:
		assert_eq((res["sim"] as GameSim).checksum(), sim.checksum(), "загрузка восстанавливает состояние точно")
	# Оборванный JSON: слот выглядит пустым, загрузка — «не найдено».
	_write(Save.path_for("slot2"), "{\"format\": \"gtds\", \"seed\": ")
	assert_true(Save.read("slot2").is_empty())
	assert_eq(Save.restore(Save.read("slot2"))["reason"], "ERR_SAVE_MISSING")
	var cases: Dictionary = {
		"saved_checksum": ["ERR_SAVE_CHECKSUM", 12345],
		"data_hash": ["ERR_SAVE_INCOMPATIBLE", 1],
		"saved_tick": ["ERR_SAVE_CORRUPT", "x"],
		"commands": ["ERR_REPLAY_FORMAT", "nope"],
		"map": ["ERR_REPLAY_FORMAT", "arena_99"],
		"difficulty": ["ERR_REPLAY_FORMAT", "nightmare"],
	}
	for key: String in cases:
		var bad: Dictionary = good.duplicate(true)
		bad[key] = cases[key][1]
		assert_eq(Save.restore(bad)["reason"], cases[key][0], "подмена " + key)
	var no_seed: Dictionary = good.duplicate(true)
	no_seed.erase("seed")
	assert_eq(Save.restore(no_seed)["reason"], "ERR_REPLAY_FORMAT", "без seed")
	Save.delete("slot1")
	assert_false(Save.exists("slot1"))
	Save.save_dir = old_dir


func test_malformed_replays_and_imports_are_rejected() -> void:
	var sim: GameSim = new_sim(5, {"max_waves": 1, "record_events": false})
	BotPlayer.new(sim, "maze", 5).run_to_end()
	var rep: Dictionary = JSON.parse_string(JSON.stringify(Replay.from_sim(sim, "test")))
	assert_true(Replay.simulate(data(), rep)["ok"], "исходный реплей проходит")
	for key: String in ["seed", "difficulty", "map", "max_waves", "commands", "data_hash"]:
		var bad: Dictionary = rep.duplicate(true)
		bad.erase(key)
		assert_eq(Replay.simulate(data(), bad)["reason"], "ERR_REPLAY_FORMAT", "без " + key)
	var bad_cmd: Dictionary = rep.duplicate(true)
	(bad_cmd["commands"] as Array)[0] = {"type": "place"}
	assert_eq(Replay.simulate(data(), bad_cmd)["reason"], "ERR_REPLAY_FORMAT", "команда без тика")
	var zero_waves: Dictionary = rep.duplicate(true)
	zero_waves["max_waves"] = 0
	assert_eq(Replay.simulate(data(), zero_waves)["reason"], "ERR_REPLAY_FORMAT")
	var bundle: Dictionary = {"format": RecordIO.EXPORT_FORMAT, "record": {"id": "x1", "name": "A"}, "replay": {"seed": 1}}
	var imp: Dictionary = RecordIO.import_bundle(data(), bundle)
	assert_false(imp["ok"], "импорт с обрезанным реплеем отклонён")
	assert_eq(imp["reason"], "ERR_REPLAY_FORMAT")


func test_corrupt_leaderboard_falls_back_to_backup() -> void:
	var old_path: String = Leaderboard.records_path
	var path: String = _tmp("leaderboard.json")
	_write(path, "{ \"records\": [ обрыв")
	_write(path + ".bak", JSON.stringify({"schema": 1, "records": [{"id": "r1", "name": "A", "score": 10}]}))
	Leaderboard.records_path = path
	Leaderboard._load_records()
	assert_eq(Leaderboard.records.size(), 1, "записи взяты из резервной копии")
	assert_true(FileAccess.file_exists(path + ".corrupt"), "испорченный файл отложен для разбора")
	Leaderboard.records_path = old_path
	Leaderboard._load_records()


## Отслеживаемые рецепты: прежнее одиночное значение переносится, больше MAX_PINNED не бывает —
## снимается самый старый, открепление убирает только свой рецепт.
func test_pinned_recipes_migrate_and_cap() -> void:
	var path: String = _tmp("settings_pins.cfg")
	_with_settings(path, func() -> void:
		Settings.cfg.set_value("general", "pinned_recipe", "cinder_crown")
		assert_eq(Settings.pinned_recipes(), ["cinder_crown"] as Array[String], "старое значение читается как список")
		assert_eq(Settings.set_recipe_pinned("beacon_lens", true), "", "место есть — ничего не снято")
		assert_eq(Settings.pinned_recipes(), ["cinder_crown", "beacon_lens"] as Array[String])
		assert_eq(String(Settings.get_value("general", "pinned_recipe")), "", "старый ключ очищен")
		Settings.set_recipe_pinned("sky_harpoon", true)
		assert_eq(Settings.set_recipe_pinned("frostwell", true), "", "четыре рецепта помещаются")
		assert_eq(Settings.MAX_PINNED, 4)
		assert_eq(Settings.set_recipe_pinned("gilded_idol", true), "cinder_crown", "сверх лимита снят самый старый")
		assert_eq(Settings.pinned_recipes().size(), Settings.MAX_PINNED)
		Settings.set_recipe_pinned("beacon_lens", false)
		assert_eq(Settings.pinned_recipes(), ["sky_harpoon", "frostwell", "gilded_idol"] as Array[String], "открепляется только свой рецепт")
		Settings.replace_pinned_recipe("sky_harpoon", "cinder_crown")
		assert_eq(Settings.pinned_recipes(), ["cinder_crown", "frostwell", "gilded_idol"] as Array[String], "замена встаёт на место прежнего")
		Settings.replace_pinned_recipe("cinder_crown", "frostwell")
		assert_eq(Settings.pinned_recipes(), ["cinder_crown", "frostwell", "gilded_idol"] as Array[String], "уже отслеживаемый не дублируется"))
