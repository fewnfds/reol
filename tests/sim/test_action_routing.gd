extends RefCounted
## Common movement contract: native and service work retain their original
## identity/reservations through a detour; combat interrupts that same work.
const Fixture = preload("res://tests/sim/test_settlement_services.gd")
var _fixture: RefCounted = Fixture.new()
var _blocked: Dictionary = {}


func _stand(cell: Vector2i) -> bool:
	return cell.x >= 90 and cell.y >= 90 and cell.x <= 175 and cell.y <= 125 and not _blocked.has(cell)


func _step(from: Vector2i, direction: Vector2i) -> bool:
	return _stand(from + direction) and (direction.x == 0 or direction.y == 0 or _stand(from + Vector2i(direction.x, 0)) or _stand(from + Vector2i(0, direction.y)))


func _path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	return SimGridNavigation.find_path(from, to, _stand, _step, 64, 16384)


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _fixture._make_world(runner)
	if world == null:
		return null
	for region: VillageSimulation in world.regions.values():
		region.set_navigation(_path, _step)
	world.services.set_navigation(_path, _step)
	return world


func run(runner: Object) -> void:
	_native_detour_and_slices(runner)
	_service_detour_and_combat(runner)
	print("SCENARIO action routing: native AStar detours retain original work, canonical invalidation, same sliced/restored future, and hostile interruption retains real stock")


func _native_detour_and_slices(runner: Object) -> void:
	_blocked.clear()
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var sim: VillageSimulation = world.regions.home
	var target: Vector2i = SimRouteTravel.cell(sim.places.store.cell)
	sim.set_actor_cell("player", target + Vector2i(-4, 0))
	runner.assert_true(sim.submit_action("player", "deliver_wood"), "ordinary work accepts the same original actor and native navigation")
	if sim.actors.player.active.is_empty():
		return
	var id: String = str(sim.actors.player.active.id)
	var stock: int = sim.inventory.quantity("store", "wood")
	world.advance_to_ms(50, 4096, 2147483647)
	runner.assert_true(world.synchronize_regions(), "a topology commit first settles the old body intervals")
	var stop: Vector2i = SimRouteTravel.cell(sim.actors.player.active.path[0])
	_blocked[stop] = true
	world.invalidate_region("home")
	runner.assert_eq(sim.next_boundary_ms(), world.elapsed_ms + 1, "a newly obstructed leg wakes on a canonical integer boundary")
	var checkpoint: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))
	var fine: RegionalSimulation = _world(runner)
	runner.assert_true(fine.restore(checkpoint), "the original in-flight body and obstructed remainder can restore before reevaluation")
	var end: int = world.elapsed_ms + 2200
	runner.assert_true(world.advance_to_ms(end, 4096, 2147483647), "coarse advancement repairs a blocked route through the common executor")
	while fine.elapsed_ms < end:
		if not fine.advance_to_ms(mini(end, fine.elapsed_ms + 37), 4096, 2147483647):
			runner.assert_true(false, "sliced reevaluation reaches its next boundary")
			return
	runner.assert_eq(sim.actors.player.active.id, id, "detouring preserves the original action identity")
	runner.assert_eq(sim.inventory.quantity("store", "wood"), stock - (3 if bool(sim.actors.player.active.carrying) else 0), "route repair cannot issue an early or duplicate pickup")
	runner.assert_true(not sim.inventory.reservations.has(id + ":wood") or not bool(sim.actors.player.active.carrying), "the original stock is either reserved or actually carried")
	runner.assert_eq(SnapshotValues.canonical_json(RegionalSimulation._normalized(fine.to_dict())).sha256_text(), SnapshotValues.canonical_json(RegionalSimulation._normalized(world.to_dict())).sha256_text(), "native detours have the same full future across arbitrary host slices and restore")


func _service_detour_and_combat(runner: Object) -> void:
	_blocked.clear()
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var source: Dictionary = {"region": "home", "container": "store"}
	var target: Dictionary = {"region": "river", "container": "store"}
	var reply: Dictionary = world.services.begin_haul("player", source, target, "wood", 2)
	runner.assert_true(reply.ok, "general hauling uses the same original work occupancy")
	if not reply.ok:
		return
	for _index: int in 128:
		var job: Dictionary = world.services.jobs[reply.id]
		if job.stage == "delivery" or job.status != "active":
			break
		world.advance_to_ms(world.services.next_boundary_ms(), 4096, 2147483647)
	var job: Dictionary = world.services.jobs[reply.id]
	runner.assert_true(job.status == "active" and job.carrying, "cargo is physically in the original bag before testing interruption")
	if job.status != "active" or job.path.is_empty():
		return
	_blocked[SimRouteTravel.cell(job.path[0])] = true
	world.advance_to_ms(world.elapsed_ms + 100, 4096, 2147483647)
	runner.assert_eq(job.status, "active", "a service detour does not discard its actual consignment")
	var person: Dictionary = world.regions.home.actors.player
	world.regions.home.set_actor_position("chen_shouzhuo", SimRouteTravel.point(person) + Vector2(80, 0))
	var start: Dictionary = world.conflicts.begin("chen_shouzhuo", "player")
	runner.assert_true(start.ok, "a real nearby hostile intent can interrupt ordinary transport")
	if not start.ok:
		return
	runner.assert_eq(job.status, "cancelled", "the combat handoff ends the original service process")
	runner.assert_eq(world.regions.home.inventory.entrusted("actor:player", "wood"), 2, "combat preserves the public cargo and its original responsibility")
	runner.assert_eq(world.describe_actor_action("player").domain, "conflicts", "the common activity view now projects the actual combat owner")
	world.conflicts.cancel("player")
	runner.assert_true(not world.describe_actor_action("player").ok, "yielding leaves no fabricated work process behind")
