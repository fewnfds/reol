class_name SimEnvironmentGroundField
extends "res://scripts/sim/environment_field_cache.gd"
## The ground field owns the same inherited source slots, spatial index,
## candidate and revision as the base cache. The small auxiliary structures
## count *distinct* nonzero grades per channel; they are derived bounds only.
## This does not hold object identities, source positions or field values.
##
## A candidate scans the old live index excluding its replaced slot, and adds
## the candidate source separately. Its stop bound therefore must also exclude
## that old slot. In particular a unique extreme grade cannot force a full
## radius scan after it has already been logically removed from the candidate.

const SOURCE_LIST_LIMIT: int = 64

var _grade_bounds: Array[GradeBounds] = []
var _candidate_bounds := PackedInt32Array()
# Exact grade counts for source-anchor blocks, derived from the SAME slots.
# A receiver tile needs only blocks in its maximum-radius neighborhood. A
# distant extreme then cannot inflate that tile's search stopping bound.
var _block_bounds: Dictionary[int, BlockBounds] = {}
var _build_bounds := PackedInt32Array()
var _bounds_rect := Rect2i()
var _bounds_x: int = 0
var _bounds_y: int = 0
var _build_sources := PackedInt32Array()
var _build_gathering: bool = false
var _build_gather_slot: int = -1
var _build_source_index: int = 0
var _build_source_direct: bool = false
# Disposable per-candidate participation metadata. A bit denotes an effect
# channel that can differ because of this source, not another copy of a source
# or world state. Clean old tiles permit exact per-cell change masks; a missing
# or dirty old tile continues through the full reconstruction path.
var _candidate_channel_mask: int = 0
var _candidate_fast_tile: int = -1
var _candidate_fast: bool = false
var _candidate_old_values := PackedInt32Array()
var _candidate_change_masks: Dictionary[int, PackedByteArray] = {}
var _candidate_weight_index: int = -1
var _candidate_old_weight: int = 0
var _candidate_new_weight: int = 0
var _candidate_cold_pending: bool = false
var _candidate_cold_only: bool = false
var _candidate_cold_blocks := Rect2i()
var _candidate_cold_x: int = 0
var _candidate_cold_y: int = 0
var _transport: Callable
var _transport_capture: Callable
var _transport_pair: Callable
var _transport_receiver := Vector2i(-1, -1)
var _transport_sources: Dictionary[Vector2i, PackedInt32Array] = {}
var _compute_backend: WeakRef
var _compute_attempted: bool = false
var _compute_ticket: int = 0
var _compute_tiles: Dictionary[int, PackedInt32Array] = {}
var _compute_cell: int = 0


func set_transport(callback: Callable, capture: Callable = Callable(), pair: Callable = Callable()) -> void:
	_transport = callback
	_transport_capture = capture
	_transport_pair = pair


func invalidate_geometry(area: Rect2i) -> void:
	_transport_receiver = Vector2i(-1, -1)
	_transport_sources.clear()
	_abort_build()
	_revision += 1
	_mark_dirty(area.intersection(Rect2i(Vector2i.ZERO, _size)))


func _transport_grade(value: int, from: Vector2i, to: Vector2i, channel: int) -> int:
	if value == 0 or not _transport.is_valid():
		return value
	# The receiver scans several effect channels over the same nearby anchors.
	# Reuse geometry across those channels and old/new candidates, not sources
	# or field values. Scope is one receiver (at most the radius neighborhood).
	if to != _transport_receiver:
		_transport_receiver = to
		_transport_sources.clear()
	if not _transport_sources.has(from):
		_transport_sources[from] = PackedInt32Array([-1, -1])
	var factors: PackedInt32Array = _transport_sources[from]
	var kind: int = 1 if channel >= 5 else 0
	if factors[kind] < 0:
		if _transport_pair.is_valid():
			var pair: Vector2i = _transport_pair.call(from, to)
			factors[0] = clampi(pair.y, 0, 10000)
			factors[1] = clampi(pair.x, 0, 10000)
		else:
			factors[kind] = clampi(int(_transport.call(from, to, channel)), 0, 10000)
		_transport_sources[from] = factors
	return (value * factors[kind] + 5000) / 10000


