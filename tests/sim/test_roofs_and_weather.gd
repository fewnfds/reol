extends RefCounted

const Fixtures = preload("res://tests/sim/test_rooms_and_rest.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_test_weather_phase_and_water(runner)
	_test_roof_material_layer_support(runner)
	_test_exposure_rest_and_restore(runner)
	print("SCENARIO roofs/weather: real upper-layer labor/support/collapse, local rain, finite source accounting, damp original bed recovery and independent candidates")


func _world(runner: Object) -> RegionalSimulation:
	return _fixtures._world(runner)


func _canonical(world: RegionalSimulation) -> String:
	return _fixtures._canonical(world)


func _test_weather_phase_and_water(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var rule: Dictionary = world.weather.definitions
	runner.assert_eq(world.weather.current_kind("home"), "clear", "climate begins at a defined shared-time origin")
	runner.assert_eq(SimWeather.kind_at(rule, "home", 0, 1200000), "rain", "local phase changes exactly at the content boundary")
	runner.assert_eq(SimWeather.kind_at(rule, "river", 0, 1000000), "rain", "regions can experience different weather on the same time axis")
	runner.assert_eq(SimWeather.kind_at(rule, "home", 0, 1000000), "clear", "remote rainfall does not rewrite local weather")
	# Check the O(phases) rain bound against explicit pulse sampling, including
	# non-minute migration epochs and several complete climate cycles.
	for epoch: int in [0, 444100, 2998843]:
		for region: String in ["home", "river"]:
			var direct: int = 0
			var previous: int = epoch
			for index: int in 210:
				var pulse: int = previous - posmod(previous, 60000) + 60000
				if SimWeather.kind_at(rule, region, epoch, previous) == "rain":
					direct += int(rule.rain_source_per_pulse)
				runner.assert_eq(SimWeather.rain_budget({"epoch_ms": epoch}, rule, region, pulse), direct, "rain budget matches exact pulse history at epoch %d/%s/%d" % [epoch, region, index])
				previous = pulse
	var sim: VillageSimulation = world.regions.home
	var stored: int = sim.inventory.quantity("well", "water")
	world.advance_to_ms(1560000)
	runner.assert_eq(sim.inventory.quantity("well", "water"), stored, "rain never teleports water into the hauled well-side container")
	runner.assert_eq(sim.land_resources.sources.spring.rainfall, 6, "six rainy pulses enter the actual finite spring source")
	runner.assert_eq(sim.inventory.quantity("resource:spring", "water"), 30, "rain and scheduled growth remain distinct source quantities")
	world.advance_to_ms(4500000)
	world.to_dict()
	runner.assert_true(sim.inventory.quantity("resource:spring", "water") <= 36, "a full spring cannot bank unlimited rain")
	var restored: RegionalSimulation = _world(runner)
	runner.assert_true(restored.restore(JSON.parse_string(_canonical(world))), "rain sources restore with explicit inflow and the original inventory balance")
	var broken: Dictionary = JSON.parse_string(_canonical(world))
	broken.regions.home.land_resources.sources.woodlot.rainfall = 1
	broken.regions.home.inventory.containers["resource:woodlot"].wood += 1
	runner.assert_true(not restored.restore(broken), "rain cannot authorize wood appearing in an unrelated natural source")


func _test_roof_material_layer_support(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._bed_world(runner)
	var world: RegionalSimulation = fixture.world
	var construction: SimConstruction = world.construction
	var cell := Vector2i(110, 108)
	var roof: String = _fixtures._fixtures._place(runner, world, "wood_roof", cell)
	runner.assert_eq(construction.project_at(cell), fixture.bed, "upper blueprint does not replace the actual ground bed")
	runner.assert_eq(construction.project_at(cell, "roof"), roof, "roof and ground have independent occupancy indexes")
	runner.assert_true(not construction.roofed(cell), "an overhead blueprint is not actual shelter")
	runner.assert_true(construction.begin("player", roof).ok, "roof uses the same material and body work process")
	_fixtures._fixtures._finish(runner, world)
	runner.assert_eq(construction.projects[roof].state, "blueprint", "labor without physical support cannot become a floating roof")
	runner.assert_true(world.regions.home.inventory.quantity(roof, "wood") == 4 and int(construction.projects[roof].work_ms) == 180000, "failed support retains the real brought wood and finished labor")
	# The failed roof job left its real lumber on the west stand (109,108).
	# Build support on the clear east side instead of trying to bury that batch.
	var support: String = _fixtures._build(runner, world, "wood_wall", Vector2i(111, 108))
	runner.assert_true(construction.begin("player", roof).ok, "adding real support allows the existing work to resume")
	_fixtures._fixtures._finish(runner, world)
	runner.assert_true(construction.roofed(cell) and construction.is_bed(fixture.bed) and not construction.blocked(cell), "supported roof covers the actual bed without becoming a ground obstacle")
	runner.assert_eq(world.regions.home.inventory.quantity(roof, "wood"), 0, "overhead material is consumed exactly once")
	var state: Dictionary = JSON.parse_string(_canonical(world))
	var restored: RegionalSimulation = _world(runner)
	runner.assert_true(restored.restore(state), "same-cell bed and supported roof survive a complete independent world candidate")
	runner.assert_true(construction.begin("player", support, "demolish").ok, "physical support can be dismantled through the original work")
	_fixtures._fixtures._finish(runner, world)
	runner.assert_eq(construction.projects[roof].state, "removed", "removing the last nearby support collapses the roof rather than preserving imaginary cover")
	runner.assert_true(not construction.roofed(cell) and construction.is_bed(fixture.bed), "roof collapse leaves the original bed and ground route intact")
	runner.assert_eq(world.regions.home.inventory.quantity(roof, "wood"), 2, "collapsed roof leaves finite original salvage")
	runner.assert_true(restored.restore(JSON.parse_string(_canonical(world))), "collapse receipts and source materials remain a valid save")
	var wrong: Dictionary = state.duplicate(true)
	wrong.construction.projects[support].type = "wood_bed"
	runner.assert_true(not restored.restore(wrong), "a fabricated roof support cannot pass material/type and occupancy checks")


func _test_exposure_rest_and_restore(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._bed_world(runner)
	var world: RegionalSimulation = fixture.world
	var bed: String = fixture.bed
	var covered: String = _fixtures._build(runner, world, "wood_bed", Vector2i(112, 108))
	_fixtures._build(runner, world, "wood_wall", Vector2i(113, 108))
	var roof: String = _fixtures._build(runner, world, "wood_roof", Vector2i(112, 108))
	world.advance_to_ms(1440000)
	runner.assert_true(world.weather.bed_is_wet(bed) and world.weather.bed_wetness(covered) == 0, "same local rain wets an exposed bed while the actual overhead roof shelters another")
	var sim: VillageSimulation = world.regions.home
	sim.set_actor_cell("player", Vector2i(110, 108))
	sim.set_actor_cell("lao_zhou", Vector2i(112, 108))
	sim.actors.player.energy = 20.0
	sim.actors.lao_zhou.energy = 20.0
	world.invalidate_region("home")
	runner.assert_true(world.resting.begin("player", bed).ok and world.resting.begin("lao_zhou", covered).ok, "two distinct bodies rest on two real independently reserved beds")
	world.advance_to_ms(world.elapsed_ms + 1)
	var at: int = world.elapsed_ms
	var copied: Dictionary = JSON.parse_string(_canonical(world))
	var fine: RegionalSimulation = _world(runner)
	runner.assert_true(fine.restore(copied), "rain, wetness, roofs and ongoing original needs restore together")
	world.set_active_region("river")
	fine.set_active_region("home")
	world.advance_to_ms(at + 180000)
	while fine.elapsed_ms < at + 180000:
		fine.advance_to_ms(mini(at + 180000, fine.elapsed_ms + 991))
	var sparse_state: Dictionary = JSON.parse_string(_canonical(world))
	var fine_state: Dictionary = JSON.parse_string(_canonical(fine))
	sparse_state.active_region = ""
	fine_state.active_region = ""
	runner.assert_eq(JSON.stringify(sparse_state), JSON.stringify(fine_state), "coarse absent and fine nearby exposure/needs/water yield the identical complete future")
	runner.assert_true(float(sim.actors.lao_zhou.energy) > float(sim.actors.player.energy) + 2.9, "wet bedding actually slows original energy recovery without a second resource panel")
	world.resting.cancel("player")
	world.resting.cancel("lao_zhou")
	var stable: String = _canonical(world)
	for kind: String in ["time", "phantom_bed", "inflow", "double_roof", "missing_weather"]:
		var broken: Dictionary = JSON.parse_string(stable)
		match kind:
			"time": broken.weather.last_pulse_ms -= 1
			"phantom_bed": broken.weather.damp_beds["construction:999"] = 20
			"inflow": broken.regions.home.land_resources.sources.spring.rainfall += 100
			"double_roof": broken.construction.projects[covered].type = "wood_roof"
			"missing_weather": broken.erase("weather")
		runner.assert_true(not world.restore(broken), "bad environment candidate rejected: " + kind)
		runner.assert_eq(_canonical(world), stable, "bad environment leaves original living world untouched: " + kind)
	runner.assert_true(world.construction.begin("player", roof, "demolish").ok, "remove overhead cover without removing its ground bed")
	_fixtures._fixtures._finish(runner, world)
	world.advance_to_ms(1800000)
	runner.assert_true(world.weather.bed_wetness(covered) > 0 and world.construction.is_bed(covered), "removing a roof exposes the existing bed to subsequent rain")
	world.advance_to_ms(3300000)
	runner.assert_eq(world.weather.bed_wetness(bed), 0, "later dry weather removes accumulated dampness gradually")
