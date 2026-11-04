extends RefCounted
## Creation-time geography compiles to the existing climate contract.
## These tests do not advance a world or replace persisted climate definitions.

const Geographic = preload("res://scripts/sim/geographic_climate.gd")
const Climate = preload("res://scripts/sim/climate_rules.gd")
const Calendar = preload("res://scripts/sim/world_calendar.gd")
const Weather = preload("res://scripts/sim/weather.gd")
const DAY_MS: int = 86400000
const HOUR_MS: int = 3600000
const CLIMATE_PATH: String = "res://data/definitions/climate.json"
const PROFILE_PATH: String = "res://data/scenarios/world_geography.json"
const WEATHER_PATH: String = "res://data/definitions/weather.json"


func run(runner: Object) -> void:
	var template: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CLIMATE_PATH))
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	var weather: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WEATHER_PATH))
	if not Climate.valid_definitions(template) or not Weather.valid_definitions(weather) or not Geographic.valid_profile(template, profile):
		runner.assert_true(false, "geographic climate fixtures use the actual valid definitions and opening profile")
		return
	_hemispheres_and_poles(runner, template, profile)
	_continentality(runner, template, profile)
	_longitude(runner, template, profile)
	_vernal_phase(runner, template, profile)
	_calendar_lengths(runner, template, profile)
	_rejection_and_ownership(runner, template, profile)
	_boundaries_and_envelopes(runner, template, profile, weather)
	print("SCENARIO geographic climate: hemispheres, equator/poles/tilt, marine lag and continental ranges, longitude, short/long calendars, atomic invalid input, component boundaries and conservative envelopes")


func _with_latitude(template: Dictionary, source: Dictionary, latitude_mdeg: int, continentality: int = 1000) -> Dictionary:
	var profile: Dictionary = source.duplicate(true)
	profile.solar.latitude_mdeg = latitude_mdeg
	for region: Dictionary in profile.regions.values():
		region.continentality_milli = continentality
		region.temperature_offset_tenths = 0
	return Geographic.compile(template, profile)


func _range(curve: Array) -> int:
	var low: int = int(curve[0][1])
	var high: int = low
	for point: Array in curve:
		low = mini(low, int(point[1]))
		high = maxi(high, int(point[1]))
	return high - low


func _peak_day(curve: Array) -> int:
	var day: int = int(curve[0][0])
	var value: int = int(curve[0][1])
	# Ignore the duplicate end point when choosing the first maximum.
	for index: int in range(1, curve.size() - 1):
		if int(curve[index][1]) > value:
			day = int(curve[index][0])
			value = int(curve[index][1])
	return day


func _hemispheres_and_poles(runner: Object, template: Dictionary, profile: Dictionary) -> void:
	var north: Dictionary = _with_latitude(template, profile, 45000)
	var south: Dictionary = _with_latitude(template, profile, -45000)
	var equator: Dictionary = _with_latitude(template, profile, 0)
	var pole: Dictionary = _with_latitude(template, profile, 90000)
	var valid: bool = not north.is_empty() and not south.is_empty() and not equator.is_empty() and not pole.is_empty()
	runner.assert_true(valid, "equatorial, opposite temperate and polar profiles compile")
	if not valid:
		return
	runner.assert_eq(north.regions.home.base_tenths, south.regions.home.base_tenths, "equal north/south latitude has equal baseline with equal local offsets")
	runner.assert_eq(north.regions.home.daily_curve, south.regions.home.daily_curve, "equal north/south latitude retains the same daily cycle")
	var northern: Array = north.regions.home.seasonal_curve
	var southern: Array = south.regions.home.seasonal_curve
	runner.assert_eq(northern.size(), southern.size(), "opposite hemispheres share seasonal sample positions")
	if northern.size() != southern.size():
		return
	for index: int in range(northern.size()):
		runner.assert_eq(int(northern[index][0]), int(southern[index][0]), "hemispheric knots use the same calendar")
		runner.assert_eq(int(northern[index][1]), -int(southern[index][1]), "seasonal contribution reverses at equal north/south latitudes")
	# At the same June/December civil noon, daily/background terms cancel.
	for sample: Array in [[100, true], [280, false]]:
		var at_ms: int = int(sample[0]) * DAY_MS + 12 * HOUR_MS - int(template.calendar.start_minutes) * Calendar.MINUTE_MS
		var warmer: bool = Climate.temperature_at(north, "home", at_ms, "clear") > Climate.temperature_at(south, "home", at_ms, "clear")
		runner.assert_eq(warmer, bool(sample[1]), "north and south exchange warm and cold seasons at the same world time")
	runner.assert_eq(_range(equator.regions.home.seasonal_curve), 0, "this simplified equatorial model has no latitude-driven seasonal term")
	runner.assert_true(_range(equator.regions.home.daily_curve) > 0, "an equatorial opening can still have a daily temperature cycle")
	runner.assert_eq(_range(pole.regions.home.daily_curve), 0, "the ideal pole receives no daily temperature cycle in this model")
	runner.assert_true(int(equator.regions.home.base_tenths) > int(north.regions.home.base_tenths) and int(north.regions.home.base_tenths) > int(pole.regions.home.base_tenths), "equal-offset baselines decrease from equator to pole")
	var untilted_profile: Dictionary = profile.duplicate(true)
	untilted_profile.solar.latitude_mdeg = 45000
	untilted_profile.solar.axial_tilt_mdeg = 0
	var untilted: Dictionary = Geographic.compile(template, untilted_profile)
	runner.assert_true(not untilted.is_empty(), "zero axial tilt is a supported geographic opening")
	if not untilted.is_empty():
		runner.assert_eq(_range(untilted.regions.home.seasonal_curve), 0, "zero tilt removes this model's annual solar term")
		runner.assert_true(_range(untilted.regions.home.daily_curve) > 0, "zero tilt does not erase a temperate daily cycle")


