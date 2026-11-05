extends RefCounted
## Pure tide queries on the original seed, integer world time and cell.

const Tide = preload("res://scripts/sim/environment_field_tide.gd")


func run(runner: Object) -> void:
	_cycle_and_boundaries(runner)
	_spatial_interpolation(runner)
	_determinism(runner)
	_rejection_and_limits(runner)
	print("SCENARIO environment field tide: full-amplitude closed cycle, continuous signed-space phase, pure deterministic sampling and safe future boundaries")


func _cycle_and_boundaries(runner: Object) -> void:
	var period: int = 1200
	for example: Array in [[0, Vector2i.ZERO], [1, Vector2i(35, -12)], [-99, Vector2i(-67, 138)], [123456789, Vector2i(128, -64)]]:
		var seed: int = int(example[0])
		var cell: Vector2i = example[1]
		var opening: Dictionary = Tide.sample(seed, cell, 0, period)
		runner.assert_true(bool(opening.ok), "the selected seed and cell have a valid cycle")
		var first_low: int = posmod(period - int(opening.phase_ms), period)
		var low: Dictionary = Tide.sample(seed, cell, first_low, period)
		var rising_mid: Dictionary = Tide.sample(seed, cell, first_low + period / 4, period)
		var high: Dictionary = Tide.sample(seed, cell, first_low + period / 2, period)
		var falling_mid: Dictionary = Tide.sample(seed, cell, first_low + period * 3 / 4, period)
		var closed: Dictionary = Tide.sample(seed, cell, first_low + period, period)
		runner.assert_eq(low.multiplier, 980000, "every cell reaches the full lower endpoint")
		runner.assert_eq(high.multiplier, 1000000, "every cell reaches the full upper endpoint")
		runner.assert_eq(rising_mid.multiplier, 990000, "a quarter cycle reaches the nominal multiplier while rising")
		runner.assert_eq(falling_mid.multiplier, 990000, "the falling half crosses the same nominal multiplier")
		runner.assert_eq(closed.multiplier, low.multiplier, "the triangular wave closes exactly after one cycle")
		runner.assert_eq(closed.phase_ms, low.phase_ms, "the integer phase closes exactly after one cycle")
		runner.assert_eq(int(low.next_boundary_ms), first_low + period / 2, "a low turning point reports the next high, not itself")
		runner.assert_eq(int(high.next_boundary_ms), first_low + period, "a high turning point reports the next low")
		var just_before_high: Dictionary = Tide.sample(seed, cell, first_low + period / 2 - 1, period)
		runner.assert_eq(int(just_before_high.next_boundary_ms), first_low + period / 2, "the next turning point is exact one millisecond before it")
		for at_ms: int in [0, 1, 197, 1199, 1200, 10001]:
			var current: Dictionary = Tide.sample(seed, cell, at_ms, period)
			var repeated: Dictionary = Tide.sample(seed, cell, at_ms + period, period)
			runner.assert_true(int(current.multiplier) >= Tide.MIN_MULTIPLIER and int(current.multiplier) <= Tide.SCALE, "all sampled multipliers remain within the declared bounds")
			runner.assert_eq(current.multiplier, repeated.multiplier, "any phase repeats after the complete period")
			runner.assert_eq(current.phase_ms, repeated.phase_ms, "periodic phases do not drift")
			runner.assert_eq(int(repeated.next_boundary_ms), int(current.next_boundary_ms) + period, "turning points repeat with the same period")
			runner.assert_true(bool(current.next_boundary_known) and int(current.next_boundary_ms) > at_ms, "a representable turning point is strictly in the future")
	for seed: int in [-1, 0, 1]:
		var first: Dictionary = Tide.sample(seed, Vector2i(-1, 1), 0, 2, 1)
		var second: Dictionary = Tide.sample(seed, Vector2i(-1, 1), 1, 2, 1)
		runner.assert_eq(int(first.multiplier) + int(second.multiplier), 1980000, "the minimum two-millisecond cycle still reaches both endpoints")
		runner.assert_eq(first.next_boundary_ms, 1, "the minimum cycle has a turning point every millisecond")


