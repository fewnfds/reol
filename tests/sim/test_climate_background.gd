extends RefCounted
## Original bodies and herb sources consume the same archived outdoor climate.

const Fixtures = preload("res://tests/sim/test_regional_simulation.gd")
const CLIMATE_PATH: String = "res://data/definitions/climate.json"
const WEATHER_PATH: String = "res://data/definitions/weather.json"
const OPENING_MS: int = 12345
const FIRST_SAMPLE_MS: int = 120000
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
	var live: RegionalSimulation = _world(runner, disk)
	if source == null or live == null:
		return
	runner.assert_eq(source.elapsed_ms, OPENING_MS, "villages and regional world begin at the declared fractional-minute instant")
	runner.assert_eq(source.weather.epoch_ms, OPENING_MS, "weather epoch is created from that actual opening instant")
	runner.assert_true(source._content != live._content, "the saved and live worlds own different content versions")
	runner.assert_true(source.environment.local_conditions("player").temperature_tenths != live.environment.local_conditions("player").temperature_tenths, "different content changes an actual body's outdoor projection")
	_assert_herb_sample(runner, source, "home", OPENING_MS)
	_assert_herb_sample(runner, source, "river", OPENING_MS)
	_assert_weather_transition(runner, source)
	runner.assert_true(source.advance_to_ms(FIRST_SAMPLE_MS), "shared time reaches the first complete climate sample")
	if source.elapsed_ms != FIRST_SAMPLE_MS:
		return
	if not live.advance_to_ms(FIRST_SAMPLE_MS):
		runner.assert_true(false, "independent disk-content world reaches the same instant")
		return
	runner.assert_eq(live.elapsed_ms, FIRST_SAMPLE_MS, "both live worlds reach the same actual instant")
	var before_queries: String = _state(source)
	for at_ms: int in [OPENING_MS, OPENING_MS + 59999, OPENING_MS + 60000, FIRST_SAMPLE_MS]:
		_assert_projection(runner, source, "home", "player", at_ms)
		_assert_projection(runner, source, "river", "river_player", at_ms)
	_assert_herb_sample(runner, source, "home", FIRST_SAMPLE_MS)
	_assert_herb_sample(runner, source, "river", FIRST_SAMPLE_MS)
	_assert_human_sample(runner, source, "home", "player", FIRST_SAMPLE_MS)
	_assert_human_sample(runner, source, "river", "river_player", FIRST_SAMPLE_MS)
	runner.assert_eq(_state(source), before_queries, "historical and current observation queries do not alter the world")
	_restore_and_continue(runner, source, live, saved_bundle)
	print("SCENARIO climate background: real regional bodies and herbs, non-minute weather epoch, historical projections and independent archived-content continuation")


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


func _assert_weather_transition(runner: Object, world: RegionalSimulation) -> void:
	var rules: Dictionary = world.weather.definitions
	var epoch: int = world.weather.epoch_ms
	for region: String in ["home", "river"]:
		var first: String = "clear" if region == "home" else "rain"
		var second: String = "rain" if region == "home" else "clear"
		runner.assert_eq(SimWeather.kind_at(rules, region, epoch, epoch + 59999), first, "region retains its actual weather immediately before the boundary: " + region)
		runner.assert_eq(SimWeather.kind_at(rules, region, epoch, epoch + 60000), second, "region changes weather exactly at its fractional-epoch boundary: " + region)


