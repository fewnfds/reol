class_name SimClimateRules
extends RefCounted
## Deterministic outdoor conditions and human comfort margins, in tenths °C.
## Garment insulation changes cold exposure, never a world's physical heat.

const Calendar = preload("res://scripts/sim/world_calendar.gd")


static func valid_definitions(data: Variant) -> bool:
	var fields: Array = ["version", "calendar", "fallback_region", "regions", "human", "garments", "solar"]
	if not Calendar._keys(data, fields) or not Calendar._integer(data.version, 2, 2) or not Calendar.valid_definitions(data.calendar):
		return false
	if not SimSolarRules.valid_definitions(data.solar) or not Calendar._integer(data.solar.vernal_day, 0, Calendar.days_per_year(data.calendar) - 1):
		return false
	if not data.regions is Dictionary or data.regions.is_empty() or not data.fallback_region is String or not data.regions.has(data.fallback_region):
		return false
	var bounds: Array[Rect2i] = []
	for id: Variant in data.regions:
		var region: Variant = data.regions[id]
		if not id is String or id.strip_edges().is_empty() or not Calendar._keys(region, ["label", "bounds", "base_tenths", "seasonal_curve", "daily_curve", "weather_offsets"]):
			return false
		if not region.label is String or region.label.strip_edges().is_empty() or not _bounds(region.bounds) or not Calendar._integer(region.base_tenths, -1000, 1000):
			return false
		var next := Rect2i(int(region.bounds[0]), int(region.bounds[1]), int(region.bounds[2]), int(region.bounds[3]))
		for prior: Rect2i in bounds:
			if next.intersects(prior):
				return false
		bounds.append(next)
		if not _curve(region.seasonal_curve, Calendar.days_per_year(data.calendar)) or not _curve(region.daily_curve, Calendar.DAY_MINUTES):
			return false
		if not Calendar._keys(region.weather_offsets, ["clear", "rain"]) or region.weather_offsets.clear != 0 or not Calendar._integer(region.weather_offsets.rain, -500, 0):
			return false
	var human: Variant = data.human
	if not Calendar._keys(human, ["comfort_min_tenths", "comfort_max_tenths", "energy_scale", "energy_rate_per_degree", "max_energy_rate", "max_insulation_tenths", "insulation_heat_percent"]):
		return false
	if not Calendar._integer(human.comfort_min_tenths, -1000, 1000) or not Calendar._integer(human.comfort_max_tenths, int(human.comfort_min_tenths) + 1, 1000) or not Calendar._integer(human.energy_scale, 1, 100000000):
		return false
	if not Calendar._integer(human.energy_rate_per_degree, 1, int(human.energy_scale)) or not Calendar._integer(human.max_energy_rate, 1, int(human.energy_scale)) or not Calendar._integer(human.max_insulation_tenths, 1, 1000) or not Calendar._integer(human.insulation_heat_percent, 0, 100):
		return false
	if not data.garments is Dictionary or data.garments.is_empty():
		return false
	for id: Variant in data.garments:
		var garment: Variant = data.garments[id]
		if not id is String or id.strip_edges().is_empty() or not Calendar._keys(garment, ["insulation_tenths", "wet_loss_percent"]) or not Calendar._integer(garment.insulation_tenths, 0, int(human.max_insulation_tenths)) or not Calendar._integer(garment.wet_loss_percent, 0, 100):
			return false
	return true


static func _bounds(value: Variant) -> bool:
	return value is Array and value.size() == 4 and Calendar._integer(value[0], -1000000, 1000000) and Calendar._integer(value[1], -1000000, 1000000) and Calendar._integer(value[2], 1, 1000000) and Calendar._integer(value[3], 1, 1000000)


static func _curve(value: Variant, period: int) -> bool:
	if not value is Array or value.size() < 2 or value.size() > 64:
		return false
	var previous: int = -1
	for point: Variant in value:
		if not point is Array or point.size() != 2 or not Calendar._integer(point[0], previous + 1, period) or not Calendar._integer(point[1], -1000, 1000):
			return false
		previous = int(point[0])
	return int(value[0][0]) == 0 and previous == period and value[0][1] == value[-1][1]


static func region_at(rules: Dictionary, cell: Vector2i) -> String:
	for id: String in rules.regions:
		var bounds: Array = rules.regions[id].bounds
		if Rect2i(int(bounds[0]), int(bounds[1]), int(bounds[2]), int(bounds[3])).has_point(cell):
			return id
	return str(rules.fallback_region)


