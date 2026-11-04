extends RefCounted
## Pure millisecond background and phase queries; no scheduler is advanced.

const Climate = preload("res://scripts/sim/climate_rules.gd")
const Weather = preload("res://scripts/sim/weather.gd")
const DAY_MS: int = 86400000
const FUTURE_EPOCH: int = 200000000


func run(runner: Object) -> void:
	_default_background(runner)
	_daily_segments(runner)
	_fast_and_fractional_changes(runner)
	_season_and_cancellation(runner)
	_weather_phases(runner)
	_invalid_and_limits(runner)
	print("SCENARIO climate boundaries: pure background, integer curve thresholds, phase epochs, periodic wrap and bounded timestamps")


func _climate() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/climate.json"))


func _weather() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/weather.json"))


func _controlled_climate() -> Dictionary:
	var rules: Dictionary = _climate()
	rules.calendar.start_minutes = 0
	for region: Dictionary in rules.regions.values():
		region.daily_curve = [[0, 0], [1440, 0]]
		region.seasonal_curve = [[0, 0], [360, 0]]
		region.weather_offsets.rain = 0
	return rules


func _controlled_weather() -> Dictionary:
	var rules: Dictionary = _weather()
	rules.phases = [{"kind": "clear", "duration_ms": DAY_MS}]
	for region: Dictionary in rules.regions.values():
		region.offset_ms = 0
	return rules


