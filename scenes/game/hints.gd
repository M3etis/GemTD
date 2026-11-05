class_name HintsController
extends RefCounted
## Контекстные подсказки при первых событиях (§8.5): первая воздушная волна, первый доступный рецепт,
## первый слейт в раунде, первая пара одинаковых спец-башен (слияние), первый босс, первые трейты
## и Покров, удача по карману, MVP, первая утечка, лишнее золото при максимальной удаче (огранка),
## первая финальная волна короткого забега.
## Каждая показывается один раз за всё время (Settings: general.hints_seen); отключается в настройках.

## Сколько золота должно скопиться при максимальной удаче, чтобы подсказать про огранку.
const POLISH_HINT_GOLD: int = 300

var game: Node


func _init(g: Node) -> void:
	game = g


func on_event(e: Dictionary) -> void:
	if not bool(Settings.get_value("gameplay", "hints")):
		return
	var sim: GameSim = game.sim
	var data: GameData = sim.data
	match String(e["type"]):
		"round_started":
			var n: int = sim.round_index
			var summary: Dictionary = WaveSpawner.summary(data, n)
			if data.is_air_wave(n):
				_show("air")
			if sim.is_finale(n):
				_show("finale", [Ui.finale_notes(data, sim.length_cfg)])
			elif data.is_boss_wave(n):
				_show("boss")
			var traits: Array = summary["traits"]
			if traits.has("shroud"):
				_show("shroud")
			elif not traits.is_empty():
				_show("traits")
			var cost: int = data.luck_cost(sim.luck)
			if cost >= 0 and sim.gold >= cost:
				_show("luck")
			elif cost < 0 and sim.gold >= POLISH_HINT_GOLD:
				# Удача на максимуме, а золото копится: куда его тратить — огранка в панели башни.
				_show("polish")
		"choice_ready":
			for a: Dictionary in ChoiceLogic.actions_for(sim, 0):
				if String(a["id"]).begins_with("forge"):
					_show("recipe")
			for cand: Dictionary in sim.candidates:
				if not BuildCommands.can_combine(sim, cand["cell"], 2).is_empty():
					continue
				_show("combine")
				break
			for cand2: Dictionary in sim.candidates:
				if not SlateBook.available_at(sim, cand2["cell"]).is_empty():
					_show("slate")
					break
		"special_forged":
			for t: TowerState in sim.towers:
				if BuildCommands.merge_partner(sim, t) != null:
					_show("merge", [String.num(BuildCommands.merge_inherit(data))])
					break
		"ready_for_wave":
			if not ChoiceLogic.board_forges(sim).is_empty():
				_show("recipe")
		"mvp_awarded":
			_show("mvp")
		"enemy_leaked":
			_show("leak")


## args — числа для подстановки в текст подсказки (%s).
func _show(id: String, args: Array = []) -> void:
	var seen: Array = Settings.get_value("general", "hints_seen")
	if seen.has(id):
		return
	seen = seen.duplicate()
	seen.append(id)
	Settings.set_value("general", "hints_seen", seen)
	var text: String = TranslationServer.translate("HINT_" + id.to_upper())
	Events.toast_requested.emit(text % args if not args.is_empty() else text, "hint")
