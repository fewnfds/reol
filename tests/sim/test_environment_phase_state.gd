extends RefCounted
## Actual five-element anchors: continuity, private preparation and recovery.

const State = preload("res://scripts/sim/environment_phase_state.gd")


func run(runner: Object) -> void:
	_lifecycle_and_move(runner)
	_split_invariance(runner)
	_isolation_and_failures(runner)
	_restore_and_stale_proof(runner)
	print("SCENARIO environment phase state: five independent channels, continuous retargeting, cancellable bulk and isolated recovery")


func _lifecycle_and_move(runner: Object) -> void:
	var state := State.new()
	runner.assert_eq(state.actual_at(Vector2i.ZERO, 0).reason, "not_configured", "unconfigured phase owner has no value")
	runner.assert_true(state.configure(Vector2i(16, 16), 256, 100), "phase owner configures")
	runner.assert_true(not state.configure(Vector2i(16, 16), 256, 100), "configure cannot replace a live state")
	runner.assert_eq(state.actual_at(Vector2i.ZERO, 100).reason, "untracked", "a missing anchor is not silently treated as zero")
	var fields: Dictionary = _columns()
	_set_target(fields, Vector2i(1, 1), true, [0.0, 1.0, 2.0, 3.0, 4.0], [10000.0, 0.0, 2000.0, 3000.0, 4000.0], 5_100, 1_000)
	_set_target(fields, Vector2i(6, 1), true, [0.0, 1.0, 2.0, 3.0, 4.0], [0.0, 0.0, 0.0, 0.0, 0.0], 5_100, 1_000)
	var opening: Dictionary = _prepare(state, 100, Vector2i.ZERO, fields, 7)
	runner.assert_true(bool(opening.get("ok", false)), "five channel anchors prepare incrementally")
	if not bool(opening.get("ok", false)):
		return
	runner.assert_eq(state.actual_at(Vector2i(1, 1), 100).reason, "untracked", "prepared anchors remain private")
	runner.assert_true(bool(state.commit_bulk(opening.proof).get("ok", false)), "the complete candidate publishes once")
	runner.assert_true(not state.can_commit_bulk(opening.proof), "a published proof cannot replay")
	runner.assert_eq(state.next_boundary_ms(), 5_100, "earliest shared target segment boundary is exposed")
	var start: PackedFloat64Array = state.actual_at(Vector2i(1, 1), 100).values
	runner.assert_eq(start, PackedFloat64Array([0.0, 1.0, 2.0, 3.0, 4.0]), "activation uses supplied values in packed channel order")
	var before: PackedFloat64Array = state.actual_at(Vector2i(1, 1), 1_100).values
	_near(runner, before[0], 10000.0 * (1.0 - exp(-1.0)), 1.0e-9, "metal influence establishes gradually")
	_near(runner, before[1], exp(-1.0), 1.0e-12, "wood is an independent channel")
	var reads_before: Dictionary = state.snapshot()
	for t: int in [5_100, 1_100, 100, 4_999, 1_100]:
		state.actual_at(Vector2i(1, 1), t)
	runner.assert_eq(state.snapshot(), reads_before, "reads in arbitrary order do not modify anchors")
	runner.assert_eq(state.actual_at(Vector2i(1, 1), 5_101).reason, "target_boundary", "values beyond known target segments are not invented")
	var moved: Dictionary = _columns()
	_set_target(moved, Vector2i(1, 1), false, [], [0.0, 0.0, 0.0, 0.0, 0.0], 10_000, 1_000)
	_set_target(moved, Vector2i(6, 1), false, [], [10000.0, 0.0, 2000.0, 3000.0, 4000.0], 10_000, 1_000)
	var move_plan: Dictionary = _prepare(state, 1_100, Vector2i.ZERO, moved, 256)
	runner.assert_true(bool(move_plan.get("ok", false)), "two locations can be retargeted together")
	if not bool(move_plan.get("ok", false)):
		return
	runner.assert_true(bool(state.commit_bulk(move_plan.proof).get("ok", false)), "source move publishes both cells")
	_near(runner, state.actual_at(Vector2i(1, 1), 1_100).values[0], before[0], 1.0e-9, "old location starts with its actual value")
	_near(runner, state.actual_at(Vector2i(6, 1), 1_100).values[0], 0.0, 1.0e-12, "new location retains its own actual value")
	_near(runner, state.actual_at(Vector2i(1, 1), 2_100).values[0], before[0] * exp(-1.0), 1.0e-9, "old location gradually loses residual influence")
	_near(runner, state.actual_at(Vector2i(6, 1), 2_100).values[0], 10000.0 * (1.0 - exp(-1.0)), 1.0e-9, "new location gradually establishes influence")
	runner.assert_eq(state.actual_at(Vector2i(1, 1), 1_099).reason, "history_unavailable", "previous segment is not reverse reconstructed")
	runner.assert_eq(state.next_boundary_ms(), 10_000, "replacing every old boundary updates the earliest index")


