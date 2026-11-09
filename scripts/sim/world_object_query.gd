class_name SimWorldObjectQuery
extends RefCounted
## Authority-only projections over existing owners. No registration, spawning,
## settlement, permission grant, world mutation or implicit observer knowledge.
## Each returned dictionary/array is detached. Kinds select adapters, never a
## particular content name. Stock/source records are not invented item instances.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const ENTITY_KINDS: Array[String] = ["actor", "avian", "artifact", "large_body"]
const MAX_CAPTURE_OBJECTS: int = 4096
const MAX_CAPTURE_CELLS: int = 65536


static func describe(world: RegionalSimulation, reference: Variant) -> Dictionary:
	if world == null:
		return _failure("world_unavailable")
	if not world.accepts_commands():
		return _failure("settlement_pending")
	if not reference is Dictionary or not _text(reference.get("kind")):
		return _failure("invalid_reference")
	var kind: String = reference.kind
	if kind in ENTITY_KINDS:
		return _entity(world, reference)
	match kind:
		"plant":
			return _plant(world, reference)
		"stock":
			return _stock(world, reference)
		"resource":
			return _resource(world, reference)
		"construction", "workplace":
			return _structure(world, reference)
	return _failure("unsupported_kind")


static func capability(world: RegionalSimulation, reference: Variant, name: String) -> Dictionary:
	if not _text(name):
		return _failure("invalid_capability")
	var row: Dictionary = describe(world, reference)
	if not bool(row.ok):
		return row
	# A stale declaration is reported as stale, never silently settled or used
	# to authorize an action. Consumers must revalidate before any world change.
	var known: bool = row.capabilities.has(name)
	match row.capability_namespace:
		"body_form":
			known = world.embodiment.recognizes_capability(name)
		"artifact_definition":
			for definition: Dictionary in world.artifacts.definitions.types.values():
				if SimArtifacts.type_has_capability(definition, name):
					known = true
		"inventory_entry":
			known = name == "quantity_record"
		"resource_record":
			known = name in ["finite_source", "ecology_response"]
		"plant_definition":
			known = name in ["plant_body", "growth", "damageable", "harvest", "rooted", "communication"]
		"structure_geometry":
			known = name in ["structure_geometry", "damageable"] or name in SimConstructionGeometry.CAPABILITIES
	if not known:
		return _failure("unsupported_capability")
	return {"ok": true, "reference": row.reference, "capability": name,
		"namespace": row.capability_namespace, "declared": row.capabilities.has(name),
		"scope": "declaration_only", "stale": row.stale,
		"world_has_backlog": row.world_has_backlog, "world_time_ms": row.world_time_ms}


static func capture(world: RegionalSimulation, references: Array, budget: int = MAX_CAPTURE_OBJECTS) -> Dictionary:
	# One synchronous capture; there is no reliable global same-time revision in
	# the current world. The result therefore stays explicitly historical. It is
	# not a live occupancy index or an enumeration of all world objects.
	if world == null:
		return _failure("world_unavailable")
	if budget < 1 or budget > MAX_CAPTURE_OBJECTS:
		return _failure("invalid_budget")
	if references.size() > budget:
		return _failure("budget_exhausted")
	if world.elapsed_ms < 0 or world.target_ms < world.elapsed_ms:
		return _failure("invalid_time")
	if world.target_ms > world.elapsed_ms:
		return _failure("world_has_backlog")
	var snapshot := SimObjectSpatialSnapshot.new(MAX_CAPTURE_OBJECTS, MAX_CAPTURE_CELLS)
	var cell_count: int = 0
	for reference: Variant in references:
		var row: Dictionary = describe(world, reference)
		if not bool(row.ok):
			return row
		if bool(row.stale):
			return _failure("stale_source")
		var cells: Array[Vector2i] = row.spatial.cells
		if cells.size() > MAX_CAPTURE_CELLS - cell_count:
			return _failure("budget_exhausted")
		cell_count += cells.size()
		var appended: Dictionary = snapshot.append(row.reference, cells, row.spatial.layer, row.spatial.relation)
		if not bool(appended.ok):
			return appended
	var sealed: Dictionary = snapshot.seal(world.elapsed_ms)
	if not bool(sealed.ok):
		return sealed
	return {"ok": true, "snapshot": snapshot, "scope": "captured_references", "live": false,
		"world_time_ms": world.elapsed_ms, "object_count": references.size()}


