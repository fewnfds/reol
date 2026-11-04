extends RefCounted
## Geometric known points and symmetry check the pure rule independently.

const Solar = preload("res://scripts/sim/solar_rules.gd")
const Calendar = preload("res://scripts/sim/world_calendar.gd")
const HOUR_MS: int = 3600000
const DAY_MS: int = 86400000
const NOON_MS: int = 43200000
const YEAR_MS: int = 360 * DAY_MS


func run(runner: Object) -> void:
	_defaults_and_boundaries(runner)
	_known_geometric_points(runner)
	_seasons_and_hemispheres(runner)
	_poles_and_tangencies(runner)
	_twilight_weather_and_roof(runner)
	_longitude_calendar_and_large_time(runner)
	_purity_and_rejection(runner)
	print("SCENARIO solar rules: equatorial and midlatitude geometric known points, seasonal and north/south symmetry, poles and tangent horizons, diffuse twilight, shared weather transmission, bound calendar/longitude phases, safe-integer time and pure rejected queries")


func _calendar(start_minutes: int = 0) -> Dictionary:
	return {"version": 1, "days_per_month": 30, "months_per_year": 12,
		"seasons": ["spring", "summer", "autumn", "winter"], "start_minutes": start_minutes}


func _rules(latitude: int = 30000, tilt: int = 23500) -> Dictionary:
	var rules: Dictionary = Solar.migration_defaults()
	rules.latitude_mdeg = latitude
	rules.axial_tilt_mdeg = tilt
	return rules


func _noon(day: int) -> int:
	return day * DAY_MS + NOON_MS


func _without_time(query: Dictionary) -> Dictionary:
	var result: Dictionary = query.duplicate(true)
	result.erase("at_ms")
	return result


func _near(runner: Object, actual: int, expected: int, tolerance: int, label: String) -> void:
	runner.assert_true(absi(actual - expected) <= tolerance, "%s: expected %d ± %d, got %d" % [label, expected, tolerance, actual])


func _defaults_and_boundaries(runner: Object) -> void:
	var expected: Dictionary = {"latitude_mdeg": 30000, "longitude_mdeg": 0, "meridian_mdeg": 0,
		"axial_tilt_mdeg": 23500, "vernal_day": 0, "relative_scale": 10000,
		"clear_transmission": 10000, "rain_transmission": 4500, "roof_transmission": 1000}
	var rules: Dictionary = Solar.migration_defaults()
	runner.assert_eq(rules, expected, "historical defaults have the agreed complete fixed values")
	runner.assert_true(Solar.valid_definitions(rules), "the fixed defaults are valid solar content")
	rules.latitude_mdeg = -90000
	runner.assert_eq(Solar.migration_defaults(), expected, "mutating one returned default cannot change later worlds")
	for latitude: int in [-90000, 0, 90000]:
		for tilt: int in [0, 45000]:
			var edge: Dictionary = _rules(latitude, tilt)
			edge.longitude_mdeg = -180000
			edge.meridian_mdeg = 180000
			edge.relative_scale = 1
			edge.clear_transmission = 0
			edge.rain_transmission = 10000
			edge.roof_transmission = 0
			runner.assert_true(Solar.valid_definitions(edge) and not Solar.sample(_calendar(), edge, 0).is_empty(), "declared geometric and transmission endpoints remain valid")
	var largest_scale: Dictionary = _rules(0, 0)
	largest_scale.relative_scale = 1000000
	var bright: Dictionary = Solar.sample(_calendar(), largest_scale, NOON_MS)
	runner.assert_eq(bright.total_relative, 1000000, "the largest relative scale remains exact at zenith")


