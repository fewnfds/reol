extends RefCounted
## Differential checks against the original field candidate. The optimized
## structure changes only safe search bounds; integer tiles remain identical.

const Baseline = preload("res://scripts/sim/environment_field_cache.gd")
const GroundField = preload("res://scripts/sim/environment_ground_field.gd")
const CHANNELS: int = 7
const SIZE := Vector2i(32, 24)


func run(runner: Object) -> void:
	_mixed_candidate_equivalence(runner)
	_solo_maximum_and_work(runner)
	_stale_and_cancel(runner)
	_index_churn(runner)
	_live_rebuild_after_maximum_removal(runner)
	_preserved_unrelated_draft(runner)
	_cold_rebuild_local_source_bounds(runner)
	_cold_rebuild_spatial_changes(runner)
	_uniform_cold_rebuild_work(runner)
	print("SCENARIO ground field bounds: exact seven-channel candidate comparison, ties, removal and cancellation")


func _mixed_candidate_equivalence(runner: Object) -> void:
	var base := Baseline.new()
	var fast := GroundField.new()
	if not _ok(runner, base.configure(SIZE, 24) and fast.configure(SIZE, 24), "reference and indexed fields configure"):
		return
	var random := RandomNumberGenerator.new()
	random.seed = 602117
	for slot: int in 16:
		var grades: Array[int] = []
		for channel: int in CHANNELS:
			grades.append(0 if random.randi_range(0, 3) == 0 else random.randi_range(1, 5) * 500)
		# Several equal maxima and co-located sources exercise heap ties/chains.
		if slot in [0, 1, 2]:
			grades[5] = 9500
		var point := Vector2i(15, 11) if slot in [0, 1] else Vector2i(random.randi_range(0, 31), random.randi_range(0, 23))
		var radius: int = random.randi_range(1, 8)
		if not _set_pair(runner, base, fast, slot, point, radius, grades):
			return
	# Direct replacement/removal must update the bound before later candidates.
	if not _set_pair(runner, base, fast, 2, Vector2i(16, 10), 4, [200, 300, 400, 500, 600, 700, 800]):
		return
	runner.assert_true(bool(base.remove_source(1).get("ok", false)) and bool(fast.remove_source(1).get("ok", false)), "one tied maximum can be removed")
	var changes: Array[Dictionary] = [
		{"slot": 0, "op": "set", "cell": Vector2i(30, 21), "radius": 6, "channels": [100, 7000, 0, 600, 800, 9500, 300]},
		{"slot": 3, "op": "remove"},
		{"slot": 16, "op": "set", "cell": Vector2i(0, 23), "radius": 8, "channels": [20000, 0, 1000, 0, 0, 400, 0]},
		{"slot": 0, "op": "remove"},
		{"slot": 16, "op": "set", "cell": Vector2i(15, 11), "radius": 2, "channels": [1, 200, 30000, 0, 0, 0, 1]},
		{"slot": 1, "op": "set", "cell": Vector2i(15, 11), "radius": 8, "channels": [1, 200, 30000, 0, 0, 0, 1]},
		{"slot": 16, "op": "remove"},
		{"slot": 1, "op": "remove"},
	]
	for index: int in changes.size():
		var spec: Dictionary = changes[index]
		var change: Dictionary = {} if spec.op == "remove" else {"cell": spec.cell, "radius": spec.radius, "channels": spec.channels}
		var first: Dictionary = base.begin_source_change(spec.slot, spec.op, change)
		var second: Dictionary = fast.begin_source_change(spec.slot, spec.op, change)
		if not _ok(runner, bool(first.get("ok", false)) and bool(second.get("ok", false)), "mixed candidate %d begins" % index):
			return
		runner.assert_eq(second.tile_ids, first.tile_ids, "both select the same old/new coverage blocks")
		var a: Dictionary = _finish(base, first.handle, runner)
		var b: Dictionary = _finish(fast, second.handle, runner)
		if not bool(a.get("ok", false)) or not bool(b.get("ok", false)):
			return
		for id: int in first.tile_ids:
			var expected: Dictionary = base.candidate_tile_copy(a.proof, id)
			var actual: Dictionary = fast.candidate_tile_copy(b.proof, id)
			runner.assert_true(bool(expected.get("ok", false)) and bool(actual.get("ok", false)), "the candidate tile can be read")
			runner.assert_eq(actual.get("channels"), expected.get("channels"), "all receiver values and seven channels match original field")
		var committed_a: Dictionary = base.commit_source_change(a.proof)
		var committed_b: Dictionary = fast.commit_source_change(b.proof)
		if not _ok(runner, bool(committed_a.get("ok", false)) and bool(committed_b.get("ok", false)), "both candidates publish"):
			return
		runner.assert_eq(committed_b.revision, committed_a.revision, "optimization adds no second source revision")
		runner.assert_true(not bool(fast.commit_source_change(b.proof).get("ok", true)), "an already consumed proof cannot be replayed")


