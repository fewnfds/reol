class_name SimStructureQuery
extends RefCounted
## Read-only projections of original construction and fixed workplace geometry.
## References are {kind: construction, id} or {kind: workplace, region, part}.
## Workplace parts are walls, door, roof, desk and archive. A walls/roof reference
## names the saved component as a whole; it does not invent one entity per cell.
## No synchronization, ownership, physics coefficients or persistent index lives
## here. Results are detached; player-facing callers must apply actual knowledge.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const NORTH: int = 1
const EAST: int = 2
const SOUTH: int = 4
const WEST: int = 8
const SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const PARTS: Array[String] = ["walls", "door", "desk", "archive", "roof"]
const FACTS: Array[String] = ["movement_blocked", "enclosure_boundary", "roofed", "thermal_barrier", "sight_blocked", "wall_connection"]


static func locate(world: RegionalSimulation, reference: Variant) -> Dictionary:
	if world == null:
		return _failure("world_unavailable")
	if not reference is Dictionary or not reference.get("kind") is String:
		return _failure("invalid_reference")
	match reference.kind:
		"construction":
			if not Shape.keys(reference, ["kind", "id"]) or not reference.id is String or str(reference.id).is_empty():
				return _failure("invalid_reference")
			return _construction(world, reference)
		"workplace":
			if not Shape.keys(reference, ["kind", "region", "part"]) or not reference.region is String or str(reference.region).is_empty() or not reference.part is String:
				return _failure("invalid_reference")
			if not PARTS.has(reference.part):
				return _failure("unsupported_part")
			return _workplace(world, reference)
	return _failure("unsupported_kind")


static func at_cell(world: RegionalSimulation, cell: Vector2i, layer: String = "") -> Dictionary:
	if world == null:
		return _failure("world_unavailable")
	if not layer in ["", "ground", "roof"]:
		return _failure("invalid_layer")
	if not Shape.cell_valid([cell.x, cell.y]):
		return _failure("invalid_cell")
	var structures: Array[Dictionary] = []
	var domain: SimConstruction = world.construction
	if domain != null:
		if domain.world != world:
			return _failure("invalid_world")
		# Existing per-layer indexes exclude cancelled/removed project history.
		for current: String in ["ground", "roof"]:
			if not layer.is_empty() and current != layer:
				continue
			var id: String = domain.project_at(cell, current)
			if id.is_empty():
				continue
			var row: Dictionary = _construction(world, {"kind": "construction", "id": id})
			if not bool(row.ok) or row.layer != current or not row.cells.has(cell):
				return _failure("invalid_source")
			structures.append(row)
	var regions: Array = world.regions.keys()
	for region: Variant in regions:
		if not region is String:
			return _failure("invalid_world")
	regions.sort()
	for region: String in regions:
		for part: String in PARTS:
			if not layer.is_empty() and ("roof" if part == "roof" else "ground") != layer:
				continue
			var row: Dictionary = _workplace(world, {"kind": "workplace", "region": region, "part": part})
			if not bool(row.ok):
				if row.reason == "not_found":
					continue
				return row
			if row.cells.has(cell):
				structures.append(row)
	var result: Dictionary = {"ok": true, "cell": cell, "layer": layer, "structures": structures}
	for fact: String in FACTS:
		result[fact] = false
		for row: Dictionary in structures:
			result[fact] = bool(result[fact]) or bool(row[fact])
	return result


static func wall_mask(world: RegionalSimulation, cell: Vector2i, observed: Callable = Callable()) -> int:
	# Visual connectivity only: an isolated built wall and an absent/invalid
	# source both yield zero. Use at_cell to decide whether a wall is present.
	# Rendering needs a boolean, not five detached full component projections
	# per neighbour. Read the original ground index and fixed wall geometry.
	if not _wall_connection(world, cell):
		return 0
	var mask: int = 0
	for index: int in SIDES.size():
		var neighbor: Vector2i = cell + SIDES[index]
		# Presentation must filter before reading an unseen neighbour's live
		# physical state. Simulation/diagnostics leave this predicate unset.
		if observed.is_valid() and not bool(observed.call(neighbor)):
			continue
		if _wall_connection(world, neighbor):
			mask |= 1 << index
	return mask


static func _wall_connection(world: RegionalSimulation, cell: Vector2i) -> bool:
	if world == null or not Shape.cell_valid([cell.x, cell.y]):
		return false
	var domain: SimConstruction = world.construction
	if domain != null:
		if domain.world != world:
			return false
		var id: String = domain.project_at(cell, "ground")
		if not id.is_empty():
			var project: Dictionary = domain.projects[id]
			if project.state == "built" and domain.definitions.types[project.type].kind in ["wall", "door"]:
				return true
	for sim: VillageSimulation in world.regions.values():
		if SimWorkplaces.wall_at(sim.places, cell):
			return true
		var doorway: Array = sim.places.get("records", {}).get("workspace", {}).get("door", [])
		if doorway.size() == 2 and SimRouteTravel.cell(doorway) == cell:
			return true
	return false


