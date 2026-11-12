extends RefCounted
## Joint candidates must match rebuilding original slots, including ties,
## removed winners, co-located sources, cancellation and compact worker input.

static func run() -> bool:
	for cold: bool in [false, true]:
		var field := SimEnvironmentGroundField.new()
		var reference := SimEnvironmentGroundField.new()
		for cache: SimEnvironmentGroundField in [field, reference]:
			if not cache.configure(Vector2i(32, 32), 8): return false
			cache.set_source(0, Vector2i(15, 15), 3, PackedInt32Array([900, 0, 0, 0, 0, 700, 0]))
			cache.set_source(1, Vector2i(15, 15), 3, PackedInt32Array([900, 0, 0, 0, 0, 500, 0]))
			cache.set_source(2, Vector2i(17, 15), 3, PackedInt32Array([300, 0, 0, 0, 0, 400, 0]))
		if not cold and not _warm(field): return false
		var edits: Array[Dictionary] = [
			{"slot": 0, "operation": "remove", "source": {}},
			{"slot": 1, "operation": "set", "source": {"cell": Vector2i(17, 15), "radius": 3, "channels": PackedInt32Array([200, 0, 0, 0, 0, 100, 0])}},
			{"slot": 3, "operation": "set", "source": {"cell": Vector2i(17, 15), "radius": 3, "channels": PackedInt32Array([800, 0, 0, 0, 0, 600, 0])}}]
		var opened: Dictionary = field.begin_source_changes(edits)
		if not opened.ok: return false
		var computed: Dictionary = {}
		if not cold:
			var job: Dictionary = field.export_source_compute_job(opened.handle)
			var batch := SimFieldCompute.new()
			if not job.ok: return false
			batch.start(job, 2)
			batch.execution.finish(true)
			var result: Dictionary = batch.collect()
			if not result.ok: return false
			computed = result.prepared
		# Cancellation must leave original slots, maxima and clean tiles intact.
		field.step_source_change(opened.handle, 17)
		if not field.cancel_source_change(opened.handle).ok or field._slot_radius[0] != 3: return false
		opened = field.begin_source_changes(edits)
		var done: bool = false
		for step: int in 1000:
			var progress: Dictionary = field.step_source_change(opened.handle, 1000)
			if not progress.ok: return false
			if progress.done:
				done = true
				break
		if not done: return false
		var finished: Dictionary = field.finish_source_change(opened.handle)
		if not finished.ok: return false
		for tile: Dictionary in computed.get("tiles", []):
			if field.candidate_tile_copy(finished.proof, tile.id).channels != tile.values: return false
		if not field.commit_source_change(finished.proof).ok: return false
		for edit: Dictionary in edits:
			if edit.operation == "remove":
				reference.remove_source(edit.slot)
			else:
				reference.set_source(edit.slot, edit.source.cell, edit.source.radius, edit.source.channels)
		if not _warm(reference) or not _warm(field): return false
		for y: int in 32:
			for x: int in 32:
				if field.read_base(Vector2i(x, y)).channels != reference.read_base(Vector2i(x, y)).channels: return false
		if field._max_source != reference._max_source or field._source_count != reference._source_count: return false
	return _cold_only() and _paused_gather() and _sparse_move()


static func _warm(field: SimEnvironmentGroundField, area: Rect2i = Rect2i(0, 0, 32, 32)) -> bool:
	if not field.request_area(area).ok: return false
	for step: int in 1000:
		var progress: Dictionary = field.rebuild(4, 10000)
		if not progress.ok: return false
		if int(field.diagnostics().pending_tiles) == 0: return true
	return false


static func _commit(field: SimEnvironmentGroundField, handle: Variant) -> bool:
	for step: int in 1000:
		var result: Dictionary = field.step_source_change(handle, 1000)
		if not result.ok: return false
		if result.done:
			var finished: Dictionary = field.finish_source_change(handle)
			return finished.ok and field.commit_source_change(finished.proof).ok
	return false


