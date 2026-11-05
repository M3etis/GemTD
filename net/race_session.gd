class_name RaceSession
extends Node
## Матч «Гонка»: реплики полей соперников (детерминированная пересимуляция их команд),
## синхронные раунды (хост открывает волну, когда все готовы или вышел таймер),
## контроль рассинхрона по контрольным суммам и итоговая таблица.

signal opponents_changed
signal begin_wave(round_index: int)
signal force_build(round_index: int)
signal speed_changed(speed: int)
signal paused_changed(on: bool)
signal match_ended(standings: Array)
signal player_out(id: int, name: String, victory: bool)
signal desync(id: int, wave: int)
## Соперник начал (on) или перестал наблюдать за полем локального игрока.
signal watched_changed(watcher: int, on: bool)

const HEARTBEAT_INTERVAL: float = 0.1
const MAX_REPLICA_STEPS: int = 400

var data: GameData
var config: Dictionary = {}
var local_id: int = 1
var local_sim: GameSim
## peer_id → {sim, name, color, queue, hb, ready_round, build_round, over, summary, left, checksums}
var replicas: Dictionary = {}
var ended: bool = false
var standings: Array[Dictionary] = []
var timer_left: float = -1.0
var timer_round: int = 0
var pauses_used: int = 0
## Скорость и пауза матча по последней команде хоста. Команда могла прийти, пока сцена грузилась
## (из очереди в setup — до подписки RaceController): контроллер применяет их при создании.
var speed: int = 1
var paused: bool = false
## Кто сейчас наблюдает за полем локального игрока: id соперника → true.
var watchers: Dictionary = {}
## Золото от соперников, ещё не зачисленное своей командой receive_gold: [{from, amount}].
## Зачисляется в _process — к этому времени командой уже слушает сеть (очередь в setup приходит раньше).
var _incoming_gold: Array[Dictionary] = []
var _hb_timer: float = 0.0
var _local_ready_round: int = 0
var _local_build_round: int = 0
var _local_over: Dictionary = {}
var _local_checksums: Dictionary = {}
var _begun_round: int = 0
var _forced_round: int = 0


func setup(game_data: GameData, cfg: Dictionary, sim: GameSim) -> void:
	data = game_data
	# Копия: Net.leave() очищает исходный словарь конфигурации матча.
	config = cfg.duplicate(true)
	local_sim = sim
	local_id = Net.my_id()
	for p: Dictionary in cfg["players"]:
		var id: int = int(p["id"])
		if id == local_id:
			continue
		var rs: GameSim = GameSim.new(data, {"seed": int(p["seed"]), "difficulty": String(cfg["difficulty"]),
			"max_waves": int(cfg["max_waves"]), "endless": bool(cfg.get("endless", false)), "record_events": false})
		rs.start()
		rs.drain_events()
		replicas[id] = {"sim": rs, "replica": Replica.new(rs), "name": String(p["name"]), "color": String(p["color"]),
			"ready_round": 0, "build_round": 1, "over": false, "summary": {}, "left": false, "checksums": {}}
	_local_build_round = 1
	Net.match_message.connect(_on_match_message)
	Net.control_message.connect(_on_control)
	Net.disconnected.connect(_on_disconnected)
	for item: Dictionary in Net.take_backlog():
		if String(item["kind"]) == "match":
			_on_match_message(int(item["from"]), item["msg"])
		else:
			_on_control(item["msg"])


static func local_config(cfg: Dictionary) -> Dictionary:
	var me: int = Net.my_id()
	for p: Dictionary in cfg["players"]:
		if int(p["id"]) == me:
			return {"seed": int(p["seed"]), "difficulty": String(cfg["difficulty"]), "max_waves": int(cfg["max_waves"]),
				"endless": bool(cfg.get("endless", false))}
	return {}


func player_name(id: int) -> String:
	if id == local_id:
		return Net.my_name
	return String(replicas[id]["name"]) if replicas.has(id) else "?"


# --- Локальный игрок → сеть --------------------------------------------------

func on_local_command(cmd: Dictionary) -> void:
	Net.send_match({"t": "cmd", "cmd": cmd})


func on_local_round_started(round_index: int) -> void:
	_local_build_round = round_index
	Net.send_match({"t": "phase", "round": round_index, "phase": "build"})
	if Net.is_host():
		_host_check_round()


func on_local_ready(round_index: int) -> void:
	_local_ready_round = round_index
	Net.send_match({"t": "ready", "round": round_index})
	if Net.is_host():
		_host_check_round()


func on_local_wave_cleared(wave: int, checksum: int) -> void:
	_local_checksums[wave] = checksum
	Net.send_match({"t": "cs", "wave": wave, "cs": checksum})


func on_local_over(summary: Dictionary) -> void:
	_local_over = summary
	Net.send_match({"t": "over", "summary": summary})
	if Net.is_host():
		_host_check_round()
		_host_check_end()


## Локальный игрок начал (on) или перестал наблюдать за полем target — тот увидит сообщение.
func on_local_watch(target: int, on: bool) -> void:
	Net.send_match({"t": "watch", "target": target, "on": on})


