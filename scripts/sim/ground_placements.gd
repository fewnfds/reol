class_name SimGroundPlacements
extends RefCounted
## Original ground-location metadata for explicitly registered stock entries
## or unique artifacts. Quantity, identity and use remain with their owners.
## `slots` must only be changed through this object; `_cells` and `_buckets`
## are rebuildable indexes, not additional item or position authorities.

const VERSION: int = 1
const MAP_SIZE: int = WorldMapData.WORLD_SIZE
const BUCKET_SHIFT: int = 4
const MAX_SIZE: int = 64
const MAX_SLOTS: int = 524288
const MAX_TEXT: int = 512
const MAX_REFERENCE_CHARACTERS: int = 67108864
const MAX_METADATA_CHARACTERS: int = 67108864
const MAX_REVISION: int = SimInventory.MAX_COUNT

var slots: Dictionary = {}
var revision: int = 0
var _owner: WeakRef
var _cells: Dictionary[Vector2i, String] = {}
var _buckets: Dictionary[Vector2i, Dictionary] = {}
var _reference_slots: Dictionary[String, String] = {}
var _active_count: int = 0
var _reference_characters: int = 0
var _metadata_characters: int = 0


func configure(world: RegionalSimulation) -> bool:
	if world == null:
		return false
	if _owner != null:
		return _owner.get_ref() == world
	_owner = weakref(world)
	return true


func rebind(world: RegionalSimulation) -> void:
	# The complete detached candidate is already validated by the caller. Its
	# source-owner callbacks must now point to the published world instance.
	_owner = weakref(world) if world != null else null


func bound_to(world: RegionalSimulation) -> bool:
	return world != null and _owner != null and _owner.get_ref() == world


func register_slot(id: String, region: String, reference: Dictionary, cell: Vector2i, size: Vector2i = Vector2i.ONE, replace_id: String = "") -> Dictionary:
	if not _text(id) or not _text(region) or not _valid_reference(reference, region):
		return _failure("invalid_reference")
	if slots.has(id):
		return _failure("duplicate_slot")
	if slots.size() >= MAX_SLOTS:
		return _failure("slot_capacity")
	if revision >= MAX_REVISION:
		return _failure("revision_capacity")
	var key: String = JSON.stringify(reference, "", true)
	var replacing: bool = false
	if not replace_id.is_empty() and slots.has(replace_id) and bool(slots[replace_id].active):
		var old: Dictionary = slots[replace_id]
		if reference.kind != "artifact" or old.region != region or JSON.stringify(old.reference, "", true) != key:
			return _failure("invalid_replacement")
		replacing = true
	elif not replace_id.is_empty() and (slots.has(replace_id) or replace_id.begins_with("ground:")):
		# A stale or missing ground source must not silently become an unrelated
		# placement. Non-ground container IDs may identify a held source.
		return _failure("invalid_replacement")
	if _reference_slots.has(key) and (not replacing or _reference_slots[key] != replace_id):
		return _failure("reference_already_placed")
	if key.length() > MAX_REFERENCE_CHARACTERS - _reference_characters:
		return _failure("reference_capacity")
	var metadata_size: int = key.length() + id.length() + region.length()
	if metadata_size > MAX_METADATA_CHARACTERS - _metadata_characters:
		return _failure("metadata_capacity")
	var checked: Dictionary = can_place(region, cell, size, replace_id if replacing else "")
	if not bool(checked.ok):
		return checked
	# All checks precede the short synchronous mutation. No callbacks run while
	# the location and indexes are published. No source-owner fact is modified.
	if replacing:
		var old: Dictionary = slots[replace_id]
		var old_cell := Vector2i(int(old.cell[0]), int(old.cell[1]))
		var old_size := Vector2i(int(old.size[0]), int(old.size[1]))
		_unindex(replace_id, old_cell, old_size)
		old.active = false
		_active_count -= 1
	var value: Dictionary = {"region": region, "reference": reference.duplicate(true),
		"cell": [cell.x, cell.y], "size": [size.x, size.y], "active": true}
	slots[id] = value
	_reference_slots[key] = id
	_reference_characters += key.length()
	_metadata_characters += metadata_size
	_index(id, cell, size, _cells, _buckets)
	_active_count += 1
	revision += 1
	return {"ok": true, "changed": true, "id": id, "revision": revision}


