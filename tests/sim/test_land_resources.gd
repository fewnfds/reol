extends RefCounted

const Fixtures = preload("res://tests/sim/test_village_simulation.gd")
const RegionalFixtures = preload("res://tests/sim/test_regional_simulation.gd")
var _fixtures: RefCounted = Fixtures.new()


func run(runner: Object) -> void:
	_test_growth_is_finite_and_requires_labor(runner)
	_test_depletion_competition_and_custody(runner)
	_test_overflow_keeps_source_and_cargo(runner)
	_test_saved_work_and_bad_candidates(runner)
	_test_world_coarse_and_fine(runner)
	_test_known_buffers_drive_supply(runner)
	_test_three_days_from_empty_buffers(runner)


func _make(runner: Object, autonomous: bool = false) -> VillageSimulation:
	return _fixtures._make_simulation(runner, autonomous)


func _finish(sim: VillageSimulation, actor: String, runner: Object) -> void:
	var deadline: int = sim.elapsed_ms + 21600000
	while not sim.actors[actor].active.is_empty() and sim.elapsed_ms < deadline:
		sim.advance_to_ms(sim.next_boundary_ms())
	runner.assert_true(sim.actors[actor].active.is_empty(), "resource work reaches a terminal state")


func _state(sim: VillageSimulation) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(sim.to_dict(), "", true, true)), "", true, true)


func _test_growth_is_finite_and_requires_labor(runner: Object) -> void:
	var sim: VillageSimulation = _make(runner)
	var store: int = sim.inventory.quantity("store", "wood")
	var before: String = _state(sim)
	var line: String = sim.land_resources.describe("player", "woodlot")
	runner.assert_true(line.contains("落枝") and _state(sim) == before, "looking at a source neither grows it nor delivers goods")
	sim.advance_to_ms(5 * 86400000)
	runner.assert_eq(sim.inventory.quantity("resource:woodlot", "wood"), 18, "five absent days cannot bank more than the woodland capacity")
	runner.assert_eq(sim.inventory.quantity("store", "wood"), store, "natural growth never silently replenishes the warehouse")
	runner.assert_eq(sim.land_resources.sources.woodlot.produced, 6, "growth records only the actual increment before capacity")
	runner.assert_true(sim.submit_action("player", "gather_wood"), "the same real actor can collect finite branches")
	_finish(sim, "player", runner)
	runner.assert_eq(sim.inventory.quantity("store", "wood"), store + 3, "completed labor physically delivers three branches")
	runner.assert_eq(sim.inventory.quantity("resource:woodlot", "wood"), 15, "full past days do not immediately refill a newly harvested source")
	sim.advance_to_ms(5 * 86400000 + 3600000)
	runner.assert_eq(sim.inventory.quantity("resource:woodlot", "wood"), 17, "the next actual growth pulse adds its bounded amount")
	runner.assert_true(SimSnapshotSchema.validate(sim.to_dict(), sim._content), "skipped full growth and extraction remain valid persisted history")