func _split_invariance(runner: Object) -> void:
	var whole := State.new()
	var split := State.new()
	whole.configure(Vector2i(2, 2), 4, 0)
	split.configure(Vector2i(2, 2), 4, 0)
	var fields: Dictionary = _columns()
	_set_target(fields, Vector2i.ZERO, true, [1.0, 2.0, 0.0, 0.0, 0.0], [1000.0, 300.0, 0.0, 0.0, 0.0], 10_000, 1_000)
	fields.slope[0] = 0.25
	fields.slope[1] = -0.01
	var p: Dictionary = _prepare(whole, 0, Vector2i.ZERO, fields, 256)
	whole.commit_bulk(p.proof)
	p = _prepare(split, 0, Vector2i.ZERO, fields, 1)
	split.commit_bulk(p.proof)
	for time: int in [500, 1_000, 1_000]:
		fields = _columns()
		_set_target(fields, Vector2i.ZERO, false, [], [1000.0 + 0.25 * float(time), 300.0 - 0.01 * float(time), 0.0, 0.0, 0.0], 10_000, 1_000)
		fields.slope[0] = 0.25
		fields.slope[1] = -0.01
		p = _prepare(split, time, Vector2i.ZERO, fields, 17)
		runner.assert_true(bool(p.get("ok", false)), "a shared target may be partitioned at a known time")
		if not bool(p.get("ok", false)):
			return
		split.commit_bulk(p.proof)
	var a: PackedFloat64Array = whole.actual_at(Vector2i.ZERO, 5_000).values
	var b: PackedFloat64Array = split.actual_at(Vector2i.ZERO, 5_000).values
	for channel: int in State.CHANNELS:
		_near(runner, b[channel], a[channel], 1.0e-8, "linear targets preserve the same future across split and same-time segments")


