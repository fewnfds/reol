class_name SimWorldEnvironmentFields
extends RefCounted
## The ordinary world's temperature/five-element authority, installed as
## RegionalSimulation.environment_fields. Serialized by the world's codec.
## Source indexes are disposable projections over original object owners.

const VERSION: int = 6
const MODEL: String = "composed_fields_v1"
const SIZE: int = SimGroundPlacements.MAP_SIZE
const MAX_TIME: int = SimEnvironmentTemperatureState.MAX_TIME
const TAU_MS: int = 30000
const TIDE_GRID_MS: int = 60000
const MAX_TRANSIENT: int = 128
const ANCHOR_QUANTUM: float = 0.000000001
const TARGET_CELLS_PER_WORK: int = 16
const SOURCE_FIELD_WORK: int = 256
const Field = preload("res://scripts/sim/environment_ground_field.gd")
const Temperature = preload("res://scripts/sim/environment_temperature_state.gd")
const Phases = preload("res://scripts/sim/environment_phase_state.gd")
const Targets = preload("res://scripts/sim/environment_response_targets.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const Compiler = preload("res://scripts/sim/environment_target_compiler.gd")
const Participant = preload("res://scripts/sim/world_environment_source_participant.gd")
const Background = preload("res://scripts/sim/world_environment_background.gd")
const Participation = preload("res://scripts/sim/execution/participation_index.gd")

var definitions: Dictionary = {}
var activation_ms: int = 0
var last_ms: int = 0
var last_sample_ms: int = 0
var receipts: Dictionary = {}
var device_switches: Dictionary = {}
var _owner: WeakRef
var _settings: Dictionary = {}
var _field: RefCounted
var _temperature: RefCounted
var _phases: RefCounted
var _sources: RefCounted
var _background: RefCounted
var _targets: RefCounted
var _compiler: RefCounted
var _chunks: Dictionary[Vector2i, bool] = {}
var _thermal_chunks: Dictionary[Vector2i, bool] = {}
var _samples: Dictionary = {}
var _transient: Dictionary = {}
var _active: bool = false
var _busy: bool = false
var _object_motion_key: String = ""
var _error: String = ""
var _participation := Participation.new()
var _last_refresh_chunks: int = 0
var _layout := SimEnvironmentLayout.new()
var _dirty_containers: Dictionary = {}
var _connections: Array[Dictionary] = []
var _topology_cells: Array[Vector2i] = []
var _motion_changes: Array[Dictionary] = []
var _settle_cursor: Dictionary = {}
var _allow_source_compute: bool = false
var motion_sampling_work: Dictionary = {"crossings": 0, "coalesced": 0, "adopted": 0, "forced": 0}

var world: RegionalSimulation:
	get: return _owner.get_ref() if _owner != null else null


func initialize(authority: RegionalSimulation, rules: Dictionary) -> bool:
	if _owner != null or authority == null or authority._content == null or authority._content.environment_sources == null or not ThermalDefinitions.is_valid(rules):
		return false
	_owner = weakref(authority)
	definitions = rules.duplicate(true) # Original action-price receipt unit only.
	activation_ms = authority.elapsed_ms
	last_ms = activation_ms
	last_sample_ms = activation_ms
	return true


func bind_world(authority: RegionalSimulation) -> void:
	_owner = weakref(authority)
	# Recreate only the disposable binding after the complete candidate has
	# been installed. Original state owners and response anchors stay in place.
	if _active:
		var rebound: bool = _sources.bind_world(authority)
		assert(rebound, "validated field candidate failed to rebind original owners")
		_layout.bind_world(authority)
		_connect_owners()


func activate_sources() -> bool:
	if _active:
		return _error.is_empty()
	if world == null or world.weather == null or world.artifacts == null or not _configure_components(activation_ms):
		return false
	if not world.synchronize_regions():
		return false
	var built: Dictionary = _sources.build_sources()
	if not bool(built.get("ok", false)):
		return _fail(str(built.get("reason", "source_build")))
	for key: Vector2i in _sources.affected_chunks():
		_chunks[key] = true
	_add_room_chunks()
	if not _rebuild_base() or not _refresh_targets(activation_ms, true):
		return false
	_active = true
	_rebuild_participation()
	_connect_owners()
	return mark_sample(activation_ms)


func _configure_components(at_ms: int) -> bool:
	var seed: int = int(world.map_data.descriptor().seed) if world.map_data != null else 0
	_settings = {"climate": world._content.climate, "weather": world.weather.definitions,
		"weather_epoch_ms": world.weather.epoch_ms, "seed": seed, "tau_ms": TAU_MS, "tide_grid_ms": TIDE_GRID_MS}
	_field = Field.new()
	_temperature = Temperature.new()
	_phases = Phases.new()
	# Only reanchor at causal environment boundaries. Canonical sub-nanounit
	# precision prevents JSON roundoff becoming a divergent saved future.
	_temperature.anchor_quantum = ANCHOR_QUANTUM
	_phases.anchor_quantum = ANCHOR_QUANTUM
	_background = Background.new()
	_compiler = Compiler.new()
	_targets = Targets.new()
	_sources = Participant.new()
	if not _layout.rebuild(world):
		return _fail("layout_capacity")
	var owner: WeakRef = weakref(self)
	_field.set_transport(func(from: Vector2i, to: Vector2i, channel: int) -> int:
		var domain: RefCounted = owner.get_ref()
		return domain._layout.transmission(from, to, channel) if domain != null else 0,
		func(area: Rect2i) -> Dictionary:
			var domain: RefCounted = owner.get_ref()
			return domain._layout.capture_transmission(area) if domain != null else {"ok": false, "reason": "owner_gone"},
		func(from: Vector2i, to: Vector2i) -> Vector2i:
			var domain: RefCounted = owner.get_ref()
			return domain._layout.transmission_pair(from, to) if domain != null else Vector2i.ZERO)
	var reader: Callable = func(cell: Vector2i, context: Variant = null) -> Dictionary:
		var domain: RefCounted = owner.get_ref()
		return domain._read_channels(cell, context) if domain != null else {"ok": false, "reason": "owner_gone"}
	var initial: Callable = func(cell: Vector2i, now: int) -> Dictionary:
		var domain: RefCounted = owner.get_ref()
		return domain._initial_temperature(cell, now) if domain != null else {"ok": false, "reason": "owner_gone"}
	var phase_initial: Callable = func(cell: Vector2i, now: int) -> Dictionary:
		var domain: RefCounted = owner.get_ref()
		return domain._initial_phase(cell, now) if domain != null else {"ok": false, "reason": "owner_gone"}
	var transform: Callable = func(key: String, source: Dictionary) -> Dictionary:
		var domain: RefCounted = owner.get_ref()
		return domain._transform_source(key, source) if domain != null else {}
	return _field.configure(Vector2i(SIZE, SIZE), SIZE * SIZE + 1024) \
		and _temperature.configure(Vector2i(SIZE, SIZE), SIZE * SIZE, at_ms) \
		and _phases.configure(Vector2i(SIZE, SIZE), SIZE * SIZE, at_ms) \
		and _background.configure(_settings, at_ms) and _compiler.configure(_settings) \
		and _targets.configure(_temperature, _phases, _settings, reader, initial) \
		and _sources.configure(world, _field, _temperature, _phases, _settings,
			initial, phase_initial, transform)


func next_boundary_ms() -> int:
	if not _active:
		# Activating is an assembly operation, not a zero-time boundary.
		return MAX_TIME
	var next: int = _background.next_boundary_ms()
	for kind: StringName in [&"temperature", &"phases", &"devices", &"transient"]:
		next = mini(next, _participation.next_due_ms(kind, MAX_TIME))
	if not _motion_changes.is_empty():
		next = mini(next, int(_motion_changes[0].at_ms))
	return next


func can_settle_at_ms(now: int) -> bool:
	return world != null and not _busy and _error.is_empty() and now >= last_ms and now < MAX_TIME and (_settle_cursor.is_empty() or int(_settle_cursor.target_ms) == now)


func settle_at_ms(now: int) -> bool:
	return settle_budgeted(now, 2147483647).y == SimSettlementKernel.Status.COMPLETE


func settle_budgeted(now: int, budget: int, should_yield: Callable = Callable()) -> Vector2i:
	if budget < 1 or not can_settle_at_ms(now) or not activate_sources():
		return Vector2i(1, SimSettlementKernel.Status.FAILED)
	var used: int = 0
	while used < budget:
		_allow_source_compute = should_yield.is_valid()
		var status: int = _settle_work(now)
		used += 1
		if status != SimSettlementKernel.Status.PENDING:
			return Vector2i(used, status)
		if bool(_settle_cursor.get("source_waiting", false)):
			break
		if should_yield.is_valid() and bool(should_yield.call()):
			break
	return Vector2i(used, SimSettlementKernel.Status.PENDING)


func _settle_work(now: int) -> int:
	if _settle_cursor.is_empty():
		if last_ms == now:
			return SimSettlementKernel.Status.COMPLETE if flush_sources(now) else SimSettlementKernel.Status.FAILED
		var end: int = mini(now, next_boundary_ms())
		if not _motion_changes.is_empty():
			end = mini(end, int(_motion_changes[0].at_ms))
		if end <= last_ms:
			_fail("nonprogressing_environment_boundary")
			return SimSettlementKernel.Status.FAILED
		var delta: int = end - last_ms
		# Original device stock remains in the artifact owner. The field does
		# not implement or claim energy conservation between fantasy sources.
		var depleted: Array[String] = []
		for id: String in _participation.active_ids(&"devices"):
			var item: Dictionary = world.artifacts.objects[id]
			var rule: Dictionary = world.artifacts.definitions.types[item.definition].thermal
			var available: int = int(item.stored_q) if rule.mode == "emit" else int(rule.capacity_q) - int(item.stored_q)
			var spent: int = mini(available, delta * int(rule.rate_q_per_ms))
			item.stored_q = int(item.stored_q) + (-spent if rule.mode == "emit" else spent)
			if spent == available:
				depleted.append(id)
		if not _background.advance_to_ms(end):
			_fail("background_advance")
			return SimSettlementKernel.Status.FAILED
		_settle_cursor = {"target_ms": now, "end_ms": end, "depleted": depleted}
		# Refresh old-source target segments at their exact boundary first;
		# source expiry then reanchors at the same millisecond with no jump.
		if end == _temperature.next_boundary_ms() or end == _phases.next_boundary_ms():
			_settle_cursor.refresh = _target_refresh(end, false)
		return SimSettlementKernel.Status.PENDING
	if _settle_cursor.has("refresh"):
		var status: int = _refresh_target_work(_settle_cursor.refresh)
		if status != SimSettlementKernel.Status.COMPLETE:
			return status
		_settle_cursor.erase("refresh")
		return SimSettlementKernel.Status.PENDING
	var end: int = int(_settle_cursor.end_ms)
	if not _settle_cursor.has("motion"):
		last_ms = end
		_settle_cursor.motion = {}
		_settle_cursor.device_index = 0
		_settle_cursor.expiring = _participation.due_ids(&"transient", end)
		_settle_cursor.expiry_index = 0
	if not _settle_cursor.motion.is_empty() or not _motion_changes.is_empty() and int(_motion_changes[0].at_ms) == end:
		if _settle_cursor.motion.is_empty():
			_settle_cursor.motion = _motion_changes.pop_front()
			_settle_cursor.motion.index = 0
		var crossing: Dictionary = _settle_cursor.motion
		if int(crossing.index) >= crossing.keys.size():
			_settle_cursor.motion = {}
			return SimSettlementKernel.Status.PENDING
		var key: String = crossing.keys[int(crossing.index)]
		var source: Dictionary = _sources.get_source(key)
		var status: int = SimSettlementKernel.Status.COMPLETE
		if not source.is_empty():
			source.cell = crossing.cell
			status = _step_settlement_source(key, source, end)
		if status == SimSettlementKernel.Status.COMPLETE:
			crossing.index = int(crossing.index) + 1
			motion_sampling_work.adopted += 1
		return SimSettlementKernel.Status.FAILED if status == SimSettlementKernel.Status.FAILED else SimSettlementKernel.Status.PENDING
	if int(_settle_cursor.device_index) < _settle_cursor.depleted.size():
		var id: String = _settle_cursor.depleted[int(_settle_cursor.device_index)]
		_sync_device(id)
		var key: String = Participant.artifact_key(id)
		var source: Dictionary = _sources.get_source(key)
		var status: int = SimSettlementKernel.Status.COMPLETE if source.is_empty() else _step_settlement_source(key, _transform_source(key, source), end)
		if status == SimSettlementKernel.Status.COMPLETE:
			_settle_cursor.device_index = int(_settle_cursor.device_index) + 1
		return SimSettlementKernel.Status.FAILED if status == SimSettlementKernel.Status.FAILED else SimSettlementKernel.Status.PENDING
	if int(_settle_cursor.expiry_index) < _settle_cursor.expiring.size():
		var key: String = _settle_cursor.expiring[int(_settle_cursor.expiry_index)]
		var status: int = _step_settlement_source(key, {}, end)
		if status == SimSettlementKernel.Status.COMPLETE:
			_transient.erase(key)
			_participation.set_member(&"transient", key, false)
			_settle_cursor.expiry_index = int(_settle_cursor.expiry_index) + 1
		return SimSettlementKernel.Status.FAILED if status == SimSettlementKernel.Status.FAILED else SimSettlementKernel.Status.PENDING
	_settle_cursor.clear()
	if last_ms < now:
		return SimSettlementKernel.Status.PENDING
	return SimSettlementKernel.Status.COMPLETE if flush_sources(now) else SimSettlementKernel.Status.FAILED


func prepare_object_change(request: Dictionary) -> Dictionary:
	if _busy or not _error.is_empty() or not activate_sources() or not settle_at_ms(world.elapsed_ms):
		return {"ok": false, "reason": "environment_unavailable"}
	var key: String = Participant.artifact_key(str(request.get("id", "")))
	var sample: Dictionary = _motion_sample(key)
	# Validate ownership at the original current position without publishing an
	# early field sample. A rejected/cancelled command leaves that sample intact.
	var prepared: Dictionary = _sources.prepare_object_change(request, sample.get("cell"))
	if bool(prepared.get("ok", false)):
		_busy = true
		_object_motion_key = key if not sample.is_empty() else ""
	return prepared


func finish_object_change(result: Dictionary, proof: Variant) -> Dictionary:
	var committed: Dictionary = _sources.finish_object_change(result, proof)
	if bool(committed.get("ok", false)):
		if not _object_motion_key.is_empty():
			_erase_motion_samples(_object_motion_key)
			motion_sampling_work.forced += 1
		for key: Vector2i in _sources.last_change_chunks():
			_chunks[key] = true
		if not _refresh_source_responses(world.elapsed_ms):
			committed = {"ok": false, "reason": "room_publication"}
		var reference: Dictionary = result.get("reference", {})
		if reference.get("kind") == "artifact":
			_sync_device(str(reference.id))
	_busy = false
	_object_motion_key = ""
	if bool(committed.get("ok", false)) and not flush_sources(world.elapsed_ms):
		return {"ok": false, "reason": "contained_source_publication"}
	return committed


func cancel_object_change(proof: Variant) -> bool:
	var cancelled: bool = _sources.cancel_object_change(proof)
	_busy = false
	_object_motion_key = ""
	return cancelled


func can_commit_object_change(proof: Variant) -> bool:
	return _busy and _sources.can_commit(proof)


func _device_active(id: String) -> bool:
	if not world.artifacts.has_capability(id, "thermal_exchange"):
		return false
	var item: Dictionary = world.artifacts.objects[id]
	if not bool(item.enabled) or not world.artifacts.thermal_fixed_location(item):
		return false
	var rule: Dictionary = world.artifacts.definitions.types[item.definition].thermal
	return int(item.stored_q) > 0 if rule.mode == "emit" else int(item.stored_q) < int(rule.capacity_q)


func _transform_source(key: String, original: Dictionary) -> Dictionary:
	var source: Dictionary = original.duplicate(true)
	if key.begins_with("artifact:"):
		var id: String = key.trim_prefix("artifact:")
		if world.artifacts.objects.has(id) and world.artifacts.has_capability(id, "thermal_exchange"):
			var channels: PackedInt32Array = source.channels
			channels[5] = 0
			channels[6] = 0
			if _device_active(id):
				var mode: String = world.artifacts.definitions.types[world.artifacts.objects[id].definition].thermal.mode
				channels[5 if mode == "emit" else 6] = 1000
			source.channels = channels
	return source


func can_switch_device(id: String, enabled: bool) -> bool:
	return not _busy and activate_sources() and last_ms == world.elapsed_ms and world.artifacts.has_capability(id, "thermal_exchange") and world.artifacts.thermal_fixed_location(world.artifacts.objects[id]) and bool(world.artifacts.objects[id].enabled) != enabled


func prepare_device_switch(id: String, enabled: bool) -> Dictionary:
	if not can_switch_device(id, enabled):
		return {"ok": false, "reason": "invalid_device_switch"}
	var key: String = Participant.artifact_key(id)
	var source: Dictionary = _sources.get_source(key)
	if source.is_empty():
		return {"ok": false, "reason": "source_missing"}
	var channels: PackedInt32Array = source.channels
	channels[5] = 0
	channels[6] = 0
	var item: Dictionary = world.artifacts.objects[id]
	var rule: Dictionary = world.artifacts.definitions.types[item.definition].thermal
	var available: int = int(item.stored_q) if rule.mode == "emit" else int(rule.capacity_q) - int(item.stored_q)
	if enabled and available > 0:
		channels[5 if rule.mode == "emit" else 6] = 1000
	source.channels = channels
	var prepared: Dictionary = _sources.prepare_source_change(key, source, world.elapsed_ms)
	if bool(prepared.get("ok", false)):
		_busy = true
	return prepared


func commit_device_switch(receipt: Dictionary, proof: Variant) -> bool:
	if not _busy or receipt.get("at_ms") != world.elapsed_ms or device_switches.has(receipt.action) or not _sources.can_commit(proof):
		return false
	var committed: bool = _sources.finish_source_change(proof)
	assert(committed, "preflighted device field commit failed")
	device_switches[receipt.action] = receipt.duplicate(true)
	_sync_device(str(receipt.object))
	if not _refresh_source_responses(world.elapsed_ms):
		return false
	_busy = false
	return true


func can_deposit(cell: Vector2i, amount: int) -> bool:
	return not _busy and amount == int(definitions.pulse_energy) and _inside(cell) and _transient.size() < MAX_TRANSIENT and activate_sources() and last_ms == world.elapsed_ms


func deposit(receipt: Dictionary) -> bool:
	if not receipt.get("cell") is Array or receipt.cell.size() != 2 or not receipt.get("action") is String or receipts.has(receipt.action) or receipt.get("at_ms") != world.elapsed_ms:
		return false
	var cell := Vector2i(int(receipt.cell[0]), int(receipt.cell[1]))
	if not can_deposit(cell, int(receipt.get("amount", 0))) or world.elapsed_ms > MAX_TIME - 60000:
		return false
	var key: String = "pulse:" + str(receipt.action)
	var source: Dictionary = {"cell": cell, "radius": 4, "channels": PackedInt32Array([0, 0, 0, 0, 0, 1000, 0])}
	if not _change_source(key, source, world.elapsed_ms):
		return false
	_transient[key] = {"cell": [cell.x, cell.y], "until_ms": world.elapsed_ms + 60000}
	_participation.set_member(&"transient", key)
	_participation.set_due(&"transient", key, world.elapsed_ms + 60000)
	receipts[receipt.action] = receipt.duplicate(true)
	return true


func _change_source(key: String, source: Dictionary, at_ms: int) -> bool:
	var prepared: Dictionary = _sources.prepare_source_change(key, source, at_ms)
	if not bool(prepared.get("ok", false)):
		return false # Rejected candidates have not changed either domain.
	return _finish_source_change(prepared.proof, at_ms)


func _step_settlement_source(key: String, source: Dictionary, at_ms: int) -> int:
	# The existing source/response coordinator owns the candidate and cursor.
	# Only this already-pending world boundary can resume it; no second queue.
	if not _settle_cursor.has("source_proof"):
		var opened: Dictionary = _sources.begin_source_change(key, source, at_ms, _allow_source_compute)
		if not bool(opened.get("ok", false)):
			_fail(str(opened.get("reason", "source_begin")))
			return SimSettlementKernel.Status.FAILED
		_settle_cursor.source_proof = opened.proof
	var progress: Dictionary = _sources.step_source_change(_settle_cursor.source_proof, SOURCE_FIELD_WORK, TARGET_CELLS_PER_WORK)
	_settle_cursor.source_waiting = bool(progress.get("waiting", false))
	if not bool(progress.get("ok", false)):
		_fail(str(progress.get("reason", "source_step")))
		return SimSettlementKernel.Status.FAILED
	if bool(progress.get("pending", true)):
		return SimSettlementKernel.Status.PENDING
	if not _finish_source_change(_settle_cursor.source_proof, at_ms):
		return SimSettlementKernel.Status.FAILED
	_settle_cursor.erase("source_proof")
	return SimSettlementKernel.Status.COMPLETE


func _finish_source_change(proof: Variant, at_ms: int) -> bool:
	if not _sources.finish_source_change(proof):
		return _fail("source_publication")
	for chunk: Vector2i in _sources.last_change_chunks():
		_chunks[chunk] = true
	return _refresh_source_responses(at_ms)


func _refresh_source_responses(at_ms: int) -> bool:
	# The existing joint receipt already identifies the response owners that
	# changed. Elemental cargo must not remix/reinspect untouched room heat.
	var thermal: Array[Vector2i] = _sources.last_temperature_chunks()
	if not _refresh_rooms(thermal, at_ms):
		return false
	_sync_response_deadlines(thermal, Targets.THERMAL)
	_sync_response_deadlines(_sources.last_phase_chunks(), Targets.ELEMENTAL)
	return true


func actual_at(cell: Vector2i, at_ms: int) -> Dictionary:
	if _busy or not _error.is_empty() or not _inside(cell) or at_ms < activation_ms or at_ms > last_ms:
		return {"ok": false, "reason": "environment_unavailable"}
	if not _active:
		var climate: Dictionary = SimClimateRules.background_for_region(world._content.climate, world.weather.definitions, world.weather.epoch_ms, SimClimateRules.region_at(world._content.climate, cell), at_ms)
		return {"ok": true, "value_c": float(climate.temperature_tenths) / 10.0}
	var result: Dictionary = _temperature.actual_at(cell, at_ms)
	return _background.value_at(cell, at_ms) if result.get("reason") == "untracked" else result


func project_tenths(cell: Vector2i, at_ms: int) -> Dictionary:
	var actual: Dictionary = actual_at(cell, at_ms)
	if not bool(actual.get("ok", false)):
		return {"supported": false, "reason": actual.get("reason", "unavailable")}
	var value: int = roundi(float(actual.value_c) * 10.0) - _background_tenths(cell, at_ms)
	return {"supported": true, "tenths": value, "value": value, "minimum_tenths": value, "maximum_tenths": value}


func current_tenths(cell: Vector2i) -> int:
	var result: Dictionary = project_tenths(cell, last_ms)
	assert(bool(result.supported), "current field consumer crossed an unprepared boundary")
	return int(result.get("value", 0))


func local_tenths(cell: Vector2i, at_ms: int = -1) -> int:
	var result: Dictionary = project_tenths(cell, last_ms if at_ms < 0 else at_ms)
	return int(result.get("value", 0))


func elements_at(cell: Vector2i) -> Dictionary:
	if _busy or not _active:
		return {"ok": false, "reason": "environment_unavailable"}
	var result: Dictionary = _phases.actual_at(cell, last_ms)
	if result.get("reason") == "untracked":
		result = _initial_phase(cell, last_ms)
	if bool(result.get("ok", false)):
		var packed: PackedFloat64Array = result.values
		var values := PackedFloat64Array()
		for index: int in Rules.SOURCE_FROM_PACKED_ELEMENT_INDEX:
			values.append(packed[index])
		result.values = values
	return result


func context_at(cell: Vector2i) -> Dictionary:
	# Authority-only composition for layout/environment tooling and future
	# geomancy methods. It grants neither character knowledge nor a lucky score.
	var temperature: Dictionary = actual_at(cell, last_ms)
	var elements: Dictionary = elements_at(cell)
	var light: Dictionary = SimLocalLight.at_simulation_cell(world, cell)
	if not bool(temperature.get("ok", false)) or not bool(elements.get("ok", false)) or not bool(light.get("supported", false)):
		return {"ok": false, "reason": "environment_unavailable"}
	return {"ok": true, "at_ms": last_ms, "visibility": "authority_only", "temperature_c": temperature.value_c,
		"elements": elements.values, "light_relative": light.total_relative, "roofed": world.construction.roofed(cell),
		"room": _layout.room_of.get(cell), "terrain": world.map_data.get_terrain(cell)}


func mark_sample(now: int, actor_cells: Dictionary[Vector2i, bool] = {}) -> bool:
	if _busy or not _error.is_empty() or now != last_ms or not activate_sources():
		return false
	var cells: Dictionary[Vector2i, bool] = actor_cells.duplicate()
	for region: VillageSimulation in world.regions.values():
		if actor_cells.is_empty(): # Opening capture has no prepared exposure batch.
			for id: String in region.actors:
				cells[region.exposure_sample_cell(id)] = true
		for id: String in region.land_resources.sources:
			var place_id: String = str(region.config.resource_sources[id].place)
			var place: Dictionary = region.places.get(place_id, {})
			if place.has("cell"):
				cells[SimRouteTravel.cell(place.cell)] = true
	var backgrounds: Dictionary[String, int] = {}
	var background_offsets: Dictionary[String, int] = {}
	if not _sample_background(now, backgrounds, background_offsets):
		return false
	var candidate: Dictionary = {}
	for cell: Vector2i in cells:
		var climate_region: String = _background.region_at(cell)
		if not backgrounds.has(climate_region):
			return false
		var actual: Dictionary = _temperature.actual_at(cell, now)
		if actual.get("reason") == "untracked":
			candidate[_key(cell)] = background_offsets[climate_region]
		elif bool(actual.get("ok", false)):
			candidate[_key(cell)] = roundi(float(actual.value_c) * 10.0) - backgrounds[climate_region]
		else:
			return false
	_samples = candidate
	last_sample_ms = now
	return true


func sample_may_include_offset(now: int) -> bool:
	if _background == null or not _thermal_chunks.is_empty():
		return true
	for region: String in _settings.climate.regions:
		var current: Dictionary = _background.value_for_region(region, now)
		var target: Dictionary = SimClimateRules.background_for_region(_settings.climate, _settings.weather, int(_settings.weather_epoch_ms), region, now)
		# Neutral anchors can differ by the canonical quantum. Do not exclude
		# a cell whose actual value could round across a tenth-degree edge.
		if not bool(current.get("ok", false)) or not target.has("temperature_tenths") or absf(float(current.value_c) * 10.0 - float(target.temperature_tenths)) >= 0.5 - ANCHOR_QUANTUM * 20.0:
			return true
	return false


func _sample_background(now: int, targets: Dictionary[String, int], offsets: Dictionary[String, int]) -> bool:
	if _background == null:
		return false
	for region: String in _settings.climate.regions:
		var current: Dictionary = _background.value_for_region(region, now)
		var target: Dictionary = SimClimateRules.background_for_region(_settings.climate, _settings.weather, int(_settings.weather_epoch_ms), region, now)
		if not bool(current.get("ok", false)) or not target.has("temperature_tenths"):
			return false
		targets[region] = int(target.temperature_tenths)
		offsets[region] = roundi(float(current.value_c) * 10.0) - targets[region]
	return true


func sample_result(cell: Vector2i, at_ms: int) -> Dictionary:
	if at_ms != last_sample_ms or not _samples.has(_key(cell)):
		return {"supported": false, "reason": "sample_unavailable"}
	return {"supported": true, "value": int(_samples[_key(cell)])}


func sample_tenths(cell: Vector2i, at_ms: int) -> int:
	var result: Dictionary = sample_result(cell, at_ms)
	assert(bool(result.supported), "consumer requested an unrecorded field sample")
	return int(result.get("value", 0))


func has_visible_offsets(historical: bool = false) -> bool:
	if historical:
		for value: int in _samples.values():
			if value != 0:
				return true
		return false
	# A phase-only source must not turn quiet temperature consumers into active
	# participants. Changed response chunks maintain this disposable summary;
	# actual residuals still count after their original source has disappeared.
	return not _thermal_chunks.is_empty()


func minimum_offset_tenths() -> int:
	return -20000


func maximum_offset_tenths() -> int:
	return 10000000010000


func has_cell(cell: Vector2i) -> bool:
	return _active and _temperature.actual_at(cell, last_ms).get("ok", false)


func device_emission_rates(at_ms: int) -> Dictionary:
	if at_ms != last_ms or _busy:
		return {"supported": false, "reason": "unsettled_environment"}
	var rates: Dictionary = {}
	for id: String in _participation.active_ids(&"devices"):
		if _device_active(id):
			var rule: Dictionary = world.artifacts.definitions.types[world.artifacts.objects[id].definition].thermal
			if rule.mode == "emit":
				rates[id] = mini(int(rule.rate_q_per_ms), int(world.artifacts.objects[id].stored_q))
	rates.make_read_only()
	return {"supported": true, "rates": rates}


func _refresh_targets(at_ms: int, activation: bool) -> bool:
	var cursor: Dictionary = _target_refresh(at_ms, activation)
	while true:
		var status: int = _refresh_target_work(cursor)
		if status != SimSettlementKernel.Status.PENDING:
			return status == SimSettlementKernel.Status.COMPLETE
	return false


func _target_refresh(at_ms: int, activation: bool) -> Dictionary:
	var selected: Dictionary[Vector2i, int] = {}
	if activation:
		for key: Vector2i in _sorted_chunks():
			selected[key] = Targets.THERMAL | Targets.ELEMENTAL
	else:
		for id: String in _participation.due_ids(&"temperature", at_ms):
			selected[_chunk_from_id(id)] = Targets.THERMAL
		for id: String in _participation.due_ids(&"phases", at_ms):
			var key: Vector2i = _chunk_from_id(id)
			selected[key] = int(selected.get(key, 0)) | Targets.ELEMENTAL
	var keys: Array[Vector2i] = []
	keys.assign(selected.keys())
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	_last_refresh_chunks = keys.size()
	return {"at_ms": at_ms, "activation": activation, "domains": selected, "keys": keys, "index": 0, "handle": null}


func _refresh_target_work(cursor: Dictionary) -> int:
	var at_ms: int = int(cursor.at_ms)
	var keys: Array[Vector2i] = cursor.keys
	if int(cursor.index) >= keys.size():
		if not _refresh_rooms(keys, at_ms):
			return SimSettlementKernel.Status.FAILED
		_sync_response_deadlines(keys)
		return SimSettlementKernel.Status.COMPLETE
	if cursor.handle == null:
		var key: Vector2i = keys[int(cursor.index)]
		var opened: Dictionary = _targets.begin(Rect2i(key * 16, Vector2i(16, 16)), at_ms, bool(cursor.activation), null, int(cursor.domains[key]), not bool(cursor.activation))
		if not bool(opened.get("ok", false)):
			_fail(str(opened.get("reason", "target_begin")))
			return SimSettlementKernel.Status.FAILED
		cursor.handle = opened.handle
	var progress: Dictionary = _targets.step(cursor.handle, TARGET_CELLS_PER_WORK)
	if not bool(progress.get("ok", false)):
		_fail(str(progress.get("reason", "target_step")))
		return SimSettlementKernel.Status.FAILED
	if not bool(progress.get("pending", true)):
		var finished: Dictionary = _targets.finish(cursor.handle)
		if not bool(finished.get("ok", false)) or not bool(_targets.commit(finished.proof).get("ok", false)):
			_fail("target_publication")
			return SimSettlementKernel.Status.FAILED
		cursor.handle = null
		cursor.index = int(cursor.index) + 1
	return SimSettlementKernel.Status.PENDING


func _sync_response_deadlines(keys: Array[Vector2i], domains: int = Targets.THERMAL | Targets.ELEMENTAL) -> void:
	# Checked owner receipts contain distinct chunk keys. This synchronous
	# refresh needs no dirty/ack queue between two consecutive local statements.
	for key: Vector2i in keys:
		var id: String = str(key.y * (SIZE / 16) + key.x)
		if domains & Targets.THERMAL:
			if _chunk_has_thermal_deviation(key):
				_thermal_chunks[key] = true
			else:
				_thermal_chunks.erase(key)
		for kind: StringName in [&"temperature", &"phases"]:
			if not (domains & (Targets.THERMAL if kind == &"temperature" else Targets.ELEMENTAL)):
				continue
			var state: RefCounted = _temperature if kind == &"temperature" else _phases
			var boundary: int = state.chunk_boundary_ms(key)
			_participation.set_member(kind, id, boundary >= 0)
			if boundary >= 0:
				_participation.set_due(kind, id, boundary)


func _chunk_has_thermal_deviation(key: Vector2i) -> bool:
	# Prove an untouched thermal response is the shared neutral response. Only
	# inspect this fixed-size chunk when its anchors change, never per actor/tick.
	var chunk: SimEnvironmentTemperatureState.Chunk = _temperature._chunks.get(key)
	if chunk == null:
		return false
	var neutral: Dictionary = {}
	for index: int in Temperature.CHUNK_CELLS:
		if chunk.present[index] == 0:
			continue
		if chunk.taus[index] != TAU_MS or chunk.slopes[index] != 0.0:
			return true
		var cell := Vector2i((key.x << 4) + (index & 15), (key.y << 4) + (index >> 4))
		var region: String = _background.region_at(cell)
		var cache_key: String = region + ":" + str(chunk.starts[index])
		if not neutral.has(cache_key):
			neutral[cache_key] = _background.value_at(cell, chunk.starts[index])
		var value: Dictionary = neutral[cache_key]
		var background: Dictionary = _background._regions[region]
		if not bool(value.get("ok", false)) or absf(chunk.initials[index] - float(value.value_c)) > ANCHOR_QUANTUM \
			or chunk.targets[index] != float(background.target_c) or chunk.untils[index] != int(background.until_ms):
			return true
	return false


static func _chunk_from_id(id: String) -> Vector2i:
	var index: int = int(id)
	return Vector2i(index % (SIZE / 16), index / (SIZE / 16))


func _sync_device(id: String) -> void:
	var exists: bool = world.artifacts.has_capability(id, "thermal_exchange")
	_participation.set_member(&"devices", id, exists)
	if not exists:
		return
	var active: bool = _device_active(id)
	_participation.set_active(&"devices", id, active)
	if not active:
		_participation.cancel_due(&"devices", id)
		return
	var item: Dictionary = world.artifacts.objects[id]
	var rule: Dictionary = world.artifacts.definitions.types[item.definition].thermal
	var remaining: int = int(item.stored_q) if rule.mode == "emit" else int(rule.capacity_q) - int(item.stored_q)
	var rate: int = int(rule.rate_q_per_ms)
	_participation.set_due(&"devices", id, last_ms + (remaining / rate) + (1 if remaining % rate else 0))


func _rebuild_participation() -> void:
	# Assembly/restore only. Subsequent changes update their own IDs/chunks;
	# the index holds no original object, actual value or alternate clock.
	_participation.clear()
	_thermal_chunks.clear()
	_sync_response_deadlines(_sorted_chunks())
	for id: String in world.artifacts.legacy_object_ids():
		_sync_device(id)
	for key: String in _transient:
		_participation.set_member(&"transient", key)
		_participation.set_due(&"transient", key, int(_transient[key].until_ms))


func _rebuild_base() -> bool:
	for key: Vector2i in _sorted_chunks():
		if not bool(_field.request_area(Rect2i(key * 16, Vector2i(16, 16))).get("ok", false)):
			return _fail("field_area")
	while int(_field.diagnostics().pending_tiles) > 0:
		var result: Dictionary = _field.rebuild(64, Field.MAX_WORK)
		if not bool(result.get("ok", false)):
			return _fail(str(result.get("reason", "base_rebuild")))
	return true


func _read_channels(cell: Vector2i, _context: Variant = null) -> Dictionary:
	return _field.read_base(cell)


func _initial_temperature(cell: Vector2i, at_ms: int) -> Dictionary:
	return _background.value_at(cell, at_ms)


func _initial_phase(_cell: Vector2i, _at_ms: int) -> Dictionary:
	return {"ok": true, "values": PackedFloat64Array([0, 0, 0, 0, 0])}


func _background_tenths(cell: Vector2i, at_ms: int) -> int:
	return int(SimClimateRules.background_for_region(world._content.climate, world.weather.definitions, world.weather.epoch_ms, SimClimateRules.region_at(world._content.climate, cell), at_ms).temperature_tenths)


func _sorted_chunks() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_chunks.keys())
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return result


