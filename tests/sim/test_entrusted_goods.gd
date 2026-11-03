extends RefCounted

const Fixtures = preload("res://tests/sim/test_settlement_services.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_test_private_and_public_delivery(runner)
	_test_gathering_and_public_recipe(runner)
	_test_returns_and_candidates(runner)
	_test_cross_region_consignment(runner)
	print("SCENARIO custody: same real bag, private goods preserved, cancelled public goods protected, physical returns and identical continuation")


func _world(runner: Object) -> RegionalSimulation:
	return _fixtures._make_world(runner)


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _pickup(world: RegionalSimulation, action: String, runner: Object) -> String:
	var sim: VillageSimulation = world.regions.home
	var terms: Dictionary = sim.config.actions[action]
	_fixtures._position(world, "home", str(terms.get("source", terms.target)))
	runner.assert_true(sim.submit_action("player", action), "public job accepts the original actor: " + action)
	world.invalidate_region("home")
	world.advance_to_ms(world.elapsed_ms + 100)
	var held: String = SimEntrustedGoods.first_held(sim.inventory, "player")
	runner.assert_true(not held.is_empty(), "actual pickup creates a disposition record: " + action)
	return held


func _test_private_and_public_delivery(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	var bag: String = "actor:player"
	sim.inventory.containers[bag].wood = 3
	sim.inventory.containers.store.wood = 20 # Real procurement demand, so custody is the reason for refusal.
	var stock: int = sim.inventory.quantity("store", "wood")
	var id: String = _pickup(world, "deliver_wood", runner)
	runner.assert_eq(sim.inventory.quantity(bag, "wood"), 6, "public hauling really picks up another batch rather than appropriating personal wood")
	runner.assert_eq(sim.inventory.quantity("store", "wood"), stock - 3, "source pays for the consignment once")
	runner.assert_eq(sim.inventory.available(bag, "wood"), 3, "only private wood is freely disposable")
	runner.assert_true(world.synchronize_region("home"), "cancellation uses the original body's current common time")
	sim.cancel_action("player")
	world.invalidate_region("home")
	runner.assert_eq(sim.inventory.entrusted(bag, "wood"), 3, "cancellation leaves the public consignment and responsibility intact")
	runner.assert_true(sim.inventory.consume("action:1:fixture_use", bag, "wood", 3), "same-type private wood can still be used")
	runner.assert_true(not sim.inventory.consume("action:1:fixture_steal", bag, "wood", 1), "ordinary consumption cannot silently take entrusted stock")
	runner.assert_true(not sim.inventory.reserve("private_sale", bag, "wood", 1, "player"), "ordinary reservation cannot sell or repurpose public stock")
	_fixtures._position(world, "home", "records")
	sim.inventory.containers.records.coin = 10
	var quote: Dictionary = world.services._trade.authorize("player", "home", "chen_shouzhuo", "sell_wood", 1)
	runner.assert_true(quote.ok, "public quote still reveals no private stock quantities")
	_fixtures._finish(world, "player", runner)
	runner.assert_eq(sim.inventory.quantity(bag, "coin"), 8, "protected wood cannot receive public procurement money")
	runner.assert_true(world.synchronize_region("home"), "resuming an external native command first synchronizes a quiet far body")
	runner.assert_true(sim.submit_action("player", "deliver_wood"), "the same public duty can resume its actual consignment")
	world.invalidate_region("home")
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 600000), "the consignment completes without rolling the common clock backward")
	runner.assert_eq(sim.inventory.quantity(bag, "wood"), 0, "delivery consumes just the actual consignment")
	runner.assert_eq(sim.inventory.quantity("store", "wood"), stock - 3, "resuming never picks up a second public batch")
	runner.assert_eq(sim.inventory.custody[id].settled_by.domain, "inventory", "successful native delivery closes the original responsibility")
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "native pickup/cancellation/resume history cross-validates")


