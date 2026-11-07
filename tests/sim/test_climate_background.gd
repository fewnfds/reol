extends RefCounted
## Original bodies and herb sources sample one inertial outdoor climate field.

const Fixtures = preload("res://tests/sim/test_regional_simulation.gd")
const CLIMATE_PATH: String = "res://data/definitions/climate.json"
const WEATHER_PATH: String = "res://data/definitions/weather.json"
const OPENING_MS: int = 12345
const FIRST_SAMPLE_MS: int = 120000
# Fixed by the current ordinary-world field contract, not read from the object
# being tested. The fixture makes each quantized climate boundary explicit.
const EXPECTED_TAU_MS: int = 30000
const CLIMATE_STEP_MS: int = 6000
const CLIMATE_RAMP_END_MS: int = 120000
var _fixtures := Fixtures.new()


class FlatMap extends WorldMapData:
	func terrain_is_walkable(cell: Vector2i) -> bool:
		return in_bounds(cell)

	func get_elevation(cell: Vector2i) -> int:
		return 0 if in_bounds(cell) else -1

	func independent_copy() -> WorldMapData:
		return FlatMap.new()


func run(runner: Object) -> void:
	var disk := ReolContentDB.new()
	if not disk.load_all():
		runner.assert_true(false, "ordinary definitions load for the climate fixture")
		return
	var documents: Dictionary = disk.content_bundle().documents.duplicate(true)
	var climate: Dictionary = documents[CLIMATE_PATH]
	climate.regions.home.bounds = [0, 0, 125, 512]
	climate.regions.river.bounds = [125, 0, 387, 512]
	climate.regions.home.base_tenths = 80
	climate.regions.river.base_tenths = 360
	climate.regions.home.weather_offsets.rain = -80
	climate.regions.river.weather_offsets.rain = -35
	# At the 08:00 calendar opening, the target increases by one tenth every
	# six seconds until 08:02, then stays constant through the test horizon.
	# The independent oracle below knows these boundaries without calling the
	# production response owner or its boundary/target compiler.
	for region: String in ["home", "river"]:
		climate.regions[region].seasonal_curve = [[0, 0], [360, 0]]
		climate.regions[region].daily_curve = [[0, 0], [480, 0], [482, 20], [485, 20], [1440, 0]]
	var weather: Dictionary = documents[WEATHER_PATH]
	weather.phases = [
		{"kind": "clear", "duration_ms": 60000},
		{"kind": "rain", "duration_ms": 60000},
		{"kind": "clear", "duration_ms": 60000},
	]
	weather.regions.home.offset_ms = 0
	weather.regions.river.offset_ms = 60000
	var saved_bundle: Dictionary = ReolContentBundle.from_documents(documents)
	var archived := ReolContentDB.new()
	var valid: bool = archived.load_bundle(saved_bundle)
	runner.assert_true(valid, "independent edited climate and weather form a valid saved content bundle")
	if not valid:
		return
	runner.assert_true(str(saved_bundle.digest) != str(disk.content_bundle().digest), "saved climate and weather differ from disk content")
	var source: RegionalSimulation = _world(runner, archived)
	var sliced: RegionalSimulation = _world(runner, archived)
	var live: RegionalSimulation = _world(runner, disk)
	if source == null or sliced == null or live == null:
		return
	runner.assert_eq(source.elapsed_ms, OPENING_MS, "villages and regional world begin at the declared fractional-minute instant")
	runner.assert_eq(source.weather.epoch_ms, OPENING_MS, "weather epoch is created from that actual opening instant")
	runner.assert_true(source._content != live._content, "the saved and live worlds own different content versions")
	runner.assert_true(source.environment.local_conditions("player").temperature_tenths != live.environment.local_conditions("player").temperature_tenths, "different content changes an actual body's outdoor projection")
	_assert_herb_sample(runner, source, "home", OPENING_MS)
	_assert_herb_sample(runner, source, "river", OPENING_MS)
	_assert_weather_transition(runner, source)
	_assert_projection(runner, sliced, "home", "player", OPENING_MS)
	_assert_projection(runner, sliced, "river", "river_player", OPENING_MS)
	for at_ms: int in [OPENING_MS + 59999, OPENING_MS + 60000, FIRST_SAMPLE_MS]:
		if not sliced.advance_to_ms(at_ms):
			runner.assert_true(false, "sliced world reaches the actual climate observation instant %d" % at_ms)
			return
		_assert_projection(runner, sliced, "home", "player", at_ms)
		_assert_projection(runner, sliced, "river", "river_player", at_ms)
	runner.assert_true(source.advance_to_ms(FIRST_SAMPLE_MS), "shared time reaches the first complete climate sample")
	if source.elapsed_ms != FIRST_SAMPLE_MS:
		return
	if not live.advance_to_ms(FIRST_SAMPLE_MS):
		runner.assert_true(false, "independent disk-content world reaches the same instant")
		return
	runner.assert_eq(live.elapsed_ms, FIRST_SAMPLE_MS, "both live worlds reach the same actual instant")
	var before_queries: String = _state(source)
	runner.assert_eq(_state(sliced), before_queries, "one continuous advance and sliced advances retain the same world state")
	_assert_projection(runner, source, "home", "player", FIRST_SAMPLE_MS)
	_assert_projection(runner, source, "river", "river_player", FIRST_SAMPLE_MS)
	for at_ms: int in [OPENING_MS, OPENING_MS + 59999, OPENING_MS + 60000, FIRST_SAMPLE_MS]:
		_assert_climate_oracle(runner, source, "home", at_ms)
		_assert_climate_oracle(runner, source, "river", at_ms)
	_assert_herb_sample(runner, source, "home", FIRST_SAMPLE_MS)
	_assert_herb_sample(runner, source, "river", FIRST_SAMPLE_MS)
	_assert_human_sample(runner, source, "home", "player", FIRST_SAMPLE_MS)
	_assert_human_sample(runner, source, "river", "river_player", FIRST_SAMPLE_MS)
	_assert_history_unavailable(runner, source, "player", OPENING_MS)
	_assert_history_unavailable(runner, source, "river_player", OPENING_MS + 60000)
	runner.assert_eq(_state(source), before_queries, "current, historical and pure climate queries do not alter the world")
	_restore_and_continue(runner, source, live, saved_bundle)
	print("SCENARIO climate background: independent inertial oracle, non-minute weather epoch, segmented time and archived-content continuation")


