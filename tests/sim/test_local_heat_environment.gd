extends RefCounted
## Original artifact heat changes future exposure, with explicit history.

const RegionFixture = preload("res://tests/sim/test_regional_simulation.gd")
const CLIMATE_PATH: String = "res://data/definitions/climate.json"
const SOURCE_PATH: String = "res://data/definitions/environment_sources.json"
var fixtures := RegionFixture.new()


func run(runner: Object) -> void:
	_future_only(runner)
	_neutral_background_and_preview(runner)
	_historical_sample(runner)
	_large_valid_temperature(runner)
	_same_future(runner)
	_cooling_threshold(runner)
	_changed_handoff_falls_back(runner)
	print("SCENARIO outdoor environment fields: real timed warmth, gradual exposure, mild-climate overheating, pure uncertain previews, historical samples, strong intrinsic source and whole/sliced/budgeted futures")


func _world(runner: Object, temperature: int = 100, strong_source: bool = false, clothes: bool = true, second_stone: bool = false) -> RegionalSimulation:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "thermal environment scenarios load the real content")
		return null
	# Bind all test definitions into a new immutable bundle before world creation.
	# Actual weather, bodies, artifacts and source actions keep their owners.
	var documents: Dictionary = content.content_bundle().documents
	for region: Dictionary in documents[CLIMATE_PATH].regions.values():
		region.base_tenths = temperature
		for curve: String in ["seasonal_curve", "daily_curve"]:
			for point: Array in region[curve]:
				point[1] = 0
		region.weather_offsets.rain = 0
	if strong_source:
		var sources: Dictionary = documents[SOURCE_PATH]
		sources.profiles["test_strong_hot"] = sources.profiles.intrinsic_hot.duplicate(true)
		sources.profiles.test_strong_hot.thermal_grade = 10000
		sources.bindings.artifacts.plain_slate = "test_strong_hot"
	content = ReolContentDB.new()
	if not content.load_bundle(ReolContentBundle.from_documents(documents)):
		runner.assert_true(false, "controlled climate and optional intrinsic source form a valid independent content bundle")
		return null
	var instances: Dictionary = {}
	for region: String in ["home", "river"]:
		instances[region] = fixtures._make_village(content, region, false)
	var world := RegionalSimulation.new()
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/world_continuity.json"))
	if not world.initialize(settings, instances, content):
		runner.assert_true(false, "real regional authority initializes finite heat and controlled climate")
		return null
	var services: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/settlement_services.json"))
	if not world.configure_services(services):
		runner.assert_true(false, "thermal scenarios retain original services and action exclusion")
		return null
	world.services.set_navigation(Callable(fixtures, "_path"))
	world.set_active_region("")
	if clothes and not world.clothing.spawn_opening():
		runner.assert_true(false, "thermal scenarios use the real finite opening garments")
		return null
	var artifacts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))
	if second_stone:
		# Explicit finite scenario stock for a simultaneous two-person source
		# test. No autonomous policy spawns or refills either object.
		artifacts.objects.append({"id": "second_stone", "definition": "warm_stone", "region": "home", "container": "kitchen"})
	if not world.artifacts.spawn_opening(artifacts):
		runner.assert_true(false, "thermal scenarios spawn exactly the original finite stone")
		return null
	if strong_source:
		# Physical definitions must use the original lifecycle issuance receipt,
		# including when authored as a fixed item in this controlled scenario.
		var created: Dictionary = world.object_lifecycle.execute({"command": "intrinsic_hot_opening", "op": "spawn", "id": "intrinsic_hot_fixture", "definition": "plain_slate", "to": {"region": "home", "container": "kitchen"}})
		if not bool(created.get("ok", false)):
			runner.assert_true(false, "the strong original source is issued through its lifecycle: " + str(created))
			return null
	world.regions.home.set_actor_cell("player", world.artifacts.object_cell("hearth_stone"))
	world.invalidate_region("home")
	return world


func _do(runner: Object, world: RegionalSimulation, verb: String) -> bool:
	return _do_actor(runner, world, "player", verb)


func _do_actor(runner: Object, world: RegionalSimulation, actor: String, verb: String, object_id: String = "hearth_stone") -> bool:
	var result: Dictionary = world.artifacts.begin(actor, verb, object_id)
	runner.assert_true(result.ok, "real original thermal action begins: " + actor + ":" + verb)
	if not result.ok:
		return false
	var ok: bool = world.advance_to_ms(int(world.artifacts.active[actor].due_ms))
	runner.assert_true(ok, "the original scheduler completes: " + verb)
	return ok


