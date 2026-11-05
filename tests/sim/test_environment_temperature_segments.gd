extends RefCounted
## Isolated held targets and their integration with the actual-temperature owner.

const Segments = preload("res://scripts/sim/environment_temperature_segments.gd")
const Climate = preload("res://scripts/sim/climate_rules.gd")
const Weather = preload("res://scripts/sim/weather.gd")
const Tide = preload("res://scripts/sim/environment_field_tide.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const Response = preload("res://scripts/sim/environment_field_response.gd")
const State = preload("res://scripts/sim/environment_temperature_state.gd")
const Index = preload("res://scripts/sim/environment_field_index.gd")
const CELL := Vector2i.ZERO
const SEED: int = 42
const EPOCH: int = 5_000


func run(runner: Object) -> void:
	_boundaries_and_grid(runner)
	_neutral_and_limits(runner)
	_invalid_inputs(runner)
	_field_state_and_restart(runner)
	print("SCENARIO environment temperature segments: climate and weather boundaries, global tide grid, physical limits and isolated state recovery")


func _climate() -> Dictionary:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/climate.json"))
	rules.calendar.start_minutes = 0
	for region: Dictionary in rules.regions.values():
		region.base_tenths = 200
		region.daily_curve = [[0, 0], [1440, 0]]
		region.seasonal_curve = [[0, 0], [360, 0]]
		region.weather_offsets.rain = -20
	return rules


func _weather() -> Dictionary:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/weather.json"))
	rules.phases = [{"kind": "clear", "duration_ms": 60_000}, {"kind": "rain", "duration_ms": 60_000}]
	for region: Dictionary in rules.regions.values():
		region.offset_ms = 0
	return rules


func _segment(climate: Dictionary, weather: Dictionary, at_ms: int, hot: int = 100_000, cold: int = 0, grid: int = 20_000, horizon: int = 100_000, tau: int = 8_000, epoch: int = EPOCH) -> Dictionary:
	return Segments.compile_segment(CELL, at_ms, climate, weather, epoch, SEED, hot, cold, tau, grid, horizon)


func _change(segment: Dictionary, initial: Variant = null) -> Dictionary:
	var change: Dictionary = {"cell": CELL, "target_c": segment.target_c,
		"target_per_ms": segment.target_per_ms, "until_ms": segment.until_ms,
		"tau_ms": segment.tau_ms}
	if initial != null:
		change["initial_c"] = initial
	return change


func _apply(state: RefCounted, segment: Dictionary, at_ms: int, initial: Variant = null) -> Dictionary:
	var changes: Array[Dictionary] = [_change(segment, initial)]
	var plan: Dictionary = state.prepare_targets(changes, at_ms, 1)
	return state.commit(plan) if bool(plan.get("ok", false)) else plan


func _boundaries_and_grid(runner: Object) -> void:
	var climate: Dictionary = _climate()
	var weather: Dictionary = _weather()
	climate.regions.home.daily_curve = [[0, 0], [1, 2], [2, 2], [3, 0], [1440, 0]]
	runner.assert_true(Climate.valid_definitions(climate) and Weather.valid_definitions(weather), "boundary examples use fully valid bound definitions")
	for example: Array in [[0, 20_000], [19_999, 20_000], [20_000, 30_000], [29_999, 30_000], [30_000, 40_000], [40_000, 60_000], [60_000, 65_000], [65_000, 80_000]]:
		var segment: Dictionary = _segment(climate, weather, int(example[0]))
		runner.assert_true(bool(segment.get("ok", false)), "a known segment compiles at %dms" % int(example[0]))
		if bool(segment.get("ok", false)):
			runner.assert_eq(segment.until_ms, int(example[1]), "the first climate, weather, or global-grid boundary wins")
			runner.assert_eq(segment.target_per_ms, 0.0, "the grid target is held constant")
			runner.assert_eq(segment.tau_ms, 8_000, "the caller's response time is preserved")
	var horizon_first: Dictionary = _segment(climate, weather, 20_000, 100_000, 0, 20_000, 23_456)
	runner.assert_eq(horizon_first.get("until_ms"), 23_456, "the explicit horizon may end the known segment first")
	var simultaneous: Dictionary = _segment(climate, weather, 20_000, 100_000, 0, 10_000, 30_000)
	runner.assert_eq(simultaneous.get("until_ms"), 30_000, "coincident climate, grid and horizon boundaries do not invent an extra millisecond")
	var weather_coincident: Dictionary = _segment(climate, weather, 40_000, 100_000, 0, 20_000, 60_000, 8_000, 0)
	runner.assert_eq(weather_coincident.get("until_ms"), 60_000, "coincident weather, climate, grid and horizon boundaries end together")
	var segment: Dictionary = _segment(climate, weather, 65_000)
	var background: Dictionary = Climate.background_at(climate, weather, EPOCH, CELL, 65_000)
	var held: Dictionary = Tide.sample(SEED, CELL, 60_000)
	var instant: Dictionary = Tide.sample(SEED, CELL, 65_000)
	var expected: Dictionary = Rules.thermal_target(int(background.temperature_tenths) * 100, 100_000, 0, int(held.multiplier))
	var wrong_restart: Dictionary = Rules.thermal_target(int(background.temperature_tenths) * 100, 100_000, 0, int(instant.multiplier))
	runner.assert_true(bool(segment.get("ok", false)), "a weather change inside a grid produces a segment")
	if bool(segment.get("ok", false)):
		runner.assert_eq(segment.target_c, float(expected.temperature_milli) / 1000.0, "the new weather uses the original global-grid tide sample")
		runner.assert_true(expected.temperature_milli != wrong_restart.temperature_milli, "this case would detect resampling at the weather event")
	segment = _segment(climate, weather, 30_000)
	background = Climate.background_at(climate, weather, EPOCH, CELL, 30_000)
	held = Tide.sample(SEED, CELL, 20_000)
	expected = Rules.thermal_target(int(background.temperature_tenths) * 100, 100_000, 0, int(held.multiplier))
	if bool(segment.get("ok", false)):
		runner.assert_eq(segment.target_c, float(expected.temperature_milli) / 1000.0, "a climate threshold inside a grid also retains the original sample")
	var regional_climate: Dictionary = _climate()
	var regional_weather: Dictionary = _weather()
	regional_climate.regions.river.base_tenths = 270
	regional_weather.regions.river.offset_ms = 60_000
	var river: Dictionary = Segments.compile_segment(Vector2i(300, 0), 0, regional_climate, regional_weather, EPOCH, SEED, 0, 0, 8_000, 20_000, 100_000)
	var fallback: Dictionary = Segments.compile_segment(Vector2i(-1, -1), 0, regional_climate, regional_weather, EPOCH, SEED, 0, 0, 8_000, 20_000, 100_000)
	runner.assert_eq(river.get("target_c"), 25.0, "the queried cell uses its region's climate and weather offset")
	runner.assert_eq(fallback.get("target_c"), 20.0, "a cell outside defined regions uses the real climate fallback")


func _neutral_and_limits(runner: Object) -> void:
	var climate: Dictionary = _climate()
	var weather: Dictionary = _weather()
	for levels: Array in [[0, 0], [10_000, 10_000], [Rules.MAX_GRADE_MILLI, Rules.MAX_GRADE_MILLI]]:
		var segment: Dictionary = _segment(climate, weather, 0, int(levels[0]), int(levels[1]), 1, 100_000)
		runner.assert_true(bool(segment.get("ok", false)), "equal effective grades compile")
		if bool(segment.get("ok", false)):
			runner.assert_eq(segment.target_c, 20.0, "equal hot and cold leave the neutral temperature intact")
			runner.assert_eq(segment.until_ms, 65_000, "zero net grade skips all ineffective tide grid boundaries")
	var horizon: Dictionary = _segment(climate, weather, 0, 0, 0, 1, 12_345)
	runner.assert_eq(horizon.get("until_ms"), 12_345, "the horizon still limits a neutral segment")
	var hot: Dictionary = _segment(climate, weather, 0, Rules.MAX_GRADE_MILLI)
	runner.assert_true(bool(hot.get("ok", false)), "the maximum supported hot grade is a valid physical target")
	if bool(hot.get("ok", false)):
		var tide: Dictionary = Tide.sample(SEED, CELL, 0)
		var expected: Dictionary = Rules.thermal_target(20_000, Rules.MAX_GRADE_MILLI, 0, int(tide.multiplier))
		runner.assert_eq(hot.target_c, float(expected.temperature_milli) / 1000.0, "the maximum grade maps without truncation")
		runner.assert_true(float(hot.target_c) > 1.0e9 and float(hot.target_c) < State.MAX_C, "the real upper target remains within the state domain")
		var hot_state := State.new()
		hot_state.configure(Vector2i(1, 1), 1, 0)
		runner.assert_true(bool(_apply(hot_state, hot, 0, 20.0).get("ok", false)), "the actual-temperature owner accepts the maximum-grade target")
	var cold: Dictionary = _segment(climate, weather, 0, 0, Rules.MAX_GRADE_MILLI)
	runner.assert_eq(cold.get("target_c"), State.MIN_C, "strong cold may reach the allowed actual-temperature floor")
	if bool(cold.get("ok", false)):
		var cold_state := State.new()
		cold_state.configure(Vector2i(1, 1), 1, 0)
		runner.assert_true(bool(_apply(cold_state, cold, 0, 20.0).get("ok", false)), "the actual-temperature owner accepts the exact floor")
	runner.assert_true(not bool(Rules.temperature(Rules.ABSOLUTE_ZERO_MILLI, 0).get("ok", true)), "the grade mapping rejects an absolute-zero neutral")
	var too_cold: Dictionary = climate.duplicate(true)
	too_cold.regions.home.base_tenths = -1000
	too_cold.regions.home.daily_curve = [[0, -1000], [1440, -1000]]
	too_cold.regions.home.seasonal_curve = [[0, -732], [360, -732]]
	runner.assert_true(Climate.valid_definitions(too_cold), "a cold but structurally valid climate can be below the thermal neutral domain")
	runner.assert_eq(_segment(too_cold, weather, 0).get("reason"), "neutral_out_of_range", "below-absolute-zero background fails instead of being clamped")
	too_cold.regions.home.seasonal_curve = [[0, -731], [360, -731]]
	var near_floor: Dictionary = _segment(too_cold, weather, 0, 0, 0)
	runner.assert_eq(near_floor.get("target_c"), -273.1, "a representable neutral just above absolute zero remains valid")
	var last: Dictionary = _segment(climate, weather, Response.MAX_TIME - 1, 1_000, 0, Response.MAX_TIME, Response.MAX_TIME, Response.MAX_TAU_MS)
	runner.assert_true(bool(last.get("ok", false)), "the final representable millisecond has a usable segment")
	if bool(last.get("ok", false)):
		runner.assert_eq(last.until_ms, Response.MAX_TIME, "the explicit final horizon is retained without grid overflow")
	var last_grid: Dictionary = _segment(climate, weather, Response.MAX_TIME - 1, 1_000, 0, 2, Response.MAX_TIME)
	runner.assert_eq(last_grid.get("until_ms"), Response.MAX_TIME, "a coincident final grid point remains representable")


func _invalid_inputs(runner: Object) -> void:
	var climate: Dictionary = _climate()
	var weather: Dictionary = _weather()
	var before_climate: Dictionary = climate.duplicate(true)
	var before_weather: Dictionary = weather.duplicate(true)
	var state := State.new()
	state.configure(Vector2i(1, 1), 1, 0)
	var initial: Dictionary = _segment(climate, weather, 0)
	if not bool(initial.get("ok", false)) or not bool(_apply(state, initial, 0, 20.0).get("ok", false)):
		runner.assert_true(false, "a valid initial state is available for rejection checks")
		return
	var before_state: Dictionary = state.snapshot()
	var bad: Array[Dictionary] = [
		_segment(climate, weather, -1),
		_segment(climate, weather, Response.MAX_TIME, 0, 0, 1, Response.MAX_TIME),
		_segment(climate, weather, 0, -1),
		_segment(climate, weather, 0, Rules.MAX_GRADE_MILLI + 1),
		_segment(climate, weather, 0, 0, -1),
		_segment(climate, weather, 0, 0, Rules.MAX_GRADE_MILLI + 1),
		_segment(climate, weather, 0, 0, 0, 0),
		_segment(climate, weather, 0, 0, 0, Response.MAX_TIME + 1),
		_segment(climate, weather, 0, 0, 0, 1, 0),
		_segment(climate, weather, 0, 0, 0, 1, Response.MAX_TIME + 1),
		_segment(climate, weather, 0, 0, 0, 1, 1, 0),
		_segment(climate, weather, 0, 0, 0, 1, 1, Response.MAX_TAU_MS + 1),
		_segment(climate, weather, 0, 0, 0, 1, 1, 1, -1),
		_segment(climate, weather, 0, 0, 0, 1, 1, 1, Tide.MAX_TIME + 1),
	]
	for result: Dictionary in bad:
		runner.assert_true(not bool(result.get("ok", true)) and result.get("reason") is String, "an invalid scalar returns an explicit failure")
	var malformed: Dictionary = climate.duplicate(true)
	malformed.calendar.erase("start_minutes")
	var malformed_before: Dictionary = malformed.duplicate(true)
	bad.append(_segment(malformed, weather, 0))
	runner.assert_eq(malformed, malformed_before, "rejection also preserves the malformed climate input")
	malformed = climate.duplicate(true)
	malformed.regions.home.bounds = [0, 0]
	bad.append(_segment(malformed, weather, 0))
	malformed = climate.duplicate(true)
	malformed.regions.home.erase("daily_curve")
	bad.append(_segment(malformed, weather, 0))
	malformed = climate.duplicate(true)
	malformed.regions.home.daily_curve = [[0, 0], [0, 1], [1440, 0]]
	bad.append(_segment(malformed, weather, 0))
	malformed = climate.duplicate(true)
	malformed.regions.home.weather_offsets.erase("rain")
	bad.append(_segment(malformed, weather, 0))
	var bad_weather: Dictionary = weather.duplicate(true)
	bad_weather.regions.erase("home")
	var bad_weather_before: Dictionary = bad_weather.duplicate(true)
	bad.append(_segment(climate, bad_weather, 0))
	runner.assert_eq(bad_weather, bad_weather_before, "rejection also preserves the malformed weather input")
	bad_weather = weather.duplicate(true)
	bad_weather.erase("phases")
	bad.append(_segment(climate, bad_weather, 0))
	bad_weather = weather.duplicate(true)
	bad_weather.phases[0].duration_ms = 0
	bad.append(_segment(climate, bad_weather, 0))
	bad_weather = weather.duplicate(true)
	bad_weather.phases[0].erase("kind")
	bad.append(_segment(climate, bad_weather, 0))
	for result: Dictionary in bad:
		runner.assert_true(not bool(result.get("ok", true)), "malformed inputs never produce a plausible temperature")
	runner.assert_eq(climate, before_climate, "compiling never mutates bound climate definitions")
	runner.assert_eq(weather, before_weather, "compiling never mutates bound weather definitions")
	runner.assert_eq(state.snapshot(), before_state, "rejected compilations cannot change the actual-temperature owner")


func _field_state_and_restart(runner: Object) -> void:
	var climate: Dictionary = _climate()
	var weather: Dictionary = _weather()
	climate.regions.home.daily_curve = [[0, 0], [1, 2], [2, 2], [3, 0], [1440, 0]]
	var field := Index.new()
	var control := State.new()
	var queried := State.new()
	runner.assert_true(field.configure(Vector2i(2, 2), 2) and control.configure(Vector2i(2, 2), 1, 0) and queried.configure(Vector2i(2, 2), 1, 0), "the real field and two actual-temperature owners configure")
	var hot: Array[int] = [0, 0, 0, 0, 0, 12_000, 0]
	var cold: Array[int] = [0, 0, 0, 0, 0, 0, 3_000]
	if not bool(field.set_source({"id": "hot", "cell": CELL, "radius": 1, "channels": hot}).get("ok", false)) or not bool(field.set_source({"id": "cold", "cell": CELL, "radius": 1, "channels": cold}).get("ok", false)):
		runner.assert_true(false, "the real indexed hot and cold sources are available")
		return
	var base: Dictionary = field.sample_base(CELL)
	if not bool(base.get("ok", false)):
		runner.assert_true(false, "the field exposes its effective grades")
		return
	runner.assert_eq(base.channels[5], 12_000, "the compiler consumes the real indexed hot grade")
	runner.assert_eq(base.channels[6], 3_000, "the compiler consumes the real indexed cold grade")
	var at_ms: int = 0
	var boundaries: Array[int] = []
	while at_ms < 100_000:
		var segment: Dictionary = _segment(climate, weather, at_ms, int(base.channels[5]), int(base.channels[6]))
		if not bool(segment.get("ok", false)):
			runner.assert_true(false, "each real rule segment compiles")
			return
		var old_control: Dictionary = {} if at_ms == 0 else control.actual_at(CELL, at_ms)
		var old_queried: Dictionary = {} if at_ms == 0 else queried.actual_at(CELL, at_ms)
		var initial: Variant = 20.0 if at_ms == 0 else null
		if not bool(_apply(control, segment, at_ms, initial).get("ok", false)) or not bool(_apply(queried, segment, at_ms, initial).get("ok", false)):
			runner.assert_true(false, "both owners commit each true target boundary")
			return
		if at_ms != 0:
			runner.assert_eq(control.actual_at(CELL, at_ms), old_control, "replacing a target preserves the old actual value at the boundary")
			runner.assert_eq(queried.actual_at(CELL, at_ms), old_queried, "extra queries do not change boundary continuity")
		var before: Dictionary = queried.snapshot()
		var end: int = int(segment.until_ms)
		@warning_ignore("integer_division")
		var middle: int = at_ms + (end - at_ms) / 2
		queried.actual_at(CELL, middle)
		queried.actual_at(CELL, at_ms)
		queried.actual_at(CELL, middle)
		runner.assert_eq(queried.snapshot(), before, "mid-segment queries do not create new anchors")
		if at_ms == 30_000:
			var saved: Variant = JSON.parse_string(JSON.stringify(before, "", true, true))
			var restored := State.new()
			if not restored.restore(saved):
				runner.assert_true(false, "full-precision JSON restores the active segment")
				return
			queried = restored
			runner.assert_eq(queried.actual_at(CELL, middle), control.actual_at(CELL, middle), "a mid-segment restart has the same future")
		runner.assert_eq(queried.actual_at(CELL, end), control.actual_at(CELL, end), "external query partitioning and restart preserve each future boundary")
		boundaries.append(end)
		at_ms = end
	runner.assert_eq(boundaries, [20_000, 30_000, 40_000, 60_000, 65_000, 80_000, 100_000], "integration crosses the intended global-grid, climate, weather and horizon boundaries")
