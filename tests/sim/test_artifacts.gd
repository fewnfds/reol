extends RefCounted

const Fixtures = preload("res://tests/sim/test_regional_simulation.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_test_material_transform(runner)
	_test_unique_location_and_personal_understanding(runner)
	_test_experiments_real_costs_and_food(runner)
	_test_mid_action_json_and_cancellation(runner)
	_test_invalid_artifacts_are_atomic(runner)
	_test_coarse_and_fine(runner)


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _fixtures._make_world(runner)
	if world == null:
		return null
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))
	runner.assert_true(world.artifacts.spawn_opening(opening), "new scenario issues its real objects at declared locations")
	world.regions.home.set_actor_cell("player", SimRouteTravel.cell(world.regions.home.places.kitchen.cell.duplicate()))
	world.invalidate_region("home")
	return world


func _do(runner: Object, world: RegionalSimulation, verb: String) -> void:
	var result: Dictionary = world.artifacts.begin("player", verb, "hearth_stone")
	runner.assert_true(bool(result.ok), "real artifact action begins: " + verb)
	if bool(result.ok):
		runner.assert_true(world.advance_to(world.current_time + int(world.artifacts.definitions.verbs[verb].minutes)), "world settles artifact duration: " + verb)


func _state(world: RegionalSimulation) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(world.to_dict())), "", true, true)


func _test_material_transform(runner: Object) -> void:
	var inventory := SimInventory.new()
	inventory.create_container("pot", {"grain": 2, "water": 1, "meal": 0})
	inventory.reserve("other", "pot", "grain", 1, "cook")
	var before: Dictionary = inventory.to_dict()
	runner.assert_true(not inventory.transform("cook", "pot", {"grain": 2, "water": 1}, {"meal": 6}), "alternate heat respects another cook's ingredient reservation")
	runner.assert_eq(inventory.to_dict(), before, "failed recipe consumes no partial ingredients")
	inventory.release("other")
	runner.assert_true(inventory.transform("cook", "pot", {"grain": 2, "water": 1}, {"meal": 6}), "complete material transaction cooks real food")
	runner.assert_true(inventory.transform("cook", "pot", {"grain": 2, "water": 1}, {"meal": 6}), "identical transaction retry is idempotent")
	runner.assert_eq(inventory.quantity("pot", "meal"), 6, "retry cannot create a second batch")
	runner.assert_true(not inventory.transform("cook", "pot", {"grain": 1}, {"meal": 9}), "transaction ID cannot be reused for a different recipe")
	var restored := SimInventory.new()
	runner.assert_true(restored.restore(JSON.parse_string(JSON.stringify(inventory.to_dict()))), "material transformation survives JSON validation")
	runner.assert_true(restored.transform("cook", "pot", {"grain": 2, "water": 1}, {"meal": 6}), "restored transaction remains idempotent")
	var overflow := SimInventory.new()
	overflow.create_container("pot", {"grain": 2, "water": 1, "meal": SimInventory.MAX_COUNT})
	before = overflow.to_dict()
	runner.assert_true(not overflow.transform("overflow", "pot", {"grain": 2, "water": 1}, {"meal": 6}), "full output rejects recipe before consuming inputs")
	runner.assert_eq(overflow.to_dict(), before, "capacity failure is atomic")


func _test_unique_location_and_personal_understanding(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var domain: SimArtifacts = world.artifacts
	runner.assert_true(not bool(domain.describe("river_player", "hearth_stone").known), "distant resident does not know an undiscovered object")
	var view: Dictionary = domain.describe("player", "hearth_stone")
	runner.assert_true(bool(view.known) and not bool(view.method) and not view.has("charge"), "novice receives appearance without hidden charge or activation")
	var before: String = _state(world)
	for _index in 10:
		domain.describe("player", "hearth_stone")
	runner.assert_eq(_state(world), before, "opening details neither teaches a method nor changes random state")
	var original_count: int = domain.objects.size()
	_do(runner, world, "take")
	runner.assert_eq(domain.objects.hearth_stone.container, "actor:player", "taking changes the object's single canonical container")
	runner.assert_eq(domain.objects.size(), original_count, "taking never makes a second object")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "warm_stone"), 0, "unique object is not duplicated as a stack in the quantity ledger")
	world.regions.home.set_actor_cell("player", SimRouteTravel.cell([102, 102]))
	runner.assert_eq(domain.object_cell("hearth_stone"), Vector2i(102, 102), "carried object follows the actual body through its source reference")
	world.regions.home.set_actor_cell("chen_shouzhuo", SimRouteTravel.cell([102, 102]))
	runner.assert_true(not bool(domain.begin("chen_shouzhuo", "take", "hearth_stone").ok), "another person cannot silently take an already held object")
	runner.assert_true(not bool(domain.describe("shi_tou", "hearth_stone").method), "seeing another person hold a stone does not teach its use")


