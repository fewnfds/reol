class_name SimEnvironmentSourceBindings
extends RefCounted
## Developer/authority-only, on-demand projection over original ground objects.
## Owns only immutable definition memoization and precomputed geometry. No source
## positions, item quantities, field response, clock, save state or player facts.

const SCOPE: String = "active_ground_base_targets"
const MAX_WORK: int = 1_000_000
const Rules = preload("res://scripts/sim/environment_field_rules.gd")

var _owner: WeakRef
var _definitions: EnvironmentSourceDefinitions
var _profiles: Dictionary = {}
var _kernels: Dictionary = {}


func configure(world: RegionalSimulation, definitions: EnvironmentSourceDefinitions) -> bool:
	if _owner != null or world == null or definitions == null or not definitions.is_configured():
		return false
	if world.artifacts == null or world.artifacts.world != world or world.object_lifecycle == null:
		return false
	if world.object_lifecycle.world != world or not world.object_lifecycle.ground.bound_to(world):
		return false
	if not definitions.validate_artifacts(world.artifacts.definitions.types):
		return false
	# These small tables are independent of source count and built once. Queries
	# do no square roots, integration, whole-world rebuilds or per-frame updates.
	for radius: int in EnvironmentSourceDefinitions.RADII:
		var width: int = radius * 2 + 1
		var weights := PackedInt64Array()
		weights.resize(width * width)
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				weights[(y + radius) * width + x + radius] = int(Rules.kernel(Vector2i(x, y), radius).weight)
		_kernels[radius] = weights
	_definitions = definitions
	_owner = weakref(world)
	return true


func project(reference: Variant) -> Dictionary:
	var context: Dictionary = _context()
	if not bool(context.ok):
		return context
	if not reference is Dictionary or not reference.get("kind") is String:
		return _failure("invalid_reference")
	var world: RegionalSimulation = context.world
	var region: String
	var container: String
	match reference.kind:
		"artifact":
			if not _keys(reference, ["kind", "id"]) or not _text(reference.id):
				return _failure("invalid_reference")
			var item: Variant = world.artifacts.objects.get(reference.id)
			if not item is Dictionary:
				return _failure("not_found")
			region = str(item.get("region", ""))
			container = str(item.get("container", ""))
		"stock":
			if not _keys(reference, ["kind", "domain", "region", "container", "item"]):
				return _failure("invalid_reference")
			for key: String in ["domain", "region", "container", "item"]:
				if not _text(reference[key]):
					return _failure("invalid_reference")
			if reference.domain != "village":
				return _failure("unsupported_domain")
			region = reference.region
			container = reference.container
			if not world.regions.get(region) is VillageSimulation or not world.regions[region].inventory.containers.has(container):
				return _failure("not_found")
		_:
			return _failure("unsupported_kind")
	if not container.begins_with("ground:"):
		return _failure("unsupported_location")
	var slot: Variant = world.object_lifecycle.ground.slots.get(container)
	if not slot is Dictionary or slot.region != region or slot.reference != reference:
		return _failure("invalid_location")
	if not bool(slot.active):
		return _failure("not_found")
	var result: Dictionary = _project_slot(world, slot, container)
	if not bool(result.ok):
		return result.duplicate(true)
	result["reference"] = reference.duplicate(true)
	result["source_id"] = JSON.stringify(reference, "", true)
	result["elements"] = result.elements.duplicate()
	result.merge(_metadata(world))
	return result