func discard_uncommitted(id: String) -> void:
	# Only the synchronous lifecycle transaction that just registered this ID
	# may roll back its unpublished slot here. This is not a gameplay removal.
	if not slots.has(id):
		return
	var value: Dictionary = slots[id]
	var key: String = JSON.stringify(value.reference, "", true)
	if bool(value.active):
		var cell := Vector2i(int(value.cell[0]), int(value.cell[1]))
		var size := Vector2i(int(value.size[0]), int(value.size[1]))
		_unindex(id, cell, size)
		if _reference_slots.get(key) == id:
			_reference_slots.erase(key)
		_active_count -= 1
	_reference_characters -= key.length()
	_metadata_characters -= key.length() + id.length() + str(value.region).length()
	slots.erase(id)
	# Advance monotonically to invalidate any speculative consumers; rollback
	# never rewinds an epoch or publishes another source-owner state.
	if revision < MAX_REVISION:
		revision += 1


func deactivate(id: String) -> Dictionary:
	if not _text(id) or not slots.has(id):
		return _failure("not_found")
	var value: Dictionary = slots[id]
	var context: Dictionary = _context(str(value.region), false)
	if not bool(context.ok):
		return context
	if not bool(value.active):
		return {"ok": true, "changed": false, "id": id, "revision": revision}
	if revision >= MAX_REVISION:
		return _failure("revision_capacity")
	var cell := Vector2i(int(value.cell[0]), int(value.cell[1]))
	var size := Vector2i(int(value.size[0]), int(value.size[1]))
	_unindex(id, cell, size)
	_reference_slots.erase(JSON.stringify(value.reference, "", true))
	value.active = false
	_active_count -= 1
	revision += 1
	return {"ok": true, "changed": true, "id": id, "revision": revision}


func can_place(region: String, cell: Vector2i, size: Vector2i = Vector2i.ONE, except_id: String = "") -> Dictionary:
	var context: Dictionary = _context(region, true)
	if not bool(context.ok):
		return context
	if not _geometry_valid(cell, size):
		return _failure("invalid_geometry")
	if not except_id.is_empty():
		if not slots.has(except_id) or not bool(slots[except_id].active) or slots[except_id].region != region:
			return _failure("invalid_exception")
	var world: RegionalSimulation = context.world
	if world.construction != null and world.construction.world != world:
		return _failure("invalid_world")
	for y: int in range(cell.y, cell.y + size.y):
		for x: int in range(cell.x, cell.x + size.x):
			var at := Vector2i(x, y)
			var occupied: String = _cells.get(at, "")
			if not occupied.is_empty() and occupied != except_id:
				return _failure_at("ground_occupied", at)
			if not world.map_data.terrain_is_walkable(at):
				return _failure_at("terrain_blocked", at)
			if world.construction != null and world.construction.blocked(at):
				return _failure_at("structure_blocked", at)
	return {"ok": true, "revision": revision, "checked_cells": size.x * size.y}


func locate(region: String, id: String) -> Dictionary:
	if not _text(region) or not _text(id):
		return _failure("invalid_reference")
	if not slots.has(id) or slots[id].region != region:
		return _failure("not_found")
	var value: Dictionary = slots[id]
	return {"ok": true, "id": id, "region": value.region, "reference": value.reference.duplicate(true),
		"cell": Vector2i(int(value.cell[0]), int(value.cell[1])), "size": Vector2i(int(value.size[0]), int(value.size[1])),
		"active": bool(value.active), "revision": revision}


