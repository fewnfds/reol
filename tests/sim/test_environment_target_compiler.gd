extends RefCounted
## The cached compiler must produce the same held targets as the existing
## per-cell compiler, regardless of region order, clock or horizon changes.

const Compiler = preload("res://scripts/sim/environment_target_compiler.gd")
const Segments = preload("res://scripts/sim/environment_temperature_segments.gd")
const SegmentFixture = preload("res://tests/sim/test_environment_temperature_segments.gd")
const Climate = preload("res://scripts/sim/climate_rules.gd")
const Weather = preload("res://scripts/sim/weather.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const Response = preload("res://scripts/sim/environment_field_response.gd")


func run(runner: Object) -> void:
	_differential(runner)
	_boundary_neighbors(runner)
	_detached_configuration(runner)
	_invalid_inputs(runner)
	_unphysical_background(runner)
	print("SCENARIO environment target compiler: region and time differential, immutable configuration and rejection")


func _settings() -> Dictionary:
	return {
		"climate": JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/climate.json")),
		"weather": JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/weather.json")),
		"weather_epoch_ms": 5_000,
		"seed": 42,
		"tau_ms": 8_000,
		"tide_grid_ms": 20_000,
	}


func _reference(settings: Dictionary, cell: Vector2i, at_ms: int, hot: int, cold: int, horizon: int) -> Dictionary:
	return Segments.compile_segment(cell, at_ms, settings.climate, settings.weather,
		int(settings.weather_epoch_ms), int(settings.seed), hot, cold, int(settings.tau_ms),
		int(settings.tide_grid_ms), horizon)


func _compare(runner: Object, compiler: RefCounted, settings: Dictionary, cell: Vector2i, at_ms: int, hot: int, cold: int, horizon: int) -> void:
	var expected: Dictionary = _reference(settings, cell, at_ms, hot, cold, horizon)
	var actual: Dictionary = compiler.compile(cell, at_ms, hot, cold, horizon)
	var label: String = "seed=%d cell=%s time=%d hot=%d cold=%d horizon=%d" % [int(settings.seed), str(cell), at_ms, hot, cold, horizon]
	runner.assert_eq(actual.get("ok"), expected.get("ok"), "compiler status: " + label)
	if bool(expected.get("ok", false)) and bool(actual.get("ok", false)):
		for key: String in ["target_c", "target_per_ms", "until_ms", "tau_ms"]:
			runner.assert_eq(actual.get(key), expected.get(key), "compiler " + key + ": " + label)
	elif not bool(expected.get("ok", false)) and not bool(actual.get("ok", false)):
		runner.assert_eq(actual.get("reason"), expected.get("reason"), "compiler failure reason: " + label)


func _differential(runner: Object) -> void:
	var settings: Dictionary = _settings()
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(269, 511), Vector2i(270, 0),
		Vector2i(511, 511), Vector2i(512, 511), Vector2i(-1, 0), Vector2i(300, 100)]
	var times: Array[int] = [0, 1, 999, 1000, 19_999, 20_000, 59_999, 60_000,
		1_204_999, 1_205_000, 3_599_999, 3_600_000, 86_399_999, 86_400_000,
		90 * 86_400_000 - 1, 90 * 86_400_000, Response.MAX_TIME - 1]
	var grades: Array[Array] = [[0, 0], [10_000, 0], [0, 10_000],
		[7_000, 7_000], [Rules.MAX_GRADE_MILLI, 1]]
	for seed: int in [0, 42, -4_294_967_297, 4_294_967_297]:
		settings.seed = seed
		var compiler := Compiler.new()
		if not compiler.configure(settings):
			runner.assert_true(false, "valid differential settings configure")
			return
		for at_ms: int in times:
			# One-millisecond horizons and ordinary longer horizons both apply at
			# the supported clock limit; changing the horizon invalidates the cache.
			var horizons: Array[int] = [at_ms + 1, mini(Response.MAX_TIME, at_ms + 90_000_000)]
			for horizon: int in horizons:
				for cell: Vector2i in cells:
					for grade: Array in grades:
						_compare(runner, compiler, settings, cell, at_ms, int(grade[0]), int(grade[1]), horizon)


func _boundary_neighbors(runner: Object) -> void:
	var settings: Dictionary = _settings()
	var compiler := Compiler.new()
	if not compiler.configure(settings):
		runner.assert_true(false, "boundary settings configure")
		return
	# Ask the original implementation for its actual changing boundary, then
	# compare on both sides. Reversing the clock order also exercises cache reset.
	for cell: Vector2i in [Vector2i(12, 12), Vector2i(270, 8), Vector2i(-1, -1)]:
		for start: int in [0, 19_999, 1_200_000, 86_400_000, 90 * 86_400_000]:
			for grade: Array in [[10_000, 0], [0, 10_000], [4_000, 4_000]]:
				var segment: Dictionary = _reference(settings, cell, start, int(grade[0]), int(grade[1]), Response.MAX_TIME)
				if not bool(segment.get("ok", false)):
					runner.assert_true(false, "reference must compile the boundary fixture: " + str(segment))
					return
				var boundary: int = int(segment.until_ms)
				for at_ms: int in [boundary + 1, boundary, boundary - 1]:
					_compare(runner, compiler, settings, cell, at_ms, int(grade[0]), int(grade[1]), mini(Response.MAX_TIME, at_ms + 100_000))


