extends Node
## Стресс-тест производительности (§13 PROMPT.md): игровая сцена в режиме "stress".
## Запуск: godot --path . res://tests/perf/stress.tscn -- --preset=high [--seconds=60]
## Итоги — в docs/perf.md (по строке на пресет, данные в docs/perf/results.json).


func _ready() -> void:
	Game.run_config = {"mode": "stress"}
	Game.goto_scene.call_deferred("game")
