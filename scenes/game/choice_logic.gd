class_name ChoiceLogic
extends RefCounted
## Что показать игроку в фазе выбора и на поле: кнопки действий, подсказки карточек, доступные сплавы.
## Только чтение состояния симуляции — команды отправляет игровая сцена.


## Кнопки для выбранного кандидата: Keep, Combine ×4/×2, Forge, слейты, усиление до L3, понижение качества.
static func actions_for(sim: GameSim, slot: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sim.phase != GameSim.Phase.CHOOSING or slot < 0 or slot >= sim.candidates.size():
		out.append({"id": "keep", "text": TranslationServer.translate("ACT_KEEP"), "icon": "check", "variation": "PrimaryButton", "disabled": true})
		return out
	var cand: Dictionary = sim.candidates[slot]
	var cell: Vector2i = cand["cell"]
	var data: GameData = sim.data
	var gem_name: String = TranslationServer.translate(String(data.gem(String(cand["gem"]))["name_key"]))
	var forge_opts: Array[Dictionary] = RecipeBook.available_at(sim, cell)
	var first_forge: bool = true
	for o: Dictionary in forge_opts:
		var sp: String = String(o["special"])
		out.append({"id": "forge:" + sp, "text": String(TranslationServer.translate("ACT_FORGE_NAMED")) % TranslationServer.translate(String(data.special(sp)["name_key"])),
			"icon": "sparkle", "variation": "PrimaryButton", "action": "forge" if first_forge else "",
			"tooltip": SpecialText.recipe_text(data, sp)})
		first_forge = false
	for so: Dictionary in SlateBook.available_at(sim, cell):
		var sid: String = String(so["slate"])
		var gems: PackedStringArray = PackedStringArray()
		for pc: Vector2i in so["cells"]:
			var pcand: Dictionary = sim.candidate_at(pc)
			gems.append("%s %s" % [TranslationServer.translate(String(data.gem(String(pcand["gem"]))["name_key"])), String(data.quality(int(pcand["quality"]))["roman"])])
		out.append({"id": "slate:" + sid, "text": String(TranslationServer.translate("ACT_MAKE_SLATE")) % TranslationServer.translate(String(data.slate(sid)["name_key"])),
			"icon": "gem", "variation": "Button",
			"tooltip": String(TranslationServer.translate("ACT_MAKE_SLATE_TIP")) % " + ".join(gems) + "\n" + "\n".join(SlateText.describe(data, sid))})
	var first_combine: bool = true
	for count: int in [4, 2]:
		if BuildCommands.can_combine(sim, cell, count).is_empty():
			var q: int = int(cand["quality"]) + (1 if count == 2 else 2)
			out.append({"id": "combine%d" % count, "text": String(TranslationServer.translate("ACT_COMBINE")) % [count, gem_name, String(data.quality(q)["roman"])],
				"icon": "arrow_up", "variation": "Button", "action": "combine" if first_combine else "",
				"tooltip": TranslationServer.translate("ACT_COMBINE_TIP")})
			first_combine = false
	for t: TowerState in sim.towers:
		var up: Dictionary = BuildCommands.next_upgrade(sim, t)
		if up.is_empty() or String(up["gem"]).is_empty() or not BuildCommands.candidate_fits_upgrade(cand, up):
			continue
		var enough: bool = sim.gold >= int(up["gold"])
		out.append({"id": "upgrade3:%d:%d" % [t.cell.x, t.cell.y],
			"text": String(TranslationServer.translate("ACT_EMPOWER")) % [TranslationServer.translate(String(data.special(t.special_id)["name_key"])), int(up["to_level"]), int(up["gold"])],
			"icon": "sparkle", "variation": "Button", "disabled": not enough,
			"tooltip": TranslationServer.translate("ACT_EMPOWER_TIP") if enough else TranslationServer.translate("ERR_NOT_ENOUGH_GOLD")})
	# Без горячей клавиши: оставить гем можно только нажатием этой кнопки (Space и повторный клик — нет).
	out.append({"id": "keep", "text": TranslationServer.translate("ACT_KEEP"), "icon": "check",
		"variation": "PrimaryButton" if forge_opts.is_empty() else "Button"})
	if sim.can_downgrade(cell).is_empty():
		var lower: Dictionary = data.quality(int(cand["quality"]) - 1)
		out.append({"id": "downgrade", "text": String(TranslationServer.translate("ACT_DOWNGRADE")) % String(lower["roman"]),
			"icon": "arrow_down", "variation": "GhostButton",
			"tooltip": String(TranslationServer.translate("ACT_DOWNGRADE_TIP")) % [gem_name, String(lower["roman"]), TranslationServer.translate(String(lower["key"]))]})
	return out


## Подсказки для карточек кандидатов: [{dupes, recipes:[{special, have, total}], upgrade}].
static func card_hints(sim: GameSim) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cand: Dictionary in sim.candidates:
		var cell: Vector2i = cand["cell"]
		var gem: String = String(cand["gem"])
		var q: int = int(cand["quality"])
		var ready_ids: PackedStringArray = PackedStringArray()
		for o: Dictionary in RecipeBook.available_at(sim, cell):
			ready_ids.append(String(o["special"]))
		var recipes: Array[Dictionary] = []
		for sp: String in RecipeBook.recipes_with(sim.data, gem, q):
			if ready_ids.has(sp):
				recipes.append({"special": sp, "have": 3, "total": 3})
				continue
			var prog: Dictionary = RecipeBook.progress(sim, sp, false)
			var mine_owned: bool = false
			for part: Dictionary in prog["parts"]:
				if String(part["gem"]) == gem and int(part["quality"]) == q and bool(part["owned"]):
					mine_owned = true
			recipes.append({"special": sp, "have": int(prog["have"]) + (0 if mine_owned else 1), "total": int(prog["total"])})
		recipes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["have"]) > int(b["have"]))
		var upgrade: String = ""
		for t: TowerState in sim.towers:
			var up: Dictionary = BuildCommands.next_upgrade(sim, t)
			if not up.is_empty() and not String(up["gem"]).is_empty() and BuildCommands.candidate_fits_upgrade(cand, up):
				upgrade = t.special_id
				break
		out.append({"dupes": BuildCommands.duplicates(sim, cell).size(), "recipes": recipes, "upgrade": upgrade})
	return out


## Сплавы из башен на поле (без кандидатов): [{cell, special}] — по одному на рецепт.
## Спец-башня встаёт на место последнего поставленного компонента (башни перебираются от новых к старым),
## а не первого попавшегося. На другом компоненте её собирают из панели этой башни.
static func board_forges(sim: GameSim) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sim.is_over() or sim.damage_test:
		return out
	var seen: Dictionary = {}
	var newest_first: Array[TowerState] = sim.towers.duplicate()
	newest_first.sort_custom(func(a: TowerState, b: TowerState) -> bool: return a.id > b.id)
	for t: TowerState in newest_first:
		if t.is_special():
			continue
		for o: Dictionary in RecipeBook.available_at(sim, t.cell):
			var sp: String = String(o["special"])
			if seen.has(sp):
				continue
			seen[sp] = true
			out.append({"cell": t.cell, "special": sp})
	return out
