class_name SimTerrainEdits
extends RefCounted
## Bounded developer terrain transaction. No time advancement, save/restore,
## historical-event scan, player permission or duplicated entity authority.

const MAX_CELLS: int = 256


static func apply(world: RegionalSimulation, raw: Variant, player_journey: Dictionary = {}) -> Dictionary:
	var checked: Dictionary = inspect(world, raw, player_journey)
	if not bool(checked.ok):
		return checked
	var parsed: Dictionary = world.map_data.inspect_terrain_patch(raw)
	var cells: Array[Vector2i] = []
	for cell: Vector2i in parsed.rows:
		if int(parsed.rows[cell]) != world.map_data.get_terrain(cell):
			cells.append(cell)
	var fields: SimWorldEnvironmentFields = world.environment_fields as SimWorldEnvironmentFields
	if fields != null and not cells.is_empty() and not fields.before_topology_change(world.elapsed_ms, cells):
		return _reject("pending_time")
	# Synchronous commit: no callbacks or mutations occur between preflight and
	# the map's complete validation. Notifications publish only the accepted map.
	var result: Dictionary = world.map_data.apply_terrain_patch(raw)
	if fields != null and not cells.is_empty():
		var published: bool = fields.diagnostics().error.is_empty()
		assert(published, "preflighted terrain environment publication failed")
	result["code"] = "applied" if bool(result.ok) else "invalid_patch"
	return result


static func inspect(world: RegionalSimulation, raw: Variant, player_journey: Dictionary = {}) -> Dictionary:
	if world == null or world.map_data == null:
		return _reject("no_world")
	if world.elapsed_ms != world.target_ms:
		return _reject("pending_time")
	for sim: VillageSimulation in world.regions.values():
		if sim.elapsed_ms != world.elapsed_ms:
			return _reject("unsynchronized_region")
	if not raw is Array or raw.size() > MAX_CELLS:
		return _reject("brush_limit")
	var parsed: Dictionary = world.map_data.inspect_terrain_patch(raw)
	if not bool(parsed.ok):
		return _reject("invalid_patch")
	var changes: Dictionary = {}
	for cell: Vector2i in parsed.rows:
		if int(parsed.rows[cell]) != world.map_data.get_terrain(cell):
			changes[cell] = int(parsed.rows[cell])
	if changes.is_empty():
		return {"ok": true, "code": "unchanged"}
	for cell: Vector2i in changes:
		if _fixed_space(world, cell):
			return _reject("fixed_space", cell)
	# Only the resulting nonwalkable cells can invalidate current occupancy or
	# pedestrian routes; rock additionally obstructs active remote contact.
	for cell: Vector2i in changes:
		if int(changes[cell]) != WorldMapData.TERRAIN_GRASS and _occupied(world, cell):
			return _reject("occupied", cell)
		if int(changes[cell]) == WorldMapData.TERRAIN_ROCK and _contact_reserved(world, cell):
			return _reject("active_contact", cell)
	if not _routes_open(world, changes, player_journey):
		return _reject("reserved_route")
	return {"ok": true, "code": "ready"}


static func _fixed_space(world: RegionalSimulation, cell: Vector2i) -> bool:
	if world.construction != null and (world.construction.protected_cell(cell) or world.construction.site_contains(cell) or world.construction.material_cell_referenced(cell)):
		return true
	for sim: VillageSimulation in world.regions.values():
		for place: Dictionary in sim.places.values():
			if SimRouteTravel.cell(place.cell) == cell:
				return true
		# Protect the existing room's entry apron as well as its full roof.
		var room: Dictionary = sim.places.get("records", {}).get("workspace", {})
		if not room.is_empty() and SimRouteTravel.cell(room.door).distance_squared_to(cell) <= 1:
			return true
	if world.field_opportunities != null:
		for site: Dictionary in world.field_opportunities.sites.values():
			if SimRouteTravel.cell(site.cell) == cell:
				return true
	if world.avian_life != null:
		for site: Dictionary in world.avian_life.sites.values():
			if SimRouteTravel.cell(site.cell) == cell:
				return true
	return false


