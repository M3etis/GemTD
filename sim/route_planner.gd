class_name RoutePlanner
extends RefCounted
## Маршрут Вход → C1..C5 → Выход. Наземный путь — A* по сегментам, воздушный — прямые.

var grid: BoardGrid
var ground_cells: Array[Vector2i] = []
var ground_points: PackedVector2Array = PackedVector2Array()
var ground_cum: PackedFloat64Array = PackedFloat64Array()
var ground_length: float = 0.0
var air_points: PackedVector2Array = PackedVector2Array()
var air_cum: PackedFloat64Array = PackedFloat64Array()
var air_length: float = 0.0
var version: int = 0


func _init(g: BoardGrid) -> void:
	grid = g
	air_points = PackedVector2Array()
	for p: Vector2i in grid.route_points:
		air_points.append(BoardGrid.center(p))
	air_cum = cumulative(air_points)
	air_length = air_cum[air_cum.size() - 1]


## Полный наземный путь с учётом временно занятых клеток.
## Возвращает {ok, cells, segment (индекс перекрытого сегмента или -1)}.
func compute(extra_solid: Array[Vector2i] = []) -> Dictionary:
	for c: Vector2i in extra_solid:
		grid.astar.set_point_solid(c, true)
	var out: Array[Vector2i] = []
	var blocked_segment: int = -1
	for i: int in grid.route_points.size() - 1:
		var seg: Array[Vector2i] = grid.astar.get_id_path(grid.route_points[i], grid.route_points[i + 1])
		if seg.is_empty():
			blocked_segment = i
			break
		if i > 0:
			seg.remove_at(0)
		out.append_array(seg)
	for c: Vector2i in extra_solid:
		grid.astar.set_point_solid(c, grid.get_cell(c) != BoardGrid.Cell.EMPTY)
	return {"ok": blocked_segment < 0, "cells": out, "segment": blocked_segment}


func recompute() -> bool:
	var res: Dictionary = compute()
	if not res["ok"]:
		return false
	ground_cells = res["cells"]
	ground_points = cells_to_points(ground_cells)
	ground_cum = cumulative(ground_points)
	ground_length = ground_cum[ground_cum.size() - 1] if ground_cum.size() > 0 else 0.0
	version += 1
	return true


static func cells_to_points(path_cells: Array[Vector2i]) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for c: Vector2i in path_cells:
		pts.append(BoardGrid.center(c))
	return pts


static func cumulative(points: PackedVector2Array) -> PackedFloat64Array:
	var cum: PackedFloat64Array = PackedFloat64Array()
	var total: float = 0.0
	for i: int in points.size():
		if i > 0:
			total += points[i].distance_to(points[i - 1])
		cum.append(total)
	return cum


static func path_length(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	return total


func is_on_ground_path(c: Vector2i) -> bool:
	return ground_cells.has(c)
