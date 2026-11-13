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
