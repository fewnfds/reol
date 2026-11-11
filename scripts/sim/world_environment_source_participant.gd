class_name SimWorldEnvironmentSourceParticipant
extends RefCounted
## Production source participant. Source positions and slot numbers here are
## disposable indexes; real objects, quantities, clocks and actual response
## anchors remain with their original owners. No player knowledge is exposed.
##
## An object operation is prepared before its original owner mutates. The
## caller must recheck can_commit(), publish the original change, and finish
## synchronously without a callback or signal in between. A rejected original
## operation must cancel the same proof. Only one candidate can be outstanding.

const Bindings = preload("res://scripts/sim/environment_source_bindings.gd")
const Change = preload("res://scripts/sim/environment_source_change.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const Field = preload("res://scripts/sim/environment_field_cache.gd")
const SIDE: int = 16
const MAX_SYNC_STEPS: int = 1_000_000

var _world_ref: WeakRef
var _world: RegionalSimulation:
	get: return _world_ref.get_ref() if _world_ref != null else null
var _definitions: EnvironmentSourceDefinitions
var _field: RefCounted
var _query: RefCounted
var _changes: RefCounted
var _transform: Callable
# Reference -> integer slot. The field already owns packed positions/channels;
# do not allocate a second source dictionary and array for every ground pile.
var _records: Dictionary = {}
var _free: Array[int] = []
var _next_slot: int = 0
var _capacity: int = 0
var _affected_chunks: Dictionary = {}
var _pending: Dictionary = {}
var _built: bool = false
var _failed: bool = false
var _last_change_chunks: Array[Vector2i] = []
var _last_temperature_chunks: Array[Vector2i] = []
var _last_phase_chunks: Array[Vector2i] = []
# Disposable participation over accepted, nonzero field records. Moving an
# empty/ordinary pocket must not enumerate all materials and legacy objects.
var _container_sources: Dictionary = {}
var _source_containers: Dictionary[String, Array] = {}


static func artifact_key(id: String) -> String:
	return "artifact:" + id


static func stock_key(region: String, container: String, item: String) -> String:
	return "stock:" + JSON.stringify([region, container, item], "", true)


func configure(world: RegionalSimulation, field: RefCounted, temperature: RefCounted, phases: RefCounted, settings: Dictionary, initial_temperature: Callable, initial_phase: Callable, source_transform: Callable = Callable()) -> bool:
	if _world != null or world == null or world._content == null or world._content.environment_sources == null:
		return false
	if field == null or temperature == null or phases == null or not initial_temperature.is_valid() or not initial_phase.is_valid():
		return false
	var query := Bindings.new()
	if not query.configure(world, world._content.environment_sources):
		return false
	var changes := Change.new()
	if not changes.configure(field, temperature, settings, initial_temperature, phases, initial_phase):
		return false
	var capacity: int = int(field.diagnostics().get("capacity", 0))
	if capacity <= 0:
		return false
	_world_ref = weakref(world)
	_definitions = world._content.environment_sources
	_field = field
	_query = query
	_changes = changes
	_capacity = capacity
	_transform = source_transform
	return true


func bind_world(world: RegionalSimulation) -> bool:
	# The regional restore candidate is first fully validated, then its owners
	# are rebound to the live regional shell. No source or field is recreated.
	if world == null or _world == null or not _pending.is_empty() or _failed:
		return false
	if world._content == null or world._content.environment_sources == null or world._content.environment_sources.digest() != _definitions.digest():
		return false
	if world.object_lifecycle != _world.object_lifecycle or world.artifacts != _world.artifacts or world.regions != _world.regions:
		return false
	var query := Bindings.new()
	if not query.configure(world, _definitions):
		return false
	_world_ref = weakref(world)
	_query = query
	return true


func build_sources() -> Dictionary:
	# Invoke on a candidate world after the original opening/restore is complete
	# and relevant regions are synchronized. Failure discards this participant.
	if _world == null or _built or _failed or not _pending.is_empty():
		return _failure("invalid_state")
	var ids: Array = _world.object_lifecycle.ground.slots.keys()
	ids.sort()
	for slot_id: String in ids:
		var slot: Dictionary = _world.object_lifecycle.ground.slots[slot_id]
		if not bool(slot.get("active", false)):
			continue
		if not str(slot_id).begins_with("ground:") or not slot.get("reference") is Dictionary:
			return _build_failure("invalid_ground_reference")
		# The independent restore candidate may legitimately retain target-time
		# debt. Read the checked committed slot at elapsed_ms without treating
		# the future target as already completed or clearing that debt.
		var projected: Dictionary = _query.project_ground_slot(_world, slot, slot_id)
		if not bool(projected.get("ok", false)):
			return _build_failure(str(projected.get("reason", "source_projection")))
		if projected.get("status") == "source":
			var reference: Dictionary = slot.reference
			var key: String = artifact_key(str(reference.id)) if reference.kind == "artifact" else stock_key(str(reference.region), str(reference.container), str(reference.item))
			var source: Dictionary = _source(projected.cell, int(projected.radius_cells), projected.elements, int(projected.thermal_grade))
			var transformed: Dictionary = _apply_transform(key, source)
			if not bool(transformed.get("ok", false)) or not _add_initial(key, transformed.source):
				return _build_failure(str(transformed.get("reason", "source_index")))
	# Legacy artifacts and lifecycle-owned contained artifacts have separate
	# original indexes; scan them once at activation, never once per frame.
	var fixed: Dictionary = {}
	for id: String in _world.artifacts.legacy_object_ids():
		fixed[id] = true
	# The independent candidate has restored original identities before its
	# final cross-validation rebuilds the disposable _contained lookup. Build
	# from those originals once, not from an as-yet-empty derived index.
	for id: String in _world.object_lifecycle.created:
		var item: Variant = _world.artifacts.objects.get(id)
		if item is Dictionary and not str(item.container).begins_with("ground:"):
			fixed[id] = true
	var fixed_ids: Array = fixed.keys()
	fixed_ids.sort()
	for id: String in fixed_ids:
		var item: Variant = _world.artifacts.objects.get(id)
		if not item is Dictionary:
			return _build_failure("invalid_artifact")
		var container: String = str(item.get("container", ""))
		if container.begins_with("ground:"):
			continue
		var projected: Dictionary = current_artifact_source(id)
		if not bool(projected.get("ok", false)):
			return _build_failure(str(projected.get("reason", "artifact_projection")))
		if not projected.source.is_empty() and not _add_initial(artifact_key(id), projected.source):
			return _build_failure("source_index")
	for region: String in _world.regions:
		for container: String in _world.regions[region].inventory.containers:
			if container.begins_with("ground:"):
				continue
			for item: String in _world.regions[region].inventory.containers[container]:
				var source: Dictionary = stock_source(region, container, item)
				if not source.is_empty():
					var key: String = stock_key(region, container, item)
					if not _add_initial(key, source):
						return _build_failure("contained_stock_source")
	for id: String in _world.construction._project_ids():
		var source: Dictionary = construction_source(id)
		if not source.is_empty() and not _add_initial("construction:" + id, source):
			return _build_failure("construction_source")
	if _world.plants != null:
		var plants: Array = _world.plants.bodies.keys()
		plants.sort()
		for id: String in plants:
			var source: Dictionary = _world.plants.source_for(id)
			if not source.is_empty() and not _add_initial("plant:" + id, source):
				return _build_failure("plant_source")
	_built = true
	return {"ok": true, "source_count": _records.size(), "affected_chunks": affected_chunks()}


func affected_chunks() -> Array[Vector2i]:
	# Retain chunks ever touched: after a source leaves their actual residual may
	# still exist. Sorting makes activation and snapshots independent of hash order.
	var result: Array[Vector2i] = []
	result.assign(_affected_chunks.keys())
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return result


func last_change_chunks() -> Array[Vector2i]:
	# The last successful publication only. Historical residual coverage stays
	# in affected_chunks(), but must not be copied/sorted after every operation.
	return _last_change_chunks.duplicate()


func last_temperature_chunks() -> Array[Vector2i]:
	return _last_temperature_chunks.duplicate()


func last_phase_chunks() -> Array[Vector2i]:
	return _last_phase_chunks.duplicate()


func get_source(key: String) -> Dictionary:
	if not _records.has(key):
		return {}
	var slot: int = int(_records[key])
	var channels := PackedInt32Array()
	channels.resize(7)
	for channel: int in 7:
		channels[channel] = int(_field._slot_channels[slot * 7 + channel])
	return {"cell": Vector2i(int(_field._slot_x[slot]), int(_field._slot_y[slot])),
		"radius": int(_field._slot_radius[slot]), "channels": channels}


func add_transient_initial(key: String, source: Dictionary) -> bool:
	# Restore-only rebuild of the disposable field before candidate publication.
	# It does not touch actual anchors; the caller validates the saved receipt,
	# lifetime and compiled target against the original world before accepting.
	if not _available() or not key.begins_with("pulse:") or key.length() <= 6 or not _valid_source(source):
		return false
	if _is_zero(source):
		return false
	return _add_initial(key, source)


func current_artifact_source(id: String) -> Dictionary:
	if _world == null or _world.artifacts == null or not _world.artifacts.objects.has(id):
		return _failure("not_found")
	var item: Dictionary = _world.artifacts.objects[id]
	var location: Dictionary = SimEntityQuery.locate(_world, {"kind": "artifact", "id": id})
	if not bool(location.get("ok", false)):
		return _failure("unavailable_artifact_location")
	var profile: Dictionary = _definitions.profile("artifact", str(item.definition))
	if not bool(profile.get("ok", false)):
		return profile
	var point: Vector2i = location.cell
	if str(item.container).begins_with("ground:"):
		var slot: Dictionary = _world.object_lifecycle.ground.slots[item.container]
		var size := Vector2i(int(slot.size[0]), int(slot.size[1]))
		point += Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
	var raw: Dictionary = _source(point, int(profile.radius_cells), profile.elements, int(profile.thermal_grade))
	_attenuate_container(raw, str(item.container))
	var transformed: Dictionary = _apply_transform(artifact_key(id), raw)
	if not bool(transformed.get("ok", false)):
		return transformed
	return {"ok": true, "source": {} if _is_zero(transformed.source) else transformed.source}


func diagnostics() -> Dictionary:
	return {"built": _built, "failed": _failed, "source_count": _records.size(),
		"slot_high_water": _next_slot, "free_slots": _free.size(),
		"affected_chunks": _affected_chunks.size(), "candidate_pending": not _pending.is_empty()}


func prepare_source_change(key: String, new_source: Dictionary, at_ms: int) -> Dictionary:
	if key.strip_edges().is_empty():
		return _failure("invalid_reference")
	return _prepare_transition(key if _records.has(key) else "", key if not new_source.is_empty() else "", new_source, at_ms)


func begin_source_change(key: String, new_source: Dictionary, at_ms: int, allow_compute: bool = false) -> Dictionary:
	if key.strip_edges().is_empty():
		return _failure("invalid_reference")
	return _begin_transition(key if _records.has(key) else "", key if not new_source.is_empty() else "", new_source, at_ms, allow_compute)


func step_source_change(proof: Variant, field_work: int, cell_budget: int) -> Dictionary:
	if _pending.is_empty() or not is_same(_pending.token, proof):
		return _failure("invalid_commit")
	if field_work < 1 or field_work > Field.MAX_WORK or cell_budget < 0 or cell_budget > SIDE * SIDE:
		return _failure("work_budget")
	if _pending.kind != "preparing":
		return {"ok": true, "pending": false}
	var progress: Dictionary = _changes.step(_pending.handle, field_work, cell_budget)
	if not bool(progress.get("ok", false)):
		_pending = {} # The coordinator has already cancelled its domain candidates.
		return progress
	if bool(progress.get("pending", true)):
		return {"ok": true, "pending": true, "waiting": bool(progress.get("waiting", false))}
	var finished: Dictionary = _changes.finish(_pending.handle)
	if not bool(finished.get("ok", false)):
		_changes.cancel(_pending.handle)
		_pending = {}
		return finished
	_pending.kind = "change"
	_pending.field_proof = finished.proof
	return {"ok": true, "pending": false}


func prepare_object_change(request: Dictionary) -> Dictionary:
	if not _available() or not request.get("op") is String:
		return _failure("invalid_state")
	var op: String = request.op
	if op in ["spawn", "move", "remove", "artifact_transfer"]:
		return _prepare_artifact(request)
	if op == "stock_transfer":
		return _prepare_stock(request)
	return _failure("unsupported_operation")


func can_commit(proof: Variant) -> bool:
	if _pending.is_empty() or not is_same(_pending.token, proof) or _pending.kind == "preparing":
		return false
	return bool(_changes.can_commit(_pending.field_proof).get("ok", false)) if _pending.kind == "change" else true


func finish_source_change(proof: Variant) -> bool:
	if not can_commit(proof):
		return false
	_last_change_chunks.clear()
	_last_temperature_chunks.clear()
	_last_phase_chunks.clear()
	if _pending.kind == "change":
		var committed: Dictionary = _changes.commit(_pending.field_proof)
		assert(bool(committed.get("ok", false)), "preflighted environment source commit failed")
		_last_change_chunks.assign(committed.get("touched_chunks", []))
		_last_temperature_chunks.assign(committed.get("temperature_chunks", []))
		_last_phase_chunks.assign(committed.get("phase_chunks", []))
		var old_key: String = _pending.old_key
		var new_key: String = _pending.new_key
		var slot: int = _pending.slot
		if not old_key.is_empty():
			_records.erase(old_key)
		if not new_key.is_empty():
			_records[new_key] = slot
			_touch(_pending.source)
		elif not old_key.is_empty():
			_free.append(slot)
		if _pending.allocation == "free":
			_free.pop_back()
		elif _pending.allocation == "new":
			_next_slot += 1
	elif _pending.kind == "change_reference":
		var entry: int = int(_records[_pending.old_key])
		_records.erase(_pending.old_key)
		_records[_pending.new_key] = entry
	# Even a physically identical transfer can change the carrying container.
	# Reindex only after the original object and the field proof both commit.
	if _pending.has("old_key"):
		_index_source_container(str(_pending.old_key))
	if _pending.has("new_key") and _pending.new_key != _pending.old_key:
		_index_source_container(str(_pending.new_key))
	_pending = {}
	return true


func finish_object_change(result: Dictionary, proof: Variant) -> Dictionary:
	# The original lifecycle owns the business result. It invokes this only
	# after its successful synchronous write, with no intervening observer.
	if not bool(result.get("ok", false)) or not can_commit(proof):
		return _failure("invalid_commit")
	return {"ok": finish_source_change(proof)}


func cancel_source_change(proof: Variant) -> bool:
	if _pending.is_empty() or not is_same(_pending.token, proof):
		return false
	if _pending.kind in ["change", "preparing"]:
		var cancelled: Dictionary = _changes.cancel(_pending.handle)
		if not bool(cancelled.get("ok", false)):
			return false
	_pending = {}
	return true


func cancel_object_change(proof: Variant) -> bool:
	return cancel_source_change(proof)


func _prepare_transition(old_key: String, new_key: String, source: Dictionary, at_ms: int) -> Dictionary:
	# Object operations require a prepared proof before their synchronous write.
	# Internal world settlement uses the same coordinator with bounded resumes.
	var opened: Dictionary = _begin_transition(old_key, new_key, source, at_ms)
	if not bool(opened.get("ok", false)):
		return opened
	for _step: int in MAX_SYNC_STEPS:
		var progress: Dictionary = step_source_change(opened.proof, Field.MAX_WORK, SIDE * SIDE)
		if not bool(progress.get("ok", false)):
			return progress
		if not bool(progress.get("pending", true)):
			return opened
	cancel_source_change(opened.proof)
	return _failure("source_work_limit")


func _begin_transition(old_key: String, new_key: String, source: Dictionary, at_ms: int, allow_compute: bool = false) -> Dictionary:
	if not _available() or at_ms < 0 or at_ms >= Change.Temperature.MAX_TIME:
		return _failure("invalid_state")
	if not old_key.is_empty() and not _records.has(old_key):
		return _failure("source_missing")
	if not new_key.is_empty() and _records.has(new_key) and new_key != old_key:
		return _failure("source_exists")
	if new_key.is_empty() != source.is_empty() or not source.is_empty() and not _valid_source(source):
		return _failure("invalid_source")
	var token := RefCounted.new()
	if old_key.is_empty() and new_key.is_empty():
		_pending = {"kind": "none", "token": token}
		return {"ok": true, "proof": token, "changed": false}
	if not old_key.is_empty() and not new_key.is_empty() and get_source(old_key) == source:
		_pending = {"kind": "rename", "token": token, "old_key": old_key, "new_key": new_key}
		# Same physical source and location: only the derived reference changes.
		if old_key != new_key:
			_pending.kind = "change_reference"
		return {"ok": true, "proof": token, "changed": false}
	var slot: int = -1
	var allocation: String = "existing"
	if not old_key.is_empty():
		slot = int(_records[old_key])
	elif not _free.is_empty():
		slot = _free.back()
		allocation = "free"
	elif _next_slot < _capacity:
		slot = _next_slot
		allocation = "new"
	else:
		return _failure("source_capacity")
	var operation: String = "remove" if new_key.is_empty() else "set"
	var opened: Dictionary = _changes.begin(slot, operation, source, at_ms, Change.Temperature.MAX_TIME, allow_compute)
	if not bool(opened.get("ok", false)):
		return opened
	_pending = {"kind": "preparing", "token": token, "handle": opened.handle,
		"slot": slot, "allocation": allocation, "old_key": old_key,
		"new_key": new_key, "source": source.duplicate(true)}
	return {"ok": true, "proof": token, "changed": true}


func _prepare_artifact(request: Dictionary) -> Dictionary:
	if not request.get("id") is String or str(request.id).is_empty():
		return _failure("invalid_reference")
	var id: String = request.id
	var op: String = request.op
	var existing: Variant = _world.artifacts.objects.get(id)
	var definition: String
	if op == "spawn":
		definition = str(request.get("definition", ""))
	elif existing is Dictionary:
		definition = str(existing.get("definition", ""))
		if not request.get("from") is Dictionary or request.from.get("region") != existing.region or request.from.get("container") != existing.container:
			return _failure("source_changed")
	else:
		return _failure("not_found")
	var key: String = artifact_key(id)
	var old_key: String = key if _records.has(key) else ""
	if op != "spawn" and not _artifact_location_emits(existing) and not old_key.is_empty():
		return _failure("source_index_mismatch")
	if op != "spawn" and _artifact_location_emits(existing):
		var old_projection: Dictionary = current_artifact_source(id)
		if not bool(old_projection.get("ok", false)):
			return old_projection
		if old_projection.source.is_empty() != old_key.is_empty() or not old_key.is_empty() and old_projection.source != get_source(old_key):
			return _failure("source_index_mismatch")
	var source: Dictionary = {}
	if op != "remove":
		if not request.get("to") is Dictionary:
			return _failure("invalid_location")
		var target: Dictionary = _artifact_at(id, definition, request.to)
		if not bool(target.get("ok", false)):
			return target
		source = target.source
	return _prepare_transition(old_key, key if not source.is_empty() else "", source, int(request.get("at_ms", _world.elapsed_ms)))


func _prepare_stock(request: Dictionary) -> Dictionary:
	if not request.get("from") is Dictionary or not request.get("to") is Dictionary or not request.get("item") is String or not SimAvianLife.Schema.count(request.get("amount"), 1):
		return _failure("invalid_request")
	var origin: Dictionary = request.from
	var target: Dictionary = request.to
	if not origin.get("region") is String or not origin.get("container") is String or target.get("region") != origin.region or not _world.regions.has(origin.region):
		return _failure("invalid_location")
	if not SimInventory._nonempty(request.get("item")) or not SimInventory._nonempty(request.get("command")):
		return _failure("invalid_request")
	var inventory: SimInventory = _world.regions[origin.region].inventory
	if not inventory.containers.has(origin.container) or inventory.quantity(origin.container, request.item) < int(request.amount):
		return _failure("insufficient_stock")
	var old_key: String = ""
	if str(origin.container).begins_with("ground:"):
		var slot: Variant = _world.object_lifecycle.ground.slots.get(origin.container)
		if not slot is Dictionary or not bool(slot.get("active", false)) or slot.get("reference") != {"kind": "stock", "domain": "village", "region": origin.region, "container": origin.container, "item": request.item}:
			return _failure("source_changed")
		var quantity: int = inventory.quantity(origin.container, request.item)
		if quantity < int(request.amount):
			return _failure("insufficient_stock")
		var old_profile: Dictionary = _definitions.profile("material", request.item)
		if not bool(old_profile.get("ok", false)):
			return old_profile
		var old_ref: String = stock_key(origin.region, origin.container, request.item)
		var old_cell := Vector2i(int(slot.cell[0]), int(slot.cell[1]))
		var old_raw: Dictionary = _source(old_cell, int(old_profile.radius_cells), old_profile.elements, int(old_profile.thermal_grade))
		var old_transformed: Dictionary = _apply_transform(old_ref, old_raw)
		if not bool(old_transformed.get("ok", false)):
			return old_transformed
		if _records.has(old_ref) == _is_zero(old_transformed.source) or _records.has(old_ref) and get_source(old_ref) != old_transformed.source:
			return _failure("source_index_mismatch")
		if quantity == int(request.amount):
			if _records.has(old_ref):
				old_key = old_ref
	var new_key: String = ""
	var source: Dictionary = {}
	if target.has("cell"):
		if not SimAvianLife.Schema.cell_valid(target.cell):
			return _failure("invalid_cell")
		var cell := Vector2i(int(target.cell[0]), int(target.cell[1]))
		var destination: Dictionary = _world.object_lifecycle.stock_destination(origin.region, cell, request.item)
		if not bool(destination.get("ok", false)):
			return destination
		if not destination.has("container"):
			var profile: Dictionary = _definitions.profile("material", request.item)
			if not bool(profile.get("ok", false)):
				return profile
			var raw: Dictionary = _source(cell, int(profile.radius_cells), profile.elements, int(profile.thermal_grade))
			new_key = stock_key(origin.region, "ground:" + str(request.get("command", "")), request.item)
			var transformed: Dictionary = _apply_transform(new_key, raw)
			if not bool(transformed.get("ok", false)):
				return transformed
			source = transformed.source
			if _is_zero(source):
				new_key = ""
				source = {}
		else:
			if destination.container == origin.container:
				return _failure("same_location")
			if inventory.quantity(destination.container, request.item) > SimInventory.MAX_COUNT - int(request.amount):
				return _failure("quantity_overflow")
			var destination_key: String = stock_key(origin.region, str(destination.container), request.item)
			var destination_profile: Dictionary = _definitions.profile("material", request.item)
			if not bool(destination_profile.get("ok", false)):
				return destination_profile
			var destination_raw: Dictionary = _source(cell, int(destination_profile.radius_cells), destination_profile.elements, int(destination_profile.thermal_grade))
			var projected: Dictionary = _apply_transform(destination_key, destination_raw)
			if not bool(projected.get("ok", false)):
				return projected
			if _records.has(destination_key) == _is_zero(projected.source) or _records.has(destination_key) and get_source(destination_key) != projected.source:
				return _failure("source_index_mismatch")
	return _prepare_transition(old_key, new_key, source, int(request.get("at_ms", _world.elapsed_ms)))


func _artifact_at(id: String, definition: String, location: Dictionary) -> Dictionary:
	if not location.get("region") is String or not _world.regions.has(location.region):
		return _failure("invalid_location")
	var point := Vector2i(-1, -1)
	if location.has("cell"):
		if not SimAvianLife.Schema.cell_valid(location.cell):
			return _failure("invalid_cell")
		var item_definition: Variant = _world.artifacts.definitions.types.get(definition)
		if not item_definition is Dictionary or not item_definition.get("placement") is Dictionary or not item_definition.placement.get("footprint") is Array or item_definition.placement.footprint.size() != 2:
			return _failure("invalid_definition")
		var size := Vector2i(int(item_definition.placement.footprint[0]), int(item_definition.placement.footprint[1]))
		point = Vector2i(int(location.cell[0]), int(location.cell[1])) + Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
	else:
		if not location.get("container") is String:
			return _failure("invalid_location")
		var container: String = location.container
		if container.begins_with("site:"):
			if _world.field_opportunities == null or not _world.artifacts.valid_location(location.region, container):
				return _failure("invalid_location")
			point = _world.field_opportunities.slot_cell(location.region, container)
		else:
			var place: Dictionary = SimStorageQuery.locate(_world, {"domain": "village", "region": location.region, "container": container})
			if not bool(place.get("ok", false)):
				return _failure("unavailable_location")
			point = place.cell
	var profile: Dictionary = _definitions.profile("artifact", definition)
	if not bool(profile.get("ok", false)):
		return profile
	var source: Dictionary = _source(point, int(profile.radius_cells), profile.elements, int(profile.thermal_grade))
	_attenuate_container(source, str(location.get("container", "")))
	var transformed: Dictionary = _apply_transform(artifact_key(id), source)
	if not bool(transformed.get("ok", false)):
		return transformed
	return {"ok": true, "source": {} if _is_zero(transformed.source) else transformed.source}


func _apply_transform(key: String, source: Dictionary) -> Dictionary:
	var value: Variant = _transform.call(key, source.duplicate(true)) if _transform.is_valid() else source
	if not value is Dictionary or not _valid_source(value):
		return _failure("invalid_source_transform")
	return {"ok": true, "source": value.duplicate(true)}


func _add_initial(key: String, source: Dictionary) -> bool:
	if _records.has(key) or not _valid_source(source):
		return false
	if _is_zero(source):
		return true
	if _next_slot >= _capacity:
		return false
	var inserted: Dictionary = _field.set_source(_next_slot, source.cell, source.radius, source.channels)
	if not bool(inserted.get("ok", false)):
		return false
	_records[key] = _next_slot
	_index_source_container(key)
	_next_slot += 1
	_touch(source)
	return true


func _touch(source: Dictionary) -> void:
	var cell: Vector2i = source.cell
	var radius: int = int(source.radius)
	var maximum: int = SimGroundPlacements.MAP_SIZE - 1
	var first := Vector2i(maxi(0, cell.x - radius + 1) >> 4, maxi(0, cell.y - radius + 1) >> 4)
	var last := Vector2i(mini(maximum, cell.x + radius - 1) >> 4, mini(maximum, cell.y + radius - 1) >> 4)
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			_affected_chunks[Vector2i(x, y)] = true


func _available() -> bool:
	return _world != null and _built and not _failed and _pending.is_empty()


static func _source(cell: Vector2i, radius: int, elements: Array, thermal_grade: int) -> Dictionary:
	return {"cell": cell, "radius": radius, "channels": Rules.source_to_packed_channels(elements, thermal_grade)}


static func _valid_source(source: Dictionary) -> bool:
	if source.size() != 3 or not source.get("cell") is Vector2i or not source.get("radius") is int or not source.get("channels") is PackedInt32Array:
		return false
	var cell: Vector2i = source.cell
	if cell.x < 0 or cell.y < 0 or cell.x >= SimGroundPlacements.MAP_SIZE or cell.y >= SimGroundPlacements.MAP_SIZE or source.radius not in EnvironmentSourceDefinitions.RADII or source.channels.size() != 7:
		return false
	for amount: int in source.channels:
		if amount < 0 or amount > EnvironmentSourceDefinitions.GRADE_LIMIT:
			return false
	return true


static func _is_zero(source: Dictionary) -> bool:
	for amount: int in source.channels:
		if amount != 0:
			return false
	return true


static func _artifact_location_emits(item: Dictionary) -> bool:
	return not str(item.get("container", "")).is_empty()


func _attenuate_container(source: Dictionary, container: String) -> void:
	var channels: PackedInt32Array = source.channels
	for channel: int in 7:
		var factor: int = SimEnvironmentLayout.container_transmission(_world, container, "thermal" if channel >= 5 else "elements")
		channels[channel] = (channels[channel] * factor + 5000) / 10000
	source.channels = channels


func construction_source(id: String) -> Dictionary:
	var row: Dictionary = _world.construction.projects.get(id, {})
	if row.is_empty() or row.state != "built":
		return {}
	var rule: Dictionary = _world.construction.definitions.types[row.type]
	var name: String = str(SimEnvironmentLayout.terms(rule).source)
	var profile: Dictionary = _definitions.intrinsic_profile(name) if not name.is_empty() else _definitions.profile("material", str(rule.item))
	if profile.is_empty() or not profile.has("elements"):
		return {}
	var cells: Array[Vector2i] = _world.construction.project_cells(id)
	var size := Vector2i(int(rule.size[0]), int(rule.size[1]))
	if int(row.rotation) % 2:
		size = Vector2i(size.y, size.x)
	var point: Vector2i = SimRouteTravel.cell(row.cell) + Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
	var source: Dictionary = _source(point, int(profile.radius_cells), profile.elements, int(profile.thermal_grade))
	return {} if _is_zero(source) else source


func stock_source(region: String, container: String, item: String) -> Dictionary:
	var inventory: SimInventory = _world.regions[region].inventory
	if inventory.quantity(container, item) == 0:
		return {}
	var profile: Dictionary = _definitions.profile("material", item)
	if not bool(profile.get("ok", false)):
		return {} # Only explicitly registered material capabilities participate.
	var location: Dictionary = SimStorageQuery.locate(_world, {"domain": "village", "region": region, "container": container})
	if not bool(location.get("ok", false)):
		return {}
	var source: Dictionary = _source(location.cell, int(profile.radius_cells), profile.elements, int(profile.thermal_grade))
	_attenuate_container(source, container)
	return {} if _is_zero(source) else source


func _index_source_container(key: String) -> void:
	var previous: Array = _source_containers.get(key, [])
	_reindex_source_container(key)
	var current: Array = _source_containers.get(key, [])
	if previous != current:
		# First/last source or a new carrier changes whether a local cell edge
		# has a world consequence. Recompute that body's existing deadline.
		for pair: Array in [previous, current]:
			if not pair.is_empty() and str(pair[1]).begins_with("actor:"):
				_world.regions[str(pair[0])].invalidate_actor_boundary(str(pair[1]).trim_prefix("actor:"))


func _reindex_source_container(key: String) -> void:
	if key.is_empty():
		return
	var previous: Array = _source_containers.get(key, [])
	if not previous.is_empty():
		var group: Dictionary = _container_sources[previous[0]][previous[1]]
		group.erase(key)
		if group.is_empty():
			_container_sources[previous[0]].erase(previous[1])
			if _container_sources[previous[0]].is_empty():
				_container_sources.erase(previous[0])
		_source_containers.erase(key)
	if not _records.has(key):
		return
	var region: String
	var container: String
	var material: String = ""
	if key.begins_with("stock:"):
		var parts: Array = JSON.parse_string(key.trim_prefix("stock:"))
		region = str(parts[0])
		container = str(parts[1])
		material = str(parts[2])
	elif key.begins_with("artifact:"):
		var item: Dictionary = _world.artifacts.objects[key.trim_prefix("artifact:")]
		region = str(item.region)
		container = str(item.container)
	else:
		return
	if container.begins_with("ground:") or container.is_empty():
		return
	if not _container_sources.has(region):
		_container_sources[region] = {}
	if not _container_sources[region].has(container):
		_container_sources[region][container] = {}
	_container_sources[region][container][key] = material
	_source_containers[key] = [region, container]


func has_container_sources(region: String, container: String) -> bool:
	return _container_sources.get(region, {}).has(container)


func container_items(region: String, container: String) -> Array:
	var values: Dictionary = {}
	for material: String in _container_sources.get(region, {}).get(container, {}).values():
		if not material.is_empty():
			values[material] = true # Include a removed last unit until its source retires.
	for item: String in _world.regions[region].inventory.containers.get(container, {}):
		values[item] = true
	var result: Array = values.keys()
	result.sort()
	return result


func container_keys(region: String, container: String) -> Array[String]:
	var result: Array[String] = []
	result.assign(_container_sources.get(region, {}).get(container, {}).keys())
	result.sort()
	return result


func _build_failure(reason: String) -> Dictionary:
	_failed = true
	return _failure(reason)


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
