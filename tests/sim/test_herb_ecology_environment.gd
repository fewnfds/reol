extends RefCounted
## Same old bodies, weather and finite source; only the held environmental law
## differs. Presentation and queries cannot decide whether a plant lives.

const RegionFixture = preload("res://tests/sim/test_regional_simulation.gd")
var _fixtures: RefCounted = RegionFixture.new()


func run(runner: Object) -> void:
	_sampling(runner)
	_futures(runner)
	_rain_budget(runner)
	_real_use(runner)
	print("SCENARIO herb environment: geographic minute samples, cold/dry/rain recovery, near/far and bounded same future, exact held-rain budget and original private harvest/production")


func _world(runner: Object, temperature: int = 200, initial_water: int = 0) -> RegionalSimulation:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "herb environment reads ordinary definitions")
		return null
	content.land_resources.types.wild_herbs.ecology.initial_water = initial_water
	for region: Dictionary in content.climate.regions.values():
		region.base_tenths = temperature
		for curve: String in ["seasonal_curve", "daily_curve"]:
			for point: Array in region[curve]:
				point[1] = 0
		region.weather_offsets.rain = 0
	var villages: Dictionary = {}
	for id: String in ["home", "river"]:
		villages[id] = _fixtures._make_village(content, id, false)
	var world := RegionalSimulation.new()
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/world_continuity.json"))
	if not world.initialize(settings, villages, content):
		runner.assert_true(false, "herb environment binds original two villages: " + str(world.errors))
		return null
	world.set_active_region("")
	return world


