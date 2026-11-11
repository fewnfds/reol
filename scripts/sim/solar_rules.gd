class_name SimSolarRules
extends RefCounted
## Pure, map-wide geometric sunlight from the bound civil calendar and original
## integer timeline. Relative illumination is a game scale, never physical lux.
## No refraction, equation of time, terrain horizon, moon or local light source
## is modeled. All returned values are instantaneous projections, not a clock.

const Calendar = preload("res://scripts/sim/world_calendar.gd")
const HALF_DAY_MS: int = 12 * 60 * Calendar.MINUTE_MS
const MS_PER_MDEG_LONGITUDE: int = 240
const TRANSMISSION_SCALE: int = 10000
const HORIZON_EPSILON: float = 0.000000000001
const TWILIGHT_DEGREES: float = 6.0
const FIELDS: Array[String] = ["latitude_mdeg", "longitude_mdeg", "meridian_mdeg", "axial_tilt_mdeg", "vernal_day", "relative_scale", "clear_transmission", "rain_transmission", "roof_transmission"]


static func valid_definitions(solar: Variant) -> bool:
	if not Calendar._keys(solar, FIELDS):
		return false
	if not _integer(solar.latitude_mdeg, -90000, 90000) or not _integer(solar.longitude_mdeg, -180000, 180000) or not _integer(solar.meridian_mdeg, -180000, 180000):
		return false
	if not _integer(solar.axial_tilt_mdeg, 0, 45000) or not _integer(solar.vernal_day, 0, Calendar.MAX_TIMESTAMP) or not _integer(solar.relative_scale, 1, 1000000):
		return false
	for field: String in ["clear_transmission", "rain_transmission", "roof_transmission"]:
		if not _integer(solar[field], 0, TRANSMISSION_SCALE):
			return false
	return true


static func sample(calendar: Dictionary, solar: Dictionary, at_ms: int, weather_kind: String = "clear") -> Dictionary:
	# Validation is bounded to these nine solar fields and the small calendar;
	# this query never scans regions, content bundles, actors or live processes.
	if at_ms < 0 or at_ms > Calendar.MAX_TIMESTAMP or weather_kind not in ["clear", "rain"] or not Calendar.valid_definitions(calendar) or not valid_definitions(solar):
		return {}
	var year_days: int = Calendar.days_per_year(calendar)
	if int(solar.vernal_day) >= year_days:
		return {}
	var year_ms: int = year_days * Calendar.DAY_MS
	var civil_offset_ms: int = int(calendar.start_minutes) * Calendar.MINUTE_MS
	var civil_year_ms: int = posmod(posmod(at_ms, year_ms) + civil_offset_ms, year_ms)
	# Vernal-day civil noon is the zero-declination anchor. Longitude only
	# changes local solar time; it cannot change the Sun's global declination.
	var year_phase_ms: int = posmod(civil_year_ms - int(solar.vernal_day) * Calendar.DAY_MS - HALF_DAY_MS, year_ms)
	var longitude_offset_ms: int = (int(solar.longitude_mdeg) - int(solar.meridian_mdeg)) * MS_PER_MDEG_LONGITUDE
	var solar_time_ms: int = posmod(posmod(at_ms, Calendar.DAY_MS) + civil_offset_ms + longitude_offset_ms, Calendar.DAY_MS)
	# Reduce the safe-integer timestamp before converting any phase to float.
	var latitude: float = deg_to_rad(float(solar.latitude_mdeg) / 1000.0)
	var declination: float = deg_to_rad(float(solar.axial_tilt_mdeg) / 1000.0) * sin(TAU * float(year_phase_ms) / float(year_ms))
	if absf(declination) < HORIZON_EPSILON:
		declination = 0.0
	var hour_angle: float = TAU * float(solar_time_ms - HALF_DAY_MS) / float(Calendar.DAY_MS)
	var vertical: float = sin(latitude) * sin(declination)
	var rotating: float = cos(latitude) * cos(declination)
	var elevation_sine: float = clampf(vertical + rotating * cos(hour_angle), -1.0, 1.0)
	if absf(elevation_sine) < HORIZON_EPSILON:
		elevation_sine = 0.0
	var elevation: float = asin(elevation_sine)
	var day: Dictionary = _daylight(vertical, rotating)
	var elevation_degrees: float = rad_to_deg(elevation)
	var sky_phase: String = "night"
	if elevation_sine >= 0.0:
		sky_phase = "day"
	elif elevation_degrees >= -TWILIGHT_DEGREES - HORIZON_EPSILON:
		sky_phase = "dawn" if solar_time_ms < HALF_DAY_MS else "dusk"
	var projection: float = maxf(0.0, elevation_sine)
	# Clear geometric light: 80% maximum direct, 2..20% daytime diffuse;
	# civil twilight carries only diffuse light, fading to zero at -6 degrees.
	var diffuse_fraction: float = 0.02 + 0.18 * projection if elevation_sine >= 0.0 else 0.02 * clampf((elevation_degrees + TWILIGHT_DEGREES) / TWILIGHT_DEGREES, 0.0, 1.0)
	var scale: int = int(solar.relative_scale)
	var direct_clear: int = clampi(roundi(float(scale) * 0.8 * projection), 0, scale)
	var diffuse_clear: int = clampi(roundi(float(scale) * diffuse_fraction), 0, scale - direct_clear)
	var transmission: int = int(solar.clear_transmission if weather_kind == "clear" else solar.rain_transmission)
	var direct: int = _transmitted(direct_clear, transmission)
	var diffuse: int = _transmitted(diffuse_clear, transmission)
	return {"at_ms": at_ms, "solar_time_ms": solar_time_ms, "year_phase_ms": year_phase_ms,
		"elevation_mdeg": clampi(roundi(elevation_degrees * 1000.0), -90000, 90000),
		"declination_mdeg": roundi(rad_to_deg(declination) * 1000.0),
		"daylight_ms": int(day.daylight_ms), "polar_state": str(day.polar_state), "sky_phase": sky_phase,
		"direct_relative": direct, "diffuse_relative": diffuse, "total_relative": direct + diffuse,
		"relative_scale": scale, "weather_kind": weather_kind, "weather_transmission": transmission,
		"roof_transmission": int(solar.roof_transmission)}


