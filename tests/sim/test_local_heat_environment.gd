extends RefCounted
## Original artifact heat changes future exposure, with explicit history.

const RegionFixture = preload("res://tests/sim/test_regional_simulation.gd")
var fixtures := RegionFixture.new()


func run(runner: Object) -> void:
	_future_only(runner)
	_neutral_background_and_preview(runner)
	_historical_sample(runner)
	_large_valid_temperature(runner)
	_residual_batching(runner)
	_same_future(runner)
	_cooling_threshold(runner)
	_changed_handoff_falls_back(runner)
	print("SCENARIO local heat environment: real original warmth changes only future needs, neutral-climate overheating, pure future previews, historical samples after movement/dissipation, full thermal range and quiet residual batching")


func _world(runner: Object, temperature: int = 100, maximum_pulse: bool = false, clothes: bool = true, second_stone: bool = false, managed_herbs: bool = true) -> RegionalSimulation:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "thermal environment scenarios load the real content")
		return null
	# Set a controlled opening climate before initialization. Actual weather,
	# bodies, material storage and source actions retain their original owners.
	for region: Dictionary in content.climate.regions.values():
		region.base_tenths = temperature
		for curve: String in ["seasonal_curve", "daily_curve"]:
			for point: Array in region[curve]:
				point[1] = 0
		region.weather_offsets.rain = 0
	if maximum_pulse:
		content.local_heat.pulse_energy = int(content.local_heat.max_cell_energy)
	if not managed_herbs:
		# Only the residual-field cost scenario excludes a different system's
		# compulsory minute sampling, using explicit prior fixed-source rules.
		content.land_resources.types.wild_herbs.erase("ecology")
	var instances: Dictionary = {}
	for region: String in ["home", "river"]:
		instances[region] = fixtures._make_village(content, region, false, managed_herbs)
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
	var sample: Dictionary = world.environment.samples.player
	runner.assert_true(int(sample.heat_tenths) > 0, "the completed original source appears in the new future exposure sample")
	runner.assert_eq(sample.temperature_tenths, 100 + int(sample.heat_tenths), "sampled temperature is the outdoor climate plus actual local heat")
	runner.assert_true(str(world.environment.local_conditions("player").feeling).contains("近旁留有暖意"), "visible local warmth has a qualitative explanation without exposing its hidden energy ledger")
	runner.assert_true(world.environment.energy_rate("player") < old_rate, "the real warm cell reduces the following cold burden")
	var future_rate: int = world.environment.energy_rate("player")
	before = _energy(world)
	world.advance_to_ms(world.elapsed_ms + 60000)
	runner.assert_eq(before - _energy(world), base_rate + future_rate, "only the next original energy interval uses the saved warm exposure rate")