func _solo_maximum_and_work(runner: Object) -> void:
	var base := Baseline.new()
	var fast := GroundField.new()
	if not _ok(runner, base.configure(SIZE, 32) and fast.configure(SIZE, 32), "solo maximum fixture configures"):
		return
	if not _set_pair(runner, base, fast, 0, Vector2i(7, 10), 8, [0, 0, 0, 0, 0, 100_000, 0]):
		return
	for index: int in range(1, 20):
		var point := Vector2i(index, 4)
		if not _set_pair(runner, base, fast, index, point, 8, [2000, 0, 0, 0, 0, 0, 0]):
			return
	var source := {"cell": Vector2i(27, 10), "radius": 8, "channels": [0, 0, 0, 0, 0, 100_000, 0]}
	var first: Dictionary = base.begin_source_change(0, "set", source)
	var second: Dictionary = fast.begin_source_change(0, "set", source)
	if not _ok(runner, bool(first.get("ok", false)) and bool(second.get("ok", false)), "isolated maximum move begins"):
		return
	var a: Dictionary = _finish(base, first.handle, runner)
	var b: Dictionary = _finish(fast, second.handle, runner)
	if not bool(a.get("ok", false)) or not bool(b.get("ok", false)):
		return
	for id: int in first.tile_ids:
		runner.assert_eq(fast.candidate_tile_copy(b.proof, id).get("channels"), base.candidate_tile_copy(a.proof, id).get("channels"), "a unique hot maximum matches on every affected tile")
	runner.assert_true(int(b.total_work) < int(a.total_work), "excluding a unique maximum reduces counted candidate work")
	print("GROUND_FIELD_WORK reference=%d indexed=%d" % [int(a.total_work), int(b.total_work)])
	runner.assert_true(bool(base.cancel_source_change(first.handle).get("ok", false)) and bool(fast.cancel_source_change(second.handle).get("ok", false)), "cancelling both candidates leaves their live fields intact")


func _stale_and_cancel(runner: Object) -> void:
	var field := GroundField.new()
	if not _ok(runner, field.configure(SIZE, 3), "stale candidate fixture configures"):
		return
	runner.assert_true(bool(field.set_source(0, Vector2i(5, 5), 4, [5000, 10, 0, 0, 0, 0, 0]).get("ok", false)), "first source is valid")
	var opened: Dictionary = field.begin_source_change(0, "remove")
	if not _ok(runner, bool(opened.get("ok", false)), "candidate opens before an unrelated write"):
		return
	runner.assert_true(bool(field.set_source(1, Vector2i(6, 5), 4, [4000, 20, 0, 0, 0, 0, 0]).get("ok", false)), "a real source write changes revision")
	runner.assert_eq(field.step_source_change(opened.handle, 1).get("reason"), "stale", "stale bounds cannot be used after a live source changes")
	runner.assert_true(bool(field.cancel_source_change(opened.handle).get("ok", false)), "a stale candidate remains cancellable")
	var retry: Dictionary = field.begin_source_change(0, "remove")
	if not _ok(runner, bool(retry.get("ok", false)), "retry recomputes bounds after cancellation"):
		return
	var sealed: Dictionary = _finish(field, retry.handle, runner)
	if not bool(sealed.get("ok", false)):
		return
	var tile: Dictionary = field.candidate_tile_copy(sealed.proof, retry.tile_ids[0])
	var rect: Rect2i = tile.rect
	var offset: int = ((5 - rect.position.y) * rect.size.x + 6 - rect.position.x) * CHANNELS
	runner.assert_eq(tile.channels[offset], 4000, "remaining weaker source becomes the exact new maximum")
	runner.assert_true(bool(field.commit_source_change(sealed.proof).get("ok", false)), "current proof publishes")
	runner.assert_eq(field.diagnostics().source_count, 1, "publication removes only one original source")
	runner.assert_true(not bool(field.commit_source_change(sealed.proof).get("ok", true)), "a committed proof cannot replay")