func _continentality(runner: Object, template: Dictionary, profile: Dictionary) -> void:
	var marine: Dictionary = _with_latitude(template, profile, 45000, 0)
	var inland: Dictionary = _with_latitude(template, profile, 45000, 1000)
	var valid: bool = not marine.is_empty() and not inland.is_empty()
	runner.assert_true(valid, "marine and continental profiles compile at the same latitude")
	if not valid:
		return
	runner.assert_eq(marine.regions.home.base_tenths, inland.regions.home.base_tenths, "marine moderation does not silently change the configured local mean")
	runner.assert_true(_range(inland.regions.home.daily_curve) > _range(marine.regions.home.daily_curve), "land has a larger daily range than the moderated coast")
	runner.assert_true(_range(inland.regions.home.seasonal_curve) > _range(marine.regions.home.seasonal_curve), "land has a larger annual range than the moderated coast")
	runner.assert_true(_peak_day(marine.regions.home.seasonal_curve) > _peak_day(inland.regions.home.seasonal_curve), "marine thermal response peaks later than inland at the same northern latitude")


func _longitude(runner: Object, template: Dictionary, profile: Dictionary) -> void:
	var central: Dictionary = profile.duplicate(true)
	central.solar.latitude_mdeg = 45000
	central.solar.longitude_mdeg = 0
	central.solar.meridian_mdeg = 0
	var eastern: Dictionary = central.duplicate(true)
	eastern.solar.longitude_mdeg = 30000
	var west: Dictionary = central.duplicate(true)
	west.solar.longitude_mdeg = -30000
	var meridian: Dictionary = eastern.duplicate(true)
	meridian.solar.meridian_mdeg = 30000
	var base: Dictionary = Geographic.compile(template, central)
	var east: Dictionary = Geographic.compile(template, eastern)
	var western: Dictionary = Geographic.compile(template, west)
	var aligned: Dictionary = Geographic.compile(template, meridian)
	var valid: bool = not base.is_empty() and not east.is_empty() and not western.is_empty() and not aligned.is_empty()
	runner.assert_true(valid, "central, eastern and western longitude profiles compile")
	if not valid:
		return
	for region: String in base.regions:
		runner.assert_eq(east.regions[region].base_tenths, base.regions[region].base_tenths, "longitude alone does not alter annual baseline")
		runner.assert_eq(east.regions[region].seasonal_curve, base.regions[region].seasonal_curve, "longitude alone does not alter annual phase")
		runner.assert_eq(western.regions[region].seasonal_curve, base.regions[region].seasonal_curve, "western longitude also leaves annual phase unchanged")
		runner.assert_eq(aligned.regions[region].daily_curve, base.regions[region].daily_curve, "longitude equal to its meridian has zero solar-time shift")
		for example: Array in [[base, 5, 15], [east, 3, 13], [western, 7, 17]]:
			var selected_climate: Dictionary = example[0]
			var daily_curve: Array = selected_climate.regions[region].daily_curve
			var low_hour: int = int(example[1])
			var high_hour: int = int(example[2])
			var low: int = Climate._sample(daily_curve, low_hour * HOUR_MS, Calendar.MINUTE_MS)
			var high: int = Climate._sample(daily_curve, high_hour * HOUR_MS, Calendar.MINUTE_MS)
			runner.assert_true(low < Climate._sample(daily_curve, posmod((low_hour - 2) * HOUR_MS, DAY_MS), Calendar.MINUTE_MS) and low < Climate._sample(daily_curve, posmod((low_hour + 2) * HOUR_MS, DAY_MS), Calendar.MINUTE_MS), "daily minimum follows local solar 05:00")
			runner.assert_true(high > Climate._sample(daily_curve, posmod((high_hour - 2) * HOUR_MS, DAY_MS), Calendar.MINUTE_MS) and high > Climate._sample(daily_curve, posmod((high_hour + 2) * HOUR_MS, DAY_MS), Calendar.MINUTE_MS), "daily maximum follows local solar 15:00")
		# 30 degrees is exactly two hours; rotating a line through midnight
		# introduces at most a small integer-knot quantization difference.
		for hour: int in [0, 3, 5, 8, 12, 15, 20, 23]:
			var at_ms: int = hour * HOUR_MS
			var local_east: int = Climate._sample(east.regions[region].daily_curve, at_ms, Calendar.MINUTE_MS)
			var central_east: int = Climate._sample(base.regions[region].daily_curve, posmod(at_ms + 2 * HOUR_MS, DAY_MS), Calendar.MINUTE_MS)
			var local_west: int = Climate._sample(western.regions[region].daily_curve, at_ms, Calendar.MINUTE_MS)
			var central_west: int = Climate._sample(base.regions[region].daily_curve, posmod(at_ms - 2 * HOUR_MS, DAY_MS), Calendar.MINUTE_MS)
			runner.assert_true(absi(local_east - central_east) <= 2, "30 degrees east shifts the daily cycle two hours, within integer-knot precision")
			runner.assert_true(absi(local_west - central_west) <= 2, "30 degrees west shifts the daily cycle two hours, within integer-knot precision")
		runner.assert_true(int(east.regions[region].daily_curve[0][1]) != int(base.regions[region].daily_curve[0][1]), "the longitude example actually changes the local daily phase")


