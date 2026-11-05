extends RefCounted
## Timed lifecycle actions use original owners and the shared world clock.
## Authority-only requests here do not provide player reach or consent.

const Fixture = preload("res://tests/sim/test_object_lifecycle.gd")
var _fixture := Fixture.new()


class Observer extends RefCounted:
	var notices: Array = []

	func on_committed(change: Dictionary) -> void:
		notices.append(change.duplicate(true))


class CancelOtherObserver extends RefCounted:
	var owner: WeakRef
	var notices: Array[String] = []
	var cancelled: bool = false

	func _init(lifecycle: SimObjectLifecycle) -> void:
		owner = weakref(lifecycle)

	func on_committed(change: Dictionary) -> void:
		var command: String = str(change.get("command", ""))
		notices.append(command)
		if command == "a_callback_move":
			var lifecycle: Variant = owner.get_ref()
			if lifecycle != null:
				cancelled = lifecycle.cancel("shi_tou")


func run(runner: Object) -> void:
	_timing_conflicts_and_single_commit(runner)
	_stock_reservation_and_cancel(runner)
	_revalidate_changed_destination(runner)
	_revalidate_changed_source(runner)
	_save_and_continue_inflight(runner)
	_bounded_and_segmented_advancement(runner)
	_multicell_reservation(runner)
	_callback_cancellation_at_shared_deadline(runner)
	_timed_merge_into_existing_pile(runner)
	print("SCENARIO object actions: shared clock, reservations, interruption, revalidation, in-flight restore and bounded advancement")


