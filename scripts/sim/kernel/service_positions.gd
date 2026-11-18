extends RefCounted
## Derived body/destination occupancy. Execution exclusivity remains World.reservations.
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Positions = preload("res://scripts/sim/kernel/work_positions.gd")
const CLEARANCE: float = 0.04
const SERVICE_RADIUS: float = 0.35

static func uses_station(world: RefCounted, target: int) -> bool:
	# Loose goods and personal contacts have no long-lived service station.
	# Their concurrent transactions/participation remain owned by the host.
	return world.objects.records.get(target, {}).get("kind", "") not in ["", "actor", "pile"]

static func occupants(world: RefCounted, point: Vector2, radius: float, actor: int, destinations: bool = true) -> Array[int]:
	var result: Array[int] = []
	for other: int in world.stations.nearby(world, point, radius + CLEARANCE, destinations):
		if other == actor or not world.actor_slots.has(other): continue
		var slot: int = int(world.actor_slots[other])
		var page: RefCounted = world.pages[slot / 256]
		var row: int = slot % 256
		if page.health[row] <= 0: continue
		var minimum: float = radius + page.radii[row] + CLEARANCE
		if point.distance_squared_to(world.position_at(other)) < minimum * minimum:
			result.append(other)
		elif destinations and page.modes[row] in [world.Units.Mode.APPROACH, world.Units.Mode.RESOURCE, world.Units.Mode.EXPLORE, world.Units.Mode.MANUAL] and point.distance_squared_to(page.targets[row]) < minimum * minimum:
			result.append(other)
	return result

static func idle_actor(world: RefCounted, actor: int) -> bool:
	if actor == 1 or not world.actor_slots.has(actor) or not world.combat.alive(world, actor): return false
	var slot: int = world.actor_slots[actor]
	return world.objects.records[actor].get("autonomous", false) and not world.decisions.records.get(actor, {}).get("manual", false) and not world.decisions.in_combat(actor) and world.gate.current(actor).is_empty() and world.pages[slot / 256].modes[slot % 256] == world.Units.Mode.IDLE

static func request_clearance(world: RefCounted, occupants: Array[int]) -> void:
	for actor: int in occupants:
		if idle_actor(world, actor): world.decisions.wake(world, actor, world.operation_time(), "space_needed", 50)

static func is_service_cell(world: RefCounted, point: Vector2, radius: float = SERVICE_RADIUS) -> bool:
	var minimum: float = radius + SERVICE_RADIUS + CLEARANCE
	for target: int in world.objects.nearby(point, 5.0, false):
		var record: Dictionary = world.objects.records[target]
		if record.kind in ["pile", "floor", "wall", "door"]: continue
		var spec: Dictionary = world.facilities.definitions.get(record.definition, {})
		if record.kind not in ["plant", "resource", "blueprint"] and spec.get("capabilities", {}).is_empty(): continue
		# A body just across a tile edge can still obstruct a service point.
		# Future solids also need their whole footprint clear before starting.
		if record.kind == "blueprint":
			for tile: int in record.cells:
				if world._body_overlaps_tile(point, radius, tile): return true
		var operations: Array = spec.get("work_positions", {}).keys()
		if not operations.has("default"): operations.append("default")
		for operation: String in operations:
			for tile: int in Positions.cells(world, target, operation):
				if point.distance_squared_to(Terrain.center(tile)) < minimum * minimum: return true
	return false

static func step_aside(world: RefCounted, actor: int, at: int, quiet: bool = true) -> bool:
	if not idle_actor(world, actor): return false
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	var origin: Vector2 = page.positions[row]
	var overlapping: bool = not occupants(world, origin, page.radii[row], actor, false).is_empty()
	if not is_service_cell(world, origin, page.radii[row]) and not overlapping: return false
	var centre := Vector2i(origin.floor())
	# Bounded local search and actual movement, no perpetual wandering or push.
	for pass_index: int in (2 if overlapping else 1):
		for ring: int in range(1, 5):
			for offset: int in range(ring * 8):
				var index: int = (offset + actor) % (ring * 8)
				var side: int = index / (ring * 2)
				var along: int = index % (ring * 2) - ring
				var delta: Vector2i = [Vector2i(along, -ring), Vector2i(ring, along), Vector2i(-along, ring), Vector2i(-ring, -along)][side]
				var cell: Vector2i = centre + delta
				if cell.x < 1 or cell.y < 1 or cell.x >= Terrain.SIZE - 1 or cell.y >= Terrain.SIZE - 1: continue
				var point: Vector2 = Vector2(cell) + Vector2.ONE * 0.5
				if not world.terrain.can_stand(point, page.radii[row], page.flight[row] > 0) or not occupants(world, point, page.radii[row], actor).is_empty(): continue
				if pass_index == 0 and is_service_cell(world, point, page.radii[row]): continue
				if not world.terrain.segment_clear(origin, point, page.radii[row], page.flight[row] > 0): continue
				if not world.adopt_motion(actor, at): return false
				page.move_to(row, point, world.Units.Mode.EXPLORE)
				world.decisions.track_host(world, actor)
				if quiet:
					world.decisions.records[actor].task.merge({"purpose": "clearance", "reconsider": false, "knowledge_revision": int(world.knowledge.records.get(actor, {}).get("next_revision", 1))})
				return true
	return false