func _index_churn(runner: Object) -> void:
	# Compare the exclusion upper bound to a fresh brute-force maximum after
	# repeated slot reuse, ties and arbitrary non-root grade deletions. This
	# checks the performance index; candidate result checks above check the field.
	var field := GroundField.new()
	if not _ok(runner, field.configure(SIZE, 32), "grade churn fixture configures"):
		return
	var active: Dictionary = {}
	var random := RandomNumberGenerator.new()
	random.seed = 901272
	var matched: bool = true
	for iteration: int in 500:
		var slot: int = random.randi_range(0, 31)
		if active.has(slot) and random.randi_range(0, 3) == 0:
			if not bool(field.remove_source(slot).get("ok", false)):
				matched = false
				break
			active.erase(slot)
		else:
			var grades: Array[int] = []
			for channel: int in CHANNELS:
				grades.append(random.randi_range(0, 20) * (channel + 1))
			if not bool(field.set_source(slot, Vector2i(random.randi_range(0, 31), random.randi_range(0, 23)), random.randi_range(1, 4), grades).get("ok", false)):
				matched = false
				break
			active[slot] = grades.duplicate()
		var excluded: int = random.randi_range(0, 31)
		var request := {"cell": Vector2i(31, 23), "radius": 1, "channels": [77777 + iteration, 1, 2, 3, 4, 5, 6]}
		var opened: Dictionary = field.begin_source_change(excluded, "set", request)
		if not bool(opened.get("ok", false)):
			matched = false
			break
		for channel: int in CHANNELS:
			var expected: int = 0
			for other: int in active:
				if other != excluded:
					expected = maxi(expected, int(active[other][channel]))
			if field._candidate_bounds[channel] != expected:
				matched = false
		if not bool(field.cancel_source_change(opened.handle).get("ok", false)):
			matched = false
			break
		if not matched:
			break
	runner.assert_true(matched, "bounded grade heap matches brute force through slot and tied-grade churn")
	for slot: int in active:
		runner.assert_true(bool(field.remove_source(slot).get("ok", false)), "churned sources can all be removed")
	for channel: int in CHANNELS:
		runner.assert_eq(field._grade_bounds[channel].heap.size(), 0, "removed distinct grades leave no unbounded stale heap entries")


func _live_rebuild_after_maximum_removal(runner: Object) -> void:
	var base := Baseline.new()
	var fast := GroundField.new()
	if not _ok(runner, base.configure(SIZE, 32) and fast.configure(SIZE, 32), "ordinary rebuild fixture configures"):
		return
	if not _set_pair(runner, base, fast, 0, Vector2i(7, 10), 8, [0, 0, 0, 0, 0, 100_000, 0]):
		return
	for index: int in range(1, 20):
		if not _set_pair(runner, base, fast, index, Vector2i(index, 4), 8, [2000, 0, 0, 0, 0, 0, 0]):
			return
	if not _ok(runner, bool(base.remove_source(0).get("ok", false)) and bool(fast.remove_source(0).get("ok", false)), "the only hot source is removed"):
		return
	runner.assert_eq(int(fast._max_source[5]), 0, "ordinary live rebuild forgets a removed unique hot maximum")
	var area := Rect2i(Vector2i.ZERO, SIZE)
	base.request_area(area)
	fast.request_area(area)
	var a: Dictionary = _rebuild(base, runner)
	var b: Dictionary = _rebuild(fast, runner)
	if not bool(a.get("ok", false)) or not bool(b.get("ok", false)):
		return
	for y: int in SIZE.y:
		for x: int in SIZE.x:
			var cell := Vector2i(x, y)
			var first: Dictionary = base.read_base(cell)
			var second: Dictionary = fast.read_base(cell)
			if first.get("channels") != second.get("channels"):
				runner.assert_true(false, "ordinary rebuilt field differs at " + str(cell))
				return
	runner.assert_true(true, "all live rebuilt receiver channels match after deleting the strongest source")
	runner.assert_true(int(b.total_work) < int(a.total_work), "lowering the former live maximum reduces ordinary rebuild work")
	print("GROUND_REBUILD_WORK reference=%d indexed=%d" % [int(a.total_work), int(b.total_work)])