static func label(query: Dictionary) -> String:
	match query.get("sky_phase", ""):
		"day": return "天光明亮" if int(query.get("total_relative", 0)) * 2 >= int(query.get("relative_scale", 1)) else "天光柔暗"
		"dawn": return "晨曦微明"
		"dusk": return "暮色渐暗"
		"night": return "夜色深沉"
	return "天光不明"


static func _daylight(vertical: float, rotating: float) -> Dictionary:
	if rotating <= HORIZON_EPSILON:
		if vertical > HORIZON_EPSILON:
			return {"daylight_ms": Calendar.DAY_MS, "polar_state": "day"}
		if vertical < -HORIZON_EPSILON:
			return {"daylight_ms": 0, "polar_state": "night"}
		# At the ideal pole/equinox the entire geometric path is the horizon.
		# Use the 12h equinoctial limit rather than dividing zero by zero.
		return {"daylight_ms": HALF_DAY_MS, "polar_state": "none"}
	var horizon: float = -vertical / rotating
	if horizon <= -1.0 + HORIZON_EPSILON:
		return {"daylight_ms": Calendar.DAY_MS, "polar_state": "day"}
	if horizon >= 1.0 - HORIZON_EPSILON:
		return {"daylight_ms": 0, "polar_state": "night"}
	var duration: int = roundi(float(Calendar.DAY_MS) * acos(clampf(horizon, -1.0, 1.0)) / PI)
	return {"daylight_ms": clampi(duration, 0, Calendar.DAY_MS), "polar_state": "none"}


@warning_ignore("integer_division")
static func _transmitted(relative: int, transmission: int) -> int:
	# Product <= 1e6 * 1e4: exact and safely below the JSON integer ceiling.
	return relative * transmission / TRANSMISSION_SCALE


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	if value is int:
		return value >= minimum and value <= maximum
	if value is float:
		return is_finite(value) and value >= float(minimum) and value <= float(maximum) and floor(value) == value
	return false
