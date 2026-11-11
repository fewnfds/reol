class_name SimWorldGeometry
extends RefCounted
## Rebuildable geometry owned by the simulation, independent of SceneTree.
## The owner updates pages; workers only receive sealed, retained page views.

signal changed(cells: Array[Vector2i], previous_revision: int)

const PAGE_SHIFT: int = 4
const PAGE_SIZE: int = 1 << PAGE_SHIFT
const HEIGHT_MASK: int = 3
const TERRAIN_SHIFT: int = 2
const TERRAIN_MASK: int = 3
const WALKABLE: int = 16
const COVER: int = 32
const PATH_CACHE_LIMIT: int = 1024

class ReadView extends RefCounted:
	var source_id: int
	var revision: int
	var bounds: Rect2i
	var pages: Dictionary[Vector2i, PackedByteArray] = {}

	func value(cell: Vector2i) -> int:
		if not bounds.has_point(cell):
			return -1
		var coord := Vector2i(cell.x >> SimWorldGeometry.PAGE_SHIFT, cell.y >> SimWorldGeometry.PAGE_SHIFT)
		var page: PackedByteArray = pages[coord]
		return page[(cell.y & (SimWorldGeometry.PAGE_SIZE - 1)) * SimWorldGeometry.PAGE_SIZE + (cell.x & (SimWorldGeometry.PAGE_SIZE - 1))]

	func is_walkable(cell: Vector2i) -> bool:
		var raw: int = value(cell)
		return raw >= 0 and (raw & SimWorldGeometry.WALKABLE) != 0

	func can_move(from: Vector2i, to: Vector2i) -> bool:
		var source: int = value(from)
		var target: int = value(to)
		return target >= 0 and (target & SimWorldGeometry.WALKABLE) != 0 and absi((source & SimWorldGeometry.HEIGHT_MASK if source >= 0 else -1) - (target & SimWorldGeometry.HEIGHT_MASK)) <= 1

	func can_step(from: Vector2i, direction: Vector2i) -> bool:
		if direction == Vector2i.ZERO:
			return true
		return can_move(from, from + direction) and (direction.x == 0 or direction.y == 0 or can_move(from, from + Vector2i(direction.x, 0)) or can_move(from, from + Vector2i(0, direction.y)))

var revision: int = 0
var work: Dictionary = {"built_pages": 0, "updated_cells": 0, "captures": 0, "captured_pages": 0}
var _owner: WeakRef
var _active: bool = true
var _pages: Dictionary[Vector2i, PackedByteArray] = {}
var _paths: Dictionary[String, Array] = {}
var _connections: Array[Array] = []
var _plant_cells: Dictionary[String, Vector2i] = {}
var _large_bounds: Dictionary[String, Rect2i] = {}
var _layout_version: int

var world: RegionalSimulation:
	get: return _owner.get_ref() if _owner != null else null


func _init(authority: RegionalSimulation) -> void:
	_owner = weakref(authority)
	_layout_version = _workplace_version()
	_connect(world.map_data.terrain_changed, invalidate)
	if world.construction != null:
		_connect(world.construction.space_changed, invalidate)
	if world.plants != null:
		for id: String in world.plants.bodies:
			var cell: Variant = _blocking_plant_cell(id)
			if cell is Vector2i:
				_plant_cells[id] = cell
		_connect(world.plants.plant_changed, _plant_changed)
	if world.large_bodies != null:
		for id: String in world.large_bodies.bodies:
			_large_bounds[id] = world.large_bodies.swept_bounds(id)
		_connect(world.large_bodies.body_space_changed, _large_changed)
		_connect(world.large_bodies.bodies_space_changed, _large_batch_changed)
		_connect(world.large_bodies.space_reset, _large_reset)


func _connect(event: Signal, callback: Callable) -> void:
	event.connect(callback)
	_connections.append([event, callback])


