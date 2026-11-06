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
const Columns = preload("res://scripts/persistence/environment_response_columns.gd")
const Compiler = preload("res://scripts/sim/environment_target_compiler.gd")
const VERSION: int = 2


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
	var response: Dictionary = Columns.capture(session._temperature, session._phases, area)
	if not bool(response.get("ok", false)):
		return response
	var snapshot: Dictionary = {"version": VERSION, "at_ms": world.elapsed_ms,
		"area": [area.position.x, area.position.y, area.size.x, area.size.y],
		"source_digest": session._definitions.digest(), "settings": settings,
		"settings_digest": _digest(settings), "world": physical,
		"response": response.data}
	return {"ok": true, "snapshot": snapshot}


static func stage(data: Variant, world_factory: Callable, definitions: EnvironmentSourceDefinitions, settings: Dictionary) -> Dictionary:
	# The caller supplies a fresh initialized world, never a live world. Regional
	# restore validates original identities and in-flight actions in isolation.
	if not _keys(data, ["version", "at_ms", "area", "source_digest", "settings", "settings_digest", "world", "response"]):
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
	if not world is RegionalSimulation or not world.restore(data.world):
		return _failure("world_restore")
	var candidate := Session.new()
	# JSON comparison normalizes integral numbers to floats. Bind the validated
	# current rule definitions, not that comparison-only representation.
	if not candidate.configure(world, definitions, settings, area):
		return _failure("session_configuration")
	# Keep the validator alive with the private payload until the session has
	# rebuilt its real source cache and validated both restored response owners.
	var validator := CandidateValidator.new()
	if not validator.configure(candidate._settings):
		candidate.close()
		return _failure("response_rule_configuration")
	if not data.response is Dictionary or data.response.get("area") != data.area or data.response.get("size") != [Ground.SIZE, Ground.SIZE]:
		candidate.close()
		return _failure("response_shape")
	# Packed arrays are detached on capture/read and copy-on-write thereafter;
	# staging takes one ownership copy, never expands per-cell dictionaries.
	var payload: Dictionary = {"response": data.response, "validator_owner": validator}
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
	var cursor: int = 0
	var revision: int = -1
	var _compiler := Compiler.new()

	func configure(settings: Dictionary) -> bool:
		return _compiler.configure(settings)

	## At most one budget of cells per call; candidates remain private until ALL
	## cells agree with the rebuilt original field. No full snapshot expansion.
	func validate(session: RefCounted) -> Dictionary:
		var world: RegionalSimulation = session._world
		var area: Rect2i = session._area
		if session._temperature._size != Vector2i(Ground.SIZE, Ground.SIZE) or session._temperature._capacity != Ground.SIZE * Ground.SIZE or session._temperature._last_change_ms > world.elapsed_ms:
			return {"ok": false}
		var remaining: int = mini(session.cell_budget, area.size.x * area.size.y - cursor)
		for _slot: int in remaining:
			@warning_ignore("integer_division")
			var cell := Vector2i(area.position.x + cursor % area.size.x, area.position.y + cursor / area.size.x)
			cursor += 1
			var read: Dictionary = session._ground.read_response_channels(cell)
			if not bool(read.get("ok", false)) or not read.get("channels") is PackedInt32Array or read.channels.size() != 7:
				return {"ok": false}
			if revision < 0:
				revision = int(read.revision)
			if revision != int(read.revision):
				return {"ok": false}
			var key := Vector2i(cell.x >> 4, cell.y >> 4)
			if not Columns.validate_cell(session._temperature._chunks.get(key), session._phases._chunks.get(key), ((cell.y & 15) << 4) + (cell.x & 15), cell, session._settings, world.elapsed_ms, read.channels, _compiler):
				return {"ok": false}
		return {"ok": true, "pending": cursor < area.size.x * area.size.y, "visited": remaining}