func _spatial_interpolation(runner: Object) -> void:
	var period: int = 600000
	var spacing: int = 64
	# At time zero the exposed phase is the interpolated raw corner phase.
	# Midpoints must stay between their two anchors, including negative cells.
	for seed: int in [-19, 0, 7, 103]:
		for y: int in [-64, 0, 64]:
			for x: int in [-128, -64, 0, 64]:
				var left: int = int(Tide.sample(seed, Vector2i(x, y), 0, period, spacing).phase_ms)
				var middle: int = int(Tide.sample(seed, Vector2i(x + 32, y), 0, period, spacing).phase_ms)
				var right: int = int(Tide.sample(seed, Vector2i(x + spacing, y), 0, period, spacing).phase_ms)
				runner.assert_true(middle >= mini(left, right) and middle <= maxi(left, right), "raw phase stays between coarse endpoints on both sides of zero")
				runner.assert_true(absi(2 * middle - left - right) <= 1, "coarse horizontal midpoint is the integer midpoint, not an extrapolation")
		for x: int in [-64, 0, 64]:
			for y: int in [-128, -64, 0, 64]:
				var top: int = int(Tide.sample(seed, Vector2i(x, y), 0, period, spacing).phase_ms)
				var middle: int = int(Tide.sample(seed, Vector2i(x, y + 32), 0, period, spacing).phase_ms)
				var bottom: int = int(Tide.sample(seed, Vector2i(x, y + spacing), 0, period, spacing).phase_ms)
				runner.assert_true(absi(2 * middle - top - bottom) <= 1, "coarse vertical midpoint remains correct for negative and positive rows")
		var corners: Array[Vector2i] = [Vector2i(-64, -64), Vector2i(0, -64), Vector2i(-64, 0), Vector2i(0, 0)]
		var corner_sum: int = 0
		for corner: Vector2i in corners:
			corner_sum += int(Tide.sample(seed, corner, 0, period, spacing).phase_ms)
		var center: int = int(Tide.sample(seed, Vector2i(-32, -32), 0, period, spacing).phase_ms)
		runner.assert_true(absi(4 * center - corner_sum) <= 3, "the negative quadrant center interpolates all four raw corner phases")
	# Adjacent samples near every coarse seam have a bounded phase step; no
	# discontinuity may be introduced by crossing zero or a negative boundary.
	for coordinate: int in range(-130, 131):
		var a: int = int(Tide.sample(91, Vector2i(coordinate, -17), 0, period, spacing).phase_ms)
		var b: int = int(Tide.sample(91, Vector2i(coordinate + 1, -17), 0, period, spacing).phase_ms)
		var c: int = int(Tide.sample(91, Vector2i(-17, coordinate), 0, period, spacing).phase_ms)
		var d: int = int(Tide.sample(91, Vector2i(-17, coordinate + 1), 0, period, spacing).phase_ms)
		runner.assert_true(absi(a - b) <= 9376 and absi(c - d) <= 9376, "adjacent raw phases stay continuous across coarse grid seams")
	# Select a wide-gap example so this catches shortest-arc phase blending,
	# which otherwise can appear correct at nearby random corner phases.
	var checked_wide_gap: bool = false
	for seed: int in range(128):
		var left: int = int(Tide.sample(seed, Vector2i(-64, 0), 0, period, spacing).phase_ms)
		var right: int = int(Tide.sample(seed, Vector2i(0, 0), 0, period, spacing).phase_ms)
		if absi(left - right) > period / 2:
			var middle: int = int(Tide.sample(seed, Vector2i(-32, 0), 0, period, spacing).phase_ms)
			runner.assert_true(absi(2 * middle - left - right) <= 1, "wide phase gaps interpolate through the raw midpoint, not around the ring")
			checked_wide_gap = true
			break
	runner.assert_true(checked_wide_gap, "the fixture exercises raw interpolation across a greater-than-half-period phase gap")


func _determinism(runner: Object) -> void:
	var examples: Array = [
		[0, Vector2i(0, 0), 0], [7, Vector2i(-1, -65), 137],
		[-7, Vector2i(128, -129), 123456789], [4294967296, Vector2i(12, 55), 999999],
		[-9223372036854775807 - 1, Vector2i(-2147483648, 2147483647), Tide.MAX_TIME],
		[9223372036854775807, Vector2i(2147483647, -2147483648), 100],
	]
	var snapshots: Array[Dictionary] = []
	for example: Array in examples:
		var query: Dictionary = Tide.sample(int(example[0]), example[1], int(example[2]))
		runner.assert_true(bool(query.ok), "full signed seed and Vector2i ranges are valid")
		snapshots.append(query.duplicate(true))
	for index: int in range(examples.size() - 1, -1, -1):
		var example: Array = examples[index]
		runner.assert_eq(Tide.sample(int(example[0]), example[1], int(example[2])), snapshots[index], "reverse query order and intervening calls never redraw a phase")
		var changed: Dictionary = Tide.sample(int(example[0]), example[1], int(example[2]))
		changed["multiplier"] = -1
		runner.assert_eq(Tide.sample(int(example[0]), example[1], int(example[2])), snapshots[index], "mutating one result cannot change a later sample")
	var distinct_seed_found: bool = false
	var distinct_cell_found: bool = false
	for coordinate: int in range(16):
		var cell: Vector2i = Vector2i(coordinate * 64, -64)
		var base: int = int(Tide.sample(0, cell, 0).phase_ms)
		if base != int(Tide.sample(4294967296, cell, 0).phase_ms):
			distinct_seed_found = true
		if base != int(Tide.sample(0, cell + Vector2i(64, 0), 0).phase_ms):
			distinct_cell_found = true
	runner.assert_true(distinct_seed_found, "high seed bits affect stable corner phases")
	runner.assert_true(distinct_cell_found, "coarse grid location affects stable corner phases")


