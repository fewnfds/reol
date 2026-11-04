extends RefCounted
## Archives are read-only. New soil begins now, without repricing any old work.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const ARCHIVE: String = "res://tests/fixtures/session_v32.json"
const SOURCE_SHA: String = "a804cc0707f0e1be89372868bbdb58dc4544b4b1aa4e296a00dd999c185cd88a"
var _fixtures: RefCounted = Fixtures.new()


func run(runner: Object) -> void:
	_archives(runner)
	_bad_legacy(runner)
	_modern(runner)
	print("SCENARIO herb migration: read-only v1-v32 activation, preserved original goods/actions/heat, strict modern soil/weather/water references and atomic rejection")


static func canonical(value: Variant) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(value), "", true, true)


static func prior_village(current: Dictionary, prior: Dictionary) -> Dictionary:
	# Only project away the explicitly new schema. The caller still compares
	# every original field, including old growth phase, stock and pending work.
	var result: Dictionary = current.duplicate(true)
	result.version = prior.version
	result.config.actions.erase("irrigate_herb")
	result.land_resources.version = prior.land_resources.version
	for id: String in result.land_resources.sources:
		result.land_resources.sources[id].erase("ecology")
		result.land_resources.sources[id].next_growth_ms = prior.land_resources.sources[id].next_growth_ms
	return result


func _archives(runner: Object) -> void:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "herb migration loads original content")
		return
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SOURCE_SHA, "real unfinished warming source retains original bytes")
	for version: int in range(1, 33):
		var path: String = "res://tests/fixtures/session_v%d.json" % version
		var original: String = FileAccess.get_file_as_string(path)
		var source: Dictionary = JSON.parse_string(original)
		var before: String = canonical(source)
		var migrated: Dictionary = SessionSaveSchema.upgrade(source, content)
		runner.assert_true(not migrated.is_empty(), "real archive reaches herb activation: v%d" % version)
		if migrated.is_empty():
			continue
		runner.assert_eq(migrated.schema_version, SessionSaveSchema.VERSION, "root reaches current version: v%d" % version)
		if migrated.has("continuity"):
			for region: String in migrated.continuity.world.regions:
				var sim: Dictionary = migrated.continuity.world.regions[region]
				for row: Dictionary in sim.land_resources.sources.values():
					if row.ecology.is_empty():
						continue
					runner.assert_eq(row.ecology.activation_ms, sim.elapsed_ms, "soil starts at original saved village present: v%d/%s" % [version, region])
					runner.assert_eq(row.ecology.base_produced, row.produced, "only actual previous production is the historical baseline")
					runner.assert_eq(row.ecology.rain_input, 0, "migration never grants historical rain")
					runner.assert_eq(row.ecology.irrigated, 0, "migration never invents past care")
					runner.assert_eq(row.ecology.progress, 0, "old periodic growth is not also credited as new progress")
		if version == 32:
			var old_world: Dictionary = source.continuity.world
			var new_world: Dictionary = migrated.continuity.world
			for region: String in old_world.regions:
				runner.assert_eq(canonical(prior_village(new_world.regions[region], old_world.regions[region])), canonical(old_world.regions[region]), "v32 keeps every original village fact: " + region)
			for field: String in ["weather", "local_heat", "environment", "artifacts", "health", "clothing"]:
				var expected: Dictionary = old_world[field].duplicate(true)
				if field == "artifacts":
					runner.assert_eq(int(expected.version), 4, "the real ecology archive has the original artifact v4 envelope")
					# Root v40 -> v41 explicitly upgrades only this envelope to v5.
					expected.version = 5
				if field == "health":
					expected.version = 2
					expected["conflict_source_floor"] = 1
				runner.assert_eq(canonical(new_world[field]), canonical(expected), "activation preserves real in-flight domain with only explicit schema additions: " + field)
			var expected_conflicts: Dictionary = SimConflicts.empty_state()
			expected_conflicts.perception_since_ms = int(old_world.elapsed_ms)
			runner.assert_eq(canonical(new_world.conflicts), canonical(expected_conflicts), "old ecology archive gains only saved-present perception activation and no imagined combat or teaching")
			runner.assert_eq(new_world.spirit_sources.version, SimSpiritSources.VERSION, "later source activation explicitly reaches current cost reconciliation")
			runner.assert_eq(canonical(new_world.capability_practice), canonical(SimCapabilityPractice.empty_state()), "old ecology archive gains no invented advanced practice or learning history")
			runner.assert_eq(canonical(migrated.simulation), canonical(new_world.regions.home), "root and home remain the same body and inventory")
		runner.assert_eq(canonical(source), before, "pure migration leaves its input unchanged: v%d" % version)
		runner.assert_eq(FileAccess.get_file_as_string(path), original, "real historical file remains unchanged: v%d" % version)