static func _cold_only() -> bool:
	var field := SimEnvironmentGroundField.new()
	var reference := SimEnvironmentGroundField.new()
	for cache: SimEnvironmentGroundField in [field, reference]:
		if not cache.configure(Vector2i(32, 32), 8): return false
		cache.set_source(0, Vector2i(15, 15), 3, PackedInt32Array([900, 0, 0, 0, 0, 700, 0]))
		cache.set_source(1, Vector2i(17, 15), 3, PackedInt32Array([300, 0, 0, 0, 0, 400, 0]))
	# Every original source is replaced: cold tiles can prove exact old values
	# and masks without relying on any previously materialized tile.
	var edits: Array[Dictionary] = [
		{"slot": 0, "operation": "remove", "source": {}},
		{"slot": 1, "operation": "set", "source": {"cell": Vector2i(18, 15), "radius": 3, "channels": PackedInt32Array([200, 0, 0, 0, 0, 500, 0])}}]
	var opened: Dictionary = field.begin_source_changes(edits)
	if not opened.ok: return false
	for step: int in 1000:
		var progress: Dictionary = field.step_source_change(opened.handle, 1000)
		if not progress.ok: return false
		if not progress.done: continue
		var finished: Dictionary = field.finish_source_change(opened.handle)
		if not finished.ok: return false
		for id: int in opened.tile_ids:
			if not field.candidate_tile_copy(finished.proof, id).has("change_mask"): return false
		if not field.commit_source_change(finished.proof).ok: return false
		reference.remove_source(0)
		reference.set_source(1, edits[1].source.cell, 3, edits[1].source.channels)
		if not _warm(field) or not _warm(reference): return false
		for y: int in 32:
			for x: int in 32:
				if field.read_base(Vector2i(x, y)).channels != reference.read_base(Vector2i(x, y)).channels: return false
		return true
	return false


static func _paused_gather() -> bool:
	var field := SimEnvironmentGroundField.new()
	var reference := SimEnvironmentGroundField.new()
	for cache: SimEnvironmentGroundField in [field, reference]:
		if not cache.configure(Vector2i(32, 32), 8): return false
		cache.set_source(1, Vector2i(20, 20), 10, PackedInt32Array([1000, 0, 0, 0, 0, 0, 0]))
		cache.set_source(0, Vector2i(20, 20), 2, PackedInt32Array([100, 0, 0, 0, 0, 0, 0]))
	field.request_area(Rect2i(0, 0, 16, 16))
	for step: int in 1000:
		field.rebuild(1, 1)
		if field._build_tile != 0 or field._build_gather_slot != 0: continue
		# The small source misses tile 0, but its linked successor affects it.
		var opened: Dictionary = field.begin_source_change(0, "remove", {})
		if not opened.ok or not _commit(field, opened.handle): return false
		reference.remove_source(0)
		if not _warm(field, Rect2i(0, 0, 16, 16)) or not _warm(reference, Rect2i(0, 0, 16, 16)): return false
		for y: int in 16:
			for x: int in 16:
				if field.read_base(Vector2i(x, y)).channels != reference.read_base(Vector2i(x, y)).channels: return false
		return true
	return false


static func _sparse_move() -> bool:
	var field := SimEnvironmentGroundField.new()
	if not field.configure(Vector2i(512, 512), 8): return false
	field.set_source(0, Vector2i(8, 8), 2, PackedInt32Array([900, 0, 0, 0, 0, 0, 0]))
	field.request_area(Rect2i(496, 496, 16, 16))
	if not _warm(field, Rect2i(0, 0, 16, 16)): return false
	var opened: Dictionary = field.begin_source_change(0, "set", {"cell": Vector2i(500, 500), "radius": 2, "channels": PackedInt32Array([900, 0, 0, 0, 0, 0, 0])})
	if not opened.ok: return false
	var job: Dictionary = field.export_source_compute_job(opened.handle)
	if job.ok or job.reason != "candidate_sparse_area" or not _commit(field, opened.handle): return false
	return field.read_base(Vector2i(8, 8)).channels[0] == 0 and field.read_base(Vector2i(500, 500)).channels[0] == 900