func _vernal_phase(runner: Object, template: Dictionary, profile: Dictionary) -> void:
	# The default 360-day year has a 15-day knot lattice; shifting its vernal
	# anchor by two knots tests the seasonal phase without a rounding ambiguity.
	if Calendar.days_per_year(template.calendar) != 360:
		runner.assert_true(false, "vernal phase fixture uses the opening 360-day calendar")
		return
	var first_profile: Dictionary = profile.duplicate(true)
	first_profile.solar.latitude_mdeg = 45000
	first_profile.solar.vernal_day = 0
	var later_profile: Dictionary = first_profile.duplicate(true)
	later_profile.solar.vernal_day = 30
	var first: Dictionary = Geographic.compile(template, first_profile)
	var later: Dictionary = Geographic.compile(template, later_profile)
	runner.assert_true(not first.is_empty() and not later.is_empty(), "different vernal anchors both compile")
	if first.is_empty() or later.is_empty():
		return
	runner.assert_eq(later.regions.home.base_tenths, first.regions.home.base_tenths, "shifting the vernal anchor does not change the baseline")
	runner.assert_eq(later.regions.home.daily_curve, first.regions.home.daily_curve, "shifting the vernal anchor does not move the daily cycle")
	runner.assert_eq(_peak_day(later.regions.home.seasonal_curve) - _peak_day(first.regions.home.seasonal_curve), 30, "a 30-day vernal shift moves the annual peak by 30 days")
	for day: int in [0, 15, 30, 90, 180, 270, 345]:
		var value: int = Climate._sample(later.regions.home.seasonal_curve, day * DAY_MS, DAY_MS)
		var previous: int = Climate._sample(first.regions.home.seasonal_curve, posmod(day - 30, 360) * DAY_MS, DAY_MS)
		runner.assert_eq(value, previous, "the shifted vernal anchor preserves the seasonal waveform across the year seam")


