extends RefCounted

const Fixtures = preload("res://tests/sim/test_settlement_services.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_test_cash_goods_and_recognition(runner)
	_test_failed_exchange_is_atomic(runner)
	_test_competing_buyers_and_authority(runner)
	_test_continuation_and_candidates(runner)
	print("SCENARIO local trade: authorized quotes, finite original cash/goods/demand, two-sided atomic settlement, competition and identical continuation")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _fixtures._make_world(runner)
	_fixtures._position(world, "home", "records")
	return world


func _quote(world: RegionalSimulation, offer: String, lots: Variant = 1, actor: String = "player", receiver: String = "chen_shouzhuo") -> Dictionary:
	return SimInteractionRequests.submit(world, {"sender": world.embodiment.subject_for_actor(actor), "receiver": world.embodiment.subject_for_actor(receiver), "verb": "trade", "object": {"kind": "trade_offer", "id": offer}, "medium": "spoken", "conditions": {"lots": lots}})


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(world.to_dict(), "", true, true)


func _test_cash_goods_and_recognition(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	sim.inventory.containers["actor:player"].herb = 1
	var cash: int = _fixtures._total(world, "coin")
	var food: int = sim.inventory.quantity("kitchen", "meal")
	var hunger: float = sim.actors.player.hunger
	var credit: int = sim.institutions.balance(str(sim.config.institution.id), "player")
	var reply: Dictionary = _quote(world, "buy_meal")
	runner.assert_true(reply.ok, "person with public pay authority can quote an actual local purchase")
	runner.assert_eq(sim.inventory.quantity("kitchen", "meal"), food, "agreement never immediately delivers the promised goods")
	runner.assert_eq(sim.inventory.quantity("actor:player", "coin"), 8, "quote does not deduct money before actual handling")
	var early: Dictionary = world.services._trade.settle(world.services.jobs[reply.process.id])
	runner.assert_true(not early.ok and sim.inventory.quantity("actor:player", "coin") == 8 and sim.inventory.quantity("actor:player", "meal") == 0, "a direct early tool call cannot skip the physical route and handling time")
	_fixtures._finish(world, "player", runner)
	runner.assert_eq(sim.inventory.quantity("actor:player", "meal"), 1, "purchased food physically remains in the original bag")
	runner.assert_eq(sim.inventory.quantity("actor:player", "coin"), 6, "buyer pays the agreed finite amount")
	runner.assert_eq(sim.inventory.quantity("records", "coin"), 2, "sale funds the same public cash container used by visitor services")
	runner.assert_true(float(sim.actors.player.hunger) <= hunger, "buying food does not directly heal or feed the actor")
	runner.assert_eq(_fixtures._total(world, "coin"), cash, "purchase transfers existing money instead of minting rewards")
	_fixtures._position(world, "home", "records")
	reply = _quote(world, "sell_herb")
	runner.assert_true(reply.ok, "holder can offer an actual personal herb to local procurement")
	_fixtures._finish(world, "player", runner)
	runner.assert_eq(sim.inventory.quantity("actor:player", "herb"), 0, "sold herb leaves the actual bag")
	runner.assert_eq(sim.inventory.quantity("actor:player", "coin"), 8, "sale is paid from the actual finite public budget")
	runner.assert_eq(sim.inventory.quantity("records", "coin"), 0, "public budget is spent, never re-filled by a shop reset")
	runner.assert_eq(_fixtures._total(world, "coin"), cash, "purchase and procurement conserve the same coins")
	runner.assert_eq(sim.institutions.balance(str(sim.config.institution.id), "player"), credit, "trade is not also counted as unpaid public labor")
	var job: Dictionary = world.services.jobs[reply.process.id]
	var before: String = _canonical(world)
	runner.assert_true(world.services._trade.settle(job).ok, "replaying the identical completed exchange is idempotent")
	runner.assert_eq(_canonical(world), before, "replaying settlement cannot create another payment or item")
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(before)), "completed money and goods have mutually validated ownership receipts")


