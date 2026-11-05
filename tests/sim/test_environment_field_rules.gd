extends RefCounted
## The field kernel and temperature table are independent of a live world.

const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const MAX_INTEGER: int = 9223372036854775807
const MIN_INTEGER: int = -9223372036854775807 - 1


func run(runner: Object) -> void:
	_circle(runner)
	_source_channels_and_rounding(runner)
	_temperature_anchors(runner)
	_seasonal_and_monotonic(runner)
	_extended_levels_with_bounded_values(runner)
	_net_before_modulation(runner)
	_rejection(runner)
	print("SCENARIO environment field rules: circular Euclidean kernel, seasonal net-grade temperature, symmetric modulation, high grades and safe rejection")


func _source_channels_and_rounding(runner: Object) -> void:
	var source_elements: Array[int] = [11, 22, 33, 44, 55]
	var cold: PackedInt32Array = Rules.source_to_packed_channels(source_elements, -9)
	var hot: PackedInt32Array = Rules.source_to_packed_channels(source_elements, 9)
	runner.assert_eq(cold, PackedInt32Array([44, 11, 55, 22, 33, 0, 9]), "source elements map to metal/wood/water/fire/earth and the cold magnitude")
	runner.assert_eq(hot, PackedInt32Array([44, 11, 55, 22, 33, 9, 0]), "one positive thermal attribute becomes the separate packed hot maximum")
	runner.assert_eq(Rules.packed_to_source_elements(cold), source_elements, "a completed packed field returns the public wood/fire/earth/metal/water order")
	var round_trip: Array[int] = Rules.packed_to_source_elements(cold)
	round_trip[0] = 1000
	runner.assert_eq(int(cold[1]), 11, "mutating external elements cannot mutate the packed field")
	runner.assert_eq(Rules.effective_grade(1, 500_000), 1, "a positive half unit rounds away from zero")
	runner.assert_eq(Rules.effective_grade(-1, 500_000), -1, "a negative half unit rounds symmetrically away from zero")
	runner.assert_eq(Rules.effective_grade(2, 750_000), 2, "a positive one-and-a-half rounds to nearest")
	runner.assert_eq(Rules.effective_grade(-2, 750_000), -2, "a negative one-and-a-half has the same magnitude")
	runner.assert_eq(Rules.effective_grade(1, 499_999), 0, "a value below the halfway point rounds to zero")
	runner.assert_eq(Rules.effective_grade(-1, 499_999), 0, "negative values below the halfway point also round to zero")
	runner.assert_eq(Rules.effective_grade(Rules.MAX_GRADE_MILLI, Rules.SCALE), Rules.MAX_GRADE_MILLI, "the maximum supported grade retains its full strength without overflow")
	runner.assert_eq(Rules.effective_grade(-Rules.MAX_GRADE_MILLI, Rules.SCALE), -Rules.MAX_GRADE_MILLI, "the negative maximum remains symmetric")


func _circle(runner: Object) -> void:
	var samples: Array = [
		[Vector2i.ZERO, 4, 1_000_000],
		[Vector2i(1, 0), 4, 750_000],
		[Vector2i(1, 1), 4, 646_447],
		[Vector2i(2, 0), 4, 500_000],
		[Vector2i(2, 1), 4, 440_983],
		[Vector2i(3, 1), 4, 209_431],
		[Vector2i(3, 3), 4, 0],
		[Vector2i(3, 4), 5, 0],
		[Vector2i(4, 0), 4, 0],
		[Vector2i(5, 0), 4, 0],
		[Vector2i(1, 0), 1, 0],
		[Vector2i(1, 1), 1, 0],
		[Vector2i(1, 0), 128, 992_188], # exact half millionth, ties up
		[Vector2i(255, 0), 256, 3_906],
	]
	for sample: Array in samples:
		var point: Vector2i = sample[0]
		var radius: int = int(sample[1])
		var expected: int = int(sample[2])
		for transformed: Vector2i in [point, Vector2i(-point.x, point.y), Vector2i(point.x, -point.y), Vector2i(point.y, point.x)]:
			runner.assert_eq(Rules.kernel(transformed, radius), {"ok": true, "weight": expected}, "circular kernel and reflection at " + str(transformed))
	var straight: int = int(Rules.kernel(Vector2i(1, 0), 4).weight)
	var diagonal: int = int(Rules.kernel(Vector2i(1, 1), 4).weight)
	runner.assert_true(straight > diagonal, "a diagonal lies sqrt(2) away, not one grid step")
	runner.assert_eq(Rules.kernel(Vector2i(-2147483648, 2147483647), 256), {"ok": true, "weight": 0}, "extreme coordinates are rejected as exterior before squaring")