static func _key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < SIZE and cell.y < SIZE


func _fail(reason: String) -> bool:
	_error = reason
	return false


func to_dict() -> Dictionary:
	if not activate_sources() or _busy or not flush_sources(world.elapsed_ms):
		return {}
	return load("res://scripts/persistence/world_environment_fields_state.gd").capture(self)


func restore(data: Variant) -> bool:
	if not data is Dictionary or _active or _busy:
		return false
	return load("res://scripts/persistence/world_environment_fields_state.gd").restore_into(self, data)


func diagnostics() -> Dictionary:
	return {"model": MODEL, "active": _active, "error": _error, "at_ms": last_ms,
		"motion_sampling": motion_sampling_work.duplicate(), "pending_motion_samples": _motion_changes.size(),
		"motion_period_ms": {"thermal": SimCadence.THERMAL_MOTION_MS, "elemental": SimCadence.FIELD_MOTION_MS},
		"tracked_chunks": _chunks.size(), "transient_sources": _transient.size(),
		"last_refresh_chunks": _last_refresh_chunks,
		"execution": {"temperature": _participation.diagnostics(&"temperature"),
			"phases": _participation.diagnostics(&"phases"), "devices": _participation.diagnostics(&"devices")},
		"geometry": "material_transmission_mixed_rooms", "rooms": _layout.rooms.size(),
		"source": _sources.diagnostics() if _active else {}}


