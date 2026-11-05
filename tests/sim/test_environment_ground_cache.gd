extends RefCounted
## Exercise the developer-only cache against original physical objects and
## their lifecycle. No scene, physical temperature or player knowledge here.

const LifecycleFixture = preload("res://tests/sim/test_object_lifecycle.gd")
const SourceFixture = preload("res://tests/sim/test_environment_source_bindings.gd")
const Definitions = preload("res://scripts/data/environment_source_definitions.gd")
const Bindings = preload("res://scripts/sim/environment_source_bindings.gd")
const GroundCache = preload("res://scripts/sim/environment_ground_cache.gd")

# Fixture navigation Callables must outlive the worlds used below.
var _fixture := LifecycleFixture.new()
var _source_fixture := SourceFixture.new()
var _callback_world: RegionalSimulation
var _callback_cache: RefCounted
var _callback_reads: Array[Dictionary] = []
var _nested_result: Dictionary = {}
var _guard_world: RegionalSimulation
var _guard_results: Dictionary = {}


func run(runner: Object) -> void:
	_real_ground_sources(runner)
	_stale_region_cannot_mask_untracked_inventory(runner)
	print("SCENARIO environment ground cache: real source projection, bounded build, invalidation, timed action and detached restoration")


func _stale_region_cannot_mask_untracked_inventory(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._world(runner)
	if world == null:
		return
	var ids: Array = world.regions.keys()
	var first: String = str(ids[0])
	var last: String = str(ids.back())
	var inventory: SimInventory = world.regions[last].inventory
	inventory.containers.store.wood = 1
	var transfer: Dictionary = {"command": "cache_epoch_remote", "op": "stock_transfer", "item": "wood", "amount": 1,
		"from": {"region": last, "container": "store"}, "to": {"region": last, "cell": [40, 40]}}
	if not _ok(runner, bool(world.object_lifecycle.execute(transfer).get("ok", false)), "the later region has a real original ground source"):
		return
	var definitions := Definitions.new()
	var cache := GroundCache.new()
	if not _ok(runner, definitions.configure(_source_fixture._definitions()) and cache.configure(world, definitions), "the multi-region epoch regression binds the real world"):
		return
	_read_ready(runner, cache, Vector2i(40, 40), "remote source before untracked mutation")
	# Establish a transiently stale first region and a changed later inventory.
	# The ordinary next operation may synchronize the first region, but cannot
	# accept the unchecked epoch of the second as if it had invalidated the cache.
	world.elapsed_ms = 1
	world.target_ms = 1
	for id: String in ids:
		world.regions[id].elapsed_ms = 1
	world.regions[first].elapsed_ms = 0
	runner.assert_true(inventory.consume("cache_epoch_bypass", "ground:cache_epoch_remote", "wood", 1), "a later original inventory API changes its ground epoch")
	var unrelated: Dictionary = world.object_lifecycle.execute({"command": "cache_epoch_unrelated", "op": "spawn", "id": "cache_epoch_other", "definition": "plain_slate", "to": {"region": first, "cell": [70, 70]}})
	runner.assert_true(bool(unrelated.get("ok", false)), "a lawful unrelated object transaction remains permitted")
	for id: String in ids:
		world.regions[id].elapsed_ms = world.elapsed_ms
	var stale: Dictionary = cache.read_base(Vector2i(40, 40))
	runner.assert_eq(stale.get("reason"), "inventory_changed", "all inventory epochs are validated before any stale-region timestamp refusal")
	runner.assert_true(not bool(stale.get("ok", true)) and not stale.has("elements"), "normal transactions cannot bless a bypass and publish its old source")
	cache.close()


func _real_ground_sources(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._world(runner)
	if world == null:
		return
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var inventory: SimInventory = world.regions.home.inventory
	# Establish the test's initial stock before binding the cache. The lifecycle
	# owns every subsequent physical transfer and its ground placement.
	inventory.containers.store.wood = 10000
	var requests: Array[Dictionary] = [
		_fixture._spawn("cache_slab", "cache_slab_item", "stone_slab", [15, 12]),
		_fixture._spawn("cache_edge", "cache_edge_item", "plain_slate", [0, 0]),
		_fixture._spawn("cache_far", "cache_far_item", "plain_slate", [511, 511]),
		_fixture._transfer("cache_hot", _fixture._location("store"), _fixture._ground(14, 15), "wood", 1),
		_fixture._transfer("cache_cold", _fixture._location("kitchen"), _fixture._ground(16, 14), "grain", 1),
		_fixture._transfer("cache_weak", _fixture._location("garden"), _fixture._ground(18, 15), "herb", 1),
	]
	for request: Dictionary in requests:
		if not _ok(runner, bool(lifecycle.execute(request).get("ok", false)), "real ground source setup " + str(request.command)):
			return
	var raw: Dictionary = _source_fixture._definitions()
	raw.profiles.earth.radius_cells = 2
	raw.profiles.hot.radius_cells = 8
	raw.profiles.cold.radius_cells = 16
	raw.profiles.weak.radius_cells = 4
	# Distinct strengths exercise all five order conversions.
	raw.profiles.earth.elements.wood = 101
	raw.profiles.earth.elements.water = 303
	raw.profiles.hot.elements.metal = 711
	raw.profiles.cold.elements.water = 2200
	raw.profiles.weak.elements.wood = 1300
	var definitions: RefCounted = Definitions.new()
	if not _ok(runner, definitions.configure(raw), "the four allowed source radii form one validated definition set"):
		return
	var query: RefCounted = Bindings.new()
	if not _ok(runner, query.configure(world, definitions), "the direct reference view binds the original world"):
		return
	var cache: RefCounted = GroundCache.new()
	_callback_world = world
	_callback_cache = cache
	_callback_reads.clear()
	_nested_result = {}
	# The observer is deliberately connected before cache configuration. A
	# regular signal ordering cannot guarantee its read sees invalidation.
	lifecycle.committed.connect(_on_committed)
	if not _ok(runner, cache.configure(world, definitions), "cache binds the same world and explicit definitions"):
		return
	var first: Dictionary = cache.read_base(Vector2i(2, 0))
	runner.assert_true(bool(first.get("ok", false)) and bool(first.get("pending", false)) and not first.has("elements"), "initial assembly never returns invented or partial field values")
	var one: Dictionary = cache.advance(1, 100000)
	runner.assert_true(bool(one.get("ok", false)) and int(one.get("work_used", 2)) <= 1, "one-unit initialization preserves the requested work budget")
	var early_move: Dictionary = lifecycle.execute(_fixture._move("cache_during_build", "cache_edge_item", _fixture._location("ground:cache_edge"), _fixture._ground(2, 0)))
	if not _ok(runner, bool(early_move.get("ok", false)), "a legal original object can move while initialization is pending"):
		cache.close()
		return
	var interrupted: Dictionary = cache.read_base(Vector2i(0, 0))
	runner.assert_true((not bool(interrupted.get("ok", false)) or bool(interrupted.get("pending", false))) and not interrupted.has("elements"), "a changed world cannot publish the interrupted initialization")
	cache.close()
	if not _ok(runner, cache.configure(world, definitions), "a fresh binding can recover after interrupted initialization"):
		return
	var area: Rect2i = Rect2i(Vector2i(14, 13), Vector2i(4, 3))
	runner.assert_true(bool(cache.request_area(area).get("ok", false)), "a region spanning two tile blocks can be requested")
	for y: int in range(13, 16):
		for x: int in range(14, 18):
			if not _compare(runner, cache, query, Vector2i(x, y), "mixed source field"):
				cache.close()
				return
	if not _compare(runner, cache, query, Vector2i(0, 0), "low map edge") or not _compare(runner, cache, query, Vector2i(511, 511), "high map edge"):
		cache.close()
		return
	runner.assert_eq(int(cache.diagnostics().get("source_count", -1)), 6, "three unique artifacts and three stock entries each contribute one real source")
	var slab: Dictionary = query.project({"kind": "artifact", "id": "cache_slab_item"})
	runner.assert_eq(slab.get("size"), Vector2i(2, 1), "the cross-block slab remains one original multi-cell object")
	runner.assert_eq(slab.get("cell"), Vector2i(15, 12), "the even-width source retains the existing anchor convention")

	var backlog_target: int = world.target_ms
	world.target_ms = world.elapsed_ms + 1
	var backlog: Dictionary = cache.read_base(Vector2i(16, 15))
	runner.assert_eq(backlog.get("reason"), "world_has_backlog", "owed world time prevents a current cache reading")
	runner.assert_true(not backlog.has("elements"), "backlog refusal never exposes old values as current")
	world.target_ms = backlog_target
	if not _compare(runner, cache, query, Vector2i(16, 15), "backlog cleared"):
		cache.close()
		return

	var before_failure: Dictionary = cache.read_base(Vector2i(15, 13))
	var invalidations: int = int(cache.diagnostics().invalidations)
	var rejected: Dictionary = lifecycle.execute(_fixture._spawn("cache_overlap", "cache_overlap_item", "plain_slate", [16, 12]))
	runner.assert_true(not bool(rejected.get("ok", true)), "placement on the second cell of a two-cell original fails")
	runner.assert_eq(cache.read_base(Vector2i(15, 13)), before_failure, "a rejected physical operation leaves the completed cache result unchanged")
	runner.assert_eq(int(cache.diagnostics().invalidations), invalidations, "a rejected operation does not invalidate unrelated cached targets")

	if not _stack_changes(runner, world, cache, query):
		cache.close()
		return
	if not _callbacks_and_artifact_changes(runner, world, cache, query):
		cache.close()
		return
	if not _resynchronized_source_changes_again(runner, world, cache, query):
		cache.close()
		return
	if not _artifact_guard_cannot_reenter_lifecycle(runner, world, cache, query):
		cache.close()
		return
	if not _timed_change(runner, world, cache, query):
		cache.close()
		return
	_restore_and_bypass(runner, world, cache, definitions, query)
	cache.close()


func _stack_changes(runner: Object, world: RegionalSimulation, cache: RefCounted, query: RefCounted) -> bool:
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var inventory: SimInventory = world.regions.home.inventory
	var observer := Vector2i(16, 15)
	var original: Dictionary = cache.read_base(observer)
	var before_invalidations: int = int(cache.diagnostics().invalidations)
	var grow: Dictionary = lifecycle.execute(_fixture._transfer("cache_grow", _fixture._location("store"), _fixture._ground(14, 15), "wood", 9999))
	if not _ok(runner, bool(grow.get("ok", false)), "the real one-item pile can merge to 10000"):
		return false
	runner.assert_eq(inventory.quantity("ground:cache_hot", "wood"), 10000, "the original ledger records the whole pile")
	runner.assert_eq(cache.read_base(observer), original, "changing positive pile quantity does not amplify or invalidate its field")
	runner.assert_eq(int(cache.diagnostics().invalidations), before_invalidations, "quantity growth alone does not invalidate source geometry")
	var prior_direct: Dictionary = query.sample_base(observer)
	runner.assert_eq(prior_direct.get("hot_grade"), 3000, "the stronger source dominates at the common receiver")
	var pickup: Dictionary = lifecycle.execute(_fixture._transfer("cache_pickup", _fixture._location("ground:cache_hot"), _fixture._location("actor:player"), "wood", 10000))
	if not _ok(runner, bool(pickup.get("ok", false)), "the entire strong pile moves to the real actor container"):
		return false
	var pending: Dictionary = cache.read_base(observer)
	runner.assert_true(bool(pending.get("pending", false)) and not pending.has("elements"), "removing a strong source makes the old result pending immediately")
	if not _compare(runner, cache, query, observer, "after strongest source pickup"):
		return false
	var after_direct: Dictionary = query.sample_base(observer)
	runner.assert_eq(after_direct.get("hot_grade"), 1000, "the weaker real source takes over when the maximum leaves")
	runner.assert_eq(after_direct.get("thermal_grade"), -2750, "the cold source still participates after the heat source leaves")
	var split: Dictionary = lifecycle.execute(_fixture._transfer("cache_split", _fixture._location("actor:player"), _fixture._ground(13, 15), "wood", 4))
	if not _ok(runner, bool(split.get("ok", false)), "four carried items form a new real pile"):
		return false
	if not _compare(runner, cache, query, Vector2i(13, 15), "four-item pile"):
		return false
	var four: Dictionary = cache.read_base(Vector2i(13, 15))
	var stable_invalidations: int = int(cache.diagnostics().invalidations)
	for count: int in [12, 9984]:
		var add: Dictionary = lifecycle.execute(_fixture._transfer("cache_stack_%d" % count, _fixture._location("actor:player"), _fixture._ground(13, 15), "wood", count))
		if not _ok(runner, bool(add.get("ok", false)), "a compatible pile merges real material quantity %d" % count):
			return false
		runner.assert_eq(cache.read_base(Vector2i(13, 15)), four, "one pile has equal influence at 4, 16 and 10000 items")
	runner.assert_eq(inventory.quantity("ground:cache_split", "wood"), 10000, "the merged pile is still one original ledger entry")
	runner.assert_eq(int(cache.diagnostics().invalidations), stable_invalidations, "growing an existing nonempty pile does not rebuild its field")
	var separate: Dictionary = lifecycle.execute(_fixture._transfer("cache_separate", _fixture._location("ground:cache_split"), _fixture._ground(12, 15), "wood", 5))
	if not _ok(runner, bool(separate.get("ok", false)), "splitting the pile creates a second distinct ground position"):
		return false
	if not _compare(runner, cache, query, Vector2i(13, 15), "split sources overlap"):
		return false
	runner.assert_eq(query.sample_base(Vector2i(13, 15)).get("hot_grade"), 4000, "separate same-profile piles overlap by maximum rather than summation")
	var merge: Dictionary = lifecycle.execute(_fixture._transfer("cache_merge", _fixture._location("ground:cache_separate"), _fixture._ground(13, 15), "wood", 5))
	if not _ok(runner, bool(merge.get("ok", false)), "both original piles merge through the lifecycle"):
		return false
	runner.assert_eq(inventory.quantity("ground:cache_split", "wood"), 10000, "merged material is not duplicated or lost")
	runner.assert_eq(inventory.quantity("ground:cache_separate", "wood"), 0, "the emptied split no longer contains material")
	return _compare(runner, cache, query, Vector2i(13, 15), "merged sources")


func _callbacks_and_artifact_changes(runner: Object, world: RegionalSimulation, cache: RefCounted, query: RefCounted) -> bool:
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	# Warm the edge block before the callback reads it.
	if not _compare(runner, cache, query, Vector2i(2, 0), "edge source before callback"):
		return false
	var outer: Dictionary = lifecycle.execute(_fixture._move("cache_outer", "cache_edge_item", _fixture._location("ground:cache_during_build"), _fixture._ground(3, 0)))
	if not _ok(runner, bool(outer.get("ok", false)), "outer object movement commits"):
		return false
	runner.assert_true(bool(_nested_result.get("ok", false)), "an observer may issue a second real move from its callback")
	runner.assert_eq(_callback_reads.size(), 2, "both the earlier observer and its nested operation read during their respective notifications")
	for value: Dictionary in _callback_reads:
		runner.assert_true((not bool(value.get("ok", false)) or bool(value.get("pending", false))) and not value.has("elements"), "a callback never observes the old block as a current value")
	if not _compare(runner, cache, query, Vector2i(4, 0), "nested move final position"):
		return false
	var held: Dictionary = lifecycle.execute(_fixture._move("cache_hold", "cache_edge_item", _fixture._location("ground:cache_nested"), _fixture._location("actor:player")))
	if not _ok(runner, bool(held.get("ok", false)), "an original artifact can be carried without a remaining ground source"):
		return false
	if not _compare(runner, cache, query, Vector2i(4, 0), "held artifact removed from ground"):
		return false
	var dropped: Dictionary = lifecycle.execute(_fixture._move("cache_redrop", "cache_edge_item", held.to, _fixture._ground(5, 0)))
	if not _ok(runner, bool(dropped.get("ok", false)), "the same original artifact can be placed again"):
		return false
	if not _compare(runner, cache, query, Vector2i(5, 0), "artifact redrop"):
		return false
	var removed: Dictionary = lifecycle.execute({"command": "cache_remove", "op": "remove", "id": "cache_edge_item", "from": dropped.to.duplicate(true)})
	if not _ok(runner, bool(removed.get("ok", false)), "a real ground artifact is removed"):
		return false
	if not _compare(runner, cache, query, Vector2i(5, 0), "artifact removed"):
		return false
	var spawned: Dictionary = lifecycle.execute(_fixture._spawn("cache_late_spawn", "cache_late_item", "plain_slate", [5, 0]))
	if not _ok(runner, bool(spawned.get("ok", false)), "a new artifact may appear after the cache is already ready"):
		return false
	return _compare(runner, cache, query, Vector2i(5, 0), "artifact spawned after binding")


func _on_committed(notice: Dictionary) -> void:
	if notice.get("command") == "cache_outer":
		_callback_reads.append(_callback_cache.read_base(Vector2i(2, 0)))
		_nested_result = _callback_world.object_lifecycle.execute(_fixture._move("cache_nested", "cache_edge_item", notice.result.to, _fixture._ground(4, 0)))
	elif notice.get("command") == "cache_nested":
		_callback_reads.append(_callback_cache.read_base(Vector2i(3, 0)))


func _resynchronized_source_changes_again(runner: Object, world: RegionalSimulation, cache: RefCounted, query: RefCounted) -> bool:
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var first: Dictionary = lifecycle.execute(_fixture._move("cache_queue_a1", "cache_late_item", _fixture._location("ground:cache_late_spawn"), _fixture._ground(6, 0)))
	if not _ok(runner, bool(first.get("ok", false)), "the first original object moves before queued sources are projected"):
		return false
	var second: Dictionary = lifecycle.execute(_fixture._move("cache_queue_b", "cache_slab_item", _fixture._location("ground:cache_slab"), _fixture._ground(20, 12)))
	if not _ok(runner, bool(second.get("ok", false)), "the second original object also queues a source update"):
		return false
	runner.assert_eq(int(cache.diagnostics().pending_sources), 2, "two independent physical objects have pending source updates")
	var progressed: Dictionary = cache.advance(1, 100000)
	runner.assert_true(bool(progressed.get("ok", false)) and int(progressed.get("work_used", 0)) == 1, "a single work unit synchronizes exactly one queued source")
	runner.assert_eq(int(cache.diagnostics().pending_sources), 1, "the second update remains pending after the first source is synchronized")
	var again: Dictionary = lifecycle.execute(_fixture._move("cache_queue_a2", "cache_late_item", first.to, _fixture._ground(7, 0)))
	if not _ok(runner, bool(again.get("ok", false)), "the first original object moves again before the other queued update completes"):
		return false
	runner.assert_eq(int(cache.diagnostics().pending_sources), 2, "a source synchronized earlier is queued again for its newer actual location")
	var pending: Dictionary = cache.read_base(Vector2i(7, 0))
	runner.assert_true(bool(pending.get("pending", false)) and not pending.has("elements"), "the final location is not reported ready from its older projection")
	for cell: Vector2i in [Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0), Vector2i(15, 12), Vector2i(20, 12)]:
		if not _compare(runner, cache, query, cell, "source changes again while another is queued"):
			return false
	runner.assert_eq(int(cache.diagnostics().pending_sources), 0, "both queued originals and the repeated change are fully synchronized")
	return true


func _artifact_guard_cannot_reenter_lifecycle(runner: Object, world: RegionalSimulation, cache: RefCounted, query: RefCounted) -> bool:
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var ongoing: Dictionary = _fixture._move("cache_guard_pending", "cache_late_item", _fixture._location("ground:cache_queue_a2"), _fixture._ground(8, 0))
	var scheduled: Dictionary = lifecycle.schedule(ongoing, "player", 5000)
	if not _ok(runner, bool(scheduled.get("ok", false)), "the original lifecycle has a real pending action for guard cancellation"):
		return false
	_guard_world = world
	_guard_results = {}
	world.artifacts.transfers.set_guard(_probe_lifecycle_in_guard)
	var stone: Dictionary = world.artifacts.objects.hearth_stone
	var change: Dictionary = SimArtifactTransfers.describe("hearth_stone", stone, "home", "actor:player", world.elapsed_ms, "guard_probe", "take")
	var allowed: bool = world.artifacts.transfers.allows(change)
	world.artifacts.transfers.set_guard(Callable())
	runner.assert_true(allowed and not _guard_results.is_empty(), "the original artifact preflight actually invokes the guard")
	runner.assert_eq(_guard_results.get("execute", {}).get("reason"), "transaction_busy", "the artifact guard cannot execute an unrelated object transaction")
	runner.assert_eq(_guard_results.get("schedule", {}).get("reason"), "transaction_busy", "the artifact guard cannot schedule an unrelated timed transaction")
	runner.assert_eq(_guard_results.get("cancel"), false, "the artifact guard cannot cancel the already active lifecycle action")
	runner.assert_eq(_guard_results.get("before_lifecycle"), _guard_results.get("after_lifecycle"), "all failed reentrant calls preserve the lifecycle receipts, action and ground state")
	runner.assert_eq(_guard_results.get("before_inventory"), _guard_results.get("after_inventory"), "the original inventory ledger remains unchanged through the guard")
	runner.assert_eq(_guard_results.get("before_actor"), _guard_results.get("after_actor"), "the pending actor's action and autonomy remain unchanged during the guard")
	runner.assert_eq(lifecycle.actions.cache_guard_pending.status, "active", "the guard did not cancel the genuinely pending action")
	runner.assert_true(lifecycle.cancel("player"), "the action can be canceled normally after guard execution ends")
	_guard_world = null
	return _compare(runner, cache, query, Vector2i(7, 0), "guard reentry leaves source cache unchanged")


func _probe_lifecycle_in_guard(_change: Dictionary) -> bool:
	var lifecycle: SimObjectLifecycle = _guard_world.object_lifecycle
	var inventory: SimInventory = _guard_world.regions.home.inventory
	_guard_results["before_lifecycle"] = lifecycle.to_dict()
	_guard_results["before_inventory"] = inventory.to_dict()
	_guard_results["before_actor"] = _guard_world.regions.home.actors.player.duplicate(true)
	_guard_results["execute"] = lifecycle.execute(_fixture._spawn("cache_guard_illegal", "cache_guard_illegal_item", "plain_slate", [10, 0]))
	var move: Dictionary = _fixture._move("cache_guard_illegal_schedule", "cache_far_item", _fixture._location("ground:cache_far"), _fixture._ground(509, 511))
	_guard_results["schedule"] = lifecycle.schedule(move, "shi_tou", 5000)
	_guard_results["cancel"] = lifecycle.cancel("player")
	_guard_results["after_lifecycle"] = lifecycle.to_dict()
	_guard_results["after_inventory"] = inventory.to_dict()
	_guard_results["after_actor"] = _guard_world.regions.home.actors.player.duplicate(true)
	return true


func _timed_change(runner: Object, world: RegionalSimulation, cache: RefCounted, query: RefCounted) -> bool:
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var request: Dictionary = _fixture._move("cache_timed", "cache_far_item", _fixture._location("ground:cache_far"), _fixture._ground(510, 511))
	var scheduled: Dictionary = lifecycle.schedule(request, "player", 100)
	if not _ok(runner, bool(scheduled.get("ok", false)), "a real actor schedules an original artifact move"):
		return false
	var due: int = int(scheduled.action.due_ms)
	if not _ok(runner, world.advance_to_ms(due), "the common clock reaches the timed object's deadline"):
		return false
	runner.assert_eq(lifecycle.actions.cache_timed.status, "completed", "the ordinary timed lifecycle really completes the move")
	for id: String in world.regions:
		if not _ok(runner, world.synchronize_region(id), "region is synchronized before field observation: " + id):
			return false
	var pending: Dictionary = cache.read_base(Vector2i(511, 511))
	runner.assert_true(bool(pending.get("pending", false)) and not pending.has("elements"), "timed completion invalidates the prior edge block before it can be read")
	return _compare(runner, cache, query, Vector2i(510, 511), "timed artifact completion")


func _restore_and_bypass(runner: Object, world: RegionalSimulation, cache: RefCounted, definitions: RefCounted, query: RefCounted) -> void:
	var observed := Vector2i(13, 15)
	var previous: Dictionary = cache.read_base(observed)
	var saved: Variant = JSON.parse_string(_fixture._state(world))
	if not _ok(runner, saved is Dictionary and world.restore(saved), "the real world can restore a complete candidate into its existing instance"):
		return
	var stale: Dictionary = cache.read_base(observed)
	runner.assert_true(not bool(stale.get("ok", true)) and not stale.has("elements"), "a cache attached to replaced world owners never publishes an old result")
	cache.close()
	runner.assert_eq(cache.read_base(observed).get("reason"), "not_configured", "closed service has no readable field")
	if not _ok(runner, cache.configure(world, definitions), "the same service explicitly binds the restored world owners"):
		return
	var restored_query: RefCounted = Bindings.new()
	if not _ok(runner, restored_query.configure(world, definitions), "a new direct view binds the restored owners"):
		return
	if not _compare(runner, cache, restored_query, observed, "restored cache"):
		return
	var restored: Dictionary = cache.read_base(observed)
	runner.assert_eq(restored.get("elements"), previous.get("elements"), "restoration rebuilds the same source-derived element field")
	runner.assert_eq(restored.get("thermal_grade"), previous.get("thermal_grade"), "restoration rebuilds the same source-derived thermal field")
	var artifacts_data: Dictionary = world.artifacts.to_dict()
	if not _ok(runner, world.artifacts.restore(artifacts_data), "the same artifact owner accepts a complete valid restore"):
		return
	var generation_stale: Dictionary = cache.read_base(observed)
	runner.assert_true(not bool(generation_stale.get("ok", true)) and not generation_stale.has("elements"), "same-owner artifact replacement invalidates old source data")
	cache.close()
	if not _ok(runner, cache.configure(world, definitions), "explicit rebind follows the owner generation change"):
		return
	if not _compare(runner, cache, restored_query, observed, "artifact generation rebind"):
		return
	var inventory: SimInventory = world.regions.home.inventory
	if not _ok(runner, inventory.transfer("cache_untracked", "ground:cache_split", "actor:player", "wood", 1), "the original ledger exposes a direct ground transfer outside lifecycle"):
		return
	var untracked: Dictionary = cache.read_base(observed)
	runner.assert_eq(untracked.get("reason"), "inventory_changed", "a bypassed ground ledger revision cannot leave old cached data readable")
	runner.assert_true(not untracked.has("elements"), "an untracked source mutation does not silently return prior values")
	cache.close()
	if not _ok(runner, cache.configure(world, definitions), "a fresh binding can rebuild from the still-valid original owners"):
		return
	_compare(runner, cache, restored_query, observed, "rebind after direct ledger change")


func _compare(runner: Object, cache: RefCounted, query: RefCounted, cell: Vector2i, label: String) -> bool:
	var cached: Dictionary = _read_ready(runner, cache, cell, label)
	if cached.is_empty():
		return false
	var direct: Dictionary = query.sample_base(cell)
	if not _ok(runner, bool(direct.get("ok", false)) and bool(direct.get("complete", false)), label + ": direct A1 sample is complete"):
		return false
	runner.assert_eq(cached.get("elements"), direct.get("elements"), label + ": all five channels match the original sources at " + str(cell))
	runner.assert_eq(cached.get("thermal_grade"), direct.get("thermal_grade"), label + ": cold/hot composition matches at " + str(cell))
	runner.assert_eq(cached.get("config_digest"), direct.get("config_digest"), label + ": the exact source definitions match")
	runner.assert_eq(cached.get("rule_version"), direct.get("rule_version"), label + ": the rounding rule version matches")
	return true


func _read_ready(runner: Object, cache: RefCounted, cell: Vector2i, label: String) -> Dictionary:
	# Fixed iteration and work/time budgets keep a broken implementation from
	# hanging the synchronous test runner indefinitely.
	for iteration: int in 2000:
		var sample: Dictionary = cache.read_base(cell)
		if not bool(sample.get("ok", false)):
			runner.assert_true(false, label + ": cache read failed: " + str(sample))
			return {}
		if not bool(sample.get("pending", true)):
			return sample
		if sample.has("elements") or sample.has("thermal_grade"):
			runner.assert_true(false, label + ": pending returned partial data")
			return {}
		var progressed: Dictionary = cache.advance(65536, 100000)
		if not bool(progressed.get("ok", false)):
			runner.assert_true(false, label + ": budgeted build failed: " + str(progressed))
			return {}
	runner.assert_true(false, label + ": budgeted cache did not converge within the test limit")
	return {}


func _ok(runner: Object, value: bool, label: String) -> bool:
	runner.assert_true(value, label)
	return value