func _world(runner: Object, content: ReolContentDB) -> RegionalSimulation:
	var instances: Dictionary = {}
	for region: String in ["home", "river"]:
		# Reuse the normal fixture's actual config, places and bodies, but create
		# the real opening at OPENING_MS; no running clock or past is rewritten.
		var template: VillageSimulation = _fixtures._make_village(content, region, false)
		if template == null:
			runner.assert_true(false, "climate fixture builds its original village: " + region)
			return null
		var cells: Dictionary = {}
		for id: String in template.actors:
			cells[id] = template.actors[id].cell.duplicate()
		var sim := VillageSimulation.new()
		if not sim.initialize(content, template.config, cells, template.places, OPENING_MS):
			runner.assert_true(false, "fractional-time village initializes: " + region)
			return null
		sim.set_navigation(Callable(_fixtures, "_path"))
		instances[region] = sim
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/world_continuity.json"))
	var world := RegionalSimulation.new()
	if not world.initialize(settings, instances, content) or not world.configure_services(content.settlement_services):
		runner.assert_true(false, "fractional opening assembles original weather, environment and plants: " + str(world.errors))
		return null
	world.services.set_navigation(Callable(_fixtures, "_path"))
	world.set_active_region("")
	var terrain := FlatMap.new()
	if not terrain.configure_nature(content.natural_environment):
		runner.assert_true(false, "fixture map binds the same independent content")
		return null
	world.bind_map_data(terrain)
	return world


# These fixture-specific expectations deliberately do not query any field,
# response, target compiler, or boundary calculator from the implementation.
# Their horizon is 08:00 through 08:04, before the next daily-curve segment.
@warning_ignore("integer_division")
func _oracle_weather(region: String, at_ms: int) -> String:
	var offset: int = 0 if region == "home" else 60000
	var phase: int = ((at_ms - OPENING_MS + offset) / 60000) % 3
	return "rain" if phase == 1 else "clear"


@warning_ignore("integer_division")
func _oracle_background_tenths(region: String, at_ms: int) -> int:
	var base: int = 80 if region == "home" else 360
	var rain_offset: int = -80 if region == "home" else -35
	var daily: int = mini(at_ms / CLIMATE_STEP_MS, 20)
	return base + daily + (rain_offset if _oracle_weather(region, at_ms) == "rain" else 0)