func replace_domain_source(key: String, source: Dictionary, at_ms: int) -> bool:
	if not key.begins_with("plant:") or not _active or _busy or last_ms != at_ms or at_ms != world.elapsed_ms:
		return false
	return _change_source(key, source, at_ms)


func _add_room_chunks() -> void:
	for cell: Vector2i in _layout.room_of:
		_chunks[Vector2i(cell.x >> 4, cell.y >> 4)] = true


func _refresh_rooms(keys: Array[Vector2i], at_ms: int) -> bool:
	if _layout.rooms.is_empty() or keys.is_empty():
		return true
	var selected: Dictionary = {}
	for key: Vector2i in keys:
		for y: int in 16:
			for x: int in 16:
				var cell: Vector2i = key * 16 + Vector2i(x, y)
				if _layout.room_of.has(cell):
					selected[_layout.room_of[cell]] = true
	var changes: Array[Dictionary] = []
	var touched: Dictionary[Vector2i, bool] = {}
	for anchor: Vector2i in selected:
		var segment: Dictionary = _layout.compile_room(self, anchor, at_ms)
		if not bool(segment.get("ok", false)):
			return _fail("room_target")
		var room: Dictionary = _layout.rooms[anchor]
		var actual_sum: float = 0.0
		for cell: Vector2i in room.cells:
			var actual: Dictionary = _temperature.actual_at(cell, at_ms)
			if actual.get("reason") == "untracked":
				actual = _initial_temperature(cell, at_ms)
			if not bool(actual.get("ok", false)):
				return _fail("room_actual")
			actual_sum += float(actual.value_c)
		for cell: Vector2i in room.cells:
			changes.append({"cell": cell, "initial_c": actual_sum / room.cells.size(),
				"target_c": segment.target_c, "target_per_ms": segment.target_per_ms,
				"until_ms": segment.until_ms, "tau_ms": segment.tau_ms})
			touched[Vector2i(cell.x >> 4, cell.y >> 4)] = true
	if changes.is_empty():
		return true
	var plan: Dictionary = _temperature.prepare_targets(changes, at_ms, SIZE * SIZE, true)
	if not bool(plan.get("ok", false)) or not bool(_temperature.commit(plan).get("ok", false)):
		return _fail("room_response")
	var affected: Array[Vector2i] = []
	affected.assign(touched.keys())
	_sync_response_deadlines(affected)
	return true


