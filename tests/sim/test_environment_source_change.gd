extends RefCounted
## Integration of two isolated owners only; this does not exercise Main,
## an inventory transaction, world time, room topology, or a GPU backend.

const SourceChange = preload("res://scripts/sim/environment_source_change.gd")
const Cache = preload("res://scripts/sim/environment_field_cache.gd")
const Temperature = preload("res://scripts/sim/environment_temperature_state.gd")
const SegmentFixture = preload("res://tests/sim/test_environment_temperature_segments.gd")

const MAP_SIZE := Vector2i(20, 1)
const A := Vector2i(1, 0)
const B := Vector2i(17, 0)
const UNRELATED := Vector2i(19, 0)
const HOT := [0, 0, 0, 0, 0, 1000, 0]
const COLD := [0, 0, 0, 0, 0, 0, 1000]
const HORIZON: int = 10_000
const DRIVE_LIMIT: int = 150_000


func run(runner: Object) -> void:
	_candidate_isolation(runner)
	_budgeted_continuity(runner)
	_stale_candidates(runner)
	_rejection_and_release(runner)
	_proof_and_handle_isolation(runner)
	print("SCENARIO isolated environment source changes: owner isolation, continuity, budgets and rollback")


func _fixture(runner: Object, temperature_capacity: int = 20, initial_method: String = "_initial", invalid_neutral: bool = false) -> Dictionary:
	var field := Cache.new()
	var temperature := Temperature.new()
	var coordinator := SourceChange.new()
	var definitions := SegmentFixture.new()
	var climate: Dictionary = definitions._climate()
	if invalid_neutral:
		for region: Dictionary in climate.regions.values():
			region.base_tenths = -1000
			region.daily_curve = [[0, -1000], [1440, -1000]]
			region.seasonal_curve = [[0, -732], [360, -732]]
	var settings: Dictionary = {"climate": climate, "weather": definitions._weather(),
		"weather_epoch_ms": 0, "seed": 42, "tau_ms": 1000, "tide_grid_ms": 10_000}
	var configured: bool = field.configure(MAP_SIZE, 4) and temperature.configure(MAP_SIZE, temperature_capacity, 0)
	if configured:
		configured = coordinator.configure(field, temperature, settings, Callable(self, initial_method))
	runner.assert_true(configured, "isolated field, actual temperature and their coordinator configure")
	if not configured:
		return {}
	return {"field": field, "temperature": temperature, "coordinator": coordinator}


func _initial(_cell: Vector2i, _at_ms: int) -> Dictionary:
	return {"ok": true, "value_c": 20.0}


func _initial_unavailable(_cell: Vector2i, _at_ms: int) -> Dictionary:
	return {"ok": false, "reason": "no_actual_history"}


func _initial_wrong_status(_cell: Vector2i, _at_ms: int) -> Dictionary:
	return {"ok": "false", "value_c": 20.0}


func _initial_below_absolute_zero(_cell: Vector2i, _at_ms: int) -> Dictionary:
	return {"ok": true, "value_c": -300.0}


func _source(cell: Vector2i, channels: Array) -> Dictionary:
	return {"cell": cell, "radius": 1, "channels": channels.duplicate()}


func _revision(field: RefCounted) -> Array:
	var info: Dictionary = field.diagnostics()
	return [info.source_count, info.revision]


func _begin(runner: Object, coordinator: RefCounted, slot: int, operation: String, source: Dictionary, at_ms: int) -> Dictionary:
	var result: Dictionary = coordinator.begin(slot, operation, source, at_ms, HORIZON)
	runner.assert_true(bool(result.get("ok", false)), "a valid isolated source candidate begins: " + str(result))
	return result


