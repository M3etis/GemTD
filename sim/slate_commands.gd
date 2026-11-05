class_name SlateCommands
extends RefCounted
## Команды слейтов: сделать из гемов раунда, объединить два базовых, переложить (за золото, цена растёт), продать.
## Вызываются только из GameSim.apply() (и BuildCommands.sell для слейта).


## Слейт из кандидата в клетке c. Остальные кандидаты становятся стенами, а клетка c — проходимой:
## плита лежит на земле, лабиринт в этой клетке открывается (как в оригинале).
static func make(sim: GameSim, c: Vector2i, slate: String) -> Dictionary:
	if sim.phase != GameSim.Phase.CHOOSING:
		return BuildCommands._err("ERR_NOT_CHOOSING")
	if sim.candidate_at(c).is_empty():
		return BuildCommands._err("ERR_NOT_CANDIDATE")
	if sim.slate_by_cell.has(c):
		return BuildCommands._err("ERR_SLATE_HERE")
	var cells: Array = []
	for o: Dictionary in SlateBook.available_at(sim, c):
		if String(o["slate"]) == slate:
			cells = o["cells"]
	if cells.is_empty():
		return BuildCommands._err("ERR_SLATE_MISSING")
	var parts: Array[Dictionary] = []
	for cell: Vector2i in cells:
		var cand: Dictionary = sim.candidate_at(cell)
		parts.append({"cell": cell, "gem": cand["gem"], "quality": int(cand["quality"])})
	sim.finish_choice(c)
	sim.grid.set_cell(c, BoardGrid.Cell.EMPTY)
	sim.route.recompute()
	var s: TowerState = sim.add_slate(c, slate)
	var made: Dictionary = sim.stats["slates_made"]
	made[slate] = int(made.get(slate, 0)) + 1
	sim.combat.recompute_auras(sim)
	sim.emit_event({"type": "slate_made", "cell": c, "slate": slate, "parts": parts, "tower_id": s.id})
	sim.emit_event({"type": "path_changed", "length": sim.route.ground_length})
	return BuildCommands._ok()


## Два базовых слейта → составной в клетке c; второй исчезает, его клетка остаётся как была.
## Убийства и урон суммируются.
static func combine(sim: GameSim, c: Vector2i, with_cell: Vector2i) -> Dictionary:
	if not sim.is_build_phase():
		return BuildCommands._err("ERR_NOT_BUILD_PHASE")
	var a: TowerState = sim.slate_by_cell.get(c) as TowerState
	var b: TowerState = sim.slate_by_cell.get(with_cell) as TowerState
	if a == null or b == null or a == b:
		return BuildCommands._err("ERR_NOT_SLATE")
	var combo: String = SlateBook.combo_of(sim.data, a.slate_id, b.slate_id)
	if combo.is_empty():
		return BuildCommands._err("ERR_SLATE_NO_COMBO")
	sim.remove_slate(a)
	sim.remove_slate(b)
	var s: TowerState = sim.add_slate(c, combo)
	s.kills = a.kills + b.kills
	s.total_damage = a.total_damage + b.total_damage
	var made: Dictionary = sim.stats["slates_made"]
	made[combo] = int(made.get(combo, 0)) + 1
	sim.combat.recompute_auras(sim)
	sim.emit_event({"type": "slates_combined", "cell": c, "from": with_cell, "slate": combo,
		"parts": [a.slate_id, b.slate_id], "tower_id": s.id})
	return BuildCommands._ok()


## Цена следующего переноса слейта: economy.slate_move.base + step × число уже сделанных переносов (всех слейтов).
static func move_cost(sim: GameSim) -> int:
	var cfg: Dictionary = sim.data.economy["slate_move"]
	return int(cfg["base"]) + int(cfg["step"]) * sim.slate_moves


## Можно ли переложить слейт из c в to: "" или код ошибки. Слейт кладётся на любую клетку поля без другого
## слейта — пустую (и на путь), со стеной или с башней: он лежит на земле и строительству не мешает.
static func can_move(sim: GameSim, c: Vector2i, to: Vector2i) -> String:
	if not sim.is_build_phase():
		return "ERR_NOT_BUILD_PHASE"
	if not sim.slate_by_cell.has(c):
		return "ERR_NOT_SLATE"
	if to == c or not sim.grid.can_hold_slate(to):
		return "ERR_SLATE_TARGET"
	if sim.gold < move_cost(sim):
		return "ERR_NOT_ENOUGH_GOLD"
	return ""


## Переложить слейт (сколько угодно раз, каждый следующий перенос дороже).
static func move(sim: GameSim, c: Vector2i, to: Vector2i) -> Dictionary:
	var reason: String = can_move(sim, c, to)
	if not reason.is_empty():
		return BuildCommands._err(reason)
	var s: TowerState = sim.slate_by_cell[c]
	var cost: int = move_cost(sim)
	if cost > 0:
		sim.add_gold(-cost)
	sim.slate_moves += 1
	sim.slate_by_cell.erase(c)
	sim.grid.set_reserved(c, false)
	s.move_to(to)
	s.moves += 1
	sim.slate_by_cell[to] = s
	sim.grid.set_reserved(to, true)
	sim.combat.recompute_auras(sim)
	sim.emit_event({"type": "slate_moved", "from": c, "to": to, "slate": s.slate_id, "tower_id": s.id, "gold": cost})
	return BuildCommands._ok()


static func sell(sim: GameSim, c: Vector2i) -> Dictionary:
	if not sim.is_build_phase():
		return BuildCommands._err("ERR_NOT_BUILD_PHASE")
	var s: TowerState = sim.slate_by_cell.get(c) as TowerState
	if s == null:
		return BuildCommands._err("ERR_NOT_SLATE")
	var value: int = s.sell_value(sim.data)
	sim.remove_slate(s)
	sim.add_gold(value)
	sim.combat.recompute_auras(sim)
	sim.emit_event({"type": "slate_sold", "cell": c, "gold": value, "slate": s.slate_id})
	return BuildCommands._ok()
