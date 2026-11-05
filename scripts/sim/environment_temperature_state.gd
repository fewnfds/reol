class_name SimEnvironmentTemperatureState
extends RefCounted
## One owner for actual outdoor temperature at explicitly tracked cells.
## Each cell keeps one known target segment; reads do not change its anchor.
## This object holds no clock, source inventory, Q balance, or integral ledger.

const Response = preload("res://scripts/sim/environment_field_response.gd")
const VERSION: int = 1
const PLAN_VERSION: int = 1
const MIN_C: float = -273.15
const MAX_C: float = Response.MAX_ABS_VALUE
const MAX_TIME: int = Response.MAX_TIME
const MAX_AXIS: int = 4096
const MAX_CAPACITY: int = 4_194_304
const MAX_REVISION: int = 9_007_199_254_740_991
const CHUNK_SIDE: int = 16
const CHUNK_CELLS: int = CHUNK_SIDE * CHUNK_SIDE
const MAX_BULK_CHUNKS: int = 64

var _configured: bool = false
var _size := Vector2i.ZERO
var _capacity: int = 0
var _activation_ms: int = 0
var _last_change_ms: int = 0
var _revision: int = 0
var _chunks: Dictionary = {}
var _tracked_count: int = 0
# Rebuildable index of boundaries; packed anchors remain authoritative. The
# boundary index is neither serialized nor used as a second clock.
var _boundary_counts: Dictionary = {}
var _earliest_boundary: int = -1
var _issued_plan := WeakRef.new()
# One private candidate at most. Its arrays are never included in a plan.
var _prepared_chunks: Dictionary = {}
var _prepared_counts: Dictionary = {}
var _prepared_earliest: int = -1
var _prepared_count: int = 0
var _prepared_changed: int = 0
var _prepared_at_ms: int = -1
var _prepared_revision: int = -1
var _prepared_rows: Array = []
# A single isolated builder and an identity that changes on every successful
# restore, even when the restored numeric revision equals the old one.
var _bulk: BulkBuilder = null
var _restore_identity := RefCounted.new()


func configure(size: Vector2i, capacity: int, activation_ms: int) -> bool:
	if _configured or not _valid_configuration(size, capacity, activation_ms):
		return false
	_size = size
	_capacity = capacity
	_activation_ms = activation_ms
	_last_change_ms = activation_ms
	_revision = 0
	_configured = true
	return true


func actual_at(cell: Vector2i, at_ms: int) -> Dictionary:
	if not _configured:
		return _failure("not_configured")
	if not _inside(cell, _size):
		return _failure("invalid_cell")
	if at_ms < _activation_ms or at_ms > MAX_TIME:
		return _failure("time_out_of_range")
	var chunk: Chunk = _chunks.get(_chunk_key(cell))
	var index: int = _chunk_index(cell)
	if chunk == null or chunk.present[index] == 0:
		return _failure("untracked")
	if at_ms < chunk.starts[index]:
		return _failure("history_unavailable")
	if at_ms > chunk.untils[index]:
		return _failure("target_boundary")
	var value: float = Response._value_only_unchecked(chunk.starts[index], at_ms, chunk.initials[index], chunk.targets[index], chunk.slopes[index], chunk.taus[index])
	if not _temperature(value):
		return _failure("response_unavailable")
	return {"ok": true, "cell": cell, "at_ms": at_ms, "value_c": value}


