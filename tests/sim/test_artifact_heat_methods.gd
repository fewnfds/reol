extends RefCounted

const Fixtures = preload("res://tests/sim/test_artifacts.gd")
var _fixtures: RefCounted = Fixtures.new()


func run(runner: Object) -> void:
	_test_two_uses_one_supply(runner)
	_test_atomic_failures(runner)
	_test_drying_resume_and_cancel(runner)
	_test_autonomous_personal_learning(runner)
	_test_methods_respect_beliefs(runner)
	_test_depleted_experience_guides_recharge(runner)
	_test_methods_sparse_matches_fine(runner)


func _world(runner: Object) -> RegionalSimulation:
	return _fixtures._world(runner)


func _do(world: RegionalSimulation, actor: String, verb: String, runner: Object) -> void:
	var response: Dictionary = world.artifacts.begin(actor, verb, "hearth_stone")
	runner.assert_true(bool(response.ok), "real heat method begins: " + verb)
	if bool(response.ok):
		world.advance_to_ms(world.elapsed_ms + int(world.artifacts.definitions.verbs[verb].minutes) * 60000)


func _state(world: RegionalSimulation) -> int:
	return JSON.stringify(JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true)), "", true, true).hash()


func _test_two_uses_one_supply(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	_do(world, "player", "study", runner)
	_do(world, "player", "heat", runner)
	runner.assert_eq(world.artifacts.objects.hearth_stone.charge, 4, "cooking consumes the single stone's existing heat")
	_do(world, "player", "take", runner)
	sim.set_actor_cell("player", SimRouteTravel.cell(sim.places.garden.cell))
	var herb: int = sim.inventory.quantity("garden", "herb")
	var food: int = sim.inventory.quantity("kitchen", "meal")
	_do(world, "player", "dry", runner)
	runner.assert_eq(sim.inventory.quantity("garden", "herb"), herb - 2, "drying consumes actual raw herbs in the actual garden")
	runner.assert_eq(sim.inventory.quantity("garden", "dried_herb"), 2, "dry herbs remain as physical output in the same container")
	runner.assert_eq(sim.inventory.quantity("kitchen", "meal"), food, "second heat use does not pretend to be another cooking result")
	runner.assert_eq(world.artifacts.objects.hearth_stone.charge, 3, "second use draws down the same remaining finite supply")
	runner.assert_eq(world.artifacts.objects.size(), 1, "cross-purpose use never duplicates its unique object")
	runner.assert_eq(sim.actors.player.receipts.size(), 1, "new craft does not mint an unapproved institutional work receipt")
	var expected: int = _state(world)
	world.advance_to_ms(world.elapsed_ms)
	runner.assert_eq(_state(world), expected, "repeating a settled target cannot dry a second batch")
	var restored: RegionalSimulation = _world(runner)
	runner.assert_true(restored.restore(JSON.parse_string(JSON.stringify(world.to_dict()))), "both cooking and drying histories validate against their original transformations")
	runner.assert_eq(_state(restored), expected, "two real uses and their unique supply survive JSON exactly")
	print("SCENARIO shared heat: same finite stone cooks real food and dries real herbs, with separate social recognition")


func _prepare_drying(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _world(runner)
	_do(world, "player", "study", runner)
	_do(world, "player", "take", runner)
	world.regions.home.set_actor_cell("player", SimRouteTravel.cell(world.regions.home.places.garden.cell))
	return world


func _test_atomic_failures(runner: Object) -> void:
	for failure: String in ["stock", "charge", "capacity", "reservation"]:
		var world: RegionalSimulation = _prepare_drying(runner)
		var sim: VillageSimulation = world.regions.home
		match failure:
			"stock": sim.inventory.containers.garden.herb = 0
			"charge": world.artifacts.objects.hearth_stone.charge = 0
			"capacity": sim.inventory.containers.garden.dried_herb = SimInventory.MAX_COUNT
			"reservation": sim.inventory.reserve("pending:herbs", "garden", "herb", int(sim.inventory.quantity("garden", "herb")), "shi_tou")
		var herbs: int = sim.inventory.quantity("garden", "herb")
		var dried: int = sim.inventory.quantity("garden", "dried_herb")
		var charge: int = int(world.artifacts.objects.hearth_stone.charge)
		_do(world, "player", "dry", runner)
		runner.assert_eq(sim.inventory.quantity("garden", "herb"), herbs, "failed heat work never half-consumes herbs: " + failure)
		runner.assert_eq(sim.inventory.quantity("garden", "dried_herb"), dried, "failed heat work never adds output: " + failure)
		runner.assert_eq(world.artifacts.objects.hearth_stone.charge, charge, "failed heat work preserves unspent source heat: " + failure)
		runner.assert_eq(world.artifacts.events.back().kind, "depleted" if failure == "charge" else "failed", "failed heat work records actual failure: " + failure)


func _test_drying_resume_and_cancel(runner: Object) -> void:
	var world: RegionalSimulation = _prepare_drying(runner)
	runner.assert_true(bool(world.artifacts.begin("player", "dry", "hearth_stone").ok), "drying has a persistent in-progress action")
	world.advance_to_ms(world.elapsed_ms + 12345)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict()))
	var restored: RegionalSimulation = _world(runner)
	runner.assert_true(restored.restore(saved), "unfinished drying restores with original investments and full remaining time")
	var end: int = world.elapsed_ms + 400000
	world.advance_to_ms(end)
	restored.advance_to_ms(end)
	runner.assert_eq(_state(restored), _state(world), "unfinished drying continues with identical effects and source supply")
	world = _prepare_drying(runner)
	world.artifacts.begin("player", "dry", "hearth_stone")
	var qi: int = int(world.regions.home.actors.player.qi)
	world.advance_to_ms(world.elapsed_ms + 10000)
	world.artifacts.cancel("player")
	world.advance_to_ms(world.elapsed_ms + 400000)
	runner.assert_eq(world.regions.home.inventory.quantity("garden", "dried_herb"), 0, "cancelled drying never delivers a future product")
	runner.assert_eq(world.regions.home.actors.player.qi, qi, "cancelling cannot refund already invested personal qi")
	runner.assert_eq(world.artifacts.objects.hearth_stone.charge, 6, "interrupted heat transfer has not consumed the uncommitted source heat")


