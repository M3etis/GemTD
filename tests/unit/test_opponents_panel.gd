extends TestCase
## Панель игроков «Гонки»: раз в 0.25 с числа обновляются на месте, строки пересобираются только при
## смене состава — иначе клик по золоту соперника, попавший на пересборку, терялся бы.


func _rows(gold: int, other_over: bool) -> Array[Dictionary]:
	return [
		{"id": 1, "name": "Я", "color": "#7cc4ff", "lives": 20, "wave": 3, "status": "build", "me": true, "gold": 50, "over": false},
		{"id": 2, "name": "Аня", "color": "#ff7ad9", "lives": 18, "wave": 3, "status": "combat", "me": false, "gold": gold, "over": other_over},
	] as Array[Dictionary]


func test_numbers_update_in_place() -> void:
	var p: OpponentsPanel = OpponentsPanel.new()
	p.update_rows(_rows(10, false), "")
	var list: VBoxContainer = p.get("_list")
	var first: Node = list.get_child(1)
	var nodes: Dictionary = p.get("_row_nodes")
	assert_eq((nodes[2]["gold"] as Label).text, "10")
	p.update_rows(_rows(35, false), "")
	assert_eq(list.get_child(1), first, "та же кнопка — клик не теряется")
	assert_eq(((p.get("_row_nodes") as Dictionary)[2]["gold"] as Label).text, "35")
	p.update_rows(_rows(35, true), "")
	assert_eq(String(p.get("_layout")).contains("2:false:false"), true, "соперник выбыл — кнопки золота больше нет")
	p.free()
