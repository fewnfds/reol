extends RefCounted
## Bound-content climate envelopes cover unobserved future phases without
## advancing time or claiming jointly attainable extrema or safe heat deletion.


func run(runner: Object) -> void:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "climate envelope loads actual definitions")
		return
	var climate: Dictionary = content.climate.duplicate(true)
	var weather: Dictionary = content.weather.duplicate(true)
	var before: String = JSON.stringify([climate, weather], "", true, true)
	for region: String in weather.regions:
		var envelope: Dictionary = SimClimateRules.background_envelope(climate, weather, region)
		runner.assert_true(bool(envelope.supported) and bool(envelope.conservative), "bound climate reports a conservative supported envelope: " + region)
		runner.assert_eq(SimClimateRules.bound_region_envelope(climate.regions[region], weather.phases), envelope, "bounded inspection of validated regional content gives the same conservative envelope")
		var times: Array[int] = [0, 1, 137, 59999, 60000, 7199999, 7200000, 9007199254740990, 9007199254740991]
		var civil_start_ms: int = int(climate.calendar.start_minutes) * 60000
		for point: Array in climate.regions[region].daily_curve:
			var at_ms: int = posmod(int(point[0]) * 60000 - civil_start_ms, 86400000)
			times.append(at_ms)
			times.append(at_ms + 1)
		for point: Array in climate.regions[region].seasonal_curve:
			var at_ms: int = posmod(int(point[0]) * 86400000 - civil_start_ms, SimWorldCalendar.days_per_year(climate.calendar) * 86400000)
			times.append(at_ms)
			times.append(at_ms + 1)
		for epoch: int in [0, 137, 91234567]:
			for at_ms: int in times:
				var value: Dictionary = SimClimateRules.background_for_region(climate, weather, epoch, region, at_ms)
				runner.assert_true(not value.is_empty() and int(value.temperature_tenths) >= int(envelope.min_tenths) and int(value.temperature_tenths) <= int(envelope.max_tenths), "envelope covers actual background through seasonal/weather epochs and maximum timestamp")
	runner.assert_eq(JSON.stringify([climate, weather], "", true, true), before, "envelope inspection does not mutate bound content")

	# Zero curves make the exact effect of a configured weather phase explicit.
	var flat: Dictionary = climate.duplicate(true)
	var local: Dictionary = flat.regions.home
	local.base_tenths = 100
	local.daily_curve = [[0, 0], [1440, 0]]
	local.seasonal_curve = [[0, 0], [SimWorldCalendar.days_per_year(flat.calendar), 0]]
	local.weather_offsets.rain = -20
	var envelope: Dictionary = SimClimateRules.background_envelope(flat, weather, "home")
	runner.assert_eq(envelope.min_tenths, 80, "whole climate envelope includes the rain transition's two degree drop")
	runner.assert_eq(envelope.max_tenths, 100, "whole climate envelope includes clear conditions")
	var only_clear: Dictionary = weather.duplicate(true)
	only_clear.phases = [{"kind": "clear", "duration_ms": 60000}]
	envelope = SimClimateRules.background_envelope(flat, only_clear, "home")
	runner.assert_eq(envelope.min_tenths, 100, "unreachable weather kinds do not widen the actual content envelope")
	runner.assert_eq(envelope.max_tenths, 100, "a truly constant background has a constant envelope")
	var only_rain: Dictionary = weather.duplicate(true)
	only_rain.phases = [{"kind": "rain", "duration_ms": 60000}]
	envelope = SimClimateRules.background_envelope(flat, only_rain, "home")
	runner.assert_eq(envelope.min_tenths, 80, "permanent rain retains its actual minimum offset")
	runner.assert_eq(envelope.max_tenths, 80, "unreachable clear conditions do not fabricate a warm upper bound")
	# The daily and seasonal extrema need not coincide. Sum independent extrema
	# deliberately, rather than infer a tight future bound from sparse sampling.
	local.daily_curve = [[0, -31], [720, 17], [1440, -31]]
	envelope = SimClimateRules.background_envelope(flat, weather, "home")
	runner.assert_eq(envelope.min_tenths, 49, "negative integer interpolation remains within endpoint envelope")
	runner.assert_eq(envelope.max_tenths, 117, "conservative upper includes all curve endpoints")
	var invalid: Dictionary = flat.duplicate(true)
	invalid.regions.home.daily_curve[0][1] = 2001
	for result: Dictionary in [SimClimateRules.background_envelope(invalid, weather, "home"), SimClimateRules.background_envelope(flat, {}, "home"), SimClimateRules.background_envelope(flat, weather, "missing")]:
		runner.assert_true(not bool(result.supported) and not result.has("min_tenths") and not result.has("max_tenths"), "invalid or missing definitions report unknown without fabricated numeric bounds")
	print("SCENARIO climate envelope: bound-content conservative extrema, real phase/season/epoch coverage, constant backgrounds, unreachable weather and explicit unknowns")
