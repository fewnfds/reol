class_name SimEnvironmentFieldCache
extends RefCounted
## Isolated F1 candidate. Slots are caller-owned references to source projections;
## the original object, quantity, energy, clock and environment history remain
## elsewhere. This cache does not implement those owners or save their state.
##
## Rebuilding is resumable. Readers never see a partial tile: an absent/dirty
## tile returns pending until its complete replacement is published. A source
## change discards any in-progress tile, because it can mutate a linked list
## being traversed even when that source itself does not reach the tile.

const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const CHANNELS: int = 7
const TILE_SIZE: int = 16
const MAX_AXIS: int = 4096
const MAX_CAPACITY: int = 4194304
const MAX_WORK: int = 1000000
const MAX_COMPUTE_SNAPSHOT_BYTES: int = 64 * 1024 * 1024
const MAX_CANDIDATE_TILES: int = 64
const UNSET: int = -2

var _size: Vector2i = Vector2i.ZERO
var _capacity: int = 0
var _tile_columns: int = 0
var _heads := PackedInt32Array()
var _cell_source_counts := PackedInt32Array()
var _max_cell_sources: int = 0 # conservative upper bound after removals
var _slot_x := PackedInt32Array()
var _slot_y := PackedInt32Array()
var _slot_radius := PackedInt32Array() # zero marks an inactive slot
var _slot_next := PackedInt32Array()
var _slot_channels := PackedInt32Array() # seven grades per slot
var _radius_counts := PackedInt32Array()
var _max_source := PackedInt32Array() # conservative; never decreases
var _max_radius: int = 0
var _source_count: int = 0
var _revision: int = 0
var _kernels: Dictionary[int, PackedInt32Array] = {}
var _ordered_radius: int = -1
var _ordered_offsets := PackedInt32Array() # fixed 9-bit biased x/y code
var _ordered_weights := PackedInt32Array()

# Tile records only exist for requested cells. Each complete values array is a
# disposable projection. Queued records stay dirty until atomically replaced.
var _tiles: Dictionary[int, Dictionary] = {}
var _queue: Array[int] = []
var _queue_cursor: int = 0
var _build_tile: int = -1
var _build_rect: Rect2i = Rect2i()
var _build_values := PackedInt32Array()
var _build_offsets := PackedInt32Array()
var _build_weights := PackedInt32Array()
var _build_phase: int = 0 # 0 receiver search, 2 complete
var _receiver_index: int = 0
var _receiver_x: int = 0
var _receiver_y: int = 0
var _receiver_channel: int = 0
var _receiver_best: int = 0
var _neighbor_index: int = 0
var _neighbor_slot: int = UNSET
var _neighbor_dx: int = 0
var _neighbor_dy: int = 0
# At most one unpublished source projection; physical source ownership remains
# with the caller. Candidate computation never changes live slots or tiles.
var _source_candidate: SourceCandidate = null


func configure(size: Vector2i, capacity: int) -> bool:
	if _capacity != 0 or size.x < 1 or size.y < 1 or size.x > MAX_AXIS or size.y > MAX_AXIS or capacity < 1 or capacity > MAX_CAPACITY:
		return false
	# Prepare all arrays locally so a reported allocation failure does not
	# publish a half-configured index. The engine may itself abort on OOM.
	var heads := PackedInt32Array()
	var cell_counts := PackedInt32Array()
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	var radii := PackedInt32Array()
	var next := PackedInt32Array()
	var channels := PackedInt32Array()
	var counts := PackedInt32Array()
	var maxima := PackedInt32Array()
	if heads.resize(size.x * size.y) != OK or cell_counts.resize(size.x * size.y) != OK or xs.resize(capacity) != OK or ys.resize(capacity) != OK or radii.resize(capacity) != OK or next.resize(capacity) != OK or channels.resize(capacity * CHANNELS) != OK or counts.resize(Rules.MAX_RADIUS + 1) != OK or maxima.resize(CHANNELS) != OK:
		return false
	heads.fill(-1)
	next.fill(-1)
	_heads = heads
	_cell_source_counts = cell_counts
	_slot_x = xs
	_slot_y = ys
	_slot_radius = radii
	_slot_next = next
	_slot_channels = channels
	_radius_counts = counts
	_max_source = maxima
	_size = size
	_capacity = capacity
	@warning_ignore("integer_division")
	_tile_columns = (size.x + TILE_SIZE - 1) / TILE_SIZE
	return true


func set_source(slot: int, cell: Vector2i, radius: int, channels: Variant) -> Dictionary:
	if _capacity == 0:
		return _failure("not_configured")
	if slot < 0 or slot >= _capacity:
		return _failure("slot_out_of_range")
	if not _inside(cell):
		return _failure("source_cell")
	if radius < 1 or radius > Rules.MAX_RADIUS:
		return _failure("source_radius")
	if not (channels is Array or channels is PackedInt32Array or channels is PackedInt64Array) or channels.size() != CHANNELS:
		return _failure("source_channels")
	var normalized := PackedInt32Array()
	for value: Variant in channels:
		if not value is int or value < 0 or value > Rules.MAX_GRADE_MILLI:
			return _failure("source_channel_value")
		normalized.append(value)
	var old_radius: int = _slot_radius[slot]
	var old_cell := Vector2i(_slot_x[slot], _slot_y[slot])
	var unchanged: bool = old_radius == radius and old_cell == cell
	if unchanged:
		for channel: int in CHANNELS:
			if _slot_channels[slot * CHANNELS + channel] != normalized[channel]:
				unchanged = false
				break
	if unchanged:
		return {"ok": true, "changed": false, "revision": _revision, "old_area": Rect2i(), "new_area": Rect2i()}
	# Tables are reusable, derived geometry only; no source/owner mutation has
	# happened before the entire input is validated.
	_ensure_kernel(radius)
	var old_area: Rect2i = _coverage(old_cell, old_radius) if old_radius > 0 else Rect2i()
	var new_area: Rect2i = _coverage(cell, radius)
	if old_radius > 0:
		_unlink(slot, old_cell)
		_radius_counts[old_radius] -= 1
	else:
		_source_count += 1
	_slot_x[slot] = cell.x
	_slot_y[slot] = cell.y
	_slot_radius[slot] = radius
	for channel: int in CHANNELS:
		_slot_channels[slot * CHANNELS + channel] = normalized[channel]
		_max_source[channel] = maxi(_max_source[channel], normalized[channel])
	var head_index: int = _linear(cell)
	_slot_next[slot] = _heads[head_index]
	_heads[head_index] = slot
	_cell_source_counts[head_index] += 1
	_max_cell_sources = maxi(_max_cell_sources, _cell_source_counts[head_index])
	_radius_counts[radius] += 1
	_max_radius = maxi(_max_radius, radius)
	_trim_max_radius()
	_revision += 1
	_abort_build()
	_mark_dirty(old_area)
	_mark_dirty(new_area)
	return {"ok": true, "changed": true, "revision": _revision, "old_area": old_area, "new_area": new_area}