func _state(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _sampling(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var sim: VillageSimulation = world.regions.home
	runner.assert_eq(sim.land_resources.sources.herb_slope.ecology.temperature_tenths, 200, "opening plant sample uses its real geographic climate")
	world.advance_to_ms(1199999)
	var soil: Dictionary = sim.land_resources.sources.herb_slope.ecology
	runner.assert_eq(soil.absorbed, 0, "dry clear weather never feeds growth")
	world.advance_to_ms(1200000)
	runner.assert_true(sim.land_resources.sources.herb_slope.ecology.rain, "the actual clear-to-rain minute samples the new future law")
	runner.assert_eq(sim.land_resources.sources.herb_slope.ecology.rain_input, 0, "new rain never credits its preceding interval")
	world.advance_to_ms(1800000)
	runner.assert_true(int(sim.land_resources.sources.herb_slope.ecology.rain_input) > 0, "real future rain enters finite soil")
	runner.assert_true(int(sim.land_resources.sources.herb_slope.ecology.absorbed) > 0, "sufficient actual rain resumes plant uptake")
	runner.assert_true(world._valid_herb_conditions(), "real climate and rain ledger pass independent joint bounds")
	var before: String = _state(world)
	for ignored: int in 20:
		sim.land_resources.ecology_observation("herb_slope")
	runner.assert_eq(_state(world), before, "repeated visual observations cannot advance plant truth")
	var cold: RegionalSimulation = _world(runner, 0, 36000000)
	if cold == null:
		return
	cold.advance_to_ms(2400000)
	var cold_soil: Dictionary = cold.regions.home.land_resources.sources.herb_slope.ecology
	runner.assert_eq(cold_soil.absorbed, 0, "water and real rainfall cannot bypass plant cold dormancy")
	runner.assert_true(int(cold_soil.rain_input) > 0, "dormant plants still receive original weather water")


func _futures(runner: Object) -> void:
	var coarse: RegionalSimulation = _world(runner)
	var fine: RegionalSimulation = _world(runner)
	var bounded: RegionalSimulation = _world(runner)
	if coarse == null or fine == null or bounded == null:
		return
	var stop: int = 3600123
	runner.assert_true(coarse.advance_to_ms(stop), "coarse absent ecology reaches a real future")
	fine.set_active_region("home")
	for at_ms: int in range(17003, stop, 17003):
		fine.advance_to_ms(at_ms)
		fine.regions.river.land_resources.ecology_observation("herb_slope")
	fine.advance_to_ms(stop)
	fine.set_active_region("")
	var complete: bool = false
	var attempts: int = 0
	while not complete and attempts < 10000:
		complete = bounded.advance_to_ms(stop, 1)
		attempts += 1
	runner.assert_true(complete, "retained budget debt completes without skipping soil samples")
	runner.assert_eq(_state(fine), _state(coarse), "presence and extra visual queries retain the complete same two-village future")
	runner.assert_eq(_state(bounded), _state(coarse), "budget yielding retains the complete same world future")


func _rain_budget(runner: Object) -> void:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/weather.json"))
	for activation: int in [0, 1, 59701, 797431]:
		for region: String in ["home", "river"]:
			var next: int = SimHerbEcologyRules.next_sample_ms({"sample_ms": activation, "activation_ms": activation}, {"sample_ms": 60000})
			var weather: Dictionary = {"epoch_ms": 123}
			for stop: int in [activation + 59000, activation + 121234, activation + 4500123]:
				var sampled: int = activation
				var cursor: int = activation
				var duration: int = 0
				var boundary: int = next
				while cursor < stop:
					var end: int = mini(stop, boundary)
					if SimWeather.kind_at(rules, region, int(weather.epoch_ms), sampled) == "rain":
						duration += end - cursor
					cursor = end
					if cursor == boundary:
						sampled = cursor
						boundary += 60000
				runner.assert_eq(RegionalSimulation._herb_rain_duration(rules, weather, region, activation, stop, next), duration, "bounded phase arithmetic equals actual held rain samples: %d/%s/%d" % [activation, region, stop])


func _real_use(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, 200, 36000000)
	if world == null:
		return
	var sim: VillageSimulation = world.regions.home
	runner.assert_true(sim.submit_action("player", "keep_herb"), "real private gathering starts against original ecological inventory")
	world.invalidate_region("home")
	var deadline: int = 1800000
	while not sim.actors.player.active.is_empty() and world.elapsed_ms < deadline:
		world.advance_to_ms(mini(deadline, sim.next_boundary_ms()))
	runner.assert_eq(sim.inventory.quantity("actor:player", "herb"), 2, "original travel and labor yield two actual private fresh herbs")
	runner.assert_eq(sim.land_resources.sources.herb_slope.extracted, 2, "same ecological source records the actual harvest")
	runner.assert_true(sim.submit_action("player", "keep_wood"), "private fuel still uses the original source and labor")
	world.invalidate_region("home")
	deadline = world.elapsed_ms + 1800000
	while not sim.actors.player.active.is_empty() and world.elapsed_ms < deadline:
		world.advance_to_ms(mini(deadline, sim.next_boundary_ms()))
	var opened: Dictionary = world.personal_production.create("player", "home", "dry_herbs")
	runner.assert_true(opened.ok, "ecological fresh herbs can enter the existing real drying process")
	if not opened.ok:
		return
	var id: String = str(opened.batch)
	runner.assert_true(world.personal_production.active.has("player"), "original private herbs and fuel are reserved for real work")
	deadline = world.elapsed_ms + 1800000
	while world.personal_production.active.has("player") and world.elapsed_ms < deadline:
		world.advance_to_ms(mini(deadline, world.elapsed_ms + 60000))
	runner.assert_eq(sim.inventory.quantity("actor:player", "herb"), 0, "fresh medicinal material is actually consumed by original production")
	runner.assert_eq(world.personal_production.batches[id].state, "ready", "real elapsed labor produces one finite ready batch")
	runner.assert_true(world.personal_production.begin("player", id, "collect").ok, "finished original batch needs physical pickup")
	deadline = world.elapsed_ms + 1800000
	while world.personal_production.active.has("player") and world.elapsed_ms < deadline:
		world.advance_to_ms(mini(deadline, world.elapsed_ms + 60000))
	runner.assert_eq(sim.inventory.quantity("actor:player", "dried_herb"), 2, "only collected original dried herbs enter the player's pocket")
