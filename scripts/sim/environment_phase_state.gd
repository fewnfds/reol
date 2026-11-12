class_name SimEnvironmentPhaseState
extends RefCounted
## Actual five-element influence for explicitly tracked cells. This owns no
## world clock, objects or sources. Values use the field cache's milli-grade
## units and its packed metal/wood/water/fire/earth channel order.
##
## For bulk input, mask/initial_mask/until_ms/tau_ms have 256 cell entries;
## initial/target/slope have 256 * 5 values at cell_index * 5 + channel.
## All five channels share a one-second logical sample and response time.
## Source changes in one second replace the next target, retaining that second's
## held value. Reads project whole seconds without advancing a clock or anchor.

const Response = preload("res://scripts/sim/environment_field_response.gd")
const VERSION: int = 2
const CHANNELS: int = 5
const CHUNK_SIDE: int = 16
const CHUNK_CELLS: int = 256
const CHUNK_VALUES: int = CHUNK_CELLS * CHANNELS
const MAX_AXIS: int = 4096
const MAX_CAPACITY: int = 4_194_304
const MAX_BULK_CHUNKS: int = 64
const MAX_TIME: int = Response.MAX_TIME
const MAX_REVISION: int = 9_007_199_254_740_991
const MAX_VALUE: float = Response.MAX_ABS_VALUE

var _configured: bool = false
## Optional model-versioned canonical anchors; numerical reference uses zero.
var anchor_quantum: float = 0.0
var _size := Vector2i.ZERO
var _capacity: int = 0
var _activation_ms: int = 0
var _last_change_ms: int = 0
var _revision: int = 0
var _chunks: Dictionary = {}
var _tracked_count: int = 0
var _boundary_counts: Dictionary = {}
var _earliest_boundary: int = -1
var _identity := RefCounted.new()
var _bulk: BulkBuilder = null


func configure(size: Vector2i, capacity: int, activation_ms: int) -> bool:
	if _configured or not _valid_configuration(size, capacity, activation_ms):
		return false
	_size = size
	_capacity = capacity
	_activation_ms = activation_ms
	_last_change_ms = activation_ms
	_configured = true
	return true


func actual_at(cell: Vector2i, at_ms: int, include_response: bool = false) -> Dictionary:
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
	var sampled_at: int = sample_ms(at_ms)
	var values := PackedFloat64Array()
	values.resize(CHANNELS)
	for channel: int in CHANNELS:
		var offset: int = index * CHANNELS + channel
		var value: float = Response._value_only_unchecked(chunk.starts[index], sampled_at,
			chunk.initials[offset], chunk.targets[offset], chunk.slopes[offset], chunk.taus[index])
		if not _valid_value(value):
			return _failure("response_unavailable")
		values[channel] = clampf(snappedf(value, anchor_quantum), 0.0, MAX_VALUE) if anchor_quantum > 0.0 else value
	var result: Dictionary = {"ok": true, "cell": cell, "at_ms": sampled_at, "values": values}
	if include_response:
		# Diagnostic metadata is not allocated by the ordinary math reads.
		var targets := PackedFloat64Array()
		for channel: int in CHANNELS:
			var offset: int = index * CHANNELS + channel
			targets.append(chunk.targets[offset] + chunk.slopes[offset] * float(sampled_at - chunk.starts[index]))
		result.merge({"targets": targets, "response_start_ms": chunk.starts[index], "tau_ms": chunk.taus[index]})
	return result


func sample_ms(at_ms: int) -> int:
	return maxi(_activation_ms, at_ms - posmod(at_ms, SimCadence.FIELD_SAMPLE_MS))


func response_revision() -> int:
	return _revision


