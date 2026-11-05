class_name VoicePool
extends RefCounted
## Голоса Audio без перебора пула: стек свободных плееров, звучащие в порядке запуска и счётчик голосов
## по событию. В большом бою вызовов Audio.play сотни в секунду, а пул почти всегда занят: проход
## по 40 плеерам на каждый вызов стоил ~0.1 мс кадра (стресс-тест, этап 7).
## Если заняты все голоса, частые боевые звуки пропускаются, а остальные (интерфейс, волны, потеря жизни,
## босс) забирают самый старый боевой голос — важное не теряется за грохотом боя.

var players: Array[AudioStreamPlayer] = []
var _free: Array[AudioStreamPlayer] = []
var _busy: Array[AudioStreamPlayer] = []
var _count: Dictionary = {}
var _event: Dictionary = {}


func _init(list: Array[AudioStreamPlayer]) -> void:
	players = list
	reset()


func reset() -> void:
	_free = players.duplicate()
	_busy.clear()
	_count.clear()
	_event.clear()


## Сколько голосов сейчас звучит у события.
func active(id: String) -> int:
	return int(_count.get(id, 0))


func free_count() -> int:
	return _free.size()


func busy_count() -> int:
	return _busy.size()


## Свободный голос для события или null (пул занят, а событие боевое).
func take(id: String) -> AudioStreamPlayer:
	if not _free.is_empty():
		return _free.pop_back()
	if is_combat_event(id) or _busy.is_empty():
		return null
	var victim: AudioStreamPlayer = _busy[0]
	for p: AudioStreamPlayer in _busy:
		if is_combat_event(String(_event.get(p.get_instance_id(), ""))):
			victim = p
			break
	victim.stop()
	release(victim)
	return _free.pop_back()


## Голос занят событием id (вызывать перед play()).
func claim(p: AudioStreamPlayer, id: String) -> void:
	_event[p.get_instance_id()] = id
	_count[id] = active(id) + 1
	_busy.append(p)


## Голос освободился: звук доиграл (сигнал finished) или голос забрали. Повторный вызов ничего не делает.
func release(p: AudioStreamPlayer) -> void:
	var iid: int = p.get_instance_id()
	if not _event.has(iid):
		return
	var id: String = String(_event[iid])
	_event.erase(iid)
	var n: int = active(id) - 1
	if n > 0:
		_count[id] = n
	else:
		_count.erase(id)
	_busy.erase(p)
	_free.append(p)


## Частые звуки боя: выстрелы, попадания, ранения, статусы, трейты.
static func is_combat_event(id: String) -> bool:
	return id.begins_with("sfx/gems/") or id.begins_with("sfx/specials/") or id.begins_with("sfx/enemies/") \
		or id.begins_with("sfx/status/") or id.begins_with("sfx/traits/")