func _drive(runner: Object, context: Dictionary, handle: Variant, budget: int, at_ms: int, extra_reads: bool = false) -> Dictionary:
	var coordinator: RefCounted = context.coordinator
	var field: RefCounted = context.field
	var temperature: RefCounted = context.temperature
	var within_budget: bool = true
	for iteration: int in DRIVE_LIMIT:
		var result: Dictionary = coordinator.step(handle, budget, budget)
		if not bool(result.get("ok", false)):
			runner.assert_true(within_budget, "all successful source and temperature steps respected their budgets")
			return result
		within_budget = within_budget and int(result.get("field_work", -1)) >= 0 and int(result.get("field_work", -1)) <= budget
		within_budget = within_budget and int(result.get("cells", -1)) >= 0 and int(result.get("cells", -1)) <= budget
		if extra_reads and iteration % 101 == 0:
			temperature.actual_at(A, at_ms)
			field.read_base(UNRELATED)
		if not bool(result.get("pending", true)):
			runner.assert_true(within_budget, "all source and temperature steps respected their budgets")
			return result
	runner.assert_true(false, "bounded source preparation reaches a result before the iteration limit")
	return {"ok": false, "reason": "drive_limit"}


func _seal(runner: Object, context: Dictionary, handle: Variant, budget: int, at_ms: int, extra_reads: bool = false) -> Dictionary:
	var ready: Dictionary = _drive(runner, context, handle, budget, at_ms, extra_reads)
	if not bool(ready.get("ok", false)):
		runner.assert_true(false, "valid isolated source preparation reaches ready: " + str(ready))
		return ready
	var result: Dictionary = context.coordinator.finish(handle)
	runner.assert_true(bool(result.get("ok", false)), "a ready source candidate produces a proof")
	return result


func _publish(runner: Object, context: Dictionary, slot: int, operation: String, source: Dictionary, at_ms: int, budget: int, extra_reads: bool = false) -> Dictionary:
	var coordinator: RefCounted = context.coordinator
	var opened: Dictionary = _begin(runner, coordinator, slot, operation, source, at_ms)
	if not bool(opened.get("ok", false)):
		return opened
	var sealed: Dictionary = _seal(runner, context, opened.handle, budget, at_ms, extra_reads)
	if not bool(sealed.get("ok", false)):
		return sealed
	var preflight: Dictionary = coordinator.can_commit(sealed.proof)
	runner.assert_true(bool(preflight.get("ok", false)), "a complete source and temperature candidate preflights")
	if not bool(preflight.get("ok", false)):
		return preflight
	var result: Dictionary = coordinator.commit(sealed.proof)
	runner.assert_true(bool(result.get("ok", false)), "both isolated owners publish their candidate")
	if bool(result.get("ok", false)):
		runner.assert_true(not bool(coordinator.commit(sealed.proof).get("ok", true)), "a consumed source proof cannot be replayed")
	return result


func _actual(runner: Object, temperature: RefCounted, cell: Vector2i, at_ms: int) -> float:
	var result: Dictionary = temperature.actual_at(cell, at_ms)
	runner.assert_true(bool(result.get("ok", false)), "actual temperature can be sampled at the requested time: " + str(result))
	return float(result.get("value_c", NAN))


func _target(temperature: RefCounted, cell: Vector2i) -> float:
	for row: Dictionary in temperature.snapshot().cells:
		if row.cell == [cell.x, cell.y]:
			return float(row.response.target_value)
	return NAN


func _read_field(runner: Object, field: RefCounted, cell: Vector2i) -> PackedInt32Array:
	var result: Dictionary = field.read_base(cell)
	for _attempt: int in 8:
		if not bool(result.get("ok", false)) or not bool(result.get("pending", true)):
			break
		field.rebuild(1, Cache.MAX_WORK)
		result = field.read_base(cell)
	var available: bool = bool(result.get("ok", false)) and not bool(result.get("pending", true))
	runner.assert_true(available, "the requested live source-field tile is available")
	return result.channels if available else PackedInt32Array()


