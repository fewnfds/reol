class_name SimWorldEvents
extends SimEventQueue
## Trusted world rule catalogue. The reusable queue knows no routes or plants.
var _owner: WeakRef
var world: RegionalSimulation:
	get: return _owner.get_ref() if _owner != null else null


func initialize(authority: RegionalSimulation) -> bool:
	_owner = weakref(authority)
	clock_ms = authority.elapsed_ms
	return register_rule("route_assessment", _weak(&"_route_condition"), _weak(&"_assess_route"), _weak(&"_route_payload")) and register_rule("plant_awakening", _weak(&"_plant_condition"), _weak(&"_awaken"), _weak(&"_plant_payload"))


func _weak(method: StringName) -> Callable:
	var owner: WeakRef = weakref(self)
	if method in [&"_route_payload", &"_plant_payload"]:
		return func(payload: Dictionary) -> bool:
			var queue: RefCounted = owner.get_ref()
			return queue != null and queue.call(method, payload) == true
	return func(payload: Dictionary, context: Dictionary) -> int:
		var queue: RefCounted = owner.get_ref()
		return int(queue.call(method, payload, context)) if queue != null else Effect.INVALID


func bind_world(authority: RegionalSimulation) -> void:
	_owner = weakref(authority)


func seed_routes() -> bool:
	for id: String in world.routes:
		if not enqueue("route:" + id, "route_assessment", (world.current_time + 1) * RegionalSimulation.MINUTE_MS,
			{"route": id}, {"repeat_ms": int(world.settings.routes[id].assessment_minutes) * RegionalSimulation.MINUTE_MS}):
			return false
	return true


func cross_valid() -> bool:
	if clock_ms != world.elapsed_ms:
		return false
	for id: String in world.routes:
		var row: Dictionary = records.get("route:" + id, {})
		if row.is_empty() or row.status != "pending" or row.request.rule != "route_assessment" or row.request.payload != {"route": id} or int(row.request.repeat_ms) != int(world.settings.routes[id].assessment_minutes) * RegionalSimulation.MINUTE_MS:
			return false
	for id: String in records:
		if records[id].request.rule == "route_assessment" and id != "route:" + str(records[id].request.payload.route):
			return false
	return true


func _route_payload(payload: Dictionary) -> bool:
	return Shape.keys(payload, ["route"]) and payload.route is String and world.routes.has(payload.route)


func _route_condition(payload: Dictionary, _context: Dictionary) -> int:
	return Condition.READY if world.routes.has(payload.route) else Condition.INVALID


func _assess_route(payload: Dictionary, _context: Dictionary) -> int:
	return Effect.APPLIED if world.request_delivery(str(payload.route)) else Effect.INVALID


func _plant_payload(payload: Dictionary) -> bool:
	return Shape.keys(payload, ["plant"]) and SimInventory._nonempty(payload.plant)


func _plant_condition(payload: Dictionary, _context: Dictionary) -> int:
	if world.plants == null or not world.plants.bodies.has(payload.plant):
		return Condition.INVALID
	var row: Dictionary = world.plants.bodies[payload.plant]
	var rule: Dictionary = world.plants.definitions.types[row.definition]
	if row.stage in ["dead", "removed"] or not bool(rule.sapient):
		return Condition.INVALID
	return Condition.READY if row.growth_ms >= rule.mature_ms else Condition.WAIT


func _awaken(payload: Dictionary, context: Dictionary) -> int:
	return Effect.APPLIED if world.plants.awaken(str(payload.plant), str(context.id)) else Effect.INVALID