func _assert_projection(runner: Object, world: RegionalSimulation, region: String, actor: String, at_ms: int) -> void:
	var sim: VillageSimulation = world.regions[region]
	var body_cell: Vector2i = SimRouteTravel.cell(sim.actors[actor].cell)
	var herb_cell: Vector2i = SimRouteTravel.cell(sim.places.garden.cell)
	var climate: Dictionary = world._content.climate
	var weather: Dictionary = world.weather.definitions
	var epoch: int = world.weather.epoch_ms
	var kind: String = SimWeather.kind_at(weather, region, epoch, at_ms)
	var expected: int = SimClimateRules.temperature_at(climate, region, at_ms, kind)
	runner.assert_eq(SimClimateRules.region_at(climate, body_cell), region, "the actual body occupies the intended climate region: " + actor)
	runner.assert_eq(SimClimateRules.region_at(climate, herb_cell), region, "the actual herb source occupies the same climate region: " + region)
	var body: Dictionary = world.environment.local_conditions(actor, at_ms)
	var herb: Dictionary = RegionalSimulation.herb_conditions_for(world._content, world.weather.to_dict(), herb_cell, at_ms)
	if body.is_empty() or herb.is_empty():
		runner.assert_true(false, "actual recipients have valid climate projections: " + region)
		return
	runner.assert_eq(str(body.region), region, "human projection uses physical geography: " + actor)
	runner.assert_eq(int(body.heat_tenths), 0, "no local heat is introduced into the outdoor comparison")
	runner.assert_eq(int(body.temperature_tenths), expected, "human projection uses the independent weather and climate oracle at %d: %s" % [at_ms, actor])
	runner.assert_eq(int(herb.temperature_tenths), expected, "herb projection uses the same independent outdoor oracle at %d: %s" % [at_ms, region])
	runner.assert_eq(bool(herb.rain), kind == "rain", "herb projection uses the historical weather phase: " + region)
	runner.assert_eq(int(herb.heat_tenths), 0, "herb background adds no imaginary local heat")


func _assert_herb_sample(runner: Object, world: RegionalSimulation, region: String, at_ms: int) -> void:
	var sim: VillageSimulation = world.regions[region]
	var ecology: Dictionary = sim.land_resources.sources.herb_slope.ecology
	runner.assert_true(not ecology.is_empty(), "actual managed herb source exists: " + region)
	if ecology.is_empty():
		return
	var cell: Vector2i = SimRouteTravel.cell(sim.places.garden.cell)
	var kind: String = SimWeather.kind_at(world.weather.definitions, region, world.weather.epoch_ms, at_ms)
	var expected: int = SimClimateRules.temperature_at(world._content.climate, region, at_ms, kind)
	runner.assert_eq(int(ecology.sample_ms), at_ms, "herb holds the genuine sample time: " + region)
	runner.assert_eq(int(ecology.temperature_tenths), expected, "actual herb state received the outdoor temperature: " + region)
	runner.assert_eq(bool(ecology.rain), kind == "rain", "actual herb state received the corresponding weather: " + region)
	runner.assert_eq(int(ecology.heat_tenths), 0, "actual herb state has no local heat in this scenario")
	runner.assert_eq(SimClimateRules.region_at(world._content.climate, cell), region, "sample belongs to the original garden's geography: " + region)


func _assert_human_sample(runner: Object, world: RegionalSimulation, region: String, actor: String, at_ms: int) -> void:
	var sample: Dictionary = world.environment.samples.get(actor, {})
	runner.assert_true(not sample.is_empty(), "environment sampled the original body: " + actor)
	if sample.is_empty():
		return
	var kind: String = SimWeather.kind_at(world.weather.definitions, region, world.weather.epoch_ms, at_ms)
	var expected: int = SimClimateRules.temperature_at(world._content.climate, region, at_ms, kind)
	runner.assert_eq(int(sample.at_ms), at_ms, "human sample retains the real shared time: " + actor)
	runner.assert_eq(str(sample.region), region, "human sample retains its physical climate region: " + actor)
	runner.assert_eq(int(sample.temperature_tenths), expected, "actual human sample uses the original outdoor temperature: " + actor)
	runner.assert_eq(int(sample.heat_tenths), 0, "human sample contains no invented local heat")


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
	_assert_projection(runner, restored, "home", "player", OPENING_MS + 59999)
	_assert_projection(runner, restored, "river", "river_player", OPENING_MS + 60000)
	_assert_herb_sample(runner, restored, "home", FIRST_SAMPLE_MS)
	_assert_herb_sample(runner, restored, "river", FIRST_SAMPLE_MS)
	_assert_human_sample(runner, restored, "home", "player", FIRST_SAMPLE_MS)
	_assert_human_sample(runner, restored, "river", "river_player", FIRST_SAMPLE_MS)
	runner.assert_eq(_state(restored), source_before, "restored historical projections do not change saved facts")
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
		_assert_herb_sample(runner, restored, "home", 240000)
		_assert_herb_sample(runner, restored, "river", 240000)
		runner.assert_true(restored.environment.local_conditions("player").temperature_tenths != live.environment.local_conditions("player").temperature_tenths, "continued restored body still uses its saved rules instead of the other live world")
		runner.assert_eq(_state(live), live_before, "continuing the restored world does not advance the other live world")


func _state(world: RegionalSimulation) -> String:
	return _json(world.to_dict())


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
