extends Node
## LAN / direct-IP мультиплеер (§11 PROMPT.md) на ENet.
## Хост — авторитет лобби и таймингов и одновременно игрок (peer id 1).
## Каждый клиент симулирует своё поле сам; по сети идут команды, такты, готовность и итоги.

signal state_changed
signal lobby_updated
signal chat_received(sender: String, text: String, color: Color)
signal match_started(config: Dictionary)
signal match_message(from: int, msg: Dictionary)
signal control_message(msg: Dictionary)
signal connection_failed(reason: String)
signal disconnected(reason: String)

enum State { OFFLINE, CONNECTING, LOBBY, IN_MATCH }

## Таймауты ENet (ENetPacketPeer.set_timeout). Загрузка сцены матча (первая компиляция шейдеров на слабом Mac)
## замораживает главный поток на секунды, и ENet не подтверждает пакеты соперника. Стандартные 5 с рвали
## соединение на старте: у хоста гость «выбывал», а гость получал «Победа!». Корректный выход шлёт
## disconnect сразу, поэтому долгий таймаут заметен только при падении игры или обрыве сети.
const PEER_TIMEOUT_LIMIT: int = 32
const PEER_TIMEOUT_MIN_MS: int = 30000
const PEER_TIMEOUT_MAX_MS: int = 60000

var state: int = State.OFFLINE
var my_name: String = ""
## peer_id → {id, name, color, ready, index}
var players: Dictionary = {}
var settings: Dictionary = {}
var match_config: Dictionary = {}
## Чат комнаты и матча: последние NetProtocol.CHAT_HISTORY сообщений {sender, text, color}.
## Лобби и матч показывают их при открытии: сообщения во время загрузки сцены не теряются.
var chat_log: Array[Dictionary] = []
var discovery: LanDiscovery
var _peer: ENetMultiplayerPeer = null
## Сообщения матча до подписки сцены (см. _deliver_match).
var _backlog: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	discovery = LanDiscovery.new()
	discovery.name = "Discovery"
	add_child(discovery)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: _fail("NET_ERR_CONNECT"))
	multiplayer.server_disconnected.connect(_on_server_lost)


func is_online() -> bool:
	return state != State.OFFLINE


func is_host() -> bool:
	return is_online() and multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


func default_settings() -> Dictionary:
	var data: GameData = GameData.load_default()
	return {
		"match_name": "",
		"seed_mode": "random",
		"seed_text": "",
		"difficulty": data.default_difficulty,
		"waves": mini(NetProtocol.DEFAULT_RACE_WAVES, data.wave_count()),
		"timer": 60,
		"fair": true,
		"max_players": NetProtocol.MAX_PLAYERS,
		"port": NetProtocol.DEFAULT_PORT,
	}


# --- Подключение -----------------------------------------------------------

func host(port: int, player_name: String) -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err: Error = _peer.create_server(port, NetProtocol.MAX_PLAYERS - 1)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	my_name = NetProtocol.sanitize_name(player_name)
	settings = default_settings()
	settings["port"] = port
	settings["match_name"] = tr("NET_MATCH_OF") % my_name
	players = {1: {"id": 1, "name": my_name, "color": NetProtocol.COLORS[0], "ready": true, "index": 0}}
	_set_state(State.LOBBY)
	discovery.start_beacon(_beacon_info)
	lobby_updated.emit()
	return OK


func join(address: String, port: int, player_name: String) -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err: Error = _peer.create_client(address, port)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	my_name = NetProtocol.sanitize_name(player_name)
	_set_state(State.CONNECTING)
	return OK


func leave() -> void:
	_backlog.clear()
	discovery.stop_beacon()
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	match_config.clear()
	chat_log.clear()
	if state != State.OFFLINE:
		_set_state(State.OFFLINE)


func _set_state(s: int) -> void:
	state = s
	state_changed.emit()


func _beacon_info() -> Dictionary:
	return {"name": String(settings.get("match_name", "")), "players": players.size(), "max": int(settings.get("max_players", 4)),
		"port": int(settings.get("port", NetProtocol.DEFAULT_PORT)), "version": Game.version(), "open": state == State.LOBBY}


func _fail(reason: String) -> void:
	leave()
	connection_failed.emit(reason)


func _on_connected() -> void:
	_relax_timeout(1)
	_c_hello.rpc_id(1, {"name": my_name, "version": Game.version(), "data_hash": GameData.load_default().data_hash, "protocol": NetProtocol.VERSION})


func _on_server_lost() -> void:
	var was_match: bool = state == State.IN_MATCH
	leave()
	disconnected.emit("NET_ERR_HOST_LEFT" if was_match else "NET_ERR_HOST_CLOSED")


func _on_peer_connected(id: int) -> void:
	# У клиента ENet-пир только один — хост (его таймаут задаётся в _on_connected).
	if is_host():
		_relax_timeout(id)