func remove_source(slot: int) -> Dictionary:
	if _capacity == 0:
		return _failure("not_configured")
	if slot < 0 or slot >= _capacity:
		return _failure("slot_out_of_range")
	var radius: int = _slot_radius[slot]
	if radius == 0:
		return _failure("unknown_source")
	var cell := Vector2i(_slot_x[slot], _slot_y[slot])
	var old_area: Rect2i = _coverage(cell, radius)
	_unlink(slot, cell)
	_slot_radius[slot] = 0
	_slot_next[slot] = -1
	_radius_counts[radius] -= 1
	_source_count -= 1
	_trim_max_radius()
	_revision += 1
	_abort_build()
	_mark_dirty(old_area)
	return {"ok": true, "revision": _revision, "old_area": old_area}


func begin_source_change(slot: int, operation: String, change: Dictionary = {}) -> Dictionary:
	# A failed or busy begin never displaces an existing candidate.
	if _source_candidate != null:
		return _failure("busy")
	if _capacity == 0:
		return _failure("not_configured")
	if slot < 0 or slot >= _capacity:
		return _failure("slot_out_of_range")
	var old_radius: int = _slot_radius[slot]
	var old_cell := Vector2i(_slot_x[slot], _slot_y[slot])
	var new_cell := Vector2i.ZERO
	var new_radius: int = 0
	var normalized := PackedInt32Array()
	if operation == "remove":
		if not change.is_empty():
			return _failure("source_shape")
		if old_radius == 0:
			return _failure("unknown_source")
	elif operation == "set":
		if change.size() != 3 or not change.has("cell") or not change.has("radius") or not change.has("channels") or not change.cell is Vector2i or not change.radius is int:
			return _failure("source_shape")
		new_cell = change.cell
		new_radius = change.radius
		if not _inside(new_cell):
			return _failure("source_cell")
		if new_radius < 1 or new_radius > Rules.MAX_RADIUS:
			return _failure("source_radius")
		if not (change.channels is Array or change.channels is PackedInt32Array or change.channels is PackedInt64Array) or change.channels.size() != CHANNELS:
			return _failure("source_channels")
		for value: Variant in change.channels:
			if not value is int or value < 0 or value > Rules.MAX_GRADE_MILLI:
				return _failure("source_channel_value")
			normalized.append(value)
		var unchanged: bool = old_radius == new_radius and old_cell == new_cell
		if unchanged:
			for channel: int in CHANNELS:
				if _slot_channels[slot * CHANNELS + channel] != normalized[channel]:
					unchanged = false
					break
		if unchanged:
			return _failure("unchanged")
	else:
		return _failure("source_operation")
	var old_area: Rect2i = _coverage(old_cell, old_radius)
	var new_area: Rect2i = _coverage(new_cell, new_radius)
	var tile_set: Dictionary[int, bool] = {}
	if not _add_candidate_tiles(old_area, tile_set) or not _add_candidate_tiles(new_area, tile_set):
		return _failure("candidate_tile_limit")
	var ids: Array[int] = []
	for tile_id: int in tile_set:
		ids.append(tile_id)
	ids.sort()
	ids.make_read_only()
	# New kernels and the existing ordered-offset table may require a
	# synchronous first build; this setup is not covered by step's budget.
	var new_kernel := PackedInt32Array()
	if new_radius > 0:
		new_kernel = _kernels[new_radius] if _kernels.has(new_radius) else _make_kernel(new_radius)
	if _max_radius > 0:
		_ensure_ordered_offsets()
	var candidate := SourceCandidate.new()
	candidate.handle = SourceChangeHandle.new()
	candidate.revision = _revision
	candidate.slot = slot
	candidate.old_cell = old_cell
	candidate.old_radius = old_radius
	candidate.new_cell = new_cell
	candidate.new_radius = new_radius
	candidate.new_channels = normalized
	candidate.new_kernel = new_kernel
	candidate.old_area = old_area
	candidate.new_area = new_area
	candidate.tile_ids = ids
	candidate.tile_set = tile_set
	if _max_radius > 0:
		candidate.offsets = _ordered_offsets
		candidate.weights = _ordered_weights
	_source_candidate = candidate
	var public_ids: Array = ids.duplicate()
	public_ids.make_read_only()
	return {"ok": true, "handle": candidate.handle, "tile_ids": public_ids,
		"old_area": old_area, "new_area": new_area}


func step_source_change(handle: Variant, max_work: int) -> Dictionary:
	if not _source_handle_matches(handle):
		return _failure("invalid_handle")
	if _source_candidate.revision != _revision:
		return _failure("stale")
	if _source_candidate.sealed:
		return _failure("already_finished")
	if max_work < 0 or max_work > MAX_WORK:
		return _failure("work_budget")
	var used: int = 0
	while used < max_work and _source_candidate.tile_index < _source_candidate.tile_ids.size():
		if not _source_candidate.building:
			var tile_id: int = _source_candidate.tile_ids[_source_candidate.tile_index]
			_source_candidate.rect = _rect_for_tile(tile_id)
			_source_candidate.values = PackedInt32Array()
			if _source_candidate.values.resize(_source_candidate.rect.size.x * _source_candidate.rect.size.y * CHANNELS) != OK:
				return _failure("candidate_allocation")
			_source_candidate.receiver_index = 0
			_source_candidate.receiver_x = _source_candidate.rect.position.x
			_source_candidate.receiver_y = _source_candidate.rect.position.y
			_source_candidate.channel = 0
			_source_candidate.phase = 0
			_source_candidate.offset_index = 0
			_source_candidate.neighbor_slot = UNSET
			_source_candidate.building = true
		else:
			_step_source_candidate()
		used += 1
	return {"ok": true, "work": used, "done": _source_candidate.tile_index == _source_candidate.tile_ids.size(),
		"completed_tiles": _source_candidate.tile_index, "total_tiles": _source_candidate.tile_ids.size()}


