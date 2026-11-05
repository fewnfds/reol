extends RefCounted
## The existing two-settlement runtime fixture, not a Main-scene or restart
## test: real lifecycle placements travel through the same shared timeline.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const ITEM_ID: String = "continuity_physical_item"
const SPAWN_COMMAND: String = "continuity_spawn_item"
const STOCK_COMMAND: String = "continuity_drop_wood"
const ITEM_CONTAINER: String = "ground:continuity_spawn_item"
const STOCK_CONTAINER: String = "ground:continuity_drop_wood"
const STOCK_AMOUNT: int = 4
const MAX_TRIP_MINUTES: int = 250


func run(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var path: String = "user://tests/lifecycle_continuity_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	var available: bool = true
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		available = available and not FileAccess.file_exists(path + suffix)
	runner.assert_true(available, "the continuity test owns a new save path")
	if available:
		_exercise(runner, fixture, path)
		for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
			var owned_path: String = ProjectSettings.globalize_path(path + suffix)
			if FileAccess.file_exists(owned_path):
				DirAccess.remove_absolute(owned_path)
	fixtures._dispose(fixture)
	print("SCENARIO lifecycle continuity: ordinary two-region runtime fixture, real item and stock, out-and-back travel, independent stage and resumed save")


func _exercise(runner: Object, fixture: Dictionary, path: String) -> void:
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var home: VillageSimulation = world.regions.home
	var inventory: SimInventory = home.inventory
	var center: Vector2i = runtime.controlled_cell()
	var item_cell: Vector2i = _find_cell(lifecycle, center)
	runner.assert_true(item_cell.x >= 0, "the actual home map has a legal ground cell for a physical item")
	if item_cell.x < 0:
		return
	var spawn_request: Dictionary = {"command": SPAWN_COMMAND, "op": "spawn", "id": ITEM_ID, "definition": "plain_slate", "to": _ground(item_cell)}
	var spawned: Dictionary = lifecycle.execute(spawn_request)
	runner.assert_true(bool(spawned.get("ok", false)), "the actual lifecycle creates the unique original item")
	if not bool(spawned.get("ok", false)):
		return
	var stock_cell: Vector2i = _find_cell(lifecycle, center)
	runner.assert_true(stock_cell.x >= 0 and stock_cell != item_cell, "the actual home map has a separate ground cell for the material pile")
	if stock_cell.x < 0 or stock_cell == item_cell:
		return
	var store_before: int = inventory.quantity("store", "wood")
	runner.assert_true(inventory.available("store", "wood") >= STOCK_AMOUNT, "the real home store has enough available wood")
	if inventory.available("store", "wood") < STOCK_AMOUNT:
		return
	var stock_request: Dictionary = {"command": STOCK_COMMAND, "op": "stock_transfer", "from": {"region": "home", "container": "store"}, "to": _ground(stock_cell), "item": "wood", "amount": STOCK_AMOUNT}
	var dropped: Dictionary = lifecycle.execute(stock_request)
	runner.assert_true(bool(dropped.get("ok", false)), "the lifecycle splits actual store wood into a separate ground pile")
	if not bool(dropped.get("ok", false)):
		return
	runner.assert_eq(inventory.quantity("store", "wood"), store_before - STOCK_AMOUNT, "the initial split removes only the real source quantity")
	_assert_originals(runner, world, item_cell, stock_cell, "initial")
	var initial: Dictionary = WorldSessionSnapshot.capture(runtime)
	var initial_world: Dictionary = initial.get("continuity", {}).get("world", {})
	runner.assert_true(initial_world.get("artifacts", {}).get("objects", {}).has(ITEM_ID), "the initial joint snapshot contains the original item")
	runner.assert_true(initial_world.get("object_lifecycle", {}).get("ground", {}).get("slots", {}).has(STOCK_CONTAINER), "the initial joint snapshot contains the original wood placement")
	var time_before_trip: int = GameClock.elapsed_ms
	if not _travel(runner, runtime, "river"):
		return
	runner.assert_true(runtime.world_sim == world and world.regions.home == home, "leaving home retains the same authoritative world and home region")
	runner.assert_eq(runtime.current_region, "river", "the player actually entered the remote region")
	runner.assert_true(GameClock.elapsed_ms > time_before_trip, "the real outward journey advances shared time")
	_assert_originals(runner, world, item_cell, stock_cell, "at river")
	if not world.synchronize_region("home"):
		runner.assert_true(false, "home can be synchronized at the outward arrival boundary")
		return
	var away_start: int = GameClock.elapsed_ms
	var resident_before: String = _canonical(home.actors.shi_tou)
	if not _advance_minutes(runner, runtime, 10, "while away"):
		return
	runner.assert_true(runtime.current_region == "river" and world.active_region == "river", "the player remains in the remote region during the observation interval")
	runner.assert_true(world.synchronize_region("home"), "the original home region catches up while the player is away")
	runner.assert_eq(home.elapsed_ms, GameClock.elapsed_ms, "home reaches the same committed shared time while the player is away")
	runner.assert_true(home.elapsed_ms > away_start and _canonical(home.actors.shi_tou) != resident_before, "an original home resident actually changes while the player is away")
	_assert_originals(runner, world, item_cell, stock_cell, "after away time")
	if not _travel(runner, runtime, "home"):
		return
	runner.assert_true(runtime.world_sim == world and world.regions.home == home, "returning reconnects the same world rather than a replacement")
	runner.assert_eq(runtime.current_region, "home", "the player actually returns to home")
	_assert_originals(runner, world, item_cell, stock_cell, "after return")
	var saved: Error = runtime.save_game(path)
	runner.assert_eq(saved, OK, "the ordinary runtime saves the returned world and shared time")
	if saved != OK:
		return
	var checkpoint: Dictionary = WorldSessionSnapshot.capture(runtime)
	var checkpoint_text: String = _canonical(checkpoint)
	var staged: Dictionary = WorldSessionSnapshot.stage(runtime, checkpoint)
	runner.assert_true(not staged.is_empty(), "the actual checkpoint stages as an independent candidate")
	if staged.is_empty():
		return
	var candidate: RegionalSimulation = staged.world
	runner.assert_true(candidate != world and candidate.regions.home != home, "candidate staging constructs distinct world and home owners")
	runner.assert_true(runtime.world_sim == world and _canonical(WorldSessionSnapshot.capture(runtime)) == checkpoint_text, "candidate staging leaves the live world unchanged")
	_assert_originals(runner, candidate, item_cell, stock_cell, "independent candidate")
	if not _advance_minutes(runner, runtime, 3, "original continuation"):
		return
	var future_text: String = _canonical(WorldSessionSnapshot.capture(runtime))
	var loaded: Error = runtime.load_game(path)
	runner.assert_eq(loaded, OK, "the ordinary runtime reloads the joint checkpoint")
	if loaded != OK:
		return
	var restored: RegionalSimulation = runtime.world_sim
	runner.assert_true(restored != world, "normal loading publishes an independently restored world")
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(runtime)), checkpoint_text, "normal loading restores the whole original checkpoint")
	_assert_originals(runner, restored, item_cell, stock_cell, "after load")
	var restored_stock_before: int = restored.regions.home.inventory.quantity("store", "wood")
	var restored_receipts_before: int = restored.object_lifecycle.receipts.size()
	var restored_objects_before: int = restored.artifacts.objects.size()
	runner.assert_eq(restored.object_lifecycle.execute(spawn_request), spawned, "retrying the saved creation returns its original result")
	runner.assert_eq(restored.object_lifecycle.execute(stock_request), dropped, "retrying the saved split returns its original result")
	runner.assert_eq(restored.object_lifecycle.receipts.size(), restored_receipts_before, "retries do not add duplicate receipts")
	runner.assert_eq(restored.artifacts.objects.size(), restored_objects_before, "retries do not create a duplicate item")
	runner.assert_eq(restored.regions.home.inventory.quantity("store", "wood"), restored_stock_before, "retry does not deduct the source material twice")
	_assert_originals(runner, restored, item_cell, stock_cell, "after retry")
	if not _advance_minutes(runner, runtime, 3, "restored continuation"):
		return
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(runtime)), future_text, "the restored world reaches the same full three-minute future exactly once")
	_assert_originals(runner, restored, item_cell, stock_cell, "after restored continuation")


