extends RefCounted
## One player observation: current cells, explored ground and frozen static views.
## Shared unit sight queries live in sight.gd; NPCs do not own these bitmaps.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const STATE_FIELDS: Array = ["memories", "explored", "ground", "next_ms", "previous"]
var memories: Dictionary = {}
var explored := PackedByteArray()
var ground := PackedByteArray() # Last observed terrain appearance, not live terrain.
var tiles := PackedByteArray() # Current player visibility; derived, not saved.
var seen_tiles := PackedInt32Array()
var visible := PackedByteArray()
var revision: int = 0
var previous := Vector2(-1, -1)
var next_ms: int = 0
var work_usec: int = 0
var _view_origin: int = -1
var _view_range: float = -1.0
var _sight_revision: int = -1
var _layout_seen: int = -1
var _ground_revision: int = -1
var _ground_flags: Dictionary = {}


func _init() -> void:
	explored.resize(Terrain.SIZE * Terrain.SIZE)
	ground.resize(explored.size())
	tiles.resize(explored.size())


func rebuild(world: RefCounted) -> bool:
	if explored.size() != Terrain.SIZE * Terrain.SIZE or ground.size() != explored.size():
		return false
	for id: Variant in memories:
		if not id is int or not memories[id] is Dictionary or not memories[id].get("tile") is int or not memories[id].get("cells") is PackedInt32Array:
			return false
		if memories[id].tile < 0 or memories[id].tile >= explored.size():
			return false
		for tile: int in memories[id].cells:
			if tile < 0 or tile >= explored.size():
				return false
	world.sight.sync(world)
	update_tiles(world)
	update_visible(world)
	revision += 1
	return true


func update(world: RefCounted, now: int, force: bool = false) -> void:
	var started: int = Time.get_ticks_usec()
	world.sight.sync(world)
	var changed: bool = _layout_seen != world.objects.layout_revision or _ground_revision != world.terrain.revision or not is_equal_approx(_view_range, world.sight.range_for(world, 1))
	if not force and not changed and now < next_ms:
		return
	next_ms = now + 200
	var origin: Vector2 = world.combat.position(world, 1)
	var view_changed: bool = update_tiles(world)
	update_visible(world)
	if force or changed or view_changed:
		previous = Terrain.center(Terrain.index(Vector2i(origin.floor())))
		update_ground_flags(world)
		for tile: int in seen_tiles:
			explored[tile] = 255
			ground[tile] = world.terrain.surface_at(tile) | int(_ground_flags.get(tile, 0))
		var nearby: Array[int] = world.objects.nearby(previous, _view_range)
		for id: int in memories.keys():
			var current: Dictionary = world.objects.records.get(id, {})
			if observes(memories[id]) and (current.is_empty() or current.tile != memories[id].tile or current.get("cells", PackedInt32Array([current.tile])) != memories[id].cells):
				memories.erase(id)
		for id: int in nearby:
			var rec: Dictionary = world.objects.records[id]
			if not observes(rec):
				continue
			memories[id] = {"id": id, "kind": rec.kind, "definition": rec.definition, "tile": rec.tile,
				"cells": rec.get("cells", PackedInt32Array([rec.tile])).duplicate(), "layer": rec.get("layer", "ground"),
				"stage": rec.get("stage", -1), "sapient": rec.get("sapient", false)}
		_layout_seen = world.objects.layout_revision
		revision += 1
	work_usec += Time.get_ticks_usec() - started


func update_visible(world: RefCounted) -> void:
	visible.resize(world.attack_due.size())
	visible.fill(0)
	for page: RefCounted in world.pages:
		for row: int in page.ids.size():
			var id: int = page.ids[row]
			if id > 0 and (id == 1 or tiles[Terrain.index(Vector2i(page.positions[row]))] != 0):
				visible[world.actor_slots[id]] = 1


func update_tiles(world: RefCounted) -> bool:
	var cell := Vector2i(world.combat.position(world, 1).floor())
	var sight_range: float = world.sight.range_for(world, 1)
	var index: int = Terrain.index(cell)
	if index == _view_origin and is_equal_approx(sight_range, _view_range) and _sight_revision == world.sight.revision:
		return false
	_view_origin = index
	_view_range = sight_range
	_sight_revision = world.sight.revision
	tiles.fill(0)
	seen_tiles.clear()
	var radius: int = mini(Terrain.SIZE, ceili(sight_range))
	for y: int in range(maxi(0, cell.y - radius), mini(Terrain.SIZE, cell.y + radius + 1)):
		for x: int in range(maxi(0, cell.x - radius), mini(Terrain.SIZE, cell.x + radius + 1)):
			var tile: int = y * Terrain.SIZE + x
			if world.sight.sees_tile(index, tile, sight_range):
				tiles[tile] = 255
				seen_tiles.append(tile)
	return true


func observes(rec: Dictionary) -> bool:
	if rec.tile >= 0 and tiles[rec.tile] != 0:
		return true
	for tile: int in rec.get("cells", PackedInt32Array()):
		if tiles[tile] != 0:
			return true
	return false


func update_ground_flags(world: RefCounted) -> void:
	if _ground_revision == world.terrain.revision:
		return
	_ground_revision = world.terrain.revision
	_ground_flags.clear()
	for tile: int in world.terrain.floors:
		_ground_flags[tile] = 8
	# The development source markers are observed too, not a live overlay on
	# already explored terrain. Bits 4..6 encode seven marker colours.
	for source: int in world.terrain.source_cells.size():
		var tile: int = world.terrain.source_cells[source]
		_ground_flags[tile] = (int(_ground_flags.get(tile, 0)) & 15) | ((world.terrain.source_channels[source] + 1) << 4)
