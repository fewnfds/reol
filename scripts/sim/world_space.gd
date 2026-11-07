class_name SimWorldSpace
extends RefCounted
## Live, authority-only cell projections over original owners. Ground and
## construction retain their own indexes; only bodies/fixed components need
## additional rebuildable links here. No physical state or saved event history.

signal changed(change: Dictionary)

const KINDS: Array[String] = ["actor", "avian", "large_body", "artifact", "stock", "construction", "workplace"]
const LAYERS: Array[String] = ["ground", "air", "roof", "planned"]
const MAX_WORK: int = 65536
const MAX_AREA: int = 4096

var revision: int = 0
var _owner: WeakRef
var _ready: bool = false
var _entries: Dictionary = {}
var _cells: Dictionary[Vector2i, Dictionary] = {}
var _connections: Array = []
var _building: bool = false
var _build_work: int = 0

var world: RegionalSimulation:
	get: return _owner.get_ref() if _owner != null else null


func _init(authority: RegionalSimulation) -> void:
	_owner = weakref(authority)
	_bind_sources()


func _bind_sources() -> void:
	for sim: VillageSimulation in world.regions.values():
		_connect(sim.body_space_changed, _body_changed.bind("actor"))
		_connect(sim.space_reset, reset)
	_connect(world.avian_life.body_space_changed, _body_changed.bind("avian"))
	_connect(world.large_bodies.body_space_changed, _body_changed.bind("large_body"))
	_connect(world.artifacts.space_reset, reset)
	_connect(world.avian_life.space_reset, reset)
	_connect(world.large_bodies.space_reset, reset)
	_connect(world.object_lifecycle.committed, _objects_changed)
	_connect(world.artifact_transfers.committed, _artifact_changed)
	_connect(world.construction.space_changed, _structures_changed)


func detach() -> void:
	for connection: Array in _connections:
		var event: Signal = connection[0]
		var callback: Callable = connection[1]
		if is_instance_valid(event.get_object()) and event.is_connected(callback):
			event.disconnect(callback)
	_connections.clear()
	_ready = false


func reset(reason: String = "restored") -> void:
	_ready = false
	_entries.clear()
	_cells.clear()
	_announce([], [], [], reason)


func prepare(budget: int = MAX_WORK) -> Dictionary:
	if world == null or world.space != self:
		return _failure("world_replaced", 0)
	if _ready:
		return {"ok": true, "work_used": 0}
	if budget < 1 or budget > MAX_WORK:
		return _failure("invalid_budget", 0)
	_entries.clear()
	_cells.clear()
	_building = true
	_build_work = 0
	for region: String in world.regions:
		var sim: VillageSimulation = world.regions[region]
		for id: String in sim.actors:
			if not _prepare_reference({"kind": "actor", "id": id}, budget):
				return _build_failed(budget)
		for part: String in SimStructureQuery.PARTS:
			var reference: Dictionary = {"kind": "workplace", "region": region, "part": part}
			if not _prepare_reference(reference, budget):
				return _build_failed(budget)
	for id: String in world.avian_life.birds:
		if not _prepare_reference({"kind": "avian", "id": id}, budget):
			return _build_failed(budget)
	for id: String in world.large_bodies.bodies:
		if not _prepare_reference({"kind": "large_body", "id": id}, budget):
			return _build_failed(budget)
	# Only original site placements are indexed here. Registered ground objects
	# are queried through ground's own cell index; contained objects stay out.
	for id: String in world.artifacts.legacy_object_ids():
		_build_work += 1 # Classification also counts for non-site objects.
		if _build_work > budget or str(world.artifacts.objects[id].container).begins_with("site:") and not _prepare_reference({"kind": "artifact", "id": id}, budget):
			return _build_failed(budget)
	_building = false
	_ready = true
	return {"ok": true, "work_used": _build_work}


func _prepare_reference(reference: Dictionary, budget: int) -> bool:
	if not _refresh(reference):
		return false
	_build_work += 1 + _entries.get(JSON.stringify(reference, "", true), {}).get("cells", []).size()
	return _build_work <= budget


func _build_failed(budget: int) -> Dictionary:
	_building = false
	_entries.clear()
	_cells.clear()
	return _failure("budget_exhausted" if _build_work > budget else "unsupported_source", mini(_build_work, budget))


func _connect(event: Signal, callback: Callable) -> void:
	if not event.is_connected(callback):
		event.connect(callback)
	_connections.append([event, callback])


