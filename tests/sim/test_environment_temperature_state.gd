extends RefCounted
## The isolated owner tracks only actual temperatures over known segments.

const State = preload("res://scripts/sim/environment_temperature_state.gd")
const Index = preload("res://scripts/sim/environment_field_index.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")


func run(runner: Object) -> void:
	_lifecycle(runner)
	_field_move_and_cancel(runner)
	_transaction_rejection(runner)
	_boundary_index(runner)
	_read_order_and_restore(runner)
	_snapshot_rejection(runner)
	print("SCENARIO environment temperature state: known segments, source-field targets, continuous moves, atomic plans, read-only projection and isolated JSON recovery")


func _change(cell: Vector2i, target: float, until: int, tau: int = 1_000, slope: float = 0.0) -> Dictionary:
	return {"cell": cell, "target_c": target, "target_per_ms": slope, "until_ms": until, "tau_ms": tau}


func _new_change(cell: Vector2i, initial: float, target: float, until: int, tau: int = 1_000, slope: float = 0.0) -> Dictionary:
	var result: Dictionary = _change(cell, target, until, tau, slope)
	result["initial_c"] = initial
	return result


func _apply(state: RefCounted, changes: Array[Dictionary], at_ms: int, budget: int) -> Dictionary:
	var plan: Dictionary = state.prepare_targets(changes, at_ms, budget)
	return state.commit(plan) if bool(plan.get("ok", false)) else plan


func _near(runner: Object, actual: float, expected: float, tolerance: float, message: String) -> void:
	runner.assert_true(is_finite(actual) and absf(actual - expected) <= tolerance, "%s: expected %s ± %s, got %s" % [message, str(expected), str(tolerance), str(actual)])


func _check_boundary(runner: Object, state: RefCounted, expected: int, message: String) -> void:
	var snapshot: Dictionary = state.snapshot()
	var scanned: int = -1
	for row: Dictionary in snapshot.get("cells", []):
		var boundary: int = int(row.response.until_ms)
		if scanned < 0 or boundary < scanned:
			scanned = boundary
	runner.assert_eq(state.next_boundary_ms(), expected, message)
	runner.assert_eq(state.next_boundary_ms(), scanned, "the exposed boundary agrees with the saved response segments")


func _lifecycle(runner: Object) -> void:
	var state := State.new()
	runner.assert_eq(state.actual_at(Vector2i.ZERO, 0), {"ok": false, "reason": "not_configured"}, "an unconfigured owner cannot invent a value")
	runner.assert_eq(state.next_boundary_ms(), -1, "an unconfigured owner has no boundary")
	runner.assert_eq(state.snapshot(), {}, "an unconfigured owner has no snapshot")
	for candidate: Array in [[Vector2i.ZERO, 1, 0], [Vector2i(2, 2), 0, 0], [Vector2i(2, 2), 5, 0], [Vector2i(2, 2), 1, -1], [Vector2i(2, 2), 1, State.MAX_TIME + 1]]:
		var blank := State.new()
		runner.assert_true(not blank.configure(candidate[0], int(candidate[1]), int(candidate[2])), "invalid configuration is rejected")
		runner.assert_eq(blank.snapshot(), {}, "failed configuration leaves the owner empty")
	runner.assert_true(state.configure(Vector2i(3, 2), 6, 100), "a bounded owner configures at its activation")
	runner.assert_true(not state.configure(Vector2i(3, 2), 6, 100), "configuration cannot replace a live owner")
	runner.assert_eq(state.actual_at(Vector2i(1, 1), 100), {"ok": false, "reason": "untracked"}, "an untracked cell cannot be mistaken for zero temperature")
	runner.assert_eq(state.actual_at(Vector2i(-1, 0), 100), {"ok": false, "reason": "invalid_cell"}, "outside cells fail explicitly")
	runner.assert_eq(state.actual_at(Vector2i.ZERO, 99), {"ok": false, "reason": "time_out_of_range"}, "times before activation fail explicitly")
	var initial_changes: Array[Dictionary] = [_new_change(Vector2i(1, 1), 10.0, 20.0, 1_100)]
	var initial_plan: Dictionary = state.prepare_targets(initial_changes, 100, 1)
	runner.assert_true(bool(initial_plan.get("ok", false)), "a new cell accepts the supplied real initial value")
	if not bool(initial_plan.get("ok", false)):
		return
	var commit: Dictionary = state.commit(initial_plan)
	runner.assert_true(bool(commit.get("ok", false)) and int(commit.revision) == 1, "a complete plan publishes one revision")
	runner.assert_eq(state.actual_at(Vector2i(1, 1), 100).value_c, 10.0, "the initial value is continuous at activation")
	_near(runner, float(state.actual_at(Vector2i(1, 1), 1_100).value_c), 20.0 - 10.0 * exp(-1.0), 1.0e-11, "the response advances toward its known target")
	runner.assert_eq(state.next_boundary_ms(), 1_100, "the target boundary is exposed")
	runner.assert_eq(state.actual_at(Vector2i(1, 1), 1_101), {"ok": false, "reason": "target_boundary"}, "a query beyond the known target is not fabricated")
	runner.assert_true(not bool(state.commit(initial_plan).get("ok", true)), "a committed plan cannot be replayed")