func before_topology_change(now: int, cells: Array[Vector2i]) -> bool:
	if _busy or now != world.elapsed_ms or not settle_at_ms(now):
		return false
	_topology_cells = cells.duplicate()
	return true


func after_topology_change(now: int, terrain: bool = false) -> bool:
	# Called inside the construction owner's synchronous publication. Preserve
	# all old actual values; only new compartments mix them by cell area.
	var affected: Dictionary[Vector2i, bool] = {}
	var old_barriers: Dictionary = _layout.barriers.duplicate()
	var old_rooms: Dictionary[Vector2i, Vector2i] = _layout.room_of.duplicate()
	var old_compartments: Dictionary = _layout.rooms.duplicate()
	var invalidations: Array[Rect2i] = []
	if not _layout.rebuild(world):
		return _fail("layout_capacity")
	# A structural change must not reanchor every unchanged room in the world.
	# Changed compartments include both old/new cells (split, merge and roof).
	for anchor: Vector2i in old_compartments:
		if old_compartments[anchor] != _layout.rooms.get(anchor, {}):
			for cell: Vector2i in old_compartments[anchor].cells:
				affected[Vector2i(cell.x >> 4, cell.y >> 4)] = true
	for anchor: Vector2i in _layout.rooms:
		if _layout.rooms[anchor] != old_compartments.get(anchor, {}):
			for cell: Vector2i in _layout.rooms[anchor].cells:
				affected[Vector2i(cell.x >> 4, cell.y >> 4)] = true
	for cell: Vector2i in _topology_cells:
		var old_terms: Dictionary = old_barriers.get(cell, {})
		var new_terms: Dictionary = _layout.barriers.get(cell, {})
		if not terrain and int(old_terms.get("thermal", 10000)) == int(new_terms.get("thermal", 10000)) and int(old_terms.get("elements", 10000)) == int(new_terms.get("elements", 10000)):
			continue
		invalidations.append(Rect2i(cell - Vector2i(16, 16), Vector2i(33, 33)))
		for y: int in range(maxi(0, cell.y - 16) >> 4, (mini(SIZE - 1, cell.y + 16) >> 4) + 1):
			for x: int in range(maxi(0, cell.x - 16) >> 4, (mini(SIZE - 1, cell.x + 16) >> 4) + 1):
				affected[Vector2i(x, y)] = true
	_topology_cells.clear()
	var old_channels: Dictionary[Vector2i, PackedInt32Array] = {}
	for key: Vector2i in affected:
		old_channels[key] = _field.cached_chunk_channels(key)
		_chunks[key] = true
	for area: Rect2i in invalidations:
		_field.invalidate_geometry(area)
	if not _rebuild_base():
		return false
	# Actual anchors are preserved by normal retargeting before the new rooms
	# are mixed. No climate reset, duplicate indoor value or saved room stock.
	var keys: Array[Vector2i] = []
	keys.assign(affected.keys())
	for key: Vector2i in keys:
		var previous: PackedInt32Array = old_channels[key]
		var current: PackedInt32Array = _field.cached_chunk_channels(key)
		if current.size() != 256 * 7:
			return _fail("topology_base_unavailable")
		var masks := PackedByteArray()
		masks.resize(256)
		var domains: int = 0
		for index: int in 256:
			var cell := key * 16 + Vector2i(index & 15, index >> 4)
			var changed: int = 0
			if previous.size() != current.size():
				changed = Targets.THERMAL | Targets.ELEMENTAL
			else:
				for channel: int in 7:
					if previous[index * 7 + channel] != current[index * 7 + channel]:
						changed |= Targets.THERMAL if channel >= 5 else Targets.ELEMENTAL
			# Entering or leaving a mixed room changes its thermal law even if
			# the source max stayed the same. Unrelated cells keep their anchors.
			if old_rooms.has(cell) or _layout.room_of.has(cell):
				changed |= Targets.THERMAL
			masks[index] = changed
			domains |= changed
		if domains == 0:
			continue
		var opened: Dictionary = _targets.begin(Rect2i(key * 16, Vector2i(16, 16)), now, false, null, domains, false, masks)
		if not bool(opened.get("ok", false)):
			return _fail("topology_target")
		while true:
			var progress: Dictionary = _targets.step(opened.handle, 256)
			if not bool(progress.get("ok", false)):
				return _fail("topology_target")
			if not bool(progress.pending):
				break
		var finished: Dictionary = _targets.finish(opened.handle)
		if not bool(finished.get("ok", false)) or not bool(_targets.commit(finished.proof).get("ok", false)):
			return _fail("topology_response")
	if not _refresh_rooms(keys, now):
		return false
	_sync_response_deadlines(keys)
	for id: String in world.construction._project_ids():
		_mark_container(str(world.construction.definitions.site.region), id)
		_mark_container(str(world.construction.definitions.site.region), id + ":contents")
		if not _change_source("construction:" + id, _sources.construction_source(id), now):
			return false
	return flush_sources(now)