func _bad_legacy(runner: Object) -> void:
	var content := ReolContentDB.new()
	content.load_all()
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ARCHIVE))
	for kind: String in ["root_conflict", "already_action", "already_ecology", "wrong_source", "wrong_village", "bad_old_phase"]:
		var bad: Dictionary = source.duplicate(true)
		match kind:
			"root_conflict": bad.simulation.inventory.containers["actor:player"].water = 1
			"already_action": bad.continuity.world.regions.river.config.actions["irrigate_herb"] = {}
			"already_ecology": bad.continuity.world.regions.river.land_resources.sources.herb_slope["ecology"] = {}
			"wrong_source": bad.continuity.world.regions.river.land_resources.version = 3
			"wrong_village": bad.continuity.world.regions.river.version = 6
			"bad_old_phase": bad.continuity.world.regions.river.land_resources.sources.herb_slope.next_growth_ms = 1
		var before: String = canonical(bad)
		runner.assert_true(SessionSaveSchema.upgrade(bad, content).is_empty(), "old corruption is not covered by new activation: " + kind)
		runner.assert_eq(canonical(bad), before, "failed old migration is pure: " + kind)


func _modern(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	GameClock.advance_msec(70001)
	var source: Dictionary = WorldSessionSnapshot.capture(runtime)
	var before: String = canonical(source)
	var live: RegionalSimulation = runtime.world_sim
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, source).is_empty(), "actual new ecology stages as an independent full candidate")
	for kind: String in ["missing_ecology", "old_source", "unknown_field", "free_water", "fake_temperature", "fake_rain", "stale_sample", "future_activation", "unbacked_irrigation", "orphan_consume", "dry_rain"]:
		var bad: Dictionary = source.duplicate(true)
		var sim: Dictionary = bad.continuity.world.regions.river
		var ecology: Dictionary = sim.land_resources.sources.herb_slope.ecology
		match kind:
			"missing_ecology": sim.land_resources.sources.herb_slope.erase("ecology")
			"old_source": sim.land_resources.version = 2
			"unknown_field": ecology["growth_bonus"] = 3
			"free_water": ecology.water = int(ecology.water) + 1
			"fake_temperature": ecology.temperature_tenths = int(ecology.temperature_tenths) + 1
			"fake_rain": ecology.rain = not ecology.rain
			"stale_sample": ecology.sample_ms = ecology.activation_ms
			"future_activation": ecology.activation_ms = int(sim.elapsed_ms) + 1
			"unbacked_irrigation": ecology.irrigation_receipts["fake"] = {"actor": "river_player", "at_ms": sim.elapsed_ms, "amount": 1, "water_units": 60000000}
			"orphan_consume": sim.inventory.operations["fake:irrigate"] = {"kind": "consume", "container": "actor:river_player", "item": "water", "amount": 1}
			"dry_rain":
				# Keep the water conservation equation balanced. It must still
				# fail because no sampled rainfall occurred in this dry interval.
				ecology.rain_input = int(ecology.rain_input) + 1
				ecology.overflow = int(ecology.overflow) + 1
		var bad_before: String = canonical(bad)
		runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "modern ecology rejects malformed source: " + kind)
		runner.assert_true(runtime.world_sim == live, "bad source never swaps live authority: " + kind)
		runner.assert_eq(canonical(WorldSessionSnapshot.capture(runtime)), before, "bad source leaves complete live world unchanged: " + kind)
		runner.assert_eq(canonical(bad), bad_before, "candidate never repairs malformed input: " + kind)
	_fixtures._dispose(fixture)