static func _occupied(world: RegionalSimulation, cell: Vector2i) -> bool:
	if world.object_lifecycle != null:
		var ground: Dictionary = world.object_lifecycle.ground.query(Rect2i(cell, Vector2i.ONE), 512)
		if not bool(ground.ok) or not ground.ids.is_empty():
			return true
	for sim: VillageSimulation in world.regions.values():
		for body: Dictionary in sim.actors.values():
			# Dead bodies still have one spatial owner; terrain editing cannot
			# quietly relocate them or make their current archive invalid.
			if SimRouteTravel.cell(body.cell) == cell:
				return true
	if world.avian_life != null:
		for id: String in world.avian_life.birds:
			if int(world.avian_life.birds[id].altitude) == 0 and world.avian_life.body_cell(id) == cell:
				return true
	if world.large_bodies != null:
		for id: String in world.large_bodies.bodies:
			if world.large_bodies.swept_bounds(id).has_point(cell):
				return true
	return false


static func _routes_open(world: RegionalSimulation, changes: Dictionary, journey: Dictionary) -> bool:
	var actors: Dictionary = {}
	for sim: VillageSimulation in world.regions.values():
		for id: String in sim.actors:
			var body: Dictionary = sim.actor_state(id)
			var start: Vector2i = SimRouteTravel.cell(body.cell)
			actors[id] = start
			if not _path_open(world, changes, start, body.active.get("path", [])):
				return false
			if world.field_opportunities != null and not _path_open(world, changes, start, world.field_opportunities.route_projection(id).get("path", [])):
				return false
	if not journey.is_empty() and not _path_open(world, changes, actors["player"], journey.get("path", [])):
		return false
	if world.services != null:
		for id: String in world.services.active_jobs:
			var job: Dictionary = world.services.jobs[world.services.active_jobs[id]]
			if not _path_open(world, changes, actors[id], job.get("path", [])):
				return false
	for domain: RefCounted in [world.construction, world.facility_use, world.resting, world.plants, world.personal_production, world.capability_practice]:
		if domain == null:
			continue
		for id: String in domain.active:
			var job: Dictionary = domain.active[id]
			if not _path_open(world, changes, actors[id], job.get("path", [])):
				return false
			for key: String in ["stand", "destination"]:
				if job.get(key) is Array and job[key].size() == 2 and not _open(world, changes, SimRouteTravel.cell(job[key])):
					return false
	if world.soul_vessels != null:
		for id: String in world.soul_vessels.agency.errands:
			if not _path_open(world, changes, actors[id], world.soul_vessels.agency.errands[id].path):
				return false
	for route: Dictionary in world.settings.get("routes", {}).values():
		var path: Array = route.get("path", [])
		if not path.is_empty() and not _path_open(world, changes, SimRouteTravel.cell(path[0]), path):
			return false
	if world.large_bodies != null:
		for id: String in world.large_bodies.bodies:
			var body: Dictionary = world.large_bodies.bodies[id]
			var size: Vector2i = world.large_bodies.size()
			for raw: Array in body.waypoints:
				if not _footprint_open(world, changes, SimRouteTravel.cell(raw), size):
					return false
			for raw: Array in body.path:
				if not _footprint_open(world, changes, SimRouteTravel.cell(raw), size):
					return false
	return true


static func _open(world: RegionalSimulation, changes: Dictionary, cell: Vector2i) -> bool:
	return int(changes[cell]) == WorldMapData.TERRAIN_GRASS if changes.has(cell) else world.map_data.terrain_is_walkable(cell)


