extends RefCounted

const Fixtures = preload("res://tests/sim/test_settlement_services.gd")
var fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_food_and_resumption(runner)
	_custody_and_atomicity(runner)
	_remote_trade_and_continuation(runner)
	_candidates(runner)
	print("SCENARIO personal production: original private materials/labor, staged batches, interrupted ignition, physical collection, finite sale and candidate continuity")


func _world(runner: Object) -> RegionalSimulation:
	return fixtures._make_world(runner)


func _stock(world: RegionalSimulation) -> void:
	world.regions.home.inventory.containers["actor:player"].merge({"wood": 2, "grain": 2, "water": 1, "herb": 2}, true)


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _to_work(world: RegionalSimulation, runner: Object) -> void:
	var steps: int = 0
	while world.personal_production.owns_actor("player") and world.personal_production.active.player.phase == "travel" and steps < 1024:
		runner.assert_true(world.advance_to_ms(world.personal_production.next_boundary_ms()), "original body traverses the route to its batch")
		steps += 1
	runner.assert_true(world.personal_production.owns_actor("player") and world.personal_production.active.player.phase == "work", "body actually arrives before processing")


func _finish(world: RegionalSimulation, runner: Object) -> void:
	_to_work(world, runner)
	if world.personal_production.owns_actor("player"):
		runner.assert_true(world.advance_to_ms(int(world.personal_production.active.player.due_ms)), "original shared time finishes actual labor")
	runner.assert_true(not world.personal_production.owns_actor("player"), "batch work releases the unique body")


func _food_and_resumption(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var domain: SimPersonalProduction = world.personal_production
	var sim: VillageSimulation = world.regions.home
	var bag: String = "actor:player"
	var before: String = _canonical(world)
	runner.assert_true(not domain.create("player", "home", "cook_rations").ok, "missing private ingredients cannot start a batch")
	runner.assert_eq(_canonical(world), before, "failed preparation leaks neither a reservation nor an empty batch")
	_stock(world)
	fixtures._position(world, "home", "records")
	var id: String = str(domain.create("player", "home", "cook_rations").batch)
	runner.assert_true(not id.is_empty(), "actual bag can reserve its own ingredients")
	runner.assert_eq(sim.inventory.quantity(bag, "grain"), 2, "preparation reserves rather than remotely taking materials")
	runner.assert_eq(sim.inventory.quantity(id, "grain"), 0, "worksite remains empty before arrival")
	runner.assert_eq(sim.inventory.available(bag, "grain"), 0, "reserved private grain cannot fund another job")
	runner.assert_true(not world.services.begin("player", "home", "rest").ok and not sim.submit_action("player", "rest"), "one body cannot also perform service or native work")
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "inflight reservations and route restore independently")
	_to_work(world, runner)
	runner.assert_eq(sim.inventory.quantity(bag, "wood"), 1, "ignition consumes exactly one actual private fuel")
	runner.assert_eq(sim.inventory.quantity(id, "grain"), 2, "grain is now physically at the worksite batch")
	var at_ms: int = world.elapsed_ms
	var energy: float = float(sim.actors.player.energy)
	world.advance_to_ms(at_ms + 12345)
	runner.assert_true(float(sim.actors.player.energy) < energy, "processing pays the original needs and labor cost")
	runner.assert_true(domain.cancel("player"), "player can interrupt personal work")
	runner.assert_eq(domain.batches[id].work_ms, 12345, "fractional labor remains with the batch")
	runner.assert_eq(sim.inventory.quantity(bag, "wood"), 1, "stopping never refunds burned fuel")
	copy = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "stopped in-process materials restore without another bag")
	runner.assert_true(domain.begin("player", id, "make").ok, "unfinished batch can resume without another set of materials")
	_to_work(world, runner)
	runner.assert_eq(int(domain.active.player.due_ms) - world.elapsed_ms, int(domain.definitions.recipes.cook_rations.work_ms) - 12345, "resumption owes exactly the remaining labor")
	_finish(world, runner)
	runner.assert_eq(domain.batches[id].state, "ready", "recipe completion changes in-process material to finished goods")
	runner.assert_eq(sim.inventory.quantity(id, "meal"), 6, "six meals remain in the actual worksite container")
	runner.assert_eq(sim.inventory.quantity(bag, "meal"), 0, "finishing does not teleport goods into the bag")
	runner.assert_true(sim.actors.player.receipts.is_empty(), "private production grants no public work credit")
	before = _canonical(world)
	runner.assert_true(not domain.begin("player", id, "make").ok, "finished batch cannot be cooked a second time")
	runner.assert_eq(_canonical(world), before, "repeated completion intent changes nothing")
	sim.inventory.containers[bag]["meal"] = SimInventory.MAX_COUNT
	runner.assert_true(domain.begin("player", id, "collect").ok, "collection intent is followed by actual handling")
	_finish(world, runner)
	runner.assert_eq(domain.batches[id].state, "ready", "full bag leaves the complete lot on site")
	runner.assert_eq(sim.inventory.quantity(id, "meal"), 6, "failed collection loses no part of the output")
	sim.inventory.containers[bag]["meal"] = 0
	runner.assert_true(domain.begin("player", id, "collect").ok, "a later attempt can really collect the stored goods")
	_finish(world, runner)
	runner.assert_eq(sim.inventory.quantity(bag, "meal"), 6, "actual collection transfers the whole batch to the original bag")
	runner.assert_true(world.services.begin("player", "home", "eat").ok, "newly made food enters the original carried-food action")
	fixtures._finish(world, "player", runner)
	runner.assert_eq(sim.inventory.quantity(bag, "meal"), 5, "eating consumes the same produced food")
	copy = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "finished, collected and used batch receipts agree")