func _candidate_isolation(runner: Object) -> void:
	var context: Dictionary = _fixture(runner)
	if context.is_empty():
		return
	var coordinator: RefCounted = context.coordinator
	var field: RefCounted = context.field
	var temperature: RefCounted = context.temperature
	var before_field: Array = _revision(field)
	var before_temperature: Dictionary = temperature.snapshot()
	var opened: Dictionary = _begin(runner, coordinator, 0, "set", _source(A, HOT), 0)
	if not bool(opened.get("ok", false)):
		return
	var handle: Variant = opened.handle
	runner.assert_eq(coordinator.begin(0, "set", _source(A, HOT), 0, HORIZON).get("reason"), "busy", "a second begin cannot replace a private candidate")
	runner.assert_eq(coordinator.finish(handle).get("reason"), "pending", "a candidate cannot finish before preparation")
	for invalid: Array in [[0, 1], [Cache.MAX_WORK + 1, 1], [1, -1], [1, 257]]:
		runner.assert_eq(coordinator.step(handle, invalid[0], invalid[1]).get("reason"), "work_budget", "invalid work limits leave the candidate intact")
	var partial: Dictionary = coordinator.step(handle, 1, 0)
	runner.assert_true(bool(partial.get("ok", false)) and bool(partial.get("pending", false)), "a partial budget leaves work pending")
	runner.assert_eq(_revision(field), before_field, "begin and partial work do not publish a source")
	runner.assert_eq(temperature.snapshot(), before_temperature, "begin and partial work do not publish temperature anchors")
	var sealed: Dictionary = _seal(runner, context, handle, 17, 0)
	if not bool(sealed.get("ok", false)):
		return
	runner.assert_true(bool(coordinator.can_commit(sealed.proof).get("ok", false)), "preflight accepts a complete candidate")
	runner.assert_eq(_revision(field), before_field, "ready and preflight still leave the live source unchanged")
	runner.assert_eq(temperature.snapshot(), before_temperature, "ready and preflight still leave live temperature unchanged")
	runner.assert_true(bool(coordinator.cancel(handle).get("ok", false)), "a completed candidate can be cancelled")
	runner.assert_true(not bool(coordinator.commit(sealed.proof).get("ok", true)), "a cancelled candidate proof cannot commit")
	runner.assert_eq(_revision(field), before_field, "cancellation never publishes a field source")
	runner.assert_eq(temperature.snapshot(), before_temperature, "cancellation never publishes temperature")
	var retry: Dictionary = _begin(runner, coordinator, 0, "set", _source(A, HOT), 0)
	if bool(retry.get("ok", false)):
		runner.assert_true(bool(coordinator.cancel(retry.handle).get("ok", false)), "both owners are available after cancellation")


func _budgeted_continuity(runner: Object) -> void:
	var expected: Dictionary = {}
	for budget: int in [1, 17, 256]:
		var result: Dictionary = _sequence(runner, budget, budget == 1)
		if result.is_empty():
			return
		if expected.is_empty():
			expected = result
		else:
			runner.assert_eq(result, expected, "budget and extra read partitioning preserve the same fields, anchors and future")