func _step_source_candidate() -> void:
	var candidate: SourceCandidate = _source_candidate
	if candidate.phase == 0:
		# Count the candidate source independently; it is absent from the live
		# scan below, and never mutates the live heads/slots while pending.
		candidate.best = 0
		if candidate.new_radius > 0:
			var dx: int = absi(candidate.receiver_x - candidate.new_cell.x)
			var dy: int = absi(candidate.receiver_y - candidate.new_cell.y)
			if dx < candidate.new_radius and dy < candidate.new_radius:
				var strength: int = candidate.new_channels[candidate.channel]
				var weight: int = candidate.new_kernel[dy * candidate.new_radius + dx]
				@warning_ignore("integer_division")
				candidate.best = (strength * weight + Rules.SCALE / 2) / Rules.SCALE
		candidate.phase = 1
		return
	if candidate.neighbor_slot == UNSET:
		if candidate.offset_index >= candidate.offsets.size():
			_finish_source_candidate_channel()
			return
		@warning_ignore("integer_division")
		var upper: int = (_max_source[candidate.channel] * candidate.weights[candidate.offset_index] + Rules.SCALE / 2) / Rules.SCALE
		if upper <= candidate.best:
			_finish_source_candidate_channel()
			return
		var code: int = candidate.offsets[candidate.offset_index]
		candidate.dx = (code & 511) - 255
		candidate.dy = (code >> 9) - 255
		var x: int = candidate.receiver_x + candidate.dx
		var y: int = candidate.receiver_y + candidate.dy
		if x < 0 or y < 0 or x >= _size.x or y >= _size.y:
			candidate.offset_index += 1
			return
		candidate.neighbor_slot = _heads[y * _size.x + x]
		if candidate.neighbor_slot == -1:
			candidate.neighbor_slot = UNSET
			candidate.offset_index += 1
		return # resolving an offset and consuming a source are separate work
	var source_slot: int = candidate.neighbor_slot
	if source_slot != candidate.slot:
		var radius: int = _slot_radius[source_slot]
		var dx: int = absi(candidate.dx)
		var dy: int = absi(candidate.dy)
		var strength: int = _slot_channels[source_slot * CHANNELS + candidate.channel]
		if strength > candidate.best and dx < radius and dy < radius:
			var kernel: PackedInt32Array = _kernels[radius]
			@warning_ignore("integer_division")
			var value: int = (strength * kernel[dy * radius + dx] + Rules.SCALE / 2) / Rules.SCALE
			candidate.best = maxi(candidate.best, value)
	candidate.neighbor_slot = _slot_next[source_slot]
	if candidate.neighbor_slot == -1:
		candidate.neighbor_slot = UNSET
		candidate.offset_index += 1


func _finish_source_candidate_channel() -> void:
	var candidate: SourceCandidate = _source_candidate
	candidate.values[candidate.receiver_index * CHANNELS + candidate.channel] = candidate.best
	candidate.channel += 1
	candidate.phase = 0
	candidate.offset_index = 0
	candidate.neighbor_slot = UNSET
	if candidate.channel < CHANNELS:
		return
	candidate.channel = 0
	candidate.receiver_index += 1
	if candidate.receiver_index == candidate.rect.size.x * candidate.rect.size.y:
		candidate.results[candidate.tile_ids[candidate.tile_index]] = candidate.values
		candidate.values = PackedInt32Array()
		candidate.tile_index += 1
		candidate.building = false
		return
	candidate.receiver_x += 1
	if candidate.receiver_x >= candidate.rect.end.x:
		candidate.receiver_x = candidate.rect.position.x
		candidate.receiver_y += 1


func finish_source_change(handle: Variant) -> Dictionary:
	if not _source_handle_matches(handle):
		return _failure("invalid_handle")
	if _source_candidate.revision != _revision:
		return _failure("stale")
	if _source_candidate.sealed:
		return _failure("already_finished")
	if _source_candidate.tile_index != _source_candidate.tile_ids.size():
		return _failure("pending")
	_source_candidate.sealed = true
	_source_candidate.proof = SourceChangeProof.new()
	var result: Dictionary = {"ok": true, "proof": _source_candidate.proof}
	result.make_read_only()
	return result


func candidate_tile_copy(proof: Variant, tile_id: int) -> Dictionary:
	var checked: Dictionary = can_commit_source_change(proof)
	if not bool(checked.get("ok", false)):
		return checked
	if not _source_candidate.tile_set.has(tile_id):
		return _failure("candidate_tile")
	var values: PackedInt32Array = _source_candidate.results[tile_id]
	return {"ok": true, "rect": _rect_for_tile(tile_id), "channels": values.duplicate()}


func can_commit_source_change(proof: Variant) -> Dictionary:
	if _source_candidate == null or not _source_candidate.sealed or not proof is SourceChangeProof or not is_same(_source_candidate.proof, proof):
		return _failure("invalid_proof")
	if _source_candidate.revision != _revision:
		return _failure("stale")
	return {"ok": true, "revision": _revision}