func _prepare(runner: Object, world: RegionalSimulation) -> bool:
	return _do(runner, world, "study") and _do(runner, world, "take")


func _state(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _energy(world: RegionalSimulation) -> int:
	world.synchronize_region("home")
	return roundi(float(world.regions.home.actors.player.energy) * VillageSimulation.NEED_SCALE)


func _future_only(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _prepare(runner, world):
		return
	var old_rate: int = world.environment.energy_rate("player")
	var base_rate: int = roundi(float(world.regions.home.config.needs.energy_per_minute) * VillageSimulation.NEED_SCALE)
	var before: int = _energy(world)
	runner.assert_true(old_rate > 0, "the original worn robe is insufficient in the controlled cold opening")
	if not _do(runner, world, "warm"):
		return
	runner.assert_eq(before - _energy(world), base_rate + old_rate, "warm completion does not refund or remove the preceding cold minute")
	var event: Dictionary = world.artifacts.events.back()
	runner.assert_true(event.kind == "warmed" and world.local_heat.receipts.has(event.action), "only the real completed warm job installs its original temporary source")
	var sample: Dictionary = world.environment.samples.player
	runner.assert_eq(int(sample.heat_tenths), 0, "the actual temperature does not jump at the source's completion instant")
	runner.assert_eq(world.environment.energy_rate("player"), old_rate, "the completion instant leaves the already-sampled cold rate unchanged")
	before = _energy(world)
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 60000), "the temporary source acts for the next full shared minute")
	runner.assert_eq(before - _energy(world), base_rate + old_rate, "the interval before the new sample retains its earlier exposure rate")
	sample = world.environment.samples.player
	runner.assert_true(int(sample.heat_tenths) > 0, "actual heat is present in the next sampled exposure after time has elapsed")
	runner.assert_eq(sample.temperature_tenths, 100 + int(sample.heat_tenths), "sampled temperature is the outdoor climate plus actual local heat")
	runner.assert_true(str(world.environment.local_conditions("player").feeling).contains("近旁留有暖意"), "visible local warmth has a qualitative explanation without exposing its hidden energy ledger")
	runner.assert_true(world.environment.energy_rate("player") < old_rate, "the real warm cell reduces the following cold burden")
	var future_rate: int = world.environment.energy_rate("player")
	before = _energy(world)
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 60000), "the next sampled exposure actually elapses")
	runner.assert_eq(before - _energy(world), base_rate + future_rate, "only the next original energy interval uses the saved warm exposure rate")


func _neutral_background_and_preview(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, 220)
	if world == null or not _prepare(runner, world):
		return
	runner.assert_true(world.environment.samples.player.cell.is_empty(), "the ordinary mild opening retains the bounded neutral shortcut")
	if not _do(runner, world, "warm"):
		return
	runner.assert_eq(int(world.environment.samples.player.heat_tenths), 0, "a new source does not instantly change the previous mild sample")
	if not world.advance_to_ms(world.elapsed_ms + 60000):
		runner.assert_true(false, "mild location advances while the real source establishes its field")
		return
	var sample: Dictionary = world.environment.samples.player
	runner.assert_true(not sample.cell.is_empty() and sample.heat_tenths > 0, "local heat cannot disappear through a neutral outdoor-climate shortcut")
	runner.assert_true(world.environment.energy_rate("player") > 0 and str(world.environment.local_conditions("player").feeling).contains("暑"), "overheating the otherwise mild location has a real cost and qualitative explanation")
	runner.assert_eq(world.environment.samples.river_player.heat_tenths, 0, "a distant original resident receives no local heat")
	var current: Dictionary = world.environment.local_conditions("player")
	var cell: Vector2i = world.artifacts.object_cell("hearth_stone")
	var before: String = _state(world)
	var heat_time: int = int(world.local_heat.last_ms)
	var actual: Dictionary = world.local_heat.project_tenths(cell, world.elapsed_ms)
	runner.assert_true(bool(actual.get("supported", false)) and actual.get("value") == current.get("heat_tenths"), "the actual committed temperature is supported and agrees with local conditions")
	for offset: int in [1, 7319, 60000, 86400000]:
		var preview: Dictionary = world.environment.local_conditions("player", world.elapsed_ms + offset)
		var projected: Dictionary = world.local_heat.project_tenths(cell, world.elapsed_ms + offset)
		runner.assert_eq(projected.get("supported"), false, "uncommitted future field values remain explicitly unknown")
		runner.assert_eq(preview.get("heat_supported"), false, "future local conditions preserve that uncertainty")
		runner.assert_true(not projected.has("value") and not preview.has("heat_tenths"), "unknown future heat has no numeric zero or cold sentinel")
		runner.assert_true(projected.get("reason") is String and preview.get("heat_reason") is String, "the unknown future supplies its failure reason")
		if projected.get("reason") is String and preview.get("heat_reason") is String:
			runner.assert_eq(preview.heat_reason, projected.reason, "local conditions retain the projection failure reason")
		runner.assert_true(not preview.has("temperature_tenths") and not preview.has("burden_rate"), "an unsupported forecast does not publish an exact temperature or burden")
		runner.assert_eq(preview.get("temperature_min_tenths"), 220 + world.local_heat.minimum_offset_tenths(), "the lower bound includes an admissible cold offset")
		runner.assert_eq(preview.get("temperature_max_tenths"), 220 + world.local_heat.maximum_offset_tenths(), "the upper bound includes an admissible warm offset")
		runner.assert_eq(world.local_heat.last_ms, heat_time, "future conditions never advance the real thermal integrator")
	runner.assert_eq(_state(world), before, "repeated future condition previews mutate no world, source or committed field state")


