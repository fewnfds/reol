class_name EnvironmentResponseSession
extends RefCounted
## Closed developer acceptance adapter over ONE original regional world.
## The caller relinquishes direct use of that world until close(). Raw public
## domain references are not a general isolation API. Main does not use this.
## Only completed projections leave this adapter; preparation uses game time.

const Ground = preload("res://scripts/sim/environment_ground_cache.gd")
const Temperature = preload("res://scripts/sim/environment_temperature_state.gd")
const Phases = preload("res://scripts/sim/environment_phase_state.gd")
const Targets = preload("res://scripts/sim/environment_response_targets.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const Segments = preload("res://scripts/sim/environment_temperature_segments.gd")
const Tide = preload("res://scripts/sim/environment_field_tide.gd")

var field_work: int = 128
var cell_budget: int = 32
var _world: RegionalSimulation
var _ground: RefCounted
var _temperature: RefCounted
var _phases: RefCounted
var _targets: RefCounted
var _settings: Dictionary = {}
var _definitions: EnvironmentSourceDefinitions
var _area: Rect2i
var _state: String = "closed"
var _reason: String = ""
var _requested_ms: int = 0
var _published_ms: int = 0
var _boundary_ms: int = 0
var _refresh_row: int = 0
var _target_handle: RefCounted
var _event_context: Variant
var _direct_handle: RefCounted
var _last_result: Dictionary = {}
var _views: Dictionary = {}
var _restore_state: Dictionary = {}
var _world_guard_bound: bool = false
var _transfer_guard_bound: bool = false


func configure(world: RegionalSimulation, definitions: EnvironmentSourceDefinitions, settings: Dictionary, area: Rect2i) -> bool:
	if _state != "closed" or world == null or world.elapsed_ms != world.target_ms or definitions == null or not definitions.is_configured():
		return false
	if not Rect2i(0, 0, Ground.SIZE, Ground.SIZE).encloses(area) or not area.has_area() or area.position.x % 16 != 0 or area.position.y % 16 != 0 or area.size.x % 16 != 0 or area.size.y % 16 != 0:
		return false
	if settings.get("climate") != world.environment.definitions or settings.get("weather") != world.weather.definitions or settings.get("weather_epoch_ms") != world.weather.epoch_ms:
		return false
	if not world.synchronize_regions():
		return false
	var ground := Ground.new()
	if not ground.configure(world, definitions):
		return false
	_world = world
	_ground = ground
	_definitions = definitions
	_settings = settings.duplicate(true)
	_area = area
	_published_ms = world.elapsed_ms
	_requested_ms = world.elapsed_ms
	_ground.request_area(area)
	_state = "sources"
	return true


func pump() -> Dictionary:
	if _state in ["closed", "error"]:
		return _failure(_reason if not _reason.is_empty() else _state)
	if _state == "sources":
		var built: Dictionary = _ground.advance(maxi(1, field_work), 2000)
		if not bool(built.get("ok", false)):
			return _fail(str(built.get("reason", "source_build")))
		var info: Dictionary = _ground.diagnostics()
		if info.state != "ready" or int(info.pending_tiles) != 0:
			return status()
		_temperature = Temperature.new()
		_phases = Phases.new()
		_targets = Targets.new()
		if not _restore_state.is_empty():
			if not _temperature.restore(_restore_state.temperature) or not _phases.restore(_restore_state.phases):
				return _fail("response_restore")
		else:
			if not _temperature.configure(Vector2i(Ground.SIZE, Ground.SIZE), Ground.SIZE * Ground.SIZE, _world.elapsed_ms) or not _phases.configure(Vector2i(Ground.SIZE, Ground.SIZE), Ground.SIZE * Ground.SIZE, _world.elapsed_ms):
				return _fail("response_configuration")
		if not _targets.configure(_temperature, _phases, _settings, Callable(_ground, "read_response_channels")):
			return _fail("target_configuration")
		if not _ground.bind_response(_temperature, _phases, _settings, Callable(self, "_initial_temperature"), Callable(self, "_initial_phase")):
			return _fail("joint_configuration")
		if not _world.bind_environment_boundary_guard(self):
			return _fail("world_already_guarded")
		_world_guard_bound = true
		if not _world.artifact_transfers.bind_ground_guard(self):
			return _fail("artifact_transfers_already_guarded")
		_transfer_guard_bound = true
		if not _restore_state.is_empty():
			if not bool(_restore_state.validator.call(self)):
				return _fail("response_restore_contract")
			_restore_state = {}
			_state = "ready"
			return status()
		_start_refresh(true)
	if _state in ["activation", "refresh"]:
		return _pump_targets()
	if _state == "direct":
		var result: Dictionary = _world.object_lifecycle.resume_environment_change(_direct_handle)
		if bool(result.get("pending", false)):
			return status()
		_direct_handle = null
		_last_result = result.duplicate(true)
		_state = "ready"
		_views.clear()
		return status()
	if _state == "advance":
		var complete: bool = _world.advance_to_ms(_boundary_ms, 1)
		if not complete:
			if not _world.errors.is_empty():
				return _fail(str(_world.errors.back()))
			return status()
		if not _world.synchronize_regions():
			return _fail("regions_unavailable")
		if _world.elapsed_ms == next_response_boundary_ms():
			_start_refresh(false)
			return status()
		_publish_boundary()
	return status()


func advance_to_ms(at_ms: int) -> Dictionary:
	if at_ms < _published_ms or at_ms > Temperature.MAX_TIME or _state not in ["ready", "advance", "refresh"]:
		return _failure("busy" if _state != "ready" else "time_out_of_range")
	_requested_ms = maxi(_requested_ms, at_ms)
	_world.target_ms = maxi(_world.target_ms, at_ms)
	if _state == "ready" and _world.elapsed_ms < _requested_ms:
		_boundary_ms = mini(_requested_ms, next_response_boundary_ms())
		_state = "advance"
	return pump()


func execute(request: Dictionary) -> Dictionary:
	if _state != "ready":
		return _failure("busy")
	var result: Dictionary = _world.object_lifecycle.execute(request)
	if bool(result.get("pending", false)):
		_direct_handle = result.handle
		_state = "direct"
	else:
		_last_result = result.duplicate(true)
		_views.clear()
	return result


func schedule(request: Dictionary, actor: String, duration_ms: int) -> Dictionary:
	return _world.object_lifecycle.schedule(request, actor, duration_ms) if _state == "ready" else _failure("busy")


func cancel(actor: String = "") -> bool:
	if _state == "direct" and actor.is_empty():
		var result: Dictionary = _world.object_lifecycle.cancel_environment_change(_direct_handle)
		var cancelled: bool = bool(result.get("ok", false))
		if cancelled:
			_direct_handle = null
			_state = "ready"
		return cancelled
	if _state in ["ready", "advance"] and not actor.is_empty():
		return _world.object_lifecycle.cancel(actor)
	return false


func sample(cell: Vector2i) -> Dictionary:
	if _state != "ready" or not _area.has_point(cell):
		return _failure("busy" if _state != "ready" else "outside_response_area")
	var base: Dictionary = _ground.read_base(cell)
	var actual: Dictionary = _temperature.actual_at(cell, _world.elapsed_ms)
	var phases: Dictionary = _phases.actual_at(cell, _world.elapsed_ms)
	if not bool(base.get("ok", false)) or bool(base.get("pending", false)) or not bool(actual.get("ok", false)) or not bool(phases.get("ok", false)):
		return _failure("actual_unavailable")
	var channels: Dictionary = _ground.read_response_channels(cell)
	var packed: PackedInt32Array = channels.channels
	var target: Dictionary = Segments.compile_segment(cell, _world.elapsed_ms, _settings.climate, _settings.weather, int(_settings.weather_epoch_ms), int(_settings.seed), packed[5], packed[6], int(_settings.tau_ms), int(_settings.tide_grid_ms), Temperature.MAX_TIME)
	return {"ok": true, "at_ms": _published_ms, "cell": cell, "target_c": target.target_c,
		"actual_c": actual.value_c, "actual_elements": phases.values.duplicate(), "base_elements": base.elements.duplicate(),
		"thermal_grade": base.thermal_grade, "visibility": "authority_only"}


func view(cells: Array[Vector2i], ids: Array[String]) -> Dictionary:
	var key: String = str(cells) + str(ids)
	if _state != "ready":
		return _views.get(key, {"ok": false, "reason": "busy", "at_ms": _published_ms}).duplicate(true)
	var samples: Array[Dictionary] = []
	for cell: Vector2i in cells:
		samples.append(sample(cell))
	var objects: Dictionary = {}
	for id: String in ids:
		objects[id] = _world.artifacts.objects.get(id, {}).duplicate(true)
	var result: Dictionary = {"ok": true, "at_ms": _published_ms, "samples": samples, "objects": objects}
	_views[key] = result.duplicate(true)
	return result


func status() -> Dictionary:
	return {"ok": _state != "error", "pending": _state != "ready", "state": _state,
		"at_ms": _published_ms, "requested_ms": _requested_ms, "reason": _reason,
		"result": _last_result.duplicate(true), "visibility": "authority_only"}


func stage_restore_payload(payload: Dictionary, validator: Callable) -> bool:
	if _state != "sources" or not _restore_state.is_empty() or not validator.is_valid():
		return false
	_restore_state = payload.duplicate(true)
	_restore_state["validator"] = validator
	return true


func next_response_boundary_ms() -> int:
	var temperature: int = _temperature.next_boundary_ms()
	var phases: int = _phases.next_boundary_ms()
	return mini(temperature if temperature >= 0 else Temperature.MAX_TIME, phases if phases >= 0 else Temperature.MAX_TIME)


func prepare_move(plan: Dictionary, context: Variant = null) -> Dictionary:
	for location: Dictionary in [plan.from, plan.target]:
		if bool(location.get("ground", false)) or str(location.get("container", "")).begins_with("ground:"):
			var slot: Dictionary = _world.object_lifecycle.ground.slots.get(location.get("container", ""), location)
			var cell: Vector2i = slot.cell if slot.cell is Vector2i else Vector2i(int(slot.cell[0]), int(slot.cell[1]))
			var size: Vector2i = plan.size
			var center: Vector2i = cell + Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
			var radius: int = _definitions.max_radius() - 1
			var coverage := Rect2i(center - Vector2i.ONE * radius, Vector2i.ONE * (radius * 2 + 1)).intersection(Rect2i(0, 0, Ground.SIZE, Ground.SIZE))
			if not _area.encloses(coverage):
				return _failure("outside_response_area")
	_event_context = context
	return _ground.begin_move(plan, context)


func resume_move(handle: Variant) -> Dictionary:
	return _ground.step_move(handle, field_work, cell_budget, _event_context)


func can_commit_move(proof: Variant, plan: Dictionary, context: Variant = null) -> Dictionary:
	return _ground.can_commit_move(proof, plan, context)


func commit_move(proof: Variant, plan: Dictionary) -> Dictionary:
	return _ground.commit_move(proof, plan)


func cancel_move(handle: Variant) -> Dictionary:
	return _ground.cancel_move(handle)


func allows_artifact_transfer(change: Dictionary) -> bool:
	# Legacy tools may complete actions scheduled before this developer session.
	# They cannot bypass the joint lifecycle by writing a ground item directly.
	return not str(change.get("from", {}).get("container", "")).begins_with("ground:") and not str(change.get("to", {}).get("container", "")).begins_with("ground:")


func close() -> bool:
	if _world != null and (_world.environment_boundary_active() or _world.object_lifecycle.environment_change_pending()):
		return false
	if _target_handle != null:
		_targets.cancel(_target_handle)
	if _world != null:
		if _transfer_guard_bound:
			_world.artifact_transfers.bind_ground_guard(null)
		if _world_guard_bound:
			_world.bind_environment_boundary_guard(null)
	if _ground != null:
		_ground.close()
	_world = null
	_ground = null
	_targets = null
	_temperature = null
	_phases = null
	_definitions = null
	_settings.clear()
	_restore_state.clear()
	_views.clear()
	_target_handle = null
	_world_guard_bound = false
	_transfer_guard_bound = false
	_state = "closed"
	return true


func _start_refresh(activation: bool) -> void:
	_state = "activation" if activation else "refresh"
	_refresh_row = _area.position.y
	_target_handle = null
	_event_context = _world.environment_response_context(self)


func _pump_targets() -> Dictionary:
	if _target_handle == null:
		# One row is at most 32 chunks in the declared 512-cell world. Larger
		# candidate roots never accumulate; the session publishes only after ALL
		# rows are ready. This is not a public batch object transaction.
		var row := Rect2i(Vector2i(_area.position.x, _refresh_row), Vector2i(_area.size.x, 16))
		var opened: Dictionary = _targets.begin(row, _world.elapsed_ms, _state == "activation", _event_context)
		if not bool(opened.get("ok", false)):
			return _fail(str(opened.get("reason", "target_begin")))
		_target_handle = opened.handle
	var result: Dictionary = _targets.step(_target_handle, cell_budget)
	if not bool(result.get("ok", false)):
		return _fail(str(result.get("reason", "target_prepare")))
	if bool(result.get("pending", true)):
		return status()
	var finished: Dictionary = _targets.finish(_target_handle)
	if not bool(finished.get("ok", false)):
		return _fail(str(finished.get("reason", "target_finish")))
	var committed: Dictionary = _targets.commit(finished.proof)
	if not bool(committed.get("ok", false)):
		return _fail(str(committed.get("reason", "target_commit")))
	_target_handle = null
	_refresh_row += 16
	if _refresh_row == _area.end.y:
		_publish_boundary()
	return status()


func _publish_boundary() -> void:
	_published_ms = _world.elapsed_ms
	if _world.elapsed_ms < _requested_ms:
		_boundary_ms = mini(_requested_ms, next_response_boundary_ms())
		_state = "advance"
	else:
		_views.clear()
		_state = "ready"


func _initial_temperature(_cell: Vector2i, _at_ms: int) -> Dictionary:
	# The closed area was completely initialized. First observation can never
	# manufacture previously untracked history after activation.
	return _failure("untracked_actual_history")


func _initial_phase(_cell: Vector2i, _at_ms: int) -> Dictionary:
	return _failure("untracked_actual_history")


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "visibility": "authority_only"}


func _fail(reason: String) -> Dictionary:
	_state = "error"
	_reason = reason
	return _failure(reason)
