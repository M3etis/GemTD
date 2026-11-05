extends TestCase
## «Гонка»: игрок видит, что соперник наблюдает за его полем (сообщение watch через хоста).


func test_watch_message_tracks_watchers() -> void:
	assert_true(NetProtocol.valid_match_msg({"t": "watch", "target": 1, "on": true}))
	assert_false(NetProtocol.valid_match_msg({"t": "watch", "target": 1}), "нет on")
	var rs: RaceSession = RaceSession.new()
	rs.local_id = 1
	rs.replicas[2] = {"name": "Аня"}
	rs.replicas[3] = {"name": "Борис"}
	var got: Array = []
	rs.watched_changed.connect(func(id: int, on: bool) -> void: got.append([id, on]))
	rs.call("_on_match_message", 2, {"t": "watch", "target": 1, "on": true})
	rs.call("_on_match_message", 3, {"t": "watch", "target": 2, "on": true})
	assert_true(rs.watchers.has(2))
	assert_false(rs.watchers.has(3), "Борис смотрит не на нас")
	rs.call("_on_match_message", 2, {"t": "watch", "target": 1, "on": true})
	assert_eq(got, [[2, true]], "повтор без изменения — без сигнала")
	rs.call("_on_match_message", 2, {"t": "watch", "target": 1, "on": false})
	assert_false(rs.watchers.has(2))
	assert_eq(got, [[2, true], [2, false]])
	rs.free()