@warning_ignore("integer_division")
func _oracle_actual_tenths(region: String, at_ms: int) -> int:
	# Solve dy/dt = (target-y)/tau exactly between every known step in this
	# fixture. Target jumps at climate steps or fractional-epoch weather phases;
	# actual y is continuous there. Values here are in tenths of a degree.
	var actual: float = float(_oracle_background_tenths(region, OPENING_MS))
	var cursor: int = OPENING_MS
	while cursor < at_ms:
		var climate_boundary: int = at_ms
		if cursor < CLIMATE_RAMP_END_MS:
			climate_boundary = mini(at_ms, (cursor / CLIMATE_STEP_MS + 1) * CLIMATE_STEP_MS)
		var weather_boundary: int = OPENING_MS + ((cursor - OPENING_MS) / 60000 + 1) * 60000
		var end: int = mini(at_ms, mini(climate_boundary, weather_boundary))
		var target: float = float(_oracle_background_tenths(region, cursor))
		actual = target + (actual - target) * exp(-float(end - cursor) / float(EXPECTED_TAU_MS))
		cursor = end
	return roundi(actual)


func _assert_climate_oracle(runner: Object, world: RegionalSimulation, region: String, at_ms: int) -> void:
	var kind: String = _oracle_weather(region, at_ms)
	var background: int = _oracle_background_tenths(region, at_ms)
	runner.assert_eq(SimWeather.kind_at(world.weather.definitions, region, world.weather.epoch_ms, at_ms), kind, "weather oracle uses archived region and epoch at %d: %s" % [at_ms, region])
	runner.assert_eq(SimClimateRules.temperature_at(world._content.climate, region, at_ms, kind), background, "instantaneous climate oracle includes its quantized curve and weather at %d: %s" % [at_ms, region])
	var herb_cell: Vector2i = SimRouteTravel.cell(world.regions[region].places.garden.cell)
	var pure: Dictionary = RegionalSimulation.herb_conditions_for(world._content, world.weather.to_dict(), herb_cell, at_ms)
	if pure.is_empty():
		runner.assert_true(false, "pure climate target is available for the herb: " + region)
		return
	runner.assert_eq(int(pure.temperature_tenths), background, "pure herb target remains the instantaneous climate oracle: " + region)
	runner.assert_eq(bool(pure.rain), kind == "rain", "pure herb projection retains its requested weather time: " + region)


func _assert_weather_transition(runner: Object, world: RegionalSimulation) -> void:
	for region: String in ["home", "river"]:
		for at_ms: int in [OPENING_MS, 17999, 18000, OPENING_MS + 59999, OPENING_MS + 60000, FIRST_SAMPLE_MS, 240000]:
			_assert_climate_oracle(runner, world, region, at_ms)
		var before: int = OPENING_MS + 59999
		var after: int = OPENING_MS + 60000
		runner.assert_true(_oracle_weather(region, before) != _oracle_weather(region, after), "fixture has a real weather phase change: " + region)
		runner.assert_true(_oracle_background_tenths(region, after) != _oracle_background_tenths(region, before), "weather changes the instantaneous target: " + region)
		runner.assert_eq(_oracle_actual_tenths(region, after), _oracle_actual_tenths(region, before), "actual temperature is continuous at the weather transition: " + region)
		runner.assert_true(_oracle_actual_tenths(region, after) != _oracle_background_tenths(region, after), "actual temperature does not jump to its new target: " + region)


func _assert_history_unavailable(runner: Object, world: RegionalSimulation, actor: String, at_ms: int) -> void:
	var historical: Dictionary = world.environment.local_conditions(actor, at_ms)
	runner.assert_true(not bool(historical.get("heat_supported", true)), "past physical observation is explicitly unsupported: " + actor)
	runner.assert_eq(str(historical.get("heat_reason", "")), "history_unavailable", "past observation reports the history boundary: " + actor)
	runner.assert_true(not historical.has("temperature_tenths") and not historical.has("burden_rate"), "past observation never invents a temperature or burden: " + actor)