func _rejection_and_limits(runner: Object) -> void:
	for at_ms: int in [-1, Tide.MAX_TIME + 1]:
		var rejected: Dictionary = Tide.sample(0, Vector2i.ZERO, at_ms)
		runner.assert_true(not bool(rejected.ok) and not str(rejected.get("reason", "")).is_empty(), "unsupported time is rejected with a reason")
	for period: int in [-2, 0, 1, 3, Tide.MAX_PERIOD_MS + 1, Tide.MAX_PERIOD_MS + 2]:
		var rejected: Dictionary = Tide.sample(0, Vector2i.ZERO, 0, period)
		runner.assert_true(not bool(rejected.ok) and not str(rejected.get("reason", "")).is_empty(), "invalid period is rejected with a reason")
	for spacing: int in [-1, 0, Tide.MAX_SPACING + 1]:
		var rejected: Dictionary = Tide.sample(0, Vector2i.ZERO, 0, Tide.DEFAULT_PERIOD_MS, spacing)
		runner.assert_true(not bool(rejected.ok) and not str(rejected.get("reason", "")).is_empty(), "invalid coarse spacing is rejected with a reason")
	for spacing: int in [1, Tide.MAX_SPACING]:
		for cell: Vector2i in [Vector2i(-2147483648, 2147483647), Vector2i(-2147483136, 2147483136)]:
			var largest_period: Dictionary = Tide.sample(9223372036854775807, cell, 0, Tide.MAX_PERIOD_MS, spacing)
			runner.assert_true(bool(largest_period.ok) and int(largest_period.phase_ms) >= 0 and int(largest_period.phase_ms) < Tide.MAX_PERIOD_MS, "largest valid period and spacing safely admit extreme coordinates")
			runner.assert_true(int(largest_period.multiplier) >= Tide.MIN_MULTIPLIER and int(largest_period.multiplier) <= Tide.SCALE, "largest valid weighted calculation stays in range")
			var next_low: int = posmod(Tide.MAX_PERIOD_MS - int(largest_period.phase_ms), Tide.MAX_PERIOD_MS)
			runner.assert_eq(Tide.sample(9223372036854775807, cell, next_low, Tide.MAX_PERIOD_MS, spacing).multiplier, Tide.MIN_MULTIPLIER, "the largest period still reaches its lower endpoint")
			runner.assert_eq(Tide.sample(9223372036854775807, cell, next_low + Tide.MAX_PERIOD_MS / 2, Tide.MAX_PERIOD_MS, spacing).multiplier, Tide.SCALE, "the largest period still reaches its upper endpoint")
	var cell: Vector2i = Vector2i(-57, 92)
	var last: Dictionary = Tide.sample(73, cell, Tide.MAX_TIME)
	var reduced: Dictionary = Tide.sample(73, cell, Tide.MAX_TIME % Tide.DEFAULT_PERIOD_MS)
	runner.assert_eq(last.phase_ms, reduced.phase_ms, "maximum time is reduced exactly as an integer before phase addition")
	runner.assert_eq(last.multiplier, reduced.multiplier, "large integer time yields the same closed-cycle multiplier")
	var prior: Dictionary = Tide.sample(73, cell, Tide.MAX_TIME - 1)
	runner.assert_eq(int(last.phase_ms), (int(prior.phase_ms) + 1) % Tide.DEFAULT_PERIOD_MS, "the final supported millisecond is not rounded away")
	runner.assert_true(bool(last.ok) and not bool(last.next_boundary_known) and int(last.next_boundary_ms) == -1, "a valid maximum-time sample explicitly reports no representable future boundary")
	runner.assert_true(not str(last.get("reason", "")).is_empty(), "an unavailable future boundary explains why")
	var before_limit: Dictionary = Tide.sample(73, cell, Tide.MAX_TIME - 1, 2)
	runner.assert_true(bool(before_limit.next_boundary_known), "a real boundary at the maximum supported time remains representable")
	runner.assert_eq(int(before_limit.next_boundary_ms), Tide.MAX_TIME, "the last representable future boundary is not discarded")
	var no_later: Dictionary = Tide.sample(73, cell, Tide.MAX_TIME, 2)
	runner.assert_true(not bool(no_later.next_boundary_known) and int(no_later.next_boundary_ms) == -1, "the current maximum is never reported as its own future boundary")