func query(area: Rect2i, budget: int = 4096) -> Dictionary:
	if not _geometry_valid(area.position, area.size, false):
		return _query_failure("invalid_area", 0)
	if budget <= 0:
		return _query_failure("invalid_budget", 0)
	var first: Vector2i = _bucket(area.position)
	var last: Vector2i = _bucket(Vector2i(area.position.x + area.size.x - 1, area.position.y + area.size.y - 1))
	var seen: Dictionary[String, bool] = {}
	var ids: Array[String] = []
	var used: int = 0
	for by: int in range(first.y, last.y + 1):
		for bx: int in range(first.x, last.x + 1):
			if used >= budget:
				return _query_failure("budget_exhausted", used)
			used += 1
			var bucket: Dictionary = _buckets.get(Vector2i(bx, by), {})
			for id: String in bucket:
				if used >= budget:
					return _query_failure("budget_exhausted", used)
				used += 1
				if seen.has(id):
					continue
				seen[id] = true
				var value: Dictionary = slots[id]
				var cell := Vector2i(int(value.cell[0]), int(value.cell[1]))
				var size := Vector2i(int(value.size[0]), int(value.size[1]))
				if area.intersects(Rect2i(cell, size)):
					if used >= budget:
						return _query_failure("budget_exhausted", used)
					used += 1
					ids.append(id)
	# Ordering is unspecified; these are location IDs only, never object data.
	return {"ok": true, "complete": true, "ids": ids, "work_used": used,
		"scope": "active_ground_placements", "revision": revision}


func stats() -> Dictionary:
	return {"slots": slots.size(), "active": _active_count, "inactive": slots.size() - _active_count,
		"cells": _cells.size(), "buckets": _buckets.size(), "revision": revision,
		"reference_characters": _reference_characters, "metadata_characters": _metadata_characters}


func to_dict() -> Dictionary:
	return {"version": VERSION, "slots": slots.duplicate(true)}


func restore(data: Dictionary) -> bool:
	# Restore is independent of any live world, terrain, artifact or inventory.
	# Cross-owner and terrain validity must be checked on the full candidate.
	if revision >= MAX_REVISION or not _keys(data, ["version", "slots"]) or not _whole(data.version, VERSION, VERSION) or not data.slots is Dictionary or data.slots.size() > MAX_SLOTS:
		return false
	var next_slots: Dictionary = {}
	var next_cells: Dictionary[Vector2i, String] = {}
	var next_buckets: Dictionary[Vector2i, Dictionary] = {}
	var next_references: Dictionary[String, String] = {}
	var next_active: int = 0
	var next_characters: int = 0
	var next_metadata_characters: int = 0
	for id: Variant in data.slots:
		if not _text(id):
			return false
		var raw: Variant = data.slots[id]
		if not _keys(raw, ["region", "reference", "cell", "size", "active"]) or not _text(raw.region) or not raw.reference is Dictionary or not _valid_reference(raw.reference, raw.region) or not raw.active is bool:
			return false
		if not _pair(raw.cell, 0, MAP_SIZE - 1) or not _pair(raw.size, 1, MAX_SIZE):
			return false
		# Validate original JSON numbers before Vector2i conversion can narrow.
		var cell := Vector2i(int(raw.cell[0]), int(raw.cell[1]))
		var size := Vector2i(int(raw.size[0]), int(raw.size[1]))
		if not _geometry_valid(cell, size):
			return false
		var key: String = JSON.stringify(raw.reference, "", true)
		if key.length() > MAX_REFERENCE_CHARACTERS - next_characters:
			return false
		var metadata_size: int = key.length() + str(id).length() + str(raw.region).length()
		if metadata_size > MAX_METADATA_CHARACTERS - next_metadata_characters:
			return false
		next_characters += key.length()
		next_metadata_characters += metadata_size
		if raw.active:
			if next_references.has(key):
				return false
			for y: int in range(cell.y, cell.y + size.y):
				for x: int in range(cell.x, cell.x + size.x):
					if next_cells.has(Vector2i(x, y)):
						return false
			next_references[key] = id
			_index(id, cell, size, next_cells, next_buckets)
			next_active += 1
		next_slots[id] = {"region": str(raw.region), "reference": raw.reference.duplicate(true),
			"cell": [cell.x, cell.y], "size": [size.x, size.y], "active": bool(raw.active)}
	# Failed candidates leave the existing authoritative metadata untouched.
	slots = next_slots
	_cells = next_cells
	_buckets = next_buckets
	_reference_slots = next_references
	_active_count = next_active
	_reference_characters = next_characters
	_metadata_characters = next_metadata_characters
	revision += 1
	return true