func _field_move_and_cancel(runner: Object) -> void:
	var field := Index.new()
	var state := State.new()
	runner.assert_true(field.configure(Vector2i(8, 2), 3) and state.configure(Vector2i(8, 2), 4, 0), "field and actual-temperature owners configure")
	var a := Vector2i(1, 0)
	var b := Vector2i(6, 0)
	var hot: Array[int] = [0, 0, 0, 0, 0, 1_000, 0]
	var cold: Array[int] = [0, 0, 0, 0, 0, 0, 1_000]
	runner.assert_true(bool(field.set_source({"id": "fire", "cell": a, "radius": 1, "channels": hot}).ok), "original hot source is indexed")
	var a_target: float = _field_target(field, a)
	var b_target: float = _field_target(field, b)
	runner.assert_eq(a_target, 40.0, "one hot grade maps to its actual target")
	runner.assert_eq(b_target, 20.0, "an empty field maps to the supplied neutral")
	var opening: Array[Dictionary] = [_new_change(a, 20.0, a_target, 10_000), _new_change(b, 20.0, b_target, 10_000)]
	runner.assert_true(bool(_apply(state, opening, 0, 2).get("ok", false)), "both real starting temperatures are installed atomically")
	var a_at_move: float = float(state.actual_at(a, 1_000).value_c)
	_near(runner, a_at_move, 40.0 - 20.0 * exp(-1.0), 1.0e-11, "A warms gradually before the move")
	runner.assert_eq(state.actual_at(b, 1_000).value_c, 20.0, "B remains neutral before the move")
	runner.assert_true(bool(field.set_source({"id": "fire", "cell": b, "radius": 1, "channels": hot}).ok), "the original source moves from A to B")
	var moved: Array[Dictionary] = [_change(a, _field_target(field, a), 10_000), _change(b, _field_target(field, b), 10_000)]
	var plan: Dictionary = state.prepare_targets(moved, 1_000, 2)
	if not bool(plan.get("ok", false)):
		runner.assert_true(false, "move plan prepares both old and new cells")
		return
	# A prepared plan is cancellable by discarding it; it cannot change the
	# actual owner or make the original source's old influence into a new source.
	var before: Dictionary = state.snapshot()
	var old_future: Dictionary = state.actual_at(a, 2_000)
	runner.assert_eq(state.snapshot(), before, "preparing the move does not commit or reanchor")
	runner.assert_eq(state.actual_at(a, 2_000), old_future, "an uncommitted move cannot alter the old future")
	runner.assert_true(bool(state.commit(plan).get("ok", false)), "one transaction commits the changed targets")
	_near(runner, float(state.actual_at(a, 1_000).value_c), a_at_move, 1.0e-12, "A inherits its own old actual temperature")
	runner.assert_eq(state.actual_at(b, 1_000).value_c, 20.0, "B starts from its own actual temperature")
	_near(runner, float(state.actual_at(a, 2_000).value_c), 20.0 + (a_at_move - 20.0) * exp(-1.0), 1.0e-11, "A returns to neutral without following the source")
	_near(runner, float(state.actual_at(b, 2_000).value_c), 40.0 - 20.0 * exp(-1.0), 1.0e-11, "B independently establishes the moved source response")
	runner.assert_true(bool(field.set_source({"id": "ice", "cell": b, "radius": 1, "channels": cold}).ok), "an equal cold source occupies B")
	var neutral: float = _field_target(field, b)
	runner.assert_eq(neutral, 20.0, "equal effective hot and cold grades cancel before temperature lookup")
	var b_before: float = float(state.actual_at(b, 2_000).value_c)
	var cancellation: Array[Dictionary] = [_change(b, neutral, 10_000)]
	runner.assert_true(bool(_apply(state, cancellation, 2_000, 1).get("ok", false)), "the equal-source target changes at the real boundary")
	_near(runner, float(state.actual_at(b, 3_000).value_c), 20.0 + (b_before - 20.0) * exp(-1.0), 1.0e-11, "actual temperature relaxes toward balanced neutral")
	runner.assert_true(bool(field.remove_source("fire").ok), "the hot source can be removed independently")
	runner.assert_eq(_field_target(field, b), 0.0, "remaining cold grade maps to the cold target")


