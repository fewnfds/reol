extends RefCounted

const Fixtures = preload("res://tests/sim/test_settlement_services.gd")
var fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_funding_and_delivery(runner)
	_pause_expire_and_custody(runner)
	_knowledge_and_commitments(runner)
	_payment_and_candidates(runner)
	_deadlines_and_granularity(runner)
	print("SCENARIO funded labor: finite institutional cash, original native delivery/custody, separate wage entitlement, present mandate, no double credit and whole-world continuation")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = fixtures._make_world(runner)
	var sim: VillageSimulation = world.regions.home
	fixtures._position(world, "home", "records")
	sim.inventory.containers.records["coin"] = 4
	sim.inventory.containers.kitchen.wood = 0
	sim.inventory.containers.kitchen.water = 0
	sim.actors.chen_shouzhuo.stock_memory["kitchen"] = {"items": {"wood": 0, "water": 0}, "tick": sim.tick_index}
	return world


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _finish_native(world: RegionalSimulation, actor: String, runner: Object, pickup_only: bool = false) -> void:
	var sim: VillageSimulation = world.regions.home
	var steps: int = 0
	while not sim.actors[actor].active.is_empty() and steps < 2048:
		if pickup_only and bool(sim.actors[actor].active.carrying):
			break
		runner.assert_true(world.advance_to_ms(sim._executor.next_boundary_ms(sim.actors[actor])), "funded worker advances original body action")
		steps += 1
	runner.assert_true(steps < 2048, "original labor reaches pickup or delivery within bounded steps")


func _accept(world: RegionalSimulation, runner: Object, actor: String = "player", offer: String = "deliver_wood") -> String:
	var result: Dictionary = world.budgeted_labor.accept(actor, "home", "chen_shouzhuo", offer)
	runner.assert_true(result.ok, "worker can personally accept a funded needed labor offer: " + str(result.line))
	return str(result.id)


func _funding_and_delivery(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	sim.inventory.containers.records.coin = 0
	var before: String = _canonical(world)
	runner.assert_true(not world.budgeted_labor.accept("player", "home", "chen_shouzhuo", "deliver_wood").ok, "empty public cash cannot promise an unfunded wage")
	runner.assert_eq(_canonical(world), before, "unfunded refusal leaves every ledger and counter unchanged")
	sim.inventory.containers.records.coin = 4
	runner.assert_true(not world.budgeted_labor.accept("player", "home", "a_he", "deliver_wood").ok, "friendship or kitchen role does not grant public payment authority")
	var money: int = fixtures._total(world, "coin")
	var inventory: SimInventory = sim.inventory
	var id: String = _accept(world, runner)
	if id.is_empty():
		return
	runner.assert_true(sim.inventory == inventory, "funding retains the original inventory instance")
	runner.assert_eq(sim.inventory.quantity("records", "coin"), 2, "actual public cash is set aside once")
	runner.assert_eq(sim.inventory.quantity(id, "coin"), 2, "reserved wage remains a real local fund")
	runner.assert_eq(sim.inventory.quantity("actor:player", "coin"), 8, "acceptance is not a remote payday")
	before = _canonical(world)
	runner.assert_eq(world.budgeted_labor.accept("player", "home", "chen_shouzhuo", "deliver_wood").id, id, "repeat request returns original contract")
	runner.assert_eq(_canonical(world), before, "repeated acceptance changes no money, clock or work")
	runner.assert_true(not world.budgeted_labor.request_claim("player", id, "chen_shouzhuo").ok, "agreement alone cannot be claimed as finished work")
	world.advance_to_ms(1234)
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "funded native travel restores without a second executor")
	_finish_native(world, "player", runner)
	copy.active_region = "river"
	copy.advance_to_ms(world.elapsed_ms)
	copy.active_region = world.active_region
	runner.assert_eq(_canonical(copy), _canonical(world), "offscreen native wage delivery has identical whole-world future")
	runner.assert_eq(world.budgeted_labor.contracts[id].status, "payable", "actual material delivery earns a pending wage")
	runner.assert_eq(sim.inventory.quantity("kitchen", "wood"), 3, "original entrusted wood actually reaches kitchen")
	runner.assert_true(sim.actors.player.receipts.is_empty(), "paid native action issues no public contribution receipt")
	sim.report_work("player")
	runner.assert_eq(sim.institutions.balance("sect", "player"), 0, "same paid delivery cannot also report public contribution")
	fixtures._position(world, "home", "records")
	runner.assert_true(world.budgeted_labor.request_claim("player", id, "chen_shouzhuo").ok, "current officer can start timed acceptance of actual delivery")
	fixtures._finish(world, "player", runner)
	runner.assert_eq(world.budgeted_labor.contracts[id].status, "paid", "physical acceptance pays the wage")
	runner.assert_eq(sim.inventory.quantity("actor:player", "coin"), 10, "two actual coins reach the one bag")
	runner.assert_eq(fixtures._total(world, "coin"), money, "wages conserve every existing coin")
	before = _canonical(world)
	runner.assert_true(not world.budgeted_labor.request_claim("player", id, "chen_shouzhuo").ok, "same completed job cannot be claimed twice")
	runner.assert_eq(_canonical(world), before, "duplicate claim creates no empty service job")
	copy = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "paid labor, original delivery and timed claim jointly validate")