func _context(region: String, needs_terrain: bool) -> Dictionary:
	if not _text(region):
		return _failure("invalid_region")
	var world: Variant = _owner.get_ref() if _owner != null else null
	if not world is RegionalSimulation:
		return _failure("world_unavailable")
	if world.elapsed_ms < 0 or world.target_ms < world.elapsed_ms:
		return _failure("invalid_time")
	if world.target_ms != world.elapsed_ms and (world.object_lifecycle == null or not world.object_lifecycle._settling):
		return _failure("pending_time")
	var simulation: Variant = world.regions.get(region)
	if not simulation is VillageSimulation:
		return _failure("invalid_region")
	if simulation.elapsed_ms != world.elapsed_ms:
		return _failure("unsynchronized_region")
	if needs_terrain and world.map_data == null:
		return _failure("terrain_unavailable")
	return {"ok": true, "world": world}


static func _index(id: String, cell: Vector2i, size: Vector2i, cells: Dictionary[Vector2i, String], buckets: Dictionary[Vector2i, Dictionary]) -> void:
	for y: int in range(cell.y, cell.y + size.y):
		for x: int in range(cell.x, cell.x + size.x):
			cells[Vector2i(x, y)] = id
	var first: Vector2i = _bucket(cell)
	var last: Vector2i = _bucket(Vector2i(cell.x + size.x - 1, cell.y + size.y - 1))
	for by: int in range(first.y, last.y + 1):
		for bx: int in range(first.x, last.x + 1):
			var point := Vector2i(bx, by)
			var bucket: Dictionary = buckets.get(point, {})
			bucket[id] = true
			buckets[point] = bucket


func _unindex(id: String, cell: Vector2i, size: Vector2i) -> void:
	for y: int in range(cell.y, cell.y + size.y):
		for x: int in range(cell.x, cell.x + size.x):
			_cells.erase(Vector2i(x, y))
	var first: Vector2i = _bucket(cell)
	var last: Vector2i = _bucket(Vector2i(cell.x + size.x - 1, cell.y + size.y - 1))
	for by: int in range(first.y, last.y + 1):
		for bx: int in range(first.x, last.x + 1):
			var point := Vector2i(bx, by)
			var bucket: Dictionary = _buckets[point]
			bucket.erase(id)
			if bucket.is_empty():
				_buckets.erase(point)


static func _bucket(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x >> BUCKET_SHIFT, cell.y >> BUCKET_SHIFT)


static func _geometry_valid(cell: Vector2i, size: Vector2i, limit_size: bool = true) -> bool:
	var maximum: int = MAX_SIZE if limit_size else MAP_SIZE
	return cell.x >= 0 and cell.y >= 0 and size.x > 0 and size.y > 0 and size.x <= maximum and size.y <= maximum and int(cell.x) + int(size.x) <= MAP_SIZE and int(cell.y) + int(size.y) <= MAP_SIZE


static func _valid_reference(reference: Dictionary, region: String) -> bool:
	if reference.get("kind") == "artifact":
		return _keys(reference, ["kind", "id"]) and _text(reference.id)
	if reference.get("kind") == "stock":
		return _keys(reference, ["kind", "domain", "region", "container", "item"]) and reference.domain in ["village", "avian"] and reference.region == region and _text(reference.container) and _text(reference.item)
	return false


static func _pair(value: Variant, minimum: int, maximum: int) -> bool:
	return value is Array and value.size() == 2 and _whole(value[0], minimum, maximum) and _whole(value[1], minimum, maximum)


static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum and float(value) == floorf(float(value))


static func _keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size():
		return false
	for key: Variant in expected:
		if not value.has(key):
			return false
	return true


static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= MAX_TEXT


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _failure_at(reason: String, cell: Vector2i) -> Dictionary:
	return {"ok": false, "reason": reason, "cell": cell}


func _query_failure(reason: String, work_used: int) -> Dictionary:
	return {"ok": false, "reason": reason, "complete": false, "work_used": work_used,
		"scope": "active_ground_placements", "revision": revision}