func _field_target(field: RefCounted, cell: Vector2i) -> float:
	var channels: PackedInt64Array = field.sample_base(cell).channels
	var target: Dictionary = Rules.thermal_target(20_000, int(channels[5]), int(channels[6]))
	return float(target.temperature_milli) / 1000.0


func _transaction_rejection(runner: Object) -> void:
	var state := State.new()
	state.configure(Vector2i(4, 2), 3, 100)
	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	var valid: Array[Dictionary] = [_new_change(a, 10.0, 50.0, 500)]
	var initial_plan: Dictionary = state.prepare_targets(valid, 100, 1)
	runner.assert_true(bool(state.commit(initial_plan).get("ok", false)), "baseline response commits")
	var baseline: Dictionary = state.snapshot()
	var unbudgeted: Array[Dictionary] = [_change(a, 20.0, 900), _new_change(b, 20.0, 20.0, 900)]
	runner.assert_eq(state.prepare_targets(unbudgeted, 200, 1), {"ok": false, "reason": "pending"}, "insufficient transaction budget returns pending without partial changes")
	runner.assert_eq(state.snapshot(), baseline, "pending preparation leaves every actual anchor unchanged")
	var bad_changes: Array = [
		[_change(a, 20.0, 900), _change(a, 30.0, 900)],
		[_new_change(a, 99.0, 20.0, 900)],
		[_change(b, 20.0, 900)],
		[_new_change(b, -273.151, 20.0, 900)],
		[_new_change(b, 20.0, -273.151, 900)],
		[_new_change(b, 20.0, State.MAX_C + 1.0, 900)],
		[_new_change(b, 20.0, 20.0, 900, 1_000, INF)],
		[_new_change(b, 20.0, -273.15, 900, 1_000, -0.001)],
		[_new_change(b, 20.0, State.MAX_C, 900, 1_000, 1.0)],
		[_new_change(Vector2i(4, 0), 20.0, 20.0, 900)],
		[_new_change(b, 20.0, 20.0, 199)],
		[_new_change(b, 20.0, 20.0, 900, 0)],
	]
	for raw: Array in bad_changes:
		var batch: Array[Dictionary] = []
		for entry: Dictionary in raw:
			batch.append(entry)
		runner.assert_true(not bool(state.prepare_targets(batch, 200, 3).get("ok", true)), "invalid complete change is explicitly rejected")
		runner.assert_eq(state.snapshot(), baseline, "a later invalid row cannot partially update an earlier one")
	var expired: Array[Dictionary] = [_change(a, 20.0, 900)]
	runner.assert_eq(state.prepare_targets(expired, 501, 1), {"ok": false, "reason": "target_boundary"}, "an old segment cannot be extended past its known target")
	runner.assert_eq(state.snapshot(), baseline, "target-boundary rejection leaves the old response intact")
	var high: Array[Dictionary] = [_new_change(b, -273.15, -273.15, 900)]
	runner.assert_true(bool(state.prepare_targets(high, 200, 1).get("ok", false)), "absolute zero itself is a valid actual and target temperature")
	var other := State.new()
	other.configure(Vector2i(4, 2), 3, 100)
	var current: Dictionary = state.prepare_targets(expired, 200, 1)
	if not bool(current.get("ok", false)):
		runner.assert_true(false, "a valid replacement prepares")
		return
	runner.assert_true(current.is_read_only() and current.rows.is_read_only() and current.rows[0].is_read_only() and current.rows[0].response.is_read_only(), "the entire public plan is read-only")
	runner.assert_true(not bool(other.commit(current).get("ok", true)), "a plan belongs only to its original owner")
	var tampered: Dictionary = current.duplicate(true)
	tampered.rows[0].response.initial_value = 123.0
	runner.assert_true(not bool(state.commit(tampered).get("ok", true)), "a changed copy cannot override the old actual temperature")
	runner.assert_eq(state.snapshot(), baseline, "failed commit leaves the original state unchanged")
	runner.assert_true(bool(state.commit(current).get("ok", false)), "rejecting a bad copy leaves the original plan usable")
	runner.assert_true(not bool(state.commit(current).get("ok", true)), "one successful plan cannot be applied twice")
	var prior_plan: Dictionary = state.prepare_targets([_change(a, 30.0, 900)], 300, 1)
	var later_plan: Dictionary = state.prepare_targets([_change(a, 40.0, 900)], 300, 1)
	runner.assert_true(not bool(state.commit(prior_plan).get("ok", true)), "a newer prepared plan supersedes the earlier uncommitted plan")
	runner.assert_true(bool(state.commit(later_plan).get("ok", false)), "the latest plan can be committed")