func _preserved_unrelated_draft(runner: Object) -> void:
	var base := Baseline.new()
	var fast := GroundField.new()
	if not _ok(runner, base.configure(SIZE, 4) and fast.configure(SIZE, 4), "preserved build fixture configures"):
		return
	if not _set_pair(runner, base, fast, 0, Vector2i(15, 0), 1, [5000, 0, 0, 0, 0, 0, 0]):
		return
	if not _set_pair(runner, base, fast, 1, Vector2i(15, 0), 4, [100, 0, 0, 0, 0, 0, 0]):
		return
	# Tile (1, 0) begins immediately right of slot 0's radius-1 old area;
	# the base algorithm may inspect slot 0 in its linked chain even though
	# that source contributes zero to every cell of this unrelated tile.
	base.read_base(Vector2i(16, 0))
	fast.read_base(Vector2i(16, 0))
	for field: RefCounted in [base, fast]:
		var found: bool = false
		for _iteration: int in 5000:
			field.rebuild(1, 1)
			if field._build_tile == 1 and field._neighbor_slot == 0:
				found = true
				break
		if not _ok(runner, found, "unrelated running tile pauses on the soon-to-be-removed source link"):
			return
	var a_open: Dictionary = base.begin_source_change(0, "remove")
	var b_open: Dictionary = fast.begin_source_change(0, "remove")
	if not _ok(runner, bool(a_open.get("ok", false)) and bool(b_open.get("ok", false)), "removal candidate opens beside an unrelated draft"):
		return
	var a: Dictionary = _finish(base, a_open.handle, runner)
	var b: Dictionary = _finish(fast, b_open.handle, runner)
	if not bool(a.get("ok", false)) or not bool(b.get("ok", false)):
		return
	if not _ok(runner, bool(base.commit_source_change(a.proof).get("ok", false)) and bool(fast.commit_source_change(b.proof).get("ok", false)), "removal candidates publish"):
		return
	runner.assert_eq(fast._build_tile, 1, "the unrelated draft remains in flight")
	runner.assert_eq(int(fast._max_source[0]), 100, "committed bound decreases to the surviving maximum")
	var base_done: Dictionary = _rebuild(base, runner)
	var fast_done: Dictionary = _rebuild(fast, runner)
	if not bool(base_done.get("ok", false)) or not bool(fast_done.get("ok", false)):
		return
	for y: int in 16:
		for x: int in range(16, 32):
			var cell := Vector2i(x, y)
			if base.read_base(cell).get("channels") != fast.read_base(cell).get("channels"):
				runner.assert_true(false, "unrelated draft changed at " + str(cell))
				return
	runner.assert_true(true, "preserved draft yields the same seven-channel field with the lower exact bound")


func _cold_rebuild_local_source_bounds(runner: Object) -> void:
	# One unique extreme would otherwise keep the global upper bound high for
	# receivers on the far side of the map, even though it cannot reach them.
	var size := Vector2i(64, 48)
	var base := Baseline.new()
	var fast := GroundField.new()
	if not _ok(runner, base.configure(size, 8) and fast.configure(size, 8), "spatial cold build fields configure"):
		return
	if not _set_pair(runner, base, fast, 0, Vector2i(1, 1), 8, [100_000, 0, 0, 0, 0, 90_000, 0]):
		return
	if not _set_pair(runner, base, fast, 1, Vector2i(31, 15), 4, [100, 200, 0, 0, 0, 0, 300]):
		return
	if not _set_pair(runner, base, fast, 2, Vector2i(63, 47), 2, [0, 0, 100, 0, 500, 0, 0]):
		return
	var result: Dictionary = _compare_rebuild(runner, base, fast, size, "distant extreme")
	if not bool(result.get("ok", false)):
		return
	runner.assert_true(int(result.optimized_work) < int(result.reference_work), "distant extreme does not force a full global-bound cold search")
	print("GROUND_COLD_REBUILD_WORK reference=%d indexed=%d" % [int(result.reference_work), int(result.optimized_work)])


