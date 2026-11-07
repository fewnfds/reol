class_name SimWorldEnvironmentFields
extends RefCounted
## The ordinary world's only actual temperature/element authority. local_heat
## is retained as a consumer-facing name, never as a second Q diffusion model.
## Source indexes are disposable projections over original object owners.

const VERSION: int = 4
const MODEL: String = "outdoor_fields_v1"
const SIZE: int = SimGroundPlacements.MAP_SIZE
const MAX_TIME: int = SimEnvironmentTemperatureState.MAX_TIME
const TAU_MS: int = 30000
const TIDE_GRID_MS: int = 60000
const MAX_TRANSIENT: int = 128
const ANCHOR_QUANTUM: float = 0.000000001
const Field = preload("res://scripts/sim/environment_ground_field.gd")
const Temperature = preload("res://scripts/sim/environment_temperature_state.gd")
const Phases = preload("res://scripts/sim/environment_phase_state.gd")
const Targets = preload("res://scripts/sim/environment_response_targets.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const Compiler = preload("res://scripts/sim/environment_target_compiler.gd")
const Participant = preload("res://scripts/sim/world_environment_source_participant.gd")
const Background = preload("res://scripts/sim/world_environment_background.gd")

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
var _samples: Dictionary = {}
var _transient: Dictionary = {}
var _active: bool = false
var _busy: bool = false
var _error: String = ""

var world: RegionalSimulation:
	get: return _owner.get_ref() if _owner != null else null


func initialize(authority: RegionalSimulation, rules: Dictionary) -> bool:
	if _owner != null or authority == null or authority._content == null or authority._content.environment_sources == null or not SimLocalHeat.valid_definitions(rules):
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
	if not _rebuild_base() or not _refresh_targets(activation_ms, true):
		return false
	_active = true
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
	var owner: WeakRef = weakref(self)
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
		and _targets.configure(_temperature, _phases, _settings, reader) \
		and _sources.configure(world, _field, _temperature, _phases, _settings,
			initial, phase_initial, transform)


func next_boundary_ms() -> int:
	if not _active:
		# Activating is an assembly operation, not a zero-time boundary.
		return MAX_TIME
	var next: int = _background.next_boundary_ms()
	for value: int in [_temperature.next_boundary_ms(), _phases.next_boundary_ms()]:
		if value >= 0:
			next = mini(next, value)
	for source: Dictionary in _transient.values():
		next = mini(next, int(source.until_ms))
	for id: String in world.artifacts.legacy_object_ids():
		var item: Dictionary = world.artifacts.objects[id]
		if not _device_active(id):
			continue
		var rule: Dictionary = world.artifacts.definitions.types[item.definition].thermal
		var remaining: int = int(item.stored_q) if rule.mode == "emit" else int(rule.capacity_q) - int(item.stored_q)
		var rate: int = int(rule.rate_q_per_ms)
		next = mini(next, last_ms + (remaining / rate) + (1 if remaining % rate else 0))
	return next


func can_settle_at_ms(now: int) -> bool:
	return world != null and not _busy and _error.is_empty() and now >= last_ms and now < MAX_TIME


func settle_at_ms(now: int) -> bool:
	if not can_settle_at_ms(now) or not activate_sources():
		return false
	while last_ms < now:
		var end: int = mini(now, next_boundary_ms())
		if end <= last_ms:
			return _fail("nonprogressing_environment_boundary")
		var delta: int = end - last_ms
		# Original device stock remains in the artifact owner. The field does
		# not implement or claim energy conservation between fantasy sources.
		var depleted: Array[String] = []
		for id: String in world.artifacts.legacy_object_ids():
			if not _device_active(id):
				continue
			var item: Dictionary = world.artifacts.objects[id]
			var rule: Dictionary = world.artifacts.definitions.types[item.definition].thermal
			var available: int = int(item.stored_q) if rule.mode == "emit" else int(rule.capacity_q) - int(item.stored_q)
			var spent: int = mini(available, delta * int(rule.rate_q_per_ms))
			item.stored_q = int(item.stored_q) + (-spent if rule.mode == "emit" else spent)
			if spent == available:
				depleted.append(id)
		if not _background.advance_to_ms(end):
			return _fail("background_advance")
		# Refresh old-source target segments at their exact boundary first;
		# source expiry then reanchors at the same millisecond with no jump.
		if end == _temperature.next_boundary_ms() or end == _phases.next_boundary_ms():
			if not _refresh_targets(end, false):
				return false
		last_ms = end
		for id: String in depleted:
			var key: String = Participant.artifact_key(id)
			var source: Dictionary = _sources.get_source(key)
			if not source.is_empty():
				source = _transform_source(key, source)
				if not _change_source(key, source, end):
					return false
		for key: String in _transient.keys():
			if int(_transient[key].until_ms) <= end:
				if not _change_source(key, {}, end):
					return false
				_transient.erase(key)
	return true


func prepare_object_change(request: Dictionary) -> Dictionary:
	if _busy or not _error.is_empty() or not activate_sources() or not settle_at_ms(world.elapsed_ms):
		return {"ok": false, "reason": "environment_unavailable"}
	var prepared: Dictionary = _sources.prepare_object_change(request)
	if bool(prepared.get("ok", false)):
		_busy = true
	return prepared


func finish_object_change(result: Dictionary, proof: Variant) -> Dictionary:
	var committed: Dictionary = _sources.finish_object_change(result, proof)
	if bool(committed.get("ok", false)):
		for key: Vector2i in _sources.affected_chunks():
			_chunks[key] = true
	_busy = false
	return committed


func cancel_object_change(proof: Variant) -> bool:
	var cancelled: bool = _sources.cancel_object_change(proof)
	_busy = false
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
	receipts[receipt.action] = receipt.duplicate(true)
	return true


func _change_source(key: String, source: Dictionary, at_ms: int) -> bool:
	var prepared: Dictionary = _sources.prepare_source_change(key, source, at_ms)
	if not bool(prepared.get("ok", false)):
		return false # Rejected candidates have not changed either domain.
	if not _sources.finish_source_change(prepared.proof):
		return _fail("source_publication")
	for chunk: Vector2i in _sources.affected_chunks():
		_chunks[chunk] = true
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


func mark_sample(now: int) -> bool:
	if _busy or now != last_ms or not activate_sources():
		return false
	var cells: Dictionary[Vector2i, bool] = {}
	for region: VillageSimulation in world.regions.values():
		for person: Dictionary in region.actors.values():
			cells[SimRouteTravel.cell(person.cell)] = true
		for id: String in region.land_resources.sources:
			var place_id: String = str(region.config.resource_sources[id].place)
			var place: Dictionary = region.places.get(place_id, {})
			if place.has("cell"):
				cells[SimRouteTravel.cell(place.cell)] = true
	var candidate: Dictionary = {}
	for cell: Vector2i in cells:
		var projected: Dictionary = project_tenths(cell, now)
		if not bool(projected.get("supported", false)):
			return false
		candidate[_key(cell)] = int(projected.value)
	_samples = candidate
	last_sample_ms = now
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
	# Conservative: retain location in exposure records even for phase-only
	# tracked chunks. This query does not scan or integrate the map.
	return not _chunks.is_empty()


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
	for id: String in world.artifacts.legacy_object_ids():
		if _device_active(id):
			var rule: Dictionary = world.artifacts.definitions.types[world.artifacts.objects[id].definition].thermal
			if rule.mode == "emit":
				rates[id] = int(rule.rate_q_per_ms)
	return {"supported": true, "rates": rates}


func _refresh_targets(at_ms: int, activation: bool) -> bool:
	for key: Vector2i in _sorted_chunks():
		var opened: Dictionary = _targets.begin(Rect2i(key * 16, Vector2i(16, 16)), at_ms, activation)
		if not bool(opened.get("ok", false)):
			return _fail(str(opened.get("reason", "target_begin")))
		var handle: Variant = opened.handle
		while true:
			var progress: Dictionary = _targets.step(handle, 256)
			if not bool(progress.get("ok", false)):
				return _fail(str(progress.get("reason", "target_step")))
			if not bool(progress.get("pending", true)):
				break
		var finished: Dictionary = _targets.finish(handle)
		if not bool(finished.get("ok", false)) or not bool(_targets.commit(finished.proof).get("ok", false)):
			return _fail("target_publication")
	return true


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
	if not activate_sources() or _busy:
		return {}
	return load("res://scripts/persistence/world_environment_fields_state.gd").capture(self)


func restore(data: Variant) -> bool:
	if not data is Dictionary or _active or _busy:
		return false
	return load("res://scripts/persistence/world_environment_fields_state.gd").restore_into(self, data)


func diagnostics() -> Dictionary:
	return {"model": MODEL, "active": _active, "error": _error, "at_ms": last_ms,
		"tracked_chunks": _chunks.size(), "transient_sources": _transient.size(),
		"geometry": "outdoor_no_room_attenuation", "source": _sources.diagnostics() if _active else {}}
