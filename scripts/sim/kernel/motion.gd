extends RefCounted
## A step's sparse timed polyline. Normal straight motion needs no knots.

static func sample(knots: PackedVector3Array, alpha: float) -> Vector2:
	for index: int in range(1, knots.size()):
		var b: Vector3 = knots[index]
		if alpha <= b.z:
			var a: Vector3 = knots[index - 1]
			return Vector2(a.x, a.y).lerp(Vector2(b.x, b.y), clampf((alpha - a.z) / maxf(0.000001, b.z - a.z), 0.0, 1.0))
	var last: Vector3 = knots[-1]
	return Vector2(last.x, last.y)


static func hit_fraction(from: Vector2, to: Vector2, before: Vector2, current: Vector2, radius: float, knots: PackedVector3Array = PackedVector3Array()) -> float:
	if knots.is_empty():
		return _hit(from - before, to - current, radius)
	for index: int in range(1, knots.size()):
		var a: Vector3 = knots[index - 1]
		var b: Vector3 = knots[index]
		if b.z <= a.z: continue
		var fraction: float = _hit(from.lerp(to, a.z) - Vector2(a.x, a.y), from.lerp(to, b.z) - Vector2(b.x, b.y), radius)
		if fraction >= 0:
			return lerpf(a.z, b.z, fraction)
	return -1.0


static func _hit(from: Vector2, to: Vector2, radius: float) -> float:
	return 0.0 if from.length_squared() <= radius * radius else Geometry2D.segment_intersects_circle(from, to, Vector2.ZERO, radius)


static func capsule_hit(from: Vector2, to: Vector2, a: Vector2, b: Vector2, radius: float) -> float:
	var length: float = a.distance_to(b)
	if length < 0.000001: return _hit(from - a, to - a, radius)
	var axis: Vector2 = (b - a) / length
	var normal := Vector2(-axis.y, axis.x)
	var p := Vector2((from - a).dot(axis), (from - a).dot(normal))
	var q := Vector2((to - a).dot(axis), (to - a).dot(normal))
	var first: float = -1.0
	for endpoint: Vector2 in [Vector2.ZERO, Vector2(length, 0)]:
		var hit: float = _hit(p - endpoint, q - endpoint, radius)
		if hit >= 0 and (first < 0 or hit < first): first = hit
	var low: float = 0.0
	var high: float = 1.0
	var delta: Vector2 = q - p
	for index: int in 2:
		var minimum: float = 0.0 if index == 0 else -radius
		var maximum: float = length if index == 0 else radius
		if absf(delta[index]) < 0.000001:
			if p[index] < minimum or p[index] > maximum: return first
		else:
			var enter: float = (minimum - p[index]) / delta[index]
			var leave: float = (maximum - p[index]) / delta[index]
			low = maxf(low, minf(enter, leave))
			high = minf(high, maxf(enter, leave))
			if low > high: return first
	if low <= high and (first < 0 or low < first): first = low
	return first


static func polygon_hit(from: Vector2, to: Vector2, polygon: PackedVector2Array, radius: float) -> float:
	if Geometry2D.is_point_in_polygon(from, polygon): return 0.0
	if from.is_equal_approx(to):
		for index: int in polygon.size():
			if from.distance_squared_to(Geometry2D.get_closest_point_to_segment(from, polygon[index], polygon[(index + 1) % polygon.size()])) <= radius * radius: return 0.0
		return -1.0
	var first: float = -1.0
	for index: int in polygon.size():
		var hit: float = capsule_hit(from, to, polygon[index], polygon[(index + 1) % polygon.size()], radius)
		if hit >= 0 and (first < 0 or hit < first): first = hit
	return first


static func at(before: Vector2, current: Vector2, knots: PackedVector3Array, alpha: float) -> Vector2:
	return before.lerp(current, alpha) if knots.is_empty() else sample(knots, alpha)


static func shape_hit(source_before: Vector2, source: Vector2, source_knots: PackedVector3Array,
		before: Vector2, current: Vector2, knots: PackedVector3Array, polygon: PackedVector2Array, radius: float) -> float:
	# A turning or sliding body is a polyline, not the chord between its endpoints.
	if source_knots.is_empty() and knots.is_empty(): return polygon_hit(before - source_before, current - source, polygon, radius)
	var times: Array[float] = [0.0, 1.0]
	for path: PackedVector3Array in [source_knots, knots]:
		for point: Vector3 in path:
			if point.z > 0.0 and point.z < 1.0: times.append(point.z)
	times.sort()
	for index: int in range(1, times.size()):
		var low: float = times[index - 1]
		var high: float = times[index]
		if high <= low: continue
		var a: Vector2 = at(before, current, knots, low) - at(source_before, source, source_knots, low)
		var b: Vector2 = at(before, current, knots, high) - at(source_before, source, source_knots, high)
		var fraction: float = polygon_hit(a, b, polygon, radius)
		if fraction >= 0: return lerpf(low, high, fraction)
	return -1.0


static func wall_hit(terrain: RefCounted, from: Vector2, to: Vector2, radius: float) -> Dictionary:
	var first: float = -1.0
	var tile: int = -1
	var visited: Dictionary = {}
	var padding: int = ceili(radius)
	for center: int in terrain.trace_cells(from, to):
		var cell: Vector2i = terrain.cell(center)
		for y: int in range(cell.y - padding, cell.y + padding + 1):
			for x: int in range(cell.x - padding, cell.x + padding + 1):
				if x < 0 or y < 0 or x >= terrain.SIZE or y >= terrain.SIZE: continue
				var key: int = terrain.index(Vector2i(x, y))
				if visited.has(key) or terrain.blocked[key] == 0: continue
				visited[key] = true
				var polygon := PackedVector2Array([Vector2(x, y), Vector2(x + 1, y), Vector2(x + 1, y + 1), Vector2(x, y + 1)])
				var hit: float = polygon_hit(from, to, polygon, radius)
				if hit >= 0 and (first < 0 or hit < first):
					first = hit
					tile = key
	return {"fraction": first, "tile": tile}