func _custody_and_atomicity(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	var bag: String = "actor:player"
	_stock(world)
	var custody_fixture: RefCounted = load("res://tests/sim/test_entrusted_goods.gd").new()
	sim.inventory.containers.kitchen.wood = 5
	var held: String = custody_fixture._pickup(world, "cook", runner)
	sim.cancel_action("player")
	world.invalidate_region("home")
	var entrusted: int = sim.inventory.entrusted(bag, "grain")
	var id: String = str(world.personal_production.create("player", "home", "cook_rations").batch)
	runner.assert_true(not id.is_empty(), "own ingredients coexist with a separate entrusted public lot")
	_finish(world, runner)
	runner.assert_eq(sim.inventory.quantity(bag, "grain"), entrusted, "private cooking takes only freely disposable grain")
	runner.assert_true(sim.inventory.custody[held].settled_by.is_empty(), "private production cannot wash away the public consignment")
	runner.assert_true(not world.personal_production.create("player", "home", "cook_rations").ok, "remaining entrusted goods cannot start another private batch")
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "mixed ownership validates against original custody and process receipts")
	world = _world(runner)
	sim = world.regions.home
	_stock(world)
	id = str(world.personal_production.create("player", "home", "cook_rations").batch)
	var reservations: Array = world.personal_production.active.player.reservations
	sim.inventory.release(str(reservations.back()))
	var actual: Dictionary = sim.inventory.containers[bag].duplicate(true)
	world.advance_to_ms(120000)
	runner.assert_true(not world.personal_production.owns_actor("player"), "lost input reservation aborts at the physical handover")
	runner.assert_eq(sim.inventory.containers[bag], actual, "a late failed leg never partly consumes the bag")
	runner.assert_true(sim.inventory.containers[id].is_empty() and sim.inventory.reservations.is_empty(), "failed handover leaves an empty pending batch and releases only its reservations")