func _find_cell(lifecycle: SimObjectLifecycle, center: Vector2i) -> Vector2i:
	for radius: int in range(1, 33):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var cell: Vector2i = center + Vector2i(x, y)
				if bool(lifecycle.ground.can_place("home", cell).get("ok", false)):
					return cell
	return Vector2i(-1, -1)


func _assert_originals(runner: Object, world: RegionalSimulation, item_cell: Vector2i, stock_cell: Vector2i, context: String) -> void:
	var item: Dictionary = world.artifacts.objects.get(ITEM_ID, {})
	runner.assert_true(not item.is_empty() and item.get("definition") == "plain_slate" and item.get("region") == "home" and item.get("container") == ITEM_CONTAINER, context + ": the same unique item retains its original owner and location")
	if not item.is_empty():
		runner.assert_eq(world.artifacts.object_cell(ITEM_ID), item_cell, context + ": the item resolves to its actual original ground cell")
	var item_slot: Dictionary = world.object_lifecycle.ground.locate("home", ITEM_CONTAINER)
	runner.assert_true(bool(item_slot.get("ok", false)) and bool(item_slot.get("active", false)) and item_slot.get("cell") == item_cell and item_slot.get("reference") == {"kind": "artifact", "id": ITEM_ID}, context + ": the original item ground slot remains active")
	var stock_slot: Dictionary = world.object_lifecycle.ground.locate("home", STOCK_CONTAINER)
	runner.assert_true(bool(stock_slot.get("ok", false)) and bool(stock_slot.get("active", false)) and stock_slot.get("cell") == stock_cell, context + ": the original wood ground slot remains active")
	runner.assert_eq(world.regions.home.inventory.quantity(STOCK_CONTAINER, "wood"), STOCK_AMOUNT, context + ": the real inventory retains exactly the original pile quantity")