func _known_geometric_points(runner: Object) -> void:
	# At the equator, every nondegenerate declination has exactly 12h above
	# the geometric horizon. At local noon, altitude = 90° - |latitude - δ|.
	var calendar: Dictionary = _calendar()
	for row: Array in [[0, 0, 90000], [90, 23500, 66500], [180, 0, 90000], [270, -23500, 66500]]:
		var query: Dictionary = Solar.sample(calendar, _rules(0), _noon(int(row[0])))
		runner.assert_eq(query.declination_mdeg, row[1], "the four independent seasonal anchors have the expected declination")
		_near(runner, int(query.elevation_mdeg), int(row[2]), 1, "equatorial solar-noon altitude follows the known geometric angle")
		runner.assert_eq(query.daylight_ms, NOON_MS, "the equator retains twelve geometric daylight hours in all four seasons")
		runner.assert_eq(query.polar_state, "none", "equatorial days are never polar")
	var temperate: Dictionary = Solar.sample(calendar, _rules(30000), NOON_MS)
	runner.assert_eq(temperate.elevation_mdeg, 60000, "30° north has 60° noon altitude at the equinox")
	var equator: Dictionary = _rules(0, 0)
	for row: Array in [[0, -90000], [6, 0], [12, 90000], [18, 0]]:
		var query: Dictionary = Solar.sample(calendar, equator, int(row[0]) * HOUR_MS)
		runner.assert_eq(query.elevation_mdeg, row[1], "untilted equatorial cardinal hours give independently known elevation")
		if int(row[0]) in [6, 18]:
			runner.assert_eq(query.direct_relative, 0, "the geometric horizon has no direct projected illumination")
			runner.assert_true(int(query.diffuse_relative) > 0, "a horizon Sun still supplies diffuse daylight")


func _seasons_and_hemispheres(runner: Object) -> void:
	var calendar: Dictionary = _calendar()
	var north: Dictionary = _rules(45000)
	var south: Dictionary = _rules(-45000)
	var summer: Dictionary = Solar.sample(calendar, north, _noon(90))
	var winter: Dictionary = Solar.sample(calendar, north, _noon(270))
	runner.assert_eq(summer.elevation_mdeg, 68500, "45° north summer-solstice noon altitude is 68.5°")
	runner.assert_eq(winter.elevation_mdeg, 21500, "45° north winter-solstice noon altitude is 21.5°")
	# Standard ideal 23.5°-tilt geometry at 45° has about 15h26m / 8h34m.
	_near(runner, int(summer.daylight_ms), 15 * HOUR_MS + 26 * 60000, 2 * 60000, "midlatitude summer day agrees with the known ideal duration")
	_near(runner, int(winter.daylight_ms), 8 * HOUR_MS + 34 * 60000, 2 * 60000, "midlatitude winter day agrees with the known ideal duration")
	_near(runner, int(summer.daylight_ms) + int(winter.daylight_ms), DAY_MS, 1, "opposite seasonal daylight complements one full day")
	for day: int in [0, 30, 90, 180, 270, 359]:
		var northern: Dictionary = Solar.sample(calendar, north, _noon(day))
		var southern: Dictionary = Solar.sample(calendar, south, _noon(day))
		_near(runner, int(northern.daylight_ms) + int(southern.daylight_ms), DAY_MS, 1, "same-instant north/south daylight complements the same rotation")
	var south_summer: Dictionary = Solar.sample(calendar, south, _noon(270))
	runner.assert_eq(south_summer.daylight_ms, summer.daylight_ms, "opposite hemispheres exchange solstice day length")
	runner.assert_eq(south_summer.elevation_mdeg, summer.elevation_mdeg, "opposite hemispheres exchange solstice noon elevation")
	var shifted: Dictionary = _rules(45000)
	shifted.vernal_day = 17
	var shifted_equinox: Dictionary = Solar.sample(calendar, shifted, _noon(17))
	runner.assert_eq(shifted_equinox.declination_mdeg, 0, "the bound vernal-day civil noon controls the seasonal anchor")
	runner.assert_eq(shifted_equinox.daylight_ms, NOON_MS, "moving the equinox changes phase without inventing another calendar")