func _sequence(runner: Object, budget: int, extra_reads: bool) -> Dictionary:
	var context: Dictionary = _fixture(runner)
	if context.is_empty():
		return {}
	var field: RefCounted = context.field
	var temperature: RefCounted = context.temperature
	if not bool(_publish(runner, context, 0, "set", _source(A, HOT), 0, budget, extra_reads).get("ok", false)):
		return {}
	if extra_reads:
		var pending: Dictionary = field.read_base(UNRELATED)
		runner.assert_true(bool(pending.get("pending", false)), "an unrelated request queued during a candidate is not discarded on commit")
		var unrelated: PackedInt32Array = _read_field(runner, field, UNRELATED)
		runner.assert_eq(unrelated, PackedInt32Array([0, 0, 0, 0, 0, 0, 0]), "the unrelated queued tile can subsequently rebuild")
	var old_at_move: float = _actual(runner, temperature, A, 1000)
	runner.assert_true(old_at_move > 20.0, "the first heat source warms its actual cell over time")
	if not bool(_publish(runner, context, 0, "set", _source(B, HOT), 1000, budget, extra_reads).get("ok", false)):
		return {}
	runner.assert_eq(_actual(runner, temperature, A, 1000), old_at_move, "moving a heat source leaves the old actual temperature continuous")
	runner.assert_eq(_actual(runner, temperature, B, 1000), 20.0, "the new cell starts from its authority-provided actual temperature")
	var new_target: float = _target(temperature, B)
	runner.assert_true(is_finite(new_target) and new_target > 20.0, "the new position receives the heat field target")
	var a_at_cold: float = _actual(runner, temperature, A, 2000)
	var b_at_cold: float = _actual(runner, temperature, B, 2000)
	runner.assert_true(absf(a_at_cold - (20.0 + (old_at_move - 20.0) * exp(-1.0))) < 0.0000001, "the abandoned position relaxes toward its 20 C climate")
	runner.assert_true(absf(b_at_cold - (new_target + (20.0 - new_target) * exp(-1.0))) < 0.0000001, "the new position gradually approaches its actual compiled target")
	if not bool(_publish(runner, context, 1, "set", _source(B, COLD), 2000, budget, extra_reads).get("ok", false)):
		return {}
	runner.assert_eq(_actual(runner, temperature, B, 2000), b_at_cold, "adding a cold source changes the target without a temperature jump")
	var equal_sources: PackedInt32Array = _read_field(runner, field, B)
	if equal_sources.size() != 7:
		return {}
	runner.assert_eq([equal_sources[5], equal_sources[6]], [1000, 1000], "independent hot and cold channels retain equal source strengths")
	runner.assert_eq(_target(temperature, B), 20.0, "equal hot and cold grades restore the neutral target")
	var b_after_cold: float = _actual(runner, temperature, B, 3000)
	runner.assert_true(absf(b_after_cold - (20.0 + (b_at_cold - 20.0) * exp(-1.0))) < 0.0000001, "the neutralized cell relaxes toward climate rather than resetting instantly")
	if not bool(_publish(runner, context, 1, "remove", {}, 3000, budget, extra_reads).get("ok", false)):
		return {}
	runner.assert_eq(_actual(runner, temperature, B, 3000), b_after_cold, "removing a source also preserves actual temperature at the event")
	var b_after_removal: float = _actual(runner, temperature, B, 4000)
	runner.assert_true(b_after_removal > b_after_cold, "removing the cold source lets the remaining heat take effect")
	return {"snapshot": temperature.snapshot(), "a": _actual(runner, temperature, A, 4000),
		"b": b_after_removal, "field_a": _read_field(runner, field, A),
		"field_b": _read_field(runner, field, B)}


