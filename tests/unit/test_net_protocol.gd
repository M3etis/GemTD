extends TestCase


func test_valid_commands_pass() -> void:
	assert_true(NetProtocol.valid_command({"type": "place", "x": 3, "y": 4, "tick": 0}))
	assert_true(NetProtocol.valid_command({"type": "start_wave", "tick": 120}))
	assert_true(NetProtocol.valid_command({"type": "forge", "x": 1, "y": 2, "special": "cinder_crown", "tick": 5}))
	assert_true(NetProtocol.valid_command({"type": "toggle_tower", "x": 1, "y": 2, "enabled": false, "tick": 5}))
	assert_true(NetProtocol.valid_command({"type": "upgrade_special", "x": 1, "y": 2, "with_x": 3, "with_y": 4, "tick": 5}))


func test_bad_commands_rejected() -> void:
	assert_false(NetProtocol.valid_command({"type": "place", "x": 3, "tick": 0}), "нет y")
	assert_false(NetProtocol.valid_command({"type": "place", "x": "3", "y": 4, "tick": 0}), "x строкой")
	assert_false(NetProtocol.valid_command({"type": "place", "x": 3, "y": 4}), "нет tick")
	assert_false(NetProtocol.valid_command({"type": "give_gold", "tick": 0}), "неизвестная команда")
	assert_false(NetProtocol.valid_command("place"))
	assert_false(NetProtocol.valid_command({"type": "upgrade_special", "x": 1, "y": 2, "with_x": "a", "tick": 5}))


func test_match_and_control_messages() -> void:
	assert_true(NetProtocol.valid_match_msg({"t": "hb", "tick": 10}))
	assert_true(NetProtocol.valid_match_msg({"t": "cmd", "cmd": {"type": "buy_life", "tick": 3}}))
	assert_false(NetProtocol.valid_match_msg({"t": "cmd", "cmd": {"type": "buy_life"}}))
	assert_false(NetProtocol.valid_match_msg({"t": "hb"}))
	assert_false(NetProtocol.valid_match_msg({"t": "unknown"}))
	assert_true(NetProtocol.valid_control({"type": "begin_wave", "round": 2}))
	assert_true(NetProtocol.valid_control({"type": "timer", "round": 2, "seconds": 60}))
	assert_false(NetProtocol.valid_control({"type": "speed"}))


func test_names_and_seeds() -> void:
	assert_eq(NetProtocol.sanitize_name("  "), "Player")
	assert_eq(NetProtocol.sanitize_name("Аня\nБорис"), "Аня Борис")
	assert_eq(NetProtocol.sanitize_name("x".repeat(50)).length(), NetProtocol.NAME_MAX)
	assert_eq(NetProtocol.player_seed(1234, 0, true), NetProtocol.player_seed(1234, 3, true), "честные камни — один seed")
	assert_ne(NetProtocol.player_seed(1234, 0, false), NetProtocol.player_seed(1234, 1, false))


func test_standings_order() -> void:
	var list: Array = [
		{"id": 1, "outcome": "defeat", "waves_cleared": 7, "lives": 0, "score": 900, "combat_seconds": 100.0},
		{"id": 2, "outcome": "victory", "waves_cleared": 10, "lives": 3, "score": 800, "combat_seconds": 300.0},
		{"id": 3, "outcome": "victory", "waves_cleared": 10, "lives": 9, "score": 500, "combat_seconds": 320.0},
		{"id": 4, "outcome": "left", "waves_cleared": 7, "lives": 5, "score": 100, "combat_seconds": 90.0},
	]
	var s: Array[Dictionary] = NetProtocol.standings(list)
	var ids: Array[int] = []
	for e: Dictionary in s:
		ids.append(int(e["id"]))
	assert_eq(ids, [3, 2, 4, 1] as Array[int], "победители по жизням, затем волны, затем жизни")
	assert_eq(int(s[0]["place"]), 1)
	assert_eq(int(s[3]["place"]), 4)


## Сообщения матча до подписки сцены копятся и отдаются по порядку (гонка при старте матча).
func test_match_messages_buffered_until_scene_listens() -> void:
	var net: Node = (load("res://autoload/net.gd") as GDScript).new()
	var got: Array = []
	net.call("_deliver_match", 2, {"t": "cmd", "n": 1})
	net.call("_deliver_match", 2, {"t": "cmd", "n": 2})
	var listener: Callable = func(from: int, msg: Dictionary) -> void: got.append([from, int(msg["n"])])
	net.connect("match_message", listener)
	net.call("_deliver_match", 2, {"t": "cmd", "n": 3})
	assert_eq(got.size(), 1, "после подписки — сразу в сигнал")
	var backlog: Array[Dictionary] = net.call("take_backlog")
	assert_eq(backlog.size(), 2)
	assert_eq(int(backlog[0]["msg"]["n"]), 1, "порядок сохранён")
	assert_eq((net.call("take_backlog") as Array).size(), 0, "забирается один раз")
	net.disconnect("match_message", listener)
	net.free()


func test_chat_text_sanitized() -> void:
	assert_eq(NetProtocol.sanitize_chat("  привет\nмир\t "), "привет мир", "одна строка, без краевых пробелов")
	assert_eq(NetProtocol.sanitize_chat(" \n "), "", "пустое не отправляется")
	assert_eq(NetProtocol.sanitize_chat("x".repeat(500)).length(), NetProtocol.CHAT_MAX)


## История чата живёт в Net: лобби и матч показывают её при открытии; длина ограничена.
func test_chat_history_capped_and_offline_send_ignored() -> void:
	var net: Node = (load("res://autoload/net.gd") as GDScript).new()
	var got: Array = []
	net.connect("chat_received", func(sender: String, text: String, _c: Color) -> void: got.append([sender, text]))
	for i: int in NetProtocol.CHAT_HISTORY + 5:
		net.call("_post_chat", "Аня", "m%d" % i, Color.WHITE)
	var log: Array[Dictionary] = net.get("chat_log")
	assert_eq(log.size(), NetProtocol.CHAT_HISTORY)
	assert_eq(String(log[0]["text"]), "m5", "старые вытесняются")
	assert_eq(got.size(), NetProtocol.CHAT_HISTORY + 5, "каждое сообщение — в сигнал")
	net.call("send_chat", "без соединения")
	assert_eq((net.get("chat_log") as Array).size(), NetProtocol.CHAT_HISTORY, "офлайн отправка ничего не делает")
	net.free()