func _neutral_background_and_preview(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, 220)
	if world == null or not _prepare(runner, world):
		return
	runner.assert_true(world.environment.samples.player.cell.is_empty(), "the ordinary mild opening retains the bounded neutral shortcut")
	if not _do(runner, world, "warm"):
		return
	var sample: Dictionary = world.environment.samples.player
	runner.assert_true(not sample.cell.is_empty() and sample.heat_tenths > 0, "local heat cannot disappear through a neutral outdoor-climate shortcut")
	runner.assert_true(world.environment.energy_rate("player") > 0 and str(world.environment.local_conditions("player").feeling).contains("暑"), "overheating the otherwise mild location has a real cost and qualitative explanation")
	runner.assert_eq(world.environment.samples.river_player.heat_tenths, 0, "a distant original resident receives no local heat")
	var current: Dictionary = world.environment.local_conditions("player")
	var cell: Vector2i = world.artifacts.object_cell("hearth_stone")
	var before: String = _state(world)
	var heat_time: int = int(world.local_heat.last_ms)
	var saw_supported: bool = false
	var saw_unsupported: bool = false
	for offset: int in [1, 7319, 60000, 86400000]:
		var preview: Dictionary = world.environment.local_conditions("player", world.elapsed_ms + offset)
		var projected: Dictionary = world.local_heat.project_tenths(cell, world.elapsed_ms + offset)
		runner.assert_true(projected.get("supported") is bool, "each thermal projection reports whether its value is known")
		if projected.get("supported") == true:
			saw_supported = true
			runner.assert_true(projected.has("value") and preview.has("heat_tenths"), "supported future heat has a value in the projection and local conditions")
			if projected.has("value") and preview.has("heat_tenths"):
				runner.assert_eq(preview.heat_tenths, projected.value, "a future initiative query uses the bounded pure thermal projection")
			runner.assert_eq(preview.get("heat_supported"), true, "a supported future exposes known heat")
		else:
			saw_unsupported = true
			runner.assert_eq(preview.get("heat_supported"), false, "an unsupported future explicitly retains uncertainty")
			runner.assert_true(not projected.has("value") and not preview.has("heat_tenths"), "unknown future heat has no numeric zero or cold sentinel")
			runner.assert_true(projected.get("reason") is String and preview.get("heat_reason") is String, "the unknown future supplies its failure reason")
			if projected.get("reason") is String and preview.get("heat_reason") is String:
				runner.assert_eq(preview.heat_reason, projected.reason, "local conditions retain the projection failure reason")
			runner.assert_eq(preview.temperature_tenths, 220, "an unsupported preview retains the existing outdoor decision bound")
		runner.assert_eq(world.local_heat.last_ms, heat_time, "future conditions never advance the real thermal integrator")
	runner.assert_true(saw_supported and saw_unsupported, "future previews exercise both known and unknown heat")
	var next: Dictionary = world.environment.local_conditions("player", world.elapsed_ms + 1)
	runner.assert_true(next.get("heat_supported") == true and next.has("heat_tenths"), "the near cooling preview is supported")
	if next.get("heat_supported") == true and next.has("heat_tenths"):
		runner.assert_true(next.heat_tenths <= current.heat_tenths, "supported cooling projection does not silently reuse the older warmer state")
	runner.assert_eq(_state(world), before, "repeated future condition previews mutate no world, source or frozen flow state")


func _historical_sample(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _prepare(runner, world) or not _do(runner, world, "warm"):
		return
	var source_cell: Vector2i = world.artifacts.object_cell("hearth_stone")
	var sampled: Dictionary = world.environment.samples.player.duplicate(true)
	world.regions.home.set_actor_cell("player", source_cell + Vector2i(15, 0))
	world.invalidate_region("home")
	world.advance_to_ms(world.elapsed_ms + 1737)
	runner.assert_eq(world.environment.local_conditions("player").heat_tenths, 0, "moving away leaves the real heat at its fixed original location")
	runner.assert_true(world.local_heat.local_tenths(source_cell) != int(sampled.heat_tenths), "current dissipation differs from the previously sampled thermal history")
	var saved: Dictionary = JSON.parse_string(_state(world))
	var copied: RegionalSimulation = _world(runner)
	if copied == null:
		return
	runner.assert_true(copied.restore(saved), "joint validation uses historical sample_tenths after movement and subsequent dissipation")
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
	if world == null or not _prepare(runner, world) or not _do(runner, world, "warm"):
		return
	runner.assert_true(world.environment.samples.player.temperature_tenths > 10000, "a valid maximum-capacity source exceeds the former outdoor-only validation range")
	var copied: RegionalSimulation = _world(runner, 100, true)
	if copied != null:
		runner.assert_true(copied.restore(JSON.parse_string(_state(world))), "the full allowed thermal range can save and restore with the original receipt")


func _residual_batching(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, 220, false, false, false, false)
	if world == null or not _prepare(runner, world) or not _do(runner, world, "warm"):
		return
	for sim: VillageSimulation in world.regions.values():
		runner.assert_true(sim.land_resources.sources.herb_slope.ecology.is_empty() and not sim.config.actions.has("irrigate_herb"), "residual-heat cost dependencies have no enabled plant process or care action")
	world.set_active_region("home")
	world.advance_to_ms(world.elapsed_ms + 600000)
	runner.assert_true(world.local_heat.input_energy > world.local_heat.loss_energy, "conservative sub-degree residue remains owned by the real thermal field")
	runner.assert_true(not world.environment._has_sampled_heat(world.elapsed_ms, false), "every residual cell projects to zero whole tenths")
	runner.assert_true(world.environment.samples.river_player.cell.is_empty(), "zero-projection residue permits the ordinary neutral sample shape")
	var remote: VillageSimulation = world.regions.river
	var steps: int = int(remote.simulation_work.step_count) + int(remote.simulation_work.quiet_batch_calls)
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 240 * 60000), "quiet far life continues for hours with a retained finite source history")
	var additional: int = int(remote.simulation_work.step_count) + int(remote.simulation_work.quiet_batch_calls) - steps
	runner.assert_true(additional < 100, "invisible conserved residue does not force quiet far bodies to synchronize every minute")