func _disconnect_owners() -> void:
	for link: Dictionary in _connections:
		var sender: Object = link.owner.get_ref()
		if sender != null and sender.is_connected(link.signal, link.callback):
			sender.disconnect(link.signal, link.callback)
	_connections.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# RefCounted is already marked dying here; do not call another script
		# method on self from this notification.
		for link: Dictionary in _connections:
			var sender: Object = link.owner.get_ref()
			if sender != null and sender.is_connected(link.signal, link.callback):
				sender.disconnect(link.signal, link.callback)


func _connect_owners() -> void:
	_disconnect_owners()
	var self_ref: WeakRef = weakref(self)
	if world.map_data != null:
		var terrain: Callable = func(cells: Array[Vector2i]) -> void:
			var domain: RefCounted = self_ref.get_ref()
			if domain != null:
				if domain._busy or domain.last_ms != domain.world.elapsed_ms:
					domain._fail("unsettled_terrain_change")
					return
				domain._topology_cells = cells.duplicate()
				if not domain.after_topology_change(domain.last_ms, true):
					domain.world.errors.append("Terrain environment publication failed")
		world.map_data.terrain_changed.connect(terrain)
		_connections.append({"owner": weakref(world.map_data), "signal": &"terrain_changed", "callback": terrain})
	for region: String in world.regions:
		var inventory: SimInventory = world.regions[region].inventory
		var region_id: String = region
		var stock: Callable = func(container: String) -> void:
			var domain: RefCounted = self_ref.get_ref()
			if domain != null:
				domain._mark_container(region_id, container)
		var body: Callable = func(id: String) -> void:
			var domain: RefCounted = self_ref.get_ref()
			if domain != null:
				if domain._sources.has_container_sources(region_id, "actor:" + id):
					domain._mark_container(region_id, "actor:" + id)
				var job: Dictionary = domain.world.construction.active.get(id, {})
				if not job.is_empty() and domain._sources.has_container_sources(region_id, str(job.project)):
					domain._mark_container(region_id, str(job.project))
		var crossing: Callable = func(id: String, cell: Vector2i, at_ms: int) -> void:
			var domain: RefCounted = self_ref.get_ref()
			if domain != null:
				domain.record_source_crossing(region_id, "actor:" + id, cell, at_ms)
		inventory.contents_changed.connect(stock)
		world.regions[region].body_space_changed.connect(body)
		world.regions[region].body_cell_crossed.connect(crossing)
		_connections.append({"owner": weakref(inventory), "signal": &"contents_changed", "callback": stock})
		_connections.append({"owner": weakref(world.regions[region]), "signal": &"body_space_changed", "callback": body})
		_connections.append({"owner": weakref(world.regions[region]), "signal": &"body_cell_crossed", "callback": crossing})