func commit_source_change(proof: Variant) -> Dictionary:
	var checked: Dictionary = can_commit_source_change(proof)
	if not bool(checked.get("ok", false)):
		return checked
	var candidate: SourceCandidate = _source_candidate
	# Preserve unrelated queue entries in order, including those enqueued while
	# the candidate was computed. Only replaced tiles are removed from it.
	var remaining: Array[int] = []
	for index: int in range(_queue_cursor, _queue.size()):
		if not candidate.tile_set.has(_queue[index]):
			remaining.append(_queue[index])
	if candidate.tile_set.has(_build_tile):
		_build_values = PackedInt32Array()
		_build_offsets = PackedInt32Array()
		_build_weights = PackedInt32Array()
		_build_tile = -1
	elif _build_tile >= 0 and _neighbor_slot == candidate.slot and candidate.old_radius > 0:
		# The build is outside both affected footprints, so this source has zero
		# contribution there. Advance past its old link before relinking it.
		_neighbor_slot = _slot_next[candidate.slot]
		if _neighbor_slot == -1:
			_neighbor_slot = UNSET
			_neighbor_index += 1
	_apply_source_candidate(candidate)
	for tile_id: int in candidate.tile_ids:
		var tile: Dictionary = _tiles.get(tile_id, {})
		tile["values"] = candidate.results[tile_id]
		tile["dirty"] = false
		tile["queued"] = false
		_tiles[tile_id] = tile
	_queue = remaining
	_queue_cursor = 0
	_revision += 1
	_source_candidate = null
	return {"ok": true, "revision": _revision, "old_area": candidate.old_area,
		"new_area": candidate.new_area, "published_tiles": candidate.tile_ids.size()}


func cancel_source_change(handle: Variant) -> Dictionary:
	# Cancellation remains available after an external source change made the
	# candidate stale; it never changes live source or cache state.
	if not _source_handle_matches(handle):
		return _failure("invalid_handle")
	_source_candidate = null
	return {"ok": true}


func _source_handle_matches(handle: Variant) -> bool:
	return _source_candidate != null and handle is SourceChangeHandle and is_same(_source_candidate.handle, handle)


func _add_candidate_tiles(area: Rect2i, result: Dictionary[int, bool]) -> bool:
	if area.size.x == 0 or area.size.y == 0:
		return true
	for y: int in range(area.position.y >> 4, ((area.end.y - 1) >> 4) + 1):
		for x: int in range(area.position.x >> 4, ((area.end.x - 1) >> 4) + 1):
			result[y * _tile_columns + x] = true
			if result.size() > MAX_CANDIDATE_TILES:
				return false
	return true


func _apply_source_candidate(candidate: SourceCandidate) -> void:
	var slot: int = candidate.slot
	if candidate.old_radius > 0:
		_unlink(slot, candidate.old_cell)
		_radius_counts[candidate.old_radius] -= 1
	if candidate.new_radius > 0:
		if not _kernels.has(candidate.new_radius):
			_kernels[candidate.new_radius] = candidate.new_kernel
		if candidate.old_radius == 0:
			_source_count += 1
		_slot_x[slot] = candidate.new_cell.x
		_slot_y[slot] = candidate.new_cell.y
		_slot_radius[slot] = candidate.new_radius
		for channel: int in CHANNELS:
			var value: int = candidate.new_channels[channel]
			_slot_channels[slot * CHANNELS + channel] = value
			_max_source[channel] = maxi(_max_source[channel], value)
		var head_index: int = _linear(candidate.new_cell)
		_slot_next[slot] = _heads[head_index]
		_heads[head_index] = slot
		_cell_source_counts[head_index] += 1
		_max_cell_sources = maxi(_max_cell_sources, _cell_source_counts[head_index])
		_radius_counts[candidate.new_radius] += 1
		_max_radius = maxi(_max_radius, candidate.new_radius)
	else:
		_slot_radius[slot] = 0
		_slot_next[slot] = -1
		_source_count -= 1
	_trim_max_radius()


func read_base(cell: Vector2i) -> Dictionary:
	if _capacity == 0:
		return _failure("not_configured")
	if not _inside(cell):
		return _failure("outside_map")
	var tile_id: int = _tile_for_cell(cell)
	if not _tiles.has(tile_id):
		_tiles[tile_id] = {"dirty": true, "queued": true, "values": PackedInt32Array()}
		_queue.append(tile_id)
	var tile: Dictionary = _tiles[tile_id]
	if bool(tile.dirty):
		return {"ok": true, "pending": true, "revision": _revision}
	var rect: Rect2i = _rect_for_tile(tile_id)
	var offset: int = ((cell.y - rect.position.y) * rect.size.x + cell.x - rect.position.x) * CHANNELS
	var stored: PackedInt32Array = tile.values
	var result := PackedInt32Array()
	result.resize(CHANNELS)
	for channel: int in CHANNELS:
		result[channel] = stored[offset + channel]
	return {"ok": true, "pending": false, "channels": result, "revision": _revision}


func request_area(area: Rect2i) -> Dictionary:
	# Validate the entire tile-aligned region before queuing anything. This
	# CPU path does not copy the map, sources, kernels or any field values.
	if _capacity == 0:
		return _failure("not_configured")
	if not _valid_compute_area(area):
		return _failure("compute_area")
	var requested: int = 0
	var pending: int = 0
	for y: int in range(area.position.y, area.end.y, TILE_SIZE):
		for x: int in range(area.position.x, area.end.x, TILE_SIZE):
			var result: Dictionary = read_base(Vector2i(x, y))
			if not bool(result.ok):
				return result
			requested += 1
			if bool(result.pending):
				pending += 1
	return {"ok": true, "requested_tiles": requested, "pending_requested_tiles": pending,
		"pending_tiles": _pending_tiles(), "revision": _revision}