func _calendar_lengths(runner: Object, template: Dictionary, profile: Dictionary) -> void:
	for year: int in [1, 2, 3, 4, 8784]:
		var local: Dictionary = template.duplicate(true)
		local.calendar.days_per_month = year if year < 8784 else 366
		local.calendar.months_per_year = 1 if year < 8784 else 24
		local.calendar.seasons = ["单季"] if year < 8784 else ["春", "夏", "秋", "冬"]
		for region: Dictionary in local.regions.values():
			region.seasonal_curve = [[0, 0], [year, 0]]
		local.solar.vernal_day = year - 1
		var adjusted: Dictionary = profile.duplicate(true)
		adjusted.solar.latitude_mdeg = 45000
		adjusted.solar.vernal_day = year - 1
		var compiled: Dictionary = Geographic.compile(local, adjusted)
		runner.assert_true(not compiled.is_empty() and Climate.valid_definitions(compiled), "a %d-day valid calendar compiles to a valid original climate shape" % year)
		if compiled.is_empty():
			continue
		for region: String in compiled.regions:
			var curve: Array = compiled.regions[region].seasonal_curve
			runner.assert_true(curve.size() >= 2 and curve.size() <= 64, "seasonal curve has bounded knot count")
			runner.assert_eq(int(curve[0][0]), 0, "seasonal curve begins at day zero")
			runner.assert_eq(int(curve[-1][0]), year, "seasonal curve ends exactly at this calendar's year")
			runner.assert_eq(int(curve[0][1]), int(curve[-1][1]), "seasonal curve closes across the year seam")
			var previous: int = -1
			for point: Array in curve:
				runner.assert_true(int(point[0]) > previous, "seasonal knot days are strictly increasing without duplicate positions")
				previous = int(point[0])
			if year < 4:
				runner.assert_eq(_range(curve), 0, "a one-to-three-day calendar has the explicit flat seasonal fallback")


func _rejection_and_ownership(runner: Object, template: Dictionary, profile: Dictionary) -> void:
	var template_before: String = var_to_str(template)
	var profile_before: String = var_to_str(profile)
	var valid: Dictionary = Geographic.compile(template, profile)
	runner.assert_true(not valid.is_empty() and Climate.valid_definitions(valid), "the original profile compiles as usable climate2 content")
	if not valid.is_empty():
		valid.solar.latitude_mdeg = -90000
		valid.regions.home.daily_curve[0][1] = 999
	runner.assert_eq(var_to_str(template), template_before, "compiled climate mutation does not modify its input template")
	runner.assert_eq(var_to_str(profile), profile_before, "compiled climate mutation does not modify its input profile")
	var malformed: Array = [null, [], "profile", {}]
	var wrong_version: Dictionary = profile.duplicate(true)
	wrong_version.version = 2
	malformed.append(wrong_version)
	var extra: Dictionary = profile.duplicate(true)
	extra.unexpected = true
	malformed.append(extra)
	var missing_region: Dictionary = profile.duplicate(true)
	missing_region.regions.erase("river")
	malformed.append(missing_region)
	var unknown_region: Dictionary = profile.duplicate(true)
	unknown_region.regions["other"] = unknown_region.regions.river
	unknown_region.regions.erase("river")
	malformed.append(unknown_region)
	for value: Variant in [-1, 1001, 0.5, true, "500"]:
		var bad: Dictionary = profile.duplicate(true)
		bad.regions.home.continentality_milli = value
		malformed.append(bad)
	for value: int in [-201, 201]:
		var bad: Dictionary = profile.duplicate(true)
		bad.regions.home.temperature_offset_tenths = value
		malformed.append(bad)
	var bad_latitude: Dictionary = profile.duplicate(true)
	bad_latitude.solar.latitude_mdeg = 90001
	malformed.append(bad_latitude)
	var bad_vernal: Dictionary = profile.duplicate(true)
	bad_vernal.solar.vernal_day = Calendar.days_per_year(template.calendar)
	malformed.append(bad_vernal)
	for bad: Variant in malformed:
		var before: String = var_to_str(bad)
		runner.assert_true(not Geographic.valid_profile(template, bad) and Geographic.compile(template, bad).is_empty(), "malformed or unsupported geographic profile is rejected")
		runner.assert_eq(var_to_str(bad), before, "rejected geographic profile is not partially repaired or changed")
		runner.assert_eq(var_to_str(template), template_before, "rejection leaves the source template unchanged")
	var bad_template: Dictionary = template.duplicate(true)
	bad_template.regions.home.daily_curve = [[0, 0], [1440, 1]]
	var bad_template_before: String = var_to_str(bad_template)
	runner.assert_true(not Geographic.valid_profile(bad_template, profile) and Geographic.compile(bad_template, profile).is_empty(), "an invalid source climate is rejected before compiling a profile")
	runner.assert_eq(var_to_str(bad_template), bad_template_before, "rejected climate input remains unchanged")
	runner.assert_eq(var_to_str(profile), profile_before, "rejected climate input does not modify its geographic profile")


