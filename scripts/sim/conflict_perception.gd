extends RefCounted
## One bounded spatial recollection per participant. Current cues are sampled
## before decisions; they are not world knowledge or the player's fog of war.

const Space = preload("res://scripts/sim/conflict_space.gd")


static func can_see(domain: RefCounted, observer: String, position: Vector2, at_level: int) -> bool:
	var body: Dictionary = domain.body(observer)
	if body.is_empty() or not bool(body.alive):
		return false
	var from: Vector2 = SimRouteTravel.point(body)
	return Space.level(domain.world, from) == at_level and from.distance_to(position) <= float(domain.rules.sight_radius) and Space.clear_segment(domain.world, from, position, at_level)


static func refresh(domain: RefCounted, row: Dictionary) -> void:
	for actor: String in row.people:
		var other: String = str(row.defender) if actor == row.initiator else str(row.initiator)
		var position: Vector2 = SimRouteTravel.point(domain.body(other))
		var at_level: int = Space.level(domain.world, position)
		if can_see(domain, actor, position, at_level):
			row.people[actor].sight = {"at_ms": domain.world.elapsed_ms, "observer_position": _point(SimRouteTravel.point(domain.body(actor))), "position": _point(position), "level": at_level}
		elif not row.people[actor].sight.is_empty() and domain.world.elapsed_ms - int(row.people[actor].sight.at_ms) > int(domain.rules.last_seen_ms):
			row.people[actor].sight = {}


static func cues(domain: RefCounted, row: Dictionary, actor: String) -> Dictionary:
	var target: String = str(row.defender) if actor == row.initiator else str(row.initiator)
	var point: Vector2 = SimRouteTravel.point(domain.body(actor))
	var target_point: Vector2 = SimRouteTravel.point(domain.body(target))
	var visible: bool = can_see(domain, actor, target_point, Space.level(domain.world, target_point))
	var result: Dictionary = {"visible": visible, "target": _point(target_point) if visible else [], "danger": []}
	# Looking at a visible opponent is the only route to their current windup.
	var action_id: String = str(row.people[target].action) if visible else ""
	if not action_id.is_empty():
		var action: Dictionary = domain.actions[action_id]
		if action.status == "active" and domain.world.elapsed_ms < int(action.effect_ms):
			if action.method == "sword" and Space.in_fan(target_point, point, _vector(action.direction), float(domain.rules.methods.sword.reach), float(domain.rules.methods.sword.half_angle_degrees)):
				result.danger = _point(target_point)
			elif action.method == "qi_bolt" and _toward(domain, target_point, point, _vector(action.direction), float(domain.rules.methods.qi_bolt.reach)):
				result.danger = _point(target_point)
	# A nearby stray projectile is a threat regardless of its encounter owner.
	# Own emissions, receding shots and shots without enough range are ignored.
	for id: String in domain.world._sorted_keys(domain.projectiles):
		var shot: Dictionary = domain.projectiles[id]
		var origin: Vector2 = _vector(shot.position)
		if shot.actor == actor or not can_see(domain, actor, origin, int(shot.level)):
			continue
		var remaining: float = float(domain.rules.methods.qi_bolt.reach) - float(shot.travelled)
		if _toward(domain, origin, point, _vector(shot.direction), remaining) and Space.clear_segment(domain.world, origin, point, int(shot.level)):
			if result.danger.is_empty() or point.distance_squared_to(origin) < point.distance_squared_to(_vector(result.danger)):
				result.danger = _point(origin)
	return result


static func _toward(domain: RefCounted, origin: Vector2, point: Vector2, direction: Vector2, remaining: float) -> bool:
	var along: float = (point - origin).dot(direction)
	return along > 0.0 and along <= remaining and Space.segment_distance(origin, origin + direction * remaining, point) <= float(domain.rules.projectile_radius) + float(domain.rules.threat_margin_px)


static func _point(value: Vector2) -> Array:
	return [value.x, value.y]


static func _vector(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