func _boundary_index(runner: Object) -> void:
	var state := State.new()
	runner.assert_true(state.configure(Vector2i(6, 1), 6, 0), "boundary-index owner configures")
	_check_boundary(runner, state, -1, "a configured owner with no cells has no boundary")
	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	var c := Vector2i(2, 0)
	var d := Vector2i(3, 0)
	var e := Vector2i(4, 0)
	var f := Vector2i(5, 0)
	var opening: Array[Dictionary] = [
		_new_change(a, 20.0, 30.0, 100), _new_change(b, 20.0, 30.0, 100),
		_new_change(c, 20.0, 30.0, 200), _new_change(d, 20.0, 30.0, 300),
		_new_change(e, 20.0, 30.0, 300),
	]
	if not bool(_apply(state, opening, 0, 5).get("ok", false)):
		runner.assert_true(false, "the boundary-index fixture commits")
		return
	_check_boundary(runner, state, 100, "two cells share the earliest boundary")
	var baseline: Dictionary = state.snapshot()
	var pending: Array[Dictionary] = [_change(a, 40.0, 250), _change(b, 40.0, 250)]
	runner.assert_eq(state.prepare_targets(pending, 50, 1), {"ok": false, "reason": "pending"}, "pending preparation cannot publish an index update")
	runner.assert_eq(state.snapshot(), baseline, "pending preparation leaves all response segments untouched")
	_check_boundary(runner, state, 100, "pending preparation leaves the earliest boundary intact")
	var plan: Dictionary = state.prepare_targets([_change(a, 40.0, 250)], 50, 1)
	if not bool(plan.get("ok", false)):
		runner.assert_true(false, "a partial earliest-boundary replacement prepares")
		return
	var forged: Dictionary = plan.duplicate(true)
	forged.rows[0].response.until_ms = 50
	runner.assert_true(not bool(state.commit(forged).get("ok", true)), "a modified plan is rejected before index publication")
	runner.assert_eq(state.snapshot(), baseline, "failed commit preserves the original response segments")
	_check_boundary(runner, state, 100, "failed commit preserves the earliest boundary")
	runner.assert_true(bool(state.commit(plan).get("ok", false)), "the original partial replacement still commits")
	_check_boundary(runner, state, 100, "replacing one of two earliest cells leaves the other visible")

	# Reconstruct into an already populated owner, proving restore discards its
	# former index and correctly counts several cells at the same boundary.
	var restored := State.new()
	restored.configure(Vector2i(6, 1), 6, 0)
	_apply(restored, [_new_change(f, 20.0, 20.0, 50)], 0, 1)
	_check_boundary(runner, restored, 50, "the destination initially has a different boundary")
	var saved: Variant = JSON.parse_string(JSON.stringify(baseline, "", true, true))
	if not restored.restore(saved):
		runner.assert_true(false, "full-precision restore rebuilds the boundary index")
		return
	runner.assert_eq(restored.snapshot(), baseline, "the index does not change the saved format")
	_check_boundary(runner, restored, 100, "restore replaces the former earliest boundary")
	runner.assert_true(bool(_apply(restored, [_change(a, 40.0, 250)], 50, 1).get("ok", false)), "one restored earliest cell can change")
	_check_boundary(runner, restored, 100, "restore reconstructs the shared boundary count")
	runner.assert_true(bool(_apply(restored, [_change(b, 40.0, 250)], 50, 1).get("ok", false)), "the last restored earliest cell can change")
	_check_boundary(runner, restored, 200, "the next distinct boundary is selected after the last copy disappears")
	runner.assert_true(bool(_apply(state, [_change(b, 40.0, 250)], 50, 1).get("ok", false)), "the original owner changes its last earliest cell")
	_check_boundary(runner, state, 200, "the original owner also selects the next distinct boundary")
	runner.assert_eq(restored.snapshot(), state.snapshot(), "restored and uninterrupted states remain identical")

	var swap: Array[Dictionary] = [_change(c, 40.0, 300), _change(d, 40.0, 200)]
	runner.assert_true(bool(_apply(state, swap, 50, 2).get("ok", false)), "a batch replaces and reintroduces the earliest boundary")
	_check_boundary(runner, state, 200, "a same-batch replacement retains the reintroduced boundary")
	runner.assert_true(bool(_apply(state, [_change(d, 40.0, 250)], 50, 1).get("ok", false)), "the reintroduced earliest cell can change")
	_check_boundary(runner, state, 250, "three cells now share the earliest boundary")
	runner.assert_true(bool(_apply(state, [_new_change(f, 20.0, 20.0, 120)], 50, 1).get("ok", false)), "a new cell can introduce an earlier boundary")
	_check_boundary(runner, state, 120, "a newly inserted earlier boundary is visible immediately")
	runner.assert_true(bool(_apply(state, [_change(f, 20.0, 350)], 50, 1).get("ok", false)), "the newly inserted earliest cell can be replaced")
	_check_boundary(runner, state, 250, "removing the inserted minimum reveals the previously shared boundary")
	runner.assert_true(bool(_apply(state, [_change(a, 40.0, 300), _change(b, 40.0, 300)], 50, 2).get("ok", false)), "a batch replaces only part of a shared boundary")
	_check_boundary(runner, state, 250, "an unchanged earliest cell remains visible after a partial batch")
	runner.assert_true(bool(_apply(state, [_change(d, 40.0, 300)], 50, 1).get("ok", false)), "the last copy of the shared boundary changes")
	_check_boundary(runner, state, 300, "the shared later boundary becomes earliest")
	runner.assert_true(bool(_apply(state, [_change(a, 41.0, 300)], 50, 1).get("ok", false)), "a replacement may retain the same boundary")
	_check_boundary(runner, state, 300, "replacing a segment at the same boundary does not alter its count")
	var four: Array[Dictionary] = [_change(a, 40.0, 350), _change(b, 40.0, 350), _change(c, 40.0, 350), _change(d, 40.0, 350)]
	runner.assert_true(bool(_apply(state, four, 50, 4).get("ok", false)), "four of five coincident boundaries move together")
	_check_boundary(runner, state, 300, "the single remaining coincident boundary is retained")
	runner.assert_true(bool(_apply(state, [_change(e, 40.0, 350)], 50, 1).get("ok", false)), "the last coincident boundary moves")
	_check_boundary(runner, state, 350, "all six responses now share their next boundary")

	var before_bad: Dictionary = state.snapshot()
	var malformed: Dictionary = before_bad.duplicate(true)
	malformed.cells[-1].response.target_value = NAN
	runner.assert_true(not state.restore(malformed), "a bad final response rejects a partially built candidate index")
	runner.assert_eq(state.snapshot(), before_bad, "failed restore leaves live segments unchanged")
	_check_boundary(runner, state, 350, "failed restore leaves the live boundary index unchanged")
	var stale: Dictionary = state.prepare_targets([_change(a, 40.0, 400)], 50, 1)
	runner.assert_true(state.restore(before_bad), "restoring the complete snapshot rebuilds the same index")
	runner.assert_true(not bool(state.commit(stale).get("ok", true)), "restore still invalidates the old prepared proof")
	_check_boundary(runner, state, 350, "a stale proof cannot alter the rebuilt boundary index")
	var empty := State.new()
	empty.configure(Vector2i(1, 1), 1, 0)
	runner.assert_true(state.restore(empty.snapshot()), "a valid empty snapshot replaces a populated owner")
	_check_boundary(runner, state, -1, "empty restore clears the previous boundary index")
	runner.assert_true(bool(_apply(state, [_new_change(Vector2i.ZERO, 20.0, 20.0, State.MAX_TIME)], 0, 1).get("ok", false)), "the maximum supported boundary commits after an empty restore")
	_check_boundary(runner, state, State.MAX_TIME, "the maximum supported boundary is not confused with an empty index")
	var immediate := State.new()
	immediate.configure(Vector2i(1, 1), 1, 0)
	runner.assert_true(bool(_apply(immediate, [_new_change(Vector2i.ZERO, 20.0, 20.0, 0)], 0, 1).get("ok", false)), "a boundary at time zero is valid")
	_check_boundary(runner, immediate, 0, "time zero is not confused with an empty index")
	runner.assert_true(bool(_apply(immediate, [_change(Vector2i.ZERO, 20.0, 1)], 0, 1).get("ok", false)), "an immediate boundary can be settled at its own time")
	_check_boundary(runner, immediate, 1, "settling time zero advances the indexed boundary")


