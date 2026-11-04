class_name SimEntityQuery
extends RefCounted
## Read-only engine/editor lookup. Player-facing knowledge must be filtered by
## the observer's actual perception and memory before exposing this result.
##
## References are domain-qualified. Nothing here creates an entity, owns a
## position, synchronizes a region, or predicts an uncommitted future.
## Supported kinds are actor, avian, artifact and large_body. An unsupported kind does
## not imply an entity is absent from another domain. `stale` compares the
## source clocks with the committed world time; `world_has_backlog` separately
## indicates that the requested target time has not yet been committed.


static func locate(world: RegionalSimulation, reference: Variant) -> Dictionary:
	if world == null:
		return _failure("world_unavailable")
	if not reference is Dictionary or reference.size() != 2 or not reference.has("kind") or not reference.has("id"):
		return _failure("invalid_reference")
	if not reference.kind is String or not reference.id is String or not SimInventory._nonempty(reference.id):
		return _failure("invalid_reference")
	var kind: String = reference.kind
	var id: String = reference.id
	match kind:
		"actor":
			return _actor(world, id)
		"avian":
			return _avian(world, id)
		"artifact":
			return _artifact(world, id)
		"large_body":
			return _large_body(world, id)
	return _failure("unsupported_kind")


static func _actor(world: RegionalSimulation, id: String) -> Dictionary:
	# Actor IDs are already unique across regions in a valid regional world. No
	# extra registry is kept; this scans region owners, not their full populations.
	var region: String = ""
	for candidate: Variant in world.regions:
		var sim: Variant = world.regions[candidate]
		if not candidate is String or not sim is VillageSimulation:
			return _failure("invalid_world")
		if sim.actors.has(id):
			if not region.is_empty():
				return _failure("ambiguous_reference")
			region = candidate
	if region.is_empty():
		return _failure("not_found")
	var simulation: VillageSimulation = world.regions[region]
	var point: Variant = _actor_position(simulation.actors.get(id))
	if point == null:
		return _failure("invalid_location")
	return _position_result(world, "actor", id, point, "village_simulation", region, simulation.elapsed_ms, "village_simulation", simulation.elapsed_ms)


static func _avian(world: RegionalSimulation, id: String) -> Dictionary:
	var domain: SimAvianLife = world.avian_life
	if domain == null:
		return _failure("domain_unavailable")
	if domain.world != world:
		return _failure("invalid_world")
	if not domain.birds.has(id):
		return _failure("not_found")
	var bird: Variant = domain.birds[id]
	if not bird is Dictionary or not bird.get("region") is String or not world.regions.has(bird.region) or not SimAvianLife.Schema.position_valid(bird.get("position")) or not SimAvianLife.Schema.count(bird.get("altitude"), 0, 1):
		return _failure("invalid_location")
	var raw: Array = bird.position
	var result: Dictionary = _position_result(world, "avian", id, Vector2(float(raw[0]), float(raw[1])), "avian_life", str(bird.region), domain.elapsed_ms, "avian_life", domain.elapsed_ms)
	if bool(result.ok):
		result["altitude"] = int(bird.altitude)
	return result


static func _large_body(world: RegionalSimulation, id: String) -> Dictionary:
	var domain: SimLargeBodies = world.large_bodies
	if domain == null:
		return _failure("domain_unavailable")
	if domain.world != world:
		return _failure("invalid_world")
	if not domain.bodies.has(id):
		return _failure("not_found")
	var body: Variant = domain.bodies[id]
	if not body is Dictionary or not body.get("region") is String or not world.regions.has(body.region) or not SimAvianLife.Schema.position_valid(body.get("position")) or not body.get("step") is Dictionary:
		return _failure("invalid_location")
	var raw: Array = body.position
	var point := Vector2(float(raw[0]), float(raw[1]))
	var result: Dictionary = _position_result(world, "large_body", id, point, "large_bodies", str(body.region), domain.elapsed_ms, "large_bodies", domain.elapsed_ms)
	if not bool(result.ok):
		return result
	var footprint: Vector2i = _large_body_footprint(world, domain)
	if not SimBodyGeometry.valid_size(footprint):
		return _failure("invalid_location")
	var step: Dictionary = body.step
	if step.is_empty():
		if not point.is_equal_approx(TileGrid.cell_to_world(TileGrid.world_to_cell(point))):
			return _failure("invalid_location")
	else:
		# Only the current committed leg is needed for its original reservation.
		# Do not inspect or expose the remaining route, waypoints or intentions.
		if not SimAvianLife.Schema.keys(step, ["from", "to", "started_ms", "due_ms"]) or not SimAvianLife.Schema.cell_valid(step.get("from")) or not SimAvianLife.Schema.cell_valid(step.get("to")):
			return _failure("invalid_location")
		if not SimAvianLife.Schema.count(step.get("started_ms"), 0, domain.elapsed_ms) or not SimAvianLife.Schema.count(step.get("due_ms"), domain.elapsed_ms + 1) or not SimAvianLife.Schema.count(domain.definitions.get("step_ms"), 1) or int(step.due_ms) - int(step.started_ms) != int(domain.definitions.step_ms):
			return _failure("invalid_time")
		var from: Vector2i = SimRouteTravel.cell(step.from)
		var to: Vector2i = SimRouteTravel.cell(step.to)
		if not SimBodyGeometry.DIRECTIONS.has(to - from):
			return _failure("invalid_location")
		var ratio: float = float(domain.elapsed_ms - int(step.started_ms)) / float(domain.definitions.step_ms)
		if not point.is_equal_approx(TileGrid.cell_to_world(from).lerp(TileGrid.cell_to_world(to), ratio)):
			return _failure("invalid_location")
	# record_region is a saved association, never inferred spatial containment.
	# Footprint and swept bounds use cells. The continuous pixel rectangle is
	# presentation/contact geometry only; it is not a new navigation occupancy.
	var extent_px: Vector2 = Vector2(footprint * TileGrid.TILE_SIZE)
	result["footprint"] = footprint
	result["physical_bounds_px"] = Rect2(point - extent_px * 0.5, extent_px)
	result["swept_bounds_cells"] = domain.swept_bounds(id)
	return result


