class_name Replica
extends RefCounted
## Реплика поля соперника: применяет его команды строго на их тиках и шагает
## не дальше последнего такта (heartbeat) владельца. Детерминизм гарантирует совпадение с оригиналом.

var sim: GameSim
var queue: Array = []
var hb: int = 0


func _init(target: GameSim) -> void:
	sim = target


func push_command(cmd: Dictionary) -> void:
	queue.append(cmd)


func heartbeat(tick: int) -> void:
	hb = maxi(hb, tick)


## Продвигает реплику. Возвращает записи wave_checksums, появившиеся за вызов.
func advance(budget: int) -> Array[Dictionary]:
	var finished: Array[Dictionary] = []
	while budget > 0:
		budget -= 1
		if not queue.is_empty() and int((queue[0] as Dictionary)["tick"]) <= sim.tick:
			var cmd: Dictionary = queue.pop_front()
			var res: Dictionary = sim.apply(cmd)
			if not res["ok"]:
				push_warning("Реплика: команда %s не применилась (%s)" % [cmd["type"], res["reason"]])
			continue
		if sim.phase == GameSim.Phase.COMBAT and sim.tick < hb:
			var next_cmd: int = int((queue[0] as Dictionary)["tick"]) if not queue.is_empty() else 1 << 40
			if sim.tick < next_cmd:
				var before: int = sim.wave_checksums.size()
				sim.step()
				if sim.wave_checksums.size() > before:
					finished.append(sim.wave_checksums[sim.wave_checksums.size() - 1])
				continue
		break
	return finished
