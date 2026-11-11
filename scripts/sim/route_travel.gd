class_name SimRouteTravel
extends RefCounted
## One geometric route convention for native work, visitor jobs and travel orders.
## Body dictionary owns the point; routes own only their segment and remainder.


class Timeline extends RefCounted:
	## Disposable arithmetic for an accepted native route. The action still owns
	## its path/cursor; this table never owns world state or commits consequences.
	var points := PackedVector2Array()
	var ends := PackedInt64Array()
	var started_ms: int

	func _init(route: Dictionary, speed: float) -> void:
		started_ms = int(route.segment_started_ms)
		points.append(Vector2(float(route.segment_from[0]), float(route.segment_from[1])))
		var deadline: int = int(route.due_ms)
		for index: int in route.path.size():
			var target: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(route.path[index]))
			if index > 0:
				deadline += maxi(1, ceili(points[-1].distance_to(target) / speed * 1000.0))
			points.append(target)
			ends.append(deadline)

	func leg_at(now: int) -> int:
		# Upper bound: exact vertices belong to the next leg, except the final
		# vertex, which the action owner must consume to perform arrival effects.
		var low: int = 0
		var high: int = ends.size()
		while low < high:
			@warning_ignore("integer_division")
			var middle: int = (low + high) / 2
			if ends[middle] <= now:
				low = middle + 1
			else:
				high = middle
		return mini(low, ends.size() - 1)

	func point_at(now: int) -> Vector2:
		return point_on_leg(now, leg_at(now))

	func point_on_leg(now: int, leg: int) -> Vector2:
		var start: int = started_ms if leg == 0 else ends[leg - 1]
		return points[leg].lerp(points[leg + 1], clampf(float(now - start) / float(ends[leg] - start), 0.0, 1.0))

	func heading_at(now: int, previous: Vector2) -> Vector2:
		return heading_on_leg(now, leg_at(now), previous)

	func heading_on_leg(now: int, leg: int, previous: Vector2) -> Vector2:
		# At an exact vertex, the next segment has not moved yet. Preserve the
		# preceding facing, including a zero-distance centering leg at spawn.
		if leg > 0 and now == ends[leg - 1]:
			leg -= 1
		while leg >= 0:
			var delta: Vector2 = points[leg + 1] - points[leg]
			if not delta.is_zero_approx() and now > (started_ms if leg == 0 else ends[leg - 1]):
				return delta.normalized()
			leg -= 1
		return previous

	func materialize(route: Dictionary, now: int) -> void:
		materialize_leg(route, leg_at(now))

	func materialize_leg(route: Dictionary, leg: int) -> void:
		# A worker may evaluate the immutable timeline; the route owner alone
		# consumes its path, after validating the same route and cursor.
		var consumed: int = ends.size() - route.path.size()
		leg = maxi(consumed, leg)
		if leg <= consumed:
			return
		route.path = route.path.slice(leg - consumed)
		route.segment_started_ms = ends[leg - 1]
		route.segment_from = [points[leg].x, points[leg].y]
		route.due_ms = ends[leg]


static func point(body: Dictionary) -> Vector2:
	return Vector2(float(body.position[0]), float(body.position[1]))


static func put(body: Dictionary, value: Vector2) -> void:
	# Repositioning alone is not an action: spawn/load/placement must not turn
	# a body or manufacture a walking phase from a jump between coordinates.
	body.position = [value.x, value.y]
	var grid: Vector2i = TileGrid.world_to_cell(value)
	body.cell = [grid.x, grid.y]


static func facing(body: Dictionary) -> Vector2:
	var raw: Array = body.facing
	return Vector2(float(raw[0]), float(raw[1]))


static func face(body: Dictionary, direction: Vector2) -> void:
	if direction.is_finite() and not direction.is_zero_approx():
		var heading: Vector2 = direction.normalized()
		body.facing = [heading.x, heading.y]


static func begin_segment(route: Dictionary, body: Dictionary, now: int, speed: float) -> void:
	route["segment_started_ms"] = now
	route["segment_from"] = body.position.duplicate()
	var distance: float = 0.0 if route.path.is_empty() else point(body).distance_to(TileGrid.cell_to_world(cell(route.path[0])))
	route["due_ms"] = now + maxi(1, ceili(distance / speed * 1000.0))


static func project(route: Dictionary, body: Dictionary, now: int) -> void:
	if route.path.is_empty():
		return
	var origin := Vector2(float(route.segment_from[0]), float(route.segment_from[1]))
	var end: Vector2 = TileGrid.cell_to_world(cell(route.path[0]))
	var next: Vector2 = projected_point(route, body, now)
	if not point(body).is_equal_approx(next):
		# The segment direction is stable under fine/batched projections. A
		# normalized difference between successive samples can round differently.
		face(body, end - origin)
	put(body, next)


static func projected_point(route: Dictionary, body: Dictionary, now: int) -> Vector2:
	# Pure evaluation of the already accepted segment, never a new movement.
	if route.path.is_empty():
		return point(body)
	var origin := Vector2(float(route.segment_from[0]), float(route.segment_from[1]))
	var end: Vector2 = TileGrid.cell_to_world(cell(route.path[0]))
	var ratio: float = clampf(float(now - int(route.segment_started_ms)) / float(int(route.due_ms) - int(route.segment_started_ms)), 0, 1)
	return origin.lerp(end, ratio)


