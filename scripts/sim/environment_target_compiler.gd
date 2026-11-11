class_name SimEnvironmentTargetCompiler
extends RefCounted
## Immutable validated rule context; memoizes region/time climate work, not
## per-cell field values. One cache interval is retained; no world history.
const Climate = preload("res://scripts/sim/climate_rules.gd")
const Weather = preload("res://scripts/sim/weather.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const Tide = preload("res://scripts/sim/environment_field_tide.gd")
const Temperature = preload("res://scripts/sim/environment_temperature_state.gd")
var _settings: Dictionary = {}
var _at_ms: int = -1
var _horizon: int = -1
var _regions: Dictionary = {}


func fork() -> SimEnvironmentTargetCompiler:
	# Validated rule data is immutable. Each execution slot has its own memo
	# table; workers must not share the original compiler's mutable region cache.
	var context := SimEnvironmentTargetCompiler.new()
	context._settings = _settings
	return context


func configure(settings: Dictionary) -> bool:
	if not _settings.is_empty() or settings.size() != 6:
		return false
	for key: String in ["climate", "weather", "weather_epoch_ms", "seed", "tau_ms", "tide_grid_ms"]:
		if not settings.has(key):
			return false
	if not Climate.valid_definitions(settings.climate) or not Weather.valid_definitions(settings.weather) or not settings.seed is int:
		return false
	if not _integer(settings.weather_epoch_ms, 0, Temperature.MAX_TIME) or not _integer(settings.tau_ms, 1, Temperature.Response.MAX_TAU_MS) or not _integer(settings.tide_grid_ms, 1, Temperature.MAX_TIME):
		return false
	_settings = settings.duplicate(true)
	return true


func compile(cell: Vector2i, at_ms: int, hot: int, cold: int, horizon_ms: int = Temperature.MAX_TIME) -> Dictionary:
	if _settings.is_empty() or at_ms < 0 or at_ms >= Temperature.MAX_TIME or horizon_ms <= at_ms or horizon_ms > Temperature.MAX_TIME:
		return {"ok": false, "reason": "target_context"}
	if hot < 0 or cold < 0 or hot > Rules.MAX_GRADE_MILLI or cold > Rules.MAX_GRADE_MILLI:
		return {"ok": false, "reason": "source_grade_out_of_range"}
	if at_ms != _at_ms or horizon_ms != _horizon:
		_regions.clear()
		_at_ms = at_ms
		_horizon = horizon_ms
	var region: String = Climate.region_at(_settings.climate, cell)
	if not _regions.has(region):
		var background: Dictionary = Climate.background_for_region(_settings.climate, _settings.weather, int(_settings.weather_epoch_ms), region, at_ms)
		if not background.get("temperature_tenths") is int:
			return {"ok": false, "reason": "background_unavailable"}
		var boundary: int = Climate.next_background_boundary_ms(_settings.climate, _settings.weather, int(_settings.weather_epoch_ms), region, at_ms)
		if boundary <= at_ms:
			return {"ok": false, "reason": "invalid_background_boundary"}
		_regions[region] = {"neutral_milli": int(background.temperature_tenths) * 100, "until_ms": mini(horizon_ms, boundary)}
	var cached: Dictionary = _regions[region]
	var grid: int = int(_settings.tide_grid_ms)
	var tide: Dictionary = Tide.sample(int(_settings.seed), cell, at_ms - posmod(at_ms, grid))
	if not bool(tide.get("ok", false)):
		return tide
	var until_ms: int = int(cached.until_ms)
	if hot != cold:
		until_ms = mini(until_ms, at_ms + mini(grid - posmod(at_ms, grid), Temperature.MAX_TIME - at_ms))
	var target: Dictionary = Rules.thermal_target(int(cached.neutral_milli), hot, cold, int(tide.multiplier) if hot != cold else Rules.SCALE)
	if not bool(target.get("ok", false)):
		return target
	var value: float = float(target.temperature_milli) / 1000.0
	if not Temperature._temperature(value):
		return {"ok": false, "reason": "target_out_of_range"}
	return {"ok": true, "target_c": value, "target_per_ms": 0.0, "until_ms": until_ms,
		"tau_ms": int(_settings.tau_ms), "neutral_c": float(cached.neutral_milli) / 1000.0, "multiplier": int(tide.multiplier)}


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum and floor(float(value)) == float(value)