func prepare_targets(changes: Array[Dictionary], at_ms: int, budget: int) -> Dictionary:
	# Build a complete copy-on-write candidate before issuing a public proof.
	# Only affected chunks are copied; the candidate root and counts are private.
	if not _configured:
		return _failure("not_configured")
	if _bulk != null:
		return _failure("busy")
	if at_ms < _last_change_ms or at_ms > MAX_TIME:
		return _failure("time_out_of_range")
	if budget < 0 or budget > _capacity:
		return _failure("invalid_budget")
	if changes.is_empty():
		return _failure("empty_change")
	if changes.size() > budget:
		return _failure("pending")
	if _revision >= MAX_REVISION:
		return _failure("revision_exhausted")

	var candidate_chunks: Dictionary = _chunks.duplicate(false)
	var candidate_counts: Dictionary = _boundary_counts.duplicate(false)
	var candidate_earliest: int = _earliest_boundary
	var candidate_count: int = _tracked_count
	var copied: Dictionary[Vector2i, bool] = {}
	var seen: Dictionary[Vector2i, bool] = {}
	var rows: Array[Dictionary] = []
	var previous_cell := Vector2i(-1, -1)
	var ordered: bool = true
	for change: Dictionary in changes:
		var has_initial: bool = change.has("initial_c")
		var fields: Array[String] = ["cell", "target_c", "target_per_ms", "until_ms", "tau_ms"]
		if has_initial:
			fields.append("initial_c")
		if not _keys(change, fields) or not change.cell is Vector2i:
			return _failure("change_shape")
		var cell: Vector2i = change.cell
		if not _inside(cell, _size) or seen.has(cell):
			return _failure("invalid_or_duplicate_cell")
		seen[cell] = true
		if not _after(cell, previous_cell):
			ordered = false
		previous_cell = cell

		var key: Vector2i = _chunk_key(cell)
		var index: int = _chunk_index(cell)
		var original: Chunk = _chunks.get(key)
		var tracked: bool = original != null and original.present[index] != 0
		if has_initial == tracked:
			return _failure("initial_mismatch")
		var initial: float
		if tracked:
			if at_ms < original.starts[index]:
				return _failure("history_unavailable")
			if at_ms > original.untils[index]:
				return _failure("target_boundary")
			initial = Response._value_only_unchecked(original.starts[index], at_ms, original.initials[index], original.targets[index], original.slopes[index], original.taus[index])
			if not _temperature(initial):
				return _failure("response_unavailable")
		else:
			if not _temperature(change.initial_c):
				return _failure("initial_out_of_range")
			initial = float(change.initial_c)
			candidate_count += 1
			if candidate_count > _capacity:
				return _failure("capacity")

		if not _temperature(change.target_c) or not _number(change.target_per_ms) or not _integer(change.until_ms, at_ms, MAX_TIME) or not _integer(change.tau_ms, 1, Response.MAX_TAU_MS):
			return _failure("target_invalid")
		var target: float = float(change.target_c)
		var slope: float = float(change.target_per_ms)
		var until_ms: int = int(change.until_ms)
		var tau_ms: int = int(change.tau_ms)
		# Response.configure permits this rate bound; physical temperature
		# additionally requires both target endpoints to be in its domain.
		if absf(slope) > Response.MAX_ABS_RATE_PER_MS or not _temperature(target + slope * float(until_ms - at_ms)):
			return _failure("target_invalid")

		var next_chunk: Chunk = candidate_chunks.get(key)
		if not copied.has(key):
			next_chunk = Chunk.new(original)
			candidate_chunks[key] = next_chunk
			copied[key] = true
		next_chunk.set_anchor(index, at_ms, until_ms, initial, target, slope, tau_ms)

		var old_boundary: int = original.untils[index] if tracked else -1
		if old_boundary != until_ms:
			if old_boundary >= 0:
				var remaining: int = int(candidate_counts[old_boundary]) - 1
				if remaining == 0:
					candidate_counts.erase(old_boundary)
				else:
					candidate_counts[old_boundary] = remaining
			candidate_counts[until_ms] = int(candidate_counts.get(until_ms, 0)) + 1
			if candidate_earliest < 0 or until_ms < candidate_earliest:
				candidate_earliest = until_ms

		var response_state: Dictionary = {"version": 1, "start_ms": at_ms, "until_ms": until_ms,
			"initial_value": initial, "target_value": target, "target_per_ms": slope, "tau_ms": tau_ms}
		response_state.make_read_only()
		var row: Dictionary = {"cell": cell, "response": response_state}
		row.make_read_only()
		rows.append(row)
	if candidate_earliest >= 0 and not candidate_counts.has(candidate_earliest):
		candidate_earliest = -1
		for boundary: int in candidate_counts:
			if candidate_earliest < 0 or boundary < candidate_earliest:
				candidate_earliest = boundary
	if not ordered:
		rows.sort_custom(_row_before)
	rows.make_read_only()
	var proof := PreparedProof.new(rows, at_ms)
	# A successful new preparation supersedes the previous candidate. A failed
	# or pending preparation has not touched the live state or the old proof.
	_prepared_chunks = candidate_chunks
	_prepared_counts = candidate_counts
	_prepared_earliest = candidate_earliest
	_prepared_count = candidate_count
	_prepared_changed = rows.size()
	_prepared_at_ms = at_ms
	_prepared_revision = _revision
	_prepared_rows = rows
	_issued_plan = weakref(proof)
	var plan: Dictionary = {"ok": true, "version": PLAN_VERSION, "owner": get_instance_id(),
		"revision": _revision, "proof": proof, "at_ms": at_ms, "rows": rows}
	plan.make_read_only()
	return plan