func _poles_and_tangencies(runner: Object) -> void:
	var calendar: Dictionary = _calendar()
	for pole: int in [-90000, 90000]:
		for day: int in [90, 270]:
			var query: Dictionary = Solar.sample(calendar, _rules(pole), _noon(day))
			var summer: bool = (pole > 0) == (day == 90)
			runner.assert_eq(query.polar_state, "day" if summer else "night", "each pole has the correct solstitial polar state")
			runner.assert_eq(query.daylight_ms, DAY_MS if summer else 0, "polar day/night gives a finite full/zero daylight duration")
			runner.assert_eq(query.elevation_mdeg, 23500 if summer else -23500, "the solstitial polar Sun has the known tilt elevation")
		var equinox: Dictionary = Solar.sample(calendar, _rules(pole), NOON_MS)
		runner.assert_eq(equinox.elevation_mdeg, 0, "the ideal pole/equinox path stays at the horizon without NaN")
		runner.assert_eq(equinox.daylight_ms, NOON_MS, "the degenerate horizon path uses the documented equinoctial limit")
	for latitude: int in [66499, 66500, 66501]:
		var rules: Dictionary = _rules(latitude)
		rules.longitude_mdeg = 180000
		var midnight_summer: Dictionary = Solar.sample(calendar, rules, _noon(90))
		runner.assert_eq(midnight_summer.elevation_mdeg, latitude - 66500, "the exact polar-circle midnight tangent is stable to one millidegree")
		runner.assert_eq(midnight_summer.polar_state, "none" if latitude < 66500 else "day", "the summer polar-circle limit avoids acos outside its domain")
		rules.longitude_mdeg = 0
		var noon_winter: Dictionary = Solar.sample(calendar, rules, _noon(270))
		runner.assert_eq(noon_winter.elevation_mdeg, 66500 - latitude, "winter tangent elevation has the opposite sign")
		runner.assert_eq(noon_winter.polar_state, "none" if latitude < 66500 else "night", "the winter polar-circle limit remains finite")
	for latitude: int in [-90000, -89999, 89999, 90000]:
		var zero_tilt: Dictionary = Solar.sample(calendar, _rules(latitude, 0), NOON_MS)
		runner.assert_eq(zero_tilt.daylight_ms, NOON_MS, "zero obliquity has stable equinoctial daylight near both poles")


func _twilight_weather_and_roof(runner: Object) -> void:
	var calendar: Dictionary = _calendar()
	var rules: Dictionary = _rules(0, 0)
	for row: Array in [[5 * HOUR_MS + 48 * 60000, "dawn"], [18 * HOUR_MS + 12 * 60000, "dusk"]]:
		var query: Dictionary = Solar.sample(calendar, rules, int(row[0]))
		runner.assert_eq(query.elevation_mdeg, -3000, "twelve equatorial minutes below the horizon gives -3° elevation")
		runner.assert_eq(query.sky_phase, row[1], "morning and evening twilight retain their distinct qualitative phases")
		runner.assert_eq(query.direct_relative, 0, "below-horizon twilight has no invented direct Sun")
		runner.assert_true(int(query.diffuse_relative) > 0 and int(query.total_relative) == int(query.diffuse_relative), "twilight carries weak diffuse natural light")
	var after_sunset: Dictionary = Solar.sample(calendar, rules, 18 * HOUR_MS + 1)
	runner.assert_true(after_sunset.sky_phase == "dusk" and int(after_sunset.total_relative) > 0, "sunset does not make the sky instantly black")
	var deep_night: Dictionary = Solar.sample(calendar, rules, 0)
	runner.assert_eq(deep_night.sky_phase, "night", "the untilted midnight sky is night")
	runner.assert_eq(deep_night.total_relative, 0, "no moon or artificial light is silently introduced into deep night")
	var clear: Dictionary = Solar.sample(calendar, rules, NOON_MS)
	var rain: Dictionary = Solar.sample(calendar, rules, NOON_MS, "rain")
	runner.assert_eq(clear.total_relative, 10000, "clear equatorial zenith reaches the declared relative scale")
	runner.assert_eq(rain.direct_relative, 3600, "rain transmits the direct component through the declared shared ratio")
	runner.assert_eq(rain.diffuse_relative, 900, "rain uses that same ratio for diffuse light")
	runner.assert_eq(rain.total_relative, int(rain.direct_relative) + int(rain.diffuse_relative), "total natural illumination is the sum of its two components")
	var roofless: Dictionary = rules.duplicate(true)
	roofless.roof_transmission = 10000
	var roofed: Dictionary = rules.duplicate(true)
	roofed.roof_transmission = 0
	runner.assert_eq(Solar.sample(calendar, roofless, NOON_MS).total_relative, Solar.sample(calendar, roofed, NOON_MS).total_relative, "pure outdoor sunlight leaves roof attenuation to the local original-structure query")
	var opaque: Dictionary = rules.duplicate(true)
	opaque.clear_transmission = 0
	var dark_day: Dictionary = Solar.sample(calendar, opaque, NOON_MS)
	runner.assert_eq(dark_day.total_relative, 0, "zero transmission blocks both natural-light components")
	runner.assert_eq(dark_day.sky_phase, "day", "weather darkness does not rewrite the geometric day phase")
	var rainy_dusk: Dictionary = Solar.sample(calendar, rules, 18 * HOUR_MS + 12 * 60000, "rain")
	runner.assert_eq(rainy_dusk.diffuse_relative, 45, "below-horizon diffuse light uses the same rain transmission as daytime")
	runner.assert_eq(Solar.sample(calendar, rules, 5 * HOUR_MS + 35 * 60000).total_relative, 0, "the pre-civil-twilight Sun supplies no invented diffuse light")
	runner.assert_true(not Solar.label(after_sunset).is_empty() and Solar.label({}) == "天光不明", "optional labels remain qualitative and handle an unavailable query")


