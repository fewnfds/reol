extends RefCounted
## Boundary-only regional fixture: real source/weather/heat rules without
## executing centuries of populated villages, routes or autonomous actions.


class QuietVillage extends VillageSimulation:
	func advance_to_ms(at_ms: int, _max_events: int = 4096) -> bool:
		if at_ms < elapsed_ms:
			return false
		land_resources.advance_to_ms(at_ms)
		elapsed_ms = at_ms
		return true


	func next_boundary_ms() -> int:
		return land_resources.next_boundary_ms()


func run(runner: Object) -> void:
	_first_qualified_sample(runner)
	_saturated_initial_intervals(runner)
	_established_final_sample(runner)
	print("SCENARIO herb limits: lightweight real regional sampling, no fabricated saturated minute, held rain cache, exact final source JSON and preserved qualified final sample")


func _fixture(runner: Object, at_ms: int, alternating: bool = false) -> RegionalSimulation:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "limit fixture loads original ecosystem definitions")
		return null
	for climate: Dictionary in content.climate.regions.values():
		climate.base_tenths = 200
		climate.weather_offsets.rain = 0
		for curve: String in ["seasonal_curve", "daily_curve"]:
			for point: Array in climate[curve]:
				point[1] = 0
	content.weather.phases = [{"kind": "clear", "duration_ms": 60000}, {"kind": "rain", "duration_ms": 60000}] if alternating else [{"kind": "rain", "duration_ms": 60000}]
	var world := RegionalSimulation.new()
	world._content = content
	world.elapsed_ms = at_ms
	world.target_ms = at_ms
	var sim := QuietVillage.new()
	sim.elapsed_ms = at_ms
	sim.config = {"resource_sources": {"herb_slope": {"definition": "wild_herbs", "place": "garden"}}, "actions": {}}
	sim.places = {"garden": {"cell": [10, 10]}}
	sim.land_resources = SimLandResources.new()
	if not sim.land_resources.initialize(sim, content.land_resources):
		runner.assert_true(false, "limit fixture creates a single real finite herb source")
		return null
	world.regions = {"home": sim}
	world.weather = SimWeather.new()
	world.environment_fields = SimLocalHeat.new()
	if not world.weather.initialize(world, content.weather) or not world.environment_fields.initialize(world, content.local_heat):
		runner.assert_true(false, "limit fixture binds the original independent weather and heat authorities")
		return null
	if not world._sample_herb_conditions(true):
		runner.assert_true(false, "limit fixture records actual conditions exactly at source activation")
		return null
	return world


func _advance(runner: Object, world: RegionalSimulation, at_ms: int, heat_sample: bool = false) -> void:
	# The same source-old-law then heat then parent-sample ordering used by the
	# real scheduler; this fixture intentionally has no people or other jobs.
	runner.assert_true(world.regions.home.advance_to_ms(at_ms), "limit source settles its old cache to the requested actual time")
	world.elapsed_ms = at_ms
	world.target_ms = at_ms
	runner.assert_true(world.environment_fields.settle_at_ms(at_ms), "limit heat settles at the same actual regional time")
	if heat_sample:
		runner.assert_true(world.environment_fields.mark_sample(at_ms), "a real global minute can sample the original heat field")
	runner.assert_true(world._sample_herb_conditions(), "parent sampling accepts valid time or skips a non-minute sentinel")


func _source(world: RegionalSimulation) -> Dictionary:
	return world.regions.home.land_resources.sources.herb_slope


func _canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _json_source_restore(runner: Object, world: RegionalSimulation) -> void:
	var sim: VillageSimulation = world.regions.home
	var original: String = _canonical(sim.land_resources.to_dict())
	for full_precision: bool in [false, true]:
		var decoded: Dictionary = JSON.parse_string(JSON.stringify(sim.land_resources.to_dict(), "", true, full_precision))
		runner.assert_true(SimLandResources.valid_state(decoded, sim.config, sim.places, sim.inventory, sim.elapsed_ms, world._content.land_resources), "near-limit saved source validates after actual JSON decoding")
		sim.land_resources.bind_restored(sim, world._content.land_resources, decoded)
		runner.assert_eq(_canonical(sim.land_resources.to_dict()), original, "near-limit JSON restores normalize the exact integer source and cached conditions")
		runner.assert_true(_source(world).next_growth_ms is int and _source(world).ecology.sample_ms is int, "final source sentinel and sample time remain actual integers after restore")
	runner.assert_true(world._valid_herb_conditions(), "restored source still agrees with real held weather and heat history")