func record_source_crossing(region: String, container: String, cell: Vector2i, at_ms: int) -> void:
	if not _active or not _sources.has_container_sources(region, container):
		return
	var keys: Array[String] = _sources.container_keys(region, container)
	if keys.is_empty():
		return
	if at_ms < last_ms:
		_fail("late_source_crossing")
		return
	motion_sampling_work.crossings += keys.size()
	for key: String in keys:
		var source: Dictionary = _sources.get_source(key)
		var due: int = SimCadence.at_or_after(at_ms, SimCadence.source_motion_ms(source.channels))
		if due == last_ms:
			source.cell = cell
			if not _change_source(key, source, at_ms):
				_fail("moving_source")
				return
			motion_sampling_work.adopted += 1
			continue
		var merged: bool = false
		for row: Dictionary in _motion_changes:
			if int(row.at_ms) == due and row.keys[0] == key:
				row.cell = cell
				row.changed_ms = at_ms
				merged = true
				motion_sampling_work.coalesced += 1
				break
		if not merged:
			_motion_changes.append({"at_ms": due, "changed_ms": at_ms, "cell": cell, "keys": [key]})
	_motion_changes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.at_ms) < int(b.at_ms) if a.at_ms != b.at_ms else str(a.keys[0]) < str(b.keys[0]))