func _remote_trade_and_continuation(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	_stock(world)
	var domain: SimPersonalProduction = world.personal_production
	var id: String = str(domain.create("player", "river", "dry_herbs").batch)
	runner.assert_true(not id.is_empty(), "same human can walk to a distant worksite")
	world.advance_to_ms(1234)
	var snapshot: Dictionary = JSON.parse_string(_canonical(world))
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(snapshot), "cross-region batch restores without a visitor clone")
	world.active_region = "river"
	copy.active_region = "home"
	_finish(world, runner)
	_finish(copy, runner)
	world.active_region = "home"
	copy.active_region = "home"
	runner.assert_eq(_canonical(world), _canonical(copy), "near and far batching have the identical full future")
	runner.assert_eq(world.regions.home.inventory.quantity(id, "dried_herb"), 2, "original ledger names goods physically at the other settlement")
	runner.assert_true(not world.regions.river.actors.has("player") and not world.regions.river.inventory.containers.has(id), "remote use creates neither a body nor duplicate stock")
	fixtures._position(world, "home", "records")
	runner.assert_true(domain.begin("player", id, "collect").ok, "owner must actually return to the stored batch")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "dried_herb"), 0, "starting a distant pickup gives no remote item")
	_finish(world, runner)
	fixtures._position(world, "river", "records")
	world.regions.river.inventory.containers.records.coin = 3
	runner.assert_true(world.services._trade.authorize("player", "river", "river_chen_shouzhuo", "sell_dried_herb", 1).ok, "existing payment mandate can quote real processed goods")
	fixtures._finish(world, "player", runner)
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "dried_herb"), 1, "sale removes exactly one actually collected herb")
	runner.assert_eq(world.regions.river.inventory.quantity("records", "coin"), 0, "procurement spends original finite cash")
	copy = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "production and cross-region sale histories agree")
	# Working offscreen also retains precisely the original fractional needs.
	world = _world(runner)
	_stock(world)
	id = str(world.personal_production.create("player", "home", "dry_herbs").batch)
	_to_work(world, runner)
	world.advance_to_ms(world.elapsed_ms + 5678)
	copy = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "midwork duration and original body restore")
	var end: int = world.elapsed_ms + 450000
	while world.elapsed_ms < end:
		world.advance_to_ms(mini(end, world.elapsed_ms + 113))
	copy.advance_to_ms(end)
	runner.assert_eq(_canonical(world), _canonical(copy), "113ms steps and sparse advancement agree including energy remainders")


func _candidates(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	_stock(world)
	var id: String = str(world.personal_production.create("player", "home", "cook_rations").batch)
	_to_work(world, runner)
	world.advance_to_ms(world.elapsed_ms + 1234)
	var baseline: String = _canonical(world)
	for fault: String in ["owner", "region", "recipe", "extra", "fuel", "orphan", "duplicate", "time", "work", "position", "native", "reservation", "free"]:
		var bad: Dictionary = JSON.parse_string(baseline)
		var batch: Dictionary = bad.personal_production.batches[id]
		var job: Dictionary = bad.personal_production.active.player
		match fault:
			"owner": batch.owner = "missing"
			"region": batch.region = "missing"
			"recipe": batch.recipe = "missing"
			"extra": batch.stock = {"meal": 100}
			"fuel": bad.regions.home.inventory.operations.erase(id + ":fuel:wood")
			"orphan": bad.regions.home.inventory.operations["production_batch:999:fuel:wood"] = bad.regions.home.inventory.operations[id + ":fuel:wood"].duplicate(true)
			"duplicate": bad.regions.river.inventory.operations[id + ":fuel:wood"] = bad.regions.home.inventory.operations[id + ":fuel:wood"].duplicate(true)
			"time": job.due_ms += 1
			"work": batch.work_ms = 1200000
			"position": bad.regions.home.actors.player.position[0] += 1
			"native": bad.regions.home.actors.player.autonomous = true
			"reservation": bad.regions.home.inventory.reservations["production_job:999:wood"] = {"container": "actor:player", "item": "wood", "amount": 1, "owner_id": "player"}
			"free": bad.regions.home.inventory.containers[id].meal = 6
		runner.assert_true(not world.restore(bad), "independent candidate rejects forged batch: " + fault)
		runner.assert_eq(_canonical(world), baseline, "failed batch load preserves the entire live world: " + fault)
	world.personal_production.cancel("player")
	runner.assert_true(world.personal_production.begin("player", id, "make").ok, "interrupted process issues a new job identity")
	_to_work(world, runner)
	baseline = _canonical(world)
	var bad: Dictionary = JSON.parse_string(baseline)
	bad.personal_production.active.player.id = "production_job:1"
	runner.assert_true(not world.restore(bad), "a resumed process cannot reuse its already spent original ignition job identity")
	runner.assert_eq(_canonical(world), baseline, "invalid identity history preserves the resumed world")
	world.regions.home.actors.player.alive = false
	world.advance_to_ms(world.elapsed_ms + 1)
	runner.assert_true(not world.personal_production.owns_actor("player"), "loss of the actual living body interrupts its job")
	runner.assert_eq(world.regions.home.inventory.quantity(id, "grain"), 2, "lost worker does not erase on-site in-process materials")