func _chef_world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	sim.set_actor_cell("a_he", SimRouteTravel.cell(sim.places.kitchen.cell))
	sim.actors.a_he.autonomous = true
	world.invalidate_region("home")
	return world


func _test_autonomous_personal_learning(runner: Object) -> void:
	var world: RegionalSimulation = _chef_world(runner)
	world.advance_to_ms(50)
	runner.assert_true(world.artifacts.active.has("a_he"), "chef chooses to examine a visible alternative when her known cooking fuel is missing")
	if not world.artifacts.active.has("a_he"):
		return
	runner.assert_eq(world.artifacts.active.a_he.verb, "inspect", "an untrained NPC starts with observation instead of hidden omniscient use")
	world.advance_to_ms(60050)
	runner.assert_eq(world.artifacts.active.a_he.verb, "study", "the NPC pays for an actual personal investigation after observation")
	runner.assert_true(not bool(world.artifacts.describe("player", "hearth_stone").method), "watching another actor investigate does not magically teach the player")
	world.advance_to_ms(300050)
	runner.assert_true(bool(world.artifacts.describe("a_he", "hearth_stone").method), "only the NPC's completed investigation teaches that NPC")
	runner.assert_eq(world.artifacts.active.a_he.verb, "heat", "learned NPC can select stone heat as a concrete alternative to wood")
	world.advance_to_ms(480050)
	runner.assert_eq(world.regions.home.inventory.quantity("kitchen", "meal"), 14, "NPC's alternative method creates actual food through the same material transaction")
	runner.assert_eq(world.artifacts.objects.hearth_stone.charge, 4, "NPC alternative consumes the same finite stone supply")
	runner.assert_eq(world.regions.home.actors.a_he.qi, 12, "NPC spends personal qi on investigation and use")
	runner.assert_true(not world.artifacts.active.has("a_he"), "observed sufficient output ends repeated alternative production")
	runner.assert_true(bool(world.regions.home.actors.a_he.autonomous), "completed experiment restores ordinary independent life")


func _test_methods_respect_beliefs(runner: Object) -> void:
	var world: RegionalSimulation = _chef_world(runner)
	var person: Dictionary = world.regions.home.actors.a_he
	person.autonomous = false
	world.advance_to_ms(50)
	person.autonomous = true
	person.retry_ms = world.elapsed_ms + int(world.regions.home.config.decision_interval) * 60000
	person.stock_memory.kitchen.items.wood = 12
	world.artifacts.consider_methods()
	runner.assert_true(not world.artifacts.active.has("a_he"), "NPC who believes fuel is stocked does not consult hidden empty inventory to seek a magic shortcut")
	person.stock_memory.kitchen.items.wood = 0
	world.artifacts.consider_methods()
	runner.assert_true(world.artifacts.active.has("a_he"), "changing that NPC's own expected supply can change its chosen method")
	world = _chef_world(runner)
	world.artifacts.objects.hearth_stone.charge = 0
	world.advance_to_ms(50)
	runner.assert_true(world.artifacts.active.has("a_he"), "NPC cannot read private source charge to foresee failure before any personal experiment")


func _test_methods_sparse_matches_fine(runner: Object) -> void:
	var fine: RegionalSimulation = _chef_world(runner)
	var sparse: RegionalSimulation = _chef_world(runner)
	for target: int in [60050, 183111, 300050, 480050]:
		while fine.elapsed_ms < target:
			fine.advance_to_ms(mini(target, fine.elapsed_ms + 250))
		sparse.advance_to_ms(target)
		runner.assert_eq(_state(sparse), _state(fine), "NPC personal learning/alternative work matches sparse/fine execution at %dms" % target)


func _test_depleted_experience_guides_recharge(runner: Object) -> void:
	var world: RegionalSimulation = _chef_world(runner)
	world.artifacts.objects.hearth_stone.charge = 0
	world.advance_to_ms(480050)
	runner.assert_eq(world.artifacts.events.back().kind, "depleted", "NPC learns lack of usable heat by actually trying, without a private-charge query")
	runner.assert_true(world.artifacts.active.has("a_he") and world.artifacts.active.a_he.verb == "charge", "that personal failure can guide a real recharge method instead of an endless blind retry")
	world.advance_to_ms(600050)
	runner.assert_eq(world.artifacts.objects.hearth_stone.charge, 6, "NPC's own qi supplies the same stone rather than creating a second reserve")
	runner.assert_eq(world.regions.home.actors.a_he.qi, 6, "NPC pays study, failed experiment, recharge and accepted next use from the original qi")
