class_name SimBodyGeometry
extends RefCounted
## Stateless clearance for centred odd-cell bodies. No position lives here.

const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]


class SearchGeometry extends RefCounted:
	# One synchronous search owns these projections. No cross-step/map cache.
	var walkable: Callable
	var elevation: Callable
	var _walkable: Dictionary[Vector2i, bool] = {}
	var _elevation: Dictionary[Vector2i, int] = {}

	func _init(ground: Callable, height: Callable) -> void:
		walkable = ground
		elevation = height

	func walkable_at(cell: Vector2i) -> bool:
		if not _walkable.has(cell):
			_walkable[cell] = bool(walkable.call(cell))
		return _walkable[cell]

	func elevation_at(cell: Vector2i) -> int:
		if not _elevation.has(cell):
			_elevation[cell] = int(elevation.call(cell))
		return _elevation[cell]


static func valid_size(size: Vector2i) -> bool:
	return size.x > 0 and size.y > 0 and size.x <= 9 and size.y <= 9 and size.x % 2 == 1 and size.y % 2 == 1


static func bounds(anchor: Vector2i, size: Vector2i) -> Rect2i:
	return Rect2i(anchor - Vector2i(size.x >> 1, size.y >> 1), size)


static func cells(anchor: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not valid_size(size):
		return result
	var area: Rect2i = bounds(anchor, size)
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			result.append(Vector2i(x, y))
	return result


static func can_stand(anchor: Vector2i, size: Vector2i, walkable: Callable, elevation: Callable) -> bool:
	if not valid_size(size) or not walkable.is_valid() or not elevation.is_valid():
		return false
	var low: int = SimInventory.MAX_COUNT
	var high: int = -1
	for cell: Vector2i in cells(anchor, size):
		if not bool(walkable.call(cell)):
			return false
		var height: int = int(elevation.call(cell))
		if height < 0:
			return false
		low = mini(low, height)
		high = maxi(high, height)
	return high - low <= 1


static func can_step(anchor: Vector2i, step: Vector2i, size: Vector2i, walkable: Callable, elevation: Callable) -> bool:
	if absi(step.x) > 1 or absi(step.y) > 1 or not can_stand(anchor, size, walkable, elevation) or not can_stand(anchor + step, size, walkable, elevation):
		return false
	for cell: Vector2i in cells(anchor, size):
		if absi(int(elevation.call(cell)) - int(elevation.call(cell + step))) > 1:
			return false
	if step.x != 0 and step.y != 0:
		return can_step(anchor, Vector2i(step.x, 0), size, walkable, elevation) and can_step(anchor, Vector2i(0, step.y), size, walkable, elevation)
	return true


static func find_path(start: Vector2i, goal: Vector2i, size: Vector2i, walkable: Callable, elevation: Callable, radius: int, budget: int, reuse_static_geometry: bool = false) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	# Bound Callables do not retain a RefCounted receiver; keep it in the
	# function scope until the complete BFS (including early returns) finishes.
	var geometry: SearchGeometry
	# Opt in only when both original callbacks are pure/stable for this call.
	# Custom callbacks retain their original evaluation order by default.
	if reuse_static_geometry:
		if not walkable.is_valid() or not elevation.is_valid():
			return empty
		geometry = SearchGeometry.new(walkable, elevation)
		walkable = geometry.walkable_at
		elevation = geometry.elevation_at
	if radius < 1 or budget < 1 or not can_stand(start, size, walkable, elevation) or not can_stand(goal, size, walkable, elevation) or absi(goal.x - start.x) > radius or absi(goal.y - start.y) > radius:
		return empty
	return SimGridNavigation.find_path(start, goal, can_stand.bind(size, walkable, elevation),
		can_step.bind(size, walkable, elevation), radius, budget, false)


static func contact_distance(point: Vector2, center: Vector2, size: Vector2i) -> float:
	var half_size: Vector2 = Vector2(size * TileGrid.TILE_SIZE) * 0.5
	var edge: Vector2 = point.clamp(center - half_size, center + half_size)
	return point.distance_to(edge)