func _test_gathering_and_public_recipe(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	var bag: String = "actor:player"
	sim.inventory.containers[bag].herb = 2
	_fixtures._position(world, "home", "garden")
	runner.assert_true(sim.submit_action("player", "gather_herb"), "public gather starts even when matching personal material exists")
	world.invalidate_region("home")
	world.advance_to_ms(100)
	runner.assert_true(not sim.actors.player.active.is_empty() and not sim.actors.player.active.carrying, "private herbs do not skip public gathering labor")
	world.advance_to_ms(1500001)
	runner.assert_eq(sim.inventory.quantity(bag, "herb"), 4, "public source harvest coexists with two private herbs")
	runner.assert_true(world.synchronize_region("home"), "stopping actual harvest first settles its body's elapsed interval")
	sim.cancel_action("player")
	world.invalidate_region("home")
	runner.assert_eq(sim.inventory.available(bag, "herb"), 2, "only actual public harvest is protected")
	# A completely separate personal gather remains available, but cannot erase custody.
	runner.assert_true(sim.submit_action("player", "keep_herb"), "individual work remains possible while responsibly holding another batch")
	world.invalidate_region("home")
	world.advance_to_ms(world.elapsed_ms + 1800000)
	runner.assert_eq(sim.inventory.available(bag, "herb"), 4, "new private harvest is independently disposable")
	runner.assert_eq(sim.inventory.entrusted(bag, "herb"), 2, "new private work does not wash away the previous public consignment")
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "cancelled gather plus private harvest has one consistent source ledger")
	world = _world(runner)
	sim = world.regions.home
	sim.inventory.containers.kitchen.wood = 5
	sim.inventory.containers[bag] = {"wood": 1, "grain": 2, "water": 1, "coin": 8}
	var held: String = _pickup(world, "cook", runner)
	runner.assert_eq(sim.inventory.available(bag, "grain"), 2, "cooking does not appropriate the actor's private ingredients")
	runner.assert_eq(sim.inventory.entrusted(bag, "grain"), 2, "cooking's own actual public inputs are protected")
	runner.assert_true(world.synchronize_region("home"), "recipe cancellation is issued at the common current time")
	sim.cancel_action("player")
	world.invalidate_region("home")
	var kitchen_grain: int = sim.inventory.quantity("kitchen", "grain")
	runner.assert_true(sim.submit_action("player", "cook"), "cancelled cooking can resume the actual entrusted input batches")
	world.invalidate_region("home")
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 1500000), "resumed cooking reaches its real future without a stale-body command")
	runner.assert_eq(sim.inventory.quantity(bag, "grain"), 2, "finished public meal leaves all private grain in the bag")
	runner.assert_eq(sim.inventory.quantity("kitchen", "grain"), kitchen_grain, "resumed recipe does not take the same public inputs twice")
	runner.assert_true(not sim.inventory.custody[held].settled_by.is_empty(), "actual recipe consumption closes its original custody")
	copy = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "recipe ingredients and completed uses restore consistently")


func _test_returns_and_candidates(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	sim.inventory.containers["actor:player"].wood = 3
	var id: String = _pickup(world, "deliver_wood", runner)
	runner.assert_true(world.synchronize_region("home"), "return scenario stops the consignment at the actual current time")
	sim.cancel_action("player")
	world.invalidate_region("home")
	var baseline: Dictionary = JSON.parse_string(_canonical(world))
	for fault: String in ["erase", "missing", "amount", "purpose", "source", "settlement", "overdraw"]:
		var bad: Dictionary = baseline.duplicate(true)
		var inv: Dictionary = bad.regions.home.inventory
		match fault:
			"erase": inv.custody.erase(id)
			"missing": inv.erase("custody")
			"amount": inv.custody[id].amount = 4
			"purpose": inv.custody[id].basis.purpose = "keep_wood"
			"source": inv.custody[id].basis.return_place = "dorm"
			"settlement": inv.custody[id].settled_by = {"domain": "inventory", "operation": id}
			"overdraw": inv.containers["actor:player"].wood = 2
		var before: String = _canonical(world)
		runner.assert_true(not world.restore(bad), "candidate rejects inconsistent custody: " + fault)
		runner.assert_eq(_canonical(world), before, "bad custody leaves the complete live world unchanged: " + fault)
	var reply: Dictionary = world.services.begin("player", "home", "return_goods")
	runner.assert_true(reply.ok, "holding public goods provides a normal physical return path")
	var job: Dictionary = world.services.jobs[reply.id]
	var before: String = _canonical(world)
	world.services._jobs._finish_work(job)
	runner.assert_eq(_canonical(world), before, "direct early finish cannot bypass route or count time")
	world.advance_to_ms(world.elapsed_ms + 500)
	var saved: String = _canonical(world)
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(saved)), "return route/handling and encumbrance restore jointly")
	_fixtures._finish(world, "player", runner)
	_fixtures._finish(copy, "player", runner)
	runner.assert_true(_canonical(copy) == _canonical(world), "return and all distant world state continue identically")
	runner.assert_eq(sim.inventory.quantity("actor:player", "wood"), 3, "return preserves the carrier's same-type private goods")
	runner.assert_eq(sim.inventory.quantity("store", "wood"), 80, "return puts the actual batch back in its source store")
	runner.assert_true(sim.actors.player.receipts.is_empty(), "return never creates a public work credit")
	before = _canonical(world)
	runner.assert_true(not world.services.begin("player", "home", "return_goods", {"custody": id}).ok, "already settled goods cannot be returned twice")
	runner.assert_eq(_canonical(world), before, "repeated return cannot move goods or generate another job")
	# A full receiving store fails without clearing responsibility or losing goods.
	world = _world(runner)
	sim = world.regions.home
	id = _pickup(world, "deliver_wood", runner)
	sim.cancel_action("player")
	sim.inventory.containers.store.wood = SimInventory.MAX_COUNT
	world.invalidate_region("home")
	reply = world.services.begin("player", "home", "return_goods")
	runner.assert_true(reply.ok, "return is an intention, not a hidden capacity oracle")
	_fixtures._finish(world, "player", runner)
	runner.assert_eq(sim.inventory.entrusted("actor:player", "wood"), 3, "full destination retains actual goods and responsibility")
	runner.assert_eq(sim.inventory.quantity("store", "wood"), SimInventory.MAX_COUNT, "full receiving store cannot overflow")


