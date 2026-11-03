class_name SimRouteTravel
extends RefCounted
## One geometric route convention for native work, visitor jobs and travel orders.
## Body dictionary owns the point; routes own only their segment and remainder.


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
	var ratio: float = clampf(float(now - int(route.segment_started_ms)) / float(int(route.due_ms) - int(route.segment_started_ms)), 0, 1)
	var next: Vector2 = origin.lerp(end, ratio)
	if not point(body).is_equal_approx(next):
		# The segment direction is stable under fine/batched projections. A
		# normalized difference between successive samples can round differently.
		face(body, end - origin)
	put(body, next)


static func crossing_ms(route: Dictionary, body: Dictionary, now: int) -> int:
	var deadline: int = int(route.due_ms)
	if route.path.is_empty():
		return deadline
	var origin := Vector2(float(route.segment_from[0]), float(route.segment_from[1]))
	var target_cell: Vector2i = cell(route.path[0])
	var target: Vector2 = TileGrid.cell_to_world(target_cell)
	var current: Vector2i = cell(body.cell)
	if target_cell == current:
		return deadline
	var fraction: float = 1.0
	var delta: Vector2 = target - origin
	for axis: int in 2:
		if current[axis] == target_cell[axis] or is_zero_approx(delta[axis]):
			continue
		var edge: float = float(maxi(current[axis], target_cell[axis]) * TileGrid.TILE_SIZE)
		fraction = minf(fraction, (edge - origin[axis]) / delta[axis])
	var crossing: int = int(route.segment_started_ms) + ceili(float(int(route.due_ms) - int(route.segment_started_ms)) * fraction) + 1
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
