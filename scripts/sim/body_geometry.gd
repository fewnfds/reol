class_name SimBodyGeometry
extends RefCounted
## Stateless clearance for centred odd-cell bodies. No position lives here.

const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]


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


static func find_path(start: Vector2i, goal: Vector2i, size: Vector2i, walkable: Callable, elevation: Callable, radius: int, budget: int) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if radius < 1 or budget < 1 or not can_stand(start, size, walkable, elevation) or not can_stand(goal, size, walkable, elevation) or absi(goal.x - start.x) > radius or absi(goal.y - start.y) > radius:
		return empty
	var queue: Array[Vector2i] = [start]
	var previous: Dictionary = {start: start}
	var index: int = 0
	while index < queue.size() and index < budget:
		var at: Vector2i = queue[index]
		index += 1
		if at == goal:
			var route: Array[Vector2i] = [goal]
			while route.back() != start:
				route.append(previous[route.back()])
			route.reverse()
			return route
		for step: Vector2i in DIRECTIONS:
			var next: Vector2i = at + step
			if previous.has(next) or absi(next.x - start.x) > radius or absi(next.y - start.y) > radius or not can_step(at, step, size, walkable, elevation):
				continue
			previous[next] = at
			queue.append(next)
	return empty


static func contact_distance(point: Vector2, center: Vector2, size: Vector2i) -> float:
	var half_size: Vector2 = Vector2(size * TileGrid.TILE_SIZE) * 0.5
	var edge: Vector2 = point.clamp(center - half_size, center + half_size)
	return point.distance_to(edge)