func _longitude_calendar_and_large_time(runner: Object) -> void:
	var calendar: Dictionary = _calendar()
	var rules: Dictionary = _rules(0, 0)
	rules.longitude_mdeg = 30000
	var eastern: Dictionary = Solar.sample(calendar, rules, 23 * HOUR_MS)
	runner.assert_eq(eastern.solar_time_ms, HOUR_MS, "30° east adds two solar hours across midnight")
	rules.longitude_mdeg = -15000
	runner.assert_eq(Solar.sample(calendar, rules, 0).solar_time_ms, 23 * HOUR_MS, "15° west subtracts one solar hour across the previous day")
	rules.meridian_mdeg = -15000
	runner.assert_eq(Solar.sample(calendar, rules, 0).solar_time_ms, 0, "longitude equal to the standard meridian has no solar-time offset")
	rules.longitude_mdeg = 180000
	rules.meridian_mdeg = -180000
	runner.assert_eq(Solar.sample(calendar, rules, 0).solar_time_ms, 0, "the full longitude difference is reduced without a negative or oversized time")
	rules.axial_tilt_mdeg = 23500
	var eastern_season: Dictionary = Solar.sample(calendar, rules, _noon(90))
	runner.assert_eq(eastern_season.declination_mdeg, 23500, "longitude cannot change the same instant's global solar declination")
	rules.longitude_mdeg = -12000
	rules.meridian_mdeg = 40000
	var shifted_season: Dictionary = Solar.sample(calendar, rules, _noon(90))
	runner.assert_eq(shifted_season.declination_mdeg, eastern_season.declination_mdeg, "different longitude shifts only solar time, keeping the same instant's season")
	runner.assert_true(shifted_season.solar_time_ms != eastern_season.solar_time_ms, "the seasonal comparison actually uses different local solar hours")
	var bound: Dictionary = _calendar(480)
	var default_rules: Dictionary = Solar.migration_defaults()
	runner.assert_eq(Solar.sample(bound, default_rules, 0).solar_time_ms, 8 * HOUR_MS, "the calendar's civil opening hour is part of the original time projection")
	var short_year: Dictionary = _calendar()
	short_year.days_per_month = 20
	short_year.months_per_year = 8
	runner.assert_eq(Solar.sample(short_year, default_rules, _noon(40)).declination_mdeg, 23500, "a bound 160-day year reaches the solstice on its own fortieth day")
	runner.assert_eq(Solar.sample(short_year, default_rules, _noon(120)).declination_mdeg, -23500, "a changed year length controls the opposite solstice without an installed 360-day assumption")
	var largest: Dictionary = Solar.sample(bound, default_rules, Calendar.MAX_TIMESTAMP)
	var reduced: Dictionary = Solar.sample(bound, default_rules, posmod(Calendar.MAX_TIMESTAMP, YEAR_MS))
	runner.assert_eq(_without_time(largest), _without_time(reduced), "maximum JSON-safe time is reduced as integers before all astronomical floats")
	var preceding: Dictionary = Solar.sample(bound, default_rules, Calendar.MAX_TIMESTAMP - 1)
	runner.assert_eq(largest.solar_time_ms, posmod(int(preceding.solar_time_ms) + 1, DAY_MS), "the largest supported timestamp retains its final millisecond")
	for at_ms: int in [0, 1, 6 * HOUR_MS, _noon(90), YEAR_MS - 1]:
		var first: Dictionary = Solar.sample(calendar, default_rules, at_ms)
		var next_year: Dictionary = Solar.sample(calendar, default_rules, at_ms + YEAR_MS)
		runner.assert_eq(_without_time(first), _without_time(next_year), "the same local season and hour recur exactly across the year ring")
	var before_midnight: Dictionary = Solar.sample(calendar, default_rules, YEAR_MS - 1)
	var after_midnight: Dictionary = Solar.sample(calendar, default_rules, YEAR_MS)
	_near(runner, int(before_midnight.declination_mdeg), int(after_midnight.declination_mdeg), 1, "declination stays continuous across civil midnight and the year seam")
	runner.assert_eq(before_midnight.total_relative, after_midnight.total_relative, "midnight does not introduce a spurious light discontinuity")


