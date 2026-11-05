class_name BuildCommands
extends RefCounted
## Команды фазы строительства: Combine, Forge, улучшение и слияние спец-башен, огранка, перенос башни,
## продажа, разрушение стен, покупка жизней, приоритет цели. Вызываются только из GameSim.apply().


static func _err(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _ok() -> Dictionary:
	return {"ok": true, "reason": ""}


# --- Combine ×2 / ×4 ---------------------------------------------------------

## Сколько кандидатов этого раунда совпадает с кандидатом в клетке (тип + качество), включая его.
static func duplicates(sim: GameSim, c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var me: Dictionary = sim.candidate_at(c)
	if me.is_empty():
		return out
	for cand: Dictionary in sim.candidates:
		if cand["gem"] == me["gem"] and int(cand["quality"]) == int(me["quality"]):
			out.append(cand["cell"])
	return out


static func can_combine(sim: GameSim, c: Vector2i, count: int) -> String:
	if sim.phase != GameSim.Phase.CHOOSING:
		return "ERR_NOT_CHOOSING"
	var me: Dictionary = sim.candidate_at(c)
	if me.is_empty():
		return "ERR_NOT_CANDIDATE"
	if count != 2 and count != 4:
		return "ERR_UNKNOWN_COMMAND"
	if duplicates(sim, c).size() < count:
		return "ERR_COMBINE_NEED_%d" % count
	if int(me["quality"]) + (1 if count == 2 else 2) > sim.data.quality_count():
		return "ERR_COMBINE_MAX"
	return ""


static func combine(sim: GameSim, c: Vector2i, count: int) -> Dictionary:
	var reason: String = can_combine(sim, c, count)
	if not reason.is_empty():
		return _err(reason)
	var me: Dictionary = sim.candidate_at(c)
	var used: Array[Vector2i] = []
	for cell: Vector2i in duplicates(sim, c):
		if cell != c and used.size() < count - 1:
			used.append(cell)
	var q: int = int(me["quality"]) + (1 if count == 2 else 2)
	var t: TowerState = sim.add_gem_tower(c, String(me["gem"]), q)
	sim.emit_event({"type": "gems_combined", "cell": c, "gem": t.gem_id, "quality": q, "from": used, "count": count, "tower_id": t.id})
	sim.finish_choice(c)
	return _ok()


# --- Forge (спец-башни) ------------------------------------------------------

static func forge(sim: GameSim, c: Vector2i, special: String) -> Dictionary:
	# Рецепт можно собрать в любой момент матча, и в бою: в «Гонке» после последнего компонента
	# волна стартует сразу, как только все готовы. Путь не меняется — компоненты GEM становятся ROCK.
	if sim.is_over() or sim.damage_test:
		return _err("ERR_GAME_OVER")
	var sp: Dictionary = sim.data.special(special)
	if sp.is_empty():
		return _err("ERR_UNKNOWN_SPECIAL")
	var p: Dictionary = RecipeBook.pool_for(sim, c)
	if p.is_empty():
		return _err("ERR_FORGE_NOT_COMPONENT")
	var items: Array = RecipeBook.match_recipe(sp["recipe"], p["required"], p["pool"])
	if items.is_empty():
		return _err("ERR_FORGE_MISSING")
	var cost: int = int(sp["forge_cost"])
	if sim.gold < cost:
		return _err("ERR_NOT_ENOUGH_GOLD")
	if cost > 0:
		sim.add_gold(-cost)
	var from_candidate: bool = String(p["required"]["kind"]) == "cand"
	var consumed: Array[Vector2i] = []
	var parts: Array[Dictionary] = []
	var one_hit: bool = true
	# Огранка башен-компонентов не пропадает: вложенное золото переходит в спец-башню (продажа вернёт 60 %),
	# уровень огранки — больший из компонентов, как при слиянии.
	var carried_gold: int = 0
	var carried_polish: int = 0
	for item: Dictionary in items:
		var cell: Vector2i = item["cell"]
		parts.append({"cell": cell, "gem": item["gem"], "quality": int(item["quality"])})
		if String(item["kind"]) == "tower":
			var part: TowerState = sim.tower_by_cell[cell]
			carried_gold += part.invested_gold
			carried_polish = maxi(carried_polish, part.polish)
		if cell == c:
			continue
		consumed.append(cell)
		if String(item["kind"]) == "tower":
			one_hit = false
			sim.tower_to_wall(sim.tower_by_cell[cell])
	if not from_candidate:
		sim.remove_tower(sim.tower_by_cell[c])
	var t: TowerState = sim.add_special_tower(c, special)
	t.invested_gold += carried_gold
	if t.deals_damage():
		t.polish = carried_polish
	var forged: Dictionary = sim.stats["specials_forged"]
	forged[special] = int(forged.get(special, 0)) + 1
	sim.emit_event({"type": "special_forged", "cell": c, "special": special, "consumed": consumed, "parts": parts,
		"one_hit": one_hit and from_candidate, "tower_id": t.id})
	if from_candidate:
		sim.finish_choice(c)
	else:
		sim.combat.recompute_auras(sim)
	return _ok()


# --- Улучшение спец-башни ------------------------------------------------------

## Требование следующего уровня: {to_level, gold, gem, min_quality} или {} если максимум.
static func next_upgrade(sim: GameSim, t: TowerState) -> Dictionary:
	if t == null or not t.is_special() or t.level >= 3:
		return {}
	var up: Dictionary = sim.data.special_upgrade(t.special_id, t.level + 1)
	if up.is_empty():
		return {}
	var out: Dictionary = up.duplicate()
	out["to_level"] = t.level + 1
	return out


static func candidate_fits_upgrade(cand: Dictionary, up: Dictionary) -> bool:
	return not cand.is_empty() and String(cand["gem"]) == String(up["gem"]) and int(cand["quality"]) >= int(up["min_quality"])


static func upgrade_special(sim: GameSim, c: Vector2i, with_cell: Vector2i) -> Dictionary:
	if not sim.is_build_phase():
		return _err("ERR_NOT_BUILD_PHASE")
	var t: TowerState = sim.tower_by_cell.get(c) as TowerState
	if t == null or not t.is_special():
		return _err("ERR_NOT_SPECIAL")
	var up: Dictionary = next_upgrade(sim, t)
	if up.is_empty():
		return _err("ERR_SPECIAL_MAX")
	var needs_gem: bool = not String(up["gem"]).is_empty()
	var cand: Dictionary = {}
	if needs_gem:
		if sim.phase != GameSim.Phase.CHOOSING:
			return _err("ERR_UPGRADE_NEEDS_GEM")
		cand = sim.candidate_at(with_cell)
		if not candidate_fits_upgrade(cand, up):
			return _err("ERR_UPGRADE_NEEDS_GEM")
	if sim.gold < int(up["gold"]):
		return _err("ERR_NOT_ENOUGH_GOLD")
	sim.add_gold(-int(up["gold"]))
	t.invested_gold += int(up["gold"])
	t.level = int(up["to_level"])
	t.refresh_stats(sim.data)
	sim.combat.recompute_auras(sim)
	sim.emit_event({"type": "special_upgraded", "cell": c, "special": t.special_id, "level": t.level, "tower_id": t.id,
		"with": with_cell if needs_gem else Vector2i(-1, -1)})
	if needs_gem:
		# Гем-компонент поглощён: в этом раунде новой башни нет, все кандидаты становятся стенами.
		sim.finish_choice(Vector2i(-1, -1))
	return _ok()


# --- Слияние двух одинаковых спец-башен ---------------------------------------------

## Доля второй башни, которую наследует слитая (economy.special_merge.inherit).
static func merge_inherit(data: GameData) -> float:
	return float(data.economy["special_merge"]["inherit"])


static func can_merge(sim: GameSim, t: TowerState, other: TowerState) -> String:
	if not sim.is_build_phase():
		return "ERR_NOT_BUILD_PHASE"
	if t == null or other == null or not t.is_special() or not other.is_special():
		return "ERR_NOT_SPECIAL"
	if t == other or t.special_id != other.special_id:
		return "ERR_MERGE_DIFFERENT"
	if t.is_merged() or other.is_merged():
		return "ERR_MERGE_ALREADY"
	return ""


## С какой башней сливать выбранную: такая же неслитая спец-башня, сильнейшая (уровень, урон), иначе null.
static func merge_partner(sim: GameSim, t: TowerState) -> TowerState:
	if t == null or not t.is_special() or t.is_merged():
		return null
	var best: TowerState = null
	for o: TowerState in sim.towers:
		if o == t or o.special_id != t.special_id or o.is_merged():
			continue
		if best == null or o.level > best.level or (o.level == best.level and o.total_damage > best.total_damage):
			best = o
	return best


## Башня в c остаётся и становится слитой, башня в with_cell становится стеной. Свой уровень — больший
## из двух, унаследованный (merge_level) — меньший: результат не зависит от того, какую башню выбрали.
## Вложенное золото, урон и убийства суммируются, MVP — больший; продажа слитой вернёт обе.
static func merge_special(sim: GameSim, c: Vector2i, with_cell: Vector2i) -> Dictionary:
	var t: TowerState = sim.tower_by_cell.get(c) as TowerState
	var other: TowerState = sim.tower_by_cell.get(with_cell) as TowerState
	var reason: String = can_merge(sim, t, other)
	if not reason.is_empty():
		return _err(reason)
	t.merge_level = mini(t.level, other.level)
	t.level = maxi(t.level, other.level)
	t.invested_gold += other.invested_gold
	t.total_damage += other.total_damage
	t.kills += other.kills
	t.mvp = maxi(t.mvp, other.mvp)
	t.polish = maxi(t.polish, other.polish)
	sim.tower_to_wall(other)
	t.refresh_stats(sim.data)
	sim.combat.recompute_auras(sim)
	sim.emit_event({"type": "special_merged", "cell": c, "from": with_cell, "special": t.special_id, "level": t.level,
		"inherited": t.merge_level, "tower_id": t.id})
	return _ok()


# --- Огранка: куда тратить золото в поздней игре -----------------------------------------

## Цена следующего уровня огранки башни t: base_cost × growthᵘʳᵒᵛᵉⁿʸ, -1 — максимум.
## Цена растёт быстрее пользы (+damage_per_level за уровень): лишнее золото превращается в силу медленно,
## и даже полная огранка одной башни (≈ 5.7 тыс. золота) — +30 % её урона, как семь-восемь стаков MVP.
## Башням поддержки без урона (аура скорости, знамя, морозная аура) огранка недоступна: ей нечего усиливать.
static func polish_cost(sim: GameSim, t: TowerState) -> int:
	var cfg: Dictionary = sim.data.economy["polish"]
	if t == null or not t.deals_damage() or t.polish >= int(cfg["max_level"]):
		return -1
	return int(roundf(float(cfg["base_cost"]) * pow(float(cfg["growth"]), float(t.polish))))


static func polish(sim: GameSim, c: Vector2i) -> Dictionary:
	if not sim.is_build_phase():
		return _err("ERR_NOT_BUILD_PHASE")
	var t: TowerState = sim.tower_by_cell.get(c) as TowerState
	if t == null:
		return _err("ERR_NOT_TOWER")
	if not t.deals_damage():
		return _err("ERR_POLISH_NO_DAMAGE")
	var cost: int = polish_cost(sim, t)
	if cost < 0:
		return _err("ERR_POLISH_MAX")
	if sim.gold < cost:
		return _err("ERR_NOT_ENOUGH_GOLD")
	sim.add_gold(-cost)
	t.invested_gold += cost
	t.polish += 1
	sim.emit_event({"type": "tower_polished", "cell": c, "level": t.polish, "tower_id": t.id, "gold": cost})
	sim.emit_event({"type": "tower_changed", "cell": c})
	return _ok()


# --- Перенос башни ----------------------------------------------------------------

## Цена следующего переноса башни: economy.tower_move.base + step × число уже сделанных переносов.
static func tower_move_cost(sim: GameSim) -> int:
	var cfg: Dictionary = sim.data.economy["tower_move"]
	return int(cfg["base"]) + int(cfg["step"]) * sim.tower_moves


## Куда можно перенести башню из c: "" или код ошибки. На стену или другую башню — меняются местами
## (лабиринт тот же), на пустую клетку — башня переезжает, а её клетка освобождается: путь пересчитывается
## и не должен перекрыться. В зону у точек маршрута и на камни раунда переносить нельзя.
static func can_move_tower(sim: GameSim, c: Vector2i, to: Vector2i) -> String:
	if not sim.is_build_phase():
		return "ERR_NOT_BUILD_PHASE"
	if not sim.tower_by_cell.has(c):
		return "ERR_NOT_TOWER"
	if to == c or not sim.grid.in_bounds(to):
		return "ERR_MOVE_TARGET"
	match sim.grid.get_cell(to):
		BoardGrid.Cell.ROCK, BoardGrid.Cell.GEM:
			pass
		BoardGrid.Cell.EMPTY:
			if sim.grid.is_no_build(to):
				return "ERR_NO_BUILD_ZONE"
			if not _path_ok_after_move(sim, c, to):
				return "ERR_BLOCKS_PATH"
		_:
			return "ERR_MOVE_TARGET"
	if sim.gold < tower_move_cost(sim):
		return "ERR_NOT_ENOUGH_GOLD"
	return ""


## Путь не перекрыт, если клетка c освободится, а to станет занятой.
static func _path_ok_after_move(sim: GameSim, c: Vector2i, to: Vector2i) -> bool:
	sim.grid.astar.set_point_solid(c, false)
	var extra: Array[Vector2i] = [to]
	var res: Dictionary = sim.route.compute(extra)
	sim.grid.astar.set_point_solid(c, true)
	return bool(res["ok"])


static func move_tower(sim: GameSim, c: Vector2i, to: Vector2i) -> Dictionary:
	var reason: String = can_move_tower(sim, c, to)
	if not reason.is_empty():
		return _err(reason)
	var t: TowerState = sim.tower_by_cell[c]
	var cost: int = tower_move_cost(sim)
	if cost > 0:
		sim.add_gold(-cost)
	sim.tower_moves += 1
	var swap: String = ""
	var other_id: int = -1
	match sim.grid.get_cell(to):
		BoardGrid.Cell.ROCK:
			swap = "wall"
			sim.rocks.erase(to)
			sim.rocks.append(c)
			sim.grid.set_cell(c, BoardGrid.Cell.ROCK)
			sim.grid.set_cell(to, BoardGrid.Cell.GEM)
			sim.tower_by_cell.erase(c)
		BoardGrid.Cell.GEM:
			swap = "tower"
			var other: TowerState = sim.tower_by_cell[to]
			other_id = other.id
			other.move_to(c)
			sim.tower_by_cell[c] = other
		_:
			sim.grid.set_cell(c, BoardGrid.Cell.EMPTY)
			sim.grid.set_cell(to, BoardGrid.Cell.GEM)
			sim.tower_by_cell.erase(c)
	t.move_to(to)
	sim.tower_by_cell[to] = t
	sim.combat.recompute_auras(sim)
	sim.emit_event({"type": "tower_moved", "from": c, "to": to, "tower_id": t.id, "swap": swap, "other_id": other_id, "gold": cost})
	if swap.is_empty():
		sim.route.recompute()
		sim.stats["max_path_length"] = maxf(float(sim.stats["max_path_length"]), sim.route.ground_length)
		sim.emit_event({"type": "path_changed", "length": sim.route.ground_length})
	return _ok()


# --- Продажа, стены, жизни -------------------------------------------------------

static func sell(sim: GameSim, c: Vector2i) -> Dictionary:
	if not sim.is_build_phase():
		return _err("ERR_NOT_BUILD_PHASE")
	var t: TowerState = sim.tower_by_cell.get(c) as TowerState
	# Только слейт в клетке — продаётся он (старые реплеи и бот). Если там и башня, «sell» — это башня,
	# а слейт под ней продаёт отдельная команда sell_slate.
	if t == null and sim.slate_by_cell.has(c):
		return SlateCommands.sell(sim, c)
	if t == null:
		return _err("ERR_NOT_TOWER")
	var value: int = t.sell_value(sim.data)
	sim.tower_to_wall(t)
	sim.add_gold(value)
	sim.combat.recompute_auras(sim)
	sim.emit_event({"type": "tower_sold", "cell": c, "gold": value, "special": t.special_id, "gem": t.gem_id})
	return _ok()


static func break_wall_cost(sim: GameSim) -> int:
	var cfg: Dictionary = sim.data.economy["break_wall"]
	return int(cfg["base"]) + int(cfg["step"]) * sim.walls_broken


static func break_wall(sim: GameSim, c: Vector2i) -> Dictionary:
	if not sim.is_build_phase():
		return _err("ERR_NOT_BUILD_PHASE")
	if sim.grid.get_cell(c) != BoardGrid.Cell.ROCK:
		return _err("ERR_NOT_WALL")
	var cost: int = break_wall_cost(sim)
	if sim.gold < cost:
		return _err("ERR_NOT_ENOUGH_GOLD")
	sim.add_gold(-cost)
	sim.walls_broken += 1
	sim.grid.set_cell(c, BoardGrid.Cell.EMPTY)
	sim.rocks.erase(c)
	sim.route.recompute()
	sim.emit_event({"type": "wall_broken", "cell": c, "gold": cost})
	sim.emit_event({"type": "path_changed", "length": sim.route.ground_length})
	return _ok()


static func buy_life_cost(sim: GameSim) -> int:
	var cfg: Dictionary = sim.data.economy["buy_life"]
	return int(cfg["base"]) + int(cfg["step"]) * sim.lives_bought


static func buy_life(sim: GameSim) -> Dictionary:
	if not sim.is_build_phase():
		return _err("ERR_NOT_BUILD_PHASE")
	if sim.lives >= sim.max_lives:
		return _err("ERR_LIVES_FULL")
	var cost: int = buy_life_cost(sim)
	if sim.gold < cost:
		return _err("ERR_NOT_ENOUGH_GOLD")
	sim.add_gold(-cost)
	sim.lives_bought += 1
	sim.lives += 1
	sim.emit_event({"type": "lives_changed", "lives": sim.lives, "delta": 1})
	sim.emit_event({"type": "life_bought", "gold": cost})
	return _ok()


# --- Золото между игроками «Гонки» ----------------------------------------------

## Передача золота сопернику to (peer id). Получатель зачисляет его своей командой receive_gold,
## поэтому оба поля и их реплики остаются детерминированными. После выбывания передавать нельзя:
## итог уже отправлен, и реплика разошлась бы с ним.
static func give_gold(sim: GameSim, to: int, amount: int) -> Dictionary:
	if sim.is_over():
		return _err("ERR_GAME_OVER")
	if amount <= 0 or to <= 0:
		return _err("ERR_GIFT_AMOUNT")
	if sim.gold < amount:
		return _err("ERR_NOT_ENOUGH_GOLD")
	sim.add_gold(-amount)
	sim.emit_event({"type": "gold_sent", "to": to, "amount": amount})
	return _ok()


## Зачисление золота от соперника from. Не считается заработанным (stats.gold_earned).
static func receive_gold(sim: GameSim, from: int, amount: int) -> Dictionary:
	if sim.is_over():
		return _err("ERR_GAME_OVER")
	if amount <= 0:
		return _err("ERR_GIFT_AMOUNT")
	sim.gold += amount
	sim.emit_event({"type": "gold_changed", "gold": sim.gold, "delta": amount})
	sim.emit_event({"type": "gold_received", "from": from, "amount": amount})
	return _ok()


# --- Управление башней ---------------------------------------------------------

static func set_targeting(sim: GameSim, c: Vector2i, mode: String) -> Dictionary:
	if sim.is_over():
		return _err("ERR_GAME_OVER")
	var t: TowerState = sim.tower_by_cell.get(c) as TowerState
	if t == null:
		return _err("ERR_NOT_TOWER")
	if not TowerState.TARGETING_MODES.has(mode):
		return _err("ERR_UNKNOWN_COMMAND")
	t.targeting = mode
	sim.emit_event({"type": "tower_changed", "cell": c})
	return _ok()


static func toggle_tower(sim: GameSim, c: Vector2i, enabled: bool) -> Dictionary:
	if sim.is_over():
		return _err("ERR_GAME_OVER")
	var t: TowerState = sim.tower_by_cell.get(c) as TowerState
	if t == null:
		return _err("ERR_NOT_TOWER")
	t.enabled = enabled
	sim.emit_event({"type": "tower_changed", "cell": c})
	return _ok()
