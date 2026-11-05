extends TestCase
## «Гонка»: передача золота. Отправитель — give_gold, получатель зачисляет своей командой receive_gold,
## поэтому оба поля и их реплики детерминированы.


func test_give_and_receive_gold() -> void:
	var a: GameSim = new_sim()
	var b: GameSim = new_sim()
	a.gold = 100
	b.gold = 5
	var earned: int = int(b.stats["gold_earned"])
	assert_eq(String(a.apply({"type": "give_gold", "to": 2, "amount": 150})["reason"]), "ERR_NOT_ENOUGH_GOLD")
	assert_eq(String(a.apply({"type": "give_gold", "to": 2, "amount": 0})["reason"]), "ERR_GIFT_AMOUNT")
	assert_true(a.apply({"type": "give_gold", "to": 2, "amount": 40})["ok"])
	assert_eq(a.gold, 60)
	assert_true(b.apply({"type": "receive_gold", "from": 1, "amount": 40})["ok"])
	assert_eq(b.gold, 45)
	assert_eq(int(b.stats["gold_earned"]), earned, "подарок не считается заработанным")
	assert_eq(String((b.command_log.back() as Dictionary)["type"]), "receive_gold", "зачисление пишется в реплей")
	b.phase = GameSim.Phase.DEFEAT
	assert_false(b.apply({"type": "receive_gold", "from": 1, "amount": 10})["ok"], "выбывшему не зачисляется")
	assert_true(NetProtocol.valid_command({"type": "give_gold", "to": 2, "amount": 40, "tick": 3}))
	assert_true(NetProtocol.valid_command({"type": "receive_gold", "from": 1, "amount": 40, "tick": 3}))


func test_session_credits_gift_addressed_to_us() -> void:
	var rs: RaceSession = RaceSession.new()
	rs.local_id = 1
	rs.local_sim = new_sim()
	rs.local_sim.gold = 0
	var other: GameSim = new_sim()
	other.gold = 100
	rs.replicas[2] = {"name": "Аня", "replica": Replica.new(other), "sim": other, "checksums": {}}
	rs.call("_on_match_message", 2, {"t": "cmd", "cmd": {"type": "give_gold", "to": 3, "amount": 30, "tick": 0}})
	rs.call("_on_match_message", 2, {"t": "cmd", "cmd": {"type": "give_gold", "to": 1, "amount": 25, "tick": 0}})
	assert_eq(rs.local_sim.gold, 0, "зачисление — в _process, когда команды уже уходят в сеть")
	rs.call("_process", 0.0)
	assert_eq(rs.local_sim.gold, 25, "чужой подарок (игроку 3) не зачислен")
	rs.call("_process", 0.0)
	assert_eq(rs.local_sim.gold, 25, "зачисляется один раз")
	rs.free()