func _stale_candidates(runner: Object) -> void:
	var context: Dictionary = _fixture(runner)
	if context.is_empty():
		return
	var coordinator: RefCounted = context.coordinator
	var field: RefCounted = context.field
	var temperature: RefCounted = context.temperature
	var opened: Dictionary = _begin(runner, coordinator, 0, "set", _source(A, HOT), 0)
	if not bool(opened.get("ok", false)):
		return
	var sealed: Dictionary = _seal(runner, context, opened.handle, 256, 0)
	if not bool(sealed.get("ok", false)):
		return
	var old_temperature: Dictionary = temperature.snapshot()
	var external: Dictionary = field.set_source(1, B, 1, COLD)
	runner.assert_true(bool(external.get("ok", false)), "a separate source mutation changes the field revision")
	var after_external: Array = _revision(field)
	runner.assert_true(not bool(coordinator.can_commit(sealed.proof).get("ok", true)), "an externally changed field rejects preflight")
	runner.assert_true(not bool(coordinator.commit(sealed.proof).get("ok", true)), "an externally changed field rejects commit")
	runner.assert_eq(_revision(field), after_external, "a stale candidate cannot overwrite the independent field mutation")
	runner.assert_eq(temperature.snapshot(), old_temperature, "a stale field never publishes its temperature candidate")
	runner.assert_true(bool(coordinator.cancel(opened.handle).get("ok", false)), "a stale field candidate can be released")
	var retry: Dictionary = _begin(runner, coordinator, 0, "set", _source(A, HOT), 0)
	if bool(retry.get("ok", false)):
		coordinator.cancel(retry.handle)

	context = _fixture(runner)
	if context.is_empty():
		return
	coordinator = context.coordinator
	field = context.field
	temperature = context.temperature
	var before_field: Array = _revision(field)
	var before_temperature: Dictionary = temperature.snapshot()
	opened = _begin(runner, coordinator, 0, "set", _source(A, HOT), 0)
	if not bool(opened.get("ok", false)):
		return
	sealed = _seal(runner, context, opened.handle, 256, 0)
	if not bool(sealed.get("ok", false)):
		return
	runner.assert_true(temperature.restore(before_temperature), "the same-revision temperature state can be restored")
	runner.assert_eq(coordinator.can_commit(sealed.proof).get("reason"), "temperature_stale", "restore invalidates a sealed candidate even at the same numeric revision")
	runner.assert_true(not bool(coordinator.commit(sealed.proof).get("ok", true)), "an invalidated temperature proof cannot publish either owner")
	runner.assert_eq(_revision(field), before_field, "temperature restore never publishes the field candidate")
	runner.assert_eq(temperature.snapshot(), before_temperature, "same-revision restore preserves the original temperature snapshot")
	runner.assert_true(bool(coordinator.cancel(opened.handle).get("ok", false)), "the coordinator releases the other owner after restore")


func _rejection_and_release(runner: Object) -> void:
	var cases: Array[Dictionary] = [
		{"capacity": 20, "initial": "_initial_unavailable", "bad_climate": false, "reason": "initial_unavailable"},
		{"capacity": 20, "initial": "_initial_wrong_status", "bad_climate": false, "reason": "initial_unavailable"},
		{"capacity": 20, "initial": "_initial_below_absolute_zero", "bad_climate": false, "reason": "initial_out_of_range"},
		{"capacity": 20, "initial": "_initial", "bad_climate": true, "reason": "neutral_out_of_range"},
		{"capacity": 1, "initial": "_initial", "bad_climate": false, "reason": "capacity"},
	]
	for example: Dictionary in cases:
		var context: Dictionary = _fixture(runner, example.capacity, example.initial, example.bad_climate)
		if context.is_empty():
			return
		var coordinator: RefCounted = context.coordinator
		var field: RefCounted = context.field
		var temperature: RefCounted = context.temperature
		var before_field: Array = _revision(field)
		var before_temperature: Dictionary = temperature.snapshot()
		var opened: Dictionary = _begin(runner, coordinator, 0, "set", _source(A, HOT), 0)
		if not bool(opened.get("ok", false)):
			return
		var result: Dictionary = _drive(runner, context, opened.handle, 256, 0)
		runner.assert_eq(result.get("reason"), example.reason, "invalid actual input or target rejects the complete candidate")
		runner.assert_eq(_revision(field), before_field, "failed input cannot publish its source")
		runner.assert_eq(temperature.snapshot(), before_temperature, "failed input cannot publish any temperature cell")
		var retry: Dictionary = _begin(runner, coordinator, 0, "set", _source(A, HOT), 0)
		if bool(retry.get("ok", false)):
			runner.assert_true(bool(coordinator.cancel(retry.handle).get("ok", false)), "failed preparation releases both private candidates")

	var context: Dictionary = _fixture(runner)
	if context.is_empty():
		return
	var coordinator: RefCounted = context.coordinator
	var field: RefCounted = context.field
	var temperature: RefCounted = context.temperature
	var before_field: Array = _revision(field)
	var before_temperature: Dictionary = temperature.snapshot()
	var busy: Dictionary = temperature.begin_bulk(0, 1)
	runner.assert_true(bool(busy.get("ok", false)), "an independent temperature transaction can be active")
	if not bool(busy.get("ok", false)):
		return
	runner.assert_eq(coordinator.begin(0, "set", _source(A, HOT), 0, HORIZON).get("reason"), "busy", "a busy temperature owner rejects coordination")
	runner.assert_eq(_revision(field), before_field, "busy rejection does not publish the field")
	runner.assert_eq(temperature.snapshot(), before_temperature, "busy rejection does not publish temperature")
	runner.assert_true(bool(temperature.cancel_bulk(busy.handle).get("ok", false)), "the independent temperature transaction remains cancelable")
	var retry: Dictionary = _begin(runner, coordinator, 0, "set", _source(A, HOT), 0)
	if bool(retry.get("ok", false)):
		runner.assert_true(bool(coordinator.cancel(retry.handle).get("ok", false)), "failed busy begin released its field candidate")