func _relax_timeout(id: int) -> void:
	var p: ENetPacketPeer = _peer.get_peer(id) if _peer != null else null
	if p != null:
		p.set_timeout(PEER_TIMEOUT_LIMIT, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)


func _on_peer_disconnected(id: int) -> void:
	if not is_host() or not players.has(id):
		return
	var left_name: String = String(players[id]["name"])
	players.erase(id)
	if state == State.IN_MATCH:
		send_control({"type": "player_left", "id": id})
	else:
		_broadcast_lobby()
	_post_chat("", tr("NET_PLAYER_LEFT") % left_name, UiTokens.TEXT_DIM)


# --- Лобби ----------------------------------------------------------------

@rpc("any_peer", "reliable")
func _c_hello(info: Dictionary) -> void:
	if not is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var reason: String = ""
	if int(info.get("protocol", -1)) != NetProtocol.VERSION or String(info.get("version", "")) != Game.version():
		reason = "NET_ERR_VERSION"
	elif int(info.get("data_hash", -1)) != GameData.load_default().data_hash:
		reason = "NET_ERR_DATA"
	elif state != State.LOBBY:
		reason = "NET_ERR_IN_MATCH"
	elif players.size() >= int(settings["max_players"]):
		reason = "NET_ERR_FULL"
	if not reason.is_empty():
		_h_rejected.rpc_id(sender, reason)
		_disconnect_later(sender)
		return
	var used: Array[int] = []
	for p: Dictionary in players.values():
		used.append(int(p["index"]))
	var index: int = 0
	while used.has(index):
		index += 1
	# Два окна на одном Mac делят settings.cfg и приходят с одним именем: второму добавляется номер.
	var taken: Array[String] = []
	for p: Dictionary in players.values():
		taken.append(String(p["name"]))
	var base: String = NetProtocol.sanitize_name(String(info.get("name", "")))
	var nick: String = base
	var n: int = 2
	while taken.has(nick):
		nick = "%s %d" % [base, n]
		n += 1
	players[sender] = {"id": sender, "name": nick, "color": NetProtocol.COLORS[index % NetProtocol.COLORS.size()], "ready": false, "index": index}
	_broadcast_lobby()
	_post_chat("", tr("NET_PLAYER_JOINED") % String(players[sender]["name"]), UiTokens.TEXT_DIM)
	Audio.play("sfx/net/player_joined")


func _disconnect_later(id: int) -> void:
	await get_tree().create_timer(0.3).timeout
	if _peer != null:
		_peer.disconnect_peer(id)


@rpc("authority", "reliable")
func _h_rejected(reason: String) -> void:
	_fail(reason)


func _broadcast_lobby() -> void:
	if not is_host():
		return
	_h_lobby.rpc(players, settings)
	lobby_updated.emit()


@rpc("authority", "reliable")
func _h_lobby(p: Dictionary, s: Dictionary) -> void:
	var was_connecting: bool = state == State.CONNECTING
	if not was_connecting and p.size() != players.size():
		Audio.play("sfx/net/player_joined" if p.size() > players.size() else "sfx/net/player_left")
	players = p
	settings = s
	if was_connecting:
		_set_state(State.LOBBY)
		Audio.play("sfx/net/player_joined")
	lobby_updated.emit()


func set_ready(v: bool) -> void:
	if is_host():
		return
	_c_ready.rpc_id(1, v)


@rpc("any_peer", "reliable")
func _c_ready(v: bool) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if is_host() and players.has(sender) and state == State.LOBBY:
		players[sender]["ready"] = v
		_broadcast_lobby()
		Audio.play("sfx/net/ready")


func update_settings(patch: Dictionary) -> void:
	if not is_host() or state != State.LOBBY:
		return
	settings.merge(patch, true)
	_broadcast_lobby()


func kick(id: int) -> void:
	if not is_host() or id == 1 or not players.has(id):
		return
	_h_rejected.rpc_id(id, "NET_ERR_KICKED")
	players.erase(id)
	_broadcast_lobby()
	_disconnect_later(id)


func send_chat(text: String) -> void:
	var clean: String = NetProtocol.sanitize_chat(text)
	# Без соединения (идёт подключение, хост пропал) отправлять некуда.
	if clean.is_empty() or not (state == State.LOBBY or state == State.IN_MATCH):
		return
	if is_host():
		_relay_chat(1, clean)
	else:
		_c_chat.rpc_id(1, clean)


@rpc("any_peer", "reliable")
func _c_chat(text: String) -> void:
	var clean: String = NetProtocol.sanitize_chat(text)
	if is_host() and not clean.is_empty():
		_relay_chat(multiplayer.get_remote_sender_id(), clean)


func _relay_chat(from: int, text: String) -> void:
	if not players.has(from):
		return
	_h_chat.rpc(String(players[from]["name"]), text, String(players[from]["color"]))
	_post_chat(String(players[from]["name"]), text, Color.html(String(players[from]["color"])))