func _pause_expire_and_custody(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	var id: String = _accept(world, runner)
	if id.is_empty():
		return
	_finish_native(world, "player", runner, true)
	var source: int = sim.inventory.quantity("store", "wood")
	sim.cancel_action("player")
	world.invalidate_region("home")
	runner.assert_eq(world.budgeted_labor.contracts[id].status, "paused", "stopping the body pauses the existing promise")
	runner.assert_eq(sim.inventory.entrusted("actor:player", "wood"), 3, "stopped wage material remains public custody")
	runner.assert_eq(sim.inventory.available("actor:player", "wood"), 0, "wage pickup cannot become private sale material")
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "paused original consignment and dedicated budget restore")
	runner.assert_true(sim.submit_action("player", "deliver_wood"), "ordinary labor entry can resume the same paid task")
	world.invalidate_region("home")
	_finish_native(world, "player", runner)
	runner.assert_eq(sim.inventory.quantity("store", "wood"), source, "resumed paid action never picks up another consignment")
	runner.assert_eq(world.budgeted_labor.contracts[id].status, "payable", "ordinary restart retains cash rather than duplicating public credit")
	world.advance_to_ms(int(world.budgeted_labor.contracts[id].until_ms) + 1234)
	runner.assert_eq(world.budgeted_labor.contracts[id].status, "payable", "earned unpaid wages survive the original delivery deadline")
	world = _world(runner)
	sim = world.regions.home
	id = _accept(world, runner)
	_finish_native(world, "player", runner, true)
	world.budgeted_labor.abandon("player", id)
	runner.assert_eq(sim.inventory.quantity("records", "coin"), 4, "abandoning unearned work returns only its reserved money")
	runner.assert_eq(sim.inventory.entrusted("actor:player", "wood"), 3, "abandoning the promise does not forgive carried public property")
	runner.assert_true(world.services.begin("player", "home", "return_goods").ok, "original return service accepts abandoned labor material")
	fixtures._finish(world, "player", runner)
	copy = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "refund and actual goods return jointly validate")
	world = _world(runner)
	sim = world.regions.home
	id = _accept(world, runner)
	sim.cancel_action("player")
	world.invalidate_region("home")
	world.advance_to_ms(int(world.budgeted_labor.contracts[id].until_ms))
	runner.assert_eq(world.budgeted_labor.contracts[id].status, "expired", "shared deadline releases an abandoned unfinished promise")
	runner.assert_eq(sim.inventory.quantity("records", "coin"), 4, "expiry returns finite money rather than granting free wages")
	copy = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "deadline and cancelled native attempt survive JSON")


