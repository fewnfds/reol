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
	_test_observable_boundaries(runner)
	_test_sparse_actor_projection(runner)
	_test_projection_observers(runner)
	_test_sparse_request_energy(runner)
	_test_reads_do_not_advance(runner)
	_test_due_actor_work(runner)
	_test_invalidation_during_settlement(runner)
	_test_simultaneous_completions(runner)


func _test_reads_do_not_advance(runner: Object) -> void:
	var sim: VillageSimulation = _make(runner)
	if sim == null:
		return
	sim.set_boundary_revision_provider(func() -> int: return 0)
	sim.set_sparse_actor_projection(true)
	runner.assert_true(sim.submit_action("player", "rest") and sim.advance_to_ms(13), "pure-read fixture retains a moving original body between due events")
	var before: Dictionary = sim._actors.duplicate(true)
	var anchors: Dictionary = sim._actor_projection_ms.duplicate()
	var projected: Vector2 = sim.projected_actor_position("player")
	var notices: Array[String] = []
	sim.body_space_changed.connect(func(id: String) -> void: notices.append(id))
	for _read: int in 3:
		sim.actor_state("player")
		var _bodies: Dictionary = sim.actors
	runner.assert_eq(sim._actors, before, "reading a body or its identity map never integrates needs or moves the original body")
	runner.assert_eq(sim._actor_projection_ms, anchors, "queries cannot consume an owner's deferred integration")
	runner.assert_true(notices.is_empty(), "queries cannot emit spatial changes")
	sim.synchronize_actors()
	runner.assert_true(sim._actors.player.position != before.player.position, "an explicit owner barrier integrates the retained route")
	runner.assert_eq(sim.actor_position(sim.actor_state("player")), projected, "pure position evaluation and explicit body integration use one segment formula")
	runner.assert_eq(sim.elapsed_ms, 13, "explicit synchronization retains the existing shared time")


func _test_due_actor_work(runner: Object) -> void:
	var reference: VillageSimulation = _make(runner)
	var indexed: VillageSimulation = _make(runner)
	if reference == null or indexed == null:
		return
	indexed.set_boundary_revision_provider(func() -> int: return 0)
	indexed.set_sparse_actor_projection(true)
	for sim: VillageSimulation in [reference, indexed]:
		runner.assert_true(sim.submit_action("player", "rest") and sim.advance_to_ms(10000), "due-set fixture advances one real route among idle peers")
	_same(runner, reference, indexed, "due actors retain the full original future among nonparticipants")
	runner.assert_true(int(indexed.simulation_work.actor_decision_checks) * 3 < int(reference.simulation_work.actor_decision_checks), "unrelated boundaries do not screen every idle peer for a native decision")


func _test_invalidation_during_settlement(runner: Object) -> void:
	for reversed_ids: bool in [false, true]:
		var reference: VillageSimulation = _make(runner)
		var indexed: VillageSimulation = _make(runner)
		if reference == null or indexed == null:
			return
		var source: String = "player" if reversed_ids else "a_he"
		var target: String = "a_he" if reversed_ids else "player"
		for sim: VillageSimulation in [reference, indexed]:
			var blocked: Array[String] = []
			var owner: WeakRef = weakref(sim)
			sim.set_control_guard(func(id: String, _control: String) -> bool: return not blocked.has(id))
			sim.set_labor_observer(func(stage: String, id: String, _action: Dictionary, _event: String) -> String:
				if stage == "finish" and id == source:
					blocked.append(target)
					owner.get_ref().invalidate_actor_boundary(target)
				return "")
			sim.set_actor_cell(source, SimRouteTravel.cell(sim.places.records.cell))
			sim.set_actor_cell(target, SimRouteTravel.cell(sim.places.dorm.cell))
			runner.assert_true(sim.submit_action(source, "seek_records") and sim.submit_action(target, "rest"), "ordered invalidation starts two original actions")
		indexed.set_boundary_revision_provider(func() -> int: return 0)
		indexed.set_sparse_actor_projection(true)
		for sim: VillageSimulation in [reference, indexed]:
			runner.assert_true(sim.advance_to_ms(60001), "the earlier action completes while its peer's deadline is still ahead")
		runner.assert_eq(indexed.actor_has_action(target), reversed_ids, "a synchronous change reaches only the remaining ID suffix at the same millisecond")
		_same(runner, reference, indexed, "dynamic due-set changes preserve the original full-pass ordering")
		for sim: VillageSimulation in [reference, indexed]:
			sim.advance_to_ms(60002)
		runner.assert_true(not indexed.actor_has_action(target), "an invalidated earlier ID is cancelled at the next causal boundary")
		_same(runner, reference, indexed, "deferred earlier IDs retain the same next-boundary future")