func _cold_rebuild_spatial_changes(runner: Object) -> void:
	var size := Vector2i(32, 24)
	var base := Baseline.new()
	var fast := GroundField.new()
	if not _ok(runner, base.configure(size, 10) and fast.configure(size, 10), "spatial mutation fields configure"):
		return
	# Tied and weaker co-located sources, adjacent block boundaries, both map
	# edges, a zero source, and differing radii exercise conservative coverage.
	var sources: Array[Dictionary] = [
		{"slot": 0, "cell": Vector2i(15, 15), "radius": 2, "grades": [50, 0, 0, 0, 0, 12_000, 0]},
		{"slot": 1, "cell": Vector2i(15, 15), "radius": 4, "grades": [0, 0, 0, 0, 0, 12_000, 0]},
		{"slot": 2, "cell": Vector2i(15, 15), "radius": 8, "grades": [0, 0, 0, 0, 0, 7_000, 0]},
		{"slot": 3, "cell": Vector2i(16, 15), "radius": 8, "grades": [100, 200, 300, 400, 500, 0, 0]},
		{"slot": 4, "cell": Vector2i(15, 16), "radius": 4, "grades": [0, 0, 0, 0, 0, 0, 900]},
		{"slot": 5, "cell": Vector2i(0, 0), "radius": 8, "grades": [3000, 0, 0, 0, 0, 0, 0]},
		{"slot": 6, "cell": Vector2i(31, 23), "radius": 2, "grades": [0, 0, 0, 1000, 0, 0, 0]},
		{"slot": 7, "cell": Vector2i(16, 16), "radius": 2, "grades": [0, 0, 0, 0, 0, 0, 0]},
	]
	for source: Dictionary in sources:
		if not _set_pair(runner, base, fast, source.slot, source.cell, source.radius, source.grades):
			return
	if not bool(_compare_rebuild(runner, base, fast, size, "mixed radii and block boundaries").get("ok", false)):
		return
	runner.assert_eq(fast.read_base(Vector2i(15, 15)).channels[5], 12_000, "tied hot maxima remain equal at the source cell")

	if not _set_pair(runner, base, fast, 0, Vector2i(25, 15), 4, [50, 0, 0, 0, 0, 12_000, 0]):
		return
	if not bool(_compare_rebuild(runner, base, fast, size, "move across source blocks").get("ok", false)):
		return
	runner.assert_eq(fast.read_base(Vector2i(15, 15)).channels[5], 12_000, "the other tied source survives a move")
	if not _ok(runner, bool(base.remove_source(1).get("ok", false)) and bool(fast.remove_source(1).get("ok", false)), "last tied maximum can be removed"):
		return
	if not bool(_compare_rebuild(runner, base, fast, size, "remove tied maximum").get("ok", false)):
		return
	runner.assert_eq(fast.read_base(Vector2i(15, 15)).channels[5], 7_000, "weaker co-located source takes over after the final tie disappears")

	var replacement := {"cell": Vector2i(16, 15), "radius": 8, "channels": [50, 0, 0, 0, 0, 12_000, 0]}
	var first: Dictionary = base.begin_source_change(0, "set", replacement)
	var second: Dictionary = fast.begin_source_change(0, "set", replacement)
	if not _ok(runner, bool(first.get("ok", false)) and bool(second.get("ok", false)), "cross-block candidate changes begin"):
		return
	var a: Dictionary = _finish(base, first.handle, runner)
	var b: Dictionary = _finish(fast, second.handle, runner)
	if not bool(a.get("ok", false)) or not bool(b.get("ok", false)):
		return
	if not _ok(runner, bool(base.commit_source_change(a.proof).get("ok", false)) and bool(fast.commit_source_change(b.proof).get("ok", false)), "cross-block candidate changes commit"):
		return
	# Candidate publication already computes affected tiles. Moving a zero
	# source dirties them again so the *ordinary* rebuild must use the newly
	# committed source index, not merely the candidate's published values.
	if not _set_pair(runner, base, fast, 7, Vector2i(17, 15), 8, [0, 0, 0, 0, 0, 0, 0]):
		return
	if not bool(_compare_rebuild(runner, base, fast, size, "ordinary rebuild after candidate commit").get("ok", false)):
		return
	runner.assert_eq(fast.read_base(Vector2i(16, 15)).channels[5], 12_000, "committed moved source is visible to a subsequent cold rebuild")