func _json(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _default_background(runner: Object) -> void:
	var rules: Dictionary = _climate()
	var weather: Dictionary = _weather()
	var rules_before: String = _json(rules)
	var weather_before: String = _json(weather)
	for example: Dictionary in [
		{"cell": Vector2i(100, 100), "region": "home", "boundary": 392728},
		{"cell": Vector2i(300, 100), "region": "river", "boundary": 308572},
	]:
		var cell: Vector2i = example.cell
		var region: String = example.region
		var boundary: int = int(example.boundary)
		var opening: Dictionary = Climate.background_at(rules, weather, 0, cell, 0)
		var direct: Dictionary = Climate.background_for_region(rules, weather, 0, region, 0)
		runner.assert_eq(opening, direct, "cell and explicit-region lookup use the same original background: " + region)
		runner.assert_eq(opening.get("region"), region, "the background identifies the real climate region: " + region)
		runner.assert_eq(opening.get("kind"), Weather.kind_at(weather, region, 0, 0), "the background uses the original weather epoch: " + region)
		runner.assert_eq(opening.get("temperature_tenths"), Climate.temperature_at(rules, region, 0, str(opening.get("kind"))), "the background uses the original climate projection: " + region)
		runner.assert_eq(Climate.next_background_boundary_ms(rules, weather, 0, region, 0), boundary, "the first actual default component boundary is not rounded to a minute: " + region)
		runner.assert_eq(Climate.next_background_boundary_ms(rules, weather, 0, region, boundary - 1), boundary, "the next boundary remains exact one millisecond before it: " + region)
		var before: Dictionary = Climate.background_for_region(rules, weather, 0, region, boundary - 1)
		var after: Dictionary = Climate.background_for_region(rules, weather, 0, region, boundary)
		runner.assert_eq(int(after.get("temperature_tenths")) - int(before.get("temperature_tenths")), 1, "the default rising component changes at the returned millisecond: " + region)
		runner.assert_true(Climate.next_background_boundary_ms(rules, weather, 0, region, boundary) > boundary, "the boundary query is strictly future: " + region)
	var fallback: Dictionary = Climate.background_at(rules, weather, 0, Vector2i(-1, -1), 0)
	runner.assert_eq(fallback, Climate.background_for_region(rules, weather, 0, str(rules.fallback_region), 0), "a cell outside every region retains the original fallback region")
	runner.assert_eq(_json(rules), rules_before, "background and boundary reads never alter climate definitions")
	runner.assert_eq(_json(weather), weather_before, "background and boundary reads never alter weather definitions")


func _daily_segments(runner: Object) -> void:
	var rules: Dictionary = _controlled_climate()
	var weather: Dictionary = _controlled_weather()
	rules.regions.home.daily_curve = [[0, 0], [1, 2], [2, 2], [3, 0], [1440, 0]]
	runner.assert_true(Climate.valid_definitions(rules) and Weather.valid_definitions(weather), "the rising, flat and falling daily example uses valid bound definitions")
	for example: Array in [[0, 30000], [29999, 30000], [30000, 60000], [60000, 150000], [149999, 150000], [150000, 180000], [180000, DAY_MS + 30000], [DAY_MS - 1, DAY_MS + 30000]]:
		runner.assert_eq(Climate.next_background_boundary_ms(rules, weather, FUTURE_EPOCH, "home", int(example[0])), int(example[1]), "the next daily threshold skips flat spans and wraps correctly at %dms" % int(example[0]))
	for example: Array in [[30000, 1], [60000, 1], [150000, -1], [180000, -1], [DAY_MS + 30000, 1]]:
		var boundary: int = int(example[0])
		var before: Dictionary = Climate.background_for_region(rules, weather, FUTURE_EPOCH, "home", boundary - 1)
		var after: Dictionary = Climate.background_for_region(rules, weather, FUTURE_EPOCH, "home", boundary)
		runner.assert_eq(int(after.get("temperature_tenths")) - int(before.get("temperature_tenths")), int(example[1]), "daily interpolation changes only at its integer threshold %dms" % boundary)


func _fast_and_fractional_changes(runner: Object) -> void:
	var rules: Dictionary = _controlled_climate()
	var weather: Dictionary = _controlled_weather()
	rules.regions.home.daily_curve = [[0, -1000], [1, 1000], [1440, -1000]]
	runner.assert_true(Climate.valid_definitions(rules), "a fast but valid daily slope stays within the original content limits")
	runner.assert_eq(Climate.next_background_boundary_ms(rules, weather, FUTURE_EPOCH, "home", 0), 30, "a steep rise finds its first 30ms threshold")
	runner.assert_eq(Climate.next_background_boundary_ms(rules, weather, FUTURE_EPOCH, "home", 30), 60, "a steep rise finds its next threshold without scanning milliseconds")
	var before: Dictionary = Climate.background_for_region(rules, weather, FUTURE_EPOCH, "home", 29)
	var after: Dictionary = Climate.background_for_region(rules, weather, FUTURE_EPOCH, "home", 30)
	runner.assert_eq(int(after.temperature_tenths) - int(before.temperature_tenths), 1, "a fast positive slope changes at the returned threshold")
	rules.regions.home.daily_curve = [[0, 1000], [1, -1000], [1440, 1000]]
	runner.assert_eq(Climate.next_background_boundary_ms(rules, weather, FUTURE_EPOCH, "home", 0), 30, "a fast negative slope uses the same magnitude threshold")
	before = Climate.background_for_region(rules, weather, FUTURE_EPOCH, "home", 29)
	after = Climate.background_for_region(rules, weather, FUTURE_EPOCH, "home", 30)
	runner.assert_eq(int(after.temperature_tenths) - int(before.temperature_tenths), -1, "a negative slope follows integer truncation toward zero")
	rules.regions.home.daily_curve = [[0, 0], [1, 7], [2, 0], [1440, 0]]
	runner.assert_eq(Climate.next_background_boundary_ms(rules, weather, FUTURE_EPOCH, "home", 0), 8572, "the first nonintegral threshold uses integer ceiling")
	runner.assert_eq(Climate.next_background_boundary_ms(rules, weather, FUTURE_EPOCH, "home", 8572), 17143, "subsequent nonintegral thresholds do not drift")


func _season_and_cancellation(runner: Object) -> void:
	var rules: Dictionary = _controlled_climate()
	var weather: Dictionary = _controlled_weather()
	rules.regions.home.seasonal_curve = [[0, 0], [1, 2], [360, 0]]
	var first: int = 43200000
	runner.assert_eq(Climate.next_background_boundary_ms(rules, weather, FUTURE_EPOCH, "home", 0), first, "the seasonal component has its own sub-day integer boundary")
	var before: Dictionary = Climate.background_for_region(rules, weather, FUTURE_EPOCH, "home", first - 1)
	var after: Dictionary = Climate.background_for_region(rules, weather, FUTURE_EPOCH, "home", first)
	runner.assert_eq(int(after.temperature_tenths) - int(before.temperature_tenths), 1, "the seasonal value changes at its returned millisecond")
	var year_ms: int = 360 * DAY_MS
	runner.assert_eq(Climate.next_background_boundary_ms(rules, weather, FUTURE_EPOCH, "home", year_ms - 1), year_ms, "the final seasonal threshold is retained across the year wrap")
	rules.regions.home.daily_curve = [[0, 0], [720, -1], [1440, 0]]
	runner.assert_true(Climate.valid_definitions(rules), "opposing daily and seasonal components are both valid")
	runner.assert_eq(Climate.next_background_boundary_ms(rules, weather, FUTURE_EPOCH, "home", 0), first, "coincident component changes are still a declared boundary")
	before = Climate.background_for_region(rules, weather, FUTURE_EPOCH, "home", first - 1)
	after = Climate.background_for_region(rules, weather, FUTURE_EPOCH, "home", first)
	runner.assert_eq(after.temperature_tenths, before.temperature_tenths, "opposite component changes may cancel in total background temperature")


func _weather_phases(runner: Object) -> void:
	var weather: Dictionary = _weather()
	var epoch: int = 12345
	for example: Array in [["home", 1212345, 1812345], ["river", 912345, 1512345]]:
		var region: String = str(example[0])
		var boundary: int = int(example[1])
		runner.assert_eq(Weather.next_phase_boundary_ms(weather, region, epoch, 0), boundary, "a pre-epoch query waits for the real phase start: " + region)
		runner.assert_eq(Weather.next_phase_boundary_ms(weather, region, epoch, epoch), boundary, "the region offset and fractional epoch determine the phase: " + region)
		runner.assert_eq(Weather.next_phase_boundary_ms(weather, region, epoch, boundary - 1), boundary, "the phase boundary is exact to one millisecond: " + region)
		runner.assert_eq(Weather.kind_at(weather, region, epoch, boundary - 1), "clear", "the former phase remains in force just before its boundary: " + region)
		runner.assert_eq(Weather.kind_at(weather, region, epoch, boundary), "rain", "the new phase starts exactly at the boundary: " + region)
		runner.assert_eq(Weather.next_phase_boundary_ms(weather, region, epoch, boundary), int(example[2]), "a phase query at its boundary advances strictly into the next phase: " + region)
	var rules: Dictionary = _controlled_climate()
	var background_boundary: int = Climate.next_background_boundary_ms(rules, weather, epoch, "river", 0)
	runner.assert_eq(background_boundary, 912345, "a flat climate still includes the actual offset weather phase")
	var single: Dictionary = _controlled_weather()
	runner.assert_eq(Weather.next_phase_boundary_ms(single, "home", 0, 0), DAY_MS, "a one-phase cycle has a declared boundary even when its kind repeats")


func _invalid_and_limits(runner: Object) -> void:
	var rules: Dictionary = _climate()
	var weather: Dictionary = _weather()
	var maximum: int = SimInventory.MAX_COUNT
	for time: int in [-1, maximum + 1]:
		runner.assert_true(Climate.background_at(rules, weather, 0, Vector2i(100, 100), time).is_empty(), "invalid query time has no invented background: %d" % time)
		runner.assert_eq(Climate.next_background_boundary_ms(rules, weather, 0, "home", time), maximum, "invalid query time has no next background boundary: %d" % time)
		runner.assert_eq(Weather.next_phase_boundary_ms(weather, "home", 0, time), maximum, "invalid query time has no next weather boundary: %d" % time)
	for epoch: int in [-1, maximum + 1]:
		runner.assert_true(Climate.background_for_region(rules, weather, epoch, "home", 0).is_empty(), "invalid weather epoch has no invented background: %d" % epoch)
		runner.assert_eq(Weather.next_phase_boundary_ms(weather, "home", epoch, 0), maximum, "invalid weather epoch has no next phase: %d" % epoch)
	var incomplete: Dictionary = weather.duplicate(true)
	incomplete.regions.erase("river")
	runner.assert_true(Climate.background_at(rules, incomplete, 0, Vector2i(300, 100), 0).is_empty(), "a missing matching weather region has no background value")
	runner.assert_eq(Climate.next_background_boundary_ms(rules, incomplete, 0, "river", 0), maximum, "a missing matching weather region has no next boundary")
	runner.assert_true(Climate.background_for_region(rules, weather, 0, "unknown", 0).is_empty(), "an unknown explicit region has no background value")
	runner.assert_eq(Weather.next_phase_boundary_ms(weather, "unknown", 0, 0), maximum, "an unknown weather region has no next phase")
	runner.assert_true(not Climate.background_at(rules, weather, 0, Vector2i(100, 100), maximum).is_empty(), "the maximum supported timestamp remains a valid read")
	runner.assert_eq(Climate.next_background_boundary_ms(rules, weather, 0, "home", maximum), maximum, "the maximum timestamp is the saturated background sentinel")
	runner.assert_eq(Climate.next_background_boundary_ms(rules, weather, 0, "home", maximum - 1), maximum, "a next boundary cannot exceed the safe integer maximum")
	runner.assert_eq(Weather.next_phase_boundary_ms(weather, "home", maximum - 1, maximum - 1), maximum, "phase scheduling saturates rather than overflowing near the maximum")