func commit(plan: Variant) -> Dictionary:
	if not _configured:
		return _failure("not_configured")
	if _bulk != null:
		return _failure("busy")
	if not _keys(plan, ["ok", "version", "owner", "revision", "proof", "at_ms", "rows"]) or not plan.is_read_only() or not plan.ok is bool or not plan.ok or not plan.version is int or plan.version != PLAN_VERSION or not plan.owner is int or plan.owner != get_instance_id() or not plan.revision is int or plan.revision != _revision:
		return _failure("invalid_or_stale_plan")
	if not plan.at_ms is int or plan.at_ms < _last_change_ms or plan.at_ms > MAX_TIME or not plan.rows is Array or not plan.rows.is_read_only() or plan.rows.is_empty() or plan.rows.size() > _capacity or _revision >= MAX_REVISION:
		return _failure("invalid_or_stale_plan")
	# The owner, not the externally visible proof object's mutable fields,
	# retains both the sole candidate and the identity of its immutable rows.
	if not plan.proof is PreparedProof or not is_same(_issued_plan.get_ref(), plan.proof) or not is_same(_prepared_rows, plan.rows) or int(plan.at_ms) != _prepared_at_ms or _prepared_revision != _revision:
		return _failure("invalid_or_stale_plan")
	var changed: int = _prepared_changed
	var at_ms: int = _prepared_at_ms
	_chunks = _prepared_chunks
	_boundary_counts = _prepared_counts
	_earliest_boundary = _prepared_earliest
	_tracked_count = _prepared_count
	_last_change_ms = at_ms
	_revision += 1
	_clear_prepared()
	return {"ok": true, "revision": _revision, "changed": changed, "at_ms": at_ms}


func begin_bulk(at_ms: int, max_changed_chunks: int) -> Dictionary:
	# Root/count copies are synchronous and scale with the existing distinct
	# chunks/boundaries. Later input and cell validation are separately bounded.
	if not _configured:
		return _failure("not_configured")
	if _bulk != null or _issued_plan.get_ref() != null:
		return _failure("busy")
	if at_ms < _last_change_ms or at_ms > MAX_TIME:
		return _failure("time_out_of_range")
	if max_changed_chunks < 1 or max_changed_chunks > MAX_BULK_CHUNKS:
		return _failure("invalid_chunk_limit")
	if _revision >= MAX_REVISION:
		return _failure("revision_exhausted")
	# A dropped small-batch proof cannot be committed and need not retain its
	# private candidate while this builder is active.
	_clear_prepared()
	var builder := BulkBuilder.new()
	builder.handle = BulkHandle.new()
	builder.owner_id = get_instance_id()
	builder.generation = _restore_identity
	builder.revision = _revision
	builder.at_ms = at_ms
	builder.max_chunks = max_changed_chunks
	builder.chunks = _chunks.duplicate(false)
	builder.counts = _boundary_counts.duplicate(false)
	builder.earliest = _earliest_boundary
	builder.tracked_count = _tracked_count
	_bulk = builder
	return {"ok": true, "handle": builder.handle}