func _temperature_anchors(runner: Object) -> void:
	# These are the proposed table's actual targets at 20 C, not copied rises.
	for row: Array in [
		[0, 20_000, 20_000],
		[1_000, 40_000, 0],
		[3_000, 200_000, -40_000],
		[5_000, 1_000_000, -120_000],
		[8_000, 5_000_000, -250_000],
		[10_000, 10_000_000, -273_150],
	]:
		var grade: int = int(row[0])
		runner.assert_eq(Rules.temperature(20_000, grade), {"ok": true, "temperature_milli": int(row[1])}, "hot anchor at grade " + str(grade))
		runner.assert_eq(Rules.temperature(20_000, -grade), {"ok": true, "temperature_milli": int(row[2])}, "cold anchor at grade " + str(grade))
	for row: Array in [
		[500, 30_000, 10_000],
		[2_000, 120_000, -20_000],
		[4_000, 600_000, -80_000],
		[6_500, 3_000_000, -185_000],
		[9_000, 7_500_000, -261_575],
	]:
		var grade: int = int(row[0])
		runner.assert_eq(Rules.temperature(20_000, grade), {"ok": true, "temperature_milli": int(row[1])}, "fractional hot grade interpolates between anchors")
		runner.assert_eq(Rules.temperature(20_000, -grade), {"ok": true, "temperature_milli": int(row[2])}, "fractional cold grade interpolates between anchors")


func _seasonal_and_monotonic(runner: Object) -> void:
	for neutral: int in [-273_149, -10_000, 20_000, 40_000, Rules.MAX_NEUTRAL_MILLI]:
		runner.assert_eq(Rules.temperature(neutral, 0), {"ok": true, "temperature_milli": neutral}, "zero net field retains the seasonal neutral")
		runner.assert_eq(Rules.temperature(neutral, -10_000), {"ok": true, "temperature_milli": Rules.ABSOLUTE_ZERO_MILLI}, "ten cold levels reach the same absolute lower limit")
		var previous_hot: int = neutral
		var previous_cold: int = neutral
		for grade: int in range(1, 10_001, 100):
			var hot: int = int(Rules.temperature(neutral, grade).temperature_milli)
			var cold: int = int(Rules.temperature(neutral, -grade).temperature_milli)
			runner.assert_true(hot >= previous_hot and cold <= previous_cold, "both temperature branches interpolate monotonically")
			runner.assert_true(cold >= Rules.ABSOLUTE_ZERO_MILLI and cold <= neutral, "cold interpolation stays between neutral and absolute zero")
			previous_hot = hot
			previous_cold = cold
	runner.assert_eq(Rules.temperature(-10_000, -3_000).temperature_milli, -63_860, "winter cold uses a proportion of the winter-to-zero span")
	runner.assert_eq(Rules.temperature(40_000, -3_000).temperature_milli, -24_093, "summer cold uses a proportion of the summer-to-zero span")
	runner.assert_eq(Rules.temperature(-10_000, 3_000).temperature_milli, 170_000, "heat rise is added to the seasonal neutral")
	runner.assert_eq(Rules.temperature(Rules.MAX_NEUTRAL_MILLI, -8_000).temperature_milli, 78_718_231, "the largest intermediate cold product preserves its ratio")


func _extended_levels_with_bounded_values(runner: Object) -> void:
	runner.assert_eq(Rules.temperature(20_000, 11_000).temperature_milli, 12_500_000, "heat extends the last segment beyond level ten")
	runner.assert_eq(Rules.temperature(20_000, 1_000_000).temperature_milli, 2_485_000_000, "heat supports one thousand levels without floating-point infinity")
	runner.assert_eq(Rules.temperature(20_000, Rules.MAX_GRADE_MILLI).temperature_milli, 2_499_985_000_000, "the declared largest hot grade stays exact and bounded")
	runner.assert_eq(Rules.temperature(20_000, -1_000_000).temperature_milli, Rules.ABSOLUTE_ZERO_MILLI, "high cold grades cannot lower temperature below zero kelvin")
	runner.assert_eq(Rules.temperature(20_000, -Rules.MAX_GRADE_MILLI).temperature_milli, Rules.ABSOLUTE_ZERO_MILLI, "the declared largest cold grade stays bounded")
	runner.assert_eq(Rules.thermal_target(20_000, 12_000, 11_000).temperature_milli, 40_000, "cold above ten still offsets heat above ten")
	runner.assert_eq(Rules.thermal_target(20_000, 11_000, 12_000).temperature_milli, 0, "reversing high-grade sources produces the cold net")
	runner.assert_eq(Rules.thermal_target(20_000, Rules.MAX_GRADE_MILLI, Rules.MAX_GRADE_MILLI).temperature_milli, 20_000, "largest equal sources neutralize before saturation")
	runner.assert_eq(Rules.thermal_target(20_000, Rules.MAX_GRADE_MILLI, Rules.MAX_GRADE_MILLI - 1_000).temperature_milli, 40_000, "a small net difference of two very large sources is preserved")