func _uniform_cold_rebuild_work(runner: Object) -> void:
	# With no stronger outlier, a local upper bound cannot prune more receiver
	# work than the global one. Only the small per-tile bound gathering is extra;
	# an extra occupied-head visit per channel would be a real regression.
	var size := Vector2i(32, 16)
	var base := Baseline.new()
	var fast := GroundField.new()
	if not _ok(runner, base.configure(size, size.x * size.y) and fast.configure(size, size.x * size.y), "uniform no-outlier fields configure"):
		return
	for y: int in size.y:
		for x: int in size.x:
			if not _set_pair(runner, base, fast, y * size.x + x, Vector2i(x, y), 16, [0, 1000, 100, 0, 100, 0, 0]):
				return
	var result: Dictionary = _compare_rebuild(runner, base, fast, size, "uniform no-outlier field")
	if not bool(result.get("ok", false)):
		return
	runner.assert_true(int(result.optimized_work) <= int(result.reference_work) + 18, "uniform receiver work only adds bounded block gathering, never a source visit per channel")
	print("GROUND_UNIFORM_WORK reference=%d indexed=%d" % [int(result.reference_work), int(result.optimized_work)])


func _compare_rebuild(runner: Object, base: RefCounted, fast: RefCounted, size: Vector2i, label: String) -> Dictionary:
	var area := Rect2i(Vector2i.ZERO, size)
	if not _ok(runner, bool(base.request_area(area).get("ok", false)) and bool(fast.request_area(area).get("ok", false)), label + ": request area"):
		return {}
	var a: Dictionary = _rebuild(base, runner)
	var b: Dictionary = _rebuild(fast, runner)
	if not bool(a.get("ok", false)) or not bool(b.get("ok", false)):
		return {}
	for y: int in size.y:
		for x: int in size.x:
			var cell := Vector2i(x, y)
			var first: Dictionary = base.read_base(cell)
			var second: Dictionary = fast.read_base(cell)
			if not bool(first.get("ok", false)) or bool(first.get("pending", true)) or not bool(second.get("ok", false)) or bool(second.get("pending", true)) or first.get("channels") != second.get("channels"):
				runner.assert_true(false, label + ": seven-channel mismatch or incomplete tile at " + str(cell))
				return {}
	runner.assert_true(true, label + ": every cell has the same seven channels")
	return {"ok": true, "reference_work": int(a.total_work), "optimized_work": int(b.total_work)}


func _set_pair(runner: Object, base: RefCounted, fast: RefCounted, slot: int, cell: Vector2i, radius: int, grades: Array) -> bool:
	var one: Dictionary = base.set_source(slot, cell, radius, grades)
	var two: Dictionary = fast.set_source(slot, cell, radius, grades)
	return _ok(runner, bool(one.get("ok", false)) and bool(two.get("ok", false)), "both fields accept a source")


func _finish(field: RefCounted, handle: Variant, runner: Object) -> Dictionary:
	var total: int = 0
	for _iteration: int in 5000:
		var result: Dictionary = field.step_source_change(handle, 10_000)
		if not bool(result.get("ok", false)):
			runner.assert_true(false, "candidate must remain current: " + str(result))
			return {}
		if int(result.work) > 10_000:
			runner.assert_true(false, "candidate exceeds its work budget")
			return {}
		total += int(result.work)
		if bool(result.done):
			var finished: Dictionary = field.finish_source_change(handle)
			if not bool(finished.get("ok", false)):
				runner.assert_true(false, "candidate obtains a proof")
				return {}
			return {"ok": true, "proof": finished.proof, "total_work": total}
	runner.assert_true(false, "bounded candidate reaches a result")
	return {}


func _rebuild(field: RefCounted, runner: Object) -> Dictionary:
	var total: int = 0
	for _iteration: int in 5000:
		var result: Dictionary = field.rebuild(16, 10_000)
		if not bool(result.get("ok", false)):
			runner.assert_true(false, "ordinary field rebuild failed: " + str(result))
			return {}
		total += int(result.work)
		if int(result.pending_tiles) == 0:
			return {"ok": true, "total_work": total}
	runner.assert_true(false, "ordinary bounded rebuild finishes")
	return {}


func _ok(runner: Object, value: bool, message: String) -> bool:
	runner.assert_true(value, message)
	return value
