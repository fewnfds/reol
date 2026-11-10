extends RefCounted
## Primary owner checks for scratch-only CPU batches, original-body adoption,
## invalidation and the retained native-interval cursor. No Main assembly.

const Fixtures = preload("res://tests/sim/test_village_simulation.gd")
var _fixtures := Fixtures.new()

class GateChunk extends RefCounted:
	var entered := Semaphore.new()
	var release := Semaphore.new()
	var result: int = 0
	var thread_id: int = 0
	func run() -> void:
		thread_id = OS.get_thread_caller_id()
		entered.post()
		release.wait()
		result = 17

class PendingVillage extends VillageSimulation:
	var ready: bool = false
	var preparations: int = 0
	var commits: int = 0
	var fail_commit: bool = false
	func prepare_actor_advance(_to_ms: int) -> bool:
		preparations += 1
		return ready
	func actor_advance_ready() -> bool:
		return ready
	func next_boundary_ms() -> int:
		return elapsed_ms + 17
	func advance_to_ms(to_ms: int, _max_events: int = 4096) -> bool:
		commits += 1
		if fail_commit:
			return false
		elapsed_ms = to_ms
		return true

class NativeWorld extends RegionalSimulation:
	func _next_boundary(limit_ms: int) -> int:
		return limit_ms

class EnvironmentBudget extends RefCounted:
	func can_settle_at_ms(_at_ms: int) -> bool:
		return true


func run(runner: Object) -> void:
	_scratch_lifetime(runner)
	_native_cursor(runner)
	_original_future(runner)
	_cancel_and_restore(runner)


func _scratch_lifetime(runner: Object) -> void:
	var first := GateChunk.new()
	var second := GateChunk.new()
	var work: Array[RefCounted] = [first, second]
	second.entered = first.entered
	var execution := SimBatchExecution.new()
	execution.start(work, 2)
	# Wait for one real worker, not for two simultaneous workers: CI may have
	# only one available pool thread. No timer/poll or scheduler-dependent race.
	first.entered.wait()
	var worker: int = first.thread_id if first.thread_id != 0 else second.thread_id
	runner.assert_true(worker != 0 and worker != OS.get_thread_caller_id(), "calculation runs outside the owner thread")
	runner.assert_true(not execution.finish(), "an unfinished worker returns pending without blocking the owner")
	execution.cancel()
	first.release.post()
	second.release.post()
	runner.assert_true(execution.finish(true) and execution.cancelled, "cancelled results are collected without reviving publication")
	runner.assert_eq([first.result, second.result], [17, 17], "cancelled scratch work may finish without touching any world owner")


func _native_cursor(runner: Object) -> void:
	var world := NativeWorld.new()
	var first := PendingVillage.new()
	var second := PendingVillage.new()
	world.regions = {"home": first, "river": second}
	world._region_boundaries = {"home": 17, "river": 17}
	world.active_region = "home"
	world.environment_fields = EnvironmentBudget.new()
	world.object_lifecycle = SimObjectLifecycle.new()
	var phases: Array[StringName] = [&"native_interval"]
	world.settlement = SimSettlementKernel.new(phases)
	runner.assert_true(world.settlement.add_step(&"native_actors", &"native_interval", world._settle_native_interval, SimSettlementKernel.CallMode.BUDGETED) and world.settlement.compile(), "native batch work uses the original compiled kernel")
	var manual: Array[int] = [0]
	world.set_manual_motion_executor(func(_from: int, _to: int) -> void: manual[0] += 1)
	var published: Array[int] = []
	world.boundary_settled.connect(func(at_ms: int) -> void: published.append(at_ms))
	runner.assert_true(not world.advance_to_ms(17), "unready independent native batches retain the shared boundary")
	runner.assert_eq([first.preparations, second.preparations], [1, 1], "all independent regions submit before waiting")
	runner.assert_true(world.has_pending_boundary() and not world.accepts_commands(), "partial manual/native state accepts no external command")
	runner.assert_eq(world.settled_ms(), 0, "worker latency never publishes future world time")
	runner.assert_eq(world.pending_boundary_ms(), 17, "continuation retains the exact accepted logical boundary")
	runner.assert_true(world.to_dict().is_empty() and not world.restore({}), "pending native work cannot be captured or overwritten by a bad load")
	runner.assert_true(not world.advance_to_ms(16), "a smaller request cannot publish the retained larger boundary")
	runner.assert_true(not world.advance_to_ms(17), "continuing a pending native batch still waits for its real input")
	runner.assert_eq(manual[0], 1, "manual movement is not replayed across worker continuations")
	first.ready = true
	second.ready = true
	runner.assert_true(world.advance_to_ms(17), "the same native boundary becomes ready when its dependencies finish")
	runner.assert_eq(manual[0], 1, "completion does not repeat manual movement")
	runner.assert_eq([first.commits, second.commits], [1, 1], "each original region submits its completed future once")
	runner.assert_eq(published, [17], "only the complete world boundary is published")
	runner.assert_true(not world.has_pending_boundary() and world.accepts_commands(), "original kernel completion restores command access")
	world.set_manual_motion_executor(Callable())
	first.fail_commit = true
	runner.assert_true(not world.advance_to_ms(34) and world.settlement.has_failed(), "a real native owner failure is a terminal error, not ordinary worker latency")
	runner.assert_eq(world.settled_ms(), 17, "failed native work cannot publish the next logical boundary")
	var commits: int = first.commits
	runner.assert_true(not world.advance_to_ms(34), "a failed native kernel does not replay its domain owner")
	runner.assert_eq(first.commits, commits, "failure retains completed effects without silently retrying them")