func detach() -> void:
	_active = false
	for link: Array in _connections:
		var event: Signal = link[0]
		if is_instance_valid(event.get_object()) and event.is_connected(link[1]):
			event.disconnect(link[1])
	_connections.clear()
	_pages.clear()
	_paths.clear()


func current_revision() -> int:
	# Opening layouts can be activated in-place. Their existing explicit version
	# is checked at owner entry points, never from a worker's read view.
	var current: int = _workplace_version()
	if current != _layout_version:
		_layout_version = current
		invalidate()
	return revision


func _workplace_version() -> int:
	var result: int = 0
	for sim: VillageSimulation in world.regions.values():
		result += int(sim.config.get("workplaces_version", 0))
	return result


func invalidate(cells: Array[Vector2i] = []) -> void:
	var previous: int = revision
	revision += 1
	_paths.clear()
	if cells.is_empty():
		_pages.clear()
	else:
		var updates: Dictionary[Vector2i, PackedByteArray] = {}
		for cell: Vector2i in cells:
			var coord := Vector2i(cell.x >> PAGE_SHIFT, cell.y >> PAGE_SHIFT)
			if not _pages.has(coord) or not world.map_data.in_bounds(cell):
				continue
			if not updates.has(coord):
				updates[coord] = _pages[coord].duplicate()
			updates[coord][(cell.y & (PAGE_SIZE - 1)) * PAGE_SIZE + (cell.x & (PAGE_SIZE - 1))] = _read_cell(cell)
			work.updated_cells += 1
		for coord: Vector2i in updates:
			_pages[coord] = updates[coord] # Previously captured pages stay immutable.
	changed.emit(cells, previous)


func _read_cell(cell: Vector2i) -> int:
	var terrain: int = world.map_data.get_terrain(cell)
	var result: int = world.map_data.get_elevation(cell) | (terrain << TERRAIN_SHIFT)
	var cover: bool = world.construction.blocked(cell) if world.construction != null else false
	if world.construction == null:
		for sim: VillageSimulation in world.regions.values():
			cover = cover or sim.workplace_blocked(cell)
	if world.plants != null:
		cover = cover or world.plants.blocked(cell)
	if cover:
		result |= COVER
	if terrain == WorldMapData.TERRAIN_GRASS and not cover and (world.large_bodies == null or not world.large_bodies.blocked(cell)):
		result |= WALKABLE
	return result


func _page(coord: Vector2i) -> PackedByteArray:
	if not _pages.has(coord):
		var page := PackedByteArray()
		page.resize(PAGE_SIZE * PAGE_SIZE)
		var base: Vector2i = coord * PAGE_SIZE
		for y: int in PAGE_SIZE:
			for x: int in PAGE_SIZE:
				page[y * PAGE_SIZE + x] = _read_cell(base + Vector2i(x, y))
		_pages[coord] = page
		work.built_pages += 1
	return _pages[coord]


func value(cell: Vector2i) -> int:
	if not _active or not world.map_data.in_bounds(cell):
		return -1
	var coord := Vector2i(cell.x >> PAGE_SHIFT, cell.y >> PAGE_SHIFT)
	return _page(coord)[(cell.y & (PAGE_SIZE - 1)) * PAGE_SIZE + (cell.x & (PAGE_SIZE - 1))]


func is_walkable(cell: Vector2i) -> bool:
	var raw: int = value(cell)
	return raw >= 0 and (raw & WALKABLE) != 0


func can_move(from: Vector2i, to: Vector2i) -> bool:
	var source: int = value(from)
	var target: int = value(to)
	return target >= 0 and (target & WALKABLE) != 0 and WorldMapData.elevation_step_allowed(source & HEIGHT_MASK if source >= 0 else -1, target & HEIGHT_MASK)


func can_step(from: Vector2i, direction: Vector2i) -> bool:
	if direction == Vector2i.ZERO:
		return true
	return can_move(from, from + direction) and (direction.x == 0 or direction.y == 0 or can_move(from, from + Vector2i(direction.x, 0)) or can_move(from, from + Vector2i(0, direction.y)))


