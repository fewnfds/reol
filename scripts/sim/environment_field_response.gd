class_name SimEnvironmentFieldResponse
extends RefCounted
## One anchored first-order response over a known constant or linear target
## segment. It projects shared time; it does not own or advance a clock.

const MAX_TIME: int = 9_000_000_000_000_000
const MAX_TAU_MS: int = 86_400_000
const MAX_ABS_VALUE: float = 1.0e12
const MAX_ABS_RATE_PER_MS: float = 2.0e12
const _FLOAT_SPLITTER: float = 134_217_729.0

var _configured: bool = false
var _start_ms: int = 0
var _until_ms: int = 0
var _initial_value: float = 0.0
var _target_value: float = 0.0
var _target_per_ms: float = 0.0
var _tau_ms: int = 1


func configure(start_ms: int, until_ms: int, initial_value: float, target_value: float, target_per_ms: float, tau_ms: int) -> bool:
	if start_ms < 0 or start_ms > MAX_TIME or until_ms < start_ms or until_ms > MAX_TIME or tau_ms < 1 or tau_ms > MAX_TAU_MS:
		return false
	if not is_finite(initial_value) or not is_finite(target_value) or not is_finite(target_per_ms):
		return false
	if absf(initial_value) > MAX_ABS_VALUE or absf(target_value) > MAX_ABS_VALUE or absf(target_per_ms) > MAX_ABS_RATE_PER_MS:
		return false
	# Bounds on both endpoints bound the entire linear target. The response is
	# within the initial/target envelope; its integral is at most 9e27 in size.
	var endpoint: float = target_value + target_per_ms * float(until_ms - start_ms)
	if not is_finite(endpoint) or absf(endpoint) > MAX_ABS_VALUE:
		return false
	_start_ms = start_ms
	_until_ms = until_ms
	_initial_value = initial_value
	_target_value = target_value
	_target_per_ms = target_per_ms
	_tau_ms = tau_ms
	_configured = true
	return true


func sample(at_ms: int) -> Dictionary:
	if not _configured:
		return {"ok": false, "reason": "not_configured"}
	if at_ms < _start_ms or at_ms > _until_ms:
		return {"ok": false, "reason": "time_out_of_range"}
	# Subtract the integer timestamps before converting to float; this retains
	# a one-millisecond interval even near MAX_TIME.
	var elapsed: float = float(at_ms - _start_ms)
	if elapsed == 0.0:
		return {"ok": true, "at_ms": at_ms, "value": _initial_value, "integral": 0.0}
	var tau: float = float(_tau_ms)
	var x: float = elapsed / tau
	var factors: Array[float] = _factors(x)
	var decay: float = factors[0]
	var response: float = factors[1]
	var lag: float = factors[2]
	var integral_lag: float = factors[3]
	var end_weight: float = factors[4]
	var target_change: float = _target_per_ms * elapsed
	var target_end: float = _target_value + target_change
	# This endpoint form avoids cancelling two nearly equal large terms when a
	# long linear target declines to zero. It is algebraically identical to
	# g0+s*(t-tau)+(y0-g0+s*tau)*exp(-t/tau).
	var value: float = _initial_value * decay + target_end * response - _target_per_ms * tau * end_weight
	var integral: float
	if x < 1.0:
		# Preserve the series form where subtracting target area and response
		# would lose the small integral for a short interval.
		integral = _initial_value * tau * response + _target_value * tau * lag + _target_per_ms * tau * tau * integral_lag
	else:
		# Integrating tau*y' = target-y gives the target's trapezoid area plus
		# tau*(initial-value). Unlike separate large ramp terms, this retains
		# the transient when the positive and negative target areas cancel.
		# Recover roundoff from the endpoint product/sums before multiplying by
		# elapsed; otherwise near-opposite endpoints can lose a finite area.
		var target_sum: float = _target_value + target_end
		var endpoint_error: float = _sum_error(_target_value, target_change, target_end) + _product_error(_target_per_ms, elapsed, target_change)
		var target_sum_error: float = _sum_error(_target_value, target_end, target_sum) + endpoint_error
		var half_elapsed: float = elapsed * 0.5
		var area: float = target_sum * half_elapsed
		var area_error: float = _product_error(target_sum, half_elapsed, area) + target_sum_error * half_elapsed
		var transient: float = tau * (_initial_value - value)
		var combined: float = area + transient
		integral = combined + (_sum_error(area, transient, combined) + area_error)
	if not is_finite(value) or not is_finite(integral):
		return {"ok": false, "reason": "non_finite_result"}
	# A convex first-order response cannot leave this envelope. Limit only
	# roundoff outside it; negative values and targets remain negative.
	var lower: float = minf(_initial_value, minf(_target_value, target_end))
	var upper: float = maxf(_initial_value, maxf(_target_value, target_end))
	value = clampf(value, lower, upper)
	return {"ok": true, "at_ms": at_ms, "value": value, "integral": integral}