func _proof_and_handle_isolation(runner: Object) -> void:
	var left: Dictionary = _fixture(runner)
	var right: Dictionary = _fixture(runner)
	if left.is_empty() or right.is_empty():
		return
	var left_coordinator: RefCounted = left.coordinator
	var right_coordinator: RefCounted = right.coordinator
	var left_field: Array = _revision(left.field)
	var right_field: Array = _revision(right.field)
	var left_temperature: Dictionary = left.temperature.snapshot()
	var right_temperature: Dictionary = right.temperature.snapshot()
	var l: Dictionary = _begin(runner, left_coordinator, 0, "set", _source(A, HOT), 0)
	var r: Dictionary = _begin(runner, right_coordinator, 0, "set", _source(B, COLD), 0)
	if not bool(l.get("ok", false)) or not bool(r.get("ok", false)):
		return
	runner.assert_eq(left_coordinator.step(r.handle, 1, 1).get("reason"), "invalid_handle", "a handle from another coordinator cannot advance this candidate")
	runner.assert_eq(left_coordinator.cancel(r.handle).get("reason"), "invalid_handle", "a foreign handle cannot cancel this candidate")
	var lp: Dictionary = _seal(runner, left, l.handle, 256, 0)
	var rp: Dictionary = _seal(runner, right, r.handle, 256, 0)
	if not bool(lp.get("ok", false)) or not bool(rp.get("ok", false)):
		return
	runner.assert_true(not bool(left_coordinator.can_commit(rp.proof).get("ok", true)), "a proof cannot be preflighted by another coordinator")
	runner.assert_true(not bool(left_coordinator.commit(rp.proof).get("ok", true)), "a proof cannot be committed by another coordinator")
	runner.assert_eq(_revision(left.field), left_field, "foreign proofs do not change the first source owner")
	runner.assert_eq(_revision(right.field), right_field, "foreign proofs do not change the second source owner")
	runner.assert_eq(left.temperature.snapshot(), left_temperature, "foreign proofs do not change the first temperature owner")
	runner.assert_eq(right.temperature.snapshot(), right_temperature, "foreign proofs do not change the second temperature owner")
	runner.assert_true(bool(left_coordinator.cancel(l.handle).get("ok", false)), "the first sealed candidate can be cancelled")
	runner.assert_true(bool(right_coordinator.cancel(r.handle).get("ok", false)), "the second sealed candidate can be cancelled")
	runner.assert_true(not bool(left_coordinator.commit(lp.proof).get("ok", true)), "a cancelled proof is invalid")
	runner.assert_true(not bool(right_coordinator.commit(rp.proof).get("ok", true)), "a second cancelled proof is invalid")