func offer_bulk_chunk(handle: Variant, key: Variant, packed_fields: Variant) -> Dictionary:
	if not _bulk_current(handle):
		return _failure("invalid_handle")
	if not _bulk.failure.is_empty():
		return _failure(_bulk.failure)
	if _bulk.sealed:
		return _failure("already_finished")
	if not _bulk.pending.is_empty():
		return _failure("busy")
	if not key is Vector2i:
		return _bulk_fail("invalid_chunk")
	var coord: Vector2i = key
	if coord.x < 0 or coord.y < 0 or coord.x >= ((_size.x + 15) >> 4) or coord.y >= ((_size.y + 15) >> 4):
		return _bulk_fail("invalid_chunk")
	if not _after(coord, _bulk.previous_key):
		return _bulk_fail("chunk_order")
	if _bulk.offered >= _bulk.max_chunks:
		return _bulk_fail("chunk_limit")
	if not _bulk_columns_valid(packed_fields):
		return _bulk_fail("chunk_shape")
	# Never retain a caller's mutable packed arrays. The one-block copy and
	# copy-on-write output block are fixed-size work per offer.
	var pending: Dictionary = {
		"mask": packed_fields.mask.duplicate(), "initial_mask": packed_fields.initial_mask.duplicate(),
		"initial": packed_fields.initial.duplicate(), "target": packed_fields.target.duplicate(),
		"slope": packed_fields.slope.duplicate(), "until_ms": packed_fields.until_ms.duplicate(),
		"tau_ms": packed_fields.tau_ms.duplicate(),
	}
	var original: Chunk = _chunks.get(coord)
	var next_chunk := Chunk.new(original)
	_bulk.chunks[coord] = next_chunk
	_bulk.original = original
	_bulk.current = next_chunk
	_bulk.pending = pending
	_bulk.current_key = coord
	_bulk.previous_key = coord
	_bulk.cursor = 0
	_bulk.current_changed = 0
	_bulk.offered += 1
	return {"ok": true, "status": "pending"}


func resume_bulk(handle: Variant, max_cells: int) -> Dictionary:
	if not _bulk_current(handle):
		return _failure("invalid_handle")
	if not _bulk.failure.is_empty():
		return _failure(_bulk.failure)
	if _bulk.sealed:
		return _failure("already_finished")
	if max_cells < 0 or max_cells > CHUNK_CELLS:
		return _failure("invalid_budget")
	if _bulk.pending.is_empty():
		return _failure("no_pending_chunk")
	var mask: PackedByteArray = _bulk.pending.mask
	var initial_mask: PackedByteArray = _bulk.pending.initial_mask
	var visited: int = 0
	var processed: int = 0
	# The budget charges every inspected slot, including empty mask positions,
	# so sparse blocks and a budget of one cannot hide an unbounded scan.
	while _bulk.cursor < CHUNK_CELLS and visited < max_cells:
		var index: int = _bulk.cursor
		_bulk.cursor += 1
		visited += 1
		if mask[index] > 1 or initial_mask[index] > 1 or (mask[index] == 0 and initial_mask[index] != 0):
			return _bulk_fail("invalid_mask")
		if mask[index] == 0:
			continue
		var reason: String = _apply_bulk_slot(index, initial_mask[index] == 1)
		if not reason.is_empty():
			return _bulk_fail(reason)
		processed += 1
	if _bulk.cursor == CHUNK_CELLS:
		# Do not publish an allocated empty block just because an offered mask
		# selected no cells; retain an existing block without an unnecessary copy.
		if _bulk.current_changed == 0:
			if _bulk.original == null:
				_bulk.chunks.erase(_bulk.current_key)
			else:
				_bulk.chunks[_bulk.current_key] = _bulk.original
		_bulk.pending = {}
		_bulk.original = null
		_bulk.current = null
		return {"ok": true, "status": "chunk_done", "visited": visited, "processed": processed, "cursor": CHUNK_CELLS}
	return {"ok": true, "status": "pending", "visited": visited, "processed": processed, "cursor": _bulk.cursor}


