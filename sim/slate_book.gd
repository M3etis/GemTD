class_name SlateBook
extends RefCounted
## Рецепты слейтов (Gem TD 3.2). Базовый — из двух гемов текущего раунда: основной (качество III)
## и один из partners (качество II). Составной — из двух готовых базовых слейтов или прямо из четырёх
## гемов раунда, закрывающих оба базовых рецепта. Гемы прошлых раундов (башни) не участвуют.


static func _fits(comp: Dictionary, cand: Dictionary) -> bool:
	return String(comp["gem"]) == String(cand["gem"]) and int(comp["quality"]) == int(cand["quality"])


## Все пары кандидатов под базовый слейт: [[клетка основного, клетка пары], ...]. used — занятые клетки.
static func base_pairs(sl: Dictionary, cands: Array, used: Array = []) -> Array:
	var out: Array = []
	for a: Dictionary in cands:
		if used.has(a["cell"]) or not _fits(sl["recipe"], a):
			continue
		for b: Dictionary in cands:
			if b["cell"] == a["cell"] or used.has(b["cell"]):
				continue
			for p: Dictionary in sl["partners"]:
				if _fits(p, b):
					out.append([a["cell"], b["cell"]])
					break
	return out


## Клетки кандидатов для слейта, среди которых есть must; [] — не собрать.
static func cells_for(data: GameData, sl: Dictionary, cands: Array, must: Vector2i) -> Array:
	if String(sl["kind"]) == "base":
		for pair: Array in base_pairs(sl, cands):
			if pair.has(must):
				return pair
		return []
	var a: Dictionary = data.slate(String(sl["from"][0]))
	var b: Dictionary = data.slate(String(sl["from"][1]))
	for p1: Array in base_pairs(a, cands):
		for p2: Array in base_pairs(b, cands, p1):
			if p1.has(must) or p2.has(must):
				return p1 + p2
	return []


## Слейты, которые можно сделать из кандидата в клетке c (фаза выбора): [{slate, cells}].
## Составные — первыми: они собирают больше. Слейт ложится в клетку c, поэтому, если там уже лежит
## другой слейт (камень поставили поверх него), отсюда не предлагается — только из другого камня рецепта.
static func available_at(sim: GameSim, c: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sim.phase != GameSim.Phase.CHOOSING or sim.candidate_at(c).is_empty() or sim.slate_by_cell.has(c):
		return out
	for kind: String in ["combo", "base"]:
		for sl: Dictionary in sim.data.slates:
			if String(sl["kind"]) != kind:
				continue
			var cells: Array = cells_for(sim.data, sl, sim.candidates, c)
			if not cells.is_empty():
				out.append({"slate": String(sl["id"]), "cells": cells})
	return out


## Составной слейт из двух базовых (в любом порядке); пусто — таких нет.
static func combo_of(data: GameData, a: String, b: String) -> String:
	for sl: Dictionary in data.slates:
		var from: Array = sl["from"]
		if from.size() == 2 and ((from[0] == a and from[1] == b) or (from[0] == b and from[1] == a)):
			return String(sl["id"])
	return ""


## Слейт на поле, с которым s объединяется в составной (первый подходящий), или null.
static func combine_partner(sim: GameSim, s: TowerState) -> TowerState:
	if s == null or not s.is_slate():
		return null
	for o: TowerState in sim.slates:
		if o != s and not combo_of(sim.data, s.slate_id, o.slate_id).is_empty():
			return o
	return null
