extends RefCounted
## Continuous response is checked against closed examples and numerical
## quadrature, independently of a live world or a frame-by-frame update.

const Response = preload("res://scripts/sim/environment_field_response.gd")
const MAX_INTEGER: int = 9223372036854775807
const MIN_INTEGER: int = -9223372036854775807 - 1


func run(runner: Object) -> void:
	_constant_targets(runner)
	_linear_target_and_integral(runner)
	_read_order_split_and_json(runner)
	_small_steps_and_large_time(runner)
	_long_opposite_targets(runner)
	_bounded_envelope(runner)
	_atomic_rejection(runner)
	print("SCENARIO environmental response: constant and linear targets, stable short-step and long-horizon integrals, ordered reads, exact JSON future and atomic rejection")


func _near(runner: Object, actual: float, expected: float, tolerance: float, label: String) -> void:
	runner.assert_true(is_finite(actual) and absf(actual - expected) <= tolerance, "%s: expected %s ± %s, got %s" % [label, str(expected), str(tolerance), str(actual)])


func _constant_targets(runner: Object) -> void:
	var cold := Response.new()
	runner.assert_true(cold.configure(0, 10_000, 100.0, 20.0, 0.0, 1_000), "a constant cooling segment configures")
	runner.assert_eq(cold.sample(0), {"ok": true, "at_ms": 0, "value": 100.0, "integral": 0.0}, "the anchor is the exact initial value and zero integral")
	var after_one_tau: Dictionary = cold.sample(1_000)
	_near(runner, float(after_one_tau.value), 20.0 + 80.0 * exp(-1.0), 1.0e-11, "cooling at one tau follows the exact exponential")
	_near(runner, float(after_one_tau.integral), 20_000.0 + 80_000.0 * (1.0 - exp(-1.0)), 1.0e-7, "constant-target integral includes both target and transient")
	var after_five_tau: Dictionary = cold.sample(5_000)
	runner.assert_true(float(after_five_tau.value) < float(after_one_tau.value) and float(after_five_tau.value) > 20.0, "cooling approaches its target without crossing it")
	var warm := Response.new()
	runner.assert_true(warm.configure(0, 10_000, -500.0, -450.0, 0.0, 1_000), "negative targets and initial values remain legal")
	var warmed: Dictionary = warm.sample(1_000)
	_near(runner, float(warmed.value), -450.0 - 50.0 * exp(-1.0), 1.0e-11, "warming retains a negative temperature without clipping")
	_near(runner, float(warmed.integral), -450_000.0 - 50_000.0 * (1.0 - exp(-1.0)), 1.0e-7, "negative values produce a negative signed integral")
	var settled := Response.new()
	runner.assert_true(settled.configure(7, 1007, -23.5, -23.5, 0.0, 200), "an already settled target configures")
	_near(runner, float(settled.sample(1007).value), -23.5, 1.0e-12, "equal initial and target values stay fixed")
	_near(runner, float(settled.sample(1007).integral), -23_500.0, 1.0e-7, "a settled value integrates over the whole interval")


func _quadrature_value(initial: float, target: float, slope: float, elapsed: float, tau: float) -> float:
	# Independent Simpson integration of exp(-(t-u)/tau)*target(u)/tau.
	var divisions: int = 1000
	var step: float = elapsed / float(divisions)
	var total: float = 0.0
	for index: int in range(divisions + 1):
		var point: float = float(index) * step
		var coefficient: float = 1.0 if index == 0 or index == divisions else (4.0 if index % 2 == 1 else 2.0)
		total += coefficient * exp(-(elapsed - point) / tau) * (target + slope * point) / tau
	return initial * exp(-elapsed / tau) + step * total / 3.0