func request_speed(s: int) -> void:
	Net.send_control({"type": "speed", "speed": s})


func request_pause(on: bool) -> bool:
	if not Net.is_host():
		return false
	if on and pauses_used >= NetProtocol.MAX_PAUSES:
		return false
	if on:
		pauses_used += 1
	Net.send_control({"type": "pause", "on": on})
	return true


# --- Сеть → реплики -----------------------------------------------------------

func _on_match_message(from: int, msg: Dictionary) -> void:
	if not replicas.has(from):
		return
	var r: Dictionary = replicas[from]
	match String(msg["t"]):
		"cmd":
			(r["replica"] as Replica).push_command(msg["cmd"])
			var cmd: Dictionary = msg["cmd"]
			if String(cmd["type"]) == "give_gold" and int(cmd["to"]) == local_id:
				_incoming_gold.append({"from": from, "amount": int(cmd["amount"])})
		"hb":
			(r["replica"] as Replica).heartbeat(int(msg["tick"]))
		"phase":
			r["build_round"] = int(msg["round"])
		"ready":
			r["ready_round"] = int(msg["round"])
		"cs":
			(r["checksums"] as Dictionary)[int(msg["wave"])] = int(msg["cs"])
			for entry: Dictionary in (r["sim"] as GameSim).wave_checksums:
				if int(entry["wave"]) == int(msg["wave"]) and int(entry["checksum"]) != int(msg["cs"]):
					desync.emit(from, int(msg["wave"]))
		"watch":
			if int(msg["target"]) == local_id:
				_set_watcher(from, bool(msg["on"]))
		"over":
			r["over"] = true
			r["summary"] = msg["summary"]
			# Финальный тик владельца приходит с итогом — реплика доигрывает до него.
			(r["replica"] as Replica).heartbeat(int((msg["summary"] as Dictionary).get("tick", 0)))
			_advance_replica(from, true)
			player_out.emit(from, String(r["name"]), String((msg["summary"] as Dictionary).get("outcome", "")) == "victory")
	opponents_changed.emit()
	if Net.is_host():
		_host_check_round()
		_host_check_end()


func _on_control(msg: Dictionary) -> void:
	match String(msg["type"]):
		"begin_wave":
			_begun_round = int(msg["round"])
			timer_left = -1.0
			begin_wave.emit(int(msg["round"]))
		"force_build":
			_forced_round = int(msg["round"])
			force_build.emit(int(msg["round"]))
		"timer":
			timer_round = int(msg["round"])
			timer_left = float(msg["seconds"])
		"speed":
			speed = int(msg["speed"])
			speed_changed.emit(speed)
		"pause":
			paused = bool(msg["on"])
			paused_changed.emit(paused)
		"player_left":
			var id: int = int(msg["id"])
			if replicas.has(id):
				_mark_left(id)
				_set_watcher(id, false)
				player_out.emit(id, String(replicas[id]["name"]), false)
			opponents_changed.emit()
			if Net.is_host():
				_host_check_round()
				_host_check_end()
		"end":
			_finish(msg["standings"])


## Связь с хостом потеряна — матч окончен. Хост в итогах «вышел», остальные — по последнему известному состоянию.
func _on_disconnected(_reason: String) -> void:
	if ended:
		return
	if replicas.has(1):
		_mark_left(1)
	var entries: Array = [_summary_for_local()]
	for id: int in replicas.keys():
		var s: Dictionary = replicas[id]["summary"] if not (replicas[id]["summary"] as Dictionary).is_empty() else (replicas[id]["sim"] as GameSim).summary()
		entries.append(_entry(id, s))
	_finish(NetProtocol.standings(entries))


func _mark_left(id: int) -> void:
	replicas[id]["left"] = true
	replicas[id]["over"] = true
	var s: Dictionary = (replicas[id]["sim"] as GameSim).summary()
	s["outcome"] = "left"
	replicas[id]["summary"] = s


func _process(delta: float) -> void:
	if ended:
		return
	while not _incoming_gold.is_empty():
		var g: Dictionary = _incoming_gold.pop_front()
		local_sim.apply({"type": "receive_gold", "from": int(g["from"]), "amount": int(g["amount"])})
	_hb_timer -= delta
	if _hb_timer <= 0.0:
		_hb_timer = HEARTBEAT_INTERVAL
		Net.send_match({"t": "hb", "tick": local_sim.tick})
	for id: int in replicas.keys():
		_advance_replica(id)
	if Net.is_host() and timer_left > 0.0:
		timer_left -= delta
		if timer_left <= 0.0 and _forced_round < timer_round:
			_forced_round = timer_round
			Net.send_control({"type": "force_build", "round": timer_round})
	elif timer_left > 0.0:
		timer_left -= delta


## Шагаем реплику до последнего такта владельца; unlimited — без лимита шагов (финал матча).
func _advance_replica(id: int, unlimited: bool = false) -> void:
	var rep: Replica = replicas[id]["replica"]
	for entry: Dictionary in rep.advance(1 << 30 if unlimited else MAX_REPLICA_STEPS):
		_check_checksum(id, entry)


