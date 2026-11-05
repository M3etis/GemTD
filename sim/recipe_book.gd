class_name RecipeBook
extends RefCounted
## Поиск рецептов спец-башен. Компоненты — только базовые гемы точного типа и качества.
## Элемент пула: {kind: "cand"|"tower", gem, quality, cell}.


## Подбор различных элементов пула под рецепт так, чтобы элемент required занял один из слотов.
## Возвращает элементы в порядке компонентов рецепта или [] если невозможно.
static func match_recipe(recipe: Array, required: Dictionary, pool: Array) -> Array:
	for i: int in recipe.size():
		var comp: Dictionary = recipe[i]
		if not _fits(comp, required):
			continue
		var chosen: Array = []
		chosen.resize(recipe.size())
		chosen[i] = required
		var used: Array = [required]
		if _fill(recipe, 0, chosen, used, pool):
			return chosen
	return []


static func _fits(comp: Dictionary, item: Dictionary) -> bool:
	return String(comp["gem"]) == String(item["gem"]) and int(comp["quality"]) == int(item["quality"])


static func _fill(recipe: Array, index: int, chosen: Array, used: Array, pool: Array) -> bool:
	if index >= recipe.size():
		return true
	if chosen[index] != null:
		return _fill(recipe, index + 1, chosen, used, pool)
	for item: Dictionary in pool:
		if used.has(item) or not _fits(recipe[index], item):
			continue
		chosen[index] = item
		used.append(item)
		if _fill(recipe, index + 1, chosen, used, pool):
			return true
		used.pop_back()
		chosen[index] = null
	return false


static func candidate_item(cand: Dictionary) -> Dictionary:
	return {"kind": "cand", "gem": cand["gem"], "quality": int(cand["quality"]), "cell": cand["cell"]}


static func tower_item(t: TowerState) -> Dictionary:
	return {"kind": "tower", "gem": t.gem_id, "quality": t.quality, "cell": t.cell, "id": t.id}


## Пул для «сплавления» в клетке: кандидаты этого раунда (если сплавляем кандидата) и гем-башни на поле.
## Кандидаты идут первыми — они всё равно станут стенами.
static func pool_for(sim: GameSim, cell: Vector2i) -> Dictionary:
	var required: Dictionary = {}
	var pool: Array = []
	var cand: Dictionary = sim.candidate_at(cell) if sim.phase == GameSim.Phase.CHOOSING else {}
	if not cand.is_empty():
		required = candidate_item(cand)
		for other: Dictionary in sim.candidates:
			if other["cell"] != cell:
				pool.append(candidate_item(other))
	else:
		var t: TowerState = sim.tower_by_cell.get(cell) as TowerState
		if t == null or t.is_special():
			return {}
		required = tower_item(t)
	for t2: TowerState in sim.towers:
		if not t2.is_special() and t2.cell != cell:
			pool.append(tower_item(t2))
	return {"required": required, "pool": pool}


## Все спец-башни, которые можно сплавить в клетке: [{special, items}].
static func available_at(sim: GameSim, cell: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var p: Dictionary = pool_for(sim, cell)
	if p.is_empty():
		return out
	for sp: Dictionary in sim.data.specials:
		var items: Array = match_recipe(sp["recipe"], p["required"], p["pool"])
		if not items.is_empty():
			out.append({"special": String(sp["id"]), "items": items})
	return out


## Прогресс рецепта по уже стоящим башням и (опционально) кандидатам:
## {have, kept, total, parts:[{gem, quality, owned, candidate}]}. owned — компонент есть (башня или кандидат),
## candidate — он пока только среди кандидатов раунда (ещё не оставлен); kept — сколько частей уже башни.
## Башни подбираются первыми: кандидат засчитывается, только если такой башни нет.
static func progress(sim: GameSim, special: String, include_candidates: bool = true) -> Dictionary:
	var sp: Dictionary = sim.data.special(special)
	var pool: Array = []
	for t: TowerState in sim.towers:
		if not t.is_special():
			pool.append(tower_item(t))
	if include_candidates:
		for c: Dictionary in sim.candidates:
			pool.append(candidate_item(c))
	var used: Array = []
	var parts: Array[Dictionary] = []
	var have: int = 0
	var kept: int = 0
	for comp: Dictionary in sp.get("recipe", []):
		var match_item: Dictionary = {}
		for item: Dictionary in pool:
			if not used.has(item) and _fits(comp, item):
				used.append(item)
				match_item = item
				break
		var owned: bool = not match_item.is_empty()
		var cand: bool = owned and String(match_item["kind"]) == "cand"
		if owned:
			have += 1
			if not cand:
				kept += 1
		parts.append({"gem": comp["gem"], "quality": int(comp["quality"]), "owned": owned, "candidate": cand})
	return {"have": have, "kept": kept, "total": parts.size(), "parts": parts}


## Уже собранные спец-башни этого рецепта на поле.
static func built(sim: GameSim, special: String) -> Array[TowerState]:
	var out: Array[TowerState] = []
	for t: TowerState in sim.towers:
		if t.special_id == special:
			out.append(t)
	return out


## Замены для отслеживаемых рецептов, чьих камней нет на поле (ни башен, ни кандидатов раунда):
## {отслеживаемый id: другой id}. Предлагается неотслеживаемый рецепт, компонентов которого на поле
## больше всего (при равенстве — больше уже оставленных, затем порядок Кодекса). Собранный рецепт
## не заменяется, одна замена не предлагается дважды; пока подходящих камней нет — пусто.
static func replacements(sim: GameSim, pinned: Array[String]) -> Dictionary:
	var out: Dictionary = {}
	var missing: Array[String] = []
	for id: String in pinned:
		if int(progress(sim, id, true)["have"]) == 0 and built(sim, id).is_empty():
			missing.append(id)
	if missing.is_empty():
		return out
	var ranked: Array[Dictionary] = []
	for sp: Dictionary in sim.data.specials:
		var other: String = String(sp["id"])
		if pinned.has(other):
			continue
		var prog: Dictionary = progress(sim, other, true)
		if int(prog["have"]) > 0:
			ranked.append({"id": other, "have": int(prog["have"]), "kept": int(prog["kept"]), "order": ranked.size()})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["have"]) != int(b["have"]):
			return int(a["have"]) > int(b["have"])
		if int(a["kept"]) != int(b["kept"]):
			return int(a["kept"]) > int(b["kept"])
		return int(a["order"]) < int(b["order"]))
	for i: int in mini(missing.size(), ranked.size()):
		out[missing[i]] = String(ranked[i]["id"])
	return out


## Рецепты, в которые входит гем данного типа и качества.
static func recipes_with(data: GameData, gem: String, quality: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for sp: Dictionary in data.specials:
		for comp: Dictionary in sp["recipe"]:
			if String(comp["gem"]) == gem and int(comp["quality"]) == quality:
				out.append(String(sp["id"]))
				break
	return out