func _test_simultaneous_completions(runner: Object) -> void:
	var sim: VillageSimulation = _make(runner)
	if sim == null:
		return
	for id: String in sim.actor_ids():
		sim.set_actor_cell(id, SimRouteTravel.cell(sim.places.records.cell))
		runner.assert_true(sim.submit_action(id, "seek_records"), "simultaneous completion fixture starts original colocated visits")
	sim.set_boundary_revision_provider(func() -> int: return 0)
	sim.set_sparse_actor_projection(true)
	runner.assert_true(sim.advance_to_ms(1), "all original visits start their timed work at the same millisecond")
	var before: int = int(sim.simulation_work.actor_merge_checks)
	runner.assert_true(sim.advance_to_ms(60001), "all original visits finish at the same causal boundary")
	for id: String in sim.actor_ids():
		runner.assert_true(not sim.actor_has_action(id), "a simultaneous original visit completes once")
	var checks: int = int(sim.simulation_work.actor_merge_checks) - before
	runner.assert_true(checks <= sim.actor_ids().size() * 2, "same-time completions merge only newly invalidated IDs plus the following decision pass, not accumulated prefixes")


func _make(runner: Object, autonomous: bool = false) -> VillageSimulation:
	return _fixtures._make_simulation(runner, autonomous)


func _test_sparse_actor_projection(runner: Object) -> void:
	var eager: VillageSimulation = _make(runner)
	var sparse: VillageSimulation = _make(runner)
	if eager == null or sparse == null:
		return
	var inputs: Array[int] = [20000, 0, 0]
	var crossings: Array = [[], []]
	var ids: Array = eager.actor_ids().slice(0, 3)
	for index: int in 2:
		var sim: VillageSimulation = eager if index == 0 else sparse
		sim.set_exposure_rate(func(_id: String) -> int: return inputs[0])
		sim.set_rest_recovery(func(_id: String) -> int: return inputs[1])
		sim.set_external_labor(func(_id: String) -> bool: return inputs[2] != 0)
		sim.set_boundary_revision_provider(func() -> int: return 0)
		var notices: Array = crossings[index]
		sim.body_cell_crossed.connect(func(id: String, cell: Vector2i, at_ms: int) -> void: notices.append([id, cell.x, cell.y, at_ms]))
		for id: String in ids:
			runner.assert_true(sim.submit_action(id, "rest"), "original native route starts before sparse projection")
	sparse.set_sparse_actor_projection(true)
	for at: int in [13, 50, 200, 1207, 5000]:
		runner.assert_true(eager.advance_to_ms(at) and sparse.advance_to_ms(at), "same exact target accepts eager and sparse bodies")
		runner.assert_eq(sparse.synchronize_actor(str(ids[0])), eager.synchronize_actor(str(ids[0])), "single-body read integrates the original point and needs at %d" % at)
	# Both bodies and old rates settle before a real dependency changes.
	eager.synchronize_actors()
	sparse.synchronize_actors()
	inputs[1] = 3
	inputs[2] = 1
	for sim: VillageSimulation in [eager, sparse]:
		sim.advance_to_ms(5307)
		sim.cancel_action(str(ids[0]), "test_interrupt")
		sim.submit_action(str(ids[0]), "inspect")
		sim.advance_to_ms(9000)
	_same(runner, eager, sparse, "rate changes and cancellation preserve the whole original village")
	runner.assert_eq(crossings[1], crossings[0], "sparse projection never drops or reorders original cell crossings")
	var resumed: VillageSimulation = _make(runner)
	runner.assert_true(resumed.restore(JSON.parse_string(JSON.stringify(sparse.to_dict()))), "materialized sparse snapshot restores without another save format")
	resumed.set_exposure_rate(func(_id: String) -> int: return inputs[0])
	resumed.set_rest_recovery(func(_id: String) -> int: return inputs[1])
	resumed.set_external_labor(func(_id: String) -> bool: return inputs[2] != 0)
	resumed.set_boundary_revision_provider(func() -> int: return 0)
	resumed.set_sparse_actor_projection(true)
	for sim: VillageSimulation in [eager, sparse, resumed]:
		sim.advance_to_ms(800000)
	_same(runner, eager, sparse, "long sparse intervals retain exact saturation, stamina and fractional carries")
	_same(runner, sparse, resumed, "rebuilding transient projection anchors retains the same later future")


func _test_projection_observers(runner: Object) -> void:
	_projection_observers_case(runner, false)
	_projection_observers_case(runner, true)