func _test_depletion_competition_and_custody(runner: Object) -> void:
	var sim: VillageSimulation = _make(runner)
	sim.inventory.containers.store.grain = 0
	runner.assert_true(sim.submit_action("player", "forage_grain"), "foraging reserves one actual batch")
	sim.advance_to_ms(2000)
	runner.assert_eq(sim.inventory.quantity("actor:player", "grain"), 0, "reaching the patch does not bypass the full harvest labor")
	sim.cancel_action("player")
	runner.assert_eq(sim.inventory.quantity("resource:meadow", "grain"), 12, "cancelling before harvest leaves grain on the plants")
	runner.assert_eq(sim.inventory.reservations.size(), 0, "cancel frees all unharvested reservations")
	runner.assert_true(sim.submit_action("player", "draw_water"), "first worker reserves twelve spring units")
	runner.assert_true(sim.submit_action("su_zhi", "draw_water"), "second worker reserves the other twelve spring units")
	runner.assert_true(not sim.submit_action("shi_tou", "draw_water"), "third worker cannot reserve the same water")
	sim.cancel_action("su_zhi")
	runner.assert_true(sim.submit_action("shi_tou", "draw_water"), "released water becomes available to another real worker")
	sim.cancel_action("shi_tou")
	sim.cancel_action("player")
	for _index in range(3):
		runner.assert_true(sim.submit_action("player", "forage_grain"), "another finite grain batch can be gathered")
		_finish(sim, "player", runner)
	runner.assert_eq(sim.inventory.quantity("resource:meadow", "grain"), 0, "three real harvests exhaust the opening mature patch")
	runner.assert_true(not sim.submit_action("player", "forage_grain"), "an exhausted source refuses a fourth reservation")
	sim.advance_to_ms(10800000)
	runner.assert_true(sim.submit_action("player", "forage_grain"), "maturing grain later permits a new real harvest")
	while not sim.actors.player.active.is_empty() and not bool(sim.actors.player.active.carrying):
		sim.advance_to_ms(sim.next_boundary_ms())
	runner.assert_eq(sim.inventory.quantity("actor:player", "grain"), 4, "finished harvest first exists in the carrier's original pocket")
	var harvested: int = int(sim.land_resources.sources.meadow.extracted)
	var warehouse: int = sim.inventory.quantity("store", "grain")
	sim.cancel_action("player")
	runner.assert_eq(sim.inventory.quantity("actor:player", "grain"), 4, "interrupted return does not erase or refund harvested grain")
	runner.assert_true(sim.submit_action("player", "forage_grain"), "retrying first resumes the grain already held")
	_finish(sim, "player", runner)
	runner.assert_eq(sim.land_resources.sources.meadow.extracted, harvested, "resumed delivery never harvests a duplicate batch")
	runner.assert_eq(sim.inventory.quantity("store", "grain"), warehouse + 4, "the same held grain arrives once")
	runner.assert_true(sim.institutions.balance("sect", "player") == 0 and not sim.actors.player.receipts.is_empty(), "needed physical supply creates evidence rather than automatic institutional credit")


func _test_overflow_keeps_source_and_cargo(runner: Object) -> void:
	var sim: VillageSimulation = _make(runner)
	# Existing pocket goods normally resume delivery. Reserve a different item,
	# then fill that pocket before its real harvest finishes.
	sim.inventory.containers["actor:player"].erase("grain")
	runner.assert_true(sim.submit_action("player", "forage_grain"), "overflow scenario begins ordinary harvest")
	sim.inventory.containers["actor:player"]["grain"] = SimInventory.MAX_COUNT - 2
	_finish(sim, "player", runner)
	runner.assert_eq(sim.land_resources.sources.meadow.extracted, 0, "full carrier cannot remove a batch from its natural source")
	runner.assert_eq(sim.inventory.reservations.size(), 0, "failed harvest releases its reservation")
	sim.inventory.containers["actor:player"].erase("grain")
	sim.inventory.containers.store.grain = SimInventory.MAX_COUNT
	runner.assert_true(sim.submit_action("player", "forage_grain"), "physical harvest may precede discovering a full destination")
	_finish(sim, "player", runner)
	runner.assert_eq(sim.inventory.quantity("actor:player", "grain"), 4, "full warehouse leaves already harvested goods with the carrier")
	runner.assert_eq(sim.land_resources.sources.meadow.extracted, 4, "failed deposit does not reverse physical extraction")
	runner.assert_true(SimSnapshotSchema.validate(sim.to_dict(), sim._content), "failed deposit still has a fully restorable custody and source state")


func _test_saved_work_and_bad_candidates(runner: Object) -> void:
	var sim: VillageSimulation = _make(runner)
	runner.assert_true(sim.submit_action("player", "forage_grain"), "save scenario begins harvesting")
	sim.advance_to_ms(43517)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(sim.to_dict()))
	var restored: VillageSimulation = _make(runner)
	runner.assert_true(restored.restore(saved), "fractional in-progress harvesting restores from ordinary JSON")
	sim.advance_to_ms(12000000)
	restored.advance_to_ms(12000000)
	runner.assert_true(_state(restored) == _state(sim), "resumed harvest, growth phase, cargo and all other life share the same future")
	var before: String = _state(restored)
	var variants: Array[Dictionary] = []
	var bad: Dictionary = saved.duplicate(true)
	bad.erase("land_resources")
	variants.append(bad)
	bad = saved.duplicate(true)
	bad.land_resources.sources.meadow.produced = 4
	variants.append(bad)
	bad = saved.duplicate(true)
	bad.land_resources.sources.meadow.next_growth_ms += 1
	variants.append(bad)
	bad = saved.duplicate(true)
	bad.inventory.containers["resource:meadow"].grain = 25
	variants.append(bad)
	bad = saved.duplicate(true)
	bad.inventory.reservations[bad.actors.player.active.reservations[0]].container = "store"
	variants.append(bad)
	bad = saved.duplicate(true)
	bad.config.actions.gather_wood.item = "coin"
	variants.append(bad)
	bad = saved.duplicate(true)
	bad.config.actions.gather_wood.amount = 1000
	variants.append(bad)
	for candidate: Dictionary in variants:
		runner.assert_true(not restored.restore(candidate), "bad modern source, growth, capacity or reservation is rejected")
		runner.assert_true(_state(restored) == before, "rejected source snapshot leaves the living world unchanged")


