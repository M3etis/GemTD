extends TestCase
## Сетевой детерминизм без сокетов: реплика, получающая команды и такты порциями,
## должна прийти к той же контрольной сумме, что и оригинал.


func _owner_run(seed_value: int, waves: int) -> Dictionary:
	var sim: GameSim = new_sim(seed_value, {"max_waves": waves, "record_events": false})
	var stream: Array[Dictionary] = []
	sim.command_listener = func(cmd: Dictionary) -> void: stream.append({"kind": "cmd", "cmd": cmd.duplicate()})
	var bot: BotPlayer = BotPlayer.new(sim, "maze", seed_value)
	var guard: int = 0
	while not sim.is_over() and guard < 2_000_000:
		guard += 1
		if sim.phase == GameSim.Phase.COMBAT:
			sim.step()
			if sim.tick % 7 == 0:
				stream.append({"kind": "hb", "tick": sim.tick})
		else:
			bot.act()
			stream.append({"kind": "hb", "tick": sim.tick})
	stream.append({"kind": "hb", "tick": sim.tick})
	return {"sim": sim, "stream": stream}


func test_replica_matches_owner_with_chunked_delivery() -> void:
	var run: Dictionary = _owner_run(31337, 4)
	var owner: GameSim = run["sim"]
	var rep_sim: GameSim = new_sim(31337, {"max_waves": 4, "record_events": false})
	var rep: Replica = Replica.new(rep_sim)
	var waves: Array[int] = []
	var i: int = 0
	var stream: Array[Dictionary] = run["stream"]
	while i < stream.size():
		# Доставляем сообщения пачками разного размера, между ними — ограниченный шаг реплики.
		var chunk: int = 1 + (i * 7) % 23
		for k: int in chunk:
			if i >= stream.size():
				break
			var m: Dictionary = stream[i]
			if m["kind"] == "cmd":
				rep.push_command(m["cmd"])
			else:
				rep.heartbeat(int(m["tick"]))
			i += 1
		for e: Dictionary in rep.advance(37):
			waves.append(int(e["wave"]))
	rep.advance(1 << 30)
	assert_eq(rep_sim.checksum(), owner.checksum(), "реплика сошлась с владельцем")
	assert_eq(rep_sim.wave_checksums.size(), owner.wave_checksums.size())
	for w: int in owner.wave_checksums.size():
		assert_eq(int(rep_sim.wave_checksums[w]["checksum"]), int(owner.wave_checksums[w]["checksum"]), "волна %d" % (w + 1))


func test_replica_never_runs_ahead_of_heartbeat() -> void:
	var run: Dictionary = _owner_run(99, 2)
	var rep: Replica = Replica.new(new_sim(99, {"max_waves": 2, "record_events": false}))
	for m: Dictionary in run["stream"]:
		if m["kind"] == "cmd":
			rep.push_command(m["cmd"])
	rep.heartbeat(50)
	rep.advance(1 << 30)
	assert_true(rep.sim.tick <= 50, "без тактов реплика не шагает дальше")