func _linear_target_and_integral(runner: Object) -> void:
	var ramp := Response.new()
	runner.assert_true(ramp.configure(500, 5_500, 30.0, -10.0, 0.02, 2_000), "an increasing linear target configures")
	for elapsed: int in [1, 5, 200, 999, 1_000, 2_000, 3_000, 5_000]:
		var query: Dictionary = ramp.sample(500 + elapsed)
		var expected: float = _quadrature_value(30.0, -10.0, 0.02, float(elapsed), 2_000.0)
		_near(runner, float(query.value), expected, 1.0e-8, "linear target agrees with independent exponential-kernel quadrature")
		# Integrating tau*y' = target-y gives this independent integral identity.
		var target_area: float = -10.0 * float(elapsed) + 0.01 * float(elapsed) * float(elapsed)
		var expected_integral: float = target_area - 2_000.0 * (expected - 30.0)
		_near(runner, float(query.integral), expected_integral, 1.0e-5, "linear-target integral agrees with the integrated response equation")
	var falling := Response.new()
	runner.assert_true(falling.configure(0, 1_000, 0.0, 0.0, -0.01, 1_000), "a falling target from equilibrium configures")
	var result: Dictionary = falling.sample(1_000)
	_near(runner, float(result.value), -10.0 * exp(-1.0), 1.0e-11, "falling linear target retains its direction")
	_near(runner, float(result.integral), -0.01 * (500_000.0 - 1_000_000.0 + 1_000_000.0 * (1.0 - exp(-1.0))), 1.0e-7, "falling linear target integrates its continuous trajectory")


func _read_order_split_and_json(runner: Object) -> void:
	var response := Response.new()
	runner.assert_true(response.configure(1_000, 10_000, 123.4567891234567, 238.12345678912345, -0.00001234567890123456, 2_500), "a fractional anchor configures")
	var before: Dictionary = response.to_dict()
	var final_query: Dictionary = response.sample(10_000)
	response.sample(7_000)
	response.sample(1_001)
	response.sample(9_500)
	runner.assert_eq(response.sample(10_000), final_query, "read order does not change the future value or integral")
	runner.assert_eq(response.to_dict(), before, "sampling does not advance or otherwise edit the anchor")
	var resumed := Response.new()
	var saved: Variant = JSON.parse_string(JSON.stringify(before, "", true, true))
	runner.assert_true(resumed.restore(saved), "full-precision JSON restores a complete v1 candidate")
	for at_ms: int in [1_000, 1_001, 5_500, 9_999, 10_000]:
		runner.assert_eq(resumed.sample(at_ms), response.sample(at_ms), "JSON recovery retains the identical anchored future")

	# A real boundary creates a new anchor; summing segment integrals must
	# reproduce the unsplit analytic curve to floating-point precision.
	var cut: int = 7_000
	var first: Dictionary = response.sample(cut)
	var next_target: float = 238.12345678912345 - 0.00001234567890123456 * float(cut - 1_000)
	var second := Response.new()
	runner.assert_true(second.configure(cut, 10_000, float(first.value), next_target, -0.00001234567890123456, 2_500), "a known linear target continues from the real boundary")
	var tail: Dictionary = second.sample(10_000)
	_near(runner, float(tail.value), float(final_query.value), 1.0e-10, "splitting at a known boundary preserves the future value")
	_near(runner, float(first.integral) + float(tail.integral), float(final_query.integral), 1.0e-6, "split segment integrals reproduce the entire interval")