static func _path_open(world: RegionalSimulation, changes: Dictionary, start: Vector2i, path: Array) -> bool:
	var current: Vector2i = start
	for raw: Array in path:
		var next: Vector2i = SimRouteTravel.cell(raw)
		var step: Vector2i = next - current
		if not _open(world, changes, next):
			return false
		if step.x != 0 and step.y != 0:
			# Check the whole patch together. A remaining diagonal may lose its
			# last terrain OR physical-cover bypass without either endpoint moving.
			var side_a := Vector2i(next.x, current.y)
			var side_b := Vector2i(current.x, next.y)
			if not _open(world, changes, side_a) and not _open(world, changes, side_b):
				return false
			if _solid(world, changes, side_a) and _solid(world, changes, side_b):
				return false
		current = next
	return true


static func _solid(world: RegionalSimulation, changes: Dictionary, cell: Vector2i) -> bool:
	if world.plants != null and world.plants.blocked(cell):
		return true
	if world.large_bodies != null and world.large_bodies.blocked(cell):
		return true
	return SimConflictSpace.solid(world, cell, 0) if not changes.has(cell) else int(changes[cell]) == WorldMapData.TERRAIN_ROCK or world.construction.blocked(cell)


static func _footprint_open(world: RegionalSimulation, changes: Dictionary, cell: Vector2i, size: Vector2i) -> bool:
	for occupied: Vector2i in SimBodyGeometry.cells(cell, size):
		if not _open(world, changes, occupied):
			return false
	return true


static func _contact_reserved(world: RegionalSimulation, cell: Vector2i) -> bool:
	if world.artifacts != null:
		for job: Dictionary in world.artifacts.active.values():
			if job.get("verb") == "draw" and job.get("draw") is Dictionary:
				var draw: Dictionary = job.draw
				if _between_cells(cell, TileGrid.world_to_cell(Vector2(float(draw.caster_position[0]), float(draw.caster_position[1]))), SimRouteTravel.cell(draw.from_cell)):
					return true
			if _artifact_contact_reserved(world, job, cell):
				return true
	if world.private_exchange != null:
		for id: String in world.private_exchange.active_jobs:
			var job: Dictionary = world.private_exchange.jobs[id]
			var from: Vector2i = TileGrid.world_to_cell(Vector2(float(job.buyer_position[0]), float(job.buyer_position[1])))
			var to: Vector2i = TileGrid.world_to_cell(Vector2(float(job.seller_position[0]), float(job.seller_position[1])))
			if _between_cells(cell, from, to):
				return true
	return false


static func _artifact_contact_reserved(world: RegionalSimulation, job: Dictionary, cell: Vector2i) -> bool:
	var domain: SimArtifacts = world.artifacts
	var id: String = str(job.get("object", ""))
	if not domain.objects.has(id):
		return false
	var item: Dictionary = domain.objects[id]
	# _near() for remote-draw tools requires clear contact for ordinary take,
	# examine/study and invited/guide operations too, not just the draw verb.
	if domain.has_capability(id, "remote_draw"):
		var target: Vector2i = domain.object_cell(id)
		for actor: String in [str(job.actor), str(job.get("recipient", "")), str(job.get("method", {}).get("guide", ""))]:
			var region: String = domain.actor_home(actor)
			if not region.is_empty() and _between_cells(cell, SimRouteTravel.cell(world.regions[region].actor_state(actor).cell), target):
				return true
	# Placing a carried tool into a fixed field slot also checks clear reach;
	# its current position is the holder, not that future storage destination.
	var destination: String = str(domain.definitions.types[item.definition].get("storage_place", ""))
	if job.get("verb") == "place" and destination.begins_with("site:"):
		var region: String = domain.storage_region(str(item.region), destination)
		var actor_region: String = domain.actor_home(str(job.actor))
		if not region.is_empty() and not actor_region.is_empty():
			var target: Vector2i = world.field_opportunities.slot_cell(region, destination)
			return _between_cells(cell, SimRouteTravel.cell(world.regions[actor_region].actor_state(job.actor).cell), target)
	return false


static func _between_cells(cell: Vector2i, from: Vector2i, to: Vector2i) -> bool:
	return Rect2i(from.min(to), (from - to).abs() + Vector2i.ONE).has_point(cell)


static func _reject(code: String, cell: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	return {"ok": false, "code": code, "cell": cell}
