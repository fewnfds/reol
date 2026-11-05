class_name SimStorageQuery
extends RefCounted
## Read-only authority/editor query. A storage reference is not a new physical
## item ID, a permission to transfer, or evidence available to a player.
## No state, clock settlement, inventory copy or persistent location cache.


static func locate(world: RegionalSimulation, reference: Variant) -> Dictionary:
	if world == null:
		return _failure("world_unavailable")
	if not _reference_valid(reference, false):
		return _failure("invalid_reference")
	var domain: String = reference.domain
	if domain not in ["village", "avian"]:
		return _failure("unsupported_domain")
	var region: String = reference.region
	if not world.regions.get(region) is VillageSimulation:
		return _failure("not_found")
	return _village(world, reference) if domain == "village" else _avian(world, reference)


static func item(world: RegionalSimulation, reference: Variant) -> Dictionary:
	if world == null:
		return _failure("world_unavailable")
	if not _reference_valid(reference, true):
		return _failure("invalid_reference")
	var storage: Dictionary = reference.duplicate(true)
	storage.erase("item")
	var result: Dictionary = locate(world, storage)
	if not bool(result.ok):
		return result
	var ledger: SimInventory = world.regions[reference.region].inventory if reference.domain == "village" else world.avian_life.inventory
	var container: String = reference.container
	var type: String = reference.item
	result.reference = reference.duplicate(true)
	result["entry_present"] = ledger.containers[container].has(type)
	result["quantity"] = ledger.quantity(container, type)
	result["available"] = ledger.available(container, type)
	result["entrusted"] = ledger.entrusted(container, type)
	return result


static func _reference_valid(reference: Variant, with_item: bool) -> bool:
	if not reference is Dictionary or reference.size() != (4 if with_item else 3):
		return false
	var fields: Array[String] = ["domain", "region", "container"]
	if with_item:
		fields.append("item")
	for field: String in fields:
		if not reference.get(field) is String or not SimInventory._nonempty(reference[field]):
			return false
	return true


static func _village(world: RegionalSimulation, reference: Dictionary) -> Dictionary:
	var sim: VillageSimulation = world.regions[reference.region]
	var container: String = reference.container
	if not sim.inventory.containers.has(container):
		return _failure("not_found")
	if container.begins_with("ground:"):
		if world.object_lifecycle == null:
			return _failure("domain_unavailable")
		var slot: Dictionary = world.object_lifecycle.ground.locate(reference.region, container)
		if not bool(slot.ok) or slot.reference.kind != "stock":
			return _failure("invalid_location")
		return _result(world, reference, TileGrid.cell_to_world(slot.cell), "village_inventory", sim.elapsed_ms, "ground_placements", world.elapsed_ms, {})
	var actor: String = container.trim_prefix("actor:") if container.begins_with("actor:") else ""
	var construction: SimConstruction = world.construction
	var project_here: bool = construction != null and construction.world == world and construction.definitions.get("site", {}).get("region") == reference.region and construction.projects.has(container)
	var candidates: int = int(not actor.is_empty() and sim.actors.has(actor)) + int(sim.places.has(container)) + int(project_here)
	if candidates > 1:
		return _failure("ambiguous_reference")
	if not actor.is_empty() and sim.actors.has(actor):
		return _actor_anchor(world, reference, sim, actor)
	if sim.places.has(container):
		var place: Variant = sim.places[container]
		if not place is Dictionary or not VillageSimulation._valid_cell(place.get("cell")):
			return _failure("invalid_location")
		return _result(world, reference, TileGrid.cell_to_world(SimRouteTravel.cell(place.cell)), "village_inventory", sim.elapsed_ms, "village_simulation", sim.elapsed_ms, {})
	if project_here:
		var project: Variant = construction.projects[container]
		if not project is Dictionary or not project.get("carrier") is String:
			return _failure("invalid_location")
		var carrier: String = project.carrier
		if not carrier.is_empty():
			if not construction.active.get(carrier) is Dictionary or construction.active[carrier].get("project") != container:
				return _failure("invalid_location")
			return _actor_anchor(world, reference, sim, carrier)
		if not VillageSimulation._valid_cell(project.get("material_cell")):
			return _failure("invalid_location")
		# Empty containers still have a recorded anchor. Quantity zero must never
		# be interpreted as a physical pile at this location.
		return _result(world, reference, TileGrid.cell_to_world(SimRouteTravel.cell(project.material_cell)), "village_inventory", sim.elapsed_ms, "construction", world.elapsed_ms, {})
	# Ledger IDs are not coordinates. No fallback to a place, body or (0,0).
	return _failure("unsupported_location")