func export_compute_job(area: Rect2i, compact: bool = false) -> Dictionary:
	if _capacity == 0:
		return _failure("not_configured")
	if not _valid_compute_area(area):
		return _failure("compute_area")
	# A window covering the whole map needs no source-ID remapping. Keep the
	# native SoA copy path for this common case instead of interpreted packing.
	if compact and area.grow(maxi(0, _max_radius - 1)).encloses(Rect2i(Vector2i.ZERO, _size)):
		return export_compute_job(area, false)
	# This is a synchronous snapshot of projections, not another item owner.
	# Full packing is O(map cells + capacity * 11 + active kernel values).
	# Compact packing visits the clipped influence window and its references;
	# neither mode is represented as a bounded rebuild work unit.
	var params := PackedInt32Array([_size.x, _size.y, _capacity, _max_radius,
		area.position.x, area.position.y, area.size.x, area.size.y])
	var projection: Dictionary
	if compact:
		projection = _compact_projection(area)
	else:
		if (_size.x * _size.y + _capacity * 11) * 4 > MAX_COMPUTE_SNAPSHOT_BYTES:
			return _failure("compute_snapshot_budget")
		# SoA header of four capacity-sized arrays (x, y, radius, next),
		# followed by seven interleaved channel values per slot.
		var slots: PackedInt32Array = _slot_x.duplicate()
		slots.append_array(_slot_y)
		slots.append_array(_slot_radius)
		slots.append_array(_slot_next)
		slots.append_array(_slot_channels)
		if slots.size() != _capacity * 11:
			return _failure("snapshot_allocation")
		projection = {"ok": true, "params": params.duplicate(), "heads": _heads.duplicate(), "slots": slots}
	if not bool(projection.get("ok", false)):
		return projection
	var offsets := PackedInt32Array()
	var kernels := PackedInt32Array()
	if offsets.resize(Rules.MAX_RADIUS + 1) != OK:
		return _failure("snapshot_allocation")
	offsets.fill(-1)
	for radius: int in range(1, Rules.MAX_RADIUS + 1):
		if _radius_counts[radius] <= 0:
			continue
		offsets[radius] = kernels.size()
		kernels.append_array(_kernels[radius])
	# A valid job is publishable only for previously requested whole tiles.
	# Request missing tiles without disturbing already clean or in-flight ones.
	for y: int in range(area.position.y, area.end.y, TILE_SIZE):
		for x: int in range(area.position.x, area.end.x, TILE_SIZE):
			var tile_id: int = _tile_for_cell(Vector2i(x, y))
			if not _tiles.has(tile_id):
				_tiles[tile_id] = {"dirty": true, "queued": true, "values": PackedInt32Array()}
				_queue.append(tile_id)
	return {"ok": true, "owner_token": get_instance_id(), "revision": _revision,
		"area": area, "params": params, "compute_params": projection.params,
		"max_cell_sources": mini(int(projection.params[2]), maxi(1, _max_cell_sources)),
		"heads": projection.heads, "slots": projection.slots,
		"kernels": kernels, "radius_offsets": offsets}


func _compact_projection(area: Rect2i) -> Dictionary:
	var extent: int = maxi(0, _max_radius - 1)
	var left: int = maxi(0, area.position.x - extent)
	var top: int = maxi(0, area.position.y - extent)
	var right: int = mini(_size.x, area.end.x + extent)
	var bottom: int = mini(_size.y, area.end.y + extent)
	var width: int = right - left
	var height: int = bottom - top
	var heads := PackedInt32Array()
	if heads.resize(width * height) != OK:
		return _failure("snapshot_allocation")
	heads.fill(-1)
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	var radii := PackedInt32Array()
	var next := PackedInt32Array()
	var channels := PackedInt32Array()
	var local_max_radius: int = 0
	# Allocate local IDs consecutively while visiting each global cell. Linking
	# to the previous local head remaps co-located sources without a global-ID
	# map or capacity-wide scan; reversing source order cannot affect max values.
	for y: int in range(top, bottom):
		for x: int in range(left, right):
			var slot: int = _heads[y * _size.x + x]
			var local_head: int = -1
			while slot >= 0:
				var local_slot: int = xs.size()
				if (width * height + (local_slot + 1) * 11) * 4 > MAX_COMPUTE_SNAPSHOT_BYTES:
					return _failure("compute_snapshot_budget")
				xs.append(x - left)
				ys.append(y - top)
				radii.append(_slot_radius[slot])
				next.append(local_head)
				for channel: int in CHANNELS:
					channels.append(_slot_channels[slot * CHANNELS + channel])
				local_head = local_slot
				local_max_radius = maxi(local_max_radius, _slot_radius[slot])
				slot = _slot_next[slot]
			heads[(y - top) * width + x - left] = local_head
	# Device storage buffers cannot be zero-sized. Empty windows retain one
	# inactive slot and max radius zero; all heads remain -1.
	if xs.is_empty():
		xs.append(0)
		ys.append(0)
		radii.append(0)
		next.append(-1)
		if channels.resize(CHANNELS) != OK:
			return _failure("snapshot_allocation")
	var local_capacity: int = xs.size()
	if ys.size() != local_capacity or radii.size() != local_capacity or next.size() != local_capacity or channels.size() != local_capacity * CHANNELS:
		return _failure("snapshot_allocation")
	var slots: PackedInt32Array = xs.duplicate()
	slots.append_array(ys)
	slots.append_array(radii)
	slots.append_array(next)
	slots.append_array(channels)
	if slots.size() != local_capacity * 11:
		return _failure("snapshot_allocation")
	return {"ok": true,
		"params": PackedInt32Array([width, height, local_capacity, local_max_radius,
			area.position.x - left, area.position.y - top, area.size.x, area.size.y]),
		"heads": heads, "slots": slots}


static func prepare_compute_result(job: Dictionary, values: PackedInt32Array) -> Dictionary:
	# This worker-side function touches only an immutable job snapshot and its
	# result buffer. Callers must transfer exclusive ownership of both inputs;
	# concurrently changing them is unsupported. It never reads a live cache.
	if not job.get("ok", false) is bool or not bool(job.get("ok", false)):
		return _failure("compute_job")
	# Godot RefCounted instance IDs may have the signed high bit set.
	if not job.get("owner_token") is int or int(job.owner_token) == 0:
		return _failure("compute_owner")
	if not job.get("revision") is int or int(job.revision) < 0:
		return _failure("compute_stale")
	if not job.get("area") is Rect2i:
		return _failure("compute_area")
	if not job.get("params") is PackedInt32Array:
		return _failure("compute_params")
	var area: Rect2i = job.area
	var params: PackedInt32Array = job.params
	if params.size() != 8 or params[0] < 1 or params[1] < 1 or params[0] > MAX_AXIS or params[1] > MAX_AXIS or params[2] < 1 or params[2] > MAX_CAPACITY or params[3] < 0 or params[3] > Rules.MAX_RADIUS:
		return _failure("compute_params")
	if not _valid_compute_area_for(area, Vector2i(params[0], params[1])):
		return _failure("compute_area")
	if params[4] != area.position.x or params[5] != area.position.y or params[6] != area.size.x or params[7] != area.size.y:
		return _failure("compute_params")
	if values.size() != area.size.x * area.size.y * CHANNELS:
		return _failure("compute_values_length")
	for value: int in values:
		if value < 0 or value > Rules.MAX_GRADE_MILLI:
			return _failure("compute_value_range")
	@warning_ignore("integer_division")
	var tile_columns: int = (params[0] + TILE_SIZE - 1) / TILE_SIZE
	var tiles: Array[Dictionary] = []
	for y: int in range(area.position.y, area.end.y, TILE_SIZE):
		for x: int in range(area.position.x, area.end.x, TILE_SIZE):
			var width: int = mini(TILE_SIZE, params[0] - x)
			var height: int = mini(TILE_SIZE, params[1] - y)
			var tile_values := PackedInt32Array()
			for row: int in height:
				var source: int = ((y + row - area.position.y) * area.size.x + x - area.position.x) * CHANNELS
				tile_values.append_array(values.slice(source, source + width * CHANNELS))
			if tile_values.size() != width * height * CHANNELS:
				return _failure("compute_allocation")
			@warning_ignore("integer_division")
			var tile_id: int = (y / TILE_SIZE) * tile_columns + (x / TILE_SIZE)
			tiles.append({"id": tile_id, "values": tile_values})
	return {"ok": true, "owner_token": int(job.owner_token), "revision": int(job.revision),
		"area": area, "params": params.duplicate(), "tiles": tiles}


