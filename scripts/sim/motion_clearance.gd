class_name SimMotionClearance
extends RefCounted
## Read-only reservations of existing motion; no second body or route state.
## Call these queries only for a proposed change that adds ground obstruction.
## The runtime-owned player journey is queried separately with segment_reserves.


static func active_segment_reserves(world: RefCounted, cell: Vector2i) -> bool:
	if world == null:
		return false
	var bodies: Dictionary = {}
	for sim: VillageSimulation in world.regions.values():
		for actor: String in sim.synchronize_actors():
			var body: Dictionary = sim.synchronize_actor(actor)
			bodies[actor] = body
			var action: Dictionary = body.get("active", {})
			if action.get("phase") == "travel" and segment_reserves(body, action, cell):
				return true
	if world.services != null:
		for actor: String in world.services.active_jobs:
			var job: Dictionary = world.services.jobs[world.services.active_jobs[actor]]
			if job.get("phase") == "travel" and not bool(job.get("road_paused", false)) and segment_reserves(bodies.get(actor, {}), job, cell):
				return true
	for domain: RefCounted in [world.construction, world.facility_use, world.resting, world.plants, world.personal_production, world.capability_practice]:
		if domain == null:
			continue
		for actor: String in domain.active:
			var job: Dictionary = domain.active[actor]
			var phase: String = str(job.get("phase", ""))
			if (phase.begins_with("to_") or phase in ["travel", "leave", "walk"]) and segment_reserves(bodies.get(actor, {}), job, cell):
				return true
	if world.field_opportunities != null:
		var field: RefCounted = world.field_opportunities
		for actor: String in field.purposes:
			if not field.owns_actor(actor):
				continue
			var trip: Dictionary = field.trips[field.purposes[actor].trip]
			if segment_reserves(bodies.get(actor, {}), trip, cell):
				return true
	if world.soul_vessels != null:
		for actor: String in world.soul_vessels.agency.errands:
			var job: Dictionary = world.soul_vessels.agency.errands[actor]
			if job.get("phase") in ["approach", "carry"] and segment_reserves(bodies.get(actor, {}), job, cell):
				return true
	return false


static func segment_reserves(body: Dictionary, route: Dictionary, cell: Vector2i) -> bool:
	var path: Variant = route.get("path", [])
	if not path is Array:
		return true
	if path.is_empty():
		return false
	if not SimLocalMotion._vector(body.get("position")) or not SimLocalMotion._vector(route.get("segment_from")) or not VillageSimulation._valid_cell(path[0]):
		# An invalid live leg must not permit a new obstacle anywhere. Normal
		# persisted states are validated by their original owner before adoption.
		return true
	var origin_raw: Array = route.segment_from
	var origin: Vector2i = TileGrid.world_to_cell(Vector2(float(origin_raw[0]), float(origin_raw[1])))
	var target: Vector2i = SimRouteTravel.cell(path[0])
	if absi(target.x - origin.x) > 1 or absi(target.y - origin.y) > 1:
		return true
	var current: Vector2i = TileGrid.world_to_cell(SimRouteTravel.point(body))
	# Preserve the entire current leg until its owner consumes path[0], even
	# after crossing into the target cell. A diagonal protects both side cells.
	return current == cell or _leg_rectangle_contains(origin, target, cell)


static func fixed_road_reserves(world: RefCounted, cell: Vector2i) -> bool:
	if world == null:
		return false
	for route: Dictionary in world.settings.get("routes", {}).values():
		if route.has("path"):
			var path: Variant = route.path
			if not path is Array or path.size() < 2 or not VillageSimulation._valid_cell(path[0]):
				return true
			var previous: Vector2i = SimRouteTravel.cell(path[0])
			if previous == cell:
				return true
			for index: int in range(1, path.size()):
				if not VillageSimulation._valid_cell(path[index]):
					return true
				var next: Vector2i = SimRouteTravel.cell(path[index])
				if _road_leg_contains(previous, next, cell):
					return true
				previous = next
		else:
			# Older assemblies may have no encoded path. Their original courier
			# projection interpolates directly between the two warehouse cells.
			var origin: Variant = _route_place_cell(world, route.get("from"), route.get("source"))
			var target: Variant = _route_place_cell(world, route.get("to"), route.get("target"))
			if origin == null or target == null:
				return true
			if _road_leg_contains(origin, target, cell):
				return true
	return false


static func _leg_rectangle_contains(from: Vector2i, to: Vector2i, cell: Vector2i) -> bool:
	var low: Vector2i = from.min(to)
	var high: Vector2i = from.max(to)
	return cell.x >= low.x and cell.y >= low.y and cell.x <= high.x and cell.y <= high.y


static func _road_leg_contains(from: Vector2i, to: Vector2i, cell: Vector2i) -> bool:
	if not _leg_rectangle_contains(from, to, cell):
		return false
	# Test the center-to-center segment against the closed square for this
	# cell. Inclusive corner crossings also protect both diagonal side cells.
	var origin: Vector2 = Vector2(from) + Vector2(0.5, 0.5)
	var direction: Vector2 = Vector2(to - from)
	var enter: float = 0.0
	var leave: float = 1.0
	for axis: int in 2:
		var edge: float = float(cell[axis])
		if is_zero_approx(direction[axis]):
			if origin[axis] < edge or origin[axis] > edge + 1.0:
				return false
			continue
		var a: float = (edge - origin[axis]) / direction[axis]
		var b: float = (edge + 1.0 - origin[axis]) / direction[axis]
		enter = maxf(enter, minf(a, b))
		leave = minf(leave, maxf(a, b))
		if enter > leave + 0.000000001:
			return false
	return true


static func _route_place_cell(world: RefCounted, region: Variant, place: Variant) -> Variant:
	if not region is String or not place is String or not world.regions.has(region):
		return null
	var sim: VillageSimulation = world.regions[region]
	var location: Variant = sim.places.get(place)
	if not location is Dictionary or not VillageSimulation._valid_cell(location.get("cell")):
		return null
	return SimRouteTravel.cell(location.cell)