static func background_at(rules: Dictionary, weather_rules: Dictionary, epoch: int, cell: Vector2i, at_ms: int) -> Dictionary:
	# Definitions are already validated and bound by the owning world. Only the
	# inexpensive lookup guards belong on this pure query's hot path.
	if not rules.get("regions") is Dictionary or not rules.get("fallback_region") is String or not rules.regions.has(rules.fallback_region):
		return {}
	return background_for_region(rules, weather_rules, epoch, region_at(rules, cell), at_ms)


static func background_for_region(rules: Dictionary, weather_rules: Dictionary, epoch: int, region: String, at_ms: int) -> Dictionary:
	if not _time_valid(epoch) or not _time_valid(at_ms) or not rules.get("regions") is Dictionary or not rules.regions.has(region) or not weather_rules.get("regions") is Dictionary or not weather_rules.regions.has(region):
		return {}
	var kind: String = SimWeather.kind_at(weather_rules, region, epoch, at_ms)
	return {"region": region, "kind": kind, "temperature_tenths": temperature_at(rules, region, at_ms, kind)}


static func background_envelope(rules: Dictionary, weather_rules: Dictionary, region: String) -> Dictionary:
	# Explicit inspection, not a hot-path temperature query. Independent extrema
	# conservatively cover every day, season and weather phase of this bound
	# content; their sums need not be jointly attainable. This is no forecast or
	# certificate that discarding a cell's thermal inertia would be safe.
	if not valid_definitions(rules) or not SimWeather.valid_definitions(weather_rules):
		return {"supported": false, "reason": "invalid_definitions"}
	if not rules.regions.has(region) or not weather_rules.regions.has(region):
		return {"supported": false, "reason": "unknown_region"}
	return bound_region_envelope(rules.regions[region], weather_rules.phases)


static func bound_region_envelope(climate: Dictionary, phases: Array) -> Dictionary:
	# The owning world already validated these definitions. Callers with a work
	# budget can charge the two curve lengths and phase count before this scan,
	# without revalidating unrelated regions, garments or spatial overlaps.
	var lower: int = int(climate.base_tenths)
	var upper: int = lower
	for curve: Array in [climate.seasonal_curve, climate.daily_curve]:
		var minimum: int = int(curve[0][1])
		var maximum: int = minimum
		for point: Array in curve:
			minimum = mini(minimum, int(point[1]))
			maximum = maxi(maximum, int(point[1]))
		lower += minimum
		upper += maximum
	var weather_min: int = 0
	var weather_max: int = 0
	var first: bool = true
	for phase: Dictionary in phases:
		var offset: int = int(climate.weather_offsets[phase.kind])
		weather_min = offset if first else mini(weather_min, offset)
		weather_max = offset if first else maxi(weather_max, offset)
		first = false
	return {"supported": true, "min_tenths": lower + weather_min,
		"max_tenths": upper + weather_max, "conservative": true}


static func next_background_boundary_ms(rules: Dictionary, weather_rules: Dictionary, epoch: int, region: String, at_ms: int) -> int:
	# Component changes and phase boundaries are deterministic candidate
	# boundaries. Simultaneous components may cancel in the total temperature.
	if not _time_valid(epoch) or not _time_valid(at_ms) or at_ms == Calendar.MAX_TIMESTAMP or not rules.get("regions") is Dictionary or not rules.regions.has(region) or not weather_rules.get("regions") is Dictionary or not weather_rules.regions.has(region):
		return Calendar.MAX_TIMESTAMP
	var climate: Dictionary = rules.regions[region]
	var start_ms: int = int(rules.calendar.start_minutes) * Calendar.MINUTE_MS
	var year_ms: int = Calendar.days_per_year(rules.calendar) * Calendar.DAY_MS
	var daily_position: int = posmod(posmod(at_ms, Calendar.DAY_MS) + start_ms, Calendar.DAY_MS)
	var seasonal_position: int = posmod(posmod(at_ms, year_ms) + start_ms, year_ms)
	var daily_delay: int = _next_curve_change_delay(climate.daily_curve, daily_position, Calendar.MINUTE_MS)
	var seasonal_delay: int = _next_curve_change_delay(climate.seasonal_curve, seasonal_position, Calendar.DAY_MS)
	var delay: int = mini(daily_delay, seasonal_delay)
	var curve_boundary: int = Calendar.MAX_TIMESTAMP
	if delay != Calendar.MAX_TIMESTAMP and delay <= Calendar.MAX_TIMESTAMP - at_ms:
		curve_boundary = at_ms + delay
	return mini(curve_boundary, SimWeather.next_phase_boundary_ms(weather_rules, region, epoch, at_ms))