func to_dict() -> Dictionary:
	if not _configured:
		return {}
	# Persist floats with JSON full_precision=true, as the project's save store
	# does, to preserve the same anchor and future exactly across a JSON roundtrip.
	return {"version": 1, "start_ms": _start_ms, "until_ms": _until_ms,
		"initial_value": _initial_value, "target_value": _target_value,
		"target_per_ms": _target_per_ms, "tau_ms": _tau_ms}


func restore(data: Variant) -> bool:
	var keys: Array[String] = ["version", "start_ms", "until_ms", "initial_value", "target_value", "target_per_ms", "tau_ms"]
	if not data is Dictionary or data.size() != keys.size():
		return false
	for key: String in keys:
		if not data.has(key):
			return false
	# JSON numbers can decode as floats. Accept integral numeric timestamps, but
	# never booleans, fractions, nonfinite numbers, or a lossy int conversion.
	if not _integer(data.version, 1, 1) or not _integer(data.start_ms, 0, MAX_TIME) or not _integer(data.until_ms, 0, MAX_TIME) or not _integer(data.tau_ms, 1, MAX_TAU_MS):
		return false
	if not _finite_number(data.initial_value) or not _finite_number(data.target_value) or not _finite_number(data.target_per_ms):
		return false
	# configure validates the complete candidate before assigning any field.
	return configure(int(data.start_ms), int(data.until_ms), float(data.initial_value), float(data.target_value), float(data.target_per_ms), int(data.tau_ms))


static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	if not _finite_number(value):
		return false
	var number: float = float(value)
	return number >= float(minimum) and number <= float(maximum) and floor(number) == number


static func _sum_error(a: float, b: float, sum: float) -> float:
	# TwoSum residual: recover the part rounded out of a+b.
	var b_virtual: float = sum - a
	return (a - (sum - b_virtual)) + (b - b_virtual)


static func _product_error(a: float, b: float, product: float) -> float:
	# Dekker split for the low part of a double product. Configured endpoint
	# and time bounds keep the split and every intermediate finite.
	var a_split: float = _FLOAT_SPLITTER * a
	var a_high: float = a_split - (a_split - a)
	var a_low: float = a - a_high
	var b_split: float = _FLOAT_SPLITTER * b
	var b_high: float = b_split - (b_split - b)
	var b_low: float = b - b_high
	return ((a_high * b_high - product) + a_high * b_low + a_low * b_high) + a_low * b_low


static func _factors(x: float) -> Array[float]:
	# response = 1-exp(-x), lag = x-response, and integral_lag =
	# x^2/2-lag. For small x, direct subtraction loses the small terms needed
	# by both the response and its integral. Integrate the alternating series
	# term-by-term instead; x < 0.5 and terms through degree 16 are sufficient
	# for double precision here.
	if x < 0.5:
		var term: float = x * x * 0.5
		var lag: float = term
		var integral_lag: float = term * x / 3.0
		for order: int in range(3, 17):
			term *= -x / float(order)
			lag += term
			integral_lag += term * x / float(order + 1)
		var response: float = x - lag
		var end_weight: float = x * response - lag
		return [1.0 - response, response, lag, integral_lag, end_weight]
	var long_decay: float = exp(-x)
	var long_response: float = 1.0 - long_decay
	var long_lag: float = x - long_response
	var long_integral_lag: float = x * x * 0.5 - long_lag
	var long_end_weight: float = 1.0 - (1.0 + x) * long_decay
	return [long_decay, long_response, long_lag, long_integral_lag, long_end_weight]
