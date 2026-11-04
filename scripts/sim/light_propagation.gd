class_name SimLightPropagation
extends RefCounted
## Pure bounded 2D geometry and relative illumination, not energy transport.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const SCALE: int = 10000
const MAX_RADIUS: int = 8


static func valid_definition(value: Variant) -> bool:
	return Shape.keys(value, ["version", "peak_relative", "radius_cells"]) and Shape.count(value.version, 1, 1) and Shape.count(value.peak_relative, 1, SCALE) and Shape.count(value.radius_cells, 1, MAX_RADIUS)


static func emission_peak(peak: int, rate: int, nominal: int) -> int:
	if peak < 0 or peak > SCALE or rate < 0 or nominal < 1:
		return 0
	var value: int = mini(rate, nominal)
	# Exact floor(peak * value / nominal), without overflowing the safe integer
	# range. Remainders stay below nominal, and quotient never exceeds peak.
	var bit: int = 1
	while bit <= (peak >> 1):
		bit <<= 1
	var quotient: int = 0
	var remainder: int = 0
	while bit > 0:
		quotient += quotient
		if remainder >= nominal - remainder:
			remainder -= nominal - remainder
			quotient += 1
		else:
			remainder += remainder
		if (peak & bit) != 0:
			if remainder >= nominal - value:
				remainder -= nominal - value
				quotient += 1
			else:
				remainder += value
		bit >>= 1
	return quotient


static func has_line_of_light(from: Vector2i, to: Vector2i, opaque: Callable) -> bool:
	if not opaque.is_valid():
		return false
	if absi(int(to.x) - int(from.x)) > MAX_RADIUS or absi(int(to.y) - int(from.y)) > MAX_RADIUS:
		return false
	if from == to:
		return true
	if bool(opaque.call(from)):
		return false
	var extent := Vector2i(absi(int(to.x) - int(from.x)), absi(int(to.y) - int(from.y)))
	var step := Vector2i(signi(int(to.x) - int(from.x)), signi(int(to.y) - int(from.y)))
	var crossed := Vector2i.ZERO
	var at: Vector2i = from
	while at != to:
		var x_cross: int = (1 + 2 * crossed.x) * extent.y
		var y_cross: int = (1 + 2 * crossed.y) * extent.x
		if x_cross == y_cross:
			# A zero-width corner is not a passage for either side's light.
			if bool(opaque.call(at + Vector2i(step.x, 0))) or bool(opaque.call(at + Vector2i(0, step.y))):
				return false
			at += step
			crossed += Vector2i.ONE
		elif x_cross < y_cross:
			at.x += step.x
			crossed.x += 1
		else:
			at.y += step.y
			crossed.y += 1
		# The target wall's facing surface receives light; it still blocks the
		# next target behind it. No light ray uses height or furniture collision.
		if at != to and bool(opaque.call(at)):
			return false
	return true


static func contribution(from: Vector2i, to: Vector2i, radius: int, peak: int, opaque: Callable) -> int:
	if radius < 1 or radius > MAX_RADIUS or peak < 0 or peak > SCALE:
		return 0
	# Bound each component before squaring arbitrary external coordinates.
	var dx: int = int(to.x) - int(from.x)
	var dy: int = int(to.y) - int(from.y)
	if absi(dx) >= radius or absi(dy) >= radius:
		return 0
	var squared: int = dx * dx + dy * dy
	var reach: int = radius * radius
	if squared >= reach or not has_line_of_light(from, to, opaque):
		return 0
	@warning_ignore("integer_division")
	return peak * (reach - squared) / reach