func _historical_sample(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _prepare(runner, world) or not _do(runner, world, "warm"):
		return
	if not world.advance_to_ms(world.elapsed_ms + 60000):
		runner.assert_true(false, "the real pulse produces a warm historical sample")
		return
	var source_cell: Vector2i = world.artifacts.object_cell("hearth_stone")
	var sampled: Dictionary = world.environment.samples.player.duplicate(true)
	runner.assert_true(int(sampled.heat_tenths) > 0, "the historical sample contains established local warmth")
	world.regions.home.set_actor_cell("player", source_cell + Vector2i(15, 0))
	world.invalidate_region("home")
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 1737), "the world moves past the sampled boundary")
	runner.assert_eq(world.environment.local_conditions("player").heat_tenths, 0, "moving away leaves the real heat at its fixed original location")
	runner.assert_true(world.local_heat.local_tenths(source_cell) != int(sampled.heat_tenths), "current dissipation differs from the previously sampled thermal history")
	var saved: Dictionary = JSON.parse_string(_state(world))
	var copied: RegionalSimulation = _world(runner)
	if copied == null:
		return
	var restored: bool = copied.restore(saved)
	runner.assert_true(restored, "joint validation uses historical sample_tenths after movement and subsequent dissipation")
	if not restored:
		return
	runner.assert_eq(VillageRuntime._json_normalized(copied.environment.samples.player), VillageRuntime._json_normalized(sampled), "loading never reprices an old body sample with current location or current heat")
	var stable: String = _state(copied)
	for corruption: String in ["heat", "temperature", "false_neutral", "missing_heat"]:
		var bad: Dictionary = JSON.parse_string(stable)
		var row: Dictionary = bad.environment.samples.player
		match corruption:
			"heat": row.heat_tenths += 1
			"temperature": row.temperature_tenths += 1
			"missing_heat": row.erase("heat_tenths")
			"false_neutral":
				row.cell = []
				row.region = ""
				row.heat_tenths = 0
				row.temperature_tenths = 0
				row.energy_rate = 0
		runner.assert_true(not copied.restore(bad), "candidate rejects historical thermal corruption: " + corruption)
		runner.assert_eq(_state(copied), stable, "rejected thermal sample leaves every live authority unchanged: " + corruption)


