class_name SimEnvironmentGroundCache
extends RefCounted
## Authority-only disposable base targets over original ground objects. No
## physical temperature, response history, stock, clock or save ownership.
## Lifecycle invalidation is synchronous; projection/rebuild is budgeted.

const Cache = preload("res://scripts/sim/environment_field_cache.gd")
const GroundField = preload("res://scripts/sim/environment_ground_field.gd")
const Bindings = preload("res://scripts/sim/environment_source_bindings.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const SourceChange = preload("res://scripts/sim/environment_source_change.gd")
const SIZE: int = SimGroundPlacements.MAP_SIZE
const TILE: int = 16
const COLUMNS: int = SIZE / TILE
const MAX_PENDING_SOURCES: int = 8192
const SCOPE: String = "cached_ground_base_targets"

var _owner: WeakRef
var _lifecycle: WeakRef
var _ground: WeakRef
var _artifacts: WeakRef
var _inventories: Dictionary = {}
var _definitions: EnvironmentSourceDefinitions
var _query: RefCounted
var _cache: RefCounted
var _state: String = "closed"
var _reason: String = "not_configured"
var _ground_revision: int = 0
var _artifact_generation: int = 0
var _entries: Dictionary[String, Vector4i] = {} # reference -> slot,x,y,radius
var _free: Array[int] = []
var _next_slot: int = 0
var _scan_tile: int = 0
var _scan_ids: Array = []
var _scan_cursor: int = 0
var _changes: Array[Dictionary] = []
var _change_keys: Dictionary = {}
var _change_cursor: int = 0
var _invalid_tiles: Dictionary[int, bool] = {}
var _projected: int = 0
var _invalidations: int = 0
var _rebuilt: int = 0
var _compute_owner: WeakRef
var _binding_generation: int = 0
var _generation: int = 0
var _response: RefCounted
var _response_move: Dictionary = {}
var _last_response_commit: Dictionary = {}


func configure(world: RegionalSimulation, definitions: EnvironmentSourceDefinitions) -> bool:
	if _state != "closed" or world == null or definitions == null:
		return false
	var query := Bindings.new()
	if not query.configure(world, definitions):
		return false
	if world.elapsed_ms != world.target_ms:
		return false
	for region: VillageSimulation in world.regions.values():
		if region.elapsed_ms != world.elapsed_ms:
			return false
	var cache := GroundField.new()
	# Exclusive ground footprints bound active sources by map cells. This
	# allocation and kernel warmup are explicit configure costs, not read costs.
	if not cache.configure(Vector2i(SIZE, SIZE), SIZE * SIZE):
		return false
	if not world.object_lifecycle.bind_environment_cache(self):
		return false
	_owner = weakref(world)
	_lifecycle = weakref(world.object_lifecycle)
	_ground = weakref(world.object_lifecycle.ground)
	_artifacts = weakref(world.artifacts)
	_definitions = definitions
	_query = query
	_cache = cache
	_binding_generation += 1
	_generation += 1
	_state = "building"
	_reason = ""
	for id: String in world.regions:
		var inventory: SimInventory = world.regions[id].inventory
		_inventories[id] = {"owner": weakref(inventory), "revision": inventory.ground_revision}
	_capture_revisions(world)
	return true


func before_object_change() -> void:
	# Catch unsupported owner mutations before a normal operation could mask
	# their revisions. Failure disables this cache, never the lawful object move.
	_context()


func objects_changed(result: Dictionary) -> void:
	if _state == "closed" or _state == "error":
		return
	if _state == "building":
		_fail("initialization_changed")
		return
	var world: RegionalSimulation = _owner.get_ref()
	if world == null:
		_fail("world_unavailable")
		return
	var source_changed: bool = false
	for location: Dictionary in [result.get("from", {}), result.get("to", {})]:
		var container: String = str(location.get("container", ""))
		var slot: Variant = world.object_lifecycle.ground.slots.get(container)
		if not slot is Dictionary:
			continue
		var reference: Dictionary = slot.reference
		var key: String = JSON.stringify(reference, "", true)
		# Positive quantity changes do not alter an existing stack's field.
		if reference.kind == "stock" and bool(slot.active) and _entries.has(key) and not _change_keys.has(key):
			continue
		# Unrelated inventory transfers and positive quantities of an existing
		# pile must not continually restart a multi-tile calculation. Still
		# capture/check every original-owner epoch below and before each write.
		if not source_changed:
			_generation += 1
			source_changed = true
		if _entries.has(key):
			var old: Vector4i = _entries[key]
			_invalidate(Vector2i(old.y, old.z), old.w)
		if bool(slot.active):
			var size := Vector2i(int(slot.size[0]), int(slot.size[1]))
			var cell := Vector2i(int(slot.cell[0]), int(slot.cell[1]))
			cell += Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
			_invalidate(cell, _definitions.max_radius())
		if not _change_keys.has(key):
			if _changes.size() - _change_cursor >= MAX_PENDING_SOURCES:
				_fail("change_queue_limit")
				return
			_change_keys[key] = true
			_changes.append(reference.duplicate(true))
	_capture_revisions(world)


func request_area(area: Rect2i) -> Dictionary:
	var context: Dictionary = _context()
	if not bool(context.ok):
		return context
	if area.size.x < 1 or area.size.y < 1:
		return _failure("invalid_area")
	var clipped: Rect2i = area.intersection(Rect2i(0, 0, SIZE, SIZE))
	if not clipped.has_area():
		return _failure("outside_map")
	var first := Vector2i(clipped.position.x / TILE, clipped.position.y / TILE) * TILE
	var last := Vector2i((clipped.end.x + TILE - 1) / TILE, (clipped.end.y + TILE - 1) / TILE) * TILE
	var result: Dictionary = _cache.request_area(Rect2i(first, last - first))
	result["revision"] = _generation
	return result


func bind_response(temperature: RefCounted, phases: RefCounted, settings: Dictionary, initial_at: Callable, phase_initial: Callable) -> bool:
	if _response != null or _state != "ready" or not bool(_context().ok):
		return false
	var response := SourceChange.new()
	if not response.configure(_cache, temperature, settings, initial_at, phases, phase_initial):
		return false
	_response = response
	return true


func begin_move(plan: Dictionary, event_context: Variant = null) -> Dictionary:
	if _response == null or not _response_move.is_empty():
		return _failure("response_busy")
	var context: Dictionary = _context(event_context)
	if not bool(context.ok):
		return context
	if _state != "ready" or _change_cursor < _changes.size() or not _invalid_tiles.is_empty():
		return _failure("source_pending")
	var projected: Dictionary = _query.project_move(plan, event_context)
	if not bool(projected.get("ok", false)):
		return projected
	var key: String = JSON.stringify(projected.reference, "", true)
	var operation: String = str(projected.operation)
	if _entries.has(key) != (projected.before.get("status") == "source"):
		return _failure("source_mapping_mismatch")
	if operation == "none":
		var handle := RefCounted.new()
		_response_move = {"plan": plan.duplicate(true), "key": key, "operation": operation,
			"handle": handle, "proof": handle, "generation": _generation, "binding": _binding_generation}
		return {"ok": true, "pending": false, "handle": handle, "proof": handle}
	var slot: int
	var allocation: String = "existing"
	if _entries.has(key):
		slot = _entries[key].x
	elif operation == "remove":
		return _failure("source_mapping_missing")
	elif not _free.is_empty():
		slot = _free.back()
		allocation = "free"
	else:
		if _next_slot >= SIZE * SIZE:
			return _failure("source_capacity")
		slot = _next_slot
		allocation = "new"
	var opened: Dictionary = _response.begin(slot, operation, projected.field_change, int(plan.at_ms), SourceChange.Temperature.MAX_TIME)
	if not bool(opened.get("ok", false)):
		return opened
	_response_move = {"plan": plan.duplicate(true), "key": key, "slot": slot, "allocation": allocation,
		"operation": operation, "source": projected.source.duplicate(true), "handle": opened.handle,
		"generation": _generation, "binding": _binding_generation, "proof": null}
	return {"ok": true, "pending": true, "handle": opened.handle}


func step_move(handle: Variant, work: int, cells: int, event_context: Variant = null) -> Dictionary:
	if _response_move.is_empty() or not is_same(handle, _response_move.handle):
		return _failure("invalid_handle")
	var context: Dictionary = _context(event_context)
	if not bool(context.ok):
		cancel_move(handle)
		return context
	var result: Dictionary = _response.step(handle, work, cells)
	if not bool(result.get("ok", false)):
		# Some failures (e.g. invalid caller budgets) retain the lower candidate.
		# Release it before dropping this mapping; otherwise lifecycle cleanup
		# cannot find the handle and the next lawful move stays permanently busy.
		_response.cancel(handle)
		_response_move = {}
		return result
	if not bool(result.get("pending", true)):
		var finished: Dictionary = _response.finish(handle)
		if not bool(finished.get("ok", false)):
			_response.cancel(handle)
			_response_move = {}
			return finished
		_response_move.proof = finished.proof
		result["proof"] = finished.proof
	return result


func can_commit_move(proof: Variant, plan: Dictionary, event_context: Variant = null) -> Dictionary:
	if _response_move.is_empty() or not is_same(proof, _response_move.proof) or plan != _response_move.plan:
		return _failure("invalid_proof")
	var context: Dictionary = _context(event_context)
	if not bool(context.ok):
		return context
	if _generation != int(_response_move.generation) or _binding_generation != int(_response_move.binding):
		return _failure("ground_candidate_stale")
	if _response_move.operation == "none":
		return {"ok": true}
	return _response.can_commit(proof)


func commit_move(proof: Variant, plan: Dictionary) -> Dictionary:
	# The lifecycle has revalidated both domains immediately before its original
	# item publication. Its synchronous commit now changed original epochs; do
	# not rerun the old-world epoch check or reproject after that first write.
	if _response_move.is_empty() or not is_same(proof, _response_move.proof) or plan != _response_move.plan:
		return _failure("invalid_proof")
	if _response_move.operation == "none":
		_capture_revisions(_owner.get_ref())
		_response_move = {}
		return {"ok": true}
	var result: Dictionary = _response.commit(proof)
	if not bool(result.get("ok", false)):
		return result
	var slot: int = int(_response_move.slot)
	var key: String = str(_response_move.key)
	if _response_move.operation == "remove":
		_entries.erase(key)
		_free.append(slot)
	else:
		if _response_move.allocation == "free":
			_free.pop_back()
		elif _response_move.allocation == "new":
			_next_slot += 1
		var source: Dictionary = _response_move.source
		_entries[key] = Vector4i(slot, source.cell.x, source.cell.y, int(source.radius_cells))
	_generation += 1
	_capture_revisions(_owner.get_ref())
	_last_response_commit = result.get("publish_us", {}).duplicate(true)
	_response_move = {}
	return result


func cancel_move(handle: Variant) -> Dictionary:
	if _response_move.is_empty() or not is_same(handle, _response_move.handle):
		return _failure("invalid_handle")
	var result: Dictionary = {"ok": true} if _response_move.operation == "none" else _response.cancel(handle)
	_response_move = {}
	return result


func read_response_channels(cell: Vector2i, event_context: Variant = null) -> Dictionary:
	var context: Dictionary = _context(event_context)
	if not bool(context.ok):
		return context
	if _state != "ready" or _change_cursor < _changes.size() or _invalid_tiles.has(_tile_id(cell)):
		return _failure("source_pending")
	var result: Dictionary = _cache.read_base(cell)
	if bool(result.get("pending", false)):
		return _failure("target_pending")
	return result


func advance(max_work: int = 4096, max_usec: int = 2000) -> Dictionary:
	if max_work < 1 or max_work > Cache.MAX_WORK or max_usec < 1 or max_usec > 100000:
		return _failure("invalid_budget")
	var context: Dictionary = _context()
	if not bool(context.ok):
		return context
	var started: int = Time.get_ticks_usec()
	var used: int = 0
	while used < max_work and Time.get_ticks_usec() - started < max_usec:
		if _state == "building":
			if not _assemble_one(context.world):
				return _failure(_reason)
			used += 1
		elif _change_cursor < _changes.size():
			var reference: Dictionary = _changes[_change_cursor]
			if not _sync_reference(reference):
				return _failure(_reason)
			_change_keys.erase(JSON.stringify(reference, "", true))
			_change_cursor += 1
			used += 1
			if _change_cursor == _changes.size():
				_changes.clear()
				_change_keys.clear()
				_change_cursor = 0
				_invalid_tiles.clear()
		else:
			if _has_compute_backend():
				break
			# A small fixed chunk bounds the interval between wall-time checks;
			# kernel initialization and publication are measured separately too.
			var result: Dictionary = _cache.rebuild(1, mini(128, max_work - used))
			if not bool(result.ok):
				_fail(str(result.reason))
				return _failure(_reason)
			used += int(result.work)
			_rebuilt += int(result.completed)
			if int(result.work) == 0:
				break
	if _change_cursor >= 512:
		var remaining: Array[Dictionary] = []
		remaining.assign(_changes.slice(_change_cursor))
		_changes = remaining
		_change_cursor = 0
	var result: Dictionary = diagnostics()
	result.merge({"ok": true, "work_used": used, "elapsed_usec": Time.get_ticks_usec() - started})
	return result


func read_base(cell: Vector2i) -> Dictionary:
	var context: Dictionary = _context()
	if not bool(context.ok):
		return context
	if cell.x < 0 or cell.y < 0 or cell.x >= SIZE or cell.y >= SIZE:
		return _failure("outside_map")
	var metadata: Dictionary = _metadata(context.world)
	if _state == "building" or _invalid_tiles.has(_tile_id(cell)):
		metadata.merge({"ok": true, "pending": true})
		return metadata
	var result: Dictionary = _cache.read_base(cell)
	if not bool(result.ok):
		return result
	metadata.merge({"ok": true, "pending": result.pending})
	if not bool(result.pending):
		var channels: PackedInt32Array = result.channels
		metadata["elements"] = Rules.packed_to_source_elements(channels)
		metadata["thermal_grade"] = channels[Rules.PACKED_HOT_INDEX] - channels[Rules.PACKED_COLD_INDEX]
	return metadata


func diagnostics() -> Dictionary:
	var cache_stats: Dictionary = _cache.diagnostics() if _cache != null else {}
	return {"state": _state, "reason": _reason, "source_count": _entries.size(),
		"projected": _projected, "invalidations": _invalidations, "rebuilt_tiles": _rebuilt,
		"pending_sources": _changes.size() - _change_cursor + (1 if _state == "building" else 0),
		"pending_tiles": int(cache_stats.get("pending_tiles", 0)),
		"cached_tiles": int(cache_stats.get("cached_tiles", 0)), "scan_tiles": _scan_tile,
		"slot_high_water": _next_slot, "free_slots": _free.size(), "cache": cache_stats,
		"capacity": int(cache_stats.get("capacity", 0)), "revision": _generation,
		"binding_generation": _binding_generation, "compute_attached": _has_compute_backend(),
		"response_commit_us": _last_response_commit.duplicate(true)}


func acquire_compute_backend(owner: Object) -> bool:
	if not is_instance_valid(owner) or _has_compute_backend() or not bool(_context().ok):
		return false
	_compute_owner = weakref(owner)
	return true


func owns_compute_backend(owner: Object) -> bool:
	return is_instance_valid(owner) and _has_compute_backend() and _compute_owner.get_ref() == owner


func release_compute_backend(owner: Object) -> bool:
	if not owns_compute_backend(owner):
		return false
	_compute_owner = null
	return true


func export_compute_job(area: Rect2i, compact: bool = false) -> Dictionary:
	var context: Dictionary = _context()
	if not bool(context.ok):
		return context
	if not _has_compute_backend():
		return _failure("compute_not_attached")
	if _state != "ready" or _change_cursor < _changes.size() or not _invalid_tiles.is_empty():
		return _failure("source_pending")
	var job: Dictionary = _cache.export_compute_job(area, compact)
	if not bool(job.get("ok", false)):
		return job
	job["ground_owner"] = get_instance_id()
	job["ground_binding"] = _binding_generation
	job["ground_generation"] = _generation
	job["ground_digest"] = _definitions.digest()
	return job


func publish_compute_result(job: Dictionary, prepared: Dictionary) -> Dictionary:
	# Same owner thread, no callbacks between all original-owner/epoch checks
	# and the underlying cache's atomic publish. Never expose a raw cache writer.
	var context: Dictionary = _context()
	if not bool(context.ok):
		return context
	if not _has_compute_backend() or job.get("ground_owner") != get_instance_id() \
		or job.get("ground_binding") != _binding_generation or job.get("ground_digest") != _definitions.digest():
		return _failure("ground_compute_owner")
	if job.get("ground_generation") != _generation or _state != "ready" \
		or _change_cursor < _changes.size() or not _invalid_tiles.is_empty():
		return _failure("ground_compute_stale")
	var result: Dictionary = _cache.publish_compute_result(job, prepared)
	if bool(result.get("ok", false)):
		_rebuilt += int(result.published_tiles)
		result["revision"] = _generation
	return result


func rebuild(max_tiles: int, max_work: int = 16384) -> Dictionary:
	if max_tiles < 1 or max_work < 1 or max_work > Cache.MAX_WORK:
		return _failure("work_budget")
	if not _has_compute_backend():
		return _failure("compute_not_attached")
	var started: int = Time.get_ticks_usec()
	# The attached scheduler is the only target builder. advance only projects
	# sources while leased; both phases share this call's wall-time/work budget.
	var synced: Dictionary = advance(max_work, 2000)
	if not bool(synced.get("ok", false)):
		return synced
	var used: int = int(synced.work_used)
	var source_pending: bool = _state != "ready" or _change_cursor < _changes.size()
	var completed: int = 0
	while not source_pending and used < max_work and completed < max_tiles and Time.get_ticks_usec() - started < 2000:
		var built: Dictionary = _cache.rebuild(1, mini(128, max_work - used))
		if not bool(built.get("ok", false)):
			return _fail(str(built.reason))
		used += int(built.work)
		completed += int(built.completed)
		if int(built.work) == 0:
			break
	_rebuilt += completed
	return {"ok": true, "pending": source_pending, "work": used, "completed": completed,
		"revision": _generation, "pending_tiles": int(_cache.diagnostics().pending_tiles)}


func _has_compute_backend() -> bool:
	return _compute_owner != null and _compute_owner.get_ref() != null


func close() -> void:
	if not _response_move.is_empty():
		cancel_move(_response_move.handle)
	_response_move = {}
	_response = null
	_binding_generation += 1
	_generation += 1
	_compute_owner = null
	var lifecycle: SimObjectLifecycle = _lifecycle.get_ref() if _lifecycle != null else null
	if lifecycle != null:
		lifecycle.bind_environment_cache(null)
	_owner = null
	_lifecycle = null
	_ground = null
	_artifacts = null
	_inventories.clear()
	_definitions = null
	_query = null
	_cache = null
	_entries.clear()
	_free.clear()
	_scan_ids.clear()
	_changes.clear()
	_change_keys.clear()
	_invalid_tiles.clear()
	_next_slot = 0
	_scan_tile = 0
	_scan_cursor = 0
	_change_cursor = 0
	_projected = 0
	_invalidations = 0
	_rebuilt = 0
	_state = "closed"
	_reason = "not_configured"


func _assemble_one(world: RegionalSimulation) -> bool:
	if _scan_cursor < _scan_ids.size():
		var slot: Dictionary = world.object_lifecycle.ground.slots[_scan_ids[_scan_cursor]]
		_scan_cursor += 1
		# Query intersects full footprints. Process only the anchor bucket so
		# a multi-cell object is projected once, without a map-sized seen copy.
		var anchor := Vector2i(int(slot.cell[0]), int(slot.cell[1]))
		if _tile_id(anchor) == _scan_tile - 1:
			return _sync_reference(slot.reference)
		return true
	if _scan_tile == COLUMNS * COLUMNS:
		_scan_ids.clear()
		_state = "ready"
		return true
	var at := Vector2i((_scan_tile % COLUMNS) * TILE, (_scan_tile / COLUMNS) * TILE)
	var found: Dictionary = world.object_lifecycle.ground.query(Rect2i(at, Vector2i(TILE, TILE)), 1024)
	if not bool(found.ok):
		_fail(str(found.reason))
		return false
	_scan_ids = found.ids
	_scan_cursor = 0
	_scan_tile += 1
	return true


func _sync_reference(reference: Dictionary) -> bool:
	var key: String = JSON.stringify(reference, "", true)
	var projected: Dictionary = _query.project(reference)
	_projected += 1
	if not bool(projected.ok) and projected.reason not in ["not_found", "unsupported_location"]:
		_fail(str(projected.reason))
		return false
	var emitting: bool = bool(projected.ok) and projected.status == "source"
	if not emitting:
		if _entries.has(key):
			var index: int = _entries[key].x
			_cache.remove_source(index)
			_entries.erase(key)
			_free.append(index)
			_generation += 1
		return true
	var index: int
	if _entries.has(key):
		index = _entries[key].x
	elif not _free.is_empty():
		index = _free.pop_back()
	else:
		if _next_slot == SIZE * SIZE:
			_fail("source_capacity")
			return false
		index = _next_slot
		_next_slot += 1
	var result: Dictionary = _cache.set_source(index, projected.cell, int(projected.radius_cells), Rules.source_to_packed_channels(projected.elements, int(projected.thermal_grade)))
	if not bool(result.ok):
		_fail(str(result.reason))
		return false
	if bool(result.get("changed", false)):
		_generation += 1
	_entries[key] = Vector4i(index, projected.cell.x, projected.cell.y, int(projected.radius_cells))
	return true


func _invalidate(cell: Vector2i, radius: int) -> void:
	var area := Rect2i(cell - Vector2i.ONE * (radius - 1), Vector2i.ONE * (2 * radius - 1))
	area = area.intersection(Rect2i(0, 0, SIZE, SIZE))
	for y: int in range(area.position.y / TILE, (area.end.y - 1) / TILE + 1):
		for x: int in range(area.position.x / TILE, (area.end.x - 1) / TILE + 1):
			_invalid_tiles[y * COLUMNS + x] = true
	_invalidations += 1


func _context(event_context: Variant = null) -> Dictionary:
	if _state == "closed" or _state == "error":
		return _failure(_reason)
	var world: RegionalSimulation = _owner.get_ref()
	if world == null:
		return _fail("world_unavailable")
	if world.object_lifecycle != _lifecycle.get_ref() or world.object_lifecycle.ground != _ground.get_ref() or world.artifacts != _artifacts.get_ref():
		return _fail("owner_replaced")
	if world.object_lifecycle.world != world or world.artifacts.world != world or not world.object_lifecycle.ground.bound_to(world) or world.object_lifecycle.ground.revision != _ground_revision or world.artifacts.state_generation != _artifact_generation or world.regions.size() != _inventories.size():
		return _fail("untracked_change")
	for id: String in _inventories:
		var region: VillageSimulation = world.regions.get(id)
		var expected: Dictionary = _inventories[id]
		if region == null or region.inventory != expected.owner.get_ref() or region.inventory.ground_revision != int(expected.revision):
			return _fail("inventory_changed")
	# Check every owner's epoch before any recoverable timestamp refusal. A
	# later lifecycle transaction must not bless an unchecked later inventory.
	for id: String in _inventories:
		var region: VillageSimulation = world.regions[id]
		if region.elapsed_ms != world.elapsed_ms:
			return _failure("stale_source")
	if world.elapsed_ms != world.target_ms and not world.environment_event_valid(event_context):
		return _failure("world_has_backlog")
	return {"ok": true, "world": world}


func _capture_revisions(world: RegionalSimulation) -> void:
	_ground_revision = world.object_lifecycle.ground.revision
	_artifact_generation = world.artifacts.state_generation
	for id: String in _inventories:
		_inventories[id].revision = world.regions[id].inventory.ground_revision


func _metadata(world: RegionalSimulation) -> Dictionary:
	return {"visibility": "authority_only", "scope": SCOPE, "live": false,
		"world_time_ms": world.elapsed_ms, "config_digest": _definitions.digest(),
		"rule_version": Rules.BASE_TARGET_RULE_VERSION}


func _fail(reason: String) -> Dictionary:
	_state = "error"
	_reason = reason
	return _failure(reason)


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "pending": false, "reason": reason, "visibility": "authority_only", "scope": SCOPE}


static func _tile_id(cell: Vector2i) -> int:
	return (cell.y / TILE) * COLUMNS + cell.x / TILE
