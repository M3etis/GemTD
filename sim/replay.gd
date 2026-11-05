class_name Replay
extends RefCounted
## Реплей = seed + настройки + лог команд с тиками. Пересимуляция обязана дать тот же checksum.

const FORMAT: String = "gtdr"
const FORMAT_VERSION: int = 1


static func from_sim(sim: GameSim, game_version: String) -> Dictionary:
	return {
		"format": FORMAT,
		"format_version": FORMAT_VERSION,
		"game_version": game_version,
		"data_hash": sim.data.data_hash,
		"seed": sim.seed_value,
		"difficulty": sim.difficulty_id,
		"map": sim.map_id,
		"max_waves": sim.total_waves,
		"endless": sim.endless,
		"commands": sim.command_log.duplicate(true),
		"wave_checksums": sim.wave_checksums.duplicate(true),
		"final_tick": sim.tick,
		"final_checksum": sim.checksum(),
	}


## Полная пересимуляция. Возвращает {ok, reason, checksum, sim}.
static func simulate(data: GameData, replay: Dictionary) -> Dictionary:
	var res: Dictionary = resimulate(data, replay, -1)
	if not res["ok"]:
		return res
	var cs: int = int(res["checksum"])
	var ok: bool = cs == int(replay.get("final_checksum", -1))
	return {"ok": ok, "reason": "" if ok else "ERR_REPLAY_CHECKSUM", "checksum": cs, "sim": res["sim"]}


## Пересимуляция лога команд. until_tick >= 0 — остановиться на этом тике (для сейвов),
## -1 — доиграть начатую волну до конца (для реплеев).
static func resimulate(data: GameData, header: Dictionary, until_tick: int) -> Dictionary:
	if not well_formed(data, header):
		return {"ok": false, "reason": "ERR_REPLAY_FORMAT", "checksum": 0, "sim": null}
	if int(header.get("data_hash", -1)) != data.data_hash:
		return {"ok": false, "reason": "ERR_REPLAY_DATA_MISMATCH", "checksum": 0, "sim": null}
	var sim: GameSim = GameSim.new(data, {
		"seed": int(header["seed"]),
		"difficulty": String(header["difficulty"]),
		"map": String(header["map"]),
		"max_waves": int(header["max_waves"]),
		"endless": bool(header.get("endless", false)),
		"record_events": false,
	})
	sim.start()
	for raw_cmd: Variant in header["commands"]:
		var cmd: Dictionary = raw_cmd
		var at: int = int(cmd["tick"])
		while sim.tick < at and sim.phase == GameSim.Phase.COMBAT:
			sim.step()
		if sim.tick != at:
			return {"ok": false, "reason": "ERR_REPLAY_TICK_MISMATCH", "checksum": sim.checksum(), "sim": sim}
		var res: Dictionary = sim.apply(cmd)
		if not res["ok"]:
			return {"ok": false, "reason": "ERR_REPLAY_COMMAND_REJECTED", "checksum": sim.checksum(), "sim": sim}
	if until_tick < 0:
		while sim.phase == GameSim.Phase.COMBAT:
			sim.step()
	else:
		while sim.tick < until_tick and sim.phase == GameSim.Phase.COMBAT:
			sim.step()
	return {"ok": true, "reason": "", "checksum": sim.checksum(), "sim": sim}


## Все поля заголовка на месте и нужных типов: файл реплея, сейва или импорта мог быть испорчен или подделан.
## После JSON числа приходят как float, из памяти — как int; годятся оба.
static func well_formed(data: GameData, header: Dictionary) -> bool:
	for key: String in ["seed", "data_hash", "max_waves"]:
		if not _is_number(header.get(key)):
			return false
	if header.has("endless") and not (header["endless"] is bool):
		return false
	# Бесконечный забег («Гонка» до последнего выжившего) хранит max_waves = 0.
	if int(header["max_waves"]) < 1 and not bool(header.get("endless", false)):
		return false
	if not (header.get("difficulty") is String) or not data.difficulty_levels.has(String(header["difficulty"])):
		return false
	if not (header.get("map") is String) or not data.maps.has(String(header["map"])):
		return false
	if not (header.get("commands") is Array):
		return false
	for c: Variant in header["commands"]:
		if not (c is Dictionary) or not _is_number((c as Dictionary).get("tick")) or not ((c as Dictionary).get("type") is String):
			return false
	return true


static func _is_number(v: Variant) -> bool:
	return v is int or v is float


## Состояние сразу перед командой с индексом cmd_index (для перемотки просмотра реплея).
static func resimulate_until_command(data: GameData, header: Dictionary, cmd_index: int) -> GameSim:
	var sim: GameSim = GameSim.new(data, {"seed": int(header["seed"]), "difficulty": String(header["difficulty"]),
		"map": String(header["map"]), "max_waves": int(header["max_waves"]), "endless": bool(header.get("endless", false)),
		"record_events": false})
	sim.start()
	var commands: Array = header["commands"]
	for i: int in mini(cmd_index, commands.size()):
		var cmd: Dictionary = commands[i]
		while sim.tick < int(cmd["tick"]) and sim.phase == GameSim.Phase.COMBAT:
			sim.step()
		sim.apply(cmd)
	return sim


## Индекс команды start_wave для волны n (или -1).
static func start_wave_index(header: Dictionary, n: int) -> int:
	var count: int = 0
	var commands: Array = header["commands"]
	for i: int in commands.size():
		if String((commands[i] as Dictionary)["type"]) == "start_wave":
			count += 1
			if count == n:
				return i
	return -1