func _isolation_and_failures(runner: Object) -> void:
	var state := State.new()
	state.configure(Vector2i(16, 16), 256, 0)
	var fields: Dictionary = _columns()
	_set_target(fields, Vector2i.ZERO, true, [0.0, 0.0, 0.0, 0.0, 0.0], [100.0, 200.0, 300.0, 400.0, 500.0], 1_000, 100)
	var opened: Dictionary = state.begin_bulk(0, 1)
	var handle: Variant = opened.handle
	runner.assert_true(bool(state.offer_bulk_chunk(handle, Vector2i.ZERO, fields).get("ok", false)), "caller can offer a chunk")
	fields.target[0] = 999.0
	var partial: Dictionary = state.resume_bulk(handle, 1)
	runner.assert_eq(partial.status, "pending", "only the requested number of cells is consumed")
	runner.assert_eq(partial.visited, 1, "budget accounts for visited slots")
	runner.assert_eq(state.actual_at(Vector2i.ZERO, 0).reason, "untracked", "partial preparation does not publish")
	runner.assert_true(bool(state.cancel_bulk(handle).get("ok", false)), "partial preparation can be cancelled")
	runner.assert_eq(state.snapshot().cells.size(), 0, "cancelled anchors leave no state")
	fields.target[0] = 100.0
	opened = state.begin_bulk(0, 1)
	handle = opened.handle
	state.offer_bulk_chunk(handle, Vector2i.ZERO, fields)
	fields.target[0] = 999.0
	state.resume_bulk(handle, 256)
	var prepared: Dictionary = state.finish_bulk(handle)
	runner.assert_true(bool(state.commit_bulk(prepared.proof).get("ok", false)), "first anchor commits")
	_near(runner, state.actual_at(Vector2i.ZERO, 1_000).values[0], 100.0 * (1.0 - exp(-10.0)), 1.0e-9, "offered columns cannot be changed by the caller")
	var before: Dictionary = state.snapshot()
	var bad: Dictionary = _columns()
	_set_target(bad, Vector2i.ZERO, false, [], [100.0, 200.0, -1.0, 400.0, 500.0], 2_000, 100)
	var result: Dictionary = _prepare(state, 500, Vector2i.ZERO, bad, 256)
	runner.assert_eq(result.get("reason"), "target_invalid", "one invalid channel rejects the entire change")
	runner.assert_eq(state.snapshot(), before, "failed channel validation cannot publish the other four")
	bad = _columns()
	_set_target(bad, Vector2i.ZERO, false, [], [0.0, 0.0, 0.0, 0.0, 0.0], 2_000, 100)
	bad.slope[0] = -1.0
	result = _prepare(state, 500, Vector2i.ZERO, bad, 256)
	runner.assert_eq(result.get("reason"), "target_invalid", "a target segment with a negative endpoint is rejected")
	runner.assert_eq(state.snapshot(), before, "invalid slope preserves state")
	bad = _columns()
	_set_target(bad, Vector2i.ZERO, true, [0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0], 2_000, 100)
	result = _prepare(state, 500, Vector2i.ZERO, bad, 256)
	runner.assert_eq(result.get("reason"), "initial_mismatch", "tracked cells cannot replace their actual value with a caller-supplied initial")
	runner.assert_eq(state.snapshot(), before, "invalid initial does not alter an anchor")
	bad = _columns()
	_set_target(bad, Vector2i(1, 0), true, [0.0, NAN, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0], 2_000, 100)
	result = _prepare(state, 500, Vector2i.ZERO, bad, 256)
	runner.assert_eq(result.get("reason"), "initial_out_of_range", "nonfinite initial is rejected")
	runner.assert_eq(state.snapshot(), before, "bad initial preserves existing cells")