func begin_bulk(at_ms: int, max_changed_chunks: int) -> Dictionary:
	if not _configured:
		return _failure("not_configured")
	if _bulk != null:
		return _failure("busy")
	if at_ms < _last_change_ms or at_ms > MAX_TIME:
		return _failure("time_out_of_range")
	if max_changed_chunks < 1 or max_changed_chunks > MAX_BULK_CHUNKS:
		return _failure("invalid_chunk_limit")
	if _revision >= MAX_REVISION:
		return _failure("revision_exhausted")
	var builder := BulkBuilder.new()
	builder.handle = BulkHandle.new()
	builder.owner_id = get_instance_id()
	builder.generation = _identity
	builder.revision = _revision
	builder.at_ms = at_ms
	builder.max_chunks = max_changed_chunks
	# Copy only the roots; changed blocks are copied on offer. This synchronous
	# root/count copy scales with existing chunks and distinct boundaries.
	builder.chunks = _chunks.duplicate(false)
	builder.counts = _boundary_counts.duplicate(false)
	builder.earliest = _earliest_boundary
	builder.tracked_count = _tracked_count
	builder.initial.resize(CHANNELS)
	builder.target.resize(CHANNELS)
	builder.slope.resize(CHANNELS)
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
	# Detach caller input. It cannot mutate an already offered transaction.
	_bulk.pending = {
		"mask": packed_fields.mask.duplicate(), "initial_mask": packed_fields.initial_mask.duplicate(),
		"initial": packed_fields.initial.duplicate(), "target": packed_fields.target.duplicate(),
		"slope": packed_fields.slope.duplicate(), "until_ms": packed_fields.until_ms.duplicate(),
		"tau_ms": packed_fields.tau_ms.duplicate(),
	}
	var original: Chunk = _chunks.get(coord)
	_bulk.original = original
	_bulk.current = Chunk.new(original)
	_bulk.chunks[coord] = _bulk.current
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
	# Budget includes empty slots, so a sparse block cannot hide a full scan.
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
	if tracked and _bulk.at_ms < original.starts[index]:
		return "history_unavailable"
	if tracked and _bulk.at_ms > original.untils[index]:
		return "target_boundary"
	if not tracked and _bulk.tracked_count >= _capacity:
		return "capacity"
	var until_ms: int = _bulk.pending.until_ms[index]
	var tau_ms: int = _bulk.pending.tau_ms[index]
	var sampled_at: int = sample_ms(_bulk.at_ms)
	if until_ms < _bulk.at_ms or until_ms > MAX_TIME or tau_ms < 1 or tau_ms > Response.MAX_TAU_MS:
		return "target_invalid"
	for channel: int in CHANNELS:
		var offset: int = index * CHANNELS + channel
		if tracked:
			_bulk.initial[channel] = Response._value_only_unchecked(original.starts[index], sampled_at,
				original.initials[offset], original.targets[offset], original.slopes[offset], original.taus[index])
		else:
			_bulk.initial[channel] = _bulk.pending.initial[offset]
		if not _valid_value(_bulk.initial[channel]):
			return "response_unavailable" if tracked else "initial_out_of_range"
		_bulk.target[channel] = _bulk.pending.target[offset]
		_bulk.slope[channel] = _bulk.pending.slope[offset]
		if not _valid_value(_bulk.target[channel]) or not is_finite(_bulk.slope[channel]) or absf(_bulk.slope[channel]) > Response.MAX_ABS_RATE_PER_MS:
			return "target_invalid"
		if not _valid_value(_bulk.target[channel] + _bulk.slope[channel] * float(until_ms - _bulk.at_ms)):
			return "target_invalid"
	if not tracked:
		_bulk.tracked_count += 1
	if anchor_quantum > 0.0:
		for channel: int in CHANNELS:
			_bulk.initial[channel] = clampf(snappedf(_bulk.initial[channel], anchor_quantum), 0.0, MAX_VALUE)
	_bulk.current.set_anchor(index, sampled_at, until_ms, _bulk.initial, _bulk.target, _bulk.slope, tau_ms)
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
	_bulk = null
	return {"ok": true, "revision": _revision, "changed": changed, "at_ms": at_ms}


func cancel_bulk(handle: Variant) -> Dictionary:
	if not _bulk_current(handle):
		return _failure("invalid_handle")
	_bulk = null
	return {"ok": true}


func next_boundary_ms() -> int:
	return _earliest_boundary if _configured else -1


func cell_boundary_ms(cell: Vector2i) -> int:
	var chunk: Chunk = _chunks.get(_chunk_key(cell))
	var index: int = (cell.y & 15) * CHUNK_SIDE + (cell.x & 15)
	return chunk.untils[index] if _inside(cell, _size) and chunk != null and chunk.present[index] != 0 else -1


func chunk_boundary_ms(key: Vector2i) -> int:
	var chunk: Chunk = _chunks.get(key)
	if chunk == null:
		return -1
	var earliest: int = -1
	for index: int in CHUNK_CELLS:
		if chunk.present[index] != 0 and (earliest < 0 or chunk.untils[index] < earliest):
			earliest = chunk.untils[index]
	return earliest


func diagnostics() -> Dictionary:
	return {"configured": _configured, "size": _size, "capacity": _capacity,
		"sample_ms": SimCadence.FIELD_SAMPLE_MS,
		"activation_ms": _activation_ms, "last_change_ms": _last_change_ms,
		"revision": _revision, "tracked": _tracked_count, "chunks": _chunks.size(),
		"next_boundary_ms": next_boundary_ms(), "bulk_active": _bulk != null}


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
		rows.append(chunk.snapshot_row(cell, _chunk_index(cell)))
	return {"version": VERSION, "size": [_size.x, _size.y], "capacity": _capacity,
		"activation_ms": _activation_ms, "last_change_ms": _last_change_ms,
		"revision": _revision, "cells": rows}


