extends RefCounted
## Exercise real world owners through the shared lifecycle entry point.
## These commands are authority-only and do not imply player reach or consent.

const Fixture = preload("res://tests/sim/test_world_object_query.gd")
const Receipt = preload("res://scripts/sim/object_receipts.gd")

# Fixture-owned callbacks retain these helpers for the lifetime of each world.
var _fixture := Fixture.new()


func run(runner: Object) -> void:
	_unique_item_identity_and_geometry(runner)
	_material_split_merge_and_conflicts(runner)
	_independent_restore_and_rejection(runner)
	_compact_timed_stock_restore(runner)
	_construction_inventory_boundaries(runner)
	print("SCENARIO object lifecycle: unique identity, cross-block footprints, real stock conservation, idempotent commands and independent restore")


func _world(runner: Object) -> RegionalSimulation:
	var opening: Dictionary = _fixture._world(runner)
	if opening.is_empty():
		return null
	var world: RegionalSimulation = opening.world
	world.bind_map_data(Fixture.FlatMap.new())
	return world


func _spawn(command: String, id: String, definition: String, cell: Array) -> Dictionary:
	return {"command": command, "op": "spawn", "id": id, "definition": definition,
		"to": {"region": "home", "cell": cell}}


func _move(command: String, id: String, source: Dictionary, destination: Dictionary) -> Dictionary:
	return {"command": command, "op": "move", "id": id,
		"from": source.duplicate(true), "to": destination.duplicate(true)}


func _transfer(command: String, source: Dictionary, destination: Dictionary, item: String, amount: int) -> Dictionary:
	return {"command": command, "op": "stock_transfer", "from": source.duplicate(true),
		"to": destination.duplicate(true), "item": item, "amount": amount}


func _location(container: String) -> Dictionary:
	return {"region": "home", "container": container}


func _ground(x: int, y: int) -> Dictionary:
	return {"region": "home", "cell": [x, y]}


func _state(world: RegionalSimulation) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(world.to_dict()))


func _total(inventory: SimInventory, item: String) -> int:
	var amount: int = 0
	for container: String in inventory.containers:
		amount += inventory.quantity(container, item)
	return amount