func _test_cross_region_consignment(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	sim.inventory.containers["actor:player"].grain = 6
	_fixtures._position(world, "river", "store")
	var reply: Dictionary = world.services.begin("player", "river", "haul_grain")
	runner.assert_true(reply.ok, "cross-region public grain has its original timed pickup")
	world.advance_to_ms(1000)
	runner.assert_eq(sim.inventory.quantity("actor:player", "grain"), 12, "visitor pickup cannot silently use the carrier's private grain")
	runner.assert_eq(sim.inventory.available("actor:player", "grain"), 6, "cross-region custody also leaves personal grain available")
	world.services.cancel("player")
	var id: String = SimEntrustedGoods.first_held(sim.inventory, "player")
	runner.assert_true(not id.is_empty(), "cancelled cross-region job leaves explicit original responsibility")
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "cancelled cross-region consignment remains a valid saved state")
	reply = world.services.begin("player", "home", "haul_grain")
	runner.assert_true(reply.ok, "cross-region duty resumes the already carried consignment")
	_fixtures._finish(world, "player", runner)
	runner.assert_eq(sim.inventory.quantity("actor:player", "grain"), 6, "cross-region delivery preserves private grain exactly")
	runner.assert_true(not sim.inventory.custody[id].settled_by.is_empty(), "cross-region completion closes the original pickup responsibility")
	runner.assert_eq(world.services.receipts.size(), 1, "only actual cross-region delivery issues one evidence receipt")
	copy = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "resumed original and completed replacement job mutually validate")
	# Returning another real cross-region consignment goes to its original supplier.
	world = _world(runner)
	sim = world.regions.home
	sim.inventory.containers["actor:player"].grain = 6
	var supplier_stock: int = world.regions.river.inventory.quantity("store", "grain")
	_fixtures._position(world, "river", "store")
	reply = world.services.begin("player", "river", "haul_grain")
	world.advance_to_ms(1000)
	world.services.cancel("player")
	id = SimEntrustedGoods.first_held(sim.inventory, "player")
	reply = world.services.begin("player", "home", "return_goods", {"custody": id})
	runner.assert_true(reply.ok, "cross-region cancellation also supports a physical supplier return")
	_fixtures._finish(world, "player", runner)
	runner.assert_eq(world.regions.river.inventory.quantity("store", "grain"), supplier_stock, "cross-region return restores exactly the supplier's real grain")
	runner.assert_eq(sim.inventory.quantity("actor:player", "grain"), 6, "cross-region supplier return preserves the carrier's private grain")
	runner.assert_true(world.services.receipts.is_empty(), "return is not a credited delivery to the other village")
	copy = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "cross-region return and source provenance restore consistently")
