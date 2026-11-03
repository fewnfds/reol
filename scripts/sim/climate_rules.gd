class_name SimClimateRules
extends RefCounted
## Deterministic outdoor conditions and human comfort margins, in tenths °C.
## Garment insulation changes cold exposure, never a world's physical heat.

const Calendar = preload("res://scripts/sim/world_calendar.gd")


static func valid_definitions(data: Variant) -> bool:
	if not Calendar._keys(data, ["version", "calendar", "fallback_region", "regions", "human", "garments"]) or not Calendar._integer(data.version, 1, 1) or not Calendar.valid_definitions(data.calendar):
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
	return {"cold_tenths": cold, "hot_tenths": hot,
		"energy_rate": mini(int(human.max_energy_rate), (cold + hot) * int(human.energy_rate_per_degree) / 10)}