static func _time_valid(at_ms: int) -> bool:
	return at_ms >= 0 and at_ms <= Calendar.MAX_TIMESTAMP


@warning_ignore("integer_division")
static func _next_curve_change_delay(curve: Array, position_ms: int, unit_ms: int) -> int:
	# A valid curve is closed and has increasing endpoints. Skip flat segments
	# rather than iterating milliseconds; one traversal covers a whole period.
	var segment_count: int = curve.size() - 1
	var index: int = 0
	while index < segment_count and position_ms >= int(curve[index + 1][0]) * unit_ms:
		index += 1
	if index == segment_count:
		return Calendar.MAX_TIMESTAMP
	var elapsed: int = position_ms - int(curve[index][0]) * unit_ms
	var skipped: int = 0
	for _segment: int in range(segment_count):
		var left: Array = curve[index]
		var right: Array = curve[index + 1]
		var duration: int = (int(right[0]) - int(left[0])) * unit_ms
		var magnitude: int = absi(int(right[1]) - int(left[1]))
		if magnitude > 0:
			# _sample truncates toward zero, so either slope changes at the same
			# positive-magnitude threshold ceil(k * duration / magnitude).
			var next_level: int = magnitude * elapsed / duration + 1
			var threshold: int = (next_level * duration + magnitude - 1) / magnitude
			return skipped + threshold - elapsed
		skipped += duration - elapsed
		index = (index + 1) % segment_count
		elapsed = 0
	return Calendar.MAX_TIMESTAMP


static func temperature_at(rules: Dictionary, region: String, at_ms: int, kind: String) -> int:
	var climate: Dictionary = rules.regions.get(region, rules.regions[rules.fallback_region])
	# The offset is a projection of the same elapsed time, matching GameClock's
	# civil start hour; modulo before interpolation bounds integer products.
	var civil_ms: int = maxi(0, at_ms) + int(rules.calendar.start_minutes) * Calendar.MINUTE_MS
	var year_ms: int = Calendar.days_per_year(rules.calendar) * Calendar.DAY_MS
	return int(climate.base_tenths) + _sample(climate.seasonal_curve, posmod(civil_ms, year_ms), Calendar.DAY_MS) + _sample(climate.daily_curve, posmod(civil_ms, Calendar.DAY_MS), Calendar.MINUTE_MS) + int(climate.weather_offsets.get(kind, 0))


@warning_ignore("integer_division")
static func _sample(curve: Array, at: int, unit_ms: int) -> int:
	for index: int in range(1, curve.size()):
		var right: Array = curve[index]
		var end_ms: int = int(right[0]) * unit_ms
		if at < end_ms:
			var left: Array = curve[index - 1]
			var start_ms: int = int(left[0]) * unit_ms
			return int(left[1]) + (int(right[1]) - int(left[1])) * (at - start_ms) / (end_ms - start_ms)
	return int(curve[-1][1])


@warning_ignore("integer_division")
static func insulation_at(rules: Dictionary, type_id: String, wet: int) -> int:
	if not rules.garments.has(type_id):
		return 0
	var garment: Dictionary = rules.garments[type_id]
	var dry: int = int(garment.insulation_tenths)
	return dry - dry * int(garment.wet_loss_percent) * clampi(wet, 0, 100) / 10000


@warning_ignore("integer_division")
static func burden(rules: Dictionary, temperature: int, insulation: int) -> Dictionary:
	var human: Dictionary = rules.human
	var warmth: int = clampi(insulation, 0, int(human.max_insulation_tenths))
	var cold: int = maxi(0, int(human.comfort_min_tenths) - temperature - warmth)
	var hot: int = maxi(0, temperature - int(human.comfort_max_tenths) + warmth * int(human.insulation_heat_percent) / 100)
	var total: int = cold + hot
	var rate_per_degree: int = int(human.energy_rate_per_degree)
	var cap: int = int(human.max_energy_rate)
	# Compare before multiplication: very high legal artifact temperatures need
	# not overflow int64 merely to discover that exposure is already capped.
	var threshold: int = (cap * 10 + rate_per_degree - 1) / rate_per_degree
	return {"cold_tenths": cold, "hot_tenths": hot,
		"energy_rate": cap if total >= threshold else total * rate_per_degree / 10}