func _detached_configuration(runner: Object) -> void:
	var settings: Dictionary = _settings()
	var reference: Dictionary = settings.duplicate(true)
	var compiler := Compiler.new()
	if not compiler.configure(settings):
		runner.assert_true(false, "detached configuration starts valid")
		return
	_compare(runner, compiler, reference, Vector2i(0, 0), 10_000, 10_000, 0, 200_000)
	settings.climate.regions.home.base_tenths = -1000
	settings.climate.regions.home.daily_curve[0][1] = 700
	settings.climate.regions.river.seasonal_curve[0][1] = -700
	settings.weather.phases[0].kind = "rain"
	settings.weather.regions.river.offset_ms = 0
	settings.weather_epoch_ms = 0
	settings.seed = 0
	settings.tau_ms = 1
	settings.tide_grid_ms = 1
	# One query revisits a cached time, the next changes clock and region; this
	# detects a shallow copy even when a previous region result was memoized.
	_compare(runner, compiler, reference, Vector2i(0, 0), 10_000, 10_000, 0, 200_000)
	_compare(runner, compiler, reference, Vector2i(0, 0), 1_205_000, 10_000, 0, 2_000_000)
	_compare(runner, compiler, reference, Vector2i(300, 0), 1_205_000, 0, 10_000, 2_000_000)
	_compare(runner, compiler, reference, Vector2i(0, 0), 10_000, 10_000, 0, 200_001)
	runner.assert_true(not compiler.configure(reference), "an already bound compiler cannot be rebound")
	_compare(runner, compiler, reference, Vector2i(0, 0), 10_000, 10_000, 0, 200_000)


func _invalid_inputs(runner: Object) -> void:
	var valid: Dictionary = _settings()
	var unbound := Compiler.new()
	runner.assert_eq(unbound.compile(Vector2i.ZERO, 0, 0, 0, 1).get("reason"), "target_context", "an unbound compiler rejects queries")
	runner.assert_true(not unbound.configure({}), "an empty configuration is rejected")
	runner.assert_true(unbound.configure(valid), "a rejected configuration leaves the compiler available")
	for pair: Array in [["climate", {}], ["weather", {}], ["seed", "42"],
		["weather_epoch_ms", -1], ["weather_epoch_ms", Response.MAX_TIME + 1],
		["tau_ms", 0], ["tau_ms", Response.MAX_TAU_MS + 1], ["tau_ms", 1.5],
		["tide_grid_ms", 0], ["tide_grid_ms", Response.MAX_TIME + 1]]:
		var invalid: Dictionary = valid.duplicate(true)
		invalid[pair[0]] = pair[1]
		var attempt := Compiler.new()
		runner.assert_true(not attempt.configure(invalid), "invalid configuration rejected: %s=%s" % [str(pair[0]), str(pair[1])])
	var missing: Dictionary = valid.duplicate(true)
	missing.erase("seed")
	runner.assert_true(not Compiler.new().configure(missing), "missing configuration field is rejected")
	var extra: Dictionary = valid.duplicate(true)
	extra["unknown"] = 1
	runner.assert_true(not Compiler.new().configure(extra), "extra configuration field is rejected")
	for example: Array in [[-1, 0, 0, 1], [Response.MAX_TIME, 0, 0, Response.MAX_TIME],
		[5, 0, 0, 5], [5, 0, 0, 4], [5, 0, 0, Response.MAX_TIME + 1]]:
		runner.assert_eq(unbound.compile(Vector2i.ZERO, example[0], example[1], example[2], example[3]).get("reason"), "target_context", "invalid time or horizon rejected")
	for grade: Array in [[-1, 0], [0, -1], [Rules.MAX_GRADE_MILLI + 1, 0], [0, Rules.MAX_GRADE_MILLI + 1]]:
		runner.assert_eq(unbound.compile(Vector2i.ZERO, 0, grade[0], grade[1], 1).get("reason"), "source_grade_out_of_range", "invalid source grade rejected")
	_compare(runner, unbound, valid, Vector2i.ZERO, 0, 10_000, 0, 100_000)


func _unphysical_background(runner: Object) -> void:
	var fixture := SegmentFixture.new()
	var climate: Dictionary = fixture._climate()
	var weather: Dictionary = fixture._weather()
	for region: Dictionary in climate.regions.values():
		region.base_tenths = -1000
		region.daily_curve = [[0, -1000], [1440, -1000]]
		region.seasonal_curve = [[0, -732], [360, -732]]
	var settings: Dictionary = _settings()
	settings.climate = climate
	settings.weather = weather
	runner.assert_true(Climate.valid_definitions(climate) and Weather.valid_definitions(weather), "below-zero background fixture is structurally valid")
	var compiler := Compiler.new()
	if not compiler.configure(settings):
		runner.assert_true(false, "structurally valid extreme background configures")
		return
	for cell: Vector2i in [Vector2i.ZERO, Vector2i(300, 0), Vector2i(-1, 0)]:
		for grade: Array in [[0, 0], [10_000, 0], [0, 10_000], [10_000, 10_000]]:
			var expected: Dictionary = _reference(settings, cell, 0, grade[0], grade[1], 60_000)
			var actual: Dictionary = compiler.compile(cell, 0, grade[0], grade[1], 60_000)
			runner.assert_eq(expected.get("reason"), "neutral_out_of_range", "reference rejects a background below absolute zero")
			runner.assert_eq(actual.get("reason"), "neutral_out_of_range", "cached compiler also rejects a background below absolute zero")