func _test_experiments_real_costs_and_food(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var sim: VillageSimulation = world.regions.home
	var person: Dictionary = sim.actors.player
	var definition: Dictionary = world.artifacts.definitions.types.warm_stone
	var food: int = sim.inventory.quantity("kitchen", "meal")
	var qi: int = int(person.qi)
	var stamina: int = int(person.stamina)
	_do(runner, world, "heat")
	runner.assert_eq(person.qi, qi - int(world.artifacts.definitions.verbs.heat.qi), "failed untrained trial spends actual qi")
	runner.assert_eq(person.stamina, stamina - int(definition.backlash_stamina), "uncontrolled flow causes real stamina backlash")
	runner.assert_eq(sim.inventory.quantity("kitchen", "meal"), food, "failed trial creates no food")
	runner.assert_eq(world.artifacts.objects.hearth_stone.charge, int(definition.opening_charge), "failed control does not secretly produce heat")
	_do(runner, world, "study")
	runner.assert_true(bool(world.artifacts.describe("player", "hearth_stone").method), "deliberate paid investigation creates personal practical understanding")
	runner.assert_true(not bool(world.artifacts.describe("shi_tou", "hearth_stone").method), "another subject does not inherit the player's investigation")
	runner.assert_true(not world.artifacts.begin("player", "heat", "hearth_stone").ok, "knowing the method does not bypass the new bodily consequence")
	world.advance_to_ms(world.elapsed_ms + int(world.health.definitions.recovery.required) * 60000)
	runner.assert_true(world.health.current_source("player").is_empty(), "actual recovery time passes before renewed heat work")
	food = sim.inventory.quantity("kitchen", "meal")
	var grain: int = sim.inventory.quantity("kitchen", "grain")
	var water: int = sim.inventory.quantity("kitchen", "water")
	var wood: int = sim.inventory.quantity("kitchen", "wood")
	_do(runner, world, "heat")
	runner.assert_eq(sim.inventory.quantity("kitchen", "grain"), grain - int(definition.inputs.grain), "magic heat still consumes grain")
	runner.assert_eq(sim.inventory.quantity("kitchen", "water"), water - int(definition.inputs.water), "magic heat still consumes water")
	runner.assert_eq(sim.inventory.quantity("kitchen", "wood"), wood, "charged stone genuinely substitutes for wood")
	runner.assert_eq(sim.inventory.quantity("kitchen", "meal"), food + int(definition.outputs.meal), "real cooked food reaches the shared kitchen")
	runner.assert_eq(world.artifacts.objects.hearth_stone.charge, int(definition.opening_charge) - int(definition.heat_cost), "successful use consumes finite stored heat once")
	runner.assert_eq(sim.actors.player.receipts.size(), 1, "needed alternative production creates original institutional evidence")
	runner.assert_eq(sim.institutions.balance(str(sim.config.institution.id), "player"), 0, "producing evidence is still distinct from formal registration")
	var settled: String = _state(world)
	world.advance_to(world.current_time)
	runner.assert_eq(_state(world), settled, "repeated completed horizon cannot double cook or award evidence")
	_do(runner, world, "charge")
	runner.assert_eq(world.artifacts.objects.hearth_stone.charge, mini(int(definition.max_charge), int(definition.opening_charge) - int(definition.heat_cost) + int(definition.charge_gain)), "recharging has a defined capacity and real qi cost")
	print("SCENARIO artifact: novice backlash→personal investigation→finite heat replaces wood, consumes grain/water and yields actual food/evidence")


func _test_mid_action_json_and_cancellation(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	world.artifacts.begin("player", "study", "hearth_stone")
	world.advance_to(world.current_time + 1)
	runner.assert_true(not world.regions.home.submit_action("player", "rest"), "native executor cannot also own a body studying an artifact")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict()))
	var resumed: RegionalSimulation = _world(runner)
	runner.assert_true(resumed.restore(snapshot), "unfinished investigation restores into an independent candidate world")
	var finish: int = int(world.artifacts.active.player.due_ms)
	world.advance_to_ms(finish)
	resumed.advance_to_ms(finish)
	runner.assert_eq(_state(resumed), _state(world), "mid-action JSON preserves costs, learning, event IDs and same future")
	world.artifacts.begin("player", "charge", "hearth_stone")
	var qi_after: int = int(world.regions.home.actors.player.qi)
	var heat_before: int = int(world.artifacts.objects.hearth_stone.charge)
	world.artifacts.cancel("player")
	runner.assert_eq(world.regions.home.actors.player.qi, qi_after, "cancellation does not refund the committed input")
	runner.assert_eq(world.artifacts.objects.hearth_stone.charge, heat_before, "cancelled charging grants no future heat")
	var control: SimEmbodiment = resumed.embodiment
	resumed.artifacts.begin("player", "charge", "hearth_stone")
	control.release_control(control.subject_for_actor("player"), control.carrier_for_source("village_actor", "player"), "action")
	resumed.invalidate_region("home")
	resumed.advance_to(resumed.current_time + 1)
	runner.assert_true(not resumed.artifacts.owns_actor("player"), "loss of control interrupts the artifact executor as well")