func publish_compute_result(job: Dictionary, prepared: Dictionary) -> Dictionary:
	# prepared must be an exclusively transferred return of our internal
	# prepare_compute_result worker; no concurrent mutation is supported.
	# It is NOT an untrusted input: range validation already ran in the worker.
	if _capacity == 0:
		return _failure("not_configured")
	if not job.get("ok", false) is bool or not bool(job.get("ok", false)):
		return _failure("compute_job")
	if not job.get("owner_token") is int or int(job.owner_token) != get_instance_id():
		return _failure("compute_owner")
	if not job.get("revision") is int or int(job.revision) != _revision:
		return _failure("compute_stale")
	if not job.get("area") is Rect2i:
		return _failure("compute_area")
	var area: Rect2i = job.area
	if not _valid_compute_area(area):
		return _failure("compute_area")
	if not job.get("params") is PackedInt32Array:
		return _failure("compute_params")
	var params: PackedInt32Array = job.params
	if params.size() != 8 or params[0] != _size.x or params[1] != _size.y or params[2] != _capacity or params[3] != _max_radius or params[4] != area.position.x or params[5] != area.position.y or params[6] != area.size.x or params[7] != area.size.y:
		return _failure("compute_params")
	if not prepared.get("ok", false) is bool or not bool(prepared.get("ok", false)):
		return _failure("compute_prepared")
	if not prepared.get("owner_token") is int or int(prepared.owner_token) != get_instance_id():
		return _failure("compute_owner")
	if not prepared.get("revision") is int or int(prepared.revision) != _revision:
		return _failure("compute_stale")
	if not prepared.get("area") is Rect2i or prepared.area != area or not prepared.get("params") is PackedInt32Array or prepared.params != params or not prepared.get("tiles") is Array:
		return _failure("compute_prepared")
	var target_ids: Array[int] = []
	var target_set: Dictionary[int, bool] = {}
	for y: int in range(area.position.y, area.end.y, TILE_SIZE):
		for x: int in range(area.position.x, area.end.x, TILE_SIZE):
			var tile_id: int = _tile_for_cell(Vector2i(x, y))
			if not _tiles.has(tile_id):
				return _failure("compute_unrequested")
			target_ids.append(tile_id)
			target_set[tile_id] = true
	var prepared_tiles: Array = prepared.tiles
	if prepared_tiles.size() != target_ids.size():
		return _failure("compute_tile_count")
	# Validate the complete unique set before replacing a single tile. Order is
	# allowed to differ so a worker may return blocks in any deterministic order.
	var seen: Dictionary[int, bool] = {}
	for entry: Variant in prepared_tiles:
		if not entry is Dictionary or not entry.get("id") is int or not entry.get("values") is PackedInt32Array:
			return _failure("compute_tile_shape")
		var tile_id: int = int(entry.id)
		if not target_set.has(tile_id) or seen.has(tile_id):
			return _failure("compute_tile_id")
		var rect: Rect2i = _rect_for_tile(tile_id)
		var tile_values: PackedInt32Array = entry.values
		if tile_values.size() != rect.size.x * rect.size.y * CHANNELS:
			return _failure("compute_tile_length")
		seen[tile_id] = true
	# Copy in the engine before committing so even a sequential caller mutation
	# of its former worker result cannot change the published cache. This only
	# happens after all shapes were checked, and before any live tile changes.
	var commit_values: Array[PackedInt32Array] = []
	for entry: Dictionary in prepared_tiles:
		var tile_values: PackedInt32Array = entry.values
		var copy: PackedInt32Array = tile_values.duplicate()
		if copy.size() != tile_values.size():
			return _failure("compute_allocation")
		commit_values.append(copy)
	var remaining: Array[int] = []
	for index: int in range(_queue_cursor, _queue.size()):
		var tile_id: int = _queue[index]
		if not target_set.has(tile_id):
			remaining.append(tile_id)
	# Discard an in-progress CPU draft only when this result replaces its tile.
	# A draft for any other pending tile retains its exact cursor and values.
	if target_set.has(_build_tile):
		_build_values = PackedInt32Array()
		_build_offsets = PackedInt32Array()
		_build_weights = PackedInt32Array()
		_build_tile = -1
	for index: int in prepared_tiles.size():
		var entry: Dictionary = prepared_tiles[index]
		var tile: Dictionary = _tiles[int(entry.id)]
		tile.values = commit_values[index]
		tile.dirty = false
		tile.queued = false
	_queue = remaining
	_queue_cursor = 0
	return {"ok": true, "published_tiles": target_ids.size(), "pending_tiles": _pending_tiles(), "revision": _revision}


func accept_compute_result(job: Dictionary, values: PackedInt32Array) -> Dictionary:
	# Synchronous convenience for existing callers/tests. The scalable runtime
	# runs prepare on an isolated worker, then calls publish on the owner thread.
	var prepared: Dictionary = prepare_compute_result(job, values)
	if not bool(prepared.get("ok", false)):
		return prepared
	return publish_compute_result(job, prepared)


