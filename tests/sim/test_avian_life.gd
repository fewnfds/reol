extends RefCounted

const Fixtures = preload("res://tests/sim/test_regional_simulation.gd")


func run(runner: Object) -> void:
	_test_life_and_geometry(runner)
	_test_real_delivery(runner)
	_test_precision_and_candidates(runner)
	print("SCENARIO avian: independent bodies forage/rest, fit shared openings, carry real light herbs and persist away from the player")


func _make(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = Fixtures.new()._make_world(runner)
	if world != null:
		var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/avian_life.json"))
		runner.assert_true(world.avian_life.spawn_opening(scenario, {"home": Vector2i(100, 100), "river": Vector2i(150, 100)}), "opening stages actual bird bodies, sites and unique references")
	return world


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _events(domain: SimAvianLife, kind: String, id: String = "") -> int:
	var result: int = 0
	for event: Dictionary in domain.events:
		if event.kind == kind and (id.is_empty() or event.bird == id):
			result += 1
	return result


func _test_life_and_geometry(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	var birds: SimAvianLife = world.avian_life
	runner.assert_eq(birds.birds.size(), 2, "two nonhuman bodies exist without Village pawns")
	runner.assert_true(not world.regions.home.actors.has("moss_sparrow"), "bird does not inherit a humanoid pawn's needs or work system")
	var carrier: String = world.embodiment.carrier_for_source("avian_body", "moss_sparrow")
	runner.assert_eq(carrier, SimAvianLife.carrier_id("moss_sparrow"), "registry references the one physical source")
	runner.assert_true(not world.embodiment.capable(carrier, "village_routine") and world.embodiment.capable(carrier, "fly"), "bird flight never implies human labor")
	var human: String = world.embodiment.carrier_for_source("village_actor", "player")
	for site: String in ["home:crevice", "home:second_crevice", "river:crevice", "river:second_crevice"]:
		runner.assert_true(birds.can_enter(carrier, site) and not birds.can_enter(human, site), "same width rule admits a sparrow and rejects a human at each crevice")
	runner.assert_true(birds.can_carry("moss_sparrow", "herb") and not birds.can_carry("moss_sparrow", "grain") and not birds.can_carry("moss_sparrow", "wood"), "beak fits a sprig but cannot move bulk human supplies")
	var river_energy: int = int(birds.birds.reed_sparrow.energy)
	world.advance_to_ms(500)
	runner.assert_true(birds.birds.moss_sparrow.active.verb == "fly" and birds.birds.reed_sparrow.active.verb == "rest", "hungry bird flies to food while tired bird selects its own roost")
	runner.assert_true(SimAvianLife.point(birds.birds.moss_sparrow) != TileGrid.cell_to_world(Vector2i(98, 99)), "flight is continuous displacement, not a teleport")
	world.advance_to_ms(240000)
	runner.assert_true(_events(birds, "forage", "moss_sparrow") > 0 and _events(birds, "rest", "reed_sparrow") > 0, "both birds meet needs without player intervention or local views")
	runner.assert_true(int(birds.birds.reed_sparrow.energy) > river_energy and birds.inventory.quantity("home:seeds", "seed") < 8, "rest restores original energy and eating consumes finite food")
	var before: String = JSON.stringify(birds.to_dict(), "", true, true)
	for _index in 5:
		birds.describe("player", "moss_sparrow")
		birds.can_carry("moss_sparrow", "herb")
	runner.assert_eq(JSON.stringify(birds.to_dict(), "", true, true), before, "queries do not feed, learn or reroll")
	world.advance_to_ms(600000)
	runner.assert_true(_events(birds, "ripened") >= 4, "plants replenish finite stock at their actual growth boundary")
	runner.assert_true(not bool(birds.describe("river_player", "moss_sparrow").known), "a far person cannot inspect another region's bird")
	var shortage: RegionalSimulation = _make(runner)
	shortage.advance_to_ms(100)
	var memory: Dictionary = shortage.avian_life.birds.moss_sparrow.known_sites["home:seeds"].duplicate(true)
	shortage.avian_life.inventory.containers["home:seeds"].seed = 0
	runner.assert_eq(shortage.avian_life.birds.moss_sparrow.known_sites["home:seeds"], memory, "changing food does not telepathically update a flying bird")
	shortage.advance_to_ms(40000)
	runner.assert_true(_events(shortage.avian_life, "failed", "moss_sparrow") > 0 and _events(shortage.avian_life, "forage", "moss_sparrow") > 0, "empty attempt fails, personal observation corrects it and another patch is tried")
	var landing: RegionalSimulation = _make(runner)
	landing.avian_life.set_landing_check(func(_at: Vector2i) -> bool: return false)
	var at: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(landing.avian_life.sites["home:seeds"].cell))
	landing.avian_life.birds.moss_sparrow.position = [at.x, at.y]
	runner.assert_true(not landing.avian_life._go("moss_sparrow", "home:seeds", "forage"), "flying over blocked ground grants no arbitrary landing")
	runner.assert_eq(landing.avian_life.birds.moss_sparrow.altitude, 1, "failed landing leaves the bird aloft")


func _prepare_help(world: RegionalSimulation) -> void:
	var domain: SimAvianLife = world.avian_life
	var at: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(domain.sites["home:seeds"].cell))
	SimRouteTravel.put(world.regions.home.actors.player, at)
	domain.birds.moss_sparrow.position = [at.x, at.y]
	domain.birds.moss_sparrow.altitude = 0
	domain.birds.moss_sparrow.fullness = 75 * SimAvianLife.SCALE
	domain.birds.moss_sparrow.energy = 80 * SimAvianLife.SCALE
	world.regions.home.inventory.containers["actor:player"]["grain"] = 1