func _test_invalid_artifacts_are_atomic(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	_do(runner, world, "study")
	_do(runner, world, "heat")
	var good: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict()))
	var successful_restore: RegionalSimulation = _world(runner)
	runner.assert_true(successful_restore.restore(good), "completed heat and its normalized integer material ledger restore successfully")
	runner.assert_eq(_state(successful_restore), _state(world), "completed food, evidence and personal learning survive JSON together")
	var invalids: Array[Dictionary] = []
	for charge: Variant in [-1, 100, 1.5, true]:
		var bad: Dictionary = good.duplicate(true)
		bad.artifacts.objects.hearth_stone.charge = charge
		invalids.append(bad)
	var bad: Dictionary = good.duplicate(true)
	bad.artifacts.objects.hearth_stone.container = "actor:missing"
	invalids.append(bad)
	bad = good.duplicate(true)
	bad.artifacts.events[0].subject = "subject:chen_shouzhuo"
	invalids.append(bad)
	bad = good.duplicate(true)
	bad.artifacts.events[0].verb = "inspect"
	invalids.append(bad)
	bad = good.duplicate(true)
	bad.artifacts.erase("active")
	invalids.append(bad)
	bad = good.duplicate(true)
	bad.erase("artifacts")
	invalids.append(bad)
	bad = good.duplicate(true)
	bad.regions.home.inventory.operations[str(good.artifacts.events[-1].action) + ":heat"].outputs.meal = 7
	invalids.append(bad)
	for invalid: Dictionary in invalids:
		var before: String = _state(world)
		runner.assert_true(not world.restore(invalid), "bad artifacts, witnesses and material effects are rejected")
		runner.assert_eq(_state(world), before, "bad object domain cannot partially replace world, materials or knowledge")


func _test_coarse_and_fine(runner: Object) -> void:
	var fine: RegionalSimulation = _world(runner)
	var coarse: RegionalSimulation = _world(runner)
	if fine == null or coarse == null:
		return
	for verb: String in ["take", "study", "heat", "charge", "place"]:
		fine.artifacts.begin("player", verb, "hearth_stone")
		coarse.artifacts.begin("player", verb, "hearth_stone")
		var due: int = int(fine.artifacts.active.player.due_ms)
		while fine.elapsed_ms < due:
			fine.advance_to_ms(mini(due, fine.elapsed_ms + 60000))
		coarse.advance_to_ms(due)
		runner.assert_eq(_state(coarse), _state(fine), "quiet far batching preserves artifact costs/observations/material effects: " + verb)
