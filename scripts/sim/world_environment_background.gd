class_name SimWorldEnvironmentBackground
extends RefCounted
## Actual neutral response shared only by untouched cells in a climate region.
## The caller routes previously source-affected cells to the temperature owner.
## This stores no cell state, source, independent clock, or numerical integral.

const Climate = preload("res://scripts/sim/climate_rules.gd")
const Weather = preload("res://scripts/sim/weather.gd")
const Calendar = preload("res://scripts/sim/world_calendar.gd")
const Response = preload("res://scripts/sim/environment_field_response.gd")
const Temperature = preload("res://scripts/sim/environment_temperature_state.gd")
const Values = preload("res://scripts/persistence/snapshot_values.gd")
const VERSION: int = 1

var _settings: Dictionary = {}
var _settings_digest: String = ""
var _activation_ms: int = 0
var _at_ms: int = 0
var _regions: Dictionary = {}


func configure(settings: Dictionary, activation_ms: int) -> bool:
	if not _settings.is_empty() or not _valid_settings(settings, activation_ms):
		return false
	var candidate_settings: Dictionary = settings.duplicate(true)
	var candidate_regions: Dictionary = {}
	for region: String in candidate_settings.climate.regions:
		var target: Dictionary = _background(candidate_settings, region, activation_ms)
		if target.is_empty():
			return false
		var anchor: Dictionary = _segment(candidate_settings, region, activation_ms, float(target.value_c))
		if anchor.is_empty():
			return false
		candidate_regions[region] = anchor
	_settings = candidate_settings
	_settings_digest = _digest(candidate_settings)
	_activation_ms = activation_ms
	_at_ms = activation_ms
	_regions = candidate_regions
	return true


func advance_to_ms(at_ms: int) -> bool:
	if _settings.is_empty() or at_ms < _at_ms or at_ms > Response.MAX_TIME:
		return false
	# Construct all new anchors first. If any segment fails, no region or cursor
	# is changed; the caller retains the previous committed world time.
	var candidate: Dictionary = {}
	for region: String in _regions:
		var anchor: Dictionary = _regions[region]
		while int(anchor.until_ms) <= at_ms and int(anchor.until_ms) < Response.MAX_TIME:
			var boundary: int = int(anchor.until_ms)
			var actual: float = Response._value_only_unchecked(int(anchor.start_ms), boundary, float(anchor.initial_c), float(anchor.target_c), 0.0, int(_settings.tau_ms))
			if not Temperature._temperature(actual):
				return false
			anchor = _segment(_settings, region, boundary, actual)
			if anchor.is_empty():
				return false
		candidate[region] = anchor
	_regions = candidate
	_at_ms = at_ms
	return true


func region_at(cell: Vector2i) -> String:
	if _settings.is_empty() or not _inside(cell):
		return ""
	return Climate.region_at(_settings.climate, cell)


func value_at(cell: Vector2i, at_ms: int) -> Dictionary:
	return value_for_region(region_at(cell), at_ms)


func value_for_region(region: String, at_ms: int) -> Dictionary:
	if region.is_empty() or not _regions.has(region):
		return {"ok": false, "reason": "invalid_cell_or_unconfigured"}
	var anchor: Dictionary = _regions[region]
	if at_ms < int(anchor.start_ms) or at_ms > int(anchor.until_ms):
		return {"ok": false, "reason": "outside_current_segment"}
	var actual: float = Response._value_only_unchecked(int(anchor.start_ms), at_ms, float(anchor.initial_c), float(anchor.target_c), 0.0, int(_settings.tau_ms))
	if not Temperature._temperature(actual):
		return {"ok": false, "reason": "response_unavailable"}
	return {"ok": true, "value_c": actual}


func next_boundary_ms() -> int:
	if _settings.is_empty():
		return -1
	var boundary: int = Response.MAX_TIME
	for anchor: Dictionary in _regions.values():
		boundary = mini(boundary, int(anchor.until_ms))
	return boundary


func snapshot() -> Dictionary:
	if _settings.is_empty():
		return {}
	return {"version": VERSION, "settings_digest": _settings_digest,
		"activation_ms": _activation_ms, "at_ms": _at_ms, "regions": _regions.duplicate(true)}