static func _construction(world: RegionalSimulation, reference: Dictionary) -> Dictionary:
	var domain: SimConstruction = world.construction
	if domain == null:
		return _failure("domain_unavailable")
	if domain.world != world:
		return _failure("invalid_world")
	if not domain.projects.has(reference.id):
		return _failure("not_found")
	var project: Variant = domain.projects[reference.id]
	if not project is Dictionary or not project.get("state") is String:
		return _failure("invalid_source")
	if project.state in ["removed", "cancelled"]:
		return _failure("not_found")
	if not project.state in ["blueprint", "built"] or not Shape.cell_valid(project.get("cell")) or not project.get("open") is bool or not project.get("type") is String or not domain.definitions.get("types") is Dictionary:
		return _failure("invalid_source")
	var rule: Variant = domain.definitions.types.get(project.type)
	if not rule is Dictionary or not rule.get("kind") in ["wall", "door", "bed", "roof"]:
		return _failure("invalid_source")
	if not project.get("site") is String or not domain.sites.get(project.site) is Dictionary:
		return _failure("invalid_source")
	var site: Dictionary = domain.sites[project.site]
	if not site.get("region") is String or not world.regions.has(site.region):
		return _failure("invalid_source")
	var cell: Vector2i = SimRouteTravel.cell(project.cell)
	var cells: Array[Vector2i] = [cell]
	var layer: String = "roof" if rule.kind == "roof" else "ground"
	# Support and shelter remain the original owner's rule, not a second solver.
	var covered: bool = project.state == "built" and layer == "roof" and domain.roofed(cell)
	return _projection(reference, str(rule.kind), layer, str(project.state), cells, str(site.region), bool(project.open), covered)


static func _workplace(world: RegionalSimulation, reference: Dictionary) -> Dictionary:
	if not world.regions.has(reference.region):
		return _failure("not_found")
	var sim: Variant = world.regions[reference.region]
	if not sim is VillageSimulation:
		return _failure("invalid_world")
	var records: Variant = sim.places.get("records", {})
	if not records is Dictionary:
		return _failure("invalid_source")
	var layout: Variant = records.get("workspace", {})
	if not layout is Dictionary:
		return _failure("invalid_source")
	if layout.is_empty():
		return _failure("not_found")
	var part: String = reference.part
	var raw: Array = []
	var kind: String
	match part:
		"walls", "roof":
			if not layout.get(part) is Array:
				return _failure("invalid_source")
			raw = layout[part]
			kind = "wall" if part == "walls" else "roof"
		"door":
			# The fixed office stores an opening coordinate, not an operable door.
			raw = [layout.get("door")]
			kind = "doorway"
		"desk", "archive":
			if not layout.get("fixtures") is Dictionary:
				return _failure("invalid_source")
			var fixture: Variant = layout.fixtures.get(part)
			var expected: String = "desk" if part == "desk" else "archive_cabinet"
			if not fixture is Dictionary or fixture.get("kind") != expected:
				return _failure("invalid_source")
			raw = [fixture.get("cell")]
			kind = expected
		_:
			return _failure("unsupported_part")
	var cells: Array[Vector2i] = []
	for value: Variant in raw:
		if not Shape.cell_valid(value):
			return _failure("invalid_source")
		var cell: Vector2i = SimRouteTravel.cell(value)
		if cells.has(cell):
			return _failure("invalid_source")
		cells.append(cell)
	return _projection(reference, kind, "roof" if part == "roof" else "ground", "built", cells, str(reference.region), part == "door", part == "roof")


static func _projection(reference: Dictionary, kind: String, layer: String, state: String, cells: Array[Vector2i], region: String, opened: bool, covered: bool) -> Dictionary:
	var built: bool = state == "built"
	var wall: bool = built and kind in ["wall", "door", "doorway"]
	var barrier: bool = built and kind in ["wall", "door"] and not opened
	return {
		"ok": true, "reference": reference.duplicate(true), "kind": kind,
		"state_owner": "construction" if reference.kind == "construction" else "village_simulation",
		"region": region, "layer": layer, "cells": cells, "state": state, "open": opened,
		"movement_blocked": barrier or built and kind in ["desk", "archive_cabinet"],
		"enclosure_boundary": wall, "roofed": covered,
		# This is the existing binary heat-boundary fact, not a conductivity.
		"thermal_barrier": barrier, "sight_blocked": barrier, "wall_connection": wall,
	}


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
