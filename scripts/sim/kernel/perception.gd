extends RefCounted
## One player observation: current cells, explored ground and frozen static views.
## Shared unit sight queries live in sight.gd; NPCs do not own these bitmaps.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const STATE_FIELDS: Array = ["memories", "explored", "ground", "next_ms", "previous"]
const GROUND_PADDING: int = 2 # Extra cached terrain, never logical sight or exploration.
var memories: Dictionary = {}
var fringe: Dictionary = {} # Render-only ground fixtures outside logical sight; not saved knowledge.
var explored := PackedByteArray()
var ground := PackedByteArray() # Last observed appearance plus hidden edge padding.
var tiles := PackedByteArray() # Current logical player visibility; derived, not saved.
var softness := PackedByteArray() # Continuous visual range margin, never authority or a separate sight simulation.
var seen_tiles := PackedInt32Array()
var visible := PackedByteArray()
var visible_actors := PackedInt64Array()
var actor_visibility_revision: int = 0
var revision: int = 0
var previous := Vector2(-1, -1)
var next_ms: int = 0
var work_usec: int = 0
var _view_origin: int = -1
var _view_range: float = -1.0
var _sight_revision: int = -1
var _layout_seen: int = -1
var _ground_revision: int = -1
var _ground_rows := PackedInt32Array() # Derived first/last supported x per row.


func _init() -> void:
	explored.resize(Terrain.SIZE * Terrain.SIZE)
	ground.resize(explored.size())
	tiles.resize(explored.size())
	softness.resize(explored.size())
	_ground_rows.resize(Terrain.SIZE * 2)


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
	_view_origin = -1
	update_tiles(world)
	cache_ground_padding(world)
	cache_static(world, false)
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
		_ground_revision = world.terrain.revision
		for tile: int in seen_tiles:
			explored[tile] = maxi(explored[tile], softness[tile])
			ground[tile] = world.terrain.surface_at(tile)
		if view_changed:
			cache_ground_padding(world)
		cache_static(world, true)
		_layout_seen = world.objects.layout_revision
		revision += 1
	work_usec += Time.get_ticks_usec() - started


func update_visible(world: RefCounted) -> void:
	visible.resize(world.body_count)
	visible.fill(0)
	var actors := PackedInt64Array()
	for page: RefCounted in world.pages:
		for row: int in page.ids.size():
			var id: int = page.ids[row]
			if id > 0 and (id == 1 or tiles[Terrain.index(Vector2i(page.positions[row]))] != 0):
				visible[world.actor_slots[id]] = 1
				if id != 1: actors.append(id)
	if actors != visible_actors:
		visible_actors = actors
		actor_visibility_revision += 1


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
	softness.fill(0)
	seen_tiles.clear()
	_ground_rows.fill(-1)
	var radius: int = mini(Terrain.SIZE, ceili(sight_range + world.sight.FEATHER))
	for y: int in range(maxi(0, cell.y - radius), mini(Terrain.SIZE, cell.y + radius + 1)):
		var first: int = -1
		var last: int = -1
		for x: int in range(maxi(0, cell.x - radius), mini(Terrain.SIZE, cell.x + radius + 1)):
			var tile: int = y * Terrain.SIZE + x
			var weight: float = world.sight.strength(index, tile, sight_range)
			softness[tile] = maxi(1, roundi(weight * 255.0)) if weight > 0.0 else 0
			if weight >= 0.5:
				tiles[tile] = 255
			if weight > 0.0:
				seen_tiles.append(tile)
				if first < 0: first = x
				last = x
		_ground_rows[y * 2] = first
		_ground_rows[y * 2 + 1] = last
	return true


func cache_ground_padding(world: RefCounted) -> void:
	# Expand row spans gathered by the existing sight pass. A conservative
	# envelope also covers gaps between ray samples, without more sight queries.
	var cell: Vector2i = Terrain.cell(_view_origin)
	var radius: int = mini(Terrain.SIZE, ceili(_view_range + world.sight.FEATHER) + GROUND_PADDING)
	var observed_rows := _ground_rows.duplicate()
	for y: int in range(maxi(0, cell.y - radius), mini(Terrain.SIZE, cell.y + radius + 1)):
		var first: int = Terrain.SIZE
		var last: int = -1
		for row: int in range(maxi(0, y - GROUND_PADDING), mini(Terrain.SIZE, y + GROUND_PADDING + 1)):
			if observed_rows[row * 2] >= 0:
				first = mini(first, observed_rows[row * 2])
				last = maxi(last, observed_rows[row * 2 + 1])
		if last < 0: continue
		_ground_rows[y * 2] = maxi(0, first - GROUND_PADDING)
		_ground_rows[y * 2 + 1] = mini(Terrain.SIZE - 1, last + GROUND_PADDING)
		var start: int = y * Terrain.SIZE + _ground_rows[y * 2]
		var end: int = y * Terrain.SIZE + _ground_rows[y * 2 + 1] + 1
		for tile: int in range(start, end):
			# Never refresh an old memory from outside the observed cells.
			if ground[tile] == 0:
				ground[tile] = world.terrain.surface_at(tile)


func cache_static(world: RefCounted, refresh: bool) -> void:
	fringe = {}
	if refresh:
		for id: int in memories.keys():
			var current: Dictionary = world.objects.records.get(id, {})
			if observes(memories[id]) and (current.is_empty() or current.tile != memories[id].tile or current.get("cells", PackedInt32Array([current.tile])) != memories[id].cells):
				memories.erase(id)
	var radius: float = _view_range + world.sight.FEATHER + GROUND_PADDING + 1.0
	for id: int in world.objects.nearby(Terrain.center(_view_origin), radius):
		var rec: Dictionary = world.objects.records[id]
		var current: bool = refresh and observes(rec)
		if not current:
			if memories.has(id) or rec.kind in ["resource", "floor"] or (rec.kind == "plant" and rec.definition == "old_tree"): continue
			var prepared: bool = prepares(rec.tile)
			for tile: int in rec.get("cells", PackedInt32Array()):
				prepared = prepared or prepares(tile)
			if not prepared: continue
		var descriptor: Dictionary = {"id": id, "kind": rec.kind, "definition": rec.definition, "tile": rec.tile,
			"cells": rec.get("cells", PackedInt32Array([rec.tile])).duplicate(), "layer": rec.get("layer", "ground"),
			"stage": rec.get("stage", -1), "vegetation_level": rec.get("vegetation_level", 3), "sapient": rec.get("sapient", false), "facing": rec.get("facing", 0), "construction_started": rec.get("construction_started", false)}
		if rec.get("eaves", false): descriptor["eaves"] = true
		if current: memories[id] = descriptor
		else: fringe[id] = descriptor


func prepares(tile: int) -> bool:
	if tile < 0 or tile >= ground.size(): return false
	var row: int = tile / Terrain.SIZE * 2
	var x: int = tile % Terrain.SIZE
	return _ground_rows[row] >= 0 and x >= _ground_rows[row] and x <= _ground_rows[row + 1]


func observes(rec: Dictionary) -> bool:
	if rec.tile >= 0 and tiles[rec.tile] != 0:
		return true
	for tile: int in rec.get("cells", PackedInt32Array()):
		if tiles[tile] != 0:
			return true
	return false
