extends RefCounted
## Read-only storage references inspect the original ledger and physical anchor.

const Query = preload("res://scripts/sim/storage_query.gd")
const EntityFixture = preload("res://tests/sim/test_entity_query.gd")
var _fixtures := EntityFixture.new()


func run(runner: Object) -> void:
	_lookup_and_isolation(runner)
	_native_custody_and_restore(runner)
	_stale_and_backlog(runner)
	print("SCENARIO storage query: original place and body anchors, two region ledgers, real reservation and custody, detached results, stale time and JSON restoration")


func _ref(region: String, container: String, item: String = "") -> Dictionary:
	var value: Dictionary = {"domain": "village", "region": region, "container": container}
	if not item.is_empty():
		value["item"] = item
	return value


func _lookup_and_isolation(runner: Object) -> void:
	var world: RegionalSimulation = _fixtures._world(runner)
	if world == null:
		return
	var before: String = _fixtures._facts(world)
	var home_ref: Dictionary = _ref("home", "store")
	var river_ref: Dictionary = _ref("river", "store")
	var home: Dictionary = Query.locate(world, home_ref)
	var river: Dictionary = Query.locate(world, river_ref)
	var bag: Dictionary = Query.locate(world, _ref("home", "actor:player"))
	runner.assert_true(bool(home.get("ok", false)) and bool(river.get("ok", false)) and bool(bag.get("ok", false)), "real place and actor containers are located")
	if bool(home.get("ok", false)) and bool(river.get("ok", false)) and bool(bag.get("ok", false)):
		runner.assert_eq(home.reference, home_ref, "the returned container reference is domain and region qualified")
		runner.assert_eq(home.state_owner, "village_inventory", "the original inventory owns storage contents")
		runner.assert_eq(home.location_owner, "village_simulation", "the original village owns the place anchor")
		runner.assert_eq(home.record_region, "home", "record region is the original ledger's region")
		runner.assert_eq(home.cell, SimRouteTravel.cell(world.regions.home.places.store.cell), "home store uses its real place cell")
		runner.assert_eq(home.position, TileGrid.cell_to_world(home.cell), "place position is its actual tile center")
		runner.assert_eq(home.carrier, {}, "a fixed place is not a carried container")
		runner.assert_eq(river.record_region, "river", "the same container name in another region selects its own ledger")
		runner.assert_eq(river.cell, SimRouteTravel.cell(world.regions.river.places.store.cell), "river store uses its own place")
		runner.assert_true(home.cell != river.cell, "same-named stores are distinct physical anchors")
		runner.assert_eq(bag.carrier, {"kind": "actor", "id": "player"}, "the pocket names the original carrier")
		runner.assert_eq(bag.position, world.regions.home.actor_position(world.regions.home.actors.player), "pocket uses the body's continuous position")
		runner.assert_true(not home.has("id") and not bag.has("id") and not bag.has("inventory"), "storage creates neither a fictional item identity nor an exposed ledger")
		runner.assert_eq(home.owner_time_ms, world.regions.home.elapsed_ms, "inventory time comes from its village")
		runner.assert_eq(home.location_time_ms, world.regions.home.elapsed_ms, "place anchor retains its village time")
		runner.assert_eq(home.world_time_ms, world.elapsed_ms, "result states the committed world time")
		runner.assert_eq(home.target_time_ms, world.target_ms, "result states the requested target time")
		runner.assert_true(not home.stale and not home.world_has_backlog, "opening owners are current and have no unprocessed target")
		# Both the caller's reference and nested returned values must be detached.
		home.reference.container = "altered"
		bag.carrier.id = "altered"
		home_ref.region = "river"
		var again: Dictionary = Query.locate(world, _ref("home", "store"))
		var bag_again: Dictionary = Query.locate(world, _ref("home", "actor:player"))
		runner.assert_eq(again.reference, _ref("home", "store"), "mutating a previous reference does not alter later results")
		runner.assert_eq(bag_again.carrier, {"kind": "actor", "id": "player"}, "mutating a returned carrier never changes the original body")
	var stock: Dictionary = Query.item(world, _ref("home", "store", "wood"))
	runner.assert_true(bool(stock.get("ok", false)), "an existing inventory entry is queryable")
	if bool(stock.get("ok", false)):
		runner.assert_true(stock.entry_present and not stock.has("id"), "an existing quantity is an entry, not a separate physical object")
		runner.assert_eq(stock.quantity, world.regions.home.inventory.quantity("store", "wood"), "quantity reads the actual inventory")
		runner.assert_eq(stock.available, stock.quantity, "unreserved stock is available")
		runner.assert_eq(stock.entrusted, 0, "the opening store has no entrusted wood")
		stock.quantity = 999999
		stock.reference.item = "water"
		var again: Dictionary = Query.item(world, _ref("home", "store", "wood"))
		runner.assert_eq(again.quantity, world.regions.home.inventory.quantity("store", "wood"), "mutating a quantity projection cannot write the ledger")
	var zero: Dictionary = Query.item(world, _ref("home", "kitchen", "wood"))
	var absent_ref: Dictionary = _ref("home", "actor:player", "unknown_unlisted_material")
	var absent: Dictionary = Query.item(world, absent_ref)
	runner.assert_true(bool(zero.get("ok", false)) and bool(absent.get("ok", false)), "zero and absent item entries remain queryable")
	if bool(zero.get("ok", false)) and bool(absent.get("ok", false)):
		runner.assert_true(zero.entry_present and int(zero.quantity) == 0, "a real zero-valued entry is present")
		runner.assert_true(not absent.entry_present and int(absent.quantity) == 0 and int(absent.available) == 0 and int(absent.entrusted) == 0, "an unlisted item remains an absent zero entry")
		runner.assert_true(not world.regions.home.inventory.containers["actor:player"].has("unknown_unlisted_material"), "querying an absent item never inserts a key")
	var resource: Dictionary = Query.locate(world, _ref("home", "resource:woodlot"))
	var place: String = str(world.regions.home.config.resource_sources.woodlot.place)
	runner.assert_true(bool(resource.get("ok", false)) and resource.cell == SimRouteTravel.cell(world.regions.home.places[place].cell), "resource stock uses its original declared place anchor")
	runner.assert_eq(Query.locate(world, _ref("missing_region", "store")), {"ok": false, "reason": "not_found"}, "unknown region is explicit")
	runner.assert_eq(Query.locate(world, _ref("home", "missing_container")), {"ok": false, "reason": "not_found"}, "unknown container is explicit")
	runner.assert_eq(Query.locate(world, {"domain": "other", "region": "home", "container": "store"}), {"ok": false, "reason": "unsupported_domain"}, "an unimplemented domain is not reinterpreted as village storage")
	runner.assert_eq(Query.locate(world, {"domain": "village", "region": "home", "container": "store", "extra": 1}), {"ok": false, "reason": "invalid_reference"}, "container reference rejects extra fields")
	runner.assert_eq(Query.item(world, {"domain": "village", "region": "home", "container": "store", "item": ""}), {"ok": false, "reason": "invalid_reference"}, "item references require a nonempty string")
	runner.assert_eq(_fixtures._facts(world), before, "all queries and returned-value edits leave original facts and time unchanged")