static func _large_body_footprint(world: RegionalSimulation, domain: SimLargeBodies) -> Vector2i:
	# Read the same original form used by domain.size(), guarding incomplete
	# sources before that direct accessor can dereference them. No registry copy.
	if world._content == null or not domain.definitions.get("form") is String:
		return Vector2i.ZERO
	var forms: Variant = world._content.body_forms.get("forms")
	if not forms is Dictionary:
		return Vector2i.ZERO
	var form: Variant = forms.get(domain.definitions.form)
	if not form is Dictionary or not form.get("footprint") is Array:
		return Vector2i.ZERO
	var raw: Array = form.footprint
	if raw.size() != 2 or not SimAvianLife.Schema.count(raw[0], 1, 9) or not SimAvianLife.Schema.count(raw[1], 1, 9):
		return Vector2i.ZERO
	return Vector2i(int(raw[0]), int(raw[1]))


static func _artifact(world: RegionalSimulation, id: String) -> Dictionary:
	var domain: SimArtifacts = world.artifacts
	if domain == null:
		return _failure("domain_unavailable")
	if domain.world != world:
		return _failure("invalid_world")
	if not domain.objects.has(id):
		return _failure("not_found")
	var item: Variant = domain.objects[id]
	if not item is Dictionary or not domain.valid_location(item.get("region"), item.get("container")):
		return _failure("invalid_location")
	var region: String = item.region
	var container: String = item.container
	var point: Variant
	var location_owner: String
	var location_time: int
	if container.begins_with("site:"):
		# A field slot owns this location, not a duplicate inventory container.
		if world.field_opportunities == null:
			return _failure("invalid_location")
		var grid: Vector2i = world.field_opportunities.slot_cell(region, container)
		if not SimAvianLife.Schema.cell_valid([grid.x, grid.y]):
			return _failure("invalid_location")
		point = TileGrid.cell_to_world(grid)
		location_owner = "field_opportunities"
		location_time = world.elapsed_ms
	else:
		var sim: VillageSimulation = world.regions[region]
		if container.begins_with("actor:"):
			point = _actor_position(sim.actors.get(container.trim_prefix("actor:")))
		else:
			var place: Variant = sim.places.get(container)
			if not place is Dictionary or not VillageSimulation._valid_cell(place.get("cell")):
				return _failure("invalid_location")
			point = TileGrid.cell_to_world(SimRouteTravel.cell(place.cell))
		if point == null:
			return _failure("invalid_location")
		location_owner = "village_simulation"
		location_time = sim.elapsed_ms
	# Artifacts have the regional world's committed clock; a held object's
	# position may still depend on an older, independently batched village.
	var result: Dictionary = _position_result(world, "artifact", id, point, "artifacts", region, world.elapsed_ms, location_owner, location_time)
	if bool(result.ok):
		result["container"] = container
	return result


static func _actor_position(body: Variant) -> Variant:
	# Human bodies use the village's own coordinate contract, not the bird
	# domain's current fixed-map bounds. The original cell still has to match
	# the continuous position; this query must never silently repair either.
	if not body is Dictionary or not SimLocalMotion._vector(body.get("position")) or not VillageSimulation._valid_cell(body.get("cell")):
		return null
	var raw: Array = body.position
	var point := Vector2(float(raw[0]), float(raw[1]))
	return point if TileGrid.world_to_cell(point) == SimRouteTravel.cell(body.cell) else null


static func _position_result(world: RegionalSimulation, kind: String, id: String, point: Vector2, owner: String, record_region: String, owner_ms: int, location_owner: String, location_ms: int) -> Dictionary:
	var now: int = world.elapsed_ms
	if owner_ms < 0 or location_ms < 0 or owner_ms > now or location_ms > now or world.target_ms < now:
		return _failure("invalid_time")
	return {
		"ok": true, "kind": kind, "id": id,
		"position": point, "cell": TileGrid.world_to_cell(point),
		"state_owner": owner, "record_region": record_region,
		"owner_time_ms": owner_ms, "location_owner": location_owner,
		"location_time_ms": location_ms, "world_time_ms": now,
		"target_time_ms": world.target_ms, "world_has_backlog": world.target_ms > now,
		"stale": owner_ms < now or location_ms < now,
	}


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