func _apply_bulk_slot(index: int, has_initial: bool) -> String:
	var cell := Vector2i((_bulk.current_key.x << 4) + (index & 15), (_bulk.current_key.y << 4) + (index >> 4))
	if not _inside(cell, _size):
		return "invalid_cell"
	var original: Chunk = _bulk.original
	var tracked: bool = original != null and original.present[index] != 0
	if has_initial == tracked:
		return "initial_mismatch"
	var initial: float
	if tracked:
		if _bulk.at_ms < original.starts[index]:
			return "history_unavailable"
		if _bulk.at_ms > original.untils[index]:
			return "target_boundary"
		initial = Response._value_only_unchecked(original.starts[index], _bulk.at_ms, original.initials[index], original.targets[index], original.slopes[index], original.taus[index])
		if not _temperature(initial):
			return "response_unavailable"
	else:
		initial = _bulk.pending.initial[index]
		if not _temperature(initial):
			return "initial_out_of_range"
		if _bulk.tracked_count >= _capacity:
			return "capacity"
	var target: float = _bulk.pending.target[index]
	var slope: float = _bulk.pending.slope[index]
	var until_ms: int = _bulk.pending.until_ms[index]
	var tau_ms: int = _bulk.pending.tau_ms[index]
	if not _temperature(target) or not is_finite(slope) or absf(slope) > Response.MAX_ABS_RATE_PER_MS or until_ms < _bulk.at_ms or until_ms > MAX_TIME or tau_ms < 1 or tau_ms > Response.MAX_TAU_MS:
		return "target_invalid"
	if not _temperature(target + slope * float(until_ms - _bulk.at_ms)):
		return "target_invalid"
	if not tracked:
		_bulk.tracked_count += 1
	_bulk.current.set_anchor(index, _bulk.at_ms, until_ms, initial, target, slope, tau_ms)
	var old_boundary: int = original.untils[index] if tracked else -1
	if old_boundary != until_ms:
		if old_boundary >= 0:
			var remaining: int = int(_bulk.counts[old_boundary]) - 1
			if remaining == 0:
				_bulk.counts.erase(old_boundary)
			else:
				_bulk.counts[old_boundary] = remaining
		_bulk.counts[until_ms] = int(_bulk.counts.get(until_ms, 0)) + 1
		if _bulk.earliest < 0 or until_ms < _bulk.earliest:
			_bulk.earliest = until_ms
	_bulk.changed += 1
	_bulk.current_changed += 1
	return ""


func finish_bulk(handle: Variant) -> Dictionary:
	if not _bulk_current(handle):
		return _failure("invalid_handle")
	if not _bulk.failure.is_empty():
		return _failure(_bulk.failure)
	if _bulk.sealed:
		return _failure("already_finished")
	if not _bulk.pending.is_empty():
		return _failure("pending")
	if _bulk.changed == 0:
		return _failure("empty_change")
	# This scan is synchronous if the old minimum disappeared, and scales with
	# the number of distinct candidate boundaries, not just changed chunks.
	if _bulk.earliest >= 0 and not _bulk.counts.has(_bulk.earliest):
		_bulk.earliest = -1
		for boundary: int in _bulk.counts:
			if _bulk.earliest < 0 or boundary < _bulk.earliest:
				_bulk.earliest = boundary
	_bulk.sealed = true
	_bulk.proof = BulkProof.new()
	var result: Dictionary = {"ok": true, "proof": _bulk.proof, "changed": _bulk.changed, "chunks": _bulk.offered}
	result.make_read_only()
	return result