func _knowledge_and_commitments(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	sim.actors.chen_shouzhuo.stock_memory.clear()
	var before: String = _canonical(world)
	runner.assert_true(not world.budgeted_labor.accept("player", "home", "chen_shouzhuo", "deliver_wood").ok, "officer cannot read hidden warehouse truth to invent a job")
	runner.assert_eq(_canonical(world), before, "unknown demand gives no new memory or mandate")
	sim.actors.chen_shouzhuo.stock_memory["kitchen"] = {"items": {"wood": 3}, "tick": sim.tick_index}
	sim.set_actor_cell("shi_tou", SimRouteTravel.cell(sim.actors.player.cell))
	var id: String = _accept(world, runner)
	runner.assert_true(not world.budgeted_labor.accept("shi_tou", "home", "chen_shouzhuo", "deliver_wood").ok, "existing funded delivery fills the remembered deficit before another NPC can claim it")
	_finish_native(world, "player", runner)
	runner.assert_true(not world.budgeted_labor.accept("shi_tou", "home", "chen_shouzhuo", "deliver_wood").ok, "stale remembered deficit cannot reissue after its promised delivery")
	runner.assert_eq(world.budgeted_labor.contracts[id].status, "payable", "binding funded work remains payable even if objective stock was already enough")
	world = _world(runner)
	sim = world.regions.home
	sim.set_actor_cell("shi_tou", SimRouteTravel.cell(sim.actors.player.cell))
	id = _accept(world, runner, "shi_tou", "deliver_water")
	_finish_native(world, "shi_tou", runner)
	runner.assert_eq(world.budgeted_labor.contracts[id].status, "payable", "NPC body uses the same personal cash contract and delivery")
	runner.assert_true(sim.actors.shi_tou.receipts.is_empty(), "NPC wage worker also gets no duplicate contribution")


func _payment_and_candidates(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	var id: String = _accept(world, runner)
	_finish_native(world, "player", runner)
	fixtures._position(world, "home", "records")
	runner.assert_true(world.budgeted_labor.request_claim("player", id, "chen_shouzhuo").ok, "officer signs a pending acceptance visit")
	world.advance_to_ms(world.elapsed_ms + 1)
	var before: String = _canonical(world)
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(before)), "claim-in-progress and unpaid contract restore together")
	for fault: String in ["owner", "fund", "cash", "paid", "delivery", "credit", "attempt", "deadline", "orphan", "extra"]:
		var bad: Dictionary = JSON.parse_string(before)
		var note: Dictionary = bad.budgeted_labor.contracts[id]
		match fault:
			"owner": note.actor = "a_he"
			"fund": bad.regions.home.inventory.operations.erase(id + ":fund")
			"cash": bad.regions.home.inventory.containers[id].coin = 1
			"paid": note.status = "paid"
			"delivery": bad.regions.home.inventory.operations.erase(str(note.attempts.back().action) + ":delivery")
			"credit":
				for event: Dictionary in bad.regions.home.social.events:
					if event.id == note.attempts.back().event:
						event.details.public.work_credit = 2
			"attempt": note.attempts.back().action = "action:999999"
			"deadline": note.until_ms += 1
			"orphan": bad.regions.home.inventory.containers["labor:99999"] = {"coin": 2}
			"extra": note.wallet = {"coin": 100}
		runner.assert_true(not world.restore(bad), "independent wage candidate rejects " + fault)
		runner.assert_eq(_canonical(world), before, "rejected " + fault + " preserves every live object and receipt")
	sim.institutions.appoint("sect", "registrar", "a_he")
	fixtures._finish(world, "player", runner)
	runner.assert_eq(world.budgeted_labor.contracts[id].status, "payable", "lost signing mandate leaves earned wage held rather than erasing it")
	runner.assert_eq(sim.inventory.quantity(id, "coin"), 2, "failed acceptance spends none of the dedicated fund")
	sim.set_actor_cell("a_he", SimRouteTravel.cell(sim.actors.player.cell))
	runner.assert_true(world.budgeted_labor.request_claim("player", id, "a_he").ok, "new incumbent can personally accept the same institutional delivery")
	sim.inventory.containers["actor:player"].coin = SimInventory.MAX_COUNT
	fixtures._finish(world, "player", runner)
	runner.assert_eq(world.budgeted_labor.contracts[id].status, "payable", "full bag preserves whole payable wage")
	sim.inventory.containers["actor:player"].coin = 8
	runner.assert_true(world.budgeted_labor.request_claim("player", id, "a_he").ok, "same earned wage may be retried with usable bag")
	fixtures._finish(world, "player", runner)
	runner.assert_eq(sim.inventory.quantity("actor:player", "coin"), 10, "new current officer pays the same two original coins")
	copy = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "changed incumbent, failed claims and final single payment validate")


func _deadlines_and_granularity(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var id: String = _accept(world, runner)
	world.advance_to_ms(1234)
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "fractional original body and dedicated fund restore")
	var end: int = world.elapsed_ms + 400000
	while world.elapsed_ms < end:
		world.advance_to_ms(mini(end, world.elapsed_ms + 113))
	copy.advance_to_ms(end)
	runner.assert_eq(_canonical(world), _canonical(copy), "113 ms and sparse labor agree including original need remainders")
	# Keep original movement blocked rather than inventing a second job timer.
	world = _world(runner)
	id = _accept(world, runner)
	var sim: VillageSimulation = world.regions.home
	sim.cancel_action("player")
	world.invalidate_region("home")
	sim.inventory.containers.records.coin = SimInventory.MAX_COUNT
	var until: int = int(world.budgeted_labor.contracts[id].until_ms)
	world.advance_to_ms(until)
	runner.assert_eq(world.budgeted_labor.contracts[id].status, "expired", "unfinished contract expires even when public container cannot accept refund")
	runner.assert_eq(sim.inventory.quantity(id, "coin"), 2, "capacity-blocked refund preserves the entire actual dedicated fund")
	copy = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "pending physical refund is a valid saved state")
	sim.inventory.containers.records.coin = 0
	world.advance_to_ms(until + 1)
	runner.assert_eq(sim.inventory.quantity("records", "coin"), 2, "later capacity releases original retained money without printing any")
	runner.assert_eq(sim.inventory.quantity(id, "coin"), 0, "actual refund empties its dedicated source exactly once")
	world.budgeted_labor.settle_at_ms(world.elapsed_ms)
	runner.assert_eq(sim.inventory.quantity("records", "coin"), 2, "repeated refund processing cannot duplicate money")