func _native_custody_and_restore(runner: Object) -> void:
	var world: RegionalSimulation = _fixtures._world(runner)
	if world == null:
		return
	runner.assert_true(world.set_active_region("home"), "the real carrier advances with the active village")
	var sim: VillageSimulation = world.regions.home
	var store_cell: Vector2i = SimRouteTravel.cell(sim.places.store.cell)
	sim.set_actor_cell("player", store_cell + Vector2i(1, 0))
	world.invalidate_region("home")
	var stock: int = sim.inventory.quantity("store", "wood")
	var store_ref: Dictionary = _ref("home", "store", "wood")
	var bag_ref: Dictionary = _ref("home", "actor:player", "wood")
	var started: bool = sim.submit_action("player", "deliver_wood")
	runner.assert_true(started, "native haul reserves a real source before travel")
	if not started:
		return
	world.invalidate_region("home")
	var reserved: Dictionary = Query.item(world, store_ref)
	runner.assert_true(bool(reserved.get("ok", false)), "the reserved source is queryable")
	if bool(reserved.get("ok", false)):
		runner.assert_eq(reserved.quantity, stock, "reservation does not create or move wood")
		runner.assert_eq(reserved.available, stock - 3, "only the reserved three units leave availability")
		runner.assert_eq(reserved.entrusted, 0, "a source reservation is not a carried consignment")
	sim.cancel_action("player")
	world.invalidate_region("home")
	var released: Dictionary = Query.item(world, store_ref)
	runner.assert_true(bool(released.get("ok", false)) and int(released.get("available", -1)) == stock, "cancelling before pickup releases the actual reservation")
	sim.set_actor_cell("player", store_cell)
	world.invalidate_region("home")
	started = sim.submit_action("player", "deliver_wood")
	runner.assert_true(started, "the original body starts a new native haul at the source")
	if not started:
		return
	world.invalidate_region("home")
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 100), "the original pickup runs at common time")
	var carried: Dictionary = Query.item(world, bag_ref)
	var source: Dictionary = Query.item(world, store_ref)
	runner.assert_true(bool(carried.get("ok", false)) and bool(source.get("ok", false)), "both ends of the real transfer remain queryable")
	if not bool(carried.get("ok", false)) or not bool(source.get("ok", false)):
		return
	runner.assert_true(carried.entry_present and int(carried.quantity) == 3 and int(carried.entrusted) == 3 and int(carried.available) == 0, "the single original bag carries exactly the protected three units")
	runner.assert_eq(source.quantity, stock - 3, "the actual source pays exactly once")
	var other_store: Dictionary = Query.item(world, _ref("river", "store", "wood"))
	runner.assert_eq(other_store.get("quantity"), world.regions.river.inventory.quantity("store", "wood"), "same-name remote store is not debited by the local pickup")
	var point: Vector2 = sim.actor_position(sim.actors.player)
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 100), "the carrier advances along the real haul route")
	var moving: Dictionary = Query.item(world, bag_ref)
	runner.assert_true(bool(moving.get("ok", false)), "moving pocket remains queryable")
	if bool(moving.get("ok", false)):
		runner.assert_true(moving.position != point and moving.position != TileGrid.cell_to_world(moving.cell), "pocket follows the continuously moving original body")
		runner.assert_eq(moving.position, sim.actor_position(sim.actors.player), "queried pocket is anchored to that same body")
	var untouched: String = _fixtures._facts(world)
	Query.item(world, bag_ref)
	Query.locate(world, _ref("home", "actor:player"))
	runner.assert_eq(_fixtures._facts(world), untouched, "reading during actual movement cannot settle or duplicate goods")
	runner.assert_true(world.synchronize_region("home"), "cancellation occurs at the committed common time")
	sim.cancel_action("player")
	world.invalidate_region("home")
	var cancelled: Dictionary = Query.item(world, bag_ref)
	runner.assert_true(bool(cancelled.get("ok", false)) and int(cancelled.quantity) == 3 and int(cancelled.entrusted) == 3 and int(cancelled.available) == 0, "cancellation retains the same protected consignment")
	var archive: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))
	var expected: Dictionary = Query.item(world, bag_ref)
	var restored: RegionalSimulation = _fixtures._world(runner)
	if restored == null:
		return
	var loaded: bool = restored.restore(archive)
	runner.assert_true(loaded, "cancelled native custody restores from its actual JSON snapshot")
	if not loaded:
		return
	runner.assert_eq(Query.item(restored, bag_ref), expected, "restored query retains the one bag, source time and custody quantities")
	runner.assert_eq(_fixtures._round_trip(restored.regions.home.inventory.to_dict()), _fixtures._round_trip(sim.inventory.to_dict()), "restoration preserves the original inventory ledger once across the JSON numeric boundary")
	for candidate: RegionalSimulation in [world, restored]:
		var owner: VillageSimulation = candidate.regions.home
		runner.assert_true(owner.submit_action("player", "deliver_wood"), "native delivery resumes its original consignment")
		candidate.invalidate_region("home")
		runner.assert_true(candidate.advance_to_ms(candidate.elapsed_ms + 600000), "resumed delivery reaches its actual future")
		var finish: Dictionary = Query.item(candidate, bag_ref)
		var destination: Dictionary = Query.item(candidate, _ref("home", "kitchen", "wood"))
		runner.assert_true(bool(finish.get("ok", false)) and int(finish.quantity) == 0 and int(finish.entrusted) == 0, "delivery settles the same custody without retaining a second copy")
		runner.assert_true(bool(destination.get("ok", false)) and int(destination.quantity) == 3, "the real destination receives the original three units once")
		runner.assert_eq(owner.inventory.quantity("store", "wood") + owner.inventory.quantity("actor:player", "wood") + owner.inventory.quantity("kitchen", "wood"), stock, "source, bag and destination retain exactly one finite wood total")
	runner.assert_eq(_fixtures._round_trip(world.to_dict()), _fixtures._round_trip(restored.to_dict()), "original and JSON-restored custody continue to the same complete future")