func restore(data: Variant) -> bool:
	# The receiver was configured with the archived settings and activation. A
	# bad candidate must not change that receiver or any already-live anchors.
	if _settings.is_empty() or not Calendar._keys(data, ["version", "settings_digest", "activation_ms", "at_ms", "regions"]):
		return false
	if not _integer(data.version, VERSION, VERSION) or not data.settings_digest is String or data.settings_digest != _settings_digest:
		return false
	if not _integer(data.activation_ms, _activation_ms, _activation_ms) or not _integer(data.at_ms, _activation_ms, Response.MAX_TIME):
		return false
	if not data.regions is Dictionary or data.regions.size() != _regions.size():
		return false
	var at_ms: int = int(data.at_ms)
	var candidate: Dictionary = {}
	for region: String in _regions:
		if not data.regions.has(region):
			return false
		var raw: Variant = data.regions[region]
		if not Calendar._keys(raw, ["start_ms", "until_ms", "initial_c", "target_c"]):
			return false
		if not _integer(raw.start_ms, _activation_ms, at_ms) or not _integer(raw.until_ms, at_ms, Response.MAX_TIME):
			return false
		var start: int = int(raw.start_ms)
		if int(raw.until_ms) == at_ms and at_ms != Response.MAX_TIME:
			return false # a committed cursor already starts its next segment
		if not Temperature._temperature(raw.initial_c) or not Temperature._temperature(raw.target_c):
			return false
		if start > _activation_ms and Climate.next_background_boundary_ms(_settings.climate, _settings.weather, int(_settings.weather_epoch_ms), region, start - 1) != start:
			return false
		var expected: Dictionary = _segment(_settings, region, start, float(raw.initial_c))
		if expected.is_empty() or int(raw.until_ms) != int(expected.until_ms) or float(raw.target_c) != float(expected.target_c):
			return false
		var bounds: Dictionary = Climate.bound_region_envelope(_settings.climate.regions[region], _settings.weather.phases)
		var low: float = float(int(bounds.min_tenths) * 100) / 1000.0
		var high: float = float(int(bounds.max_tenths) * 100) / 1000.0
		if float(raw.initial_c) < low or float(raw.initial_c) > high:
			return false
		if start == _activation_ms and float(raw.initial_c) != float(expected.target_c):
			return false
		candidate[region] = expected
	_regions = candidate
	_at_ms = at_ms
	return true


static func _background(settings: Dictionary, region: String, at_ms: int) -> Dictionary:
	var target: Dictionary = Climate.background_for_region(settings.climate, settings.weather, int(settings.weather_epoch_ms), region, at_ms)
	if not target.get("temperature_tenths") is int:
		return {}
	# Match the existing field target compiler's milli-degree conversion.
	var value: float = float(int(target.temperature_tenths) * 100) / 1000.0
	return {"value_c": value} if Temperature._temperature(value) else {}


static func _segment(settings: Dictionary, region: String, start_ms: int, initial_c: float) -> Dictionary:
	if not Temperature._temperature(initial_c) or start_ms < 0 or start_ms > Response.MAX_TIME:
		return {}
	var target: Dictionary = _background(settings, region, start_ms)
	if target.is_empty():
		return {}
	var until: int = Response.MAX_TIME
	if start_ms < Response.MAX_TIME:
		until = mini(until, Climate.next_background_boundary_ms(settings.climate, settings.weather, int(settings.weather_epoch_ms), region, start_ms))
		if until <= start_ms:
			return {}
	return {"start_ms": start_ms, "until_ms": until, "initial_c": initial_c, "target_c": float(target.value_c)}


static func _valid_settings(settings: Dictionary, activation_ms: int) -> bool:
	if not Calendar._keys(settings, ["climate", "weather", "weather_epoch_ms", "seed", "tau_ms", "tide_grid_ms"]):
		return false
	if activation_ms < 0 or activation_ms > Response.MAX_TIME or not Climate.valid_definitions(settings.climate) or not Weather.valid_definitions(settings.weather):
		return false
	if not settings.seed is int or not _integer(settings.seed, -Calendar.MAX_TIMESTAMP, Calendar.MAX_TIMESTAMP):
		return false
	if not _integer(settings.weather_epoch_ms, 0, activation_ms) or not _integer(settings.tau_ms, 1, Response.MAX_TAU_MS) or not _integer(settings.tide_grid_ms, 1, Response.MAX_TIME):
		return false
	for region: String in settings.climate.regions:
		if not settings.weather.regions.has(region):
			return false
	return true


static func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < WorldMapData.WORLD_SIZE and cell.y < WorldMapData.WORLD_SIZE


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= float(minimum) and float(value) <= float(maximum) and floor(float(value)) == float(value)


static func _digest(value: Dictionary) -> String:
	return Values.canonical_json(Values.normalized(value)).sha256_text()
