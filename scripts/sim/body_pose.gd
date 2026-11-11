class_name HumanoidPose
extends RefCounted
## Read-only presentation of existing bodies/routes/actions. No simulation writes.


class WorldFrame extends RefCounted:
	## A single committed observation: actual cross-domain jobs and hand motions
	## override the native job in the same order for home and visiting bodies.
	var at_ms: int
	var _jobs: Dictionary = {}
	var _hand_actions: Dictionary = {}
	var _sparring_people: Dictionary = {}

	func _init(world: RegionalSimulation, now: int) -> void:
		at_ms = now
		for domain: RefCounted in [world.capability_practice, world.personal_production, world.resting, world.construction]:
			if domain != null:
				_jobs.merge(domain.active, true)
		if world.field_opportunities != null:
			for id: String in world.field_opportunities.purposes:
				var route: Dictionary = world.field_opportunities.route_projection(id)
				if not route.is_empty():
					_jobs[id] = route
		if world.services != null:
			for id: String in world.services.active_jobs:
				_jobs[id] = world.services.jobs[world.services.active_jobs[id]]
		for domain: RefCounted in [world.clothing, world.method_records, world.capability_practice]:
			if domain != null:
				_hand_actions.merge(domain.active, true)
		if world.sparring != null and not world.sparring.bout.is_empty():
			_sparring_people = world.sparring.bout.people

	func pose(owner: VillageSimulation, id: String, body: Dictionary, native_leg: int = -1, journey: Dictionary = {}, manual_moving: bool = false, local_action: Dictionary = {}) -> Dictionary:
		return pose_read(owner.coarse_native_timeline(id), id, body, native_leg, journey, manual_moving, local_action)

	func pose_read(timeline: SimRouteTravel.Timeline, id: String, body: Dictionary, native_leg: int = -1, journey: Dictionary = {}, manual_moving: bool = false, local_action: Dictionary = {}) -> Dictionary:
		# Owner lends these inputs read-only until its batch is collected. This
		# function never queries an owner, Node, resource loader or live getter.
		var job: Dictionary = journey if id == "player" and not journey.is_empty() else _jobs.get(id, body.active)
		if is_same(job, body.active):
			if timeline != null and at_ms < timeline.ends[-1]:
				var leg: int = native_leg if native_leg >= 0 else timeline.leg_at(at_ms)
				var direction: Vector2 = timeline.heading_on_leg(at_ms, leg, SimRouteTravel.facing(body))
				return {"direction": direction, "moving": true, "time_ms": at_ms, "action": "walk", "started_ms": 0}
		var result: Dictionary = HumanoidPose.from_body(body, at_ms, job, manual_moving)
		if bool(result.moving):
			return result
		# Sleeping patients and unrelated occupied bodies do not gesture.
		if _hand_actions.has(id):
			result.action = "gesture"
			result.started_ms = int(_hand_actions[id].started_ms)
		if not local_action.is_empty():
			_apply_gesture(result, local_action)
		if _sparring_people.has(id):
			var action: Dictionary = _sparring_people[id].action
			if not action.is_empty():
				_apply_gesture(result, action)
		return result

	static func _apply_gesture(result: Dictionary, action: Dictionary) -> void:
		result.direction = Vector2(float(action.direction[0]), float(action.direction[1]))
		result.action = "gesture"
		result.started_ms = int(action.started_ms)


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


static func stabilized(pose: Dictionary, previous: Dictionary) -> Dictionary:
	if pose.is_empty():
		return pose
	var appearance: HumanoidAppearance = HumanoidAppearance.shared()
	var index: int = HumanoidAppearance.direction_index(pose.direction, int(previous.get("direction_index", -1)), float(appearance.definition.get("turn_hysteresis_degrees", 0)))
	pose.direction_index = index
	return pose