func _small_steps_and_large_time(runner: Object) -> void:
	var start: int = Response.MAX_TIME - 10
	var tiny := Response.new()
	runner.assert_true(tiny.configure(start, Response.MAX_TIME, 0.0, 1.0, 0.0, Response.MAX_TAU_MS), "one-millisecond samples are legal at a very large absolute time")
	var query: Dictionary = tiny.sample(start + 1)
	var tau: float = float(Response.MAX_TAU_MS)
	var expected_value: float = 1.0 / tau - 1.0 / (2.0 * tau * tau)
	var expected_integral: float = 1.0 / (2.0 * tau) - 1.0 / (6.0 * tau * tau)
	_near(runner, float(query.value), expected_value, 1.0e-20, "small-step response retains the first two independent series terms")
	_near(runner, float(query.integral), expected_integral, 1.0e-20, "small-step integral retains its quadratic leading term")
	var reloaded := Response.new()
	var snapshot: Variant = JSON.parse_string(JSON.stringify(tiny.to_dict(), "", true, true))
	runner.assert_true(reloaded.restore(snapshot), "the high-time anchor survives full-precision JSON")
	runner.assert_eq(reloaded.sample(start + 1), query, "high-time JSON recovery retains the exact one-millisecond future")
	var ramp := Response.new()
	runner.assert_true(ramp.configure(start, Response.MAX_TIME, 0.0, 0.0, 1.0, Response.MAX_TAU_MS), "small-step rising target configures")
	var ramped: Dictionary = ramp.sample(start + 1)
	_near(runner, float(ramped.value), 1.0 / (2.0 * tau) - 1.0 / (6.0 * tau * tau), 1.0e-20, "small ramp keeps the quadratic response term")
	_near(runner, float(ramped.integral), 1.0 / (6.0 * tau) - 1.0 / (24.0 * tau * tau), 1.0e-20, "small ramp keeps the cubic integral term")

	var horizon: int = 1_000_000_000_000_000
	var transient := Response.new()
	runner.assert_true(transient.configure(0, horizon, 1.0e12, 0.0, 0.0, 1), "a long segment with a finite transient configures")
	_near(runner, float(transient.sample(horizon).integral), 1.0e12, 1.0e-3, "long-horizon integral does not cancel away the initial transient")
	var declining := Response.new()
	runner.assert_true(declining.configure(0, horizon, 0.0, 1.0e12, -0.001, 1), "a very long bounded ramp to zero configures")
	_near(runner, float(declining.sample(horizon).value), 0.001, 1.0e-12, "long ramp retains its small endpoint lag without large-number cancellation")


func _long_opposite_targets(runner: Object) -> void:
	# duration = 3 * 2^51; the first slope is exactly -2^-51. Its target
	# runs from 1.5 to -1.5, so the target area is zero and the response
	# retains the roughly 1.5 value-ms transient at tau=1.
	var duration: int = 6_755_399_441_055_744
	var slope_magnitude: float = 4.440892098500626e-16
	var adjustment: float = 9.860761315262648e-32 # 2^-103
	for direction: int in [-1, 1]:
		for slope_adjustment: float in [0.0, adjustment]:
			var response := Response.new()
			var target: float = float(direction) * 1.5
			var slope: float = float(direction) * (-slope_magnitude + slope_adjustment)
			runner.assert_true(response.configure(0, duration, 0.0, target, slope, 1), "long opposite-signed targets configure")
			var result: Dictionary = response.sample(duration)
			# The adjusted exact slope adds a target trapezoid area of 9/4;
			# rounding its endpoint before the area calculation loses part of it.
			var expected: float = float(direction) * (1.5 + (2.25 if slope_adjustment != 0.0 else 0.0))
			_near(runner, float(result.get("integral", INF)), expected, 1.0e-12, "opposite targets retain the finite transient and near-cancelling target area")
			_near(runner, float(result.get("value", INF)), -target, 1.0e-12, "long endpoint keeps its expected sign and magnitude")
			var resumed := Response.new()
			var saved: Variant = JSON.parse_string(JSON.stringify(response.to_dict(), "", true, true))
			runner.assert_true(resumed.restore(saved), "long opposite-target segment survives full-precision JSON")
			runner.assert_eq(resumed.sample(duration), result, "restoring either sign retains the same long-interval integral")