func _travel(runner: Object, runtime: WorldContinuityRuntime, region: String) -> bool:
	var start: int = GameClock.elapsed_ms
	var accepted: bool = runtime.travel_to(region)
	runner.assert_true(accepted, "the real runtime accepts travel to " + region)
	if not accepted:
		return false
	for _minute: int in MAX_TRIP_MINUTES:
		if runtime.player_journey.is_empty():
			break
		if not _advance_minutes(runner, runtime, 1, "travelling to " + region):
			return false
	var arrived: bool = runtime.player_journey.is_empty() and runtime.current_region == region and GameClock.elapsed_ms > start
	runner.assert_true(arrived, "the actual travel reaches " + region + " within its bounded minute budget")
	return arrived


func _advance_minutes(runner: Object, runtime: WorldContinuityRuntime, minutes: int, context: String) -> bool:
	for _minute: int in minutes:
		var before: int = GameClock.elapsed_ms
		GameClock.advance_ticks(1)
		var committed: bool = GameClock.elapsed_ms == before + 60000 and runtime.world_sim.elapsed_ms == GameClock.elapsed_ms and runtime.world_sim.target_ms == GameClock.elapsed_ms and not GameClock.has_pending_advance()
		if not committed:
			runner.assert_true(false, context + ": a minute was not fully committed; no accumulated time is silently discarded")
			return false
	return true


func _ground(cell: Vector2i) -> Dictionary:
	return {"region": "home", "cell": [cell.x, cell.y]}


func _canonical(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