func _valid_compute_area(area: Rect2i) -> bool:
	return _valid_compute_area_for(area, _size)


static func _valid_compute_area_for(area: Rect2i, size: Vector2i) -> bool:
	if area.position.x < 0 or area.position.y < 0 or area.size.x <= 0 or area.size.y <= 0 or area.size.x > size.x or area.size.y > size.y:
		return false
	# Check without adding arbitrary coordinates before using Rect2i.end.
	if area.position.x > size.x - area.size.x or area.position.y > size.y - area.size.y:
		return false
	if area.position.x % TILE_SIZE != 0 or area.position.y % TILE_SIZE != 0:
		return false
	if area.end.x != size.x and area.end.x % TILE_SIZE != 0:
		return false
	if area.end.y != size.y and area.end.y % TILE_SIZE != 0:
		return false
	return true


func rebuild(max_tiles: int, max_work: int = 16384) -> Dictionary:
	if _capacity == 0:
		return _failure("not_configured")
	if max_tiles < 1 or max_work < 1 or max_work > MAX_WORK:
		return _failure("work_budget")
	var completed: int = 0
	var used: int = 0
	while completed < max_tiles and used < max_work:
		if _build_tile == -1:
			if _queue_cursor >= _queue.size():
				break
			_begin_next()
			used += 1
			continue
		if _build_phase == 2:
			_publish()
			completed += 1
			used += 1
			continue
		_step_receiver()
		used += 1
	_compact_queue()
	return {"ok": true, "completed": completed, "work": used, "pending_tiles": _pending_tiles(), "revision": _revision}


func diagnostics() -> Dictionary:
	var kernel_values: int = 0
	for table: PackedInt32Array in _kernels.values():
		kernel_values += table.size()
	return {"source_count": _source_count, "capacity": _capacity, "cached_tiles": _tiles.size(), "pending_tiles": _pending_tiles(), "max_radius": _max_radius, "kernel_values": kernel_values, "revision": _revision}


func _begin_next() -> void:
	_build_tile = _queue[_queue_cursor]
	_queue_cursor += 1
	var tile: Dictionary = _tiles[_build_tile]
	tile.queued = false
	_build_rect = _rect_for_tile(_build_tile)
	_build_values = PackedInt32Array()
	_build_values.resize(_build_rect.size.x * _build_rect.size.y * CHANNELS)
	_build_phase = 0 if _max_radius > 0 else 2
	if _max_radius > 0:
		_ensure_ordered_offsets()
		# Keep the active draft's original ordered geometry even if a candidate
		# publication changes the global maximum radius before it completes.
		_build_offsets = _ordered_offsets
		_build_weights = _ordered_weights
	_receiver_index = 0
	_receiver_x = _build_rect.position.x
	_receiver_y = _build_rect.position.y
	_receiver_channel = 0
	_receiver_best = 0
	_neighbor_index = 0
	_neighbor_slot = UNSET


func _step_receiver() -> void:
	if _neighbor_slot == UNSET:
		if _neighbor_index >= _build_offsets.size():
			_finish_channel()
			return
		# All subsequent offsets have at least this Euclidean distance. The
		# draft's original maximum radius bounds every original source, and
		# _max_source stays conservative after a removal. A source published
		# later has no influence on this preserved, unaffected tile.
		# Rounding is monotone, so this is a safe *inclusive* upper bound.
		# Equality may stop: this cache promises values, not winning IDs.
		@warning_ignore("integer_division")
		var upper: int = (_max_source[_receiver_channel] * _build_weights[_neighbor_index] + Rules.SCALE / 2) / Rules.SCALE
		if upper <= _receiver_best:
			_finish_channel()
			return
		var code: int = _build_offsets[_neighbor_index]
		_neighbor_dx = (code & 511) - 255
		_neighbor_dy = (code >> 9) - 255
		var x: int = _receiver_x + _neighbor_dx
		var y: int = _receiver_y + _neighbor_dy
		if x < 0 or y < 0 or x >= _size.x or y >= _size.y:
			_neighbor_index += 1
			return
		_neighbor_slot = _heads[y * _size.x + x]
		if _neighbor_slot == -1:
			_neighbor_slot = UNSET
			_neighbor_index += 1
			return
	# Exactly one linked source is consumed per work unit. Other sources at
	# this coordinate, including equal values, remain in the pending chain.
	var radius: int = _slot_radius[_neighbor_slot]
	var dx: int = absi(_neighbor_dx)
	var dy: int = absi(_neighbor_dy)
	var strength: int = _slot_channels[_neighbor_slot * CHANNELS + _receiver_channel]
	if strength > _receiver_best and dx < radius and dy < radius:
		var table: PackedInt32Array = _kernels[radius]
		var weight: int = table[dy * radius + dx]
		@warning_ignore("integer_division")
		var value: int = (strength * weight + Rules.SCALE / 2) / Rules.SCALE
		_receiver_best = maxi(_receiver_best, value)
	_neighbor_slot = _slot_next[_neighbor_slot]
	if _neighbor_slot == -1:
		_neighbor_slot = UNSET
		_neighbor_index += 1


func _finish_channel() -> void:
	_build_values[_receiver_index * CHANNELS + _receiver_channel] = _receiver_best
	_receiver_channel += 1
	_receiver_best = 0
	_neighbor_index = 0
	_neighbor_slot = UNSET
	if _receiver_channel < CHANNELS:
		return
	_receiver_channel = 0
	_receiver_index += 1
	if _receiver_index >= _build_rect.size.x * _build_rect.size.y:
		_build_phase = 2
		return
	_receiver_x += 1
	if _receiver_x >= _build_rect.end.x:
		_receiver_x = _build_rect.position.x
		_receiver_y += 1


func _publish() -> void:
	var tile: Dictionary = _tiles[_build_tile]
	tile.values = _build_values
	tile.dirty = false
	_build_values = PackedInt32Array()
	_build_offsets = PackedInt32Array()
	_build_weights = PackedInt32Array()
	_build_tile = -1


func _abort_build() -> void:
	if _build_tile < 0:
		return
	var tile: Dictionary = _tiles[_build_tile]
	if not bool(tile.queued):
		tile.queued = true
		_queue.append(_build_tile)
	_build_values = PackedInt32Array()
	_build_offsets = PackedInt32Array()
	_build_weights = PackedInt32Array()
	_build_tile = -1