func _motion_sample(key: String) -> Dictionary:
	for index: int in range(_motion_changes.size() - 1, -1, -1):
		if _motion_changes[index].keys[0] == key:
			return _motion_changes[index]
	return {}


func _erase_motion_samples(key: String) -> void:
	for index: int in range(_motion_changes.size() - 1, -1, -1):
		if _motion_changes[index].keys[0] == key:
			_motion_changes.remove_at(index)


func _refresh_container_source(key: String, source: Dictionary, now: int) -> bool:
	# body_space_changed follows crossing notifications too. Do not turn that
	# ordinary dirty notification into an immediate duplicate field rebuild.
	var queued: Dictionary = _motion_sample(key)
	if not queued.is_empty() and not source.is_empty():
		var sampled: Dictionary = _sources.get_source(key)
		if not sampled.is_empty():
			sampled.cell = queued.cell
			if sampled == source:
				return true
	# Changed strength, transfer, disappearance or an actual teleport wins over
	# a previously queued position. Its old candidate cannot move it back later.
	_erase_motion_samples(key)
	return _change_source(key, source, now)


func capture_motion_samples() -> Array:
	var result: Array = []
	for row: Dictionary in _motion_changes:
		var key: String = row.keys[0]
		var source: Dictionary = _sources.get_source(key)
		if source.is_empty():
			continue
		result.append({"key": key, "at_ms": row.at_ms, "changed_ms": row.changed_ms,
			"cell": [row.cell.x, row.cell.y], "sampled_cell": [source.cell.x, source.cell.y]})
	return result