func _check_checksum(id: int, entry: Dictionary) -> void:
	var reported: Dictionary = replicas[id]["checksums"]
	var wave: int = int(entry["wave"])
	if reported.has(wave) and int(reported[wave]) != int(entry["checksum"]):
		desync.emit(id, wave)


# --- Хост: раунды и финиш ------------------------------------------------------

func _active_ids() -> Array[int]:
	var out: Array[int] = []
	if _local_over.is_empty():
		out.append(local_id)
	for id: int in replicas.keys():
		if not bool(replicas[id]["over"]):
			out.append(id)
	return out


func _build_round_of(id: int) -> int:
	return _local_build_round if id == local_id else int(replicas[id]["build_round"])


func _ready_round_of(id: int) -> int:
	return _local_ready_round if id == local_id else int(replicas[id]["ready_round"])


func _host_check_round() -> void:
	var active: Array[int] = _active_ids()
	if active.is_empty():
		return
	var round_index: int = 1 << 30
	for id: int in active:
		round_index = mini(round_index, _build_round_of(id))
	if round_index <= _begun_round:
		return
	var all_building: bool = true
	var all_ready: bool = true
	for id: int in active:
		all_building = all_building and _build_round_of(id) >= round_index
		all_ready = all_ready and _ready_round_of(id) >= round_index
	if all_ready:
		Net.send_control({"type": "begin_wave", "round": round_index})
	elif all_building and timer_round < round_index and int(config["timer"]) > 0:
		Net.send_control({"type": "timer", "round": round_index, "seconds": float(config["timer"])})


func _host_check_end() -> void:
	if ended or not _active_ids().is_empty():
		return
	var entries: Array = [_summary_for_local()]
	for id: int in replicas.keys():
		entries.append(_entry(id, replicas[id]["summary"]))
	Net.send_control({"type": "end", "standings": NetProtocol.standings(entries)})


func _summary_for_local() -> Dictionary:
	var s: Dictionary = _local_over if not _local_over.is_empty() else local_sim.summary()
	return _entry(local_id, s)


func _entry(id: int, s: Dictionary) -> Dictionary:
	var color: String = String(replicas[id]["color"]) if replicas.has(id) else _local_color()
	return {"id": id, "name": player_name(id), "color": color, "outcome": String(s.get("outcome", "running")),
		"waves_cleared": int(s.get("waves_cleared", 0)), "lives": int(s.get("lives", 0)),
		"score": Scoring.compute(data, s) if s.has("difficulty") else 0, "combat_seconds": float(s.get("combat_seconds", 0.0)),
		"kills": int(s.get("kills", 0)), "checksum": int(s.get("checksum", 0))}


func _local_color() -> String:
	for p: Dictionary in config["players"]:
		if int(p["id"]) == local_id:
			return String(p["color"])
	return NetProtocol.COLORS[0]


func _finish(list: Array) -> void:
	if ended:
		return
	ended = true
	standings.clear()
	for e: Variant in list:
		standings.append(e as Dictionary)
	match_ended.emit(standings)


## Подтверждение: контрольные суммы реплик совпали с итогами владельцев.
func replicas_verified() -> Dictionary:
	var out: Dictionary = {}
	for id: int in replicas.keys():
		_advance_replica(id, true)
		var s: Dictionary = replicas[id]["summary"]
		var sim: GameSim = replicas[id]["sim"]
		out[id] = not s.is_empty() and int(s.get("checksum", -1)) == sim.checksum()
	return out


func local_place() -> int:
	for e: Dictionary in standings:
		if int(e["id"]) == local_id:
			return int(e["place"])
	return 0


## Сводка для панели соперников: [{id, name, color, lives, wave, status, path, me}].
func board_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	rows.append(_row(local_id, local_sim, _local_color(), not _local_over.is_empty(), false, true))
	for id: int in replicas.keys():
		var r: Dictionary = replicas[id]
		rows.append(_row(id, r["sim"], String(r["color"]), bool(r["over"]), bool(r["left"]), false))
	return rows


func _row(id: int, sim: GameSim, color: String, over: bool, left: bool, me: bool) -> Dictionary:
	var status: String
	if left:
		status = "left"
	elif over:
		status = "victory" if sim.phase == GameSim.Phase.VICTORY else "out"
	elif sim.phase == GameSim.Phase.COMBAT:
		status = "combat"
	elif sim.phase == GameSim.Phase.READY:
		status = "ready"
	else:
		status = "build"
	return {"id": id, "name": player_name(id), "color": color, "lives": sim.lives, "wave": sim.next_wave_number(),
		"status": status, "path": sim.route.ground_length, "me": me, "towers": sim.towers.size(), "watching_me": watchers.has(id), "gold": sim.gold, "over": over}


func _set_watcher(id: int, on: bool) -> void:
	if on == watchers.has(id):
		return
	if on:
		watchers[id] = true
	else:
		watchers.erase(id)
	watched_changed.emit(id, on)


func ready_count() -> Vector2i:
	var active: Array[int] = _active_ids()
	var n: int = 0
	for id: int in active:
		if _ready_round_of(id) >= _local_build_round:
			n += 1
	return Vector2i(n, active.size())
