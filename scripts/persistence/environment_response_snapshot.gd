class_name EnvironmentResponseSnapshot
extends RefCounted
## Development acceptance snapshots for the closed environment session. This
## is not the ordinary game save format and never replaces a live session.
## Original objects/time remain in the regional snapshot; field caches rebuild.

const Session = preload("res://scripts/runtime/environment_response_session.gd")
const Ground = preload("res://scripts/sim/environment_ground_cache.gd")
const Temperature = preload("res://scripts/sim/environment_temperature_state.gd")
const Phases = preload("res://scripts/sim/environment_phase_state.gd")
const Segments = preload("res://scripts/sim/environment_temperature_segments.gd")
const Tide = preload("res://scripts/sim/environment_field_tide.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const Values = preload("res://scripts/persistence/snapshot_values.gd")
const VERSION: int = 1


static func capture(session: RefCounted) -> Dictionary:
	if not is_instance_of(session, Session) or session._state != "ready" or session._world == null:
		return _failure("busy")
	var world: RegionalSimulation = session._world
	if world.elapsed_ms != world.target_ms or world.elapsed_ms != session._published_ms or world.environment_boundary_active() or world.object_lifecycle.environment_change_pending():
		return _failure("busy")
	var physical: Dictionary = world.to_dict()
	if physical.is_empty():
		return _failure("world_snapshot")
	var settings: Variant = Values.normalized(session._settings)
	if not settings is Dictionary:
		return _failure("settings_snapshot")
	var area: Rect2i = session._area
	var snapshot: Dictionary = {"version": VERSION, "at_ms": world.elapsed_ms,
		"area": [area.position.x, area.position.y, area.size.x, area.size.y],
		"source_digest": session._definitions.digest(), "settings": settings,
		"settings_digest": _digest(settings), "world": physical,
		"temperature": session._temperature.snapshot(), "phases": session._phases.snapshot()}
	return {"ok": true, "snapshot": snapshot}


static func stage(data: Variant, world_factory: Callable, definitions: EnvironmentSourceDefinitions, settings: Dictionary) -> Dictionary:
	# The caller supplies a fresh initialized world, never a live world. Regional
	# restore validates original identities and in-flight actions in isolation.
	if not _keys(data, ["version", "at_ms", "area", "source_digest", "settings", "settings_digest", "world", "temperature", "phases"]):
		return _failure("snapshot_shape")
	if not _integer(data.version, VERSION, VERSION) or not _integer(data.at_ms, 0, Temperature.MAX_TIME) or not data.world is Dictionary:
		return _failure("snapshot_shape")
	if not data.area is Array or data.area.size() != 4:
		return _failure("snapshot_area")
	for value: Variant in data.area:
		if not _integer(value, 0, Ground.SIZE):
			return _failure("snapshot_area")
	var area := Rect2i(int(data.area[0]), int(data.area[1]), int(data.area[2]), int(data.area[3]))
	if not area.has_area() or not Rect2i(0, 0, Ground.SIZE, Ground.SIZE).encloses(area) or area.position.x % 16 != 0 or area.position.y % 16 != 0 or area.size.x % 16 != 0 or area.size.y % 16 != 0:
		return _failure("snapshot_area")
	if definitions == null or not definitions.is_configured() or data.source_digest != definitions.digest():
		return _failure("source_digest")
	if not data.settings is Dictionary or not data.settings_digest is String:
		return _failure("settings_digest")
	var expected: Variant = Values.normalized(settings)
	if not expected is Dictionary or _digest(expected) != str(data.settings_digest) or _digest(data.settings) != str(data.settings_digest):
		return _failure("settings_digest")
	if not _integer(data.world.get("elapsed_ms"), int(data.at_ms), int(data.at_ms)) or not _integer(data.world.get("target_ms"), int(data.at_ms), int(data.at_ms)):
		return _failure("world_time")
	if not world_factory.is_valid():
		return _failure("world_factory")
	var world: Variant = world_factory.call()
	if not world is RegionalSimulation or not world.restore(data.world.duplicate(true)):
		return _failure("world_restore")
	var candidate := Session.new()
	# JSON comparison normalizes integral numbers to floats. Bind the validated
	# current rule definitions, not that comparison-only representation.
	if not candidate.configure(world, definitions, settings, area):
		return _failure("session_configuration")
	# Keep the validator alive with the private payload until the session has
	# rebuilt its real source cache and validated both restored response owners.
	var validator := CandidateValidator.new()
	var payload: Dictionary = {"temperature": data.temperature.duplicate(true) if data.temperature is Dictionary else {},
		"phases": data.phases.duplicate(true) if data.phases is Dictionary else {}, "validator_owner": validator}
	if not candidate.stage_restore_payload(payload, Callable(validator, "validate")):
		candidate.close()
		return _failure("session_restore")
	return {"ok": true, "candidate": candidate}


static func _digest(value: Variant) -> String:
	return Values.canonical_json(Values.normalized(value)).sha256_text()


static func _keys(value: Variant, names: Array) -> bool:
	if not value is Dictionary or value.size() != names.size():
		return false
	for name: String in names:
		if not value.has(name):
			return false
	return true


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= float(minimum) and float(value) <= float(maximum)


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "visibility": "authority_only"}