func _large_valid_temperature(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, 100, true)
	if world == null:
		return
	runner.assert_true(world.artifacts.objects.has("intrinsic_hot_fixture") and world.artifacts.objects.intrinsic_hot_fixture.container == "kitchen", "the explicit test scenario owns one fixed strong source")
	if not world.advance_to_ms(120000):
		runner.assert_true(false, "the real strong source establishes over shared world time")
		return
	var sample: Dictionary = world.environment.samples.player
	runner.assert_true(sample.temperature_tenths > 10000, "a valid intrinsically hot object raises actual sampled temperature beyond the ordinary climate range")
	var actual: Dictionary = world.local_heat.actual_at(world.artifacts.object_cell("intrinsic_hot_fixture"), world.elapsed_ms)
	runner.assert_true(bool(actual.get("ok", false)), "the strong source has an accessible actual temperature")
	if bool(actual.get("ok", false)):
		runner.assert_eq(int(sample.temperature_tenths), roundi(float(actual.value_c) * 10.0), "the original player's sample uses the same actual field")
	var copied: RegionalSimulation = _world(runner, 100, true)
	if copied != null:
		var saved: String = _state(world)
		var accepted: bool = copied.restore(JSON.parse_string(saved))
		runner.assert_true(accepted, "strong intrinsic source and actual extreme-temperature history restore with their original content")
		if accepted:
			runner.assert_eq(_state(copied), saved, "restoration preserves the complete original extreme-temperature world")