func _purity_and_rejection(runner: Object) -> void:
	var calendar: Dictionary = _calendar(480)
	var rules: Dictionary = Solar.migration_defaults()
	var before: String = var_to_str({"calendar": calendar, "solar": rules})
	var query: Dictionary = Solar.sample(calendar, rules, 1234567)
	for _repeat: int in range(4):
		runner.assert_eq(Solar.sample(calendar, rules, 1234567), query, "same bound definitions and original instant always produce the same query")
	runner.assert_eq(var_to_str({"calendar": calendar, "solar": rules}), before, "queries and labels own no mutable world clock or input state")
	for value: Variant in [null, [], "solar", {}, {"latitude_mdeg": 30000}]:
		runner.assert_true(not Solar.valid_definitions(value), "solar definition shape is explicit and complete")
	var faults: Array = [["latitude_mdeg", -90001], ["latitude_mdeg", 90001], ["longitude_mdeg", -180001],
		["meridian_mdeg", 180001], ["axial_tilt_mdeg", -1], ["axial_tilt_mdeg", 45001],
		["vernal_day", -1], ["vernal_day", Calendar.MAX_TIMESTAMP + 1], ["relative_scale", 0], ["relative_scale", 1000001],
		["clear_transmission", -1], ["rain_transmission", 10001], ["roof_transmission", 0.5],
		["latitude_mdeg", INF], ["latitude_mdeg", NAN], ["longitude_mdeg", true], ["relative_scale", "10000"]]
	for fault: Array in faults:
		var bad: Dictionary = rules.duplicate(true)
		bad[fault[0]] = fault[1]
		var original: String = var_to_str(bad)
		runner.assert_true(not Solar.valid_definitions(bad) and Solar.sample(calendar, bad, 0).is_empty(), "invalid solar numeric content rejects before trigonometry: " + str(fault))
		runner.assert_eq(var_to_str(bad), original, "invalid queries never repair the supplied solar content")
	var extra: Dictionary = rules.duplicate(true)
	extra["unexpected"] = 1
	runner.assert_true(not Solar.valid_definitions(extra), "unknown solar fields are rejected")
	var missing: Dictionary = rules.duplicate(true)
	missing.erase("roof_transmission")
	runner.assert_true(not Solar.valid_definitions(missing), "missing transmission fields are rejected")
	var outside_year: Dictionary = rules.duplicate(true)
	outside_year.vernal_day = 360
	runner.assert_true(Solar.valid_definitions(outside_year) and Solar.sample(calendar, outside_year, 0).is_empty(), "solar-only validation defers vernal-day cross-validation to the bound calendar")
	for fault: Array in [["version", 2], ["days_per_month", 0], ["months_per_year", 25], ["start_minutes", 1440], ["seasons", []]]:
		var bad_calendar: Dictionary = calendar.duplicate(true)
		bad_calendar[fault[0]] = fault[1]
		runner.assert_true(Solar.sample(bad_calendar, rules, 0).is_empty(), "invalid bound calendar rejects without scanning other content")
	for at_ms: int in [-1, Calendar.MAX_TIMESTAMP + 1]:
		runner.assert_true(Solar.sample(calendar, rules, at_ms).is_empty(), "unsupported original time is rejected")
	for weather: String in ["", "snow", "Clear"]:
		runner.assert_true(Solar.sample(calendar, rules, 0, weather).is_empty(), "unknown weather cannot silently assume clear transmission")
	var json_rules: Dictionary = JSON.parse_string(JSON.stringify(rules, "", true, true))
	var json_calendar: Dictionary = JSON.parse_string(JSON.stringify(calendar, "", true, true))
	runner.assert_true(Solar.valid_definitions(json_rules), "JSON integral numeric definitions remain valid")
	runner.assert_eq(Solar.sample(json_calendar, json_rules, 1234567), query, "JSON integral values retain exactly the same derived sunlight")