func _projection_observers_case(runner: Object, sparse_observer: bool) -> void:
	var plain: VillageSimulation = _make(runner)
	var observed: VillageSimulation = _make(runner)
	if plain == null or observed == null:
		return
	var events: Array = [[], []]
	for index: int in 2:
		var sim: VillageSimulation = plain if index == 0 else observed
		var notices: Array = events[index]
		sim.body_cell_crossed.connect(func(id: String, cell: Vector2i, at_ms: int) -> void: notices.append(["cross", id, cell.x, cell.y, at_ms]))
		sim.body_space_changed.connect(func(id: String) -> void: notices.append(["space", id]))
		for id: String in ["a_he", "player"]:
			runner.assert_true(sim.submit_action(id, "rest"), "synchronous observer fixture starts two original moving bodies")
	if sparse_observer:
		observed.set_boundary_revision_provider(func() -> int: return 0)
		observed.set_sparse_actor_projection(true)
	var callback_reads: Array[int] = [0]
	var read_owner: WeakRef = weakref(observed)
	observed.body_cell_crossed.connect(func(_id: String, _cell: Vector2i, _at_ms: int) -> void:
		var bodies: Dictionary = read_owner.get_ref().actors
		callback_reads[0] += bodies.size())
	for at: int in [100, 300, 1700, 4000]:
		plain.advance_to_ms(at)
		observed.advance_to_ms(at)
		_same(runner, plain, observed, "synchronous read cannot repeat eager need integration at %d" % at)
	runner.assert_true(callback_reads[0] > 0, "the actual body crossing signal exercised the read barrier")
	runner.assert_eq(events[1], events[0], "a synchronous observer cannot reorder later original body crossings")


func _test_sparse_request_energy(runner: Object) -> void:
	var eager: VillageSimulation = _make(runner)
	var sparse: VillageSimulation = _make(runner)
	if eager == null or sparse == null:
		return
	for sim: VillageSimulation in [eager, sparse]:
		sim.config.needs.energy_per_minute = 100.0
		sim.set_boundary_revision_provider(func() -> int: return 0)
	sparse.set_sparse_actor_projection(true)
	for sim: VillageSimulation in [eager, sparse]:
		sim.advance_to_ms(20000)
	var reference: Dictionary = eager.request_help("player", "a_he", "sparse_test")
	var result: Dictionary = sparse.request_help("player", "a_he", "sparse_test")
	runner.assert_true(reference.has("context") and result.has("context"), "personal help reaches the real willingness and cached social decision")
	runner.assert_eq(result.get("context", {}), reference.get("context", {}), "internal help uses current integrated energy before quantizing willingness")
	_same(runner, eager, sparse, "help has identical original social outcome and resource reservations")


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


func _test_observable_boundaries(runner: Object) -> void:
	var reference: VillageSimulation = _make(runner)
	var cached: VillageSimulation = _make(runner)
	if reference == null or cached == null:
		return
	var dependency: Array = [0, true, true]
	var calls: Array[int] = [0]
	var step: Callable = func(_cell: Vector2i, _direction: Vector2i) -> bool:
		calls[0] += 1
		return bool(dependency[1])
	for sim: VillageSimulation in [reference, cached]:
		sim.advance_to_ms(1)
		sim.set_navigation(_fixtures._manhattan_path, step)
		sim.set_control_guard(func(_id: String, _channel: String) -> bool: return bool(dependency[2]))
		sim.submit_action("player", "rest")
	cached.set_boundary_revision_provider(func() -> int: return int(dependency[0]))
	var expected: int = reference.next_boundary_ms()
	runner.assert_eq(cached.next_boundary_ms(), expected, "observable native deadlines retain exact crossing time")
	var queried: int = calls[0]
	for _read: int in 20:
		cached.next_boundary_ms()
	runner.assert_eq(calls[0], queried, "unchanged deadlines do not repeat full route geometry checks")
	for at: int in [2, 7, 33, 50, expected]:
		reference.advance_to_ms(at)
		cached.advance_to_ms(at)
		_same(runner, reference, cached, "deadline reuse keeps bodies, needs and observations at %d" % at)
	dependency[1] = false
	dependency[0] += 1
	runner.assert_eq(cached.next_boundary_ms(), reference.next_boundary_ms(), "an obstacle dependency change wakes the original blocked leg")
	dependency[1] = true
	dependency[2] = false
	dependency[0] += 1
	runner.assert_eq(cached.next_boundary_ms(), cached.elapsed_ms + 1, "control loss cannot hide behind a cached future deadline")
	dependency[2] = true
	dependency[0] += 1
	for sim: VillageSimulation in [reference, cached]:
		sim.cancel_action("player")
		sim.submit_action("player", "inspect")
	runner.assert_eq(cached.next_boundary_ms(), reference.next_boundary_ms(), "new commands discard their old deadline")
	var snapshot: Dictionary = cached.to_dict()
	runner.assert_true(cached.restore(snapshot), "the original in-flight format restores without derived deadlines")
	runner.assert_true(cached._actor_boundaries.is_empty(), "restore clears all derived deadline entries")
