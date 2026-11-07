extends RefCounted
## Independent authored openings, original shared clock and finite device stocks.

const ClimateFixture = preload("res://tests/sim/test_climate_background.gd")
const Devices = preload("res://tests/sim/test_thermal_devices.gd")
const CLIMATE_PATH: String = "res://data/definitions/climate.json"
const PROFILE_PATH: String = "res://data/scenarios/world_geography.json"
const OPENING_PATH: String = "res://data/scenarios/artifacts.json"
const SAMPLE_MS: int = 120000
const EXPECTED_KNOT_MS: int = 240000
const FUTURE_MS: int = 300000
var _fixture := ClimateFixture.new()
var _devices := Devices.new()


func run(runner: Object) -> void:
	var disk := ReolContentDB.new()
	if not disk.load_all():
		runner.assert_true(false, "geographic world fixture loads the complete original content bundle")
		return
	# Author both climate regions on the original complete bundle before either
	# world exists. This is only to put both fixture villages in distinct regions.
	var documents: Dictionary = disk.content_bundle().documents.duplicate(true)
	documents[CLIMATE_PATH].regions.home.bounds = [0, 0, 125, 512]
	documents[CLIMATE_PATH].regions.river.bounds = [125, 0, 387, 512]
	var input_bundle: Dictionary = ReolContentBundle.from_documents(documents)
	var profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not profile is Dictionary:
		runner.assert_true(false, "geographic fixture reads a complete opening profile")
		return
	var cold_profile: Dictionary = _profile(profile, 80000, -100)
	var hot_profile: Dictionary = _profile(profile, 0, 100)
	var original_input: String = _json(input_bundle)
	var original_cold: String = _json(cold_profile)
	var cold_content: ReolContentDB = ReolGeographicContent.build(input_bundle, cold_profile)
	var hot_content: ReolContentDB = ReolGeographicContent.build(input_bundle, hot_profile)
	runner.assert_true(cold_content != null and hot_content != null, "cold and hot profiles each compile an independent complete content bundle")
	runner.assert_eq(_json(input_bundle), original_input, "compiling geography does not change the input content bundle")
	runner.assert_eq(_json(cold_profile), original_cold, "compiling geography does not change the authored profile")
	if cold_content == null or hot_content == null:
		return
	runner.assert_true(str(cold_content.content_bundle().digest) != str(hot_content.content_bundle().digest), "different geographic profiles bind different actual content digests")
	runner.assert_true(cold_content.climate.regions.home.daily_curve != disk.climate.regions.home.daily_curve, "the cold world binds its compiled curve instead of the old disk curve")
	runner.assert_true(hot_content.climate.regions.home.daily_curve != disk.climate.regions.home.daily_curve, "the hot world binds its compiled curve instead of the old disk curve")
	var cold: RegionalSimulation = _fixture._world(runner, cold_content)
	var hot: RegionalSimulation = _fixture._world(runner, hot_content)
	if cold == null or hot == null:
		return
	var cold_at_opening: Dictionary = cold.environment.local_conditions("player")
	var hot_at_opening: Dictionary = hot.environment.local_conditions("player")
	if cold_at_opening.is_empty() or hot_at_opening.is_empty():
		runner.assert_true(false, "both profiles reach the original player's local environment")
		return
	runner.assert_true(int(cold_at_opening.temperature_tenths) < int(hot_at_opening.temperature_tenths), "polar and equatorial openings produce genuinely different local body temperatures")
	runner.assert_true(int(cold_at_opening.temperature_tenths) < int(cold_content.climate.human.comfort_min_tenths) - int(cold_content.climate.human.max_insulation_tenths), "the cold opening is below the body's maximum insulated comfort")
	runner.assert_true(int(hot_at_opening.temperature_tenths) > int(hot_content.climate.human.comfort_max_tenths), "the hot opening is above the body's declared comfort")
	runner.assert_true(int(cold_at_opening.burden_rate) > 0 and int(hot_at_opening.burden_rate) > 0, "the original environmental exposure responds in each extreme")
	_assert_opening_herbs(runner, cold, "cold")
	_assert_opening_herbs(runner, hot, "hot")
	if not hot.advance_to_ms(SAMPLE_MS):
		runner.assert_true(false, "the hot world reaches an actual shared minute sample")
		return
	_assert_sample(runner, hot, "hot")
	var hot_facts: String = _state(hot)
	_run_devices_and_restore(runner, cold)
	runner.assert_eq(_state(hot), hot_facts, "operating and restoring the cold world cannot change the independent hot world")
	print("SCENARIO geographic world: compiled extreme climates affect actual bodies and plants; real opposing thermal devices retain their own stocks across a generated curve boundary and independent JSON continuation")


