extends RefCounted
## Synchronous ground-cache scheduler contracts. Hardware GPU execution is
## tested separately by tools/qa/environment_ground_compute.gd.

const LifecycleFixture = preload("res://tests/sim/test_object_lifecycle.gd")
const SourceFixture = preload("res://tests/sim/test_environment_source_bindings.gd")
const Definitions = preload("res://scripts/data/environment_source_definitions.gd")
const Bindings = preload("res://scripts/sim/environment_source_bindings.gd")
const GroundCache = preload("res://scripts/sim/environment_ground_cache.gd")
const FieldCache = preload("res://scripts/sim/environment_field_cache.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const Compute = preload("res://scripts/runtime/environment_field_compute_runtime.gd")

var fixture := LifecycleFixture.new()
var source_fixture := SourceFixture.new()


func run(runner: Object) -> void:
	_cpu_real_sources(runner)
	_untracked_inventory(runner)
	_replaced_owner(runner)
	print("SCENARIO ground compute: real sources, resumable CPU requests, mutation and owner invalidation")


## Shared by the asynchronous native GPU QA, which retains this fixture for
## the lifetime of its original world and supplies the same runner assertions.
func setup(runner: Object) -> Dictionary:
	var world: RegionalSimulation = fixture._world(runner)
	if world == null:
		return {}
	var inventory: SimInventory = world.regions.home.inventory
	inventory.containers.store.wood = 10000
	var requests: Array[Dictionary] = [
		fixture._spawn("compute_slab", "compute_slab_item", "stone_slab", [15, 12]),
		fixture._spawn("compute_edge", "compute_edge_item", "plain_slate", [1, 1]),
		fixture._transfer("compute_hot", fixture._location("store"), fixture._ground(14, 15), "wood", 1),
		fixture._transfer("compute_cold", fixture._location("kitchen"), fixture._ground(16, 14), "grain", 1),
		fixture._transfer("compute_weak", fixture._location("garden"), fixture._ground(18, 15), "herb", 1),
	]
	for request: Dictionary in requests:
		var result: Dictionary = world.object_lifecycle.execute(request)
		if not _ok(runner, bool(result.get("ok", false)), "real source setup " + str(request.command) + ": " + str(result)):
			return {}
	var raw: Dictionary = source_fixture._definitions()
	raw.profiles.earth.radius_cells = 2
	raw.profiles.hot.radius_cells = 8
	raw.profiles.cold.radius_cells = 16
	raw.profiles.weak.radius_cells = 4
	raw.profiles.earth.elements.wood = 101
	raw.profiles.earth.elements.water = 303
	raw.profiles.hot.elements.metal = 711
	raw.profiles.cold.elements.water = 2200
	raw.profiles.weak.elements.wood = 1300
	var definitions: RefCounted = Definitions.new()
	var query: RefCounted = Bindings.new()
	var ground: RefCounted = GroundCache.new()
	if not _ok(runner, definitions.configure(raw) and query.configure(world, definitions) and ground.configure(world, definitions), "real-world ground cache and independent source query configure"):
		return {}
	for _i: int in 10000:
		var progress: Dictionary = ground.advance(65536, 100000)
		if not _ok(runner, bool(progress.get("ok", false)), "ground source assembly succeeds: " + str(progress)):
			ground.close()
			return {}
		if str(progress.get("state", "")) == "ready" and int(progress.get("pending_sources", -1)) == 0:
			return {"world": world, "ground": ground, "query": query, "definitions": definitions}
	_ok(runner, false, "ground source assembly completes within its iteration bound")
	ground.close()
	return {}


func _cpu_real_sources(runner: Object) -> void:
	var data: Dictionary = setup(runner)
	if data.is_empty():
		return
	var world: RegionalSimulation = data.world
	var ground: RefCounted = data.ground
	var oracle: RefCounted = data.query
	var service := Compute.new()
	if not _ok(runner, service.configure(ground, "cpu"), "CPU scheduler binds the real ground cache"):
		ground.close()
		return
	var start_time: int = world.elapsed_ms
	var area := Rect2i(0, 0, 32, 32)
	var started: Dictionary = service.request(area)
	if not _ok(runner, bool(started.get("ok", false)) and bool(started.get("pending", false)) and str(started.get("backend", "")) == "cpu", "CPU request starts with a real original source snapshot: " + str(started)):
		service.close()
		ground.close()
		return
	runner.assert_true(not service.close(), "active request cannot be abandoned by close")
	runner.assert_true(not bool(service.request(area).get("ok", true)), "active scheduler refuses a second request")
	var step: Dictionary = service.poll(1, 1)
	runner.assert_true(bool(step.get("ok", false)) and bool(step.get("pending", false)), "one tiny work slice cannot present the multi-tile request as complete")
	var pending: Dictionary = ground.read_base(Vector2i(14, 15))
	runner.assert_true(bool(pending.get("pending", false)) and not pending.has("elements") and not pending.has("thermal_grade"), "a pending source field never exposes partial values")
	var completed: Dictionary = _drain(runner, service)
	if bool(completed.get("ok", false)) and not bool(completed.get("pending", true)):
		_compare_area(runner, ground, oracle, area, "CPU original sources")
	var before: Dictionary = ground.read_base(Vector2i(14, 15))
	var grow: Dictionary = world.object_lifecycle.execute(fixture._transfer("compute_grow", fixture._location("store"), fixture._ground(14, 15), "wood", 9999))
	runner.assert_true(bool(grow.get("ok", false)), "a real material pile grows from one to ten thousand")
	runner.assert_eq(world.regions.home.inventory.quantity("ground:compute_hot", "wood"), 10000, "real inventory owns the expanded material pile")
	runner.assert_eq(ground.read_base(Vector2i(14, 15)), before, "the same pile has the same influence regardless of quantity")
	var again: Dictionary = service.request(area)
	if _ok(runner, bool(again.get("ok", false)), "a second CPU calculation starts"):
		var first: Dictionary = service.poll(1, 1)
		runner.assert_true(bool(first.get("ok", false)), "the second calculation accepts a bounded work slice")
		var moved: Dictionary = world.object_lifecycle.execute(fixture._move("compute_hold", "compute_edge_item", fixture._location("ground:compute_edge"), fixture._location("actor:player")))
		runner.assert_true(bool(moved.get("ok", false)), "the original artifact can move during a CPU request")
		var after_move: Dictionary = ground.read_base(Vector2i(1, 1))
		runner.assert_true(bool(after_move.get("pending", false)) and not after_move.has("elements"), "movement immediately hides the old original-source target")
		var latest: Dictionary = _drain(runner, service)
		if bool(latest.get("ok", false)) and not bool(latest.get("pending", true)):
			_compare_area(runner, ground, oracle, area, "CPU after real object move")
	var cancelled: Dictionary = service.request(area)
	if _ok(runner, bool(cancelled.get("ok", false)), "a third request can be cancelled"):
		var ticket: int = int(cancelled.ticket)
		runner.assert_true(bool(service.cancel(ticket).get("ok", false)), "cancellation accepts the current ticket")
		runner.assert_true(not service.close(), "close waits for a cancelled request to be reaped")
		var terminal: Dictionary = service.poll(1, 10)
		runner.assert_true(bool(terminal.get("ok", false)) and not bool(terminal.get("pending", true)) and bool(terminal.get("cancelled", false)), "cancelled CPU request becomes terminal")
	if RenderingServer.get_rendering_device() == null:
		runner.assert_true(service.set_mode("gpu"), "idle service may request GPU after CPU tests")
		var fallback: Dictionary = service.request(Rect2i(0, 0, 16, 16))
		if _ok(runner, bool(fallback.get("ok", false)) and str(fallback.get("backend", "")) == "cpu", "headless GPU request explicitly falls back to CPU"):
			runner.assert_true(not str(fallback.get("fallback_reason", "")).is_empty(), "the unavailable device has an explicit fallback reason")
			var fallback_done: Dictionary = _drain(runner, service)
			if bool(fallback_done.get("ok", false)) and not bool(fallback_done.get("pending", true)):
				_compare_area(runner, ground, oracle, Rect2i(0, 0, 16, 16), "CPU fallback without device")
	runner.assert_eq(world.elapsed_ms, start_time, "cache work never advances the authoritative world clock")
	runner.assert_true(service.close(), "idle CPU service releases its binding")
	_guarded_publication(runner, world, ground, oracle)
	ground.close()


func _guarded_publication(runner: Object, world: RegionalSimulation, ground: RefCounted, oracle: RefCounted) -> void:
	var owner := RefCounted.new()
	if not _ok(runner, ground.acquire_compute_backend(owner), "a live owner exclusively leases the compute backend"):
		return
	var area := Rect2i(0, 0, 16, 16)
	if not _ok(runner, bool(ground.request_area(area).get("ok", false)), "the leased backend requests a complete block"):
		ground.release_compute_backend(owner)
		return
	var job: Dictionary = ground.export_compute_job(area, true)
	if not _ok(runner, bool(job.get("ok", false)), "the real source snapshot exports to a detached job"):
		ground.release_compute_backend(owner)
		return
	var values := PackedInt32Array()
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var sample: Dictionary = oracle.sample_base(Vector2i(x, y))
			if not _ok(runner, bool(sample.get("ok", false)), "independent real-source oracle prepares an exact packed result"):
				ground.release_compute_backend(owner)
				return
			var channels: PackedInt32Array = Rules.source_to_packed_channels(sample.elements, int(sample.thermal_grade))
			channels[Rules.PACKED_HOT_INDEX] = int(sample.hot_grade)
			channels[Rules.PACKED_COLD_INDEX] = int(sample.cold_grade)
			values.append_array(channels)
	var prepared: Dictionary = FieldCache.prepare_compute_result(job, values)
	if not _ok(runner, bool(prepared.get("ok", false)), "the exact oracle result prepares against the detached job"):
		ground.release_compute_backend(owner)
		return
	var published: Dictionary = ground.publish_compute_result(job, prepared)
	runner.assert_true(bool(published.get("ok", false)), "a current detached result is actually publishable")
	_compare_area(runner, ground, oracle, area, "guarded detached publication")
	var old_job: Dictionary = ground.export_compute_job(area, true)
	if not _ok(runner, bool(old_job.get("ok", false)), "a second current job is exported before mutation"):
		ground.release_compute_backend(owner)
		return
	var old_prepared: Dictionary = FieldCache.prepare_compute_result(old_job, values)
	if not _ok(runner, bool(old_prepared.get("ok", false)), "the second old candidate is prepared"):
		ground.release_compute_backend(owner)
		return
	var moved: Dictionary = world.object_lifecycle.execute(fixture._move("compute_publish_hold", "compute_slab_item", fixture._location("ground:compute_slab"), fixture._location("actor:player")))
	runner.assert_true(bool(moved.get("ok", false)), "original multi-cell artifact moves after the detached snapshot")
	var stale: Dictionary = ground.publish_compute_result(old_job, old_prepared)
	runner.assert_true(not bool(stale.get("ok", true)) and str(stale.get("reason", "")) == "ground_compute_stale", "unsynchronized original mutation rejects the detached result before the base-cache revision changes")
	var affected: Dictionary = ground.read_base(Vector2i(15, 12))
	runner.assert_true(bool(affected.get("pending", false)) and not affected.has("elements"), "stale detached values remain unreadable")
	runner.assert_true(ground.release_compute_backend(owner), "the detached compute owner releases its lease")


func _untracked_inventory(runner: Object) -> void:
	var data: Dictionary = setup(runner)
	if data.is_empty():
		return
	var world: RegionalSimulation = data.world
	var ground: RefCounted = data.ground
	var service := Compute.new()
	if not _ok(runner, service.configure(ground, "cpu"), "epoch test attaches a CPU scheduler"):
		ground.close()
		return
	var request: Dictionary = service.request(Rect2i(0, 0, 32, 32))
	if not _ok(runner, bool(request.get("ok", false)), "epoch test starts an outstanding request"):
		service.close()
		ground.close()
		return
	runner.assert_true(world.regions.home.inventory.consume("compute_bypass", "ground:compute_cold", "grain", 1), "direct original inventory mutation changes the epoch outside lifecycle notification")
	var stale: Dictionary = ground.read_base(Vector2i(16, 14))
	runner.assert_true(not bool(stale.get("ok", true)) and not stale.has("elements"), "a bypassed inventory epoch never exposes the old field")
	var result: Dictionary = service.poll(1, 1000)
	runner.assert_true(not bool(result.get("ok", true)), "an outstanding calculation cannot succeed after an untracked original inventory change")
	_cleanup(service)
	ground.close()


func _replaced_owner(runner: Object) -> void:
	var data: Dictionary = setup(runner)
	if data.is_empty():
		return
	var world: RegionalSimulation = data.world
	var ground: RefCounted = data.ground
	var service := Compute.new()
	if not _ok(runner, service.configure(ground, "cpu"), "owner replacement test attaches a CPU scheduler"):
		ground.close()
		return
	var request: Dictionary = service.request(Rect2i(0, 0, 32, 32))
	if not _ok(runner, bool(request.get("ok", false)), "owner replacement test starts an outstanding request"):
		service.close()
		ground.close()
		return
	var serialized: Dictionary = world.artifacts.to_dict()
	runner.assert_true(world.artifacts.restore(serialized), "the same original artifact owner accepts complete restoration")
	var old: Dictionary = ground.read_base(Vector2i(1, 1))
	runner.assert_true(not bool(old.get("ok", true)) and not old.has("elements"), "same-owner artifact restore invalidates the prior binding")
	var result: Dictionary = service.poll(1, 1000)
	runner.assert_true(not bool(result.get("ok", true)), "a pending computation cannot publish across artifact restoration")
	_cleanup(service)
	ground.close()


func _drain(runner: Object, service: RefCounted) -> Dictionary:
	for _i: int in 10000:
		var result: Dictionary = service.poll(4, 100000)
		if not _ok(runner, bool(result.get("ok", false)), "bounded CPU polling remains valid: " + str(result)):
			return result
		if not bool(result.get("pending", true)):
			return result
	_ok(runner, false, "CPU request completes within its iteration bound")
	return {}


func _compare_area(runner: Object, ground: RefCounted, oracle: RefCounted, area: Rect2i, label: String) -> bool:
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			var actual: Dictionary = ground.read_base(cell)
			var expected: Dictionary = oracle.sample_base(cell)
			if not _ok(runner, bool(actual.get("ok", false)) and not bool(actual.get("pending", true)) and bool(expected.get("ok", false)), label + ": all original source data is ready at " + str(cell)):
				return false
			runner.assert_eq(actual.get("elements"), expected.get("elements"), label + ": five elements at " + str(cell))
			runner.assert_eq(actual.get("thermal_grade"), expected.get("thermal_grade"), label + ": signed thermal grade at " + str(cell))
	return true


func _cleanup(service: RefCounted) -> void:
	if bool(service.diagnostics().get("busy", false)):
		service.cancel(int(service.diagnostics().get("ticket", 0)))
		service.poll(1, 1000)
	service.close()


func _ok(runner: Object, value: bool, label: String) -> bool:
	runner.assert_true(value, label)
	return value
