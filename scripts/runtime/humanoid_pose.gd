class_name HumanoidPose
extends RefCounted
## Read-only presentation of existing bodies/routes/actions. No simulation writes.


static func from_body(body: Dictionary, now: int, job: Dictionary = {}, manual_moving: bool = false) -> Dictionary:
	var pose: Dictionary = {"direction": SimRouteTravel.facing(body), "moving": manual_moving,
		"time_ms": now, "action": "idle", "started_ms": 0}
	if not job.is_empty():
		var path: Array = job.get("path", [])
		if not path.is_empty() and job.has("segment_from") and not bool(job.get("road_paused", false)) and now < int(job.get("due_ms", now)):
			var origin := Vector2(float(job.segment_from[0]), float(job.segment_from[1]))
			var end: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(path[0]))
			if not origin.is_equal_approx(end):
				pose.direction = origin.direction_to(end)
				pose.moving = true
		elif job.get("phase") == "work" and job.get("action") != "rest":
			pose.action = "gesture"
			pose.started_ms = int(job.get("work_started_ms", job.get("segment_started_ms", now)))
	if pose.moving:
		pose.action = "walk"
	return pose


static func in_world(world: RegionalSimulation, id: String, now: int, journey: Dictionary = {}, manual_moving: bool = false, local_action: Dictionary = {}) -> Dictionary:
	var body: Dictionary = {}
	for sim: VillageSimulation in world.regions.values():
		if sim.actors.has(id):
			body = sim.actors[id]
			break
	if body.is_empty():
		return {}
	var job: Dictionary = body.active
	if id == "player" and not journey.is_empty():
		job = journey
	elif world.services != null and world.services.active_jobs.has(id):
		job = world.services.jobs[world.services.active_jobs[id]]
	elif world.field_opportunities != null and not world.field_opportunities.route_projection(id).is_empty():
		job = world.field_opportunities.route_projection(id)
	else:
		for domain: RefCounted in [world.construction, world.resting, world.personal_production, world.capability_practice]:
			if domain != null and domain.active.has(id):
				job = domain.active[id]
				break
	var result: Dictionary = from_body(body, now, job, manual_moving)
	if bool(result.moving):
		return result
	# Only supported ordinary hand motions use the generic technical clip. A
	# sleeping patient is not made to work merely because its body is occupied.
	for domain: RefCounted in [world.clothing, world.method_records, world.capability_practice]:
		if domain != null and domain.active.has(id):
			result.action = "gesture"
			result.started_ms = int(domain.active[id].started_ms)
	if not local_action.is_empty():
		result.direction = Vector2(float(local_action.direction[0]), float(local_action.direction[1]))
		result.action = "gesture"
		result.started_ms = int(local_action.started_ms)
	if world.sparring.owns_actor(id) and not world.sparring.bout.people[id].action.is_empty():
		var action: Dictionary = world.sparring.bout.people[id].action
		result.direction = Vector2(float(action.direction[0]), float(action.direction[1]))
		result.action = "gesture"
		result.started_ms = int(action.started_ms)
	return result


static func stabilized(pose: Dictionary, previous: Dictionary) -> Dictionary:
	if pose.is_empty():
		return pose
	var appearance: HumanoidAppearance = HumanoidAppearance.shared()
	var index: int = HumanoidAppearance.direction_index(pose.direction, int(previous.get("direction_index", -1)), float(appearance.definition.get("turn_hysteresis_degrees", 0)))
	pose.direction_index = index
	return pose