func _test_world_coarse_and_fine(runner: Object) -> void:
	var fixture := RegionalFixtures.new()
	var near: RegionalSimulation = fixture._make_world(runner)
	var far: RegionalSimulation = fixture._make_world(runner)
	near.set_active_region("home")
	for world: RegionalSimulation in [near, far]:
		runner.assert_true(world.regions.home.submit_action("player", "forage_grain"), "near and absent worlds both begin the same actual harvest")
		world.invalidate_region("home")
	while near.elapsed_ms < 12000000:
		near.advance_to_ms(mini(12000000, near.elapsed_ms + 517))
	runner.assert_true(far.advance_to_ms(12000000), "absent world reaches growth and work boundaries without minute-by-minute execution")
	near.set_active_region("")
	runner.assert_true(fixture._state(near) == fixture._state(far), "fine near execution and absent sparse execution produce identical resources, work and transport")


func _test_known_buffers_drive_supply(runner: Object) -> void:
	var sim: VillageSimulation = _make(runner)
	var actor: Dictionary = sim.actors.su_zhi
	actor.autonomous = true
	sim.inventory.containers.store.grain = 0
	sim.set_actor_cell("su_zhi", Vector2i(130, 130))
	actor.stock_memory.store = {"items": {"grain": 100}, "tick": 0}
	actor.stock_memory.kitchen = {"items": {"grain": 10}, "tick": 0}
	sim.advance_to_ms(50)
	runner.assert_true(actor.active.is_empty(), "distant worker believing buffers full does not secretly read the empty warehouse")
	sim.set_actor_cell("su_zhi", Vector2i(int(sim.places.store.cell[0]), int(sim.places.store.cell[1])))
	sim.observe_current_surroundings("su_zhi")
	sim.advance_to_ms(int(actor.retry_ms))
	runner.assert_true(not actor.active.is_empty() and actor.active.action == "forage_grain", "personal warehouse verification changes the worker's real supply choice")


func _test_three_days_from_empty_buffers(runner: Object) -> void:
	var sim: VillageSimulation = _make(runner, true)
	for place: String in sim.places:
		for item: String in sim.inventory.containers[place]:
			sim.inventory.containers[place][item] = 0
	for actor: String in sim.actors:
		sim.observe_current_surroundings(actor)
	for day in range(1, 4):
		runner.assert_true(sim.advance_to_ms(day * 86400000, 32768), "autonomous low-stock village reaches another day with explicit production")
	var totals: Dictionary = {}
	for id: String in sim.land_resources.sources:
		totals[id] = int(sim.land_resources.sources[id].extracted)
	runner.assert_true(totals.woodlot > 0 and totals.meadow > 0 and totals.spring > 0, "NPC labor replenishes wood, food grain and drawn water from real sources")
	var cooked: int = 0
	for operation: Dictionary in sim.inventory.operations.values():
		if operation.kind == "consume" and operation.get("item") == "grain":
			cooked += int(operation.amount)
	runner.assert_true(cooked > 0, "autonomous cooking consumes the physically gathered grain")
	for id: String in sim.actors:
		if bool(sim.actors[id].autonomous):
			runner.assert_true(float(sim.actors[id].hunger) > 0, "gathering, cooking and eating support each autonomous resident through the low-stock run: " + id)
	runner.assert_true(SimSnapshotSchema.validate(sim.to_dict(), sim._content), "three-day natural accounting, active reservations and institutional evidence remain save-valid")
	print("SCENARIO livelihood: three days from empty facility buffers, extracted=%s, cooked_grain=%d; natural sources and labor stay explicit" % [str(totals), cooked])