func can_commit_bulk(proof: Variant) -> bool:
	# A coordinator can preflight all participating domains before publishing
	# in one synchronous stack. This does not reserve time or mutate the plan.
	return _bulk != null and _bulk_current(_bulk.handle) and _bulk.sealed and proof is BulkProof and is_same(_bulk.proof, proof)


func commit_bulk(proof: Variant) -> Dictionary:
	if not can_commit_bulk(proof):
		return _failure("invalid_proof")
	var changed: int = _bulk.changed
	var at_ms: int = _bulk.at_ms
	_chunks = _bulk.chunks
	_boundary_counts = _bulk.counts
	_earliest_boundary = _bulk.earliest
	_tracked_count = _bulk.tracked_count
	_last_change_ms = at_ms
	_revision += 1
	# Old roots/blocks can be freed synchronously here; publication does not
	# imply that freeing a large replaced root is bounded by a cell budget.
	_bulk = null
	return {"ok": true, "revision": _revision, "changed": changed, "at_ms": at_ms}


func cancel_bulk(handle: Variant) -> Dictionary:
	if not _bulk_current(handle):
		return _failure("invalid_handle")
	# Releasing the candidate root and copied blocks is synchronous.
	_bulk = null
	return {"ok": true}


func _bulk_current(handle: Variant) -> bool:
	return _bulk != null and handle is BulkHandle and is_same(_bulk.handle, handle) and _bulk.owner_id == get_instance_id() and _bulk.revision == _revision and is_same(_bulk.generation, _restore_identity)


func _bulk_fail(reason: String) -> Dictionary:
	_bulk.failure = reason
	_bulk.pending = {}
	_bulk.original = null
	_bulk.current = null
	return _failure(reason)


static func _bulk_columns_valid(data: Variant) -> bool:
	if not _keys(data, ["mask", "initial_mask", "initial", "target", "slope", "until_ms", "tau_ms"]):
		return false
	return data.mask is PackedByteArray and data.mask.size() == CHUNK_CELLS and data.initial_mask is PackedByteArray and data.initial_mask.size() == CHUNK_CELLS and data.initial is PackedFloat64Array and data.initial.size() == CHUNK_CELLS and data.target is PackedFloat64Array and data.target.size() == CHUNK_CELLS and data.slope is PackedFloat64Array and data.slope.size() == CHUNK_CELLS and data.until_ms is PackedInt64Array and data.until_ms.size() == CHUNK_CELLS and data.tau_ms is PackedInt32Array and data.tau_ms.size() == CHUNK_CELLS


func _clear_prepared() -> void:
	_issued_plan = WeakRef.new()
	_prepared_chunks = {}
	_prepared_counts = {}
	_prepared_earliest = -1
	_prepared_count = 0
	_prepared_changed = 0
	_prepared_at_ms = -1
	_prepared_revision = -1
	_prepared_rows = []


func next_boundary_ms() -> int:
	return _earliest_boundary if _configured else -1


func snapshot() -> Dictionary:
	if not _configured:
		return {}
	var cells: Array[Vector2i] = []
	for key: Vector2i in _chunks:
		var chunk: Chunk = _chunks[key]
		for index: int in CHUNK_CELLS:
			if chunk.present[index] != 0:
				cells.append(Vector2i((key.x << 4) + (index & 15), (key.y << 4) + (index >> 4)))
	cells.sort_custom(_cell_before)
	var rows: Array[Dictionary] = []
	for cell: Vector2i in cells:
		var chunk: Chunk = _chunks[_chunk_key(cell)]
		rows.append({"cell": [cell.x, cell.y], "response": chunk.response_at(_chunk_index(cell))})
	return {"version": VERSION, "size": [_size.x, _size.y], "capacity": _capacity,
		"activation_ms": _activation_ms, "last_change_ms": _last_change_ms,
		"revision": _revision, "cells": rows}