@rpc("authority", "reliable")
func _h_chat(sender: String, text: String, color: String) -> void:
	_post_chat(sender, NetProtocol.sanitize_chat(text), Color.html(color))


## Сообщение в историю чата (не длиннее CHAT_HISTORY) и подписчикам; sender пуст — системное.
func _post_chat(sender: String, text: String, color: Color) -> void:
	chat_log.append({"sender": sender, "text": text, "color": color})
	if chat_log.size() > NetProtocol.CHAT_HISTORY:
		chat_log.pop_front()
	chat_received.emit(sender, text, color)


func can_start() -> bool:
	if not is_host() or players.size() < NetProtocol.MIN_PLAYERS:
		return false
	for p: Dictionary in players.values():
		if not bool(p["ready"]):
			return false
	return true


func start_match() -> void:
	if not can_start():
		return
	var data: GameData = GameData.load_default()
	var match_seed: int
	match String(settings["seed_mode"]):
		"daily":
			match_seed = RunRng.daily_seed(Game.today_iso())
		"custom":
			match_seed = RunRng.seed_from_text(String(settings["seed_text"]))
		_:
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.randomize()
			match_seed = rng.randi()
	var list: Array = []
	var ids: Array = players.keys()
	ids.sort()
	for id: Variant in ids:
		var p: Dictionary = players[id]
		list.append({"id": int(id), "name": p["name"], "color": p["color"], "index": int(p["index"]),
			"seed": NetProtocol.player_seed(match_seed, int(p["index"]), bool(settings["fair"]))})
	var endless: bool = int(settings["waves"]) == NetProtocol.ENDLESS_WAVES
	var config: Dictionary = {
		"match_seed": match_seed,
		"difficulty": String(settings["difficulty"]),
		"max_waves": 0 if endless else clampi(int(settings["waves"]), 1, data.wave_count()),
		"endless": endless,
		"timer": int(settings["timer"]),
		"fair": bool(settings["fair"]),
		"players": list,
		"version": Game.version(),
	}
	discovery.stop_beacon()
	_h_start.rpc(config)


@rpc("authority", "reliable", "call_local")
func _h_start(config: Dictionary) -> void:
	match_config = config
	_backlog.clear()
	_set_state(State.IN_MATCH)
	Audio.play("sfx/net/match_start")
	match_started.emit(config)


## Возврат в лобби после матча (только хост).
func back_to_lobby() -> void:
	if not is_host():
		return
	for id: Variant in players.keys():
		players[id]["ready"] = int(id) == 1
	_set_state(State.LOBBY)
	discovery.start_beacon(_beacon_info)
	_h_back.rpc()
	_broadcast_lobby()


@rpc("authority", "reliable")
func _h_back() -> void:
	_set_state(State.LOBBY)


# --- Матч -------------------------------------------------------------------

## Сообщение игрока всем остальным (через хоста).
func send_match(msg: Dictionary) -> void:
	if state != State.IN_MATCH:
		return
	if is_host():
		_relay(1, msg)
	else:
		_c_match.rpc_id(1, msg)


@rpc("any_peer", "reliable")
func _c_match(msg: Dictionary) -> void:
	if not is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not players.has(sender) or not NetProtocol.valid_match_msg(msg):
		return
	_relay(sender, msg)


func _relay(from: int, msg: Dictionary) -> void:
	if from != 1:
		_deliver_match(from, msg)
	for id: Variant in players.keys():
		var pid: int = int(id)
		if pid != 1 and pid != from:
			_h_match.rpc_id(pid, from, msg)


@rpc("authority", "reliable")
func _h_match(from: int, msg: Dictionary) -> void:
	if NetProtocol.valid_match_msg(msg):
		_deliver_match(from, msg)


## Сообщения матча, пришедшие до того, как сцена матча подписалась (она ещё грузится),
## не теряются: копятся и отдаются RaceSession при подписке (take_backlog).
func _deliver_match(from: int, msg: Dictionary) -> void:
	if match_message.get_connections().is_empty():
		_backlog.append({"kind": "match", "from": from, "msg": msg})
		return
	match_message.emit(from, msg)


## Накопленные до подписки сообщения в порядке прихода: {kind: match|control, from, msg}.
func take_backlog() -> Array[Dictionary]:
	var out: Array[Dictionary] = _backlog
	_backlog = []
	return out


## Управляющее сообщение хоста всем (включая себя).
func send_control(msg: Dictionary) -> void:
	if is_host():
		_h_control.rpc(msg)


@rpc("authority", "reliable", "call_local")
func _h_control(msg: Dictionary) -> void:
	if not NetProtocol.valid_control(msg):
		return
	if state == State.IN_MATCH and control_message.get_connections().is_empty():
		_backlog.append({"kind": "control", "from": 1, "msg": msg})
		return
	control_message.emit(msg)