func _unique_item_identity_and_geometry(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var original_objects: int = world.artifacts.objects.size()
	var create: Dictionary = _spawn("create_slate", "slate_instance", "plain_slate", [120, 120])
	var created: Dictionary = lifecycle.execute(create)
	runner.assert_true(bool(created.get("ok", false)), "a physical item is created through its real owner")
	if not bool(created.get("ok", false)):
		return
	var reference: Dictionary = {"kind": "artifact", "id": "slate_instance"}
	var first_location: Dictionary = _location("ground:create_slate")
	runner.assert_eq(created.reference, reference, "creation returns the unique real artifact reference")
	runner.assert_eq(created.to, first_location, "creation resolves the real ground placement")
	var described: Dictionary = world.describe_object(reference)
	runner.assert_true(bool(described.get("ok", false)), "the shared object query observes the newly created original")
	if bool(described.get("ok", false)):
		runner.assert_eq(described.spatial.cells, [Vector2i(120, 120)], "the shared query reads its actual ground cell")
		runner.assert_eq(described.spatial.relation, "placed", "a floor item is distinguished from a contained item")
	runner.assert_eq(world.artifacts.objects.size(), original_objects + 1, "one successful creation produces exactly one original artifact")
	runner.assert_eq(world.artifacts.objects.slate_instance.definition, "plain_slate", "the instance retains its original definition")
	runner.assert_eq(lifecycle.execute(create), created, "repeating the same command returns its original outcome")
	runner.assert_eq(world.artifacts.objects.size(), original_objects + 1, "a retried create cannot duplicate an item")
	var conflict: Dictionary = create.duplicate(true)
	conflict.to = _ground(121, 120)
	runner.assert_eq(lifecycle.execute(conflict).get("reason"), "command_conflict", "a command identifier cannot be reused for different work")
	var duplicate_id: Dictionary = _spawn("other_creation", "slate_instance", "plain_slate", [121, 120])
	runner.assert_true(not bool(lifecycle.execute(duplicate_id).get("ok", true)), "a second command cannot reuse a live artifact identity")
	runner.assert_true(not lifecycle.ground.slots.has("ground:other_creation"), "rejected duplicate identity leaves no ground slot")

	# The two-cell object straddles the spatial bucket boundary at x=128.
	var wide: Dictionary = lifecycle.execute(_spawn("create_slab", "slab_instance", "stone_slab", [127, 120]))
	runner.assert_true(bool(wide.get("ok", false)), "a defined multi-cell physical object can be placed")
	if not bool(wide.get("ok", false)):
		return
	for point: Vector2i in [Vector2i(127, 120), Vector2i(128, 120)]:
		var found: Dictionary = lifecycle.ground.query(Rect2i(point, Vector2i.ONE))
		runner.assert_true(bool(found.get("ok", false)) and found.get("ids", []).has("ground:create_slab"), "both sides of the bucket boundary resolve one original slab")
	var wide_description: Dictionary = world.describe_object(wide.reference)
	runner.assert_true(bool(wide_description.get("ok", false)), "the same shared query resolves a different defined object")
	if bool(wide_description.get("ok", false)):
		runner.assert_eq(wide_description.spatial.cells, [Vector2i(127, 120), Vector2i(128, 120)], "one real slab exposes its complete two-cell footprint")
	var before_overlap: String = _state(world)
	var overlap: Dictionary = lifecycle.execute(_spawn("overlap_slab", "another_instance", "plain_slate", [128, 120]))
	runner.assert_true(not bool(overlap.get("ok", true)), "a different item cannot overwrite any occupied footprint cell")
	runner.assert_true(not lifecycle.ground.slots.has("ground:overlap_slab"), "a rejected footprint has no published slot")
	runner.assert_eq(_state(world), before_overlap, "overlap rejection leaves the complete original world unchanged")
	var adjacent: Dictionary = lifecycle.execute(_spawn("adjacent_slate", "adjacent_instance", "plain_slate", [129, 120]))
	runner.assert_true(bool(adjacent.get("ok", false)), "a different item can exist in a separate legal cell")
	if not bool(adjacent.get("ok", false)):
		return

	var move_to_body: Dictionary = _move("hold_slate", "slate_instance", first_location, _location("actor:player"))
	var held: Dictionary = lifecycle.execute(move_to_body)
	runner.assert_true(bool(held.get("ok", false)), "the same item moves from ground to the original actor container")
	if not bool(held.get("ok", false)):
		return
	runner.assert_eq(held.reference, reference, "moving the item preserves its unique identity")
	runner.assert_eq(held.to, _location("actor:player"), "the original artifact now points to the actor container")
	runner.assert_eq(world.artifacts.objects.slate_instance.container, "actor:player", "the authoritative artifact owner records the move")
	var held_description: Dictionary = world.describe_object(reference)
	runner.assert_true(bool(held_description.get("ok", false)), "the original item remains queryable when carried")
	if bool(held_description.get("ok", false)):
		runner.assert_eq(held_description.spatial.relation, "contained", "the carried item is not projected as a floor placement")
	runner.assert_true(not bool(lifecycle.ground.locate("home", first_location.container).get("active", true)), "the old floor location is no longer active")
	var former_cell: Dictionary = lifecycle.ground.query(Rect2i(Vector2i(120, 120), Vector2i.ONE))
	runner.assert_true(bool(former_cell.get("ok", false)) and former_cell.ids.is_empty(), "carrying an item does not leave a second floor copy")
	runner.assert_eq(lifecycle.execute(move_to_body), held, "retry after the source changed returns the original move receipt")
	var stored: Dictionary = lifecycle.execute(_move("store_slate", "slate_instance", held.to, _location("dorm")))
	runner.assert_true(bool(stored.get("ok", false)), "the held object moves into an existing real container")
	if not bool(stored.get("ok", false)):
		return
	runner.assert_eq(stored.reference, reference, "the real identity survives a second transfer")
	runner.assert_eq(world.artifacts.objects.slate_instance.container, "dorm", "the original artifact is stored in dorm")
	var dropped: Dictionary = lifecycle.execute(_move("redrop_slate", "slate_instance", stored.to, _ground(121, 120)))
	runner.assert_true(bool(dropped.get("ok", false)), "the stored object may return to a legal ground position")
	if not bool(dropped.get("ok", false)):
		return
	var remove: Dictionary = {"command": "remove_slate", "op": "remove", "id": "slate_instance", "from": dropped.to.duplicate(true)}
	var removed: Dictionary = lifecycle.execute(remove)
	runner.assert_true(bool(removed.get("ok", false)) and bool(removed.get("removed", false)), "explicit removal terminates the original item")
	if not bool(removed.get("ok", false)):
		return
	runner.assert_true(not world.artifacts.objects.has("slate_instance"), "removal eliminates the one original artifact")
	runner.assert_eq(world.describe_object(reference).get("reason"), "not_found", "a removed identity no longer resolves in the shared query")
	runner.assert_true(not bool(lifecycle.ground.locate("home", dropped.to.container).get("active", true)), "removal releases the physical floor position")
	runner.assert_eq(lifecycle.execute(remove), removed, "the same removal may be retried without removing another object")
	runner.assert_true(not bool(lifecycle.execute(_spawn("recycle_id", "slate_instance", "plain_slate", [122, 120])).get("ok", true)), "a removed identity cannot be silently reused")
	runner.assert_true(world.artifacts.objects.has("slab_instance") and world.artifacts.objects.has("adjacent_instance"), "removing one item preserves neighboring originals")


func _material_split_merge_and_conflicts(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var inventory: SimInventory = world.regions.home.inventory
	var source: Dictionary = _location("store")
	var original_wood: int = _total(inventory, "wood")
	var original_grain: int = _total(inventory, "grain")
	var initial_store: int = inventory.quantity("store", "wood")
	runner.assert_true(inventory.available("store", "wood") >= 7, "the real opening stock provides the material to split")
	if inventory.available("store", "wood") < 7:
		return
	var drop: Dictionary = _transfer("drop_wood", source, _ground(130, 120), "wood", 4)
	var dropped: Dictionary = lifecycle.execute(drop)
	runner.assert_true(bool(dropped.get("ok", false)), "ordinary stock is transferred from its real store to the ground")
	if not bool(dropped.get("ok", false)):
		return
	var pile: Dictionary = _location("ground:drop_wood")
	runner.assert_eq(dropped.to, pile, "the first drop resolves to one ground container")
	runner.assert_true(lifecycle.receipts.drop_wood is Array, "a new stock receipt is kept in compact form")
	var drop_receipt: Dictionary = lifecycle._receipt("drop_wood")
	runner.assert_eq(drop_receipt.request, drop, "a compact receipt reconstructs the original stock request")
	runner.assert_eq(drop_receipt.result, dropped, "a compact receipt reconstructs every original result field")
	runner.assert_eq(int(drop_receipt.at_ms), world.elapsed_ms, "compact provenance retains the shared commit time")
	runner.assert_eq(int(drop_receipt.sequence), lifecycle.receipts.size(), "compact provenance retains the commit sequence")
	drop_receipt.request.to.cell[0] = 1
	drop_receipt.result.reference.container = "tampered"
	runner.assert_eq(lifecycle.execute(drop), dropped, "mutating a decoded projection cannot alter the receipt owner")
	var conflict: Dictionary = drop.duplicate(true)
	conflict.to = _ground(131, 120)
	runner.assert_eq(lifecycle.execute(conflict).get("reason"), "command_conflict", "compact provenance still rejects a changed request for the same command")
	var extended: Dictionary = dropped.duplicate(true)
	extended["future_field"] = {"evidence": "retained"}
	var fallback: Variant = Receipt.encode(drop, extended, 0, 1)
	runner.assert_true(fallback is Dictionary, "an unfamiliar result shape is never compacted by dropping fields")
	runner.assert_eq(Receipt.decode(fallback, "drop_wood").result, extended, "fallback preserves an unknown result field")
	var pile_description: Dictionary = world.describe_object(dropped.reference)
	runner.assert_true(bool(pile_description.get("ok", false)), "the shared query observes the real ground stock entry")
	if bool(pile_description.get("ok", false)):
		runner.assert_eq(pile_description.spatial.cells, [Vector2i(130, 120)], "the stock entry resolves its real ground location")
		runner.assert_eq(pile_description.attributes.quantity, 4, "stock query reads quantity from the original ledger")
	runner.assert_eq(inventory.quantity("store", "wood"), initial_store - 4, "material is deducted from its original ledger")
	runner.assert_eq(inventory.quantity(pile.container, "wood"), 4, "the original ledger holds the real floor quantity")
	runner.assert_eq(lifecycle.execute(drop), dropped, "retrying a stock command returns its committed receipt")
	runner.assert_eq(inventory.quantity(pile.container, "wood"), 4, "retrying the drop does not duplicate stock")
	var merge: Dictionary = _transfer("merge_wood", source, _ground(130, 120), "wood", 3)
	var added: Dictionary = lifecycle.execute(merge)
	runner.assert_true(bool(added.get("ok", false)), "the same ordinary material may merge into the existing pile")
	if not bool(added.get("ok", false)):
		return
	runner.assert_eq(added.to, pile, "merged stock retains the original ground container")
	runner.assert_eq(lifecycle._receipt("merge_wood").request, merge, "merged receipt retains the requested ground cell")
	runner.assert_eq(lifecycle._receipt("merge_wood").result, added, "merged receipt retains the actual existing container")
	runner.assert_eq(inventory.quantity(pile.container, "wood"), 7, "the shared original ledger records the merged quantity")
	runner.assert_true(not lifecycle.ground.slots.has("ground:merge_wood"), "merging does not create a second physical pile")
	var before_conflict: String = _state(world)
	var wrong_item: Dictionary = lifecycle.execute(_transfer("drop_grain_overlap", source, _ground(130, 120), "grain", 1))
	runner.assert_true(not bool(wrong_item.get("ok", true)), "different materials cannot be mixed into the same ground pile")
	runner.assert_true(not lifecycle.ground.slots.has("ground:drop_grain_overlap"), "an incompatible drop creates no orphan placement")
	runner.assert_eq(_state(world), before_conflict, "incompatible material leaves both source and destination unchanged")
	var excessive: Dictionary = lifecycle.execute(_transfer("excessive_wood", source, _ground(132, 120), "wood", initial_store + 1))
	runner.assert_true(not bool(excessive.get("ok", true)), "unavailable stock cannot be created by a transfer")
	runner.assert_true(not lifecycle.ground.slots.has("ground:excessive_wood"), "insufficient-stock rejection leaves no destination slot")
	var reservable: int = inventory.available("store", "wood")
	var reserved: bool = inventory.reserve("protected_wood", "store", "wood", reservable, "player")
	runner.assert_true(reserved, "existing ledger can protect the remaining source stock")
	if reserved:
		var protected_result: Dictionary = lifecycle.execute(_transfer("reserved_wood", source, _ground(132, 120), "wood", 1))
		runner.assert_true(not bool(protected_result.get("ok", true)), "a ground transfer cannot consume stock reserved by another action")
		runner.assert_true(not lifecycle.ground.slots.has("ground:reserved_wood"), "reservation refusal does not create an empty pile")
		inventory.release("protected_wood")
	var pick: Dictionary = _transfer("pick_wood", pile, _location("actor:player"), "wood", 2)
	var take: Dictionary = lifecycle.execute(pick)
	runner.assert_true(bool(take.get("ok", false)), "part of a pile moves to the real actor container")
	if not bool(take.get("ok", false)):
		return
	runner.assert_true(lifecycle.receipts.pick_wood is Array, "a container destination also uses a compact stock receipt")
	runner.assert_eq(lifecycle._receipt("pick_wood").request, pick, "compact stock provenance retains its ground source and container destination")
	runner.assert_eq(lifecycle._receipt("pick_wood").result, take, "container transfer reconstructs its entire result")
	runner.assert_eq(inventory.quantity(pile.container, "wood"), 5, "picking part of a pile leaves the remaining amount")
	var split: Dictionary = lifecycle.execute(_transfer("split_wood", _location("actor:player"), _ground(131, 120), "wood", 2))
	runner.assert_true(bool(split.get("ok", false)), "the carried portion can be placed in a different ground cell")
	if not bool(split.get("ok", false)):
		return
	runner.assert_eq(inventory.quantity("ground:split_wood", "wood"), 2, "the second pile has its own actual ledger quantity")
	var collect: Dictionary = lifecycle.execute(_transfer("collect_wood", pile, _location("dorm"), "wood", 5))
	runner.assert_true(bool(collect.get("ok", false)), "the remaining quantity can move into another real container")
	if not bool(collect.get("ok", false)):
		return
	runner.assert_eq(inventory.quantity(pile.container, "wood"), 0, "collecting the pile removes all original ground stock")
	runner.assert_true(not bool(lifecycle.ground.locate("home", pile.container).get("active", true)), "an emptied pile no longer occupies its cell")
	runner.assert_eq(_total(inventory, "wood"), original_wood, "split, merge, carry and collect conserve all real wood")
	runner.assert_eq(_total(inventory, "grain"), original_grain, "a rejected different material leaves its original stock unchanged")


func _independent_restore_and_rejection(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var spawn: Dictionary = _spawn("saved_slab", "saved_slab_instance", "stone_slab", [127, 120])
	var original_item: Dictionary = lifecycle.execute(spawn)
	var original_stock: Dictionary = lifecycle.execute(_transfer("saved_wood", _location("store"), _ground(130, 120), "wood", 4))
	var merge_request: Dictionary = _transfer("saved_merge", _location("store"), _ground(130, 120), "wood", 1)
	var merged_stock: Dictionary = lifecycle.execute(merge_request)
	var pick_request: Dictionary = _transfer("saved_pick", _location("ground:saved_wood"), _location("actor:player"), "wood", 1)
	var picked_stock: Dictionary = lifecycle.execute(pick_request)
	runner.assert_true(bool(original_item.get("ok", false)) and bool(original_stock.get("ok", false)) and bool(merged_stock.get("ok", false)) and bool(picked_stock.get("ok", false)), "saved fixture contains a real item, a merged pile and a transfer to a container")
	if not bool(original_item.get("ok", false)) or not bool(original_stock.get("ok", false)) or not bool(merged_stock.get("ok", false)) or not bool(picked_stock.get("ok", false)):
		return
	var saved_json: String = _state(world)
	var saved: Variant = JSON.parse_string(saved_json)
	runner.assert_true(saved is Dictionary, "the complete world serializes as a JSON object")
	if not saved is Dictionary:
		return
	var candidate: RegionalSimulation = _world(runner)
	if candidate == null:
		return
	var accepted_input: Dictionary = saved.duplicate(true)
	var loaded: bool = candidate.restore(accepted_input)
	runner.assert_true(loaded, "the actual world is restored into an independent candidate")
	if not loaded:
		return
	runner.assert_eq(_state(candidate), saved_json, "independent restoration preserves all original state and quantities")
	runner.assert_eq(candidate.object_lifecycle.execute(spawn), original_item, "a restored create receipt is idempotent")
	var stock_request: Dictionary = _transfer("saved_wood", _location("store"), _ground(130, 120), "wood", 4)
	runner.assert_eq(candidate.object_lifecycle.execute(stock_request), original_stock, "a restored compact stock receipt is idempotent")
	runner.assert_eq(candidate.object_lifecycle.execute(merge_request), merged_stock, "a restored ground merge replays its actual existing destination")
	runner.assert_eq(candidate.object_lifecycle.execute(pick_request), picked_stock, "a restored container transfer replays its original result")
	accepted_input.object_lifecycle.receipts.saved_wood[4] = 400
	runner.assert_eq(_state(candidate), saved_json, "mutating a restored input array cannot mutate the live receipt owner")
	var scope: Dictionary = SimObjectLifecycle.inventory_scope(saved.object_lifecycle, "home")
	runner.assert_true(scope.operations.has("object_lifecycle:saved_wood"), "compact receipts expose their original inventory operation to candidate loading")
	runner.assert_eq(candidate.regions.home.inventory.quantity("ground:saved_wood", "wood"), 4, "restored stock remains in its one original ledger")
	for point: Vector2i in [Vector2i(127, 120), Vector2i(128, 120)]:
		var found: Dictionary = candidate.object_lifecycle.ground.query(Rect2i(point, Vector2i.ONE))
		runner.assert_true(bool(found.get("ok", false)) and found.get("ids", []).has("ground:saved_slab"), "restoration rebuilds each side of the multi-cell footprint")
	var after_restore: String = _state(candidate)
	var corrupted: Dictionary = saved.duplicate(true)
	if not corrupted.get("object_lifecycle") is Dictionary:
		runner.assert_true(false, "the persisted world owns one object lifecycle state")
		return
	corrupted.object_lifecycle.ground.slots["ground:saved_slab"].reference.id = "missing_artifact"
	runner.assert_true(not candidate.restore(corrupted), "a candidate with a forged ground-to-artifact reference is rejected")
	runner.assert_eq(_state(candidate), after_restore, "failed candidate restore does not partially change the live world")
	var enlarged: Dictionary = saved.duplicate(true)
	enlarged.object_lifecycle.ground.slots["ground:saved_slab"].size = [1, 1]
	runner.assert_true(not candidate.restore(enlarged), "saved placement cannot shrink a two-cell original definition")
	var forged_stock: Dictionary = saved.duplicate(true)
	forged_stock.object_lifecycle.receipts.saved_wood = Receipt.decode(forged_stock.object_lifecycle.receipts.saved_wood, "saved_wood").duplicate(true)
	forged_stock.object_lifecycle.receipts.saved_wood.result.amount = 400
	runner.assert_true(not candidate.restore(forged_stock), "a replay result cannot claim more stock than its original ledger operation")
	forged_stock.object_lifecycle.receipts.saved_wood.result.amount = 4.5
	runner.assert_true(not candidate.restore(forged_stock), "fractional receipt quantities must be rejected before integer normalization")
	var forged_compact: Dictionary = saved.duplicate(true)
	forged_compact.object_lifecycle.receipts.saved_wood[4] = 400
	runner.assert_true(not candidate.restore(forged_compact), "a forged compact quantity cannot disagree with the real inventory operation")
	forged_compact.object_lifecycle.receipts.saved_wood[4] = 4.5
	runner.assert_true(not candidate.restore(forged_compact), "fractional compact quantities are rejected before integer normalization")
	forged_compact.object_lifecycle.receipts.saved_wood[4] = 4
	forged_compact.object_lifecycle.receipts.saved_wood[8] = true
	runner.assert_true(not candidate.restore(forged_compact), "a compact receipt cannot invent an action reservation")
	forged_compact.object_lifecycle.receipts.saved_wood[8] = false
	forged_compact.object_lifecycle.receipts.saved_wood[7] = "ground:other"
	runner.assert_true(not candidate.restore(forged_compact), "a compact receipt cannot replace the actual ground destination")
	var moved_slot: Dictionary = saved.duplicate(true)
	moved_slot.object_lifecycle.ground.slots["ground:saved_slab"].cell = [140, 120]
	runner.assert_true(not candidate.restore(moved_slot), "a slot cannot silently move without a committed request")
	var missing_receipt: Dictionary = saved.duplicate(true)
	missing_receipt.object_lifecycle.created.erase("saved_slab_instance")
	runner.assert_true(not candidate.restore(missing_receipt), "new physical objects require their creation provenance even in a legal container")
	runner.assert_eq(_state(candidate), after_restore, "all malformed object candidates preserve the accepted world")
	runner.assert_eq(_state(world), saved_json, "independent load and bad-candidate rejection do not modify the source world")
	var legacy: Dictionary = saved.duplicate(true)
	var legacy_row: Dictionary = Receipt.decode(legacy.object_lifecycle.receipts.saved_wood, "saved_wood").duplicate(true)
	legacy_row.result.amount = 4.0
	legacy.object_lifecycle.receipts.saved_wood = legacy_row
	var legacy_candidate: RegionalSimulation = _world(runner)
	if legacy_candidate == null:
		return
	var legacy_loaded: bool = legacy_candidate.restore(legacy)
	runner.assert_true(legacy_loaded, "previous full dictionary stock receipts remain readable")
	if legacy_loaded:
		runner.assert_true(legacy_candidate.object_lifecycle._receipt("saved_wood").result.amount is int, "a restored full receipt normalizes its validated amount")
		legacy_row.result.amount = 400
		runner.assert_eq(legacy_candidate.object_lifecycle.execute(stock_request), original_stock, "mutating an old-format input after restore cannot change its live receipt")


func _compact_timed_stock_restore(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var seed: Dictionary = _transfer("compact_seed", _location("store"), _ground(130, 120), "wood", 3)
	var first: Dictionary = world.object_lifecycle.execute(seed)
	runner.assert_true(bool(first.get("ok", false)), "timed compact test has a real existing pile")
	if not bool(first.get("ok", false)):
		return
	var request: Dictionary = _transfer("compact_timed", _location("store"), _ground(130, 120), "wood", 2)
	var started: Dictionary = world.object_lifecycle.schedule(request, "player", 3600)
	runner.assert_true(bool(started.get("ok", false)), "a timed transfer reserves its real stock")
	if not bool(started.get("ok", false)):
		return
	var due: int = int(started.action.due_ms)
	if not world.advance_to_ms(due - 1):
		runner.assert_true(false, "the timed transfer reaches its in-flight checkpoint")
		return
	var pending: Variant = JSON.parse_string(_state(world))
	var resumed: RegionalSimulation = _world(runner)
	if resumed == null or not pending is Dictionary:
		runner.assert_true(false, "the in-flight candidate exists")
		return
	var loaded: bool = resumed.restore(pending)
	runner.assert_true(loaded, "an existing compact receipt and an in-flight reservation restore together")
	if not loaded:
		return
	runner.assert_true(resumed.regions.home.inventory.reservations.has("object_lifecycle:compact_timed"), "the in-flight reservation stays in its original ledger")
	var original_advanced: bool = world.advance_to_ms(due)
	var resumed_advanced: bool = resumed.advance_to_ms(due)
	runner.assert_true(original_advanced and resumed_advanced, "original and restored actions complete at their common deadline")
	if not original_advanced or not resumed_advanced:
		return
	var action: Dictionary = resumed.object_lifecycle.actions.compact_timed
	runner.assert_eq(action.status, "completed", "restored timed transfer completes")
	runner.assert_true(resumed.object_lifecycle.receipts.compact_timed is Array, "completed timed stock uses compact provenance")
	var receipt: Dictionary = resumed.object_lifecycle._receipt("compact_timed")
	runner.assert_eq(receipt.request, request, "timed compact provenance retains the request")
	runner.assert_eq(receipt.result, action.result, "timed compact provenance retains the completed action result")
	runner.assert_eq(receipt.result.to, first.to, "timed merge remembers the existing pile")
	runner.assert_eq(receipt.result.reservation, "object_lifecycle:compact_timed", "timed provenance retains its inventory reservation")
	runner.assert_eq(_state(resumed), _state(world), "restored and original timed completion retain identical state")
	var complete: Variant = JSON.parse_string(_state(resumed))
	var reloaded: RegionalSimulation = _world(runner)
	if reloaded == null or not complete is Dictionary:
		runner.assert_true(false, "the completed candidate exists")
		return
	var restored_complete: bool = reloaded.restore(complete)
	runner.assert_true(restored_complete, "a completed timed compact receipt passes independent cross-validation")
	if not restored_complete:
		return
	runner.assert_eq(reloaded.object_lifecycle.execute(request), action.result, "completed timed command replay returns its original result")
	runner.assert_eq(reloaded.regions.home.inventory.quantity(first.to.container, "wood"), 5, "replay never transfers the reserved stock twice")
	var forged: Dictionary = complete.duplicate(true)
	forged.object_lifecycle.receipts.compact_timed[8] = false
	runner.assert_true(not reloaded.restore(forged), "completed action cannot lose its reservation provenance")


func _construction_inventory_boundaries(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var projects: Array = world.construction.projects.keys()
	runner.assert_true(not projects.is_empty(), "fixture provides an actual construction project and material container")
	if projects.is_empty():
		return
	var project: String = str(projects[0])
	var inventory: SimInventory = world.regions.home.inventory
	runner.assert_true(inventory.containers.has(project), "construction owns the project's actual ledger container")
	if not inventory.containers.has(project):
		return
	var anchor: Dictionary = SimStorageQuery.locate(world, {"domain": "village", "region": "home", "container": project})
	runner.assert_true(bool(anchor.get("ok", false)), "read-only storage lookup can find the project without granting transfer rights")
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var created: Dictionary = lifecycle.execute({"command": "create_project_guard_item", "op": "spawn", "id": "project_guard_item",
		"definition": "plain_slate", "to": _location("dorm")})
	runner.assert_true(bool(created.get("ok", false)), "a real independent item starts in an ordinary container")
	if not bool(created.get("ok", false)):
		return
	var before_move: String = _state(world)
	var moved: Dictionary = lifecycle.execute(_move("move_into_project", "project_guard_item", _location("dorm"), _location(project)))
	runner.assert_true(not bool(moved.get("ok", true)), "a generic artifact move cannot bypass the construction material owner")
	runner.assert_eq(_state(world), before_move, "refusing an artifact in the project preserves the complete original world")
	runner.assert_eq(world.artifacts.objects.project_guard_item.container, "dorm", "the real artifact remains in its original container")
	var available: int = inventory.available("store", "wood")
	runner.assert_true(available > 0, "the fixture has ordinary source wood for the guarded transfer")
	if available <= 0:
		return
	var before_transfer: String = _state(world)
	var transferred: Dictionary = lifecycle.execute(_transfer("stock_into_project", _location("store"), _location(project), "wood", 1))
	runner.assert_true(not bool(transferred.get("ok", true)), "a generic stock transfer cannot write construction's material container")
	runner.assert_eq(_state(world), before_transfer, "a refused project transfer changes neither the ledger nor other world facts")
	# If this real fixture contains project cargo, protect the source direction as
	# well; do not fabricate inventory that bypasses construction provenance.
	for item: String in inventory.containers[project]:
		if inventory.quantity(project, item) <= 0:
			continue
		var before_source: String = _state(world)
		var removed: Dictionary = lifecycle.execute(_transfer("stock_out_of_project", _location(project), _location("dorm"), item, 1))
		runner.assert_true(not bool(removed.get("ok", true)), "a generic transfer cannot take existing construction cargo")
		runner.assert_eq(_state(world), before_source, "refusing the project source preserves its original cargo and world state")
		break