func _net_before_modulation(runner: Object) -> void:
	for neutral: int in [-10_000, 20_000, 40_000]:
		for multiplier: int in [0, 500_000, 980_000, 990_000, 1_000_000]:
			runner.assert_eq(Rules.thermal_target(neutral, 10_000, 10_000, multiplier), {"ok": true, "temperature_milli": neutral}, "equal ice and fire remain balanced in any season and attenuation")
		runner.assert_eq(Rules.thermal_target(neutral, 0, 0), {"ok": true, "temperature_milli": neutral}, "an empty field cannot create its own temperature effect")
	runner.assert_eq(Rules.thermal_target(20_000, 10_000, 0, 980_000).temperature_milli, 9_500_000, "tide scales the grade before the nonlinear temperature mapping")
	runner.assert_eq(Rules.thermal_target(20_000, 0, 10_000, 980_000).temperature_milli, -270_835, "the same tide acts on a cold grade before temperature mapping")
	runner.assert_eq(Rules.thermal_target(20_000, 1, 0, 500_000).temperature_milli, 20_020, "positive half-grade rounds away from zero")
	runner.assert_eq(Rules.thermal_target(20_000, 0, 1, 500_000).temperature_milli, 19_980, "negative half-grade rounds symmetrically away from zero")
	runner.assert_eq(Rules.thermal_target(20_000, 2, 1, 500_000).temperature_milli, 20_020, "subtract source grades before rounding their scaled difference")
	runner.assert_eq(Rules.thermal_target(20_000, 1, 2, 500_000).temperature_milli, 19_980, "reversed fractional difference keeps the same magnitude")
	runner.assert_eq(Rules.thermal_target(20_000, 100_000, 0, 0).temperature_milli, 20_000, "zero attenuation gives a fully insulated target")


func _rejection(runner: Object) -> void:
	for radius: int in [MIN_INTEGER, -1, 0, 257, MAX_INTEGER]:
		var result: Dictionary = Rules.kernel(Vector2i.ZERO, radius)
		runner.assert_eq(result, {"ok": false, "reason": "radius_out_of_range"}, "invalid radii fail explicitly instead of inventing a field")
	for neutral: int in [MIN_INTEGER, -273_151, -273_150, Rules.MAX_NEUTRAL_MILLI + 1, MAX_INTEGER]:
		var result: Dictionary = Rules.temperature(neutral, 0)
		runner.assert_eq(result, {"ok": false, "reason": "neutral_out_of_range"}, "invalid neutral temperatures fail explicitly")
		runner.assert_eq(Rules.thermal_target(neutral, 0, 0), result, "thermal target also rejects invalid neutrals")
	for grade: int in [MIN_INTEGER, -Rules.MAX_GRADE_MILLI - 1, Rules.MAX_GRADE_MILLI + 1, MAX_INTEGER]:
		runner.assert_eq(Rules.temperature(20_000, grade), {"ok": false, "reason": "grade_out_of_range"}, "invalid net grades fail before sign or product arithmetic")
	for grade: int in [MIN_INTEGER, -1, Rules.MAX_GRADE_MILLI + 1, MAX_INTEGER]:
		var failed: Dictionary = {"ok": false, "reason": "source_grade_out_of_range"}
		runner.assert_eq(Rules.thermal_target(20_000, grade, 0), failed, "hot source grades are checked before subtraction")
		runner.assert_eq(Rules.thermal_target(20_000, 0, grade), failed, "cold source grades are checked before subtraction")
	for multiplier: int in [MIN_INTEGER, -1, 1_000_001, MAX_INTEGER]:
		runner.assert_eq(Rules.thermal_target(20_000, 1, 0, multiplier), {"ok": false, "reason": "multiplier_out_of_range"}, "invalid attenuation is never silently clamped")