func _read_order_and_restore(runner: Object) -> void:
	var state := State.new()
	state.configure(Vector2i(4, 3), 4, 123)
	var first: Array[Dictionary] = [_new_change(Vector2i(3, 2), 17.12345678912345, 50.0, 10_000, 2_000, -0.001), _new_change(Vector2i(0, 0), -100.0, -50.0, 10_000)]
	runner.assert_true(bool(_apply(state, first, 123, 2).get("ok", false)), "two nonadjacent response anchors commit")
	var baseline: Dictionary = state.snapshot()
	var future: Dictionary = state.actual_at(Vector2i(3, 2), 9_000)
	for time: int in [123, 9_000, 124, 5_000, 9_999, 500, 9_000]:
		state.actual_at(Vector2i(3, 2), time)
		state.actual_at(Vector2i.ZERO, time)
	runner.assert_eq(state.snapshot(), baseline, "frequent or out-of-order reads never reanchor actual temperatures")
	runner.assert_eq(state.actual_at(Vector2i(3, 2), 9_000), future, "query order cannot change the same future")
	runner.assert_eq(baseline.cells[0].cell, [0, 0], "snapshot orders cells by y then x")
	runner.assert_eq(baseline.cells[1].cell, [3, 2], "snapshot preserves the other coordinate")
	var saved: Variant = JSON.parse_string(JSON.stringify(baseline, "", true, true))
	var restored := State.new()
	runner.assert_true(restored.restore(saved), "a fresh owner accepts a full-precision snapshot")
	for time: int in [123, 124, 1_000, 5_000, 9_000, 10_000]:
		for cell: Vector2i in [Vector2i.ZERO, Vector2i(3, 2)]:
			runner.assert_eq(restored.actual_at(cell, time), state.actual_at(cell, time), "independent JSON recovery produces the identical future")
	var pending: Dictionary = state.prepare_targets([_change(Vector2i.ZERO, 0.0, 10_000)], 500, 1)
	runner.assert_true(state.restore(saved), "a complete valid snapshot can replace the original state")
	runner.assert_true(not bool(state.commit(pending).get("ok", true)), "restore invalidates an old plan even when its revision is the same")