func project_move(plan: Variant, event_context: Variant = null) -> Dictionary:
	# This is a forecast over a lifecycle preflight, not an item mutation or
	# permission check. Final publication must revalidate the plan and its owner
	# epochs. A plain caller cannot opt out of the backlog/time contract.
	var context: Dictionary = _context(event_context)
	if not bool(context.ok):
		return context
	var world: RegionalSimulation = context.world
	if not plan is Dictionary or not _keys(plan, ["request", "reference", "from", "target", "size", "definition", "at_ms", "ground_revision", "artifact_generation"]):
		return _failure("invalid_plan")
	var request: Variant = plan.request
	var target: Variant = plan.target
	if not request is Dictionary or not SimObjectLifecycle._request_valid(request) or request.op != "move" or not target is Dictionary:
		return _failure("invalid_plan")
	if not plan.reference is Dictionary or not _keys(plan.reference, ["kind", "id"]) or plan.reference.kind != "artifact" or plan.reference.id != request.id:
		return _failure("invalid_plan")
	if not plan.from is Dictionary or plan.from != request.from or not plan.size is Vector2i:
		return _failure("invalid_plan")
	if not plan.at_ms is int or int(plan.at_ms) != world.elapsed_ms or not plan.ground_revision is int or not plan.artifact_generation is int:
		return _failure("stale_plan")
	if int(plan.ground_revision) != world.object_lifecycle.ground.revision or int(plan.artifact_generation) != world.artifacts.state_generation:
		return _failure("stale_plan")
	var item: Variant = world.artifacts.objects.get(request.id)
	if not item is Dictionary or not world.object_lifecycle.manages(request.id):
		return _failure("stale_plan")
	if not plan.definition is String or item.get("definition") != plan.definition or item.get("region") != plan.from.get("region") or item.get("container") != plan.from.get("container"):
		return _failure("stale_plan")
	var definition: Variant = world.artifacts.definitions.types.get(item.get("definition", ""))
	if not definition is Dictionary or not definition.get("placement") is Dictionary or not definition.placement.get("footprint") is Array or definition.placement.footprint.size() != 2:
		return _failure("invalid_source")
	var size := Vector2i(int(definition.placement.footprint[0]), int(definition.placement.footprint[1]))
	if size != plan.size or not target.get("ok") is bool or not target.ok or not target.get("ground") is bool or target.get("region") != plan.from.region:
		return _failure("invalid_plan")
	var requested_destination: Dictionary = request.to
	if target.ground:
		if not _keys(target, ["ok", "ground", "region", "container", "cell"]) or not target.cell is Vector2i or not requested_destination.has("cell"):
			return _failure("invalid_plan")
		if target.region != requested_destination.region or target.container != "ground:" + request.command or target.cell != Vector2i(int(requested_destination.cell[0]), int(requested_destination.cell[1])):
			return _failure("invalid_plan")
		if not SimGroundPlacements._geometry_valid(target.cell, size):
			return _failure("invalid_plan")
	else:
		if not _keys(target, ["ok", "ground", "region", "container"]) or not requested_destination.has("container") or target.region != requested_destination.region or target.container != requested_destination.container or str(target.container).begins_with("ground:"):
			return _failure("invalid_plan")
	var region: Variant = world.regions.get(plan.from.region)
	if not region is VillageSimulation or region.elapsed_ms != world.elapsed_ms:
		return _failure("stale_source")
	var before: Dictionary = {"ok": true, "status": "no_source"}
	if str(plan.from.container).begins_with("ground:"):
		var slot: Variant = world.object_lifecycle.ground.slots.get(plan.from.container)
		if not slot is Dictionary or slot.region != plan.from.region or slot.reference != plan.reference or not bool(slot.active):
			return _failure("invalid_location")
		before = _project_slot(world, slot, plan.from.container)
		if not bool(before.get("ok", false)):
			return before.duplicate(true)
		if before.size != size:
			return _failure("invalid_location")
	var after: Dictionary = {"ok": true, "status": "no_source"}
	if bool(target.ground):
		var profile: Dictionary = _profile("artifact", str(item.definition))
		if not bool(profile.ok):
			return profile.duplicate(true)
		var origin := Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
		var emitting: bool = int(profile.thermal_grade) != 0 or profile.elements != [0, 0, 0, 0, 0]
		after = {"ok": true, "status": "source" if emitting else "no_source", "cell": target.cell + origin,
			"size": size, "quantity": 1, "profile_id": profile.profile_id, "elements": profile.elements.duplicate(),
			"thermal_grade": int(profile.thermal_grade), "radius_cells": int(profile.radius_cells)}
	var was_source: bool = before.status == "source"
	var will_be_source: bool = after.status == "source"
	var operation: String = "none"
	var field_change: Dictionary = {}
	if was_source and not will_be_source:
		operation = "remove"
	elif will_be_source:
		var same: bool = was_source and before.cell == after.cell and before.radius_cells == after.radius_cells and before.thermal_grade == after.thermal_grade and before.elements == after.elements
		if not same:
			operation = "set"
			field_change = {"cell": after.cell, "radius": int(after.radius_cells),
				"channels": Rules.source_to_packed_channels(after.elements, int(after.thermal_grade))}
	var result: Dictionary = _metadata(world)
	result.merge({"ok": true, "reference": plan.reference.duplicate(true), "operation": operation,
		"source": after.duplicate(true), "before": before.duplicate(true), "after": after.duplicate(true),
		"field_change": field_change})
	return result