class CandidateValidator:
	extends RefCounted
	## Runs only on a detached candidate after the original source cache rebuild.
	## It cannot recover source changes that happened before an anchor; it checks
	## the currently effective target for each saved known segment.
	func validate(session: RefCounted) -> bool:
		var world: RegionalSimulation = session._world
		var area: Rect2i = session._area
		var temperature: Dictionary = session._temperature.snapshot()
		var phases: Dictionary = session._phases.snapshot()
		if temperature.get("size") != [Ground.SIZE, Ground.SIZE] or phases.get("size") != [Ground.SIZE, Ground.SIZE] or int(temperature.get("capacity", 0)) != Ground.SIZE * Ground.SIZE or int(phases.get("capacity", 0)) != Ground.SIZE * Ground.SIZE:
			return false
		if int(temperature.get("activation_ms", -1)) != int(phases.get("activation_ms", -2)) or int(temperature.get("last_change_ms", -1)) != int(phases.get("last_change_ms", -2)) or int(temperature.get("last_change_ms", -1)) > world.elapsed_ms:
			return false
		var temp_rows: Variant = temperature.get("cells")
		var phase_rows: Variant = phases.get("cells")
		if not temp_rows is Array or not phase_rows is Array or temp_rows.size() != area.size.x * area.size.y or phase_rows.size() != temp_rows.size():
			return false
		for index: int in temp_rows.size():
			@warning_ignore("integer_division")
			var cell := Vector2i(area.position.x + index % area.size.x, area.position.y + index / area.size.x)
			var thermal: Dictionary = temp_rows[index]
			var phase: Dictionary = phase_rows[index]
			if thermal.cell != [cell.x, cell.y] or phase.cell != thermal.cell:
				return false
			var response: Dictionary = thermal.response
			var start_ms: int = int(response.start_ms)
			if start_ms != int(phase.start_ms) or int(response.tau_ms) != int(phase.tau_ms) or int(response.tau_ms) != int(session._settings.tau_ms):
				return false
			if start_ms > world.elapsed_ms or world.elapsed_ms > int(response.until_ms) or world.elapsed_ms > int(phase.until_ms):
				return false
			var read: Dictionary = session._ground.read_response_channels(cell)
			if not bool(read.get("ok", false)) or not read.get("channels") is PackedInt32Array or read.channels.size() != 7:
				return false
			var channels: PackedInt32Array = read.channels
			var settings: Dictionary = session._settings
			var compiled: Dictionary = Segments.compile_segment(cell, start_ms, settings.climate, settings.weather, int(settings.weather_epoch_ms), int(settings.seed), channels[5], channels[6], int(settings.tau_ms), int(settings.tide_grid_ms), Temperature.MAX_TIME)
			if not bool(compiled.get("ok", false)) or int(response.until_ms) != int(compiled.until_ms) or float(response.target_value) != float(compiled.target_c) or float(response.target_per_ms) != float(compiled.target_per_ms):
				return false
			var grid: int = int(settings.tide_grid_ms)
			var sampled: Dictionary = Tide.sample(int(settings.seed), cell, start_ms - posmod(start_ms, grid))
			if not bool(sampled.get("ok", false)):
				return false
			var next_grid: int = start_ms + mini(grid - posmod(start_ms, grid), Temperature.MAX_TIME - start_ms)
			if int(phase.until_ms) != mini(int(compiled.until_ms), next_grid):
				return false
			for channel: int in Phases.CHANNELS:
				if float(phase.target[channel]) != float(Rules.effective_grade(channels[channel], int(sampled.multiplier))) or float(phase.slope[channel]) != 0.0:
					return false
			if not bool(session._temperature.actual_at(cell, world.elapsed_ms).get("ok", false)) or not bool(session._phases.actual_at(cell, world.elapsed_ms).get("ok", false)):
				return false
		return true