func export_compute_job(area: Rect2i, compact: bool = false) -> Dictionary:
	return _with_geometry(super.export_compute_job(area, compact), area, _max_radius)


func export_source_compute_job(handle: Variant) -> Dictionary:
	var job: Dictionary = super.export_source_compute_job(handle)
	return _with_geometry(job, job.get("area", Rect2i()), maxi(_max_radius, _source_candidate.new_radius) if _source_candidate != null else _max_radius)


func _with_geometry(job: Dictionary, area: Rect2i, radius: int) -> Dictionary:
	if _transport.is_valid() and not _transport_capture.is_valid():
		return {"ok": false, "reason": "geometry_requires_cpu"}
	if not bool(job.get("ok", false)) or not _transport.is_valid() or job.has("geometry"):
		return job
	var region: Rect2i = area.grow(maxi(0, radius - 1)).intersection(Rect2i(Vector2i.ZERO, _size))
	var captured: Dictionary = _transport_capture.call(region)
	if not bool(captured.get("ok", false)) or not captured.get("geometry") is PackedInt32Array:
		return {"ok": false, "reason": "geometry_capture"}
	var geometry: PackedInt32Array = captured.geometry
	if geometry.size() != 6 + region.get_area() or geometry[0] != 1 or geometry[1] != region.position.x or geometry[2] != region.position.y or geometry[3] != region.size.x or geometry[4] != region.size.y:
		return {"ok": false, "reason": "geometry_layout"}
	# Compact source jobs use local coordinates. Move only the geometry header;
	# world publication still validates the original area/owner/revision.
	geometry = geometry.duplicate()
	var compute: PackedInt32Array = job.compute_params
	geometry[1] -= area.position.x - compute[4]
	geometry[2] -= area.position.y - compute[5]
	job.geometry = geometry
	return job


func set_compute_backend(backend: RefCounted) -> void:
	_compute_backend = weakref(backend) if backend != null else null


func step_source_change(handle: Variant, max_work: int) -> Dictionary:
	if not _source_handle_matches(handle) or _source_candidate.revision != _revision or _source_candidate.sealed or max_work < 0 or max_work > MAX_WORK:
		return super.step_source_change(handle, max_work)
	var backend: RefCounted = _compute_backend.get_ref() if _compute_backend != null else null
	if _source_candidate.allow_compute and not _compute_attempted and backend != null and max_work > 0:
		_compute_attempted = true
		var started: Dictionary = backend.request_source_candidate(handle)
		if bool(started.get("ok", false)):
			_compute_ticket = int(started.ticket)
	if _compute_ticket != 0:
		var result: Dictionary = backend.poll() if backend != null else {"ok": false}
		if bool(result.get("pending", false)):
			return {"ok": true, "done": false, "work": 0, "waiting": true}
		_compute_ticket = 0
		if bool(result.get("ok", false)) and not bool(result.get("cancelled", false)):
			var job: Dictionary = result.job
			var prepared: Dictionary = result.prepared
			if int(job.owner_token) == get_instance_id() and int(job.revision) == _revision and int(job.candidate_token) == handle.get_instance_id() and int(prepared.owner_token) == get_instance_id() and int(prepared.revision) == _revision:
				var entries: Dictionary[int, PackedInt32Array] = {}
				for entry: Dictionary in prepared.tiles:
					entries[int(entry.id)] = entry.values
				var valid: bool = true
				for id: int in _source_candidate.tile_ids:
					var old: Dictionary = _tiles.get(id, {})
					if not entries.has(id) or old.is_empty() or bool(old.dirty) or entries[id].size() != old.values.size():
						valid = false
						break
				if valid:
					_compute_tiles = entries
	if _compute_tiles.is_empty():
		return super.step_source_change(handle, max_work)
	# Build exact changed-channel masks with the original bounded work budget.
	# Nothing is published until field + response proofs commit together.
	var candidate: SourceCandidate = _source_candidate
	var used: int = 0
	while used < max_work and candidate.tile_index < candidate.tile_ids.size():
		var id: int = candidate.tile_ids[candidate.tile_index]
		var values: PackedInt32Array = _compute_tiles[id]
		var old: PackedInt32Array = _tiles[id].values
		if _compute_cell == 0:
			var masks := PackedByteArray()
			masks.resize(values.size() / CHANNELS)
			_candidate_change_masks[id] = masks
		var mask: int = 0
		for channel: int in CHANNELS:
			var index: int = _compute_cell * CHANNELS + channel
			if values[index] != old[index]:
				mask |= 1 << channel
		_candidate_change_masks[id][_compute_cell] = mask
		_compute_cell += 1
		used += 1
		if _compute_cell * CHANNELS == values.size():
			candidate.results[id] = values
			candidate.tile_index += 1
			_compute_cell = 0
	return {"ok": true, "work": used, "done": candidate.tile_index == candidate.tile_ids.size()}


