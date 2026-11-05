class_name SimEnvironmentTemperatureSegments
extends RefCounted
## Pure held-target compiler. The world validates and binds climate and weather
## definitions before calling; this class neither owns time nor changes state.
## A tide grid is global, so an intervening climate event cannot reset it.

const Calendar = preload("res://scripts/sim/world_calendar.gd")
const Climate = preload("res://scripts/sim/climate_rules.gd")
const Weather = preload("res://scripts/sim/weather.gd")
const Tide = preload("res://scripts/sim/environment_field_tide.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const Response = preload("res://scripts/sim/environment_field_response.gd")
const State = preload("res://scripts/sim/environment_temperature_state.gd")


static func compile_segment(cell: Vector2i, at_ms: int, climate: Dictionary, weather: Dictionary, epoch_ms: int, seed: int, hot_grade_milli: int, cold_grade_milli: int, tau_ms: int, grid_ms: int, horizon_ms: int) -> Dictionary:
	if at_ms < 0 or at_ms >= Response.MAX_TIME:
		return _failure("time_out_of_range")
	if epoch_ms < 0 or epoch_ms > Calendar.MAX_TIMESTAMP:
		return _failure("epoch_out_of_range")
	if horizon_ms <= at_ms or horizon_ms > Response.MAX_TIME:
		return _failure("horizon_out_of_range")
	if tau_ms < 1 or tau_ms > Response.MAX_TAU_MS:
		return _failure("tau_out_of_range")
	if grid_ms < 1 or grid_ms > Response.MAX_TIME:
		return _failure("grid_out_of_range")
	if hot_grade_milli < 0 or hot_grade_milli > Rules.MAX_GRADE_MILLI or cold_grade_milli < 0 or cold_grade_milli > Rules.MAX_GRADE_MILLI:
		return _failure("source_grade_out_of_range")
	# Guard the inputs actually traversed by the climate queries. In particular,
	# missing regions, curves or phases must fail instead of inventing zero heat
	# or producing an indexing/division error. Full content validation belongs
	# to world binding, not to this per-cell projection.
	if not _query_definitions_usable(climate, weather, cell):
		return _failure("invalid_query_definitions")
	var background: Dictionary = Climate.background_at(climate, weather, epoch_ms, cell, at_ms)
	if background.is_empty() or not background.get("region") is String or not background.get("temperature_tenths") is int:
		return _failure("background_unavailable")
	var climate_boundary: int = Climate.next_background_boundary_ms(climate, weather, epoch_ms, str(background.region), at_ms)
	if climate_boundary <= at_ms:
		return _failure("invalid_background_boundary")
	var until_ms: int = mini(horizon_ms, climate_boundary)
	var multiplier: int = Rules.SCALE
	if hot_grade_milli != cold_grade_milli:
		var grid_start: int = at_ms - posmod(at_ms, grid_ms)
		var sampled: Dictionary = Tide.sample(seed, cell, grid_start)
		if not bool(sampled.get("ok", false)):
			return _failure(str(sampled.get("reason", "tide_unavailable")))
		multiplier = int(sampled.multiplier)
		# Compare the remaining distance first; no addition can overflow and a
		# boundary outside the caller's horizon never masquerades as a segment.
		var to_grid: int = grid_ms - posmod(at_ms, grid_ms)
		if to_grid <= until_ms - at_ms:
			until_ms = at_ms + to_grid
	var target: Dictionary = Rules.thermal_target(int(background.temperature_tenths) * 100, hot_grade_milli, cold_grade_milli, multiplier)
	if not bool(target.get("ok", false)):
		return _failure(str(target.get("reason", "target_unavailable")))
	var target_c: float = float(target.temperature_milli) / 1000.0
	if not is_finite(target_c) or target_c < State.MIN_C or target_c > State.MAX_C:
		return _failure("target_out_of_range")
	return {"ok": true, "target_c": target_c, "target_per_ms": 0.0,
		"until_ms": until_ms, "tau_ms": tau_ms}


static func _query_definitions_usable(climate: Dictionary, weather: Dictionary, cell: Vector2i) -> bool:
	if not climate.get("calendar") is Dictionary or not climate.get("regions") is Dictionary or not climate.get("fallback_region") is String:
		return false
	var calendar: Dictionary = climate.calendar
	if not Calendar._integer(calendar.get("days_per_month"), 1, 366) or not Calendar._integer(calendar.get("months_per_year"), 1, 24) or not Calendar._integer(calendar.get("start_minutes"), 0, Calendar.DAY_MINUTES - 1):
		return false
	if not climate.regions.has(climate.fallback_region):
		return false
	# region_at traverses these bounds in dictionary order before using the
	# selected region. These checks do not inspect garments or unrelated state.
	for id: Variant in climate.regions:
		var candidate: Variant = climate.regions[id]
		if not id is String or not candidate is Dictionary or not Climate._bounds(candidate.get("bounds")):
			return false
	var region: String = Climate.region_at(climate, cell)
	var local: Dictionary = climate.regions[region]
	var year_days: int = Calendar.days_per_year(calendar)
	if not Calendar._integer(local.get("base_tenths"), -1000, 1000) or not Climate._curve(local.get("daily_curve"), Calendar.DAY_MINUTES) or not Climate._curve(local.get("seasonal_curve"), year_days):
		return false
	var offsets: Variant = local.get("weather_offsets")
	if not offsets is Dictionary or not Calendar._integer(offsets.get("clear"), 0, 0) or not Calendar._integer(offsets.get("rain"), -500, 0):
		return false
	if not weather.get("regions") is Dictionary or not weather.regions.has(region) or not weather.get("phases") is Array or weather.phases.is_empty():
		return false
	var weather_region: Variant = weather.regions[region]
	if not weather_region is Dictionary or not Calendar._integer(weather_region.get("offset_ms"), 0, Calendar.DAY_MS) or int(weather_region.offset_ms) % Weather.MINUTE_MS != 0:
		return false
	var cycle: int = 0
	for phase: Variant in weather.phases:
		if not phase is Dictionary or not phase.get("kind") is String or phase.kind not in ["clear", "rain"] or not Calendar._integer(phase.get("duration_ms"), Weather.MINUTE_MS, Calendar.DAY_MS):
			return false
		var duration: int = int(phase.duration_ms)
		if duration % Weather.MINUTE_MS != 0 or cycle > Calendar.MAX_TIMESTAMP - duration:
			return false
		cycle += duration
	return true


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