static func _actor_anchor(world: RegionalSimulation, reference: Dictionary, sim: VillageSimulation, id: String) -> Dictionary:
	var point: Variant = actor_position(sim.actors.get(id))
	if point == null:
		return _failure("invalid_location")
	return _result(world, reference, point, "village_inventory", sim.elapsed_ms, "village_simulation", sim.elapsed_ms, {"kind": "actor", "id": id})


static func _avian(world: RegionalSimulation, reference: Dictionary) -> Dictionary:
	var domain: SimAvianLife = world.avian_life
	if domain == null:
		return _failure("domain_unavailable")
	if domain.world != world:
		return _failure("invalid_world")
	var container: String = reference.container
	if not domain.inventory.containers.has(container):
		return _failure("not_found")
	if container.begins_with("bird:"):
		var id: String = container.trim_prefix("bird:")
		var body: Variant = domain.birds.get(id)
		if not body is Dictionary or body.get("region") != reference.region or not SimAvianLife.Schema.position_valid(body.get("position")) or not SimAvianLife.Schema.count(body.get("altitude"), 0, 1):
			return _failure("invalid_location")
		var result: Dictionary = _result(world, reference, SimAvianLife.point(body), "avian_inventory", domain.elapsed_ms, "avian_life", domain.elapsed_ms, {"kind": "avian", "id": id})
		if bool(result.ok):
			result["altitude"] = int(body.altitude)
		return result
	var site: Variant = domain.sites.get(container)
	if not site is Dictionary:
		return _failure("unsupported_location")
	if site.get("region") != reference.region or not SimAvianLife.Schema.cell_valid(site.get("cell")):
		return _failure("invalid_location")
	return _result(world, reference, TileGrid.cell_to_world(SimRouteTravel.cell(site.cell)), "avian_inventory", domain.elapsed_ms, "avian_life", domain.elapsed_ms, {})


static func actor_position(body: Variant) -> Variant:
	# Use the village body's own coordinate contract, independent of bird/map
	# bounds. Never repair a disagreeing cell and continuous coordinate.
	if not body is Dictionary or not SimLocalMotion._vector(body.get("position")) or not VillageSimulation._valid_cell(body.get("cell")):
		return null
	var point := Vector2(float(body.position[0]), float(body.position[1]))
	return point if TileGrid.world_to_cell(point) == SimRouteTravel.cell(body.cell) else null


static func _result(world: RegionalSimulation, reference: Dictionary, point: Vector2, owner: String, owner_ms: int, location_owner: String, location_ms: int, carrier: Dictionary) -> Dictionary:
	var now: int = world.elapsed_ms
	if owner_ms < 0 or location_ms < 0 or owner_ms > now or location_ms > now or world.target_ms < now:
		return _failure("invalid_time")
	return {"ok": true, "reference": reference.duplicate(true), "position": point, "cell": TileGrid.world_to_cell(point),
		"state_owner": owner, "record_region": str(reference.region), "owner_time_ms": owner_ms,
		"location_owner": location_owner, "location_time_ms": location_ms, "carrier": carrier,
		"world_time_ms": now, "target_time_ms": world.target_ms, "world_has_backlog": world.target_ms > now,
		"stale": owner_ms < now or location_ms < now}


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