func is_solid(cell: Vector2i, at_level: int) -> bool:
	var raw: int = value(cell)
	return raw < 0 or (raw & HEIGHT_MASK) > at_level or ((raw >> TERRAIN_SHIFT) & TERRAIN_MASK) == WorldMapData.TERRAIN_ROCK or (raw & COVER) != 0


func find_path(from: Vector2i, to: Vector2i, radius: int, budget: int) -> Array[Vector2i]:
	if not _active:
		return []
	current_revision()
	var key: String = "%s:%s:%d:%d" % [from, to, radius, budget]
	if _paths.has(key):
		return _paths[key].duplicate()
	var path: Array[Vector2i] = SimGridNavigation.find_path(from, to, is_walkable, can_step, radius, budget)
	if _paths.size() >= PATH_CACHE_LIMIT:
		_paths.clear()
	_paths[key] = path.duplicate()
	return path


func capture(area: Rect2i) -> ReadView:
	if not _active:
		return null
	current_revision()
	var result := ReadView.new()
	result.source_id = get_instance_id()
	result.revision = revision
	result.bounds = area.intersection(Rect2i(Vector2i.ZERO, Vector2i.ONE * WorldMapData.WORLD_SIZE))
	if result.bounds.has_area():
		var first := Vector2i(result.bounds.position.x >> PAGE_SHIFT, result.bounds.position.y >> PAGE_SHIFT)
		var last := Vector2i((result.bounds.end.x - 1) >> PAGE_SHIFT, (result.bounds.end.y - 1) >> PAGE_SHIFT)
		for y: int in range(first.y, last.y + 1):
			for x: int in range(first.x, last.x + 1):
				var coord := Vector2i(x, y)
				result.pages[coord] = _page(coord)
	result.pages.make_read_only()
	work.captures += 1
	work.captured_pages += result.pages.size()
	return result


func is_current(view: ReadView) -> bool:
	return _active and view != null and view.source_id == get_instance_id() and view.revision == current_revision()


func _blocking_plant_cell(id: String) -> Variant:
	var row: Dictionary = world.plants.bodies.get(id, {})
	if row.is_empty() or row.stage in ["root", "removed", "dead"] or not str(row.location.support).is_empty() or not bool(world.plants.definitions.types[row.definition].blocks):
		return null
	return world.plants.cell_of(id)


func _plant_changed(id: String) -> void:
	var previous: Variant = _plant_cells.get(id)
	var current: Variant = _blocking_plant_cell(id)
	if previous == current:
		return
	var cells: Array[Vector2i] = []
	if previous is Vector2i:
		cells.append(previous)
		_plant_cells.erase(id)
	if current is Vector2i:
		cells.append(current)
		_plant_cells[id] = current
	invalidate(cells)


func _large_changed(id: String) -> void:
	_large_batch_changed([id])


func _large_reset() -> void:
	_large_bounds.clear()
	for id: String in world.large_bodies.bodies:
		_large_bounds[id] = world.large_bodies.swept_bounds(id)
	invalidate()


func _large_batch_changed(ids: Array[String]) -> void:
	var touched: Dictionary[Vector2i, bool] = {}
	for id: String in ids:
		var previous: Rect2i = _large_bounds.get(id, Rect2i())
		var current: Rect2i = world.large_bodies.swept_bounds(id) if world.large_bodies.bodies.has(id) else Rect2i()
		if previous == current:
			continue
		for area: Rect2i in [previous, current]:
			for y: int in range(area.position.y, area.end.y):
				for x: int in range(area.position.x, area.end.x):
					touched[Vector2i(x, y)] = true
		if current.has_area():
			_large_bounds[id] = current
		else:
			_large_bounds.erase(id)
	if not touched.is_empty():
		var cells: Array[Vector2i] = []
		cells.assign(touched.keys())
		invalidate(cells)
