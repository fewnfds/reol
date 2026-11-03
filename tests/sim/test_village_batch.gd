extends RefCounted
## Coarse execution must skip quiet time while preserving detailed rule results.

const Fixtures = preload("res://tests/sim/test_village_simulation.gd")
var _fixtures: RefCounted = Fixtures.new()


func run(runner: Object) -> void:
	_test_idle_skips_minutes(runner)
	_test_action_boundaries_match_fine(runner)
	_test_autonomous_days_match_fine(runner)
	_test_budget_preserves_pending_time(runner)
	_test_external_change_interrupts_prediction(runner)
	_test_inflight_restore_and_mode_switch(runner)
	_test_single_minute_targets_match_fine(runner)


func _make(runner: Object, autonomous: bool = false) -> VillageSimulation:
	return _fixtures._make_simulation(runner, autonomous)


func _state(sim: VillageSimulation) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(sim.to_dict(), "", true, true)), "", true, true)


func _same(runner: Object, fine: VillageSimulation, coarse: VillageSimulation, label: String) -> void:
	runner.assert_eq(_state(coarse).hash(), _state(fine).hash(), label)


func _step_to(sim: VillageSimulation, target: int) -> void:
	while sim.tick_index < target:
		sim.step()


func _test_idle_skips_minutes(runner: Object) -> void:
	var fine: VillageSimulation = _make(runner)
	var coarse: VillageSimulation = _make(runner)
	if fine == null or coarse == null:
		return
	_step_to(fine, 1440)
	runner.assert_true(coarse.advance_to(1440), "coarse idle village reaches one day")
	_same(runner, fine, coarse, "idle batched needs, observations and shortage timestamps match fine")
	runner.assert_true(int(coarse.simulation_work.batched_minutes) > 1300, "quiet village batches most minutes")
	runner.assert_true(int(coarse.simulation_work.step_count) < 30, "idle simulation does not replay every minute")


func _test_action_boundaries_match_fine(runner: Object) -> void:
	for action_id: String in ["deliver_wood", "rest", "eat", "inspect"]:
		var fine: VillageSimulation = _make(runner)
		var coarse: VillageSimulation = _make(runner)
		if fine == null or coarse == null:
			return
		runner.assert_true(fine.submit_action("player", action_id), "fine action starts: " + action_id)
		runner.assert_true(coarse.submit_action("player", action_id), "coarse action starts: " + action_id)
		for target: int in [2, 7, 23, 55, 123, 200]:
			_step_to(fine, target)
			runner.assert_true(coarse.advance_to(target), "coarse reaches partial target for " + action_id)
			_same(runner, fine, coarse, "travel, pickup, work and finish match: %s at %d" % [action_id, target])


func _test_autonomous_days_match_fine(runner: Object) -> void:
	var fine: VillageSimulation = _make(runner, true)
	var coarse: VillageSimulation = _make(runner, true)
	if fine == null or coarse == null:
		return
	for target: int in [61, 457, 1440, 4320]:
		_step_to(fine, target)
		runner.assert_true(coarse.advance_to(target, 10000), "coarse autonomous village reaches %d" % target)
		_same(runner, fine, coarse, "autonomous supply, relations, reservations and RNG match at %d" % target)
	runner.assert_true(int(coarse.simulation_work.batched_minutes) > 1000, "busy village also batches quiet minutes")
	print("  village coarse: %d minute steps, %d batched minutes over %d game minutes" % [
		int(coarse.simulation_work.step_count), int(coarse.simulation_work.batched_minutes), coarse.tick_index,
	])


func _test_budget_preserves_pending_time(runner: Object) -> void:
	var fine: VillageSimulation = _make(runner, true)
	var coarse: VillageSimulation = _make(runner, true)
	if fine == null or coarse == null:
		return
	runner.assert_true(not coarse.advance_to(1440, 0), "zero event budget cannot discard time")
	runner.assert_eq(coarse.tick_index, 0, "zero budget leaves current time unchanged")
	runner.assert_true(not coarse.advance_to(1440, 1), "one event leaves a busy day pending")
	runner.assert_true(coarse.elapsed_ms > 0 and coarse.elapsed_ms < 1440 * 60000, "partial advance records actual progress")
	var attempts: int = 0
	while coarse.tick_index < 1440 and attempts < 5000:
		coarse.advance_to(1440, 1)
		attempts += 1
	_step_to(fine, 1440)
	_same(runner, fine, coarse, "resuming a bounded backlog loses no minutes or events")
	runner.assert_true(not coarse.advance_to(1400), "cannot rewrite committed past")
	runner.assert_true(coarse.advance_to(1440, 0), "repeating already settled target is idempotent")


func _test_external_change_interrupts_prediction(runner: Object) -> void:
	var fine: VillageSimulation = _make(runner)
	var coarse: VillageSimulation = _make(runner)
	if fine == null or coarse == null:
		return
	_step_to(fine, 20)
	coarse.advance_to(20)
	for sim: VillageSimulation in [fine, coarse]:
		sim.inventory.containers.kitchen.wood = 10
	runner.assert_eq(coarse.next_boundary_tick(), 21, "incoming stock wakes unresolved shortage at next rule tick")
	_step_to(fine, 70)
	coarse.advance_to(70)
	_same(runner, fine, coarse, "external delivery invalidates old shortage prediction")
	runner.assert_eq(coarse.situations.kitchen_shortage.status, "resolved", "shortage resolves before later request")


func _test_inflight_restore_and_mode_switch(runner: Object) -> void:
	var original: VillageSimulation = _make(runner)
	var restored: VillageSimulation = _make(runner)
	if original == null or restored == null:
		return
	original.submit_action("player", "deliver_wood")
	original.advance_to(11)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(original.to_dict()))
	runner.assert_true(restored.restore(snapshot), "batched in-flight state survives JSON restore")
	for target: int in [16, 31, 70, 120]:
		if target % 2 == 0:
			_step_to(original, target)
			restored.advance_to(target)
		else:
			original.advance_to(target)
			_step_to(restored, target)
		_same(runner, original, restored, "mode switching does not reset work at %d" % target)


func _test_single_minute_targets_match_fine(runner: Object) -> void:
	var fine: VillageSimulation = _make(runner, true)
	var coarse: VillageSimulation = _make(runner, true)
	if fine == null or coarse == null:
		return
	for target in range(1, 121):
		fine.step()
		while not coarse.advance_to(target, 1):
			pass
	_same(runner, fine, coarse, "minute-at-a-time scheduler remains equivalent")