func _same_future(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _prepare(runner, world):
		return
	var result: Dictionary = world.artifacts.begin("player", "warm", "hearth_stone")
	if not result.ok:
		runner.assert_true(false, "joint future scenario starts real warming")
		return
	world.advance_to_ms(world.elapsed_ms + 17019)
	var saved: Dictionary = JSON.parse_string(_state(world))
	var fine: RegionalSimulation = _world(runner)
	var bounded: RegionalSimulation = _world(runner)
	if fine == null or bounded == null:
		return
	runner.assert_true(fine.restore(saved) and bounded.restore(saved), "both execution budgets restore the same actual unfinished source")
	var end: int = world.elapsed_ms + 193777
	runner.assert_true(world.advance_to_ms(end), "coarse regional execution completes the source and later exposure intervals")
	while fine.elapsed_ms < end:
		fine.advance_to_ms(mini(end, fine.elapsed_ms + 617))
	var attempts: int = 0
	while not bounded.advance_to_ms(end, 1) and attempts < 2000:
		attempts += 1
	runner.assert_true(attempts < 2000, "limited event budgets finish the actual thermal future")
	runner.assert_eq(_state(fine), _state(world), "fine timing preserves original energy, thermal history and source costs together")
	runner.assert_eq(_state(bounded), _state(world), "bounded timing preserves exactly the same full joint future")


func _cooling_decision(runner: Object, probe: RegionalSimulation, actor: String) -> int:
	var cell: Vector2i = probe.artifacts.object_cell("hearth_stone")
	var current: Dictionary = probe.environment.local_conditions(actor)
	var outdoor: int = int(current.temperature_tenths) - int(current.heat_tenths)
	var threshold: int = int(probe.environment.definitions.human.comfort_min_tenths) - outdoor - probe.environment.insulation_for(actor)
	for _step: int in 30:
		var boundary: int = probe.local_heat.next_boundary_ms()
		if boundary == SimInventory.MAX_COUNT:
			break
		var before: int = probe.local_heat.local_tenths(cell)
		var after: Dictionary = probe.local_heat.project_tenths(cell, boundary)
		runner.assert_true(after.get("supported") == true and after.has("value"), "the next cooling boundary has a supported projection")
		if after.get("supported") != true or not after.has("value"):
			return -1
		if before >= threshold and int(after.value) < threshold:
			var low: int = probe.elapsed_ms
			var high: int = boundary
			while high - low > 1:
				var middle: int = low + floori(float(high - low) / 2.0)
				var projected: Dictionary = probe.local_heat.project_tenths(cell, middle)
				runner.assert_true(projected.get("supported") == true and projected.has("value"), "a cooling threshold probe has a supported projection")
				if projected.get("supported") != true or not projected.has("value"):
					return -1
				if int(projected.value) < threshold:
					high = middle
				else:
					low = middle
			if high + 137 < boundary:
				return high + 137
			break
		probe.advance_to_ms(boundary)
	runner.assert_true(false, "the real original pulse crosses the comfort threshold inside a frozen thermal interval")
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
	var person: Dictionary = world.regions.home.actors.chen_shouzhuo
	person.autonomous = true
	person.hunger = 85.0
	person.energy = 85.0
	person.retry_ms = finish
	world.invalidate_region("home")
	var charge: int = int(world.artifacts.objects.second_stone.charge)
	runner.assert_true(world.advance_to_ms(finish + 1), "a native handoff and another real source complete at the same world timestamp")
	runner.assert_true(not world.artifacts.owns_actor("chen_shouzhuo"), "a newly comfortable NPC does not spend its own stone after the nearby source finishes")
	runner.assert_eq(person.active.get("action", ""), world.regions.home.config.actor_profiles.chen_shouzhuo.duty, "an invalidated warmth handoff immediately returns to the original routine instead of idling for twelve minutes")
	runner.assert_eq(world.artifacts.objects.second_stone.charge, charge, "fallback spends none of the unneeded second holder's original finite charge")
	runner.assert_true(world.artifacts._warming_decisions.is_empty(), "a complete regional boundary consumes the transient handoff without persistence")