func _same_future(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _prepare(runner, world):
		return
	var result: Dictionary = world.artifacts.begin("player", "warm", "hearth_stone")
	if not result.ok:
		runner.assert_true(false, "joint future scenario starts real warming")
		return
	if not world.advance_to_ms(world.elapsed_ms + 17019):
		runner.assert_true(false, "the real source action reaches the in-flight checkpoint")
		return
	var saved: Dictionary = JSON.parse_string(_state(world))
	var fine: RegionalSimulation = _world(runner)
	var bounded: RegionalSimulation = _world(runner)
	if fine == null or bounded == null:
		return
	var fine_restored: bool = fine.restore(saved)
	var bounded_restored: bool = bounded.restore(saved)
	runner.assert_true(fine_restored and bounded_restored, "both execution budgets restore the same actual unfinished source")
	if not fine_restored or not bounded_restored:
		return
	var end: int = world.elapsed_ms + 193777
	runner.assert_true(world.advance_to_ms(end), "coarse regional execution completes the source and later exposure intervals")
	var fine_attempts: int = 0
	while fine.elapsed_ms < end and fine_attempts < 1000:
		fine.advance_to_ms(mini(end, fine.elapsed_ms + 617))
		fine_attempts += 1
	runner.assert_true(fine.elapsed_ms == end, "fine-grained execution completes all requested game time")
	var attempts: int = 0
	while not bounded.advance_to_ms(end, 1) and attempts < 2000:
		attempts += 1
	runner.assert_true(attempts < 2000 and bounded.elapsed_ms == end, "limited event budgets finish the actual thermal future")
	runner.assert_eq(_state(fine), _state(world), "fine timing preserves original energy, thermal history and source costs together")
	runner.assert_eq(_state(bounded), _state(world), "bounded timing preserves exactly the same full joint future")


func _cooling_decision(runner: Object, probe: RegionalSimulation, actor: String) -> int:
	# The outdoor field does not promise a future forecast. A detached world
	# genuinely advances; only committed actual conditions identify the first
	# cold second after the real temporary source has expired.
	if not probe.advance_to_ms(probe.elapsed_ms + 60000):
		runner.assert_true(false, "the real warming pulse establishes before cooling is examined")
		return -1
	var threshold: int = int(probe.environment.definitions.human.comfort_min_tenths) - probe.environment.insulation_for(actor)
	var established: Dictionary = probe.environment.local_conditions(actor)
	if established.is_empty() or not bool(established.get("heat_supported", false)):
		runner.assert_true(false, "the established local temperature is known at committed time")
		return -1
	runner.assert_true(int(established.temperature_tenths) >= threshold, "the real pulse first makes the holder comfortable")
	if int(established.temperature_tenths) < threshold:
		return -1
	for _step: int in 240:
		if not probe.advance_to_ms(probe.elapsed_ms + 1000):
			runner.assert_true(false, "the detached cooling probe continues its real shared clock")
			return -1
		var actual: Dictionary = probe.environment.local_conditions(actor)
		if actual.is_empty() or not bool(actual.get("heat_supported", false)):
			runner.assert_true(false, "committed cooling conditions remain available")
			return -1
		if int(actual.temperature_tenths) < threshold:
			return probe.elapsed_ms
	runner.assert_true(false, "the expired pulse cools enough for the holder to need warmth again")
	return -1


func _cooling_threshold(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	world.regions.home.set_actor_cell("chen_shouzhuo", world.artifacts.object_cell("hearth_stone"))
	world.invalidate_region("home")
	if not _do_actor(runner, world, "chen_shouzhuo", "take") or not _do_actor(runner, world, "chen_shouzhuo", "warm"):
		return
	var saved: Dictionary = JSON.parse_string(_state(world))
	var probe: RegionalSimulation = _world(runner)
	var fine: RegionalSimulation = _world(runner)
	var bounded: RegionalSimulation = _world(runner)
	if probe == null or fine == null or bounded == null:
		return
	if not probe.restore(saved) or not fine.restore(saved) or not bounded.restore(saved):
		runner.assert_true(false, "the real cooling pulse and original finite holder restore for timing comparison")
		return
	var decision: int = _cooling_decision(runner, probe, "chen_shouzhuo")
	if decision < 0:
		return
	for candidate: RegionalSimulation in [world, fine, bounded]:
		var person: Dictionary = candidate.regions.home.actors.chen_shouzhuo
		person.autonomous = true
		person.hunger = 85.0
		person.energy = 85.0
		person.retry_ms = decision
		candidate.invalidate_region("home")
	runner.assert_true(fine.advance_to_ms(decision - 1), "fine execution commits a cut after actual cooling but just before the native decision")
	runner.assert_true(world.advance_to_ms(decision + 1) and fine.advance_to_ms(decision + 1), "both clocks reach the same native comfort decision")
	var attempts: int = 0
	while not bounded.advance_to_ms(decision + 1, 1) and attempts < 2000:
		attempts += 1
	runner.assert_true(attempts < 2000 and bounded.elapsed_ms == decision + 1, "bounded execution reaches the same actual cooling decision")
	for candidate: RegionalSimulation in [world, fine, bounded]:
		runner.assert_true(candidate.artifacts.active.get("chen_shouzhuo", {}).get("verb") == "warm", "the real threshold produces the same warming handoff under every time split")
	runner.assert_eq(_state(fine), _state(world), "one extra cut near the cold threshold cannot change the NPC's original action or thermal future")
	runner.assert_eq(_state(bounded), _state(world), "bounded scheduling makes the same real threshold choice")


func _changed_handoff_falls_back(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, 100, false, true, true)
	if world == null:
		return
	world.regions.home.set_actor_cell("chen_shouzhuo", world.artifacts.object_cell("hearth_stone"))
	world.invalidate_region("home")
	if not _prepare(runner, world) or not _do_actor(runner, world, "chen_shouzhuo", "take", "second_stone"):
		return
	var result: Dictionary = world.artifacts.begin("player", "warm", "hearth_stone")
	if not result.ok:
		runner.assert_true(false, "the other original holder starts a timed nearby source")
		return
	var finish: int = int(world.artifacts.active.player.due_ms)
	var decision: int = finish + 20000
	var person: Dictionary = world.regions.home.actors.chen_shouzhuo
	person.autonomous = true
	person.hunger = 85.0
	person.energy = 85.0
	person.retry_ms = decision
	world.invalidate_region("home")
	var charge: int = int(world.artifacts.objects.second_stone.charge)
	runner.assert_true(world.advance_to_ms(decision - 1), "the nearby completed source has actually warmed the location before the native decision")
	var conditions: Dictionary = world.environment.local_conditions("chen_shouzhuo")
	var threshold: int = int(world.environment.definitions.human.comfort_min_tenths) - world.environment.insulation_for("chen_shouzhuo")
	runner.assert_true(bool(conditions.get("heat_supported", false)) and int(conditions.get("temperature_tenths", -99999)) >= threshold, "the NPC has become comfortable after the field establishes")
	runner.assert_true(world.advance_to_ms(decision + 1), "the original native decision reaches its scheduled timestamp")
	runner.assert_true(not world.artifacts.owns_actor("chen_shouzhuo"), "a newly comfortable NPC does not spend its own stone after another real source warms the location")
	runner.assert_eq(person.active.get("action", ""), world.regions.home.config.actor_profiles.chen_shouzhuo.duty, "an invalidated warmth handoff immediately returns to the original routine instead of idling for twelve minutes")
	runner.assert_eq(world.artifacts.objects.second_stone.charge, charge, "fallback spends none of the unneeded second holder's original finite charge")
	runner.assert_true(world.artifacts._warming_decisions.is_empty(), "a complete regional boundary consumes the transient handoff without persistence")