func _stale_and_backlog(runner: Object) -> void:
	var world: RegionalSimulation = _fixtures._world(runner)
	if world == null:
		return
	runner.assert_true(world.set_active_region("home") and world.advance_to_ms(1234), "the original world advances while the distant village batches")
	var remote: VillageSimulation = world.regions.river
	runner.assert_true(remote.elapsed_ms < world.elapsed_ms, "the real remote ledger is older than the committed world")
	if remote.elapsed_ms >= world.elapsed_ms:
		return
	var remote_ref: Dictionary = _ref("river", "actor:river_player", "wood")
	var before: String = _fixtures._facts(world)
	var stale: Dictionary = Query.item(world, remote_ref)
	runner.assert_true(bool(stale.get("ok", false)), "the older remote pocket can still be read")
	if bool(stale.get("ok", false)):
		runner.assert_true(stale.stale and not stale.world_has_backlog, "old owner time is distinct from pending world work")
		runner.assert_eq(stale.owner_time_ms, remote.elapsed_ms, "remote quantity reports its actual ledger time")
		runner.assert_eq(stale.location_time_ms, remote.elapsed_ms, "the carrier position reports the same old village time")
		runner.assert_eq(stale.world_time_ms, world.elapsed_ms, "world time remains the committed timestamp")
	runner.assert_eq(_fixtures._facts(world), before, "a stale query does not synchronize or advance the remote ledger")
	var target: int = world.elapsed_ms + 10000
	runner.assert_true(not world.advance_to_ms(target, 0), "exhausted work budget leaves a real future target")
	before = _fixtures._facts(world)
	var debt: Dictionary = Query.item(world, remote_ref)
	var current: Dictionary = Query.locate(world, _ref("home", "actor:player"))
	runner.assert_true(bool(debt.get("ok", false)) and bool(current.get("ok", false)), "committed storage remains queryable with pending work")
	if bool(debt.get("ok", false)) and bool(current.get("ok", false)):
		runner.assert_true(debt.stale and debt.world_has_backlog and current.world_has_backlog, "remote staleness and shared backlog are independently reported")
		runner.assert_eq(debt.target_time_ms, target, "the unprocessed target is reported without projection")
		runner.assert_eq(debt.world_time_ms, world.elapsed_ms, "lookup reads only the actual committed world")
	runner.assert_eq(_fixtures._facts(world), before, "pending queries consume no budget and change no ownership")