func restore(data: Variant) -> bool:
	# Validate and construct the entire candidate before replacing live state.
	if not _keys(data, ["version", "size", "capacity", "activation_ms", "last_change_ms", "revision", "cells"]) or not _integer(data.version, VERSION, VERSION) or not data["size"] is Array or data["size"].size() != 2:
		return false
	if not _integer(data["size"][0], 1, MAX_AXIS) or not _integer(data["size"][1], 1, MAX_AXIS) or not _integer(data.capacity, 1, MAX_CAPACITY) or not _integer(data.activation_ms, 0, MAX_TIME) or not _integer(data.last_change_ms, int(data.activation_ms), MAX_TIME) or not _integer(data.revision, 0, MAX_REVISION):
		return false
	var size := Vector2i(int(data["size"][0]), int(data["size"][1]))
	var capacity: int = int(data.capacity)
	var activation: int = int(data.activation_ms)
	var last_change: int = int(data.last_change_ms)
	var revision: int = int(data.revision)
	if not _valid_configuration(size, capacity, activation) or not data.cells is Array or data.cells.size() > capacity:
		return false
	if revision == 0 and (not data.cells.is_empty() or last_change != activation) or revision > 0 and data.cells.is_empty():
		return false
	var candidate_chunks: Dictionary = {}
	var candidate_counts: Dictionary = {}
	var candidate_boundary: int = -1
	var prior := Vector2i(-1, -1)
	var newest: int = activation
	for row: Variant in data.cells:
		if not _keys(row, ["cell", "start_ms", "until_ms", "tau_ms", "initial", "target", "slope"]) or not row.cell is Array or row.cell.size() != 2 or not _integer(row.cell[0], 0, size.x - 1) or not _integer(row.cell[1], 0, size.y - 1):
			return false
		var cell := Vector2i(int(row.cell[0]), int(row.cell[1]))
		if not _after(cell, prior) or not _integer(row.start_ms, activation, last_change) or not _integer(row.until_ms, int(row.start_ms), MAX_TIME) or not _integer(row.tau_ms, 1, Response.MAX_TAU_MS):
			return false
		if int(row.start_ms) != maxi(activation, int(row.start_ms) - posmod(int(row.start_ms), SimCadence.FIELD_SAMPLE_MS)):
			return false
		if not row.initial is Array or not row.target is Array or not row.slope is Array or row.initial.size() != CHANNELS or row.target.size() != CHANNELS or row.slope.size() != CHANNELS:
			return false
		var initial := PackedFloat64Array()
		var target := PackedFloat64Array()
		var slope := PackedFloat64Array()
		for channel: int in CHANNELS:
			if not _valid_value(row.initial[channel]) or not _valid_value(row.target[channel]) or not _number(row.slope[channel]) or absf(float(row.slope[channel])) > Response.MAX_ABS_RATE_PER_MS:
				return false
			if not _valid_value(float(row.target[channel]) + float(row.slope[channel]) * float(int(row.until_ms) - int(row.start_ms))):
				return false
			# The composed model already quantizes causal anchors on commit. Godot's
			# JSON decimal parser can move a double by an ulp; reconstitute that same
			# model anchor before it drives any future response. Reference mode (0)
			# retains the unquantized numerical contract.
			initial.append(clampf(snappedf(float(row.initial[channel]), anchor_quantum), 0.0, MAX_VALUE) if anchor_quantum > 0.0 else float(row.initial[channel]))
			target.append(float(row.target[channel]))
			slope.append(float(row.slope[channel]))
		var boundary: int = int(row.until_ms)
		candidate_counts[boundary] = int(candidate_counts.get(boundary, 0)) + 1
		if candidate_boundary < 0 or boundary < candidate_boundary:
			candidate_boundary = boundary
		newest = maxi(newest, int(row.start_ms))
		var key: Vector2i = _chunk_key(cell)
		var chunk: Chunk = candidate_chunks.get(key)
		if chunk == null:
			chunk = Chunk.new()
			candidate_chunks[key] = chunk
		chunk.set_anchor(_chunk_index(cell), int(row.start_ms), boundary, initial, target, slope, int(row.tau_ms))
		prior = cell
	if newest != maxi(activation, last_change - posmod(last_change, SimCadence.FIELD_SAMPLE_MS)):
		return false
	_size = size
	_capacity = capacity
	_activation_ms = activation
	_last_change_ms = last_change
	_revision = revision
	_chunks = candidate_chunks
	_tracked_count = data.cells.size()
	_boundary_counts = candidate_counts
	_earliest_boundary = candidate_boundary
	_configured = true
	_bulk = null
	_identity = RefCounted.new()
	return true