func _profile(source: Dictionary, latitude_mdeg: int, offset_tenths: int) -> Dictionary:
	var profile: Dictionary = source.duplicate(true)
	profile.solar.latitude_mdeg = latitude_mdeg
	# At -46 degrees longitude, the authored daily minimum is civil 08:04,
	# 240000 ms after this world's 08:00 civil epoch.
	profile.solar.longitude_mdeg = -46000
	profile.solar.meridian_mdeg = 0
	for region: Dictionary in profile.regions.values():
		region.continentality_milli = 1000
		region.temperature_offset_tenths = offset_tenths
	return profile


func _assert_opening_herbs(runner: Object, world: RegionalSimulation, label: String) -> void:
	for region: String in ["home", "river"]:
		var sim: VillageSimulation = world.regions[region]
		var sample: Dictionary = sim.land_resources.sources.herb_slope.ecology
		if sample.is_empty():
			runner.assert_true(false, label + " profile has an actual opening herb source in " + region)
			continue
		var at_ms: int = int(sample.sample_ms)
		var cell: Vector2i = SimRouteTravel.cell(sim.places.garden.cell)
		var background: Dictionary = SimClimateRules.background_at(world._content.climate, world.weather.definitions, world.weather.epoch_ms, cell, at_ms)
		runner.assert_eq(at_ms, world.elapsed_ms, label + " herb initial sample is at the actual opening time")
		runner.assert_eq(str(background.region), region, label + " herb uses its actual geographic region")
		runner.assert_eq(int(sample.temperature_tenths), int(background.temperature_tenths), label + " herb receives the generated background at opening")
		runner.assert_eq(int(sample.heat_tenths), 0, label + " opening herb does not invent a thermal source")


func _assert_sample(runner: Object, world: RegionalSimulation, label: String) -> void:
	var actor: Dictionary = world.environment.samples.get("player", {})
	var herb: Dictionary = world.regions.home.land_resources.sources.herb_slope.ecology
	if actor.is_empty() or herb.is_empty():
		runner.assert_true(false, label + " world produced both original body and herb samples")
		return
	var kind: String = SimWeather.kind_at(world.weather.definitions, "home", world.weather.epoch_ms, SAMPLE_MS)
	var expected: int = SimClimateRules.temperature_at(world._content.climate, "home", SAMPLE_MS, kind)
	runner.assert_eq(int(actor.at_ms), SAMPLE_MS, label + " body's exposure is sampled at the common minute boundary")
	runner.assert_eq(str(actor.region), "home", label + " body's sample uses its actual region")
	runner.assert_eq(int(actor.temperature_tenths), expected, label + " body's saved exposure reads the compiled climate")
	runner.assert_true(int(actor.energy_rate) > 0, label + " actual body sample has a nonzero exposure consequence")
	runner.assert_eq(int(herb.sample_ms), SAMPLE_MS, label + " actual herb is sampled at the same shared minute")
	runner.assert_eq(int(herb.temperature_tenths), expected, label + " herb sample reads the same compiled outdoor climate")
	runner.assert_eq(int(herb.heat_tenths), 0, label + " preactivation herb has no fabricated local heat")