func _first_qualified_sample(runner: Object) -> void:
	var world: RegionalSimulation = _fixture(runner, 1234, true)
	if world == null:
		return
	var source: Dictionary = _source(world)
	runner.assert_eq(source.ecology.sample_ms, 1234, "fractional activation stores only the actual initial cache")
	runner.assert_eq(world._next_herb_sample_ms(), 120000, "first parent sample needs a full minute before its aligned boundary")
	_advance(runner, world, 60000, true)
	runner.assert_eq(source.ecology.sample_ms, 1234, "the first partial global minute does not fabricate a completed source sample")
	runner.assert_true(world._valid_herb_conditions(), "an activation cache may survive a newer independent heat minute")
	_advance(runner, world, 120000, true)
	runner.assert_eq(source.ecology.sample_ms, 120000, "the first qualified source boundary records the actual new future cache")
	runner.assert_true(source.ecology.rain, "the source reads actual rain at its qualified sample instead of its earlier clear cache")
	runner.assert_eq(source.ecology.rain_input, 0, "newly sampled rain cannot backfill the previous clear interval")
	_advance(runner, world, 121234)
	runner.assert_eq(source.ecology.rain_input, 1234 * int(world._content.land_resources.types.wild_herbs.ecology.rain_per_ms), "held sampled rain credits only its actual 1234 future milliseconds")
	_json_source_restore(runner, world)


func _saturated_initial_intervals(runner: Object) -> void:
	for offset: int in [30000, 60000]:
		var activation: int = SimInventory.MAX_COUNT - offset
		var world: RegionalSimulation = _fixture(runner, activation)
		if world == null:
			return
		var source: Dictionary = _source(world)
		runner.assert_eq(world._next_herb_sample_ms(), SimInventory.MAX_COUNT, "a source near maximum time saturates its scheduling sentinel safely")
		var latest: int = SimInventory.MAX_COUNT - posmod(SimInventory.MAX_COUNT, 60000)
		if latest > activation:
			_advance(runner, world, latest, true)
			runner.assert_eq(source.ecology.sample_ms, activation, "an insufficient final aligned minute preserves the actual activation cache")
		_advance(runner, world, SimInventory.MAX_COUNT)
		runner.assert_eq(source.ecology.sample_ms, activation, "the final non-lattice maximum cannot become a fabricated source sample")
		runner.assert_eq(source.ecology.last_ms, SimInventory.MAX_COUNT, "the unsampled final interval still integrates all real elapsed soil time")
		runner.assert_eq(source.ecology.rain_input, offset * int(world._content.land_resources.types.wild_herbs.ecology.rain_per_ms), "actual held rain is neither skipped nor backfilled near time maximum")
		runner.assert_true(world._valid_herb_conditions(), "parent validation recognizes an unsampled final activation interval")
		_json_source_restore(runner, world)


func _established_final_sample(runner: Object) -> void:
	var latest: int = SimInventory.MAX_COUNT - posmod(SimInventory.MAX_COUNT, 60000)
	var world: RegionalSimulation = _fixture(runner, latest - 60000)
	if world == null:
		return
	_advance(runner, world, latest, true)
	var source: Dictionary = _source(world)
	runner.assert_eq(source.ecology.sample_ms, latest, "the last globally aligned full minute is a real established sample")
	var initial_rain: int = int(source.ecology.rain_input)
	_advance(runner, world, SimInventory.MAX_COUNT)
	runner.assert_eq(source.ecology.sample_ms, latest, "a final partial minute retains the established actual sampled conditions")
	runner.assert_true(int(source.ecology.rain_input) > initial_rain, "the established cache still accounts for real last-interval atmospheric water")
	runner.assert_true(world._valid_herb_conditions(), "a completed final sample remains valid at the supported maximum")
	_json_source_restore(runner, world)