func _make(runner: Object, workers: int) -> VillageSimulation:
	var base: VillageSimulation = _fixtures._make_simulation(runner)
	if base == null:
		return null
	var config: Dictionary = base.config.duplicate(true)
	var cells: Dictionary = {}
	for id: String in config.actor_profiles:
		cells[id] = [100, 100]
	for index: int in 64:
		var id: String = "batch_%03d" % index
		config.actor_profiles[id] = {"definition_id": "a_he", "autonomous": false, "hunger": 70.25, "energy": 80.5}
		cells[id] = [100, 100]
	var sim := VillageSimulation.new()
	if not sim.initialize(base._content, config, cells, base.places):
		runner.assert_true(false, "minimal batch village initializes legal definitions, bodies and original ledgers")
		return null
	sim.set_navigation(_fixtures._manhattan_path)
	sim.set_boundary_revision_provider(func() -> int: return 0)
	sim.set_sparse_actor_projection(true)
	if workers >= 0:
		sim.configure_actor_execution(workers)
	for id: String in sim.actor_ids():
		if not sim.submit_action(id, "rest"):
			runner.assert_true(false, "batch body accepts its original route")
			return null
	return sim


func _prepare(sim: VillageSimulation, at_ms: int) -> void:
	sim.prepare_actor_advance(at_ms)
	if sim._prepared_actor_advance != null:
		# Only the synchronous test harness waits. Ordinary runtime returns to
		# GameClock while work is pending and continues on another host frame.
		sim._prepared_actor_advance.execution.finish(true)


func _state(sim: VillageSimulation) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(sim.to_dict(), "", true, true)), "", true, true)