func _multicell_reservation(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._world(runner)
	if world == null:
		return
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	runner.assert_true(lifecycle.execute(_fixture._spawn("slab", "slab", "stone_slab", [120, 120])).ok, "a multi-cell original is created")
	runner.assert_true(lifecycle.execute(_fixture._spawn("small", "small", "plain_slate", [122, 120])).ok, "an independent item is created")
	var request: Dictionary = _fixture._move("place_slab", "slab", _fixture._location("ground:slab"), _fixture._ground(130, 120))
	runner.assert_true(lifecycle.schedule(request, "player", 4000).ok, "all of a multi-cell destination can be reserved")
	var conflicting: Dictionary = _fixture._move("place_small", "small", _fixture._location("ground:small"), _fixture._ground(131, 120))
	runner.assert_eq(lifecycle.schedule(conflicting, "shi_tou", 4000).get("reason"), "target_reserved", "a second actor cannot reserve the second cell of another action")
	runner.assert_eq(lifecycle.execute(_fixture._spawn("intrude", "intruder", "plain_slate", [131, 120])).get("reason"), "target_reserved", "instant creation cannot bypass a pending multi-cell destination")
	runner.assert_true(lifecycle.cancel("player"), "cancelling releases every reserved destination cell")
	runner.assert_true(lifecycle.schedule(conflicting, "shi_tou", 4000).ok, "the second cell becomes available after cancellation")


func _spawn_pair(runner: Object, world: RegionalSimulation) -> bool:
	var first: Dictionary = world.object_lifecycle.execute(_fixture._spawn("create_first", "first", "plain_slate", [120, 120]))
	var second: Dictionary = world.object_lifecycle.execute(_fixture._spawn("create_second", "second", "plain_slate", [121, 120]))
	var ok: bool = bool(first.get("ok", false)) and bool(second.get("ok", false))
	runner.assert_true(ok, "both independent physical objects are created by their original owner")
	return ok


func _timing_conflicts_and_single_commit(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._world(runner)
	if world == null or not _spawn_pair(runner, world):
		return
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var observer := Observer.new()
	lifecycle.committed.connect(observer.on_committed)
	var source: Dictionary = _fixture._location("ground:create_first")
	var request: Dictionary = _fixture._move("take_first", "first", source, _fixture._location("actor:player"))
	var started: int = world.elapsed_ms
	var scheduled: Dictionary = lifecycle.schedule(request, "player", 3400)
	runner.assert_true(bool(scheduled.get("ok", false)), "a real actor can start one timed physical move")
	if not bool(scheduled.get("ok", false)):
		return
	runner.assert_eq(scheduled.action.status, "active", "a scheduled action is active before its deadline")
	runner.assert_eq(int(scheduled.action.started_ms), started, "the action starts at committed world time")
	runner.assert_eq(int(scheduled.action.due_ms), started + 3400, "the action deadline uses the shared clock")
	runner.assert_true(world.owns_for_scope("player", &"body"), "the action occupies its actor's existing body scope")
	runner.assert_eq(lifecycle.schedule(request, "player", 3400), scheduled, "repeating an identical schedule returns the existing action")
	var changed: Dictionary = request.duplicate(true)
	changed.to = _fixture._location("dorm")
	runner.assert_eq(lifecycle.schedule(changed, "player", 3400).get("reason"), "command_conflict", "a command cannot be rescheduled with different data")
	runner.assert_eq(lifecycle.schedule(request, "player", 3401).get("reason"), "command_conflict", "a command cannot change its duration on retry")
	var other_request: Dictionary = _fixture._move("take_second", "second", _fixture._location("ground:create_second"), _fixture._location("actor:player"))
	runner.assert_eq(lifecycle.schedule(other_request, "player", 3400).get("reason"), "actor_busy", "the same body cannot perform two actions concurrently")
	runner.assert_true(world.actor_controls("shi_tou", "action") and not world.owns_for_scope("shi_tou", &"body"), "the second actor is otherwise free to act")
	var same_item: Dictionary = _fixture._move("other_actor_take", "first", source, _fixture._location("actor:shi_tou"))
	runner.assert_eq(lifecycle.schedule(same_item, "shi_tou", 3400).get("reason"), "target_reserved", "another actor cannot take an item reserved by an in-flight action")
	var immediate: Dictionary = _fixture._move("immediate_take", "first", source, _fixture._location("dorm"))
	runner.assert_true(not bool(lifecycle.execute(immediate).get("ok", true)), "an immediate transaction cannot bypass the in-flight reservation")
	var wrong_source: Dictionary = _fixture._move("wrong_source", "second", _fixture._location("dorm"), _fixture._location("actor:shi_tou"))
	runner.assert_eq(lifecycle.schedule(wrong_source, "shi_tou", 3400).get("reason"), "source_changed", "a request cannot start from a location different from the original owner")
	var foreign_actor: Dictionary = _fixture._move("foreign_actor", "second", _fixture._location("ground:create_second"), _fixture._location("actor:player"))
	runner.assert_true(not bool(lifecycle.schedule(foreign_actor, "river_player", 3400).get("ok", true)), "an actor from another region cannot claim a local action")
	runner.assert_true(not bool(lifecycle.schedule(foreign_actor, "missing_actor", 3400).get("ok", true)), "a nonexistent actor cannot run an action")
	runner.assert_eq(world.artifacts.objects.first.container, source.container, "the original remains at its source before time advances")
	runner.assert_true(observer.notices.is_empty(), "scheduling or rejection does not publish a completed transfer")
	var due: int = started + 3400
	runner.assert_true(world.advance_to_ms(due - 1), "the shared world advances up to the millisecond before completion")
	runner.assert_eq(lifecycle.actions.take_first.status, "active", "the action remains active immediately before its deadline")
	runner.assert_eq(world.artifacts.objects.first.container, source.container, "no item moves one millisecond early")
	runner.assert_true(observer.notices.is_empty(), "no success notification is sent early")
	runner.assert_true(world.advance_to_ms(due), "the world reaches the action's real deadline")
	runner.assert_eq(lifecycle.actions.take_first.status, "completed", "the scheduled move completes at its due boundary")
	runner.assert_eq(int(lifecycle.actions.take_first.finished_ms), due, "completion records the actual shared time")
	runner.assert_eq(world.artifacts.objects.first.container, "actor:player", "the original artifact changes its real location once")
	runner.assert_true(not bool(lifecycle.ground.locate("home", source.container).get("active", true)), "completion releases the old ground placement")
	runner.assert_true(not world.owns_for_scope("player", &"body"), "completed work releases the actor")
	runner.assert_eq(observer.notices.size(), 1, "the successful action publishes exactly once")
	runner.assert_true(world.advance_to_ms(due + 1), "the world continues after action completion")
	runner.assert_eq(observer.notices.size(), 1, "later boundaries do not complete or notify again")
	var replay: Dictionary = lifecycle.schedule(request, "player", 3400)
	runner.assert_true(bool(replay.get("ok", false)) and replay.get("action", {}).get("status") == "completed", "a completed schedule retry does not start another action")
	runner.assert_eq(world.artifacts.objects.first.container, "actor:player", "a retry cannot produce a second physical copy")


func _stock_reservation_and_cancel(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._world(runner)
	if world == null or not _spawn_pair(runner, world):
		return
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var inventory: SimInventory = world.regions.home.inventory
	var actor: Dictionary = world.regions.home.actors.player
	var available: int = inventory.available("store", "wood")
	var total: int = _fixture._total(inventory, "wood")
	runner.assert_true(available >= 4, "the original store has wood to reserve")
	if available < 4:
		return
	actor.autonomous = true
	world.invalidate_region("home")
	var request: Dictionary = _fixture._transfer("timed_wood", _fixture._location("store"), _fixture._ground(130, 120), "wood", 4)
	var result: Dictionary = lifecycle.schedule(request, "player", 4000)
	runner.assert_true(bool(result.get("ok", false)), "timed stock transfer reserves the original ledger quantity")
	if not bool(result.get("ok", false)):
		return
	var due: int = int(result.action.due_ms)
	var reservation: String = str(result.action.reservation)
	runner.assert_true(inventory.reservations.has(reservation), "the active action holds a real inventory reservation")
	runner.assert_eq(inventory.available("store", "wood"), available - 4, "reserved quantity is unavailable to other actions")
	runner.assert_true(not bool(actor.autonomous), "timed work temporarily occupies the actor's prior autonomy")
	var competing: bool = inventory.transfer("competing_wood", "store", "actor:shi_tou", "wood", available)
	runner.assert_true(not competing, "another ledger operation cannot spend the reserved material")
	runner.assert_eq(_fixture._total(inventory, "wood"), total, "reserving or a failed competing transfer does not move stock")
	runner.assert_true(not lifecycle.ground.slots.has("ground:timed_wood"), "no destination pile appears while work is in progress")
	runner.assert_true(world.advance_to_ms(due - 1), "the world reaches the cancellation point before work is due")
	runner.assert_true(lifecycle.cancel("player"), "an in-flight action can be cancelled")
	runner.assert_eq(lifecycle.actions.timed_wood.status, "cancelled", "the original action records cancellation")
	runner.assert_true(not inventory.reservations.has(reservation), "cancellation releases the real stock reservation")
	runner.assert_eq(inventory.available("store", "wood"), available, "cancelled material is available again")
	runner.assert_true(bool(actor.autonomous), "cancellation restores the actor's previous autonomy")
	runner.assert_true(not world.owns_for_scope("player", &"body"), "cancellation frees the actor's body scope")
	runner.assert_true(not lifecycle.cancel("player"), "cancellation cannot repeat on an already finished action")
	var retry: Dictionary = lifecycle.schedule(request, "player", 4000)
	runner.assert_true(bool(retry.get("ok", false)) and retry.get("action", {}).get("status") == "cancelled", "retrying a cancelled command does not restart it")
	# Suppress unrelated voluntary work after proving restoration of autonomy.
	actor.autonomous = false
	world.invalidate_region("home")
	runner.assert_true(world.advance_to_ms(due + 1), "the world continues beyond the cancelled deadline")
	runner.assert_eq(_fixture._total(inventory, "wood"), total, "cancelled work cannot later create or consume material")
	runner.assert_true(not lifecycle.ground.slots.has("ground:timed_wood"), "cancelled work never publishes a ground pile")


func _revalidate_changed_destination(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._world(runner)
	if world == null:
		return
	var map: WorldMapData = WorldMapData.from_descriptor(WorldMapData.flat_descriptor(20261105))
	if map == null:
		runner.assert_true(false, "the independent flat map can be prepared for a real terrain change")
		return
	var prepared: Dictionary = map.apply_terrain_patch([[120, 120, WorldMapData.TERRAIN_GRASS], [121, 120, WorldMapData.TERRAIN_GRASS], [125, 120, WorldMapData.TERRAIN_GRASS]])
	runner.assert_true(bool(prepared.get("ok", false)), "the source and destination start on actual walkable map cells")
	if not bool(prepared.get("ok", false)):
		return
	world.bind_map_data(map)
	if not _spawn_pair(runner, world):
		return
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var source: Dictionary = _fixture._location("ground:create_first")
	var request: Dictionary = _fixture._move("move_to_changed", "first", source, _fixture._ground(125, 120))
	var scheduled: Dictionary = lifecycle.schedule(request, "player", 3500)
	runner.assert_true(bool(scheduled.get("ok", false)), "a move may begin while its destination is clear")
	if not bool(scheduled.get("ok", false)):
		return
	# This changes the actual map owner after scheduling, without fabricating a
	# query or action result. Developer-level map edits do not grant gameplay permission.
	var terrain_change: Dictionary = map.apply_terrain_patch([[125, 120, WorldMapData.TERRAIN_WATER]])
	runner.assert_true(bool(terrain_change.get("ok", false)) and not map.terrain_is_walkable(Vector2i(125, 120)), "the authoritative destination terrain changes before completion")
	if not bool(terrain_change.get("ok", false)):
		return
	var due: int = int(scheduled.action.due_ms)
	runner.assert_true(world.advance_to_ms(due), "the world reaches the scheduled completion boundary")
	runner.assert_eq(lifecycle.actions.move_to_changed.status, "failed", "the action rechecks the actual blocked destination")
	runner.assert_true(not bool(lifecycle.actions.move_to_changed.result.get("ok", true)), "changed geometry returns an explicit action failure")
	runner.assert_eq(world.artifacts.objects.first.container, source.container, "failed completion retains the original at its source")
	runner.assert_true(bool(lifecycle.ground.locate("home", source.container).get("active", false)), "the original source placement remains active")
	runner.assert_true(not lifecycle.ground.slots.has("ground:move_to_changed"), "failed completion creates no destination slot")
	runner.assert_true(not lifecycle.receipts.has("move_to_changed"), "a rejected completion records no successful transaction receipt")
	runner.assert_true(not map.terrain_is_walkable(Vector2i(125, 120)), "failed completion does not undo the independent terrain change")


func _revalidate_changed_source(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._world(runner)
	if world == null:
		return
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var create: Dictionary = {"command": "create_stored", "op": "spawn", "id": "stored_item", "definition": "plain_slate", "to": _fixture._location("dorm")}
	var created: Dictionary = lifecycle.execute(create)
	runner.assert_true(bool(created.get("ok", false)), "a real original item starts in the existing dorm container")
	if not bool(created.get("ok", false)):
		return
	var request: Dictionary = _fixture._move("move_changed_source", "stored_item", _fixture._location("dorm"), _fixture._location("actor:player"))
	var scheduled: Dictionary = lifecycle.schedule(request, "player", 3200)
	runner.assert_true(bool(scheduled.get("ok", false)), "a timed move can start from the original stored item")
	if not bool(scheduled.get("ok", false)):
		return
	# A different owner-side operation is represented by changing the original
	# container fact; no second item or false ground slot is introduced.
	world.artifacts.objects.stored_item.container = "actor:shi_tou"
	world.invalidate_region("home")
	runner.assert_true(world.advance_to_ms(int(scheduled.action.due_ms)), "the world reaches the source revalidation boundary")
	runner.assert_eq(lifecycle.actions.move_changed_source.status, "failed", "the changed original source prevents completion")
	runner.assert_eq(lifecycle.actions.move_changed_source.result.get("reason"), "source_changed", "the failure distinguishes a changed source")
	runner.assert_eq(world.artifacts.objects.stored_item.container, "actor:shi_tou", "failed work does not overwrite the current original location")
	runner.assert_true(not lifecycle.receipts.has("move_changed_source"), "a source mismatch produces no successful receipt")


func _save_and_continue_inflight(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._world(runner)
	if world == null or not _spawn_pair(runner, world):
		return
	var inventory: SimInventory = world.regions.home.inventory
	var total: int = _fixture._total(inventory, "wood")
	var request: Dictionary = _fixture._transfer("saved_action", _fixture._location("store"), _fixture._ground(130, 120), "wood", 4)
	var scheduled: Dictionary = world.object_lifecycle.schedule(request, "player", 3600)
	runner.assert_true(bool(scheduled.get("ok", false)), "the world starts an action with a real ledger reservation")
	if not bool(scheduled.get("ok", false)):
		return
	var due: int = int(scheduled.action.due_ms)
	runner.assert_true(world.advance_to_ms(due - 1000), "the action can be saved while still in progress")
	var saved_json: String = _fixture._state(world)
	var snapshot: Variant = JSON.parse_string(saved_json)
	var candidate: RegionalSimulation = _fixture._world(runner)
	if candidate == null or not snapshot is Dictionary:
		runner.assert_true(false, "the in-flight snapshot and independent candidate exist")
		return
	var restored: bool = candidate.restore(snapshot)
	runner.assert_true(restored, "an independent world restores the action and its original reservation")
	if not restored:
		return
	runner.assert_eq(_fixture._state(candidate), saved_json, "the restored candidate retains the complete in-flight state")
	var reservation: String = str(scheduled.action.reservation)
	runner.assert_true(candidate.regions.home.inventory.reservations.has(reservation), "the restored reservation remains in the original inventory")
	runner.assert_eq(candidate.object_lifecycle.actions.saved_action.status, "active", "the restored action remains active until due")
	runner.assert_true(not candidate.object_lifecycle.ground.slots.has("ground:saved_action"), "restoration does not publish the unfinished result")
	runner.assert_true(world.advance_to_ms(due), "the original action reaches its deadline")
	runner.assert_true(candidate.advance_to_ms(due), "the independently restored action reaches the same deadline")
	runner.assert_eq(candidate.object_lifecycle.actions.saved_action.status, "completed", "the restored action completes once")
	runner.assert_eq(candidate.regions.home.inventory.quantity("ground:saved_action", "wood"), 4, "restored completion deposits the reserved original stock")
	runner.assert_true(not candidate.regions.home.inventory.reservations.has(reservation), "restored completion releases its reservation")
	runner.assert_eq(_fixture._total(candidate.regions.home.inventory, "wood"), total, "restored completion conserves real wood")
	runner.assert_eq(_fixture._state(candidate), _fixture._state(world), "original and restored worlds have the same completed state")
	var replay: Dictionary = candidate.object_lifecycle.schedule(request, "player", 3600)
	runner.assert_true(bool(replay.get("ok", false)) and replay.action.status == "completed", "a restored completed command retry cannot consume stock twice")
	runner.assert_eq(candidate.regions.home.inventory.quantity("ground:saved_action", "wood"), 4, "retry preserves the one completed pile")


func _bounded_and_segmented_advancement(runner: Object) -> void:
	var whole: RegionalSimulation = _fixture._world(runner)
	var bounded: RegionalSimulation = _fixture._world(runner)
	if whole == null or bounded == null or not _spawn_pair(runner, whole) or not _spawn_pair(runner, bounded):
		return
	var request: Dictionary = _fixture._move("budgeted_move", "first", _fixture._location("ground:create_first"), _fixture._location("actor:player"))
	var first: Dictionary = whole.object_lifecycle.schedule(request, "player", 65000)
	var second: Dictionary = bounded.object_lifecycle.schedule(request, "player", 65000)
	runner.assert_true(bool(first.get("ok", false)) and bool(second.get("ok", false)), "identical worlds start identical long actions")
	if not bool(first.get("ok", false)) or not bool(second.get("ok", false)):
		return
	var deadline: int = int(first.action.due_ms)
	var finish: int = deadline + 65000
	runner.assert_true(whole.advance_to_ms(finish), "one long request advances past the action's deadline")
	var completed_in_budget: bool = bounded.advance_to_ms(finish, 1)
	runner.assert_true(not completed_in_budget and bounded.elapsed_ms < finish, "a small event budget yields before the full requested time")
	runner.assert_eq(bounded.target_ms, finish, "budget exhaustion preserves the original future target")
	runner.assert_true(bounded.advance_to_ms(finish), "the bounded world can resume its owed time")
	for candidate: RegionalSimulation in [whole, bounded]:
		runner.assert_eq(candidate.elapsed_ms, finish, "each world reaches the same committed time")
		runner.assert_eq(candidate.target_ms, finish, "no requested time is silently dropped")
		runner.assert_eq(candidate.object_lifecycle.actions.budgeted_move.status, "completed", "the action completes even when its deadline precedes the request target")
		runner.assert_eq(int(candidate.object_lifecycle.actions.budgeted_move.finished_ms), deadline, "completion occurs at the actual due time")
		runner.assert_eq(candidate.artifacts.objects.first.container, "actor:player", "the same original object moves into the actor container")
		runner.assert_true(not bool(candidate.object_lifecycle.ground.locate("home", "ground:create_first").get("active", true)), "no stale source placement survives the move")
	runner.assert_eq(_fixture._state(bounded), _fixture._state(whole), "one long advance and a bounded continuation preserve the same world state")


func _callback_cancellation_at_shared_deadline(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._world(runner)
	if world == null or not _spawn_pair(runner, world):
		return
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var observer := CancelOtherObserver.new(lifecycle)
	lifecycle.committed.connect(observer.on_committed)
	var first: Dictionary = _fixture._move("a_callback_move", "first", _fixture._location("ground:create_first"), _fixture._location("actor:player"))
	var second: Dictionary = _fixture._move("b_callback_cancelled", "second", _fixture._location("ground:create_second"), _fixture._location("actor:shi_tou"))
	var a: Dictionary = lifecycle.schedule(first, "player", 3500)
	var b: Dictionary = lifecycle.schedule(second, "shi_tou", 3500)
	runner.assert_true(bool(a.get("ok", false)) and bool(b.get("ok", false)), "two actors can schedule distinct items for the same deadline")
	if not bool(a.get("ok", false)) or not bool(b.get("ok", false)):
		return
	runner.assert_eq(int(a.action.due_ms), int(b.action.due_ms), "both commands really share one deadline")
	runner.assert_true(world.advance_to_ms(int(a.action.due_ms)), "the shared clock reaches both scheduled deadlines")
	runner.assert_true(observer.cancelled, "the first completion callback cancels the other actor's still-active work")
	runner.assert_eq(observer.notices, ["a_callback_move"], "only the first actual commit emits a completion notification")
	runner.assert_eq(lifecycle.actions.a_callback_move.status, "completed", "the first action commits exactly once")
	runner.assert_eq(lifecycle.actions.b_callback_cancelled.status, "cancelled", "the second action stays cancelled after callback re-entry")
	runner.assert_eq(lifecycle.actions.b_callback_cancelled.result.get("reason"), "cancelled", "the second action retains its cancellation result")
	runner.assert_true(not lifecycle.receipts.has("b_callback_cancelled"), "cancelled work has no successful transaction receipt")
	runner.assert_eq(world.artifacts.objects.first.container, "actor:player", "the first original reached its real destination")
	runner.assert_eq(world.artifacts.objects.second.container, "ground:create_second", "the cancelled original remains at its source")
	runner.assert_true(bool(lifecycle.ground.locate("home", "ground:create_second").get("active", false)), "cancelled work leaves the second ground footprint active")
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 1), "the world continues after the shared deadline")
	runner.assert_eq(lifecycle.actions.b_callback_cancelled.status, "cancelled", "later boundaries cannot resurrect the cancelled command")
	runner.assert_eq(observer.notices, ["a_callback_move"], "later boundaries cannot publish a cancelled command")


func _timed_merge_into_existing_pile(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._world(runner)
	if world == null:
		return
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var inventory: SimInventory = world.regions.home.inventory
	var available: int = inventory.available("store", "wood")
	var store_before: int = inventory.quantity("store", "wood")
	runner.assert_true(available >= 5, "the real store can fund the seed pile and later timed merge")
	if available < 5:
		return
	var original_total: int = _fixture._total(inventory, "wood")
	var pile: Dictionary = lifecycle.execute(_fixture._transfer("seed_merge_pile", _fixture._location("store"), _fixture._ground(130, 120), "wood", 3))
	runner.assert_true(bool(pile.get("ok", false)), "an existing pile is created from the actual source ledger")
	if not bool(pile.get("ok", false)):
		return
	var request: Dictionary = _fixture._transfer("timed_merge_pile", _fixture._location("store"), _fixture._ground(130, 120), "wood", 2)
	var scheduled: Dictionary = lifecycle.schedule(request, "player", 3500)
	runner.assert_true(bool(scheduled.get("ok", false)), "timed work can reserve wood to merge into the existing same-material pile")
	if not bool(scheduled.get("ok", false)):
		return
	var reservation: String = str(scheduled.action.reservation)
	runner.assert_true(inventory.reservations.has(reservation), "the timed merge reserves the original source quantity")
	runner.assert_eq(inventory.quantity("ground:seed_merge_pile", "wood"), 3, "the existing pile is unchanged before completion")
	runner.assert_eq(_fixture._total(inventory, "wood"), original_total, "a pending merge has not created or destroyed wood")
	runner.assert_true(world.advance_to_ms(int(scheduled.action.due_ms)), "the world reaches the actual merge deadline")
	runner.assert_eq(lifecycle.actions.timed_merge_pile.status, "completed", "the same-material timed transfer completes")
	runner.assert_true(not inventory.reservations.has(reservation), "successful completion releases the source reservation")
	runner.assert_eq(inventory.quantity("ground:seed_merge_pile", "wood"), 5, "the real destination ledger holds the merged quantity")
	runner.assert_eq(inventory.quantity("store", "wood"), store_before - 5, "the actual source loses exactly the two transfers")
	runner.assert_eq(_fixture._total(inventory, "wood"), original_total, "seeding and merging conserve the original total")
	runner.assert_true(not lifecycle.ground.slots.has("ground:timed_merge_pile"), "merging does not fabricate a second ground slot")
	var located: Dictionary = lifecycle.ground.query(Rect2i(130, 120, 1, 1))
	runner.assert_eq(located.get("ids"), ["ground:seed_merge_pile"], "one original pile remains at the destination")