static func _entity(world: RegionalSimulation, reference: Dictionary) -> Dictionary:
	var row: Dictionary = SimEntityQuery.locate(world, reference)
	if not bool(row.ok):
		return row
	var cells: Array[Vector2i] = [row.cell]
	var layer: String = "air" if reference.kind == "avian" and int(row.get("altitude", 0)) > 0 else "ground"
	var relation: String = "body"
	var values: Array = []
	var namespace_name: String = "body_form"
	var definition_id: String = ""
	if reference.kind == "artifact":
		var item: Variant = world.artifacts.objects.get(reference.id)
		var types: Variant = world.artifacts.definitions.get("types")
		if not item is Dictionary or not _text(item.get("definition")) or not types is Dictionary or not types.get(item.definition) is Dictionary:
			return _failure("invalid_source")
		var definition: Dictionary = types[item.definition]
		var raw: Variant = definition.get("capabilities", ["heat_storage"])
		if not _texts(raw):
			return _failure("invalid_source")
		values = raw.duplicate()
		definition_id = item.definition
		namespace_name = "artifact_definition"
		# A container anchor is not a floor pile or navigation occupancy.
		relation = "placed" if str(row.container).begins_with("site:") or str(row.container).begins_with("ground:") else "contained"
		layer = "ground" if relation == "placed" else "container"
		if str(row.container).begins_with("ground:"):
			var slot: Dictionary = world.object_lifecycle.ground.locate(item.region, item.container)
			cells = SimObjectLifecycle.ground_cells(world.object_lifecycle.ground.slots[item.container])
	else:
		var geometry: Dictionary = body_geometry(world, reference, row.cell)
		if not bool(geometry.ok):
			return geometry
		values = geometry.traits.capabilities
		definition_id = geometry.traits.form
		cells = geometry.cells
	return _finish(row, reference, "unique_item" if reference.kind == "artifact" else "body",
		cells, layer, relation, namespace_name, values, {"definition_id": definition_id})


static func body_geometry(world: RegionalSimulation, reference: Dictionary, cell: Vector2i) -> Dictionary:
	# Geometry alone has no clock assertion. Owner write notifications can
	# update derived links before the world clock commits that same boundary;
	# live queries still validate all source clocks through the normal facade.
	if world.embodiment == null:
		return _failure("domain_unavailable")
	var source_kind: String = {"actor": "village_actor", "avian": "avian_body", "large_body": "large_body"}[reference.kind]
	var carrier: String = world.embodiment.carrier_for_source(source_kind, reference.id)
	var traits: Dictionary = world.embodiment.carrier_traits(carrier)
	if not bool(traits.ok):
		return traits
	if not _texts(traits.capabilities) or not SimBodyGeometry.valid_size(traits.footprint):
		return _failure("unsupported_geometry")
	return {"ok": true, "traits": traits, "cells": SimBodyGeometry.cells(cell, traits.footprint)}


static func _stock(world: RegionalSimulation, reference: Dictionary) -> Dictionary:
	if not _keys(reference, ["kind", "domain", "region", "container", "item"]):
		return _failure("invalid_reference")
	var storage: Dictionary = reference.duplicate()
	storage.erase("kind")
	storage.erase("item")
	# locate avoids available()/entrusted() and their reservation/custody scans.
	# Availability and legal disposal remain the ledger's business operation.
	var row: Dictionary = SimStorageQuery.locate(world, storage)
	if not bool(row.ok):
		return row
	var inventory: SimInventory = world.regions[reference.region].inventory if reference.domain == "village" else world.avian_life.inventory
	var entries: Variant = inventory.containers.get(reference.container)
	if not entries is Dictionary or not entries.has(reference.item):
		return _failure("not_found")
	var amount: Variant = entries[reference.item]
	if not Shape.count(amount):
		return _failure("invalid_source")
	var cells: Array[Vector2i] = [row.cell]
	var on_ground: bool = str(reference.container).begins_with("ground:")
	if on_ground and int(amount) == 0:
		return _failure("not_found")
	return _finish(row, reference, "stock_entry", cells, "ground" if on_ground else "container", "placed" if on_ground else "contained", "inventory_entry",
		["quantity_record"], {"item_type": reference.item, "quantity": int(amount), "independent_instance": false})


static func _resource(world: RegionalSimulation, reference: Dictionary) -> Dictionary:
	if not _keys(reference, ["kind", "region", "id"]):
		return _failure("invalid_reference")
	var sim: Variant = world.regions.get(reference.region)
	if sim == null:
		return _failure("not_found")
	if not sim is VillageSimulation or sim.land_resources == null:
		return _failure("domain_unavailable")
	var domain: SimLandResources = sim.land_resources
	if not domain.bound_to(sim):
		return _failure("invalid_world")
	if not domain.sources.has(reference.id):
		return _failure("not_found")
	var source: Variant = sim.config.get("resource_sources", {}).get(reference.id)
	if not source is Dictionary or not _text(source.get("place")) or not _text(source.get("definition")):
		return _failure("invalid_source")
	var place: Variant = sim.places.get(source.place)
	var terms: Variant = domain.definitions.get("types", {}).get(source.definition)
	if not place is Dictionary or not Shape.cell_valid(place.get("cell")) or not terms is Dictionary or not _text(terms.get("item")):
		return _failure("invalid_source")
	var container: String = SimLandResources.container_id(reference.id)
	var entries: Variant = sim.inventory.containers.get(container)
	if not entries is Dictionary or not Shape.count(entries.get(terms.item)):
		return _failure("invalid_source")
	var cell: Vector2i = SimRouteTravel.cell(place.cell)
	var row: Dictionary = _timed(world, "land_resources", reference.region, sim.elapsed_ms,
		"village_simulation", sim.elapsed_ms, TileGrid.cell_to_world(cell))
	if not bool(row.ok):
		return row
	var values: Array = ["finite_source"]
	if terms.has("ecology"):
		values.append("ecology_response")
	var cells: Array[Vector2i] = [cell]
	return _finish(row, reference, "resource_record", cells, "ground", "resource", "resource_record", values,
		{"definition_id": source.definition, "item_type": terms.item, "quantity": int(entries[terms.item]),
		"quantity_owner": "village_inventory", "container": container, "independent_plant": false})