func _original_future(runner: Object) -> void:
	var original: VillageSimulation = _make(runner, -1)
	var serial: VillageSimulation = _make(runner, 0)
	var parallel: VillageSimulation = _make(runner, 4)
	if original == null or serial == null or parallel == null:
		return
	for sim: VillageSimulation in [original, serial, parallel]:
		sim.cancel_action("player", "fixture_haul")
		sim.set_actor_cell("player", SimRouteTravel.cell(sim.places.store.cell))
		runner.assert_true(sim.submit_action("player", "deliver_wood"), "ordinary hauling shares the batched body's original action and reservation")
	var before_wood: int = _fixtures._total_item(original, "wood")
	for _boundary: int in 12:
		var at_ms: int = original.next_boundary_ms()
		for sim: VillageSimulation in [serial, parallel]:
			runner.assert_eq(sim.next_boundary_ms(), at_ms, "batching retains original exact native deadlines")
			_prepare(sim, at_ms)
		for sim: VillageSimulation in [original, serial, parallel]:
			runner.assert_true(sim.advance_to_ms(at_ms), "original native owner commits the complete due set")
		runner.assert_eq(_state(serial), _state(original), "packed serial work preserves the original physical/needs/ledger future")
		runner.assert_eq(_state(parallel), _state(original), "worker completion order preserves the same physical/needs/ledger future")
	runner.assert_true(int(parallel.actor_execution_work.parallel_batches) > 0, "real native work uses the worker backend")
	runner.assert_true(int(parallel.actor_execution_work.adopted) > 0 and int(parallel.actor_execution_work.motion_adopted) > 0, "original bodies actually adopt worker needs and motion results")
	var outside_owner: bool = false
	for id: int in parallel.actor_execution_work.threads:
		outside_owner = outside_owner or id != OS.get_thread_caller_id()
	runner.assert_true(outside_owner, "native adoption is backed by real worker execution")
	for sim: VillageSimulation in [original, serial, parallel]:
		for _boundary: int in 512:
			if not sim.actor_has_action("player"):
				break
			var at_ms: int = sim.next_boundary_ms()
			if sim != original:
				_prepare(sim, at_ms)
			if not sim.advance_to_ms(at_ms):
				break
		runner.assert_true(not sim.actor_has_action("player"), "original hauling reaches its bounded terminal state")
		runner.assert_eq(sim.inventory.quantity("kitchen", "wood"), 3, "original timed hauling delivers once after worker body advancement")
		runner.assert_eq(_fixtures._total_item(sim, "wood"), before_wood, "worker computation cannot copy or consume ledger goods")
		runner.assert_true(sim.inventory.reservations.is_empty(), "original completion releases its only real reservations")
	runner.assert_eq(_state(parallel), _state(original), "the complete hauling future remains equal after worker execution")
	runner.assert_eq(_state(serial), _state(original), "the complete hauling future remains equal after packed serial execution")
	for sim: VillageSimulation in [original, serial, parallel]:
		sim.close_actor_execution()


func _cancel_and_restore(runner: Object) -> void:
	var sim: VillageSimulation = _make(runner, 4)
	var original: VillageSimulation = _make(runner, -1)
	if sim == null or original == null:
		return
	# The opening shortage notice precedes the first group of real crossings.
	for owner: VillageSimulation in [sim, original]:
		owner.advance_to_ms(owner.next_boundary_ms())
	var at_ms: int = sim.next_boundary_ms()
	var checkpoint: Dictionary = sim.to_dict()
	_prepare(sim, at_ms)
	var old: SimActorAdvance = sim._prepared_actor_advance
	runner.assert_true(old != null, "cancellation fixture has a genuine prepared native batch")
	if old == null:
		return
	for owner: VillageSimulation in [sim, original]:
		owner.cancel_action("batch_000", "fixture_cancel")
	runner.assert_true(old.execution.cancelled and sim._prepared_actor_advance == null, "cancelling an original process revokes its old candidate")
	old.execution.finish(true)
	for owner: VillageSimulation in [sim, original]:
		owner.advance_to_ms(at_ms)
	runner.assert_eq(_state(sim), _state(original), "a late cancelled result cannot move or revive the old action")
	runner.assert_true(sim.restore(checkpoint), "valid current snapshot replaces the original native state")
	at_ms = sim.next_boundary_ms()
	_prepare(sim, at_ms)
	old = sim._prepared_actor_advance
	if old == null:
		runner.assert_true(false, "restored owner prepares another real candidate")
		return
	runner.assert_true(not sim.restore({}), "bad candidate load is rejected before changing live state")
	runner.assert_true(sim._prepared_actor_advance == old and not old.execution.cancelled, "failed loading preserves current valid calculation work")
	runner.assert_true(sim.restore(checkpoint), "successful loading replaces the generation even with equal actor IDs")
	runner.assert_true(old.execution.cancelled and sim._prepared_actor_advance == null, "old generation results lose adoption rights after restore")
	old.execution.finish(true)
	runner.assert_eq(_state(sim), JSON.stringify(JSON.parse_string(JSON.stringify(checkpoint, "", true, true)), "", true, true), "late old-world work cannot modify the replacement state")
	sim.close_actor_execution()
	original.close_actor_execution()