func _test_real_delivery(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	var domain: SimAvianLife = world.avian_life
	_prepare_help(world)
	runner.assert_true(not bool(domain.ask_herb("player", "moss_sparrow").ok), "a polite stranger cannot demand free service")
	var herbs: int = world.regions.home.inventory.quantity("garden", "herb") + domain.inventory.quantity("home:crevice", "herb") + domain.inventory.quantity("home:second_crevice", "herb")
	var seeds: int = domain.inventory.quantity("home:seeds", "seed")
	runner.assert_true(bool(domain.offer_grain("player", "moss_sparrow").ok), "nearby personal grain can be scattered into edible food")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "grain"), 0, "gift consumes actual personal grain")
	runner.assert_eq(domain.inventory.quantity("home:seeds", "seed"), seeds + int(domain.definitions.gift.seed), "gift remains real food rather than only social points")
	runner.assert_true(not bool(domain.offer_grain("player", "moss_sparrow").ok), "empty hands cannot repeat the gift")
	runner.assert_true(bool(domain.ask_herb("player", "moss_sparrow").ok), "fed and capable bird accepts a specific request")
	world.advance_to_ms(60000)
	runner.assert_eq(_events(domain, "drop", "moss_sparrow"), 1, "accepted trip leaves one actual delivery")
	runner.assert_eq(world.regions.home.inventory.quantity("garden", "herb"), herbs - domain.inventory.quantity("home:crevice", "herb") - domain.inventory.quantity("home:second_crevice", "herb"), "herb moves from ledge stock to the original garden without creation")
	runner.assert_eq(domain.inventory.quantity("bird:moss_sparrow", "herb"), 0, "delivery clears the one physical carried sprig")
	var resumed: RegionalSimulation = _make(runner)
	runner.assert_true(resumed.restore(JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))), "food gift and cross-domain delivery validate with real human inventory")
	runner.assert_eq(_canonical(resumed), _canonical(world), "loaded world retains gifts and delivery exactly once")


func _test_precision_and_candidates(runner: Object) -> void:
	var coarse: RegionalSimulation = _make(runner)
	var fine: RegionalSimulation = _make(runner)
	for at: int in range(1, 2447, 50):
		fine.advance_to_ms(at)
	fine.advance_to_ms(2447)
	coarse.advance_to_ms(2447)
	runner.assert_eq(_canonical(fine), _canonical(coarse), "50ms flight and needs match a sparse fractional target")
	var resumed: RegionalSimulation = _make(runner)
	runner.assert_true(resumed.restore(JSON.parse_string(JSON.stringify(coarse.to_dict(), "", true, true))), "in-flight body and pending action survive JSON")
	coarse.advance_to_ms(600123)
	resumed.advance_to_ms(600123)
	for at: int in range(3000, 600123, 533):
		fine.advance_to_ms(at)
	fine.advance_to_ms(600123)
	runner.assert_eq(_canonical(resumed), _canonical(coarse), "restored future equals uninterrupted execution")
	runner.assert_eq(_canonical(fine), _canonical(coarse), "phase changes, fixed-point needs and regrowth do not depend on near/far step size")
	var base: Dictionary = JSON.parse_string(JSON.stringify(coarse.to_dict(), "", true, true))
	var bads: Array[Dictionary] = []
	var bad: Dictionary = base.duplicate(true)
	bad.avian_life.birds.moss_sparrow.position = [-1, 0]
	bads.append(bad)
	bad = base.duplicate(true)
	bad.avian_life.inventory.containers["bird:moss_sparrow"] = {"wood": 1}
	bads.append(bad)
	bad = base.duplicate(true)
	bad.avian_life.birds.moss_sparrow.active.due_ms += 100
	bads.append(bad)
	bad = base.duplicate(true)
	bad.embodiment.carriers[SimAvianLife.carrier_id("moss_sparrow")].source.id = "missing"
	bads.append(bad)
	bad = base.duplicate(true)
	bad.avian_life.birds.moss_sparrow.known_sites["missing:seeds"] = {"at_ms": 0, "quantity": 8}
	bads.append(bad)
	bad = base.duplicate(true)
	bad.avian_life.exchanges["invented"] = {"from": "avian", "to": "home", "source": "bird:moss_sparrow", "target": "garden", "item": "herb", "amount": 1}
	bads.append(bad)
	for candidate: Dictionary in bads:
		var before: String = _canonical(coarse)
		runner.assert_true(not coarse.restore(candidate), "bad geometry, load, phase, knowledge, source or unproven transfer is rejected")
		runner.assert_eq(_canonical(coarse), before, "failed joint load cannot partly replace a living world")
	var lost: RegionalSimulation = _make(runner)
	lost.advance_to_ms(100)
	var stopped: Array = lost.avian_life.birds.moss_sparrow.position.duplicate()
	lost.embodiment.release_control(SimAvianLife.subject_id("moss_sparrow"), SimAvianLife.carrier_id("moss_sparrow"), "motion")
	lost.advance_to_ms(200)
	runner.assert_true(lost.avian_life.birds.moss_sparrow.active.is_empty(), "lost body control interrupts flight")
	runner.assert_eq(lost.avian_life.birds.moss_sparrow.position, stopped, "revoking motion prevents displacement in the following time interval")
	runner.assert_true(lost.restore(JSON.parse_string(JSON.stringify(lost.to_dict()))), "settled control loss persists without granting it back")
