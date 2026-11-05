class_name NetProtocol
extends RefCounted
## Протокол LAN-мультиплеера «Гонка» (§11 PROMPT.md): константы, проверка сообщений, порядок мест.
## Все сообщения — словари; проверка типов защищает от мусора и несовместимых клиентов.

const VERSION: int = 1
const DEFAULT_PORT: int = 7777
const DISCOVERY_PORT: int = 7778
const MAX_PLAYERS: int = 4
const MIN_PLAYERS: int = 2
const COLORS: Array[String] = ["#7cc4ff", "#ff7ad9", "#4ade80", "#fbbf24"]
const BUILD_TIMERS: Array[int] = [45, 60, 90, 0]
## Длина матча по умолчанию — первый акт (до Обсидианового Короля). Вся игра — больше часа боя на 1×
## (бот на 48 волнах — 63 минуты), поэтому её в «Гонке» выбирает хост, а не значение по умолчанию.
const DEFAULT_RACE_WAVES: int = 42
## «Бесконечно» в настройке числа волн: волны идут, пока жив хоть один игрок; побеждает продержавшийся дольше.
const ENDLESS_WAVES: int = 0
const MAX_PAUSES: int = 3
const NAME_MAX: int = 20
const CHAT_MAX: int = 160
const CHAT_HISTORY: int = 50

## Команды симуляции, которые можно пересылать, и типы их полей.
const COMMAND_FIELDS: Dictionary = {
	"place": {"x": TYPE_INT, "y": TYPE_INT},
	"keep": {"x": TYPE_INT, "y": TYPE_INT},
	"downgrade": {"x": TYPE_INT, "y": TYPE_INT},
	"start_wave": {},
	"upgrade_luck": {},
	"combine": {"x": TYPE_INT, "y": TYPE_INT, "count": TYPE_INT},
	"forge": {"x": TYPE_INT, "y": TYPE_INT, "special": TYPE_STRING},
	"upgrade_special": {"x": TYPE_INT, "y": TYPE_INT},
	"merge_special": {"x": TYPE_INT, "y": TYPE_INT, "with_x": TYPE_INT, "with_y": TYPE_INT},
	"sell": {"x": TYPE_INT, "y": TYPE_INT},
	"sell_slate": {"x": TYPE_INT, "y": TYPE_INT},
	"break_wall": {"x": TYPE_INT, "y": TYPE_INT},
	"buy_life": {},
	"set_targeting": {"x": TYPE_INT, "y": TYPE_INT, "mode": TYPE_STRING},
	"toggle_tower": {"x": TYPE_INT, "y": TYPE_INT, "enabled": TYPE_BOOL},
	"give_gold": {"to": TYPE_INT, "amount": TYPE_INT},
	"make_slate": {"x": TYPE_INT, "y": TYPE_INT, "slate": TYPE_STRING},
	"combine_slates": {"x": TYPE_INT, "y": TYPE_INT, "with_x": TYPE_INT, "with_y": TYPE_INT},
	"move_slate": {"x": TYPE_INT, "y": TYPE_INT, "to_x": TYPE_INT, "to_y": TYPE_INT},
	"move_tower": {"x": TYPE_INT, "y": TYPE_INT, "to_x": TYPE_INT, "to_y": TYPE_INT},
	"polish": {"x": TYPE_INT, "y": TYPE_INT},
	"receive_gold": {"from": TYPE_INT, "amount": TYPE_INT},
}

## Сообщения игрока в матче (пересылаются хостом остальным) и обязательные поля.
const MATCH_FIELDS: Dictionary = {
	"cmd": {"cmd": TYPE_DICTIONARY},
	"hb": {"tick": TYPE_INT},
	"phase": {"round": TYPE_INT, "phase": TYPE_STRING},
	"ready": {"round": TYPE_INT},
	"cs": {"wave": TYPE_INT, "cs": TYPE_INT},
	"over": {"summary": TYPE_DICTIONARY},
	"watch": {"target": TYPE_INT, "on": TYPE_BOOL},
}

## Управляющие сообщения хоста.
const CONTROL_FIELDS: Dictionary = {
	"begin_wave": {"round": TYPE_INT},
	"force_build": {"round": TYPE_INT},
	"timer": {"round": TYPE_INT, "seconds": TYPE_FLOAT},
	"speed": {"speed": TYPE_INT},
	"pause": {"on": TYPE_BOOL},
	"player_left": {"id": TYPE_INT},
	"end": {"standings": TYPE_ARRAY},
}


static func _fields_ok(msg: Dictionary, fields: Dictionary) -> bool:
	for key: String in fields.keys():
		if not msg.has(key):
			return false
		var want: int = int(fields[key])
		var got: int = typeof(msg[key])
		if got != want and not (want == TYPE_FLOAT and got == TYPE_INT):
			return false
	return true


static func valid_command(cmd: Variant) -> bool:
	if not cmd is Dictionary:
		return false
	var d: Dictionary = cmd
	var t: String = String(d.get("type", ""))
	if not COMMAND_FIELDS.has(t) or not (d.get("tick") is int):
		return false
	if t == "upgrade_special" and d.has("with_x") and not (d["with_x"] is int and d.get("with_y") is int):
		return false
	return _fields_ok(d, COMMAND_FIELDS[t])


static func valid_match_msg(msg: Variant) -> bool:
	if not msg is Dictionary:
		return false
	var d: Dictionary = msg
	var t: String = String(d.get("t", ""))
	if not MATCH_FIELDS.has(t) or not _fields_ok(d, MATCH_FIELDS[t]):
		return false
	if t == "cmd":
		return valid_command(d["cmd"])
	return true


static func valid_control(msg: Variant) -> bool:
	if not msg is Dictionary:
		return false
	var d: Dictionary = msg
	var t: String = String(d.get("type", ""))
	return CONTROL_FIELDS.has(t) and _fields_ok(d, CONTROL_FIELDS[t])


static func sanitize_name(n: String) -> String:
	var clean: String = n.strip_edges().replace("\n", " ").left(NAME_MAX)
	return clean if not clean.is_empty() else "Player"


## Текст чата: одна строка без краевых пробелов, не длиннее CHAT_MAX. Пусто — не отправлять.
static func sanitize_chat(text: String) -> String:
	return text.replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges().left(CHAT_MAX)


## Seed игрока: при «честных камнях» у всех одинаковый, иначе — производный от индекса.
static func player_seed(match_seed: int, index: int, fair: bool) -> int:
	if fair:
		return match_seed & HashUtil.MASK32
	return HashUtil.combine(match_seed, 1000 + index)


## Порядок мест: выжившие выше, затем больше пройденных волн, больше жизней, больше очков, меньше время боя.
static func standings(entries: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Variant in entries:
		out.append(e as Dictionary)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var av: int = 1 if String(a.get("outcome", "")) == "victory" else 0
		var bv: int = 1 if String(b.get("outcome", "")) == "victory" else 0
		if av != bv:
			return av > bv
		if int(a.get("waves_cleared", 0)) != int(b.get("waves_cleared", 0)):
			return int(a.get("waves_cleared", 0)) > int(b.get("waves_cleared", 0))
		if int(a.get("lives", 0)) != int(b.get("lives", 0)):
			return int(a.get("lives", 0)) > int(b.get("lives", 0))
		if int(a.get("score", 0)) != int(b.get("score", 0)):
			return int(a.get("score", 0)) > int(b.get("score", 0))
		return float(a.get("combat_seconds", 0.0)) < float(b.get("combat_seconds", 0.0)))
	for i: int in out.size():
		out[i]["place"] = i + 1
	return out
