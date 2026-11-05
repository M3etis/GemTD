extends TestCase
## Скорость матча «Гонки»: задаёт только хост, клиент видит текущую; команда, пришедшая во время
## загрузки сцены, не теряется.


func test_client_sees_current_speed() -> void:
	var top: TopBar = TopBar.new()
	var btns: Array[Button] = top.get("_speed_btns")
	top.set_speed_enabled(false)
	top.set_speed(2)
	assert_true(btns[1].button_pressed, "2× подсвечена")
	assert_false(btns[1].disabled, "текущая кнопка не серая — её видно")
	assert_true(btns[0].disabled and btns[2].disabled, "остальные недоступны")
	top.set_speed(4)
	assert_true(btns[2].button_pressed and not btns[2].disabled)
	assert_true(btns[1].disabled)
	top.set_speed_enabled(true)
	for b: Button in btns:
		assert_false(b.disabled, "у хоста все кнопки доступны")
	top.free()


func test_session_remembers_speed_and_pause() -> void:
	var rs: RaceSession = RaceSession.new()
	assert_eq(rs.speed, 1)
	rs.call("_on_control", {"type": "speed", "speed": 4})
	rs.call("_on_control", {"type": "pause", "on": true})
	assert_eq(rs.speed, 4, "контроллер применит её после загрузки сцены")
	assert_true(rs.paused)
	rs.free()