func cancel_source_change(handle: Variant) -> Dictionary:
	if _source_handle_matches(handle) and _compute_ticket != 0:
		var backend: RefCounted = _compute_backend.get_ref() if _compute_backend != null else null
		if backend != null:
			backend.cancel(_compute_ticket)
		_compute_ticket = 0
	return super.cancel_source_change(handle)


func _init() -> void:
	for _channel: int in CHANNELS:
		_grade_bounds.append(GradeBounds.new())
	_candidate_bounds.resize(CHANNELS)


func set_source(slot: int, cell: Vector2i, radius: int, channels: Variant) -> Dictionary:
	var old := _slot_grades(slot)
	var old_cell := Vector2i(_slot_x[slot], _slot_y[slot]) if not old.is_empty() else cell
	var result: Dictionary = super.set_source(slot, cell, radius, channels)
	if bool(result.get("ok", false)) and bool(result.get("changed", false)):
		var current := _slot_grades(slot)
		_replace_grades(old, current)
		_replace_block_grades(old_cell, old, cell, current)
	return result


func remove_source(slot: int) -> Dictionary:
	var old := _slot_grades(slot)
	var old_cell := Vector2i(_slot_x[slot], _slot_y[slot]) if not old.is_empty() else Vector2i.ZERO
	var result: Dictionary = super.remove_source(slot)
	if bool(result.get("ok", false)):
		_replace_grades(old, PackedInt32Array())
		_replace_block_grades(old_cell, old, Vector2i.ZERO, PackedInt32Array())
	return result


func begin_source_change(slot: int, operation: String, change: Dictionary = {}) -> Dictionary:
	var result: Dictionary = super.begin_source_change(slot, operation, change)
	if bool(result.get("ok", false)):
		_compute_attempted = false
		_compute_ticket = 0
		_compute_tiles.clear()
		_compute_cell = 0
		var old := _slot_grades(slot)
		_candidate_channel_mask = 0
		_candidate_fast_tile = -1
		_candidate_fast = false
		_candidate_old_values = PackedInt32Array()
		_candidate_change_masks.clear()
		_candidate_weight_index = -1
		_candidate_cold_pending = false
		_candidate_cold_only = false
		for channel: int in CHANNELS:
			_candidate_bounds[channel] = _grade_bounds[channel].maximum_without(old[channel] if not old.is_empty() else 0)
			var before: int = old[channel] if not old.is_empty() else 0
			var after: int = _source_candidate.new_channels[channel] if _source_candidate.new_radius > 0 else 0
			if before != 0 or after != 0:
				_candidate_channel_mask |= 1 << channel
	return result


func candidate_tile_copy(proof: Variant, tile_id: int) -> Dictionary:
	var result: Dictionary = super.candidate_tile_copy(proof, tile_id)
	if bool(result.get("ok", false)) and _candidate_change_masks.has(tile_id):
		# The returned mask is detached: callers cannot alter the candidate.
		result["change_mask"] = _candidate_change_masks[tile_id].duplicate()
	return result


func has_candidate_change_masks() -> bool:
	return true