func restore(data: Variant) -> bool:
	# Construct every chunk and boundary count in isolation; no live field is
	# assigned until the complete candidate has passed the existing v1 checks.
	if not _keys(data, ["version", "size", "capacity", "activation_ms", "last_change_ms", "revision", "cells"]) or not _integer(data.version, VERSION, VERSION) or not data["size"] is Array or data["size"].size() != 2:
		return false
	if not _integer(data["size"][0], 1, MAX_AXIS) or not _integer(data["size"][1], 1, MAX_AXIS) or not _integer(data.capacity, 1, MAX_CAPACITY) or not _integer(data.activation_ms, 0, MAX_TIME) or not _integer(data.last_change_ms, int(data.activation_ms), MAX_TIME) or not _integer(data.revision, 0, MAX_REVISION):
		return false
	var next_size := Vector2i(int(data["size"][0]), int(data["size"][1]))
	var capacity: int = int(data.capacity)
	if not _valid_configuration(next_size, capacity, int(data.activation_ms)) or not data.cells is Array or data.cells.size() > capacity:
		return false
	var revision: int = int(data.revision)
	var activation: int = int(data.activation_ms)
	var last_change: int = int(data.last_change_ms)
	if revision == 0 and (not data.cells.is_empty() or last_change != activation) or revision > 0 and data.cells.is_empty():
		return false
	var candidate_chunks: Dictionary = {}
	var candidate_counts: Dictionary = {}
	var candidate_boundary: int = -1
	var prior := Vector2i(-1, -1)
	var newest: int = activation
	# A single reusable validator preserves Response.restore's exact schema and
	# bounds without retaining a RefCounted response for every tracked cell.
	var response := Response.new()
	for row: Variant in data.cells:
		if not _keys(row, ["cell", "response"]) or not row.cell is Array or row.cell.size() != 2 or not _integer(row.cell[0], 0, next_size.x - 1) or not _integer(row.cell[1], 0, next_size.y - 1):
			return false
		var cell := Vector2i(int(row.cell[0]), int(row.cell[1]))
		if not _after(cell, prior) or not response.restore(row.response):
			return false
		var state: Dictionary = response.to_dict()
		if not _physical_response(state) or int(state.start_ms) < activation or int(state.start_ms) > last_change:
			return false
		newest = maxi(newest, int(state.start_ms))
		var boundary: int = int(state.until_ms)
		candidate_counts[boundary] = int(candidate_counts.get(boundary, 0)) + 1
		if candidate_boundary < 0 or boundary < candidate_boundary:
			candidate_boundary = boundary
		var key: Vector2i = _chunk_key(cell)
		var chunk: Chunk = candidate_chunks.get(key)
		if chunk == null:
			chunk = Chunk.new()
			candidate_chunks[key] = chunk
		chunk.set_anchor(_chunk_index(cell), int(state.start_ms), boundary, float(state.initial_value), float(state.target_value), float(state.target_per_ms), int(state.tau_ms))
		prior = cell
	if newest != last_change:
		return false
	_size = next_size
	_capacity = capacity
	_activation_ms = activation
	_last_change_ms = last_change
	_revision = revision
	_chunks = candidate_chunks
	_tracked_count = data.cells.size()
	_boundary_counts = candidate_counts
	_earliest_boundary = candidate_boundary
	_configured = true
	# Even the same numeric revision cannot make an old candidate valid again.
	_clear_prepared()
	_bulk = null
	_restore_identity = RefCounted.new()
	return true


static func _chunk_key(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x >> 4, cell.y >> 4)


static func _chunk_index(cell: Vector2i) -> int:
	return ((cell.y & 15) << 4) + (cell.x & 15)


