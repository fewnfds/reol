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
		var old := _slot_grades(slot)
		for channel: int in CHANNELS:
			_candidate_bounds[channel] = _grade_bounds[channel].maximum_without(old[channel] if not old.is_empty() else 0)
	return result


func _apply_source_candidate(candidate: SourceCandidate) -> void:
	var old := _slot_grades(candidate.slot)
	super._apply_source_candidate(candidate)
	var current := _slot_grades(candidate.slot)
	_replace_grades(old, current)
	_replace_block_grades(candidate.old_cell, old, candidate.new_cell, current)


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
	if _build_phase == 2:
		return
	var area: Rect2i = _build_rect.grow(_max_radius - 1).intersection(Rect2i(Vector2i.ZERO, _size))
	var first := Vector2i(area.position.x >> 4, area.position.y >> 4)
	var last := Vector2i((area.end.x - 1) >> 4, (area.end.y - 1) >> 4)
	_bounds_rect = Rect2i(first, last - first + Vector2i.ONE)
	_bounds_x = first.x
	_bounds_y = first.y
	_build_bounds = PackedInt32Array()
	_build_bounds.resize(CHANNELS)
	# One source block per work unit, even at the largest supported radius.
	# The ordinary receiver loop starts only after the conservative bound is
	# complete. No partial tile values or bound become externally visible.
	_build_phase = 3


func _step_receiver() -> void:
	if _build_phase == 3:
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
		_receiver_best = maxi(_receiver_best, value)
	_neighbor_slot = _slot_next[_neighbor_slot]
	if _neighbor_slot == -1:
		_neighbor_slot = UNSET
		_neighbor_index += 1


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
			candidate.best = maxi(candidate.best, value)
	candidate.neighbor_slot = _slot_next[source_slot]
	if candidate.neighbor_slot == -1:
		candidate.neighbor_slot = UNSET
		candidate.offset_index += 1


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