func _assert_projection(runner: Object, world: RegionalSimulation, region: String, actor: String, at_ms: int) -> void:
	# local_conditions uses the current local offset. Do not ask it to reconstruct
	# an earlier physical field from the current world's later response anchor.
	runner.assert_eq(world.elapsed_ms, at_ms, "physical observation uses the world's actual shared time")
	if world.elapsed_ms != at_ms:
		return
	var sim: VillageSimulation = world.regions[region]
	var body_cell: Vector2i = SimRouteTravel.cell(sim.actors[actor].cell)
	var herb_cell: Vector2i = SimRouteTravel.cell(sim.places.garden.cell)
	var climate: Dictionary = world._content.climate
	var expected: int = _oracle_actual_tenths(region, at_ms)
	var background: int = _oracle_background_tenths(region, at_ms)
	var kind: String = _oracle_weather(region, at_ms)
	runner.assert_eq(SimClimateRules.region_at(climate, body_cell), region, "the actual body occupies the intended climate region: " + actor)
	runner.assert_eq(SimClimateRules.region_at(climate, herb_cell), region, "the actual herb source occupies the same climate region: " + region)
	_assert_climate_oracle(runner, world, region, at_ms)
	var body_field: Dictionary = world.local_heat.actual_at(body_cell, at_ms)
	var herb_field: Dictionary = world.local_heat.actual_at(herb_cell, at_ms)
	var herb_offset: Dictionary = world.local_heat.project_tenths(herb_cell, at_ms)
	if not bool(body_field.get("ok", false)) or not bool(herb_field.get("ok", false)) or not bool(herb_offset.get("supported", false)):
		runner.assert_true(false, "current field is available to actual recipients: " + region)
		return
	runner.assert_eq(roundi(float(body_field.value_c) * 10.0), expected, "body field follows independent inertial oracle at %d: %s" % [at_ms, actor])
	runner.assert_eq(roundi(float(herb_field.value_c) * 10.0), expected, "herb field follows independent inertial oracle at %d: %s" % [at_ms, region])
	runner.assert_eq(int(herb_offset.value), expected - background, "herb field offset is actual minus instantaneous climate: " + region)
	var body: Dictionary = world.environment.local_conditions(actor, at_ms)
	var herb: Dictionary = RegionalSimulation.herb_conditions_for(world._content, world.weather.to_dict(), herb_cell, at_ms, int(herb_offset.value))
	if body.is_empty() or herb.is_empty():
		runner.assert_true(false, "actual recipients have valid current projections: " + region)
		return
	runner.assert_eq(str(body.region), region, "human projection uses physical geography: " + actor)
	runner.assert_eq(int(body.heat_tenths), expected - background, "human offset is actual minus instantaneous climate: " + actor)
	runner.assert_eq(int(body.temperature_tenths), expected, "human projection reads the independent actual temperature: " + actor)
	runner.assert_eq(int(herb.temperature_tenths), expected, "herb projection reads the same independent actual temperature: " + region)
	runner.assert_eq(bool(herb.rain), kind == "rain", "herb projection uses the current weather phase: " + region)
	runner.assert_eq(int(herb.heat_tenths), expected - background, "herb offset preserves the actual response lag: " + region)


func _assert_herb_sample(runner: Object, world: RegionalSimulation, region: String, at_ms: int) -> void:
	var sim: VillageSimulation = world.regions[region]
	var ecology: Dictionary = sim.land_resources.sources.herb_slope.ecology
	runner.assert_true(not ecology.is_empty(), "actual managed herb source exists: " + region)
	if ecology.is_empty():
		return
	var cell: Vector2i = SimRouteTravel.cell(sim.places.garden.cell)
	var kind: String = _oracle_weather(region, at_ms)
	var expected: int = _oracle_actual_tenths(region, at_ms)
	var background: int = _oracle_background_tenths(region, at_ms)
	runner.assert_eq(int(ecology.sample_ms), at_ms, "herb holds the genuine sample time: " + region)
	runner.assert_eq(int(ecology.temperature_tenths), expected, "actual herb state received the independently calculated field: " + region)
	runner.assert_eq(bool(ecology.rain), kind == "rain", "actual herb state received the corresponding weather: " + region)
	runner.assert_eq(int(ecology.heat_tenths), expected - background, "herb sample stores actual minus instantaneous background: " + region)
	runner.assert_eq(SimClimateRules.region_at(world._content.climate, cell), region, "sample belongs to the original garden's geography: " + region)


func _assert_human_sample(runner: Object, world: RegionalSimulation, region: String, actor: String, at_ms: int) -> void:
	var sample: Dictionary = world.environment.samples.get(actor, {})
	runner.assert_true(not sample.is_empty(), "environment sampled the original body: " + actor)
	if sample.is_empty():
		return
	var expected: int = _oracle_actual_tenths(region, at_ms)
	var background: int = _oracle_background_tenths(region, at_ms)
	runner.assert_eq(int(sample.at_ms), at_ms, "human sample retains the real shared time: " + actor)
	runner.assert_eq(str(sample.region), region, "human sample retains its physical climate region: " + actor)
	runner.assert_eq(int(sample.temperature_tenths), expected, "actual human sample uses the independently calculated field: " + actor)
	runner.assert_eq(int(sample.heat_tenths), expected - background, "human sample stores actual minus instantaneous background: " + actor)