func _apply_source_candidate(candidate: SourceCandidate) -> void:
	var old := _slot_grades(candidate.slot)
	super._apply_source_candidate(candidate)
	var current := _slot_grades(candidate.slot)
	_replace_grades(old, current)
	_replace_block_grades(candidate.old_cell, old, candidate.new_cell, current)
	if not _compute_tiles.is_empty():
		var backend: RefCounted = _compute_backend.get_ref() if _compute_backend != null else null
		if backend != null:
			backend.note_source_adoption()
	_compute_tiles.clear()


func _replace_block_grades(old_cell: Vector2i, old: PackedInt32Array, cell: Vector2i, current: PackedInt32Array) -> void:
	var old_id: int = _tile_for_cell(old_cell)
	var id: int = _tile_for_cell(cell)
	if not current.is_empty() and not _block_bounds.has(id):
		_block_bounds[id] = BlockBounds.new()
	if not old.is_empty():
		_block_bounds[old_id].sources -= 1
	if not current.is_empty():
		_block_bounds[id].sources += 1
	for channel: int in CHANNELS:
		var before: int = old[channel] if not old.is_empty() else 0
		var after: int = current[channel] if not current.is_empty() else 0
		if old_id == id and before == after:
			continue
		if before > 0:
			_block_bounds[old_id].channels[channel].remove(before)
		if after > 0:
			_block_bounds[id].channels[channel].add(after)
	if not old.is_empty() and _block_bounds[old_id].sources == 0:
		_block_bounds.erase(old_id)


func _begin_next() -> void:
	super._begin_next()
	_build_sources = PackedInt32Array()
	_build_source_index = 0
	_build_gather_slot = -1
	_build_source_direct = false
	_build_gathering = false
	if _build_phase == 2:
		return
	var area: Rect2i = _build_rect.grow(_max_radius - 1).intersection(Rect2i(Vector2i.ZERO, _size))
	_build_bounds = PackedInt32Array()
	_build_bounds.resize(CHANNELS)
	# Share the local source list over the whole receiver tile. Gathering one
	# cell/link per work unit keeps cold geometry rebuilds resumable.
	_bounds_rect = area
	_bounds_x = area.position.x
	_bounds_y = area.position.y
	_build_gathering = true
	_build_phase = 3


func _step_receiver() -> void:
	if _build_phase == 3:
		if _build_gathering:
			_gather_build_source()
			return
		var block: BlockBounds = _block_bounds.get(_bounds_y * _tile_columns + _bounds_x)
		if block != null:
			for channel: int in CHANNELS:
				_build_bounds[channel] = maxi(_build_bounds[channel], block.channels[channel].maximum_without(0))
		_bounds_x += 1
		if _bounds_x >= _bounds_rect.end.x:
			_bounds_x = _bounds_rect.position.x
			_bounds_y += 1
			if _bounds_y >= _bounds_rect.end.y:
				_build_phase = 0
		return
	if _build_source_direct:
		_step_listed_receiver()
		return
	# Same ordered offsets, source chain, rounding and work accounting as the
	# base cache. Only the conservative strength bound is now spatially local.
	# Candidate commits preserve a draft only outside old/new source coverage;
	# a previously gathered bound remains safe there, including during phase 3.
	if _neighbor_slot == UNSET:
		if _neighbor_index >= _build_offsets.size():
			_finish_channel()
			return
		@warning_ignore("integer_division")
		var upper: int = (_build_bounds[_receiver_channel] * _build_weights[_neighbor_index] + Rules.SCALE / 2) / Rules.SCALE
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
	var radius: int = _slot_radius[_neighbor_slot]
	var dx: int = absi(_neighbor_dx)
	var dy: int = absi(_neighbor_dy)
	var strength: int = _slot_channels[_neighbor_slot * CHANNELS + _receiver_channel]
	if strength > _receiver_best and dx < radius and dy < radius:
		var table: PackedInt32Array = _kernels[radius]
		@warning_ignore("integer_division")
		var value: int = (strength * table[dy * radius + dx] + Rules.SCALE / 2) / Rules.SCALE
		value = _transport_grade(value, Vector2i(_slot_x[_neighbor_slot], _slot_y[_neighbor_slot]), Vector2i(_receiver_x, _receiver_y), _receiver_channel)
		_receiver_best = maxi(_receiver_best, value)
	_neighbor_slot = _slot_next[_neighbor_slot]
	if _neighbor_slot == -1:
		_neighbor_slot = UNSET
		_neighbor_index += 1