func _component_samples(climate: Dictionary, region: String, at_ms: int) -> Array[int]:
	var start_ms: int = int(climate.calendar.start_minutes) * Calendar.MINUTE_MS
	var year_ms: int = Calendar.days_per_year(climate.calendar) * DAY_MS
	var daily_position: int = posmod(posmod(at_ms, DAY_MS) + start_ms, DAY_MS)
	var seasonal_position: int = posmod(posmod(at_ms, year_ms) + start_ms, year_ms)
	return [Climate._sample(climate.regions[region].daily_curve, daily_position, Calendar.MINUTE_MS),
		Climate._sample(climate.regions[region].seasonal_curve, seasonal_position, DAY_MS)]


func _boundaries_and_envelopes(runner: Object, template: Dictionary, profile: Dictionary, weather: Dictionary) -> void:
	# Query the original bound rules, including fractional weather epochs. A
	# returned boundary may change one component while another cancels it.
	for latitude: int in [-90000, -45000, 0, 45000, 90000]:
		var climate: Dictionary = _with_latitude(template, profile, latitude, 750)
		runner.assert_true(not climate.is_empty(), "generated latitude profile compiles for boundary inspection")
		if climate.is_empty():
			continue
		for region: String in climate.regions:
			var envelope: Dictionary = Climate.background_envelope(climate, weather, region)
			runner.assert_true(bool(envelope.get("supported", false)) and bool(envelope.get("conservative", false)), "generated content has a supported conservative annual envelope")
			if not bool(envelope.get("supported", false)):
				continue
			for at_ms: int in [0, 1, 59999, 60000, 3600000, 43200000, 86400000 - 1, 90 * DAY_MS, 270 * DAY_MS, 360 * DAY_MS - 1, Calendar.MAX_TIMESTAMP - 1]:
				for epoch: int in [0, 12345]:
					var opening: Dictionary = Climate.background_for_region(climate, weather, epoch, region, at_ms)
					runner.assert_true(not opening.is_empty() and int(opening.temperature_tenths) >= int(envelope.min_tenths) and int(opening.temperature_tenths) <= int(envelope.max_tenths), "generated temperature lies within the annual bound at real phase/time")
					var next: int = Climate.next_background_boundary_ms(climate, weather, epoch, region, at_ms)
					runner.assert_true(next > at_ms and next <= Calendar.MAX_TIMESTAMP, "generated climate's next boundary is strictly future or saturates safely")
					if next <= at_ms:
						continue
					var initial: Array[int] = _component_samples(climate, region, at_ms)
					var initial_kind: String = Weather.kind_at(weather, region, epoch, at_ms)
					# Inspect every selected point before the promised boundary, not
					# only total temperature, because components can cancel.
					var span: int = next - at_ms
					for part: int in [1, 2, 3, 4]:
						@warning_ignore("integer_division")
						var probe: int = at_ms + (span - 1) * part / 4
						runner.assert_eq(_component_samples(climate, region, probe), initial, "generated curve components stay fixed before their declared boundary")
						runner.assert_eq(Weather.kind_at(weather, region, epoch, probe), initial_kind, "weather remains in the same phase kind before the declared boundary")
					if next < Calendar.MAX_TIMESTAMP:
						var changed: bool = _component_samples(climate, region, next) != initial
						var phase_boundary: int = Weather.next_phase_boundary_ms(weather, region, epoch, at_ms)
						runner.assert_true(changed or next == phase_boundary, "generated boundary corresponds to a component change or declared weather phase")
