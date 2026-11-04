extends RefCounted
## Calendar exposure uses original bodies, garments and saved future rates.

const Fixtures = preload("res://tests/sim/test_regional_simulation.gd")
const ServicesFixture = preload("res://tests/sim/test_settlement_services.gd")
const HerbMigration = preload("res://tests/runtime/test_herb_ecology_migration.gd")
var fixtures := Fixtures.new()
var service_fixtures := ServicesFixture.new()


func run(runner: Object) -> void:
	_future_only(runner)
	_actual_clothes(runner)
	_wetness_and_region(runner)
	_npc_prepares(runner)
	_npc_cools(runner)
	_historical_clothes(runner)
	_joint_future(runner)
	_quiet_regions(runner)
	_bad_candidates(runner)
	_legacy_activation(runner)
	_partial_at_time_limit(runner)
	print("SCENARIO environment: shared calendar, geographical cold, actual dry/wet clothing, future-only original needs, ordinary NPC preparation, sparse/fine/bounded continuation and explicit legacy activation")


func _world(runner: Object, cold: bool = true, river_warm: bool = false, clothes: bool = true, temperature_tenths: int = 100, managed_herbs: bool = true) -> RegionalSimulation:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "environment fixture loads the ordinary content definitions")
		return null
	if cold:
		# Define a cold opening climate before constructing the world, never
		# rewrite elapsed time or completed real-world weather to stage winter.
		for region: String in content.climate.regions:
			var rules: Dictionary = content.climate.regions[region]
			rules.base_tenths = 140 if river_warm and region == "river" else temperature_tenths
			for curve: String in ["seasonal_curve", "daily_curve"]:
				for point: Array in rules[curve]:
					point[1] = 0
			rules.weather_offsets.rain = 0
	if not SimClimateRules.valid_definitions(content.climate):
		runner.assert_true(false, "the controlled cold opening still obeys the real climate definition contract")
		return null
	var instances: Dictionary = {}
	for region: String in ["home", "river"]:
		var sim: VillageSimulation = fixtures._make_village(content, region, false)
		if sim == null:
			runner.assert_true(false, "environment fixture creates original village bodies")
			return null
		instances[region] = sim
	if not managed_herbs:
		# These explicitly domain-only fixtures exercise neutral exposure
		# batching or the calendar's final partial minute, not plant sampling.
		# Construct fresh villages with the prior finite source law *before*
		# any time has elapsed. Never skip an enabled process in a live world.
		var prior_rules: Dictionary = content.land_resources.duplicate(true)
		prior_rules.types.wild_herbs.erase("ecology")
		content.land_resources = prior_rules
		for region: String in instances:
			var opening: VillageSimulation = instances[region]
			var village_settings: Dictionary = opening.config.duplicate(true)
			village_settings.actions.erase("irrigate_herb")
			var cells: Dictionary = {}
			for id: String in opening.actors:
				cells[id] = opening.actors[id].cell.duplicate()
			var isolated := VillageSimulation.new()
			if not isolated.initialize(content, village_settings, cells, opening.places):
				runner.assert_true(false, "environment-only dependencies initialize with explicit prior fixed-source rules")
				return null
			isolated.set_navigation(Callable(fixtures, "_path"))
			instances[region] = isolated
			runner.assert_true(isolated.land_resources.sources.herb_slope.ecology.is_empty() and not isolated.config.actions.has("irrigate_herb"), "domain-only dependency has no enabled plant process or impossible care verb: " + region)
	var world := RegionalSimulation.new()
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/world_continuity.json"))
	if not world.initialize(settings, instances, content):
		runner.assert_true(false, "environment attaches to the original regional authority")
		return null
	var services: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/settlement_services.json"))
	if not world.configure_services(services):
		runner.assert_true(false, "environment fixture retains the ordinary institutional and social interfaces")
		return null
	world.services.set_navigation(Callable(fixtures, "_path"))
	world.set_active_region("")
	if clothes and not world.clothing.spawn_opening():
		runner.assert_true(false, "environment fixture has the ordinary finite physical opening clothes")
		return null
	return world