func _run_devices_and_restore(runner: Object, world: RegionalSimulation) -> void:
	var opening: Variant = JSON.parse_string(FileAccess.get_file_as_string(OPENING_PATH))
	if not opening is Dictionary or not world.artifacts.spawn_opening(opening):
		runner.assert_true(false, "geographic world issues the original declared heat devices once")
		return
	var cell: Vector2i = world.artifacts.object_cell("fire_stone")
	world.regions.home.set_actor_cell("player", cell)
	world.regions.home.set_actor_cell("chen_shouzhuo", cell)
	world.invalidate_region("home")
	if not _devices._enable_pair(runner, world):
		return
	_assert_sample(runner, world, "cold")
	var activated: int = world.elapsed_ms
	var fire_start: int = int(world.artifacts.objects.fire_stone.stored_q)
	var cold_start: int = int(world.artifacts.objects.cold_stone.stored_q)
	var fire_rules: Dictionary = world.artifacts.definitions.types.fire_stone.thermal
	var cold_rules: Dictionary = world.artifacts.definitions.types.cold_stone.thermal
	var fire_rate: int = int(fire_rules.rate_q_per_ms)
	var cold_rate: int = int(cold_rules.rate_q_per_ms)
	if not world.advance_to_ms(activated + 173):
		runner.assert_true(false, "the genuine source and sink reach a fractional instant")
		return
	var fire_checkpoint: int = int(world.artifacts.objects.fire_stone.stored_q)
	var cold_checkpoint: int = int(world.artifacts.objects.cold_stone.stored_q)
	runner.assert_true(fire_checkpoint < fire_start and cold_checkpoint > cold_start, "the real fire and cold devices both change their original finite stocks")
	runner.assert_eq(fire_checkpoint, fire_start - mini(fire_start, 173 * fire_rate), "the fire stone spends only its actual 173 ms of stock")
	runner.assert_eq(cold_checkpoint, cold_start + mini(int(cold_rules.capacity_q) - cold_start, 173 * cold_rate), "the cold stone gains only its actual 173 ms of stock")
	var climate: Dictionary = world._content.climate
	var generated_knot: bool = false
	for point: Array in climate.regions.home.daily_curve:
		generated_knot = generated_knot or int(point[0]) == 484
	runner.assert_true(generated_knot, "the actual compiled daily curve contains its authored 08:04 minimum")
	var boundary: int = SimClimateRules.next_background_boundary_ms(climate, world.weather.definitions, world.weather.epoch_ms, "home", world.elapsed_ms)
	runner.assert_true(boundary > world.elapsed_ms and boundary <= EXPECTED_KNOT_MS, "a generated physical climate boundary lies ahead before or at the 08:04 knot")
	if boundary <= world.elapsed_ms or boundary >= FUTURE_MS:
		return
	var archive: Dictionary = JSON.parse_string(_state(world))
	var before: String = _state(world)
	var content := ReolContentDB.new()
	if not content.load_bundle(world._content.content_bundle()):
		runner.assert_true(false, "independent candidate loads the archived generated content bundle")
		return
	var map := ClimateFixture.FlatMap.new()
	if not map.configure_nature(content.natural_environment):
		runner.assert_true(false, "independent candidate map accepts archived nature definitions")
		return
	var assembly: Dictionary = ReolWorldAssemblyInputs.from_world(world, {"home": [100, 100], "river": [150, 100]})
	var candidate: RegionalSimulation = WorldRestoreFactory.restore(content, archive, assembly, map)
	runner.assert_true(candidate != null, "original device activity and generated climate restore into an independent JSON candidate")
	runner.assert_eq(_state(world), before, "candidate staging leaves the original world unchanged")
	if candidate == null:
		return
	runner.assert_true(candidate._content != world._content and candidate.map_data != world.map_data and candidate.local_heat != world.local_heat, "restored content, terrain and heat have independent owners")
	runner.assert_eq(str(candidate._content.content_bundle().digest), str(world._content.content_bundle().digest), "candidate keeps the original generated content digest")
	runner.assert_eq(_state(candidate), before, "independent JSON restore preserves every world fact at the actual checkpoint")
	for sim: VillageSimulation in candidate.regions.values():
		sim.set_navigation(Callable(_fixture._fixtures, "_path"))
	if candidate.services != null:
		candidate.services.set_navigation(Callable(_fixture._fixtures, "_path"))
	if not world.advance_to_ms(FUTURE_MS):
		runner.assert_true(false, "original world advances across the generated climate boundary")
		return
	for target: int in [boundary - 1, boundary, boundary + 1, EXPECTED_KNOT_MS, FUTURE_MS]:
		if target <= candidate.elapsed_ms:
			continue
		if not candidate.advance_to_ms(target):
			runner.assert_true(false, "restored world crosses the generated boundary in explicit slices")
			return
	runner.assert_eq(_state(candidate), _state(world), "whole and independently restored sliced advancement produce the same complete future")
	var fire_future: int = int(world.artifacts.objects.fire_stone.stored_q)
	var cold_future: int = int(world.artifacts.objects.cold_stone.stored_q)
	var duration: int = FUTURE_MS - activated
	runner.assert_true(fire_future < fire_checkpoint and cold_future > cold_checkpoint, "both real devices continue across the geographic boundary")
	runner.assert_eq(fire_future, fire_start - mini(fire_start, duration * fire_rate), "the original fire stone spends its declared finite stock once")
	runner.assert_eq(cold_future, cold_start + mini(int(cold_rules.capacity_q) - cold_start, duration * cold_rate), "the original cold stone gains its declared finite stock once")
	runner.assert_eq(int(candidate.artifacts.objects.fire_stone.stored_q), fire_future, "sliced restoration keeps the same original fire stock")
	runner.assert_eq(int(candidate.artifacts.objects.cold_stone.stored_q), cold_future, "sliced restoration keeps the same original cold stock")


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _state(world: RegionalSimulation) -> String:
	return _json(world.to_dict())