func _bounded_envelope(runner: Object) -> void:
	var ramps: Array = [
		[-50.0, -100.0, 0.2],
		[50.0, 100.0, -0.2],
		[-1.0e12, 1.0e12, -2.0e9],
		[1.0e12, -1.0e12, 2.0e9],
	]
	for row: Array in ramps:
		var initial: float = float(row[0])
		var target: float = float(row[1])
		var slope: float = float(row[2])
		var response := Response.new()
		runner.assert_true(response.configure(0, 1_000, initial, target, slope, 87), "bounded rising and falling target segments configure")
		for at_ms: int in [0, 1, 9, 87, 250, 500, 999, 1_000]:
			var endpoint: float = target + slope * float(at_ms)
			var lower: float = minf(initial, minf(target, endpoint))
			var upper: float = maxf(initial, maxf(target, endpoint))
			var result: Dictionary = response.sample(at_ms)
			runner.assert_true(bool(result.ok) and float(result.value) >= lower and float(result.value) <= upper, "sample remains inside the initial and actual target envelope")
	var instantaneous := Response.new()
	runner.assert_true(instantaneous.configure(5, 5, -7.0, -9.0, 1.0, 1), "a zero-length segment is an admissible boundary")
	runner.assert_eq(instantaneous.sample(5), {"ok": true, "at_ms": 5, "value": -7.0, "integral": 0.0}, "a zero-length segment preserves the initial value")


func _atomic_rejection(runner: Object) -> void:
	var response := Response.new()
	runner.assert_eq(response.sample(0), {"ok": false, "reason": "not_configured"}, "unconfigured response cannot invent a sample")
	runner.assert_eq(response.to_dict(), {}, "unconfigured response cannot export a partial candidate")
	runner.assert_true(response.configure(10, 1_010, 3.25, 12.75, -0.005, 500), "an initial valid response configures")
	var original: Dictionary = response.to_dict()
	var original_future: Dictionary = response.sample(500)
	for at_ms: int in [MIN_INTEGER, 9, 1_011, MAX_INTEGER]:
		runner.assert_eq(response.sample(at_ms), {"ok": false, "reason": "time_out_of_range"}, "samples outside the explicitly known segment fail")
	runner.assert_true(not response.configure(0, 1, 0.0, 1.0e12, 1.0, 1), "a linear endpoint outside the permitted range is rejected")
	runner.assert_true(not response.configure(0, 1, NAN, 0.0, 0.0, 1), "configure rejects nonfinite initial values")
	runner.assert_true(not response.configure(0, 1, 0.0, 0.0, INF, 1), "configure rejects nonfinite slopes")
	runner.assert_eq(response.to_dict(), original, "failed configure calls leave the original state unchanged")
	var candidates: Array = [null, [], {}, "candidate"]
	var wrong_version: Dictionary = original.duplicate(true)
	wrong_version.version = 2
	candidates.append(wrong_version)
	var fractional_version: Dictionary = original.duplicate(true)
	fractional_version.version = 1.5
	candidates.append(fractional_version)
	var extra: Dictionary = original.duplicate(true)
	extra.extra = 1
	candidates.append(extra)
	var missing: Dictionary = original.duplicate(true)
	missing.erase("target_per_ms")
	candidates.append(missing)
	for test: Array in [
		["start_ms", -1], ["start_ms", 10.5], ["start_ms", true], ["until_ms", 9],
		["until_ms", Response.MAX_TIME + 1], ["tau_ms", 0], ["tau_ms", Response.MAX_TAU_MS + 1],
		["initial_value", NAN], ["initial_value", 1.0e12 + 1.0], ["initial_value", false],
		["target_value", -INF], ["target_value", -1.0e12 - 1.0], ["target_per_ms", NAN],
		["target_per_ms", 2.0e12 + 1.0], ["target_per_ms", "0"], ["version", true],
	]:
		var bad: Dictionary = original.duplicate(true)
		bad[test[0]] = test[1]
		candidates.append(bad)
	var bad_endpoint: Dictionary = original.duplicate(true)
	bad_endpoint.target_value = 1.0e12
	bad_endpoint.target_per_ms = 1.0
	candidates.append(bad_endpoint)
	for candidate: Variant in candidates:
		runner.assert_true(not response.restore(candidate), "invalid or incomplete v1 candidate is rejected")
		runner.assert_eq(response.to_dict(), original, "failed candidate does not partially modify the anchor")
		runner.assert_eq(response.sample(500), original_future, "failed candidate leaves the future unchanged")