static func _structure(world: RegionalSimulation, reference: Dictionary) -> Dictionary:
	var source: Dictionary = SimStructureQuery.locate(world, reference)
	if not bool(source.ok):
		return source
	var owner_ms: int = world.elapsed_ms
	if reference.kind == "workplace":
		var sim: Variant = world.regions.get(reference.region)
		if not sim is VillageSimulation:
			return _failure("invalid_world")
		owner_ms = sim.elapsed_ms
	if source.cells.is_empty():
		return _failure("unsupported_geometry")
	var row: Dictionary = _timed(world, source.state_owner, source.region, owner_ms,
		source.state_owner, owner_ms, TileGrid.cell_to_world(source.cells[0]))
	if not bool(row.ok):
		return row
	var facts: Dictionary = {"state": source.state, "component": source.kind}
	for fact: String in SimStructureQuery.FACTS:
		facts[fact] = source[fact]
	var capabilities: Array = ["structure_geometry"]
	if reference.kind == "construction":
		for field: String in ["definition", "rotation", "hp", "max_hp", "armor", "material", "operation_slots"]:
			facts[field] = source[field]
		if source.state == "built":
			capabilities.append("damageable")
			capabilities.append_array(source.capabilities.keys())
	# Keep an aggregated wall/roof as one component with nonrectangular cells.
	return _finish(row, reference, "structure", source.cells,
		"planned" if source.state == "blueprint" else source.layer,
		"blueprint" if source.state == "blueprint" else "placed", "structure_geometry", capabilities, facts)


static func _finish(row: Dictionary, reference: Dictionary, classification: String, cells: Array[Vector2i], layer: String, relation: String, namespace_name: String, values: Array, attributes: Dictionary) -> Dictionary:
	# Strip domain-specific extras, retaining the common provenance contract.
	var result: Dictionary = {"ok": true, "reference": reference.duplicate(true),
		"classification": classification, "visibility": "authority_only",
		"capability_namespace": namespace_name, "capabilities": values.duplicate(true),
		"attributes": attributes.duplicate(true),
		"spatial": {"anchor_px": row.position, "cells": cells.duplicate(), "layer": layer,
			"relation": relation, "geometry": "cell_projection", "navigation_occupancy": false}}
	for field: String in ["state_owner", "record_region", "owner_time_ms", "location_owner", "location_time_ms", "world_time_ms", "target_time_ms", "world_has_backlog", "stale"]:
		result[field] = row[field]
	return result


static func _timed(world: RegionalSimulation, owner: String, region: String, at_ms: int, location_owner: String, location_ms: int, point: Vector2) -> Dictionary:
	if world.elapsed_ms < 0 or world.target_ms < world.elapsed_ms or at_ms < 0 or location_ms < 0 or at_ms > world.elapsed_ms or location_ms > world.elapsed_ms:
		return _failure("invalid_time")
	return {"ok": true, "position": point, "state_owner": owner, "record_region": region,
		"owner_time_ms": at_ms, "location_owner": location_owner, "location_time_ms": location_ms,
		"world_time_ms": world.elapsed_ms, "target_time_ms": world.target_ms,
		"world_has_backlog": world.target_ms > world.elapsed_ms,
		"stale": at_ms < world.elapsed_ms or location_ms < world.elapsed_ms}


static func _keys(reference: Dictionary, fields: Array) -> bool:
	if not Shape.keys(reference, fields):
		return false
	for field: String in fields:
		if not _text(reference[field]):
			return false
	return true


static func _texts(value: Variant) -> bool:
	if not value is Array:
		return false
	for entry: Variant in value:
		if not _text(entry):
			return false
	return true


static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _plant(world: RegionalSimulation, reference: Dictionary) -> Dictionary:
	var located: Dictionary = SimEntityQuery.locate(world, reference)
	if not bool(located.ok):
		return located
	var row: Dictionary = world.plants.bodies[reference.id]
	var capabilities: Array = ["plant_body", "growth", "damageable", "harvest", "rooted"]
	if not str(row.subject).is_empty():
		capabilities.append("communication")
	var cells: Array[Vector2i] = [located.cell]
	return _finish(located, reference, "plant_body", cells, "ground", "rooted" if str(row.location.support).is_empty() else "supported", "plant_definition", capabilities, {"definition_id": row.definition, "stage": row.stage, "movement_blocked": world.plants.blocked(located.cell)})