func _test_failed_exchange_is_atomic(runner: Object) -> void:
	for reason: String in ["cash", "demand", "goods", "minimum_stock", "overflow", "cancel"]:
		var world: RegionalSimulation = _world(runner)
		var sim: VillageSimulation = world.regions.home
		sim.inventory.containers["actor:player"].herb = 1
		var offer: String = "sell_herb"
		match reason:
			"cash": pass # The actual public account starts empty.
			"demand":
				sim.inventory.containers.records.coin = 10
				sim.inventory.containers.garden.herb = 24
			"goods":
				sim.inventory.containers.records.coin = 10
				sim.inventory.containers["actor:player"].herb = 0
			"minimum_stock":
				offer = "buy_meal"
				sim.inventory.containers.kitchen.meal = 2
			"overflow":
				sim.inventory.containers.records.coin = 10
				sim.inventory.containers["actor:player"].coin = SimInventory.MAX_COUNT
			"cancel": pass
		var reply: Dictionary = _quote(world, offer)
		runner.assert_true(reply.ok, "standing quote is not a hidden-stock oracle: " + reason)
		var inventory: String = JSON.stringify(sim.inventory.to_dict(), "", true, true)
		if reason == "cancel":
			runner.assert_true(world.services.cancel("player"), "inflight order can be stopped without buying anything")
		else:
			_fixtures._finish(world, "player", runner)
		runner.assert_eq(world.services.jobs[reply.process.id].status, "cancelled" if reason == "cancel" else "failed", "physical preconditions decide the terminal result: " + reason)
		runner.assert_eq(JSON.stringify(sim.inventory.to_dict(), "", true, true), inventory, "failed/cancelled trade changes neither party's money nor goods: " + reason)
	var world: RegionalSimulation = _world(runner)
	for lots: Variant in [0, -1, 1.5, 6, SimInventory.MAX_COUNT, "2"]:
		runner.assert_eq(_quote(world, "buy_meal", lots).status, "invalid", "malformed or excessive trade lots cannot start an action: " + str(lots))
	world.regions.home.set_actor_cell("a_he", SimRouteTravel.cell(world.regions.home.places.records.cell))
	runner.assert_eq(_quote(world, "buy_meal", 1, "player", "a_he").status, "incapable", "friendliness never supplies a missing public payment mandate")
	var invalid_policy: Dictionary = world.services.definitions.duplicate(true)
	invalid_policy.coin_item = "meal"
	runner.assert_true(not world.services.Schema.valid_definitions(invalid_policy, world), "currency and merchandise cannot alias and invalidate two-sided preflight")


func _test_competing_buyers_and_authority(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	sim.inventory.containers.kitchen.meal = 3
	sim.inventory.containers["actor:a_he"].coin = 8
	sim.set_actor_cell("a_he", SimRouteTravel.cell(sim.places.records.cell))
	var first: Dictionary = _quote(world, "buy_meal")
	var second: Dictionary = _quote(world, "buy_meal", 1, "a_he")
	runner.assert_true(first.ok and second.ok, "two bodies may receive quotes before either has picked up the last saleable meal")
	world.advance_to_ms(300000)
	var completed: int = int(world.services.jobs[first.process.id].status == "completed") + int(world.services.jobs[second.process.id].status == "completed")
	runner.assert_eq(completed, 1, "only one buyer can obtain the single saleable meal")
	runner.assert_eq(sim.inventory.quantity("kitchen", "meal"), 2, "competing buyers cannot spend the protected local reserve")
	runner.assert_eq(sim.inventory.quantity("records", "coin"), 2, "failed competitor is not also charged")
	world = _world(runner)
	sim = world.regions.home
	first = _quote(world, "buy_meal")
	sim.institutions.appoint(str(sim.config.institution.id), "registrar", "a_he")
	var changed: String = _canonical(world)
	var candidate: RegionalSimulation = _world(runner)
	runner.assert_true(candidate.restore(JSON.parse_string(changed)), "a legitimate pending mandate can outlive an office change and then be rejected on execution")
	_fixtures._finish(world, "player", runner)
	runner.assert_eq(world.services.jobs[first.process.id].status, "failed", "the former officer cannot force the changed public account to honor an unfulfilled quote")
	runner.assert_eq(sim.inventory.quantity("actor:player", "coin"), 8, "mandate loss costs neither side goods or payment")


func _test_continuation_and_candidates(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var reply: Dictionary = _quote(world, "buy_meal", 2)
	runner.assert_true(reply.ok, "multi-lot order retains explicit local price and count")
	world.advance_to_ms(1337)
	var saved: Dictionary = JSON.parse_string(_canonical(world))
	var fine: RegionalSimulation = _world(runner)
	runner.assert_true(fine.restore(saved), "inflight price/issuer/route restores without adding cash or completing the order")
	world.set_active_region("river")
	fine.set_active_region("home")
	world.advance_to_ms(210000)
	while fine.elapsed_ms < 210000:
		fine.advance_to_ms(mini(210000, fine.elapsed_ms + 991))
	var left: Dictionary = JSON.parse_string(_canonical(world))
	var right: Dictionary = JSON.parse_string(_canonical(fine))
	left.active_region = ""
	right.active_region = ""
	runner.assert_eq(JSON.stringify(left), JSON.stringify(right), "distant coarse and nearby fine trade produce the same full world")
	var stable: String = _canonical(world)
	for kind: String in ["half", "price", "issuer", "extra_terms", "missing_policy"]:
		var broken: Dictionary = JSON.parse_string(stable)
		var job: Dictionary = broken.services.jobs[reply.process.id]
		match kind:
			"half": broken.services.operations.erase(str(job.id) + ":trade_money")
			"price": broken.services.operations[str(job.id) + ":trade_money"].amount += 1
			"issuer": job.options.issuer = "unknown_person"
			"extra_terms": job.options.free_goods = true
			"missing_policy": broken.services.definitions.erase("trade")
		runner.assert_true(not world.restore(broken), "invalid trade candidate rejected: " + kind)
		runner.assert_eq(_canonical(world), stable, "invalid trade candidate leaves the live world intact: " + kind)