func _restore_and_stale_proof(runner: Object) -> void:
	var state := State.new()
	state.configure(Vector2i(16, 16), 256, 0)
	var fields: Dictionary = _columns()
	_set_target(fields, Vector2i(2, 0), true, [0.0, 1.0, 2.0, 3.0, 4.0], [100.0, 200.0, 300.0, 400.0, 500.0], 10_000, 1_000)
	_set_target(fields, Vector2i.ZERO, true, [1.0, 2.0, 3.0, 4.0, 5.0], [500.0, 400.0, 300.0, 200.0, 100.0], 9_000, 1_000)
	var initial: Dictionary = _prepare(state, 0, Vector2i.ZERO, fields, 16)
	state.commit_bulk(initial.proof)
	var baseline: Dictionary = state.snapshot()
	var future: Dictionary = state.actual_at(Vector2i.ZERO, 5_000)
	var decoded: Variant = JSON.parse_string(JSON.stringify(baseline, "", true, true))
	var restored := State.new()
	runner.assert_true(restored.restore(decoded), "full precision JSON snapshot restores")
	runner.assert_eq(restored.snapshot(), baseline, "restoration preserves all five anchors")
	runner.assert_eq(restored.actual_at(Vector2i.ZERO, 5_000), future, "restored response has an identical future")
	runner.assert_eq(restored.next_boundary_ms(), 9_000, "boundary index is reconstructed from anchors")
	var bad: Dictionary = baseline.duplicate(true)
	bad.cells[0].target[0] = -1.0
	runner.assert_true(not restored.restore(bad), "invalid saved channel rejects the complete candidate")
	runner.assert_eq(restored.snapshot(), baseline, "failed restore preserves the live state")
	bad = baseline.duplicate(true)
	bad.cells.append(bad.cells[0].duplicate(true))
	runner.assert_true(not restored.restore(bad), "duplicate saved cells are rejected")
	runner.assert_eq(restored.snapshot(), baseline, "duplicate rejection is atomic")
	fields = _columns()
	_set_target(fields, Vector2i.ZERO, false, [], [0.0, 0.0, 0.0, 0.0, 0.0], 10_000, 1_000)
	var pending: Dictionary = _prepare(state, 1_000, Vector2i.ZERO, fields, 256)
	runner.assert_true(bool(pending.get("ok", false)), "a new candidate can be prepared before restoration")
	runner.assert_true(state.restore(decoded), "the same numeric revision can be restored")
	runner.assert_true(not state.can_commit_bulk(pending.proof), "restoration invalidates previously prepared proof identity")
	runner.assert_eq(state.snapshot(), baseline, "stale proof cannot affect restored state")


func _columns() -> Dictionary:
	var mask := PackedByteArray()
	var initial_mask := PackedByteArray()
	var initial := PackedFloat64Array()
	var target := PackedFloat64Array()
	var slope := PackedFloat64Array()
	var until := PackedInt64Array()
	var tau := PackedInt32Array()
	mask.resize(State.CHUNK_CELLS)
	initial_mask.resize(State.CHUNK_CELLS)
	initial.resize(State.CHUNK_VALUES)
	target.resize(State.CHUNK_VALUES)
	slope.resize(State.CHUNK_VALUES)
	until.resize(State.CHUNK_CELLS)
	tau.resize(State.CHUNK_CELLS)
	return {"mask": mask, "initial_mask": initial_mask, "initial": initial, "target": target,
		"slope": slope, "until_ms": until, "tau_ms": tau}


func _set_target(fields: Dictionary, cell: Vector2i, has_initial: bool, initial: Array, target: Array, until_ms: int, tau_ms: int) -> void:
	var index: int = ((cell.y & 15) << 4) + (cell.x & 15)
	fields.mask[index] = 1
	fields.initial_mask[index] = 1 if has_initial else 0
	fields.until_ms[index] = until_ms
	fields.tau_ms[index] = tau_ms
	for channel: int in State.CHANNELS:
		var offset: int = index * State.CHANNELS + channel
		if has_initial:
			fields.initial[offset] = float(initial[channel])
		fields.target[offset] = float(target[channel])


func _prepare(state: RefCounted, at_ms: int, key: Vector2i, fields: Dictionary, budget: int) -> Dictionary:
	var opened: Dictionary = state.begin_bulk(at_ms, 1)
	if not bool(opened.get("ok", false)):
		return opened
	var handle: Variant = opened.handle
	var result: Dictionary = state.offer_bulk_chunk(handle, key, fields)
	if not bool(result.get("ok", false)):
		state.cancel_bulk(handle)
		return result
	while result.get("status") != "chunk_done":
		result = state.resume_bulk(handle, budget)
		if not bool(result.get("ok", false)):
			state.cancel_bulk(handle)
			return result
	result = state.finish_bulk(handle)
	if not bool(result.get("ok", false)):
		state.cancel_bulk(handle)
	return result


func _near(runner: Object, actual: float, expected: float, tolerance: float, message: String) -> void:
	runner.assert_true(is_finite(actual) and absf(actual - expected) <= tolerance, "%s: expected %s ± %s, got %s" % [message, str(expected), str(tolerance), str(actual)])