func _snapshot_rejection(runner: Object) -> void:
	var state := State.new()
	state.configure(Vector2i(4, 2), 4, 10)
	var first: Array[Dictionary] = [_new_change(Vector2i.ZERO, 20.0, 40.0, 1_000), _new_change(Vector2i(1, 0), 20.0, 0.0, 1_000)]
	_apply(state, first, 10, 2)
	var before: Dictionary = state.snapshot()
	var future: Dictionary = state.actual_at(Vector2i.ZERO, 500)
	var bad: Array = [null, [], {}, "state"]
	var malformed: Dictionary = before.duplicate(true)
	malformed.version = 2
	bad.append(malformed)
	malformed = before.duplicate(true)
	malformed.extra = true
	bad.append(malformed)
	malformed = before.duplicate(true)
	malformed.erase("last_change_ms")
	bad.append(malformed)
	malformed = before.duplicate(true)
	malformed.cells.append(malformed.cells[0].duplicate(true))
	bad.append(malformed)
	malformed = before.duplicate(true)
	malformed.cells.reverse()
	bad.append(malformed)
	malformed = before.duplicate(true)
	malformed.cells[0].cell = [4, 0]
	bad.append(malformed)
	malformed = before.duplicate(true)
	malformed.cells[0].erase("response")
	bad.append(malformed)
	malformed = before.duplicate(true)
	malformed.cells[0].response.initial_value = -273.151
	bad.append(malformed)
	malformed = before.duplicate(true)
	malformed.cells[0].response.target_value = NAN
	bad.append(malformed)
	malformed = before.duplicate(true)
	malformed.cells[0].response.target_value = -273.15
	malformed.cells[0].response.target_per_ms = -0.001
	bad.append(malformed)
	malformed = before.duplicate(true)
	malformed.cells[0].response.start_ms = 11
	bad.append(malformed)
	malformed = before.duplicate(true)
	malformed.last_change_ms = 11
	bad.append(malformed)
	malformed = before.duplicate(true)
	malformed.capacity = 1
	bad.append(malformed)
	malformed = before.duplicate(true)
	malformed.revision = 0
	bad.append(malformed)
	for candidate: Variant in bad:
		runner.assert_true(not state.restore(candidate), "a malformed or inconsistent complete snapshot is rejected")
		runner.assert_eq(state.snapshot(), before, "failed restoration never changes the live actual state")
		runner.assert_eq(state.actual_at(Vector2i.ZERO, 500), future, "failed restoration preserves the original future")