func needs_native_crossings(id: String, region: String) -> bool:
	if world.space != null and world.space.needs_native_crossings():
		return true
	if not _active or _dirty_containers.has(JSON.stringify([region, "actor:" + id])) or _sources.has_container_sources(region, "actor:" + id):
		return true
	var job: Dictionary = world.construction.active.get(id, {})
	return not job.is_empty() and _sources.has_container_sources(region, str(job.project))


func _mark_container(region: String, container: String) -> void:
	_dirty_containers[JSON.stringify([region, container])] = [region, container]


func flush_sources(now: int) -> bool:
	if not _active:
		return true
	if _busy or now != last_ms:
		return false
	var keys: Array = _dirty_containers.keys()
	keys.sort()
	for key: String in keys:
		var pair: Array = _dirty_containers[key]
		for item: String in _sources.container_items(pair[0], pair[1]):
			if not _refresh_container_source(Participant.stock_key(pair[0], pair[1], item), _sources.stock_source(pair[0], pair[1], item), now):
				return false
		var ids: Dictionary = world.object_lifecycle._contained.get(key, {}).get("ids", {}).duplicate()
		for id: String in world.artifacts.legacy_object_ids():
			var row: Dictionary = world.artifacts.objects[id]
			if row.region == pair[0] and row.container == pair[1]:
				ids[id] = true
		var ordered: Array = ids.keys()
		ordered.sort()
		for id: String in ordered:
			var projection: Dictionary = _sources.current_artifact_source(id)
			if not bool(projection.get("ok", false)) or not _refresh_container_source(Participant.artifact_key(id), projection.source, now):
				return _fail("carrier_source")
		_dirty_containers.erase(key)
	return true
