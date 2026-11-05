extends Node
## Доступ к балансовым данным для узлов. Сама загрузка — в GameData (используется и в тестах).

var data: GameData


func _ready() -> void:
	data = GameData.load_default()
	if not data.is_valid():
		push_error("Данные баланса содержат ошибки: %s" % str(data.errors))


func is_valid() -> bool:
	return data != null and data.is_valid()