func _gather_build_source() -> void:
	if _build_gather_slot >= 0:
		var slot: int = _build_gather_slot
		_build_sources.append(slot)
		_build_gather_slot = _slot_next[slot]
		if _build_sources.size() > SOURCE_LIST_LIMIT:
			# Dense source windows keep the original distance-ordered search and
			# block bound. Do not finish scanning a huge list merely to discard it.
			var first := Vector2i(_bounds_rect.position.x >> 4, _bounds_rect.position.y >> 4)
			var last := Vector2i((_bounds_rect.end.x - 1) >> 4, (_bounds_rect.end.y - 1) >> 4)
			_bounds_rect = Rect2i(first, last - first + Vector2i.ONE)
			_bounds_x = first.x
			_bounds_y = first.y
			_build_gathering = false
			_build_sources.clear()
			return
		for channel: int in CHANNELS:
			_build_bounds[channel] = maxi(_build_bounds[channel], _slot_channels[slot * CHANNELS + channel])
		return
	if _bounds_y >= _bounds_rect.end.y:
		_build_source_direct = _build_sources.size() <= SOURCE_LIST_LIMIT
		_build_gathering = false
		_build_phase = 0
		return
	_build_gather_slot = _heads[_bounds_y * _size.x + _bounds_x]
	_bounds_x += 1
	if _bounds_x >= _bounds_rect.end.x:
		_bounds_x = _bounds_rect.position.x
		_bounds_y += 1


func _step_listed_receiver() -> void:
	if _build_source_index >= _build_sources.size():
		_build_source_index = 0
		_receiver_index += 1
		if _receiver_index >= _build_rect.size.x * _build_rect.size.y:
			_build_phase = 2
			return
		_receiver_x += 1
		if _receiver_x >= _build_rect.end.x:
			_receiver_x = _build_rect.position.x
			_receiver_y += 1
		return
	var slot: int = _build_sources[_build_source_index]
	_build_source_index += 1
	# An adopted source outside this tile may have removed/reused a gathered
	# slot. Its current footprint has no contribution here; read the live slot.
	var radius: int = _slot_radius[slot]
	var dx: int = absi(_receiver_x - _slot_x[slot])
	var dy: int = absi(_receiver_y - _slot_y[slot])
	if radius == 0 or dx >= radius or dy >= radius:
		return
	var table: PackedInt32Array = _kernels[radius]
	var weight: int = table[dy * radius + dx]
	var offset: int = _receiver_index * CHANNELS
	for channel: int in CHANNELS:
		var strength: int = _slot_channels[slot * CHANNELS + channel]
		if strength <= _build_values[offset + channel]:
			continue
		@warning_ignore("integer_division")
		var value: int = (strength * weight + Rules.SCALE / 2) / Rules.SCALE
		if value <= _build_values[offset + channel]:
			continue
		value = _transport_grade(value, Vector2i(_slot_x[slot], _slot_y[slot]), Vector2i(_receiver_x, _receiver_y), channel)
		_build_values[offset + channel] = maxi(_build_values[offset + channel], value)


class BlockBounds:
	extends RefCounted
	var sources: int = 0
	var channels: Array[GradeBounds] = []

	func _init() -> void:
		for _channel: int in CHANNELS:
			channels.append(GradeBounds.new())


func _slot_grades(slot: int) -> PackedInt32Array:
	if slot < 0 or slot >= _capacity or _slot_radius[slot] == 0:
		return PackedInt32Array()
	var values := PackedInt32Array()
	values.resize(CHANNELS)
	for channel: int in CHANNELS:
		values[channel] = _slot_channels[slot * CHANNELS + channel]
	return values


func _replace_grades(old: PackedInt32Array, current: PackedInt32Array) -> void:
	for channel: int in CHANNELS:
		var before: int = old[channel] if not old.is_empty() else 0
		var after: int = current[channel] if not current.is_empty() else 0
		if before == after:
			continue
		if before > 0:
			_grade_bounds[channel].remove(before)
		if after > 0:
			_grade_bounds[channel].add(after)
		# The base cache's ordinary rebuild can use the exact committed maximum
		# too. Direct writes abort drafts. A candidate commit only preserves a
		# draft outside both old/new coverage, where the changed source is zero;
		# lowering that draft's bound therefore remains conservative there.
		_max_source[channel] = _grade_bounds[channel].maximum_without(0)