func query(area: Rect2i, kinds: Array = [], layer: String = "", budget: int = 4096) -> Dictionary:
	if world == null or world.space != self:
		return _failure("world_replaced", 0)
	if budget < 1 or budget > MAX_WORK:
		return _failure("invalid_budget", 0)
	if area.size.x < 1 or area.size.y < 1 or area.size.x > MAX_AREA or area.size.y > MAX_AREA or area.size.x * area.size.y > MAX_AREA:
		return _failure("invalid_area", 0)
	if world == null or world.map_data == null or not world.map_data.in_bounds(area.position) or not world.map_data.in_bounds(area.end - Vector2i.ONE):
		return _failure("invalid_area", 0)
	if not layer.is_empty() and not LAYERS.has(layer):
		return _failure("invalid_layer", 0)
	for kind: Variant in kinds:
		if not kind is String or not KINDS.has(kind):
			return _failure("unsupported_kind", 0)
	if world.elapsed_ms != world.target_ms or world.environment_boundary_active() or world.object_lifecycle.environment_change_pending() or world.object_lifecycle._committing:
		return _failure("pending_time", 0)
	var prepared: Dictionary = prepare(budget)
	if not bool(prepared.ok):
		return prepared
	# An out-of-date body could have moved into the requested area. Refuse the
	# whole body query instead of claiming a locally empty, complete answer.
	if kinds.is_empty() or "actor" in kinds:
		for sim: VillageSimulation in world.regions.values():
			if sim.elapsed_ms != world.elapsed_ms:
				return _failure("stale_source", 0)
	if (kinds.is_empty() or "avian" in kinds) and world.avian_life.elapsed_ms != world.elapsed_ms:
		return _failure("stale_source", 0)
	if (kinds.is_empty() or "large_body" in kinds) and world.large_bodies.elapsed_ms != world.elapsed_ms:
		return _failure("stale_source", 0)
	var found: Dictionary = {}
	var work: int = int(prepared.work_used)
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			work += 1
			if work > budget:
				return _failure("budget_exhausted", budget)
			var cell := Vector2i(x, y)
			var candidates: Array = []
			for key: String in _cells.get(cell, {}):
				candidates.append(_entries[key].reference)
			var ground: Dictionary = world.object_lifecycle.ground.query_cell(cell)
			for id: String in ground.get("ids", []):
				candidates.append(world.object_lifecycle.ground.slots[id].reference)
			for current: String in ["ground", "roof"]:
				var id: String = world.construction.project_at(cell, current)
				if not id.is_empty():
					candidates.append({"kind": "construction", "id": id})
			for reference: Dictionary in candidates:
				work += 1
				if work > budget:
					return _failure("budget_exhausted", budget)
				if not kinds.is_empty() and reference.kind not in kinds:
					continue
				var key: String = JSON.stringify(reference, "", true)
				if found.has(key):
					continue
				var row: Dictionary = world.describe_object(reference)
				if not bool(row.get("ok", false)) or bool(row.get("stale", true)):
					return _failure("stale_source", work)
				work += row.spatial.cells.size()
				if work > budget:
					return _failure("budget_exhausted", budget)
				if row.spatial.layer not in LAYERS or not layer.is_empty() and row.spatial.layer != layer:
					continue
				if row.spatial.cells.has(cell):
					found[key] = reference.duplicate(true)
	var references: Array = []
	var keys: Array = found.keys()
	keys.sort()
	for key: String in keys:
		references.append(found[key])
	return {"ok": true, "complete": true, "scope": "world_space", "live": true,
		"visibility": "authority_only", "geometry": "cell_projection", "references": references,
		"world_time_ms": world.elapsed_ms, "world_id": world.get_instance_id(),
		"space_id": get_instance_id(), "revision": revision, "work_used": work,
		"supported_kinds": KINDS.duplicate()}


func _refresh(reference: Dictionary) -> bool:
	var key: String = JSON.stringify(reference, "", true)
	var previous: Dictionary = _entries.get(key, {})
	var before: Array = previous.get("cells", []).duplicate()
	if not previous.is_empty():
		for cell: Vector2i in before:
			_cells[cell].erase(key)
			if _cells[cell].is_empty():
				_cells.erase(cell)
		_entries.erase(key)
	var row: Dictionary = world.describe_object(reference)
	var after: Array = []
	if not bool(row.get("ok", false)):
		if row.get("reason") != "not_found":
			return false
	elif row.spatial.layer in LAYERS:
		# Ground placements use the original slot index, never a second index.
		var ground_artifact: bool = reference.kind == "artifact" and str(world.artifacts.objects[reference.id].container).begins_with("ground:")
		if not ground_artifact:
			after = row.spatial.cells.duplicate()
			_entries[key] = {"reference": reference.duplicate(true), "cells": after}
			for cell: Vector2i in after:
				if not _cells.has(cell):
					_cells[cell] = {}
				_cells[cell][key] = true
	if not _building:
		_announce([reference], before, after, "projection_changed")
	return true


func _body_changed(id: String, kind: String) -> void:
	if not _ready:
		_announce([{"kind": kind, "id": id}], [], [], "projection_invalidated")
		return
	if not _refresh({"kind": kind, "id": id}):
		reset()


func _objects_changed(change: Dictionary) -> void:
	var references: Array = []
	if change.result.get("reference") is Dictionary:
		references.append(change.result.reference)
	_announce(references, change.get("old_ground_cells", []), change.get("new_ground_cells", []), "object_committed")


func _artifact_changed(change: Dictionary) -> void:
	if not _ready:
		_announce([change.entity], [], [], "projection_invalidated")
	elif not _refresh(change.entity):
		reset()


func _structures_changed(cells: Array) -> void:
	_announce([], cells, cells, "structure_committed")


func _announce(references: Array, before: Array, after: Array, reason: String) -> void:
	revision += 1
	if changed.get_connections().is_empty():
		return
	var notice: Dictionary = {"references": references.duplicate(true), "old_cells": before.duplicate(), "new_cells": after.duplicate(),
		"reason": reason, "world_time_ms": world.elapsed_ms, "world_id": world.get_instance_id(),
		"space_id": get_instance_id(), "revision": revision, "scope": "world_space", "visibility": "authority_only"}
	_freeze(notice)
	changed.emit(notice)


static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for item: Variant in value.values():
			_freeze(item)
		value.make_read_only()
	elif value is Array:
		for item: Variant in value:
			_freeze(item)
		value.make_read_only()


func _failure(reason: String, work: int) -> Dictionary:
	return {"ok": false, "complete": false, "reason": reason, "references": [],
		"scope": "world_space", "live": true, "work_used": work}
