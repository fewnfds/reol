extends RefCounted
## Independent candidate checks; geometric validation uses the candidate walls.

const Shape = preload("res://scripts/sim/avian_schema.gd")


static func validate(data: Variant, domain: RefCounted) -> bool:
	if not Shape.keys(data, ["version", "elapsed_ms", "bodies", "events", "next_id"]) or data.version != 1 or not Shape.count(data.elapsed_ms) or data.elapsed_ms != domain.world.elapsed_ms or not data.bodies is Dictionary or data.bodies.size() > int(domain.definitions.max_bodies) or not data.events is Array or not Shape.count(data.next_id, 1):
		return false
	for id: Variant in data.bodies:
		if not SimInventory._nonempty(id) or not _body(data.bodies[id], domain, int(data.elapsed_ms)):
			return false
		var registry: SimEmbodiment = domain.world.embodiment
		var carrier: String = domain.carrier_id(id)
		if registry.carrier_for_source("large_body", id) != carrier or registry.residence_of(domain.subject_id(id)) != carrier or registry.footprint(carrier) != domain.size():
			return false
		for channel: String in SimEmbodiment.CHANNELS:
			if not registry.controls(domain.subject_id(id), carrier, channel):
				return false
	var seen: Dictionary = {}
	var latest: Dictionary = {}
	var at_ms: int = -1
	for event: Variant in data.events:
		if not Shape.keys(event, ["id", "body", "actor", "region", "at_ms", "item", "amount"]) or not event.id is String or not event.id.begins_with("large_food:") or not event.id.trim_prefix("large_food:").is_valid_int() or seen.has(event.id) or not Shape.count(event.at_ms, maxi(0, at_ms), int(data.elapsed_ms)) or not data.bodies.has(event.body) or not domain.world.regions.has(event.region):
			return false
		var serial: int = int(event.id.trim_prefix("large_food:"))
		if serial < 1 or serial >= int(data.next_id) or event.id != "large_food:%d" % serial or event.item != domain.definitions.food or event.amount != domain.definitions.food_amount:
			return false
		var sim: VillageSimulation = domain.world.regions[event.region]
		if not sim.has_actor(event.actor) or not Shape.same_record(sim.inventory.operations.get(event.id), {"kind": "consume", "container": "actor:" + str(event.actor), "item": str(event.item), "amount": int(event.amount)}):
			return false
		if latest.has(event.body) and int(event.at_ms) - int(latest[event.body]) < int(domain.definitions.feed_interval_ms):
			return false
		latest[event.body] = event.at_ms
		seen[event.id] = str(event.region)
		at_ms = int(event.at_ms)
	if seen.size() != int(data.next_id) - 1:
		return false
	for sim: VillageSimulation in domain.world.regions.values():
		for id: String in sim.inventory.operations:
			if id.begins_with("large_food:"):
				if not seen.has(id) or domain.world.regions[seen[id]] != sim:
					return false
	for id: String in data.bodies:
		if data.bodies[id].last_fed_ms != latest.get(id, -1):
			return false
	return true


static func _body(body: Variant, domain: RefCounted, now: int) -> bool:
	if not Shape.keys(body, ["label", "region", "position", "waypoints", "destination", "facing", "step", "path", "retry_ms", "last_fed_ms"]) or not SimInventory._nonempty(body.label) or not domain.world.regions.has(body.region) or not SimLocalMotion._vector(body.position) or not body.waypoints is Array or body.waypoints.size() != 2 or not Shape.count(body.destination, 0, 1) or not Shape.count(body.facing, 0, 3) or not body.path is Array or body.path.size() > int(domain.definitions.navigation_budget) or not body.step is Dictionary or not Shape.count(body.retry_ms) or not Shape.count(body.last_fed_ms, -1, now):
		return false
	var position: Vector2 = SimAvianLife.point(body)
	if position.x < 0 or position.y < 0 or position.x >= WorldMapData.WORLD_SIZE * TileGrid.TILE_SIZE or position.y >= WorldMapData.WORLD_SIZE * TileGrid.TILE_SIZE:
		return false
	for cell: Variant in body.waypoints:
		if not _cell(cell):
			return false
	if body.waypoints[0] == body.waypoints[1]:
		return false
	var at: Vector2i = TileGrid.world_to_cell(position)
	if body.step.is_empty():
		if not position.is_equal_approx(TileGrid.cell_to_world(at)) or int(body.retry_ms) <= now:
			return false
	else:
		var step: Dictionary = body.step
		if not Shape.keys(step, ["from", "to", "started_ms", "due_ms"]) or not _cell(step.from) or not _cell(step.to) or not Shape.count(step.started_ms, 0, now) or not Shape.count(step.due_ms, now + 1) or int(step.due_ms) - int(step.started_ms) != int(domain.definitions.step_ms):
			return false
		var from: Vector2i = SimRouteTravel.cell(step.from)
		at = SimRouteTravel.cell(step.to)
		if not SimBodyGeometry.DIRECTIONS.has(at - from) or SimBodyGeometry.DIRECTIONS[body.facing] != at - from:
			return false
		var projected: Vector2 = TileGrid.cell_to_world(from).lerp(TileGrid.cell_to_world(at), float(now - int(step.started_ms)) / float(domain.definitions.step_ms))
		if not projected.is_equal_approx(position):
			return false
	var origin: Vector2i = SimRouteTravel.cell(body.waypoints[0])
	if absi(at.x - origin.x) > int(domain.definitions.navigation_radius) or absi(at.y - origin.y) > int(domain.definitions.navigation_radius):
		return false
	var visited: Dictionary = {at: true}
	for cell: Variant in body.path:
		if not _cell(cell):
			return false
		var next: Vector2i = SimRouteTravel.cell(cell)
		if not SimBodyGeometry.DIRECTIONS.has(next - at) or visited.has(next) or absi(next.x - origin.x) > int(domain.definitions.navigation_radius) or absi(next.y - origin.y) > int(domain.definitions.navigation_radius):
			return false
		visited[next] = true
		at = next
	return body.path.is_empty() or at == SimRouteTravel.cell(body.waypoints[body.destination])


static func _cell(value: Variant) -> bool:
	return value is Array and value.size() == 2 and Shape.count(value[0], 0, WorldMapData.WORLD_SIZE - 1) and Shape.count(value[1], 0, WorldMapData.WORLD_SIZE - 1)