func sample_base(cell: Vector2i, budget: int = 16384) -> Dictionary:
	var context: Dictionary = _context()
	if not bool(context.ok):
		return context
	if cell.x < 0 or cell.y < 0 or cell.x >= SimGroundPlacements.MAP_SIZE or cell.y >= SimGroundPlacements.MAP_SIZE:
		return _failure("invalid_cell")
	if budget < 1 or budget > MAX_WORK:
		return _failure("invalid_budget")
	var world: RegionalSimulation = context.world
	var radius: int = _definitions.max_radius()
	var minimum := Vector2i(maxi(0, cell.x - radius), maxi(0, cell.y - radius))
	var maximum := Vector2i(mini(SimGroundPlacements.MAP_SIZE - 1, cell.x + radius), mini(SimGroundPlacements.MAP_SIZE - 1, cell.y + radius))
	# Full footprints intersect the search even if their top-left anchor lies
	# outside it. Accounting regions are not separate spatial maps.
	var found: Dictionary = world.object_lifecycle.ground.query(Rect2i(minimum, maximum - minimum + Vector2i.ONE), budget)
	var used: int = int(found.work_used)
	if not bool(found.ok):
		return _failure(str(found.reason), used)
	var elements: Array[int] = [0, 0, 0, 0, 0]
	var hot: int = 0
	var cold: int = 0
	var source_count: int = 0
	for id: String in found.ids:
		if used >= budget:
			return _failure("budget_exhausted", used)
		used += 1
		var source: Dictionary = _project_slot(world, world.object_lifecycle.ground.slots[id], id)
		if not bool(source.ok):
			# Unknown or stale candidates cannot silently become known zero.
			return _failure(str(source.reason), used)
		if source.status == "no_source":
			continue
		var offset: Vector2i = cell - source.cell
		var extent: int = int(source.radius_cells)
		if absi(offset.x) >= extent or absi(offset.y) >= extent:
			continue
		var weights: PackedInt64Array = _kernels[extent]
		var weight: int = weights[(offset.y + extent) * (extent * 2 + 1) + offset.x + extent]
		if weight == 0:
			continue
		source_count += 1
		for channel: int in 5:
			elements[channel] = maxi(elements[channel], Rules.effective_grade(int(source.elements[channel]), weight))
		var thermal: int = Rules.effective_grade(int(source.thermal_grade), weight)
		hot = maxi(hot, thermal)
		cold = maxi(cold, -thermal)
	var result: Dictionary = _metadata(world)
	result.merge({"ok": true, "complete": true, "elements": elements,
		"thermal_grade": hot - cold, "hot_grade": hot, "cold_grade": cold,
		"source_count": source_count, "candidate_count": found.ids.size(), "work_used": used})
	return result