func _step_source_candidate() -> void:
	# Same stepped receiver, distance weights, rounding and work accounting as
	# the base cache. Only the safe upper bound differs: it excludes exactly the
	# live slot that the candidate scan below deliberately skips.
	var candidate: SourceCandidate = _source_candidate
	var tile_id: int = candidate.tile_ids[candidate.tile_index]
	if tile_id != _candidate_fast_tile:
		_prepare_incremental_tile(tile_id, candidate)
	if _candidate_cold_pending:
		_step_cold_proof(tile_id, candidate)
		return
	if _candidate_fast and candidate.phase == 0:
		_step_incremental_candidate(candidate)
		return
	if candidate.phase == 0:
		candidate.best = 0
		if candidate.new_radius > 0:
			var dx: int = absi(candidate.receiver_x - candidate.new_cell.x)
			var dy: int = absi(candidate.receiver_y - candidate.new_cell.y)
			if dx < candidate.new_radius and dy < candidate.new_radius:
				var strength: int = candidate.new_channels[candidate.channel]
				var weight: int = candidate.new_kernel[dy * candidate.new_radius + dx]
				@warning_ignore("integer_division")
				candidate.best = (strength * weight + Rules.SCALE / 2) / Rules.SCALE
				candidate.best = _transport_grade(candidate.best, candidate.new_cell, Vector2i(candidate.receiver_x, candidate.receiver_y), candidate.channel)
		candidate.phase = 1
		return
	if candidate.neighbor_slot == UNSET:
		if candidate.offset_index >= candidate.offsets.size():
			_finish_source_candidate_channel()
			return
		@warning_ignore("integer_division")
		var upper: int = (_candidate_bounds[candidate.channel] * candidate.weights[candidate.offset_index] + Rules.SCALE / 2) / Rules.SCALE
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
		return
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
			value = _transport_grade(value, Vector2i(_slot_x[source_slot], _slot_y[source_slot]), Vector2i(candidate.receiver_x, candidate.receiver_y), candidate.channel)
			candidate.best = maxi(candidate.best, value)
	candidate.neighbor_slot = _slot_next[source_slot]
	if candidate.neighbor_slot == -1:
		candidate.neighbor_slot = UNSET
		candidate.offset_index += 1


func _prepare_incremental_tile(tile_id: int, candidate: SourceCandidate) -> void:
	_candidate_fast_tile = tile_id
	_candidate_fast = false
	_candidate_weight_index = -1
	_candidate_cold_pending = false
	_candidate_cold_only = false
	_candidate_old_values = PackedInt32Array()
	var tile: Dictionary = _tiles.get(tile_id, {})
	if tile.is_empty() or bool(tile.get("dirty", true)):
		_begin_cold_proof(tile_id, candidate)
		return
	var previous: Variant = tile.get("values")
	if not previous is PackedInt32Array or previous.size() != candidate.values.size():
		return
	_candidate_old_values = previous
	candidate.values = _candidate_old_values.duplicate()
	var mask := PackedByteArray()
	mask.resize(candidate.rect.size.x * candidate.rect.size.y)
	_candidate_change_masks[tile_id] = mask
	_candidate_fast = true


func _begin_cold_proof(tile_id: int, candidate: SourceCandidate) -> void:
	# An anchor farther than the largest live radius cannot affect this block.
	# The existing block index only counts sources, so the test is deliberately
	# conservative: any other anchor in the covering blocks triggers the full
	# reconstruction rather than assuming that its influence is zero.
	if _source_count == 0:
		_initialize_cold_tile(tile_id, candidate)
		return
	var area: Rect2i = candidate.rect.grow(maxi(0, _max_radius - 1)).intersection(Rect2i(Vector2i.ZERO, _size))
	var first := Vector2i(area.position.x >> 4, area.position.y >> 4)
	var last := Vector2i((area.end.x - 1) >> 4, (area.end.y - 1) >> 4)
	_candidate_cold_blocks = Rect2i(first, last - first + Vector2i.ONE)
	_candidate_cold_x = first.x
	_candidate_cold_y = first.y
	_candidate_cold_pending = true