static func crossing_ms(route: Dictionary, body: Dictionary, now: int) -> int:
	return crossing_from_cell_ms(route, cell(body.cell), now)


static func crossing_from_cell_ms(route: Dictionary, current: Vector2i, now: int) -> int:
	var deadline: int = int(route.due_ms)
	if route.path.is_empty():
		return deadline
	var origin := Vector2(float(route.segment_from[0]), float(route.segment_from[1]))
	var target_cell: Vector2i = cell(route.path[0])
	var target: Vector2 = TileGrid.cell_to_world(target_cell)
	if target_cell == current:
		return deadline
	var fraction: float = 1.0
	var delta: Vector2 = target - origin
	for axis: int in 2:
		if current[axis] == target_cell[axis] or is_zero_approx(delta[axis]):
			continue
		var edge: float = float(maxi(current[axis], target_cell[axis]) * TileGrid.TILE_SIZE)
		fraction = minf(fraction, (edge - origin[axis]) / delta[axis])
	var duration: int = int(route.due_ms) - int(route.segment_started_ms)
	var crossing: int = int(route.segment_started_ms) + ceili(float(duration) * fraction)
	# floor-based cell ownership crosses right/down ON the edge, left/up only
	# after it. Use the same projection arithmetic as the original body, rather
	# than adding 1ms on every direction (which lets a host slice cross early).
	var projected: Vector2 = origin.lerp(target, clampf(float(crossing - int(route.segment_started_ms)) / duration, 0.0, 1.0))
	if TileGrid.world_to_cell(projected) == current:
		crossing += 1
	return mini(deadline, crossing) if crossing > now else deadline


static func cell(raw: Array) -> Vector2i:
	return Vector2i(int(raw[0]), int(raw[1]))


static func valid_segment(route: Dictionary, body: Dictionary, now: int, speed: float) -> bool:
	if not SimLocalMotion._vector(route.get("segment_from")) or not ReolGameClock._integer(route.get("segment_started_ms")) or not ReolGameClock._integer(route.get("due_ms")) or int(route.segment_started_ms) > now or int(route.due_ms) <= now or not route.get("path") is Array:
		return false
	var origin := Vector2(float(route.segment_from[0]), float(route.segment_from[1]))
	var target: Vector2 = origin if route.path.is_empty() else TileGrid.cell_to_world(cell(route.path[0]))
	var origin_cell: Vector2i = TileGrid.world_to_cell(origin)
	var target_cell: Vector2i = TileGrid.world_to_cell(target)
	if absi(origin_cell.x - target_cell.x) > 1 or absi(origin_cell.y - target_cell.y) > 1:
		return false
	var duration: int = int(route.due_ms) - int(route.segment_started_ms)
	var expected: int = maxi(1, ceili(origin.distance_to(target) / speed * 1000.0))
	if duration > expected:
		return false
	var fraction: float = float(now - int(route.segment_started_ms)) / duration
	return point(body).is_equal_approx(origin.lerp(target, fraction))


static func next_boundary(route: Dictionary, body: Dictionary, now: int, step: Callable) -> int:
	# A blocked leg wakes at a canonical world boundary, never at whichever
	# arbitrary host slice next happens to project this body.
	if not leg_open(route, body, step):
		return now + 1
	return crossing_ms(route, body, now)


static func leg_open(route: Dictionary, body: Dictionary, step: Callable) -> bool:
	if route.path.is_empty() or not step.is_valid():
		return true
	var from: Vector2i = cell(body.cell)
	var to: Vector2i = cell(route.path[0])
	return bool(step.call(from, to - from))


static func repair(sim: VillageSimulation, actor: String, route: Dictionary, now: int, destination: Array = [], speed: float = -1.0, clearance: Callable = Callable()) -> bool:
	# Domains keep target validity, reservations, phase and effects. Repair only
	# replaces an invalid geometric remainder, from the real continuous point.
	var body: Dictionary = sim.synchronize_actor(actor)
	var step: Callable = clearance if clearance.is_valid() else sim._step_validator
	if leg_open(route, body, step):
		return true
	var goal: Array = destination if not destination.is_empty() else route.path.back()
	var from: Vector2i = cell(body.cell)
	var target: Vector2i = cell(goal)
	var path: Array[Vector2i] = sim.find_path(from, target)
	if path.is_empty() and from != target:
		return false
	var encoded: Array = []
	var previous: Vector2i = from
	for next: Vector2i in path:
		if next != from:
			if step.is_valid() and not bool(step.call(previous, next - previous)):
				return false
			encoded.append([next.x, next.y])
			previous = next
	if not point(body).is_equal_approx(TileGrid.cell_to_world(from)):
		encoded.push_front([from.x, from.y])
	route.path = encoded
	sim.invalidate_native_route_completion(actor)
	begin_segment(route, body, now, float(sim.motion_rules.motion.speed) if speed < 0.0 else speed)
	if is_same(sim.actor_state(actor).active, route):
		sim.accept_native_route(actor, route)
	return true
