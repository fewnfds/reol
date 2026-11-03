extends RefCounted

const Fixtures = preload("res://tests/sim/test_local_trade.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_test_personal_output_and_existing_goods(runner)
	_test_public_delivery_remains_public(runner)
	_test_boundaries_and_continuation(runner)
	print("SCENARIO personal foraging: one finite shared source, original full labor/reservations, kept original bag output, no public credit and unchanged public work")


func _world(runner: Object) -> RegionalSimulation:
	return _fixtures._world(runner)


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(world.to_dict(), "", true, true)


func _test_personal_output_and_existing_goods(runner: Object) -> void:
	for id: String in ["keep_wood", "keep_grain", "keep_water", "keep_herb"]:
		var world: RegionalSimulation = _world(runner)
		var sim: VillageSimulation = world.regions.home
		var terms: Dictionary = sim.config.actions[id]
		# An existing identical batch must not turn fresh foraging into delivery.
		sim.inventory.containers["actor:player"][terms.item] = int(terms.amount)
		var source: int = int(sim.land_resources.sources[terms.resource].extracted)
		var public_stock: int = sim.inventory.quantity(str(terms.source), str(terms.item))
		var receipts: int = sim.actors.player.receipts.size()
		runner.assert_true(sim.submit_action("player", id), "personal work can start despite owning the same item already: " + id)
		world.invalidate_region("home")
		world.advance_to_ms(1000)
		runner.assert_eq(sim.inventory.quantity("actor:player", str(terms.item)), int(terms.amount), "neither the route nor arrival grants an unearned batch: " + id)
		runner.assert_true(not sim.actors.player.active.is_empty() and not sim.actors.player.active.carrying, "existing goods never skip fresh source labor: " + id)
		world.advance_to_ms(1800000)
		runner.assert_true(sim.actors.player.active.is_empty(), "personal forager naturally stops after the real harvest: " + id)
		runner.assert_eq(sim.inventory.quantity("actor:player", str(terms.item)), int(terms.amount) * 2, "harvest adds one real batch to the original bag: " + id)
		runner.assert_eq(sim.inventory.quantity(str(terms.source), str(terms.item)), public_stock, "personal labor does not also deliver the product to public stock: " + id)
		runner.assert_eq(int(sim.land_resources.sources[terms.resource].extracted), source + int(terms.amount), "the exact same finite natural source pays for the output: " + id)
		runner.assert_eq(sim.actors.player.receipts.size(), receipts, "personal labor creates no public delivery receipt: " + id)
		var copy: RegionalSimulation = _world(runner)
		runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "retained harvest still has valid original source accounting: " + id)


func _test_public_delivery_remains_public(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	sim.inventory.containers.store.wood = 0
	runner.assert_true(sim.submit_action("player", "gather_wood"), "original public gathering is still available")
	world.invalidate_region("home")
	world.advance_to_ms(1800000)
	runner.assert_eq(sim.inventory.quantity("store", "wood"), 3, "original public assignment physically delivers to its original store")
	runner.assert_eq(sim.inventory.quantity("actor:player", "wood"), 0, "public delivery is not silently converted into personal output")
	runner.assert_true(not sim.actors.player.receipts.is_empty(), "still-needed public delivery retains its original work evidence")


func _test_boundaries_and_continuation(runner: Object) -> void:
	for boundary: String in ["cancel", "full", "competition"]:
		var world: RegionalSimulation = _world(runner)
		var sim: VillageSimulation = world.regions.home
		if boundary == "full":
			sim.inventory.containers["actor:player"].wood = SimInventory.MAX_COUNT
		if boundary == "competition":
			runner.assert_true(sim.inventory.reserve("test_source", "resource:woodlot", "wood", 12, "a_he"), "another real reservation occupies the shared source")
		var begun: bool = sim.submit_action("player", "keep_wood")
		world.invalidate_region("home")
		if boundary == "competition":
			runner.assert_true(not begun, "personal gathering does not bypass someone else's source reservation")
			sim.inventory.release("test_source")
			continue
		runner.assert_true(begun, "finite work is scheduled before the boundary is checked: " + boundary)
		if boundary == "cancel":
			world.advance_to_ms(1000)
			sim.cancel_action("player", "manual_stop")
			world.invalidate_region("home")
		world.advance_to_ms(1800000)
		runner.assert_eq(sim.land_resources.sources.woodlot.extracted, 0, "failed or unfinished personal work never removes the source: " + boundary)
		runner.assert_eq(sim.inventory.quantity("actor:player", "wood"), SimInventory.MAX_COUNT if boundary == "full" else 0, "failed or cancelled work grants no output: " + boundary)
		runner.assert_true(sim.inventory.reservations.is_empty(), "boundary cleanup releases the actual source reservation: " + boundary)
	var world: RegionalSimulation = _world(runner)
	runner.assert_true(world.regions.home.submit_action("player", "keep_herb"), "inflight personal harvest begins")
	world.invalidate_region("home")
	world.advance_to_ms(12345)
	var saved: Dictionary = JSON.parse_string(_canonical(world))
	var fine: RegionalSimulation = _world(runner)
	runner.assert_true(fine.restore(saved), "inflight personal work restores its same original reserved source and labor")
	world.set_active_region("river")
	fine.set_active_region("home")
	world.advance_to_ms(1600000)
	while fine.elapsed_ms < 1600000:
		fine.advance_to_ms(mini(1600000, fine.elapsed_ms + 997))
	var left: Dictionary = JSON.parse_string(_canonical(world))
	var right: Dictionary = JSON.parse_string(_canonical(fine))
	left.active_region = ""
	right.active_region = ""
	runner.assert_eq(JSON.stringify(left), JSON.stringify(right), "coarse absent and nearby fine personal work yield an identical full world")
	var stable: String = _canonical(world)
	for kind: String in ["credit", "target", "amount"]:
		var wrong: Dictionary = JSON.parse_string(stable)
		match kind:
			"credit": wrong.regions.home.config.actions.keep_herb.contribution = 1
			"target": wrong.regions.home.config.actions.keep_herb.target = "garden"
			"amount": wrong.regions.home.config.actions.keep_herb.amount += 1
		runner.assert_true(not world.restore(wrong), "invalid retained-work definition is rejected: " + kind)
		runner.assert_eq(_canonical(world), stable, "bad retained-work candidate leaves the active world intact: " + kind)
