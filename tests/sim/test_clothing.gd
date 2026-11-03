extends RefCounted

const Fixtures = preload("res://tests/sim/test_settlement_services.gd")
var fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_physical_clothes(runner)
	_exposure(runner)
	_roof(runner)
	_autonomy_and_future(runner)
	_bad_candidates(runner)
	print("SCENARIO clothing: unique physical garments, timed changes, original needs/weather/roofs, NPC rain preparation, surface knowledge and joint continuation")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = fixtures._make_world(runner)
	runner.assert_true(world.clothing.spawn_opening(), "finite opening clothes spawn only on a new world")
	return world


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _finish(world: RegionalSimulation) -> void:
	world.advance_to_ms(world.clothing.next_boundary_ms())


func _take(world: RegionalSimulation, runner: Object, id: String) -> void:
	fixtures._position(world, "home", "dorm")
	runner.assert_true(world.clothing.begin("player", "take", id).ok, "one nearby owned garment can be taken")
	_finish(world)


func _physical_clothes(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var domain: SimClothing = world.clothing
	var count: int = domain.objects.size()
	runner.assert_true(not domain.spawn_opening(), "reopening a wardrobe does not replenish objects")
	fixtures._position(world, "river", "dorm")
	runner.assert_true(not domain.begin("player", "take", "clothing:spare:0").ok, "knowledge of stored clothes does not allow remote taking")
	fixtures._position(world, "home", "dorm")
	runner.assert_true(not domain.begin("player", "take", "clothing:robe:lao_zhou").ok, "nearby authority cannot take another person's worn garment")
	runner.assert_true(domain.begin("player", "take", "clothing:spare:0").ok, "taking starts an actual timed body action")
	runner.assert_true(not world.regions.home.submit_action("player", "rest"), "native body cannot concurrently rest while handling clothes")
	runner.assert_true(not world.services.begin("player", "home", "eat").ok, "institutional action cannot also own the dressing body")
	world.advance_to_ms(1000)
	runner.assert_eq(domain.objects["clothing:spare:0"].container, "dorm", "garment stays in its original place during unfinished taking")
	domain.cancel("player")
	runner.assert_eq(domain.objects["clothing:spare:0"].container, "dorm", "cancel does not teleport the garment")
	_take(world, runner, "clothing:spare:0")
	runner.assert_true(domain.held("player", "clothing:spare:0"), "finished taking moves the one physical instance into the original bag reference")
	runner.assert_true(not domain.begin("player", "wear", "clothing:spare:0").ok, "same body layer requires first removing its old garment")
	runner.assert_true(domain.begin("player", "remove", "clothing:robe:player").ok, "original robe uses the same removal rules")
	_finish(world)
	runner.assert_true(domain.begin("player", "wear", "clothing:spare:0").ok, "the released body layer accepts the alternate robe")
	_finish(world)
	runner.assert_eq(domain.appearance("player").body.color, "#345b79", "the visible body color comes from the actual worn instance")
	var rank: String = str(world.regions.home.actors.player.rank_id)
	runner.assert_eq(world.regions.home.institutions.balance("sect", "player"), 0, "changing appearance grants no institutional credit")
	runner.assert_eq(str(world.regions.home.actors.player.rank_id), rank, "appearance grants no appointment")
	runner.assert_true(not domain.begin("player", "place", "clothing:spare:0", "dorm").ok, "a worn garment cannot be stored while still worn")
	runner.assert_true(domain.begin("player", "place", "clothing:robe:player", "dorm").ok, "removed original robe can be left in the nearby real place")
	_finish(world)
	runner.assert_eq(domain.objects.size(), count, "handling and wearing never duplicate a garment")
	var restored: RegionalSimulation = _world(runner)
	runner.assert_true(restored.restore(JSON.parse_string(_canonical(world))), "cancel and complete history replay to exactly the same physical clothes")
	_take(world, runner, "clothing:spare:1")
	runner.assert_true(domain.begin("player", "wear", "clothing:spare:1").ok, "independent outer layer can cover the robe")
	_finish(world)
	world.regions.home.set_actor_cell("lao_zhou", SimRouteTravel.cell(world.regions.home.actors.player.cell))
	var seen: String = domain.seen_clothing("lao_zhou", "player")
	runner.assert_true(seen.contains("草编") and not seen.contains("靛青"), "outer cover exposes only surface cues, not hidden inner garment details")
	fixtures._position(world, "river", "dorm")
	runner.assert_true(domain.seen_clothing("lao_zhou", "player").contains("视线"), "distant observers cannot inspect current clothes")


func _exposure(runner: Object) -> void:
	var exposed: RegionalSimulation = _world(runner)
	var protected: RegionalSimulation = _world(runner)
	_take(protected, runner, "clothing:spare:1")
	runner.assert_true(protected.clothing.begin("player", "wear", "clothing:spare:1").ok, "real rain protection starts by dressing")
	_finish(protected)
	var carried: RegionalSimulation = _world(runner)
	_take(carried, runner, "clothing:spare:1")
	for world: RegionalSimulation in [exposed, protected, carried]:
		world.advance_to_ms(1440000)
	runner.assert_eq(exposed.clothing.objects["clothing:robe:player"].wet, 60, "four whole rainy pulses wet the actual exposed robe")
	runner.assert_eq(protected.clothing.objects["clothing:robe:player"].wet, 0, "actually worn outer cape shields the inner robe")
	runner.assert_eq(carried.clothing.objects["clothing:robe:player"].wet, 60, "a cape in the bag provides no shelter")
	var person: Dictionary = exposed.regions.home.actors.player
	var before: float = float(person.energy)
	exposed.advance_to_ms(1500000)
	var expected: float = float(exposed.regions.home.config.needs.energy_per_minute) + float(exposed.clothing.definitions.wet_energy_per_minute)
	runner.assert_true(absf(before - float(person.energy) - expected) < 0.00001, "wet clothes consume the original energy through its existing fixed point accumulator")
	runner.assert_true(exposed.clothing.begin("player", "remove", "clothing:robe:player").ok, "a wet garment can actually be removed")
	_finish(exposed)
	var wet: int = int(exposed.clothing.objects["clothing:robe:player"].wet)
	runner.assert_true(wet > 0 and exposed.clothing.energy_rate("player") == 0, "removal stops wet-body exposure without erasing the garment's wetness")
	exposed.advance_to_ms(1620000)
	runner.assert_true(int(exposed.clothing.objects["clothing:robe:player"].wet) < wet and int(exposed.clothing.objects["clothing:robe:player"].wet) > 0, "the removed garment gradually dries in the bag")
	runner.assert_true(protected.clothing.begin("player", "remove", "clothing:spare:1").ok, "rain cape can be removed midway through a rain minute")
	_finish(protected)
	protected.advance_to_ms(1500000)
	runner.assert_eq(protected.clothing.objects["clothing:robe:player"].wet, 0, "a newly exposed inner layer does not receive a whole minute of earlier rain")
	protected.advance_to_ms(1560000)
	runner.assert_eq(protected.clothing.objects["clothing:robe:player"].wet, 15, "the next fully exposed interval does receive rain")


func _roof(runner: Object) -> void:
	var builder: RefCounted = load("res://tests/sim/test_rooms_and_rest.gd").new()
	var world: RegionalSimulation = builder._world(runner)
	runner.assert_true(world.clothing.spawn_opening(), "construction world has the same finite clothing source")
	builder._build(runner, world, "wood_wall", Vector2i(111, 108))
	builder._build(runner, world, "wood_roof", Vector2i(110, 108))
	world.regions.home.set_actor_cell("player", Vector2i(110, 108))
	world.invalidate_region("home")
	world.advance_to_ms(1440000)
	runner.assert_eq(world.clothing.objects["clothing:robe:player"].wet, 0, "original real overhead construction shelters worn clothes from the same rain")
	runner.assert_true(world.clothing.region_roofed("home", Vector2i(110, 108)), "shelter reads physical roof geometry")


func _autonomy_and_future(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	sim.actors.lao_zhou.autonomous = true
	sim.actors.lao_zhou.energy = 80.0
	sim.actors.lao_zhou.retry_ms = 1200000
	world.invalidate_region("home")
	world.advance_to_ms(1200001)
	runner.assert_true(world.clothing.owns_actor("lao_zhou"), "an ordinary personal decision starts putting on the carried rain cape")
	var saved: String = _canonical(world)
	var fine: RegionalSimulation = _world(runner)
	runner.assert_true(fine.restore(JSON.parse_string(saved)), "rain dressing in progress validates against the original body and all other domains")
	world.set_active_region("river")
	fine.set_active_region("home")
	world.advance_to_ms(1560000)
	while fine.elapsed_ms < 1560000:
		fine.advance_to_ms(mini(1560000, fine.elapsed_ms + 991))
	var a: Dictionary = JSON.parse_string(_canonical(world))
	var b: Dictionary = JSON.parse_string(_canonical(fine))
	a.active_region = ""
	b.active_region = ""
	runner.assert_eq(JSON.stringify(a), JSON.stringify(b), "offscreen coarse and onscreen fine dressing/weather produce the identical complete future")
	runner.assert_true(world.clothing.objects["clothing:spare:2"].worn, "NPC finishes wearing his own one cape while the player is absent")
	world = _world(runner)
	sim = world.regions.home
	sim.actors.lao_zhou.autonomous = true
	sim.actors.lao_zhou.hunger = 10.0
	sim.actors.lao_zhou.retry_ms = 1200000
	world.invalidate_region("home")
	world.advance_to_ms(1200001)
	runner.assert_true(not world.clothing.owns_actor("lao_zhou") and sim.actors.lao_zhou.active.get("action") == "eat", "urgent original needs take priority over rain preparation")


func _bad_candidates(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	_take(world, runner, "clothing:spare:1")
	runner.assert_true(world.clothing.begin("player", "wear", "clothing:spare:1").ok, "candidate fixture has an actual unfinished change")
	world.advance_to_ms(world.elapsed_ms + 1)
	var stable: String = _canonical(world)
	for kind: String in ["location", "owner", "duplicate", "history", "wet", "time", "parallel", "shift", "position", "missing"]:
		var broken: Dictionary = JSON.parse_string(stable)
		match kind:
			"location": broken.clothing.objects["clothing:spare:1"].container = "records"
			"owner": broken.clothing.objects["clothing:spare:1"].owner = "shi_tou"
			"duplicate": broken.clothing.objects["clothing:extra"] = broken.clothing.objects["clothing:spare:1"].duplicate(true)
			"history": broken.clothing.events.clear()
			"wet": broken.clothing.objects["clothing:robe:player"].wet = 100
			"time": broken.clothing.active.player.due_ms += 1
			"parallel": broken.regions.home.actors.player.autonomous = true
			"shift": broken.clothing.active.player.at[0] += 1
			"position": broken.clothing.active.player.position[0] += 0.25
			"missing": broken.erase("clothing")
		runner.assert_true(not world.restore(broken), "joint candidate rejects clothes corruption: " + kind)
		runner.assert_eq(_canonical(world), stable, "rejected clothing candidate leaves the whole live world intact: " + kind)
