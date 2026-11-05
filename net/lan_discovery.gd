class_name LanDiscovery
extends Node
## Поиск игр в локальной сети: хост раз в секунду рассылает UDP-маячок, клиент слушает порт.

signal hosts_changed

const BEACON_INTERVAL: float = 1.0
const HOST_TIMEOUT: float = 3.5
const MAGIC: String = "gemtd-lobby"

var hosts: Dictionary = {}
var _beacon: PacketPeerUDP = null
var _listener: PacketPeerUDP = null
var _info: Callable
var _timer: float = 0.0
var _clock: float = 0.0


func start_beacon(info: Callable) -> void:
	stop_beacon()
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", NetProtocol.DISCOVERY_PORT)
	_info = info
	_timer = 0.0


func stop_beacon() -> void:
	if _beacon != null:
		_beacon.close()
	_beacon = null


## false — порт занят (например, второй клиент на этом же компьютере); тогда остаётся ввод IP.
func start_listen() -> bool:
	stop_listen()
	_listener = PacketPeerUDP.new()
	if _listener.bind(NetProtocol.DISCOVERY_PORT) != OK:
		_listener = null
		return false
	return true


func stop_listen() -> void:
	if _listener != null:
		_listener.close()
	_listener = null
	hosts.clear()


func _process(delta: float) -> void:
	_clock += delta
	if _beacon != null:
		_timer -= delta
		if _timer <= 0.0:
			_timer = BEACON_INTERVAL
			var info: Dictionary = _info.call()
			info["magic"] = MAGIC
			_beacon.put_packet(JSON.stringify(info).to_utf8_buffer())
	if _listener == null:
		return
	var changed: bool = false
	while _listener.get_available_packet_count() > 0:
		var pkt: PackedByteArray = _listener.get_packet()
		var ip: String = _listener.get_packet_ip()
		var data: Variant = JSON.parse_string(pkt.get_string_from_utf8())
		if not data is Dictionary or String(data.get("magic", "")) != MAGIC:
			continue
		var key: String = "%s:%d" % [ip, int(data.get("port", 0))]
		var entry: Dictionary = data
		entry["ip"] = ip
		entry["seen"] = _clock
		changed = changed or not hosts.has(key)
		hosts[key] = entry
	for key: String in hosts.keys():
		if _clock - float(hosts[key]["seen"]) > HOST_TIMEOUT:
			hosts.erase(key)
			changed = true
	if changed:
		hosts_changed.emit()


static func local_addresses() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for a: String in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out