func _state(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _comparison_state(world: RegionalSimulation) -> String:
	var data: Dictionary = JSON.parse_string(_state(world))
	data.active_region = ""
	return JSON.stringify(data, "", true, true)


func _energy(world: RegionalSimulation, actor: String = "player", region: String = "home") -> int:
	world.synchronize_region(region)
	return roundi(float(world.regions[region].actors[actor].energy) * VillageSimulation.NEED_SCALE)


func _take_cape(runner: Object, world: RegionalSimulation) -> bool:
	service_fixtures._position(world, "home", "dorm")
	var reply: Dictionary = world.clothing.begin("player", "take", "clothing:spare:1")
	runner.assert_true(reply.ok, "an owned cape is actually retrieved from the nearby original dorm")
	if not reply.ok:
		return false
	runner.assert_true(world.advance_to_ms(world.clothing.next_boundary_ms()), "actual retrieval spends the original handling time")
	return true


func _wear_cape(runner: Object, world: RegionalSimulation) -> bool:
	var reply: Dictionary = world.clothing.begin("player", "wear", "clothing:spare:1")
	runner.assert_true(reply.ok, "actual dressing starts on the original body")
	if not reply.ok:
		return false
	runner.assert_true(world.advance_to_ms(world.clothing.next_boundary_ms()), "actual dressing completes after its original shared duration")
	return true


func _future_only(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var original: int = _energy(world)
	var base_rate: int = roundi(float(world.regions.home.config.needs.energy_per_minute) * VillageSimulation.NEED_SCALE)
	runner.assert_eq(world.environment.activation_ms, 0, "a new opening enables environmental consequences at the same original world time")
	runner.assert_true(world.environment.samples.is_empty(), "an unsampled opening invents no previous exposure")
	runner.assert_eq(world.environment.next_boundary_ms(), 60000, "the first sample requires a whole minute after activation")
	world.advance_to_ms(59999)
	runner.assert_eq(world.environment.energy_rate("player"), 0, "a partial first minute is not charged as an earlier cold interval")
	world.advance_to_ms(60000)
	var first_rate: int = world.environment.energy_rate("player")
	runner.assert_true(first_rate > 0, "the real cold climate and actual robe produce a continuing exposure rate")
	runner.assert_eq(original - _energy(world), base_rate, "the newly sampled cold does not backfill the first minute's original needs")
	var before: int = _energy(world)
	world.advance_to_ms(120000)
	runner.assert_eq(before - _energy(world), base_rate + first_rate, "only the following minute spends the saved cold rate through the original fixed-point need accumulator")
	runner.assert_eq(world.environment.samples.player.at_ms, 120000, "environment samples follow the one shared minute lattice")
	runner.assert_true(world.environment.date_label().contains("春"), "the cold opening may still be spring: conditions rather than a season name cause discomfort")
	runner.assert_true(world.environment.local_conditions("player").feeling.contains("寒"), "the original body has a qualitative explanation for the actual cold burden")


func _actual_clothes(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var dry: int = world.environment.insulation_for("player")
	if not _take_cape(runner, world):
		return
	runner.assert_eq(world.environment.insulation_for("player"), dry, "a cape in the original bag supplies no worn insulation")
	world.advance_to_ms(120000)
	var old_rate: int = world.environment.energy_rate("player")
	runner.assert_true(old_rate > 0, "carrying the un-worn cape does not remove cold")
	var result: Dictionary = world.clothing.begin("player", "wear", "clothing:spare:1")
	runner.assert_true(result.ok, "a person may spend actual time adding the outer layer")
	if not result.ok:
		return
	world.advance_to_ms(122001)
	runner.assert_eq(world.environment.insulation_for("player"), dry, "unfinished dressing supplies no future garment effect")
	world.advance_to_ms(world.clothing.next_boundary_ms())
	runner.assert_true(world.environment.insulation_for("player") > dry, "the completed outer use insulates the same body without changing outdoor heat")
	runner.assert_eq(world.environment.local_conditions("player").temperature_tenths, 100, "dressing does not create physical heat or alter the climate")
	runner.assert_eq(world.environment.energy_rate("player"), old_rate, "a mid-minute clothing change does not rewrite the already sampled interval")
	runner.assert_eq(world.environment.local_conditions("player").burden_rate, 0, "current qualitative sense can already recognize adequate clothing before the next rate sample")
	world.advance_to_ms(180000)
	runner.assert_eq(world.environment.energy_rate("player"), 0, "the next sample applies the real completed outer garment to future needs")
	var before: int = _energy(world)
	world.advance_to_ms(240000)
	var base_rate: int = roundi(float(world.regions.home.config.needs.energy_per_minute) * VillageSimulation.NEED_SCALE)
	runner.assert_eq(before - _energy(world), base_rate, "a protected future minute spends only original ordinary needs, without an independent thermal resource")


func _wetness_and_region(runner: Object) -> void:
	var exposed: RegionalSimulation = _world(runner)
	var covered: RegionalSimulation = _world(runner)
	if exposed == null or covered == null:
		return
	var dry: int = exposed.environment.insulation_for("player")
	if not _take_cape(runner, covered) or not _wear_cape(runner, covered):
		return
	exposed.advance_to_ms(1440000)
	covered.advance_to_ms(1440000)
	runner.assert_true(int(exposed.clothing.objects["clothing:robe:player"].wet) > 0, "actual original rain wets the exposed physical robe")
	runner.assert_eq(covered.clothing.objects["clothing:robe:player"].wet, 0, "the worn original cape keeps the physical inner robe dry")
	runner.assert_true(exposed.environment.insulation_for("player") < dry, "actual wetness reduces the original cloth's warmth")
	runner.assert_true(exposed.environment.energy_rate("player") > covered.environment.energy_rate("player"), "the same cold rain produces different future burdens from actual worn clothing")
	runner.assert_true(exposed.clothing.energy_rate("player") > 0, "existing wet-body fatigue remains its original independent cause")
	var world: RegionalSimulation = _world(runner, true, true)
	if world == null:
		return
	world.advance_to_ms(61001)
	var rate: int = world.environment.energy_rate("player")
	runner.assert_eq(world.environment.samples.player.region, "home", "the saved cold sample identifies its actual geographical climate")
	world.regions.home.set_actor_cell("player", Vector2i(300, 100))
	world.invalidate_region("home")
	runner.assert_eq(world.environment.local_conditions("player").region, "river", "a body's current climate follows explicit geography rather than its home institution")
	runner.assert_eq(world.environment.local_conditions("player").temperature_tenths, 140, "the lowland climate supplies its own actual background")
	runner.assert_eq(world.environment.energy_rate("player"), rate, "a move between samples does not replace the preceding exposure history")
	var copied: RegionalSimulation = _world(runner, true, true)
	if copied == null:
		return
	runner.assert_true(copied.restore(JSON.parse_string(_state(world))), "a prior sample remains valid after its actual body has moved to another climate")
	world.advance_to_ms(120000)
	copied.advance_to_ms(120000)
	runner.assert_eq(world.environment.energy_rate("player"), 0, "the following geographical sample reflects the warmer lowland")
	runner.assert_eq(_state(copied), _state(world), "movement between exposure samples resumes to exactly the same original world")


func _npc_prepares(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var person: Dictionary = world.regions.home.actors.lao_zhou
	person.autonomous = true
	person.hunger = 85.0
	person.energy = 85.0
	person.retry_ms = 60000
	world.invalidate_region("home")
	world.advance_to_ms(60001)
	runner.assert_true(world.clothing.owns_actor("lao_zhou"), "an ordinary NPC can choose the already carried cape for cold, even while the weather is clear")
	if not world.clothing.owns_actor("lao_zhou"):
		return
	world.advance_to_ms(world.clothing.next_boundary_ms())
	runner.assert_true(world.clothing.objects["clothing:spare:2"].worn, "the autonomous decision finishes the original physical dressing process")
	world.advance_to_ms(120000)
	runner.assert_eq(world.environment.energy_rate("lao_zhou"), 0, "the NPC gains the same future insulation result as the player")


func _npc_cools(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, true, false, true, 330)
	if world == null:
		return
	var answer: Dictionary = world.clothing.begin("lao_zhou", "wear", "clothing:spare:2")
	runner.assert_true(answer.ok, "the hot-climate scenario starts with an actual timed use of the NPC's own carried outer layer")
	if not answer.ok:
		return
	world.advance_to_ms(world.clothing.next_boundary_ms())
	var person: Dictionary = world.regions.home.actors.lao_zhou
	person.autonomous = true
	person.hunger = 85.0
	person.energy = 85.0
	person.retry_ms = 60000
	world.invalidate_region("home")
	var attempts: int = 0
	while not world.advance_to_ms(60001, 1) and attempts < 2000:
		attempts += 1
	runner.assert_eq(world.elapsed_ms, 60001, "bounded scheduling eventually reaches the NPC's own hot-weather decision")
	runner.assert_eq(world.weather.current_kind("home"), "clear", "this decision is a clear hot-weather response, with no competing rain-cover need")
	runner.assert_true(world.clothing.owns_actor("lao_zhou"), "an ordinary NPC chooses to remove an owned outer layer when it worsens heat")
	if not world.clothing.owns_actor("lao_zhou"):
		return
	runner.assert_eq(world.clothing.active.lao_zhou.verb, "remove", "the autonomous response uses the ordinary removal process")
	var hot_rate: int = world.environment.energy_rate("lao_zhou")
	world.advance_to_ms(world.clothing.next_boundary_ms())
	runner.assert_true(not world.clothing.objects["clothing:spare:2"].worn and world.clothing.held("lao_zhou", "clothing:spare:2"), "cooling changes the original garment's use without deleting or dropping it")
	runner.assert_eq(world.environment.energy_rate("lao_zhou"), hot_rate, "removing the outer layer does not alter the preceding hot sample")
	world.advance_to_ms(120000)
	runner.assert_true(world.environment.energy_rate("lao_zhou") < hot_rate, "the next shared sample applies the NPC's lower actual heat burden")


func _historical_clothes(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	world.advance_to_ms(61001)
	var sampled_rate: int = world.environment.energy_rate("player")
	var answer: Dictionary = world.clothing.begin("player", "remove", "clothing:robe:player")
	runner.assert_true(answer.ok, "the historical sample scenario removes its actual robe after the last completed environmental sample")
	if not answer.ok:
		return
	world.advance_to_ms(world.clothing.next_boundary_ms())
	runner.assert_true(world.clothing.worn_at("player", "body").is_empty(), "the original body has genuinely completed removing its robe")
	runner.assert_eq(world.environment.samples.player.garments[0].id, "clothing:robe:player", "the preceding sample retains the garment that was actually worn then")
	var resumed: RegionalSimulation = _world(runner)
	if resumed == null:
		return
	runner.assert_true(resumed.restore(JSON.parse_string(_state(world))), "candidate validation reconstructs past worn use instead of comparing it to the body's later current use")
	world.advance_to_ms(180000)
	resumed.advance_to_ms(180000)
	runner.assert_true(world.environment.energy_rate("player") > sampled_rate, "a later actual sample reflects the body after removing its insulation")
	runner.assert_eq(_state(resumed), _state(world), "a valid sample followed by completed removal resumes to exactly the same complete future")


func _joint_future(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _take_cape(runner, world):
		return
	world.advance_to_ms(61001)
	var answer: Dictionary = world.clothing.begin("player", "wear", "clothing:spare:1")
	runner.assert_true(answer.ok, "the continuation scenario begins actual dressing after a cold sample")
	if not answer.ok:
		return
	world.advance_to_ms(62001)
	var saved: String = _state(world)
	var fine: RegionalSimulation = _world(runner)
	var bounded: RegionalSimulation = _world(runner)
	if fine == null or bounded == null:
		return
	runner.assert_true(fine.restore(JSON.parse_string(saved)), "candidate loading keeps the original cold sample, garment and unfinished dressing together")
	runner.assert_true(bounded.restore(JSON.parse_string(saved)), "a second independent authority resumes the same original work")
	world.set_active_region("river")
	fine.set_active_region("home")
	var horizon: int = 360000
	runner.assert_true(world.advance_to_ms(horizon), "offscreen bodies finish dressing and their later climate samples")
	while fine.elapsed_ms < horizon:
		if not fine.advance_to_ms(mini(horizon, fine.elapsed_ms + 7937)):
			runner.assert_true(false, "fine local execution reaches the shared environmental horizon")
			break
	var attempts: int = 0
	while not bounded.advance_to_ms(horizon, 1) and attempts < 2000:
		attempts += 1
	runner.assert_true(bounded.elapsed_ms == horizon, "a bounded scheduler retains and eventually processes all pending environmental time")
	runner.assert_eq(_comparison_state(fine), _comparison_state(world), "fine nearby and sparse absent execution produce the identical complete world future")
	runner.assert_eq(_comparison_state(bounded), _comparison_state(world), "event-budget yields do not lose or duplicate exposure, needs or physical garments")


func _quiet_regions(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, false, false, false, 100, false)
	if world == null:
		return
	world.set_active_region("home")
	runner.assert_true(world.advance_to_ms(240 * 60000), "the ordinary mild opening advances through several hours")
	runner.assert_eq(world.environment.samples.size(), world._actor_ids(world.regions).size(), "neutral exposure still carries complete original-body coverage")
	runner.assert_true(world.environment.samples.player.cell.is_empty() and world.environment.samples.player.region.is_empty(), "a proven neutral climate uses a bounded zero sample without reading a quiet body's current position")
	var remote: VillageSimulation = world.regions.river
	runner.assert_true(int(remote.simulation_work.step_count) + int(remote.simulation_work.quiet_batch_calls) < 100, "neutral climate sampling does not force quiet far residents to synchronize every minute")
	var fresh: RegionalSimulation = _world(runner, false, false, false, 100, false)
	if fresh != null:
		runner.assert_true(fresh.restore(JSON.parse_string(_state(world))), "full zero-rate coverage validates through the same candidate path")


func _bad_candidates(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	world.advance_to_ms(61001)
	var stable: String = _state(world)
	for kind: String in ["missing", "version", "rules", "activation", "pulse", "coverage", "unknown_actor", "sample_time", "rate", "temperature", "region", "cell", "insulation", "garment", "omitted_worn", "invented_worn", "false_neutral"]:
		var broken: Dictionary = JSON.parse_string(stable)
		match kind:
			"missing": broken.erase("environment")
			"version": broken.environment.version = SimEnvironment.VERSION + 1
			"rules": broken.environment.rules_version = 2
			"activation": broken.environment.activation_ms = broken.elapsed_ms + 1
			"pulse": broken.environment.last_pulse_ms -= 1
			"coverage": broken.environment.samples.erase("player")
			"unknown_actor": broken.environment.samples["not_a_body"] = broken.environment.samples.player.duplicate(true)
			"sample_time": broken.environment.samples.player.at_ms += 1
			"rate": broken.environment.samples.player.energy_rate += 1
			"temperature": broken.environment.samples.player.temperature_tenths += 1
			"region": broken.environment.samples.player.region = "unknown_climate"
			"cell": broken.environment.samples.player.cell.append(0)
			"insulation": broken.environment.samples.player.insulation_tenths += 1
			"garment": broken.environment.samples.player.garments[0].id = "clothing:robe:shi_tou"
			"omitted_worn":
				broken.environment.samples.player.garments = []
				_reprice_sample(broken.environment.samples.player, world.environment.definitions)
			"invented_worn":
				broken.environment.samples.player.garments = [{"id": "clothing:spare:0", "type": "indigo_robe", "wet": 0}]
				_reprice_sample(broken.environment.samples.player, world.environment.definitions)
			"false_neutral":
				broken.environment.samples.player.cell = []
				broken.environment.samples.player.region = ""
				broken.environment.samples.player.temperature_tenths = 0
				broken.environment.samples.player.energy_rate = 0
		runner.assert_true(not world.restore(broken), "candidate loading rejects environmental corruption: " + kind)
		runner.assert_eq(_state(world), stable, "rejected environmental candidates leave every live domain unchanged: " + kind)


func _reprice_sample(sample: Dictionary, rules: Dictionary) -> void:
	# The counterexample stays numerically coherent; it must be rejected for
	# contradicting actual historical worn use, rather than a stale derived rate.
	var insulation: int = 0
	for garment: Dictionary in sample.garments:
		insulation += SimClimateRules.insulation_at(rules, str(garment.type), int(garment.wet))
	sample.insulation_tenths = insulation
	sample.energy_rate = int(SimClimateRules.burden(rules, int(sample.temperature_tenths), insulation).energy_rate)


func _legacy_activation(runner: Object) -> void:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "legacy environment migration reads current rules")
		return
	var path: String = "res://tests/fixtures/session_v29.json"
	var original: String = FileAccess.get_file_as_string(path)
	runner.assert_eq(FileAccess.get_sha256(path), "78252157f410869b94ff9ffcb98fe898a02d3525b1815cf52bab8df3db59e1c1", "the independently recorded pre-environment archive retains its original bytes")
	var prior: Dictionary = JSON.parse_string(original)
	var upgraded: Dictionary = SessionSaveSchema.upgrade(prior, content)
	runner.assert_true(not upgraded.is_empty(), "the real pre-environment archive has an explicit ordinary migration")
	if upgraded.is_empty():
		return
	var before: Dictionary = prior.continuity.world
	var after: Dictionary = upgraded.continuity.world
	runner.assert_eq(upgraded.schema_version, SessionSaveSchema.VERSION, "the old root advances to the current session format")
	runner.assert_eq(after.version, RegionalSimulation.SCHEMA_VERSION, "the old regional authority advances jointly")
	runner.assert_eq(after.environment.activation_ms, before.elapsed_ms, "new environmental consequences begin at the original save time")
	runner.assert_eq(after.environment.last_pulse_ms, before.elapsed_ms, "the old world is not given imaginary preceding thermal samples")
	runner.assert_true(after.environment.samples.is_empty(), "legacy migration grants neither historical burden nor historical protection")
	for field: String in ["weather", "clothing", "health", "artifacts"]:
		var expected: Dictionary = before[field].duplicate(true)
		if field == "artifacts":
			runner.assert_eq(int(expected.version), 4, "the real pre-environment archive has the original artifact v4 envelope")
			# Root v40 -> v41 explicitly upgrades only this envelope to v5.
			expected.version = 5
		if field == "health":
			expected.version = 2
			expected["conflict_source_floor"] = 1
		runner.assert_eq(VillageRuntime._json_normalized(after[field]), VillageRuntime._json_normalized(expected), "migration preserves original physical history and stock with only explicit schema activation: " + field)
	var expected_conflicts: Dictionary = SimConflicts.empty_state()
	expected_conflicts.perception_since_ms = int(before.elapsed_ms)
	runner.assert_eq(VillageRuntime._json_normalized(after.conflicts), VillageRuntime._json_normalized(expected_conflicts), "pre-conflict climate archive gains only saved-present perception activation and no invented combat or teaching history")
	runner.assert_eq(after.spirit_sources.version, SimSpiritSources.VERSION, "later source activation explicitly reaches the current cost schema")
	runner.assert_eq(VillageRuntime._json_normalized(after.capability_practice), VillageRuntime._json_normalized(SimCapabilityPractice.empty_state()), "legacy climate history gains no invented practice, expenditure or learned node")
	# Later heading and ecology contracts add body/source/config fields and
	# bump the village format. Project only those explicit additions away,
	# retaining the complete comparison of all pre-existing village facts.
	var original_fields: Dictionary = after.regions.duplicate(true)
	for region: String in original_fields:
		runner.assert_eq(original_fields[region].version, VillageSimulation.SCHEMA_VERSION, "migration explicitly records the current original-body format in " + region)
		original_fields[region] = HerbMigration.prior_village(original_fields[region], before.regions[region])
		for id: String in original_fields[region].actors:
			var body: Dictionary = original_fields[region].actors[id]
			var expected_facing: Array = prior.player.motion.facing if id == "player" else [0.0, 1.0]
			runner.assert_eq(VillageRuntime._json_normalized(body.facing), VillageRuntime._json_normalized(expected_facing), "later heading initialization is explicit without inventing a past walk: " + id)
			body.erase("facing")
		original_fields[region].version = before.regions[region].version
	runner.assert_eq(VillageRuntime._json_normalized(original_fields), VillageRuntime._json_normalized(before.regions), "migration preserves every pre-existing regional physical history, action and stock field")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "legacy activation never rewrites the immutable real archive")


func _partial_at_time_limit(runner: Object) -> void:
	var source: RegionalSimulation = _world(runner, true, false, true, 100, false)
	if source == null:
		return
	# A domain-only boundary fixture supplies static dependencies without
	# advancing a populated world across centuries or rewriting its history.
	var authority := RegionalSimulation.new()
	authority.elapsed_ms = SimInventory.MAX_COUNT - 30000
	authority.target_ms = authority.elapsed_ms
	authority.regions = source.regions
	authority.weather = source.weather
	authority.clothing = source.clothing
	var domain := SimEnvironment.new()
	runner.assert_true(domain.initialize(authority, source.environment.definitions), "the pure environment boundary fixture may activate near the supported time limit")
	var saved: Dictionary = domain.to_dict()
	runner.assert_eq(domain.next_boundary_ms(), SimInventory.MAX_COUNT, "the first possible boundary saturates safely at the supported time limit")
	authority.elapsed_ms = SimInventory.MAX_COUNT
	authority.target_ms = authority.elapsed_ms
	domain.settle_at_ms(authority.elapsed_ms)
	runner.assert_true(domain.samples.is_empty(), "the final partial minute cannot invent a completed environmental exposure sample")
	runner.assert_true(domain.restore(saved), "an empty exposure state still restores when activation was less than a full minute before the time limit")
	runner.assert_eq(domain.activation_ms, SimInventory.MAX_COUNT - 30000, "the saturated boundary never rewrites the original activation time")
	var latest: int = SimInventory.MAX_COUNT - posmod(SimInventory.MAX_COUNT, 60000)
	var edge := SimEnvironment.new()
	authority.elapsed_ms = SimInventory.MAX_COUNT - 60000
	authority.target_ms = authority.elapsed_ms
	runner.assert_true(edge.initialize(authority, source.environment.definitions), "a domain may activate exactly one minute below the non-lattice maximum")
	var edge_saved: Dictionary = edge.to_dict()
	authority.elapsed_ms = latest
	authority.target_ms = authority.elapsed_ms
	edge.settle_at_ms(latest)
	authority.elapsed_ms = SimInventory.MAX_COUNT
	authority.target_ms = authority.elapsed_ms
	edge.settle_at_ms(authority.elapsed_ms)
	runner.assert_true(edge.samples.is_empty(), "a full elapsed minute at the final non-lattice timestamp cannot substitute for a qualified global-minute sample")
	runner.assert_eq(edge.last_pulse_ms, SimInventory.MAX_COUNT - 60000, "the saturated scheduling sentinel is never committed as a fabricated sample timestamp")
	var edge_restored := SimEnvironment.new()
	runner.assert_true(edge_restored.initialize(authority, source.environment.definitions) and edge_restored.restore(edge_saved), "the unsampled exact-one-minute activation restores at the supported maximum")
	for region: String in source.regions:
		runner.assert_eq(source.regions[region].elapsed_ms, 0, "partial-limit checks never advance the populated source village: " + region)
	var mild: RegionalSimulation = _world(runner, true, false, true, 230, false)
	if mild == null:
		return
	var stable_authority := RegionalSimulation.new()
	stable_authority.elapsed_ms = latest - 60000
	stable_authority.target_ms = stable_authority.elapsed_ms
	stable_authority.regions = mild.regions
	stable_authority.weather = mild.weather
	stable_authority.clothing = mild.clothing
	var established := SimEnvironment.new()
	runner.assert_true(established.initialize(stable_authority, mild.environment.definitions), "a mild boundary fixture can establish a real final global-minute sample")
	stable_authority.elapsed_ms = latest
	stable_authority.target_ms = stable_authority.elapsed_ms
	established.settle_at_ms(latest)
	runner.assert_eq(established.last_pulse_ms, latest, "the supported last global minute is a real established sample")
	runner.assert_eq(established.samples.size(), mild._actor_ids(mild.regions).size(), "the real established final sample still covers every original body")
	var established_state: Dictionary = established.to_dict()
	var established_json: String = JSON.stringify(established_state, "", true, true)
	stable_authority.elapsed_ms = SimInventory.MAX_COUNT
	stable_authority.target_ms = stable_authority.elapsed_ms
	established.settle_at_ms(stable_authority.elapsed_ms)
	runner.assert_eq(JSON.stringify(established.to_dict(), "", true, true), established_json, "the remaining non-lattice milliseconds preserve the entire established exposure cache")
	var established_restored := SimEnvironment.new()
	runner.assert_true(established_restored.initialize(stable_authority, mild.environment.definitions) and established_restored.restore(established_state), "the unchanged established cache restores at the final supported time")
	for region: String in mild.regions:
		runner.assert_eq(mild.regions[region].elapsed_ms, 0, "neutral final-pulse checks never force a populated village through years: " + region)
