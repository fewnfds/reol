class_name SimGeographicClimate
extends RefCounted
## Creation-time, bounded climate compiler. Its output is the original climate2
## rule format, not an additional runtime temperature or geography authority.

const Calendar = preload("res://scripts/sim/world_calendar.gd")
const MAX_REGIONS: int = 64
const SEASON_SEGMENTS: int = 24


static func valid_profile(template: Dictionary, profile: Variant) -> bool:
	if not SimClimateRules.valid_definitions(template) or template.regions.size() > MAX_REGIONS:
		return false
	if not Calendar._keys(profile, ["version", "solar", "regions"]) or not Calendar._integer(profile.version, 1, 1) or not SimSolarRules.valid_definitions(profile.solar):
		return false
	if int(profile.solar.vernal_day) >= Calendar.days_per_year(template.calendar) or not profile.regions is Dictionary or profile.regions.size() != template.regions.size():
		return false
	for id: String in template.regions:
		if not profile.regions.has(id):
			return false
		var region: Variant = profile.regions[id]
		if not Calendar._keys(region, ["continentality_milli", "temperature_offset_tenths"]) or not Calendar._integer(region.continentality_milli, 0, 1000) or not Calendar._integer(region.temperature_offset_tenths, -200, 200):
			return false
	return true


static func compile(template: Dictionary, profile: Variant) -> Dictionary:
	if not valid_profile(template, profile):
		return {}
	var result: Dictionary = template.duplicate(true)
	result.solar = profile.solar.duplicate(true)
	var year: int = Calendar.days_per_year(result.calendar)
	var latitude: float = deg_to_rad(float(result.solar.latitude_mdeg) / 1000.0)
	var tilt: float = deg_to_rad(float(result.solar.axial_tilt_mdeg) / 1000.0)
	var sine: float = sin(latitude)
	var longitude_minutes: int = roundi(float(int(result.solar.longitude_mdeg) - int(result.solar.meridian_mdeg)) * 240.0 / Calendar.MINUTE_MS)
	for id: String in result.regions:
		var authored: Dictionary = profile.regions[id]
		var land: float = float(authored.continentality_milli) / 1000.0
		var region: Dictionary = result.regions[id]
		region.base_tenths = roundi(300.0 - 450.0 * sine * sine) + int(authored.temperature_offset_tenths)
		var seasonal: float = 600.0 * sine * sin(tilt) * (0.35 + 0.65 * land)
		var daily: int = roundi(60.0 * maxf(0.0, cos(latitude)) * (0.30 + 0.70 * land))
		region.seasonal_curve = _seasonal_curve(year, int(result.solar.vernal_day), land, seasonal)
		region.daily_curve = _daily_curve(longitude_minutes, daily)
	return result if SimClimateRules.valid_definitions(result) else {}


static func _seasonal_curve(year: int, vernal: int, land: float, amplitude: float) -> Array:
	if year < 4:
		return [[0, 0], [year, 0]]
	var segments: int = mini(SEASON_SEGMENTS, year)
	# Sea moderation delays the annual temperature response. These are authored
	# game approximations, compiled once; the runtime only reads integer knots.
	var lag: float = float(year) * (0.025 + 0.06 * (1.0 - land))
	var curve: Array = []
	for index: int in segments:
		@warning_ignore("integer_division")
		var day: int = index * year / segments
		var phase: float = (float(day - vernal) - 0.5 - lag) / float(year)
		curve.append([day, roundi(amplitude * sin(TAU * phase))])
	curve.append([year, curve[0][1]])
	return curve


static func _daily_curve(shift: int, amplitude: int) -> Array:
	var minimum: int = posmod(300 - shift, Calendar.DAY_MINUTES)
	var maximum: int = posmod(900 - shift, Calendar.DAY_MINUTES)
	var knots: Array[int] = [0, Calendar.DAY_MINUTES]
	for point: int in [minimum, maximum]:
		if not knots.has(point):
			knots.append(point)
	knots.sort()
	var curve: Array = []
	for point: int in knots:
		var elapsed: int = posmod(point - minimum, Calendar.DAY_MINUTES)
		@warning_ignore("integer_division")
		var value: int = -amplitude + 2 * amplitude * elapsed / 600 if elapsed <= 600 else amplitude - 2 * amplitude * (elapsed - 600) / 840
		curve.append([point, value])
	return curve