func _project_slot(world: RegionalSimulation, slot: Dictionary, container: String) -> Dictionary:
	var region: Variant = world.regions.get(slot.region)
	if not region is VillageSimulation:
		return _failure("invalid_source")
	if region.elapsed_ms != world.elapsed_ms:
		return _failure("stale_source")
	var reference: Dictionary = slot.reference
	var definition: String
	var kind: String
	var quantity: int = 1
	if reference.kind == "artifact":
		var item: Variant = world.artifacts.objects.get(reference.id)
		if not item is Dictionary or item.get("region") != slot.region or item.get("container") != container:
			return _failure("invalid_source")
		definition = str(item.get("definition", ""))
		if not world.artifacts.definitions.types.has(definition):
			return _failure("invalid_source")
		kind = "artifact"
		if not bool(slot.active):
			return _failure("invalid_location")
	else:
		if reference.kind != "stock" or reference.domain != "village":
			return _failure("unsupported_domain")
		if reference.region != slot.region or reference.container != container or not region.inventory.containers.has(reference.container):
			return _failure("invalid_source")
		definition = reference.item
		kind = "material"
		# Deliberately avoid available()/entrusted(): radiation is a property of
		# the real quantity, independent of reservations and custody bookkeeping.
		quantity = region.inventory.quantity(reference.container, definition)
		if bool(slot.active) != (quantity > 0):
			return _failure("invalid_source")
	var profile: Dictionary = _profile(kind, definition)
	if not bool(profile.ok):
		return profile
	var size := Vector2i(int(slot.size[0]), int(slot.size[1]))
	var cell := Vector2i(int(slot.cell[0]), int(slot.cell[1]))
	var origin := Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
	var emitting: bool = quantity > 0 and (int(profile.thermal_grade) != 0 or profile.elements != [0, 0, 0, 0, 0])
	return {"ok": true, "status": "source" if emitting else "no_source",
		"cell": cell + origin, "size": size, "quantity": quantity,
		"profile_id": profile.profile_id, "elements": profile.elements,
		"thermal_grade": profile.thermal_grade, "radius_cells": profile.radius_cells}


func _profile(kind: String, definition: String) -> Dictionary:
	var key: String = kind + ":" + definition
	if _profiles.has(key):
		return _profiles[key]
	var profile: Dictionary = _definitions.profile(kind, definition)
	# Arbitrary inventory item IDs must not grow an unbounded negative cache.
	if bool(profile.ok):
		_profiles[key] = profile
	return profile


func _context(event_context: Variant = null) -> Dictionary:
	if _owner == null or _definitions == null:
		return _failure("definitions_unavailable")
	var world: Variant = _owner.get_ref()
	if not world is RegionalSimulation:
		return _failure("world_unavailable")
	if world.elapsed_ms < 0 or world.target_ms < world.elapsed_ms:
		return _failure("invalid_time")
	if world.artifacts == null or world.artifacts.world != world or world.object_lifecycle == null or world.object_lifecycle.world != world or not world.object_lifecycle.ground.bound_to(world):
		return _failure("invalid_world")
	if event_context != null:
		# The world issues this identity only while a supported, guarded event
		# boundary is being settled; stale and foreign tokens are never accepted.
		if not world.environment_event_valid(event_context):
			return _failure("invalid_event_context")
	elif world.elapsed_ms != world.target_ms:
		return _failure("world_has_backlog")
	return {"ok": true, "world": world}


func _metadata(world: RegionalSimulation) -> Dictionary:
	return {"visibility": "authority_only", "scope": SCOPE, "world_time_ms": world.elapsed_ms,
		"config_digest": _definitions.digest(), "rule_version": Rules.BASE_TARGET_RULE_VERSION, "live": false}


func _failure(reason: String, work_used: int = 0) -> Dictionary:
	return {"ok": false, "complete": false, "reason": reason, "work_used": work_used,
		"visibility": "authority_only", "scope": SCOPE}


static func _keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: String in expected:
		if not value.has(key):
			return false
	return true


static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= SimGroundPlacements.MAX_TEXT