func _step_cold_proof(tile_id: int, candidate: SourceCandidate) -> void:
	# One block per work unit preserves the existing resumable budget. The
	# replaced slot may be present, but no other nearby source is assumed away.
	var block_id: int = _candidate_cold_y * _tile_columns + _candidate_cold_x
	var block: BlockBounds = _block_bounds.get(block_id)
	var excluded: int = 1 if candidate.old_radius > 0 and _tile_for_cell(candidate.old_cell) == block_id else 0
	if block != null and block.sources > excluded:
		_candidate_cold_pending = false
		return
	_candidate_cold_x += 1
	if _candidate_cold_x >= _candidate_cold_blocks.end.x:
		_candidate_cold_x = _candidate_cold_blocks.position.x
		_candidate_cold_y += 1
		if _candidate_cold_y >= _candidate_cold_blocks.end.y:
			_candidate_cold_pending = false
			_initialize_cold_tile(tile_id, candidate)


func _initialize_cold_tile(tile_id: int, candidate: SourceCandidate) -> void:
	# The proof means the old field is exactly the old slot's own contribution,
	# or zero when it is a new slot. Fill that old contribution per receiver in
	# the regular bounded step, rather than scanning the whole tile up front.
	_candidate_old_values = PackedInt32Array()
	_candidate_old_values.resize(candidate.values.size())
	candidate.values.fill(0)
	var mask := PackedByteArray()
	mask.resize(candidate.rect.size.x * candidate.rect.size.y)
	_candidate_change_masks[tile_id] = mask
	_candidate_cold_only = true
	_candidate_fast = true


func _step_incremental_candidate(candidate: SourceCandidate) -> void:
	# A clean tile is a complete, revision-checked snapshot of the old max.
	# Only the changed source's old/new weighted contributions can alter it.
	if _candidate_weight_index != candidate.receiver_index:
		_candidate_weight_index = candidate.receiver_index
		_candidate_old_weight = _candidate_weight(candidate.receiver_x, candidate.receiver_y, candidate.old_cell, candidate.old_radius, _kernels.get(candidate.old_radius, PackedInt32Array()))
		_candidate_new_weight = _candidate_weight(candidate.receiver_x, candidate.receiver_y, candidate.new_cell, candidate.new_radius, candidate.new_kernel)
		if _candidate_cold_only and _candidate_old_weight > 0 and candidate.old_radius > 0:
			for channel: int in CHANNELS:
				var strength: int = _slot_channels[candidate.slot * CHANNELS + channel]
				if strength == 0:
					continue
				@warning_ignore("integer_division")
				var value: int = (strength * _candidate_old_weight + Rules.SCALE / 2) / Rules.SCALE
				value = _transport_grade(value, candidate.old_cell, Vector2i(candidate.receiver_x, candidate.receiver_y), channel)
				var offset: int = candidate.receiver_index * CHANNELS + channel
				_candidate_old_values[offset] = value
				candidate.values[offset] = value
	var before: int = 0
	var after: int = 0
	while candidate.channel < CHANNELS:
		if (_candidate_channel_mask & (1 << candidate.channel)) != 0:
			var old_grade: int = _slot_channels[candidate.slot * CHANNELS + candidate.channel] if candidate.old_radius > 0 else 0
			var new_grade: int = candidate.new_channels[candidate.channel] if candidate.new_radius > 0 else 0
			@warning_ignore("integer_division")
			before = (old_grade * _candidate_old_weight + Rules.SCALE / 2) / Rules.SCALE
			@warning_ignore("integer_division")
			after = (new_grade * _candidate_new_weight + Rules.SCALE / 2) / Rules.SCALE
			before = _transport_grade(before, candidate.old_cell, Vector2i(candidate.receiver_x, candidate.receiver_y), candidate.channel)
			after = _transport_grade(after, candidate.new_cell, Vector2i(candidate.receiver_x, candidate.receiver_y), candidate.channel)
			if before != after:
				break
		candidate.channel += 1
	if candidate.channel >= CHANNELS:
		# One bounded operation advances one receiver even when none of the
		# source's optional channels contribute at that receiver.
		candidate.channel = CHANNELS - 1
		candidate.best = _candidate_old_values[candidate.receiver_index * CHANNELS + candidate.channel]
		_finish_source_candidate_channel()
		return
	var previous: int = _candidate_old_values[candidate.receiver_index * CHANNELS + candidate.channel]
	if _candidate_cold_only:
		candidate.best = after
		_finish_source_candidate_channel()
		return
	# If another source already wins, the old contribution may be discarded.
	# When the removed contribution was a winner and the replacement is lower,
	# resume the normal exclusion scan so ties and the next winner are exact.
	if before < previous or after >= previous:
		candidate.best = maxi(previous, after)
		_finish_source_candidate_channel()
		return
	candidate.best = after
	candidate.phase = 1


