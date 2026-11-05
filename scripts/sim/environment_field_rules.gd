class_name SimEnvironmentFieldRules
extends RefCounted
## Pure prototype field geometry and net-grade temperature mapping. This does
## not own sources, physical temperature, time, or the existing thermal model.

const SCALE: int = 1_000_000
const GRADE_SCALE: int = 1_000
const ABSOLUTE_ZERO_MILLI: int = -273_150
const MAX_RADIUS: int = 256
const MAX_NEUTRAL_MILLI: int = 1_000_000_000
const MAX_GRADE_MILLI: int = 1_000_000_000

# Default balance prototype only; later versioned definitions must replace it.
# Cold values are the drop from a 20 C neutral (span to zero K = 293150 mC).
const _GRADE_KNOTS: Array[int] = [0, 1_000, 3_000, 5_000, 8_000, 10_000]
const _HEAT_RISE_MILLI: Array[int] = [0, 20_000, 180_000, 980_000, 4_980_000, 9_980_000]
const _COLD_REFERENCE_DROP_MILLI: Array[int] = [0, 20_000, 60_000, 140_000, 270_000, 293_150]
const _COLD_REFERENCE_SPAN_MILLI: int = 293_150


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func kernel(offset: Vector2i, radius: int) -> Dictionary:
	if radius < 1 or radius > MAX_RADIUS:
		return _failure("radius_out_of_range")
	# Reject exterior coordinates before squaring arbitrary Vector2i values.
	if offset.x <= -radius or offset.x >= radius or offset.y <= -radius or offset.y >= radius:
		return {"ok": true, "weight": 0}
	var squared: int = offset.x * offset.x + offset.y * offset.y
	if squared >= radius * radius:
		return {"ok": true, "weight": 0}
	if squared == 0:
		return {"ok": true, "weight": SCALE}

	# Find floor(sqrt(squared) * SCALE / radius) without floating-point drift.
	# All products stay below 4 * 256^2 * SCALE^2, safely within int64.
	var distance_squared_scaled: int = squared * SCALE * SCALE
	var low: int = 0
	var high: int = SCALE
	while low < high:
		var mid: int = (low + high + 1) >> 1
		var trial: int = radius * mid
		if trial * trial <= distance_squared_scaled:
			low = mid
		else:
			high = mid - 1
	# Round the resulting weight to nearest millionth, ties upward. A distance
	# exactly halfway must therefore round down before subtraction from SCALE.
	var halfway: int = radius * (2 * low + 1)
	if 4 * distance_squared_scaled > halfway * halfway:
		low += 1
	return {"ok": true, "weight": SCALE - low}


static func temperature(neutral_milli: int, net_grade_milli: int) -> Dictionary:
	if neutral_milli <= ABSOLUTE_ZERO_MILLI or neutral_milli > MAX_NEUTRAL_MILLI:
		return _failure("neutral_out_of_range")
	if net_grade_milli < -MAX_GRADE_MILLI or net_grade_milli > MAX_GRADE_MILLI:
		return _failure("grade_out_of_range")
	if net_grade_milli >= 0:
		return {"ok": true, "temperature_milli": neutral_milli + _heat_rise(net_grade_milli)}
	var cold_grade: int = -net_grade_milli
	if cold_grade >= _GRADE_KNOTS[-1]:
		return {"ok": true, "temperature_milli": ABSOLUTE_ZERO_MILLI}
	return {"ok": true, "temperature_milli": _cold_temperature(neutral_milli, cold_grade)}


static func thermal_target(neutral_milli: int, hot_grade_milli: int, cold_grade_milli: int, multiplier: int = SCALE) -> Dictionary:
	if hot_grade_milli < 0 or hot_grade_milli > MAX_GRADE_MILLI or cold_grade_milli < 0 or cold_grade_milli > MAX_GRADE_MILLI:
		return _failure("source_grade_out_of_range")
	# This common attenuation accepts 0..1; the tide rule has its own narrower
	# 0.98..1 interval. Zero also permits complete insulation at this layer.
	if multiplier < 0 or multiplier > SCALE:
		return _failure("multiplier_out_of_range")
	var net_grade: int = hot_grade_milli - cold_grade_milli
	var magnitude: int = _round_nonnegative(absi(net_grade) * multiplier, SCALE)
	var scaled_grade: int = -magnitude if net_grade < 0 else magnitude
	return temperature(neutral_milli, scaled_grade)


static func _round_nonnegative(numerator: int, denominator: int) -> int:
	# Trusted internal bounded values only; halfway rounds upward.
	@warning_ignore("integer_division")
	return (numerator + (denominator >> 1)) / denominator


static func _heat_rise(grade: int) -> int:
	for index: int in range(1, _GRADE_KNOTS.size()):
		if grade <= _GRADE_KNOTS[index]:
			var width: int = _GRADE_KNOTS[index] - _GRADE_KNOTS[index - 1]
			var offset: int = grade - _GRADE_KNOTS[index - 1]
			var rise: int = _HEAT_RISE_MILLI[index] - _HEAT_RISE_MILLI[index - 1]
			return _HEAT_RISE_MILLI[index - 1] + _round_nonnegative(rise * offset, width)
	# Beyond level 10, extend the last segment's slope up to the explicit
	# grade bound; the largest product is below 5e15 and stays inside int64.
	var last: int = _GRADE_KNOTS.size() - 1
	var extension_width: int = _GRADE_KNOTS[last] - _GRADE_KNOTS[last - 1]
	var extension_rise: int = _HEAT_RISE_MILLI[last] - _HEAT_RISE_MILLI[last - 1]
	return _HEAT_RISE_MILLI[last] + _round_nonnegative(extension_rise * (grade - _GRADE_KNOTS[last]), extension_width)


static func _cold_temperature(neutral_milli: int, grade: int) -> int:
	for index: int in range(1, _GRADE_KNOTS.size()):
		if grade <= _GRADE_KNOTS[index]:
			var width: int = _GRADE_KNOTS[index] - _GRADE_KNOTS[index - 1]
			var offset: int = grade - _GRADE_KNOTS[index - 1]
			var low_drop: int = _COLD_REFERENCE_DROP_MILLI[index - 1]
			var increment: int = _COLD_REFERENCE_DROP_MILLI[index] - low_drop
			var weighted_drop: int = low_drop * width + increment * offset
			var available_span: int = neutral_milli - ABSOLUTE_ZERO_MILLI
			# Round only after scaling the interpolated ratio to this neutral; the
			# largest numerator is under 8.8e17 with the stated bounds.
			var drop: int = _round_nonnegative(available_span * weighted_drop, _COLD_REFERENCE_SPAN_MILLI * width)
			return neutral_milli - drop
	# This private helper is only reached for 0 < grade < 10 levels.
	return ABSOLUTE_ZERO_MILLI