func _bulk_current(handle: Variant) -> bool:
	return _bulk != null and handle is BulkHandle and is_same(_bulk.handle, handle) and _bulk.owner_id == get_instance_id() and _bulk.revision == _revision and is_same(_bulk.generation, _identity)


func _bulk_fail(reason: String) -> Dictionary:
	_bulk.failure = reason
	_bulk.pending = {}
	_bulk.original = null
	_bulk.current = null
	return _failure(reason)


static func _bulk_columns_valid(data: Variant) -> bool:
	if not _keys(data, ["mask", "initial_mask", "initial", "target", "slope", "until_ms", "tau_ms"]):
		return false
	return data.mask is PackedByteArray and data.mask.size() == CHUNK_CELLS and data.initial_mask is PackedByteArray and data.initial_mask.size() == CHUNK_CELLS and data.initial is PackedFloat64Array and data.initial.size() == CHUNK_VALUES and data.target is PackedFloat64Array and data.target.size() == CHUNK_VALUES and data.slope is PackedFloat64Array and data.slope.size() == CHUNK_VALUES and data.until_ms is PackedInt64Array and data.until_ms.size() == CHUNK_CELLS and data.tau_ms is PackedInt32Array and data.tau_ms.size() == CHUNK_CELLS


static func _valid_configuration(size: Vector2i, capacity: int, activation_ms: int) -> bool:
	return size.x >= 1 and size.x <= MAX_AXIS and size.y >= 1 and size.y <= MAX_AXIS and capacity >= 1 and capacity <= MAX_CAPACITY and capacity <= size.x * size.y and activation_ms >= 0 and activation_ms <= MAX_TIME


static func _valid_value(value: Variant) -> bool:
	return _number(value) and float(value) >= 0.0 and float(value) <= MAX_VALUE


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


static func _chunk_key(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x >> 4, cell.y >> 4)


static func _chunk_index(cell: Vector2i) -> int:
	return ((cell.y & 15) << 4) + (cell.x & 15)


static func _inside(cell: Vector2i, size: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


static func _after(cell: Vector2i, previous: Vector2i) -> bool:
	return cell.y > previous.y or cell.y == previous.y and cell.x > previous.x


static func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or a.y == b.y and a.x < b.x


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
	# Reused per-cell scratch avoids constructing three small arrays per slot.
	var initial := PackedFloat64Array()
	var target := PackedFloat64Array()
	var slope := PackedFloat64Array()
	var original: Chunk
	var current: Chunk
	var failure: String = ""
	var sealed: bool = false


class Chunk:
	extends RefCounted
	var present := PackedByteArray()
	var starts := PackedInt64Array()
	var untils := PackedInt64Array()
	var initials := PackedFloat64Array()
	var targets := PackedFloat64Array()
	var slopes := PackedFloat64Array()
	var taus := PackedInt32Array()

	func _init(source: Variant = null) -> void:
		if source == null:
			present.resize(CHUNK_CELLS)
			starts.resize(CHUNK_CELLS)
			untils.resize(CHUNK_CELLS)
			initials.resize(CHUNK_VALUES)
			targets.resize(CHUNK_VALUES)
			slopes.resize(CHUNK_VALUES)
			taus.resize(CHUNK_CELLS)
		else:
			present = source.present.duplicate()
			starts = source.starts.duplicate()
			untils = source.untils.duplicate()
			initials = source.initials.duplicate()
			targets = source.targets.duplicate()
			slopes = source.slopes.duplicate()
			taus = source.taus.duplicate()

	func set_anchor(index: int, start_ms: int, until_ms: int, initial: PackedFloat64Array, target: PackedFloat64Array, slope: PackedFloat64Array, tau_ms: int) -> void:
		present[index] = 1
		starts[index] = start_ms
		untils[index] = until_ms
		taus[index] = tau_ms
		for channel: int in CHANNELS:
			var offset: int = index * CHANNELS + channel
			initials[offset] = initial[channel]
			targets[offset] = target[channel]
			slopes[offset] = slope[channel]

	func snapshot_row(cell: Vector2i, index: int) -> Dictionary:
		var initial: Array[float] = []
		var target: Array[float] = []
		var slope: Array[float] = []
		for channel: int in CHANNELS:
			var offset: int = index * CHANNELS + channel
			initial.append(initials[offset])
			target.append(targets[offset])
			slope.append(slopes[offset])
		return {"cell": [cell.x, cell.y], "start_ms": starts[index], "until_ms": untils[index],
			"tau_ms": taus[index], "initial": initial, "target": target, "slope": slope}