static func _valid_configuration(size: Vector2i, capacity: int, activation_ms: int) -> bool:
	return size.x >= 1 and size.x <= MAX_AXIS and size.y >= 1 and size.y <= MAX_AXIS and capacity >= 1 and capacity <= MAX_CAPACITY and capacity <= size.x * size.y and activation_ms >= 0 and activation_ms <= MAX_TIME


static func _physical_response(state: Dictionary) -> bool:
	if not _temperature(state.get("initial_value")) or not _temperature(state.get("target_value")):
		return false
	var endpoint: float = float(state.target_value) + float(state.target_per_ms) * float(int(state.until_ms) - int(state.start_ms))
	return _temperature(endpoint)


static func _temperature(value: Variant) -> bool:
	return _number(value) and float(value) >= MIN_C and float(value) <= MAX_C


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	if not _number(value):
		return false
	var number: float = float(value)
	return number >= float(minimum) and number <= float(maximum) and floor(number) == number


static func _keys(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func _inside(cell: Vector2i, size: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


static func _after(cell: Vector2i, previous: Vector2i) -> bool:
	return cell.y > previous.y or cell.y == previous.y and cell.x > previous.x


static func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or a.y == b.y and a.x < b.x


static func _row_before(a: Dictionary, b: Dictionary) -> bool:
	return _cell_before(a.cell, b.cell)


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


class BulkHandle:
	extends RefCounted


class BulkProof:
	extends RefCounted


class BulkBuilder:
	extends RefCounted
	var handle: BulkHandle
	var proof: BulkProof
	var owner_id: int = 0
	var generation: RefCounted
	var revision: int = 0
	var at_ms: int = 0
	var max_chunks: int = 0
	var chunks: Dictionary = {}
	var counts: Dictionary = {}
	var earliest: int = -1
	var tracked_count: int = 0
	var changed: int = 0
	var offered: int = 0
	var previous_key := Vector2i(-1, -1)
	var current_key := Vector2i(-1, -1)
	var cursor: int = 0
	var current_changed: int = 0
	var pending: Dictionary = {}
	var original: Chunk
	var current: Chunk
	var failure: String = ""
	var sealed: bool = false


class Chunk:
	extends RefCounted
	## Only the owner and its unpublished candidate hold these arrays. Cloning a
	## touched block makes every packed column independent of the live block.
	var present := PackedByteArray()
	var starts := PackedInt64Array()
	var untils := PackedInt64Array()
	var initials := PackedFloat64Array()
	var targets := PackedFloat64Array()
	var slopes := PackedFloat64Array()
	var taus := PackedInt32Array()

	func _init(source: Variant = null) -> void:
		if source == null:
			present.resize(256)
			starts.resize(256)
			untils.resize(256)
			initials.resize(256)
			targets.resize(256)
			slopes.resize(256)
			taus.resize(256)
		else:
			present = source.present.duplicate()
			starts = source.starts.duplicate()
			untils = source.untils.duplicate()
			initials = source.initials.duplicate()
			targets = source.targets.duplicate()
			slopes = source.slopes.duplicate()
			taus = source.taus.duplicate()

	func set_anchor(index: int, start_ms: int, until_ms: int, initial: float, target: float, slope: float, tau_ms: int) -> void:
		present[index] = 1
		starts[index] = start_ms
		untils[index] = until_ms
		initials[index] = initial
		targets[index] = target
		slopes[index] = slope
		taus[index] = tau_ms

	func response_at(index: int) -> Dictionary:
		return {"version": 1, "start_ms": starts[index], "until_ms": untils[index],
			"initial_value": initials[index], "target_value": targets[index],
			"target_per_ms": slopes[index], "tau_ms": taus[index]}


class PreparedProof:
	extends RefCounted
	var _rows: Array
	var _at_ms: int

	func _init(rows: Array, at_ms: int) -> void:
		_rows = rows
		_at_ms = at_ms

	func matches(rows: Array, at_ms: int) -> bool:
		return is_same(_rows, rows) and _at_ms == at_ms