func _mark_dirty(area: Rect2i) -> void:
	if area.size.x <= 0 or area.size.y <= 0:
		return
	@warning_ignore("integer_division")
	var min_x: int = area.position.x / TILE_SIZE
	@warning_ignore("integer_division")
	var min_y: int = area.position.y / TILE_SIZE
	@warning_ignore("integer_division")
	var max_x: int = (area.end.x - 1) / TILE_SIZE
	@warning_ignore("integer_division")
	var max_y: int = (area.end.y - 1) / TILE_SIZE
	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			var tile_id: int = y * _tile_columns + x
			if not _tiles.has(tile_id):
				continue
			var tile: Dictionary = _tiles[tile_id]
			tile.dirty = true
			if not bool(tile.queued):
				tile.queued = true
				_queue.append(tile_id)


func _compact_queue() -> void:
	if _queue_cursor == _queue.size():
		_queue.clear()
		_queue_cursor = 0
	elif _queue_cursor >= 1024 and _queue_cursor * 2 >= _queue.size():
		var remaining: Array[int] = []
		for index: int in range(_queue_cursor, _queue.size()):
			remaining.append(_queue[index])
		_queue = remaining
		_queue_cursor = 0


func _pending_tiles() -> int:
	return _queue.size() - _queue_cursor + (1 if _build_tile >= 0 else 0)


func _unlink(slot: int, cell: Vector2i) -> void:
	var head_index: int = _linear(cell)
	var current: int = _heads[head_index]
	var previous: int = -1
	while current != -1:
		if current == slot:
			_cell_source_counts[head_index] -= 1
			if previous == -1:
				_heads[head_index] = _slot_next[current]
			else:
				_slot_next[previous] = _slot_next[current]
			return
		previous = current
		current = _slot_next[current]


func _ensure_kernel(radius: int) -> void:
	if _kernels.has(radius):
		return
	_kernels[radius] = _make_kernel(radius)


static func _make_kernel(radius: int) -> PackedInt32Array:
	var table := PackedInt32Array()
	table.resize(radius * radius)
	for y: int in radius:
		for x: int in radius:
			table[y * radius + x] = int(Rules.kernel(Vector2i(x, y), radius).weight)
	return table


func _ensure_ordered_offsets() -> void:
	if _ordered_radius == _max_radius:
		return
	# Sort by squared Euclidean distance, then by encoded coordinates. Every
	# component lies in [-255, 255] because MAX_RADIUS is 256. The 18 low
	# bits encode the two biased coordinates; higher bits hold distance².
	# This one-time per-radius preparation is synchronous, not max_work-bound.
	var radius: int = _max_radius
	var table: PackedInt32Array = _kernels[radius]
	var ordered := PackedInt64Array()
	for dy: int in range(1 - radius, radius):
		for dx: int in range(1 - radius, radius):
			if table[absi(dy) * radius + absi(dx)] == 0:
				continue
			var code: int = ((dy + 255) << 9) | (dx + 255)
			ordered.append(((dx * dx + dy * dy) << 18) | code)
	ordered.sort()
	var offsets := PackedInt32Array()
	var weights := PackedInt32Array()
	offsets.resize(ordered.size())
	weights.resize(ordered.size())
	for index: int in ordered.size():
		var code: int = ordered[index] & 262143
		var dx: int = (code & 511) - 255
		var dy: int = (code >> 9) - 255
		offsets[index] = code
		weights[index] = table[absi(dy) * radius + absi(dx)]
	_ordered_offsets = offsets
	_ordered_weights = weights
	_ordered_radius = radius


func _trim_max_radius() -> void:
	while _max_radius > 0 and _radius_counts[_max_radius] == 0:
		_max_radius -= 1


func _coverage(cell: Vector2i, radius: int) -> Rect2i:
	if radius <= 0:
		return Rect2i()
	var distance: int = radius - 1
	return Rect2i(cell - Vector2i(distance, distance), Vector2i(distance * 2 + 1, distance * 2 + 1)).intersection(Rect2i(Vector2i.ZERO, _size))


func _rect_for_tile(tile_id: int) -> Rect2i:
	var tile_x: int = tile_id % _tile_columns
	@warning_ignore("integer_division")
	var tile_y: int = tile_id / _tile_columns
	var position := Vector2i(tile_x * TILE_SIZE, tile_y * TILE_SIZE)
	return Rect2i(position, Vector2i(mini(TILE_SIZE, _size.x - position.x), mini(TILE_SIZE, _size.y - position.y)))


func _tile_for_cell(cell: Vector2i) -> int:
	@warning_ignore("integer_division")
	var tile_x: int = cell.x / TILE_SIZE
	@warning_ignore("integer_division")
	var tile_y: int = cell.y / TILE_SIZE
	return tile_y * _tile_columns + tile_x


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _size.x and cell.y < _size.y


func _linear(cell: Vector2i) -> int:
	return cell.y * _size.x + cell.x


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


class SourceChangeHandle:
	extends RefCounted


class SourceChangeProof:
	extends RefCounted


class SourceCandidate:
	extends RefCounted
	var handle: SourceChangeHandle
	var proof: SourceChangeProof
	var revision: int = 0
	var slot: int = -1
	var old_cell := Vector2i.ZERO
	var old_radius: int = 0
	var new_cell := Vector2i.ZERO
	var new_radius: int = 0
	var new_channels := PackedInt32Array()
	var new_kernel := PackedInt32Array()
	var old_area := Rect2i()
	var new_area := Rect2i()
	var tile_ids: Array[int] = []
	var tile_set: Dictionary[int, bool] = {}
	var results: Dictionary = {}
	var offsets := PackedInt32Array()
	var weights := PackedInt32Array()
	var tile_index: int = 0
	var building: bool = false
	var sealed: bool = false
	var rect := Rect2i()
	var values := PackedInt32Array()
	var receiver_index: int = 0
	var receiver_x: int = 0
	var receiver_y: int = 0
	var channel: int = 0
	var phase: int = 0
	var best: int = 0
	var offset_index: int = 0
	var neighbor_slot: int = -2
	var dx: int = 0
	var dy: int = 0