func _restore_and_continue(runner: Object, source: RegionalSimulation, live: RegionalSimulation, bundle: Dictionary) -> void:
	var saved: Dictionary = JSON.parse_string(_state(source))
	var saved_json: String = _json(saved)
	var source_before: String = _state(source)
	var live_before: String = _state(live)
	var content := ReolContentDB.new()
	if not content.load_bundle(bundle):
		runner.assert_true(false, "restore candidate loads the archived content rather than disk")
		return
	var map := FlatMap.new()
	if not map.configure_nature(content.natural_environment):
		runner.assert_true(false, "restore candidate owns its own map definitions")
		return
	var assembly: Dictionary = ReolWorldAssemblyInputs.from_world(source, {"home": [100, 100], "river": [150, 100]})
	var restored: RegionalSimulation = WorldRestoreFactory.restore(content, saved, assembly, map)
	runner.assert_true(restored != null, "actual saved world restores as an independent candidate using archived definitions")
	runner.assert_eq(_json(saved), saved_json, "candidate construction does not rewrite the saved world")
	runner.assert_eq(_state(source), source_before, "candidate construction does not alter the source world")
	runner.assert_eq(_state(live), live_before, "candidate construction does not contaminate the different live world")
	if restored == null:
		return
	runner.assert_true(restored._content != source._content and restored.map_data != source.map_data, "candidate has independent content and terrain owners")
	runner.assert_eq(str(restored._content.content_bundle().digest), str(bundle.digest), "restored candidate keeps the saved bundle")
	runner.assert_eq(restored.weather.epoch_ms, OPENING_MS, "restored candidate keeps the actual fractional weather epoch")
	runner.assert_eq(_state(restored), source_before, "candidate preserves the complete original world state")
	_assert_projection(runner, restored, "home", "player", FIRST_SAMPLE_MS)
	_assert_projection(runner, restored, "river", "river_player", FIRST_SAMPLE_MS)
	_assert_climate_oracle(runner, restored, "home", OPENING_MS + 59999)
	_assert_climate_oracle(runner, restored, "river", OPENING_MS + 60000)
	_assert_herb_sample(runner, restored, "home", FIRST_SAMPLE_MS)
	_assert_herb_sample(runner, restored, "river", FIRST_SAMPLE_MS)
	_assert_human_sample(runner, restored, "home", "player", FIRST_SAMPLE_MS)
	_assert_human_sample(runner, restored, "river", "river_player", FIRST_SAMPLE_MS)
	_assert_history_unavailable(runner, restored, "player", OPENING_MS + 59999)
	_assert_history_unavailable(runner, restored, "river_player", OPENING_MS + 60000)
	runner.assert_eq(_state(restored), source_before, "restored current and unavailable past queries do not change saved facts")
	runner.assert_eq(_state(live), live_before, "restored observations never alter the differently configured live world")
	# Navigation is an unsaved adapter; restoring it must not issue any new work.
	for sim: VillageSimulation in restored.regions.values():
		sim.set_navigation(Callable(_fixtures, "_path"))
	if restored.services != null:
		restored.services.set_navigation(Callable(_fixtures, "_path"))
	var advanced_source: bool = source.advance_to_ms(240000)
	var advanced_restored: bool = restored.advance_to_ms(240000)
	runner.assert_true(advanced_source and advanced_restored, "original and restored worlds continue their shared time")
	if advanced_source and advanced_restored:
		runner.assert_eq(_state(restored), _state(source), "restored climate, weather, people and herbs continue identically")
		_assert_projection(runner, restored, "home", "player", 240000)
		_assert_projection(runner, restored, "river", "river_player", 240000)
		_assert_herb_sample(runner, restored, "home", 240000)
		_assert_herb_sample(runner, restored, "river", 240000)
		_assert_human_sample(runner, restored, "home", "player", 240000)
		_assert_human_sample(runner, restored, "river", "river_player", 240000)
		runner.assert_true(restored.environment.local_conditions("player").temperature_tenths != live.environment.local_conditions("player").temperature_tenths, "continued restored body still uses its saved rules instead of the other live world")
		runner.assert_eq(_state(live), live_before, "continuing the restored world does not advance the other live world")


func _state(world: RegionalSimulation) -> String:
	return _json(world.to_dict())


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