func _finish_source_candidate_channel() -> void:
	if _candidate_fast:
		var candidate: SourceCandidate = _source_candidate
		var offset: int = candidate.receiver_index * CHANNELS + candidate.channel
		if candidate.best != _candidate_old_values[offset]:
			var mask: PackedByteArray = _candidate_change_masks[_candidate_fast_tile]
			mask[candidate.receiver_index] |= 1 << candidate.channel
			_candidate_change_masks[_candidate_fast_tile] = mask
	super._finish_source_candidate_channel()


static func _candidate_weight(x: int, y: int, cell: Vector2i, radius: int, kernel: PackedInt32Array) -> int:
	if radius <= 0:
		return 0
	var dx: int = absi(x - cell.x)
	var dy: int = absi(y - cell.y)
	if dx >= radius or dy >= radius:
		return 0
	return kernel[dy * radius + dx]


class GradeBounds:
	extends RefCounted
	## An indexed maximum heap has one entry per distinct nonzero grade. Counts
	## preserve ties, and deleting the last source removes its heap entry rather
	## than retaining unbounded stale entries through repeated movement.
	var heap: Array[int] = []
	var counts: Dictionary[int, int] = {}
	var indices: Dictionary[int, int] = {}

	func add(grade: int) -> void:
		if counts.has(grade):
			counts[grade] += 1
			return
		counts[grade] = 1
		indices[grade] = heap.size()
		heap.append(grade)
		_sift_up(heap.size() - 1)

	func remove(grade: int) -> void:
		assert(counts.has(grade), "grade index must match committed sources")
		var count: int = counts[grade] - 1
		if count > 0:
			counts[grade] = count
			return
		counts.erase(grade)
		var position: int = indices[grade]
		indices.erase(grade)
		var last: int = heap.pop_back()
		if position == heap.size():
			return
		heap[position] = last
		indices[last] = position
		if position > 0 and heap[position] > heap[(position - 1) >> 1]:
			_sift_up(position)
		else:
			_sift_down(position)

	func maximum_without(grade: int) -> int:
		if heap.is_empty():
			return 0
		var highest: int = heap[0]
		if grade != highest or counts[highest] > 1:
			return highest
		var second: int = 0
		if heap.size() > 1:
			second = heap[1]
		if heap.size() > 2:
			second = maxi(second, heap[2])
		return second

	func _sift_up(start: int) -> void:
		var index: int = start
		while index > 0:
			var parent: int = (index - 1) >> 1
			if heap[parent] >= heap[index]:
				break
			_swap(parent, index)
			index = parent

	func _sift_down(start: int) -> void:
		var index: int = start
		while index * 2 + 1 < heap.size():
			var largest: int = index * 2 + 1
			if largest + 1 < heap.size() and heap[largest + 1] > heap[largest]:
				largest += 1
			if heap[index] >= heap[largest]:
				break
			_swap(index, largest)
			index = largest

	func _swap(a: int, b: int) -> void:
		var first: int = heap[a]
		var second: int = heap[b]
		heap[a] = second
		heap[b] = first
		indices[first] = b
		indices[second] = a
