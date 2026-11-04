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
	# Compare all historical facts. Only the pre-ecology archive loses the
	# documented newly activated fields; v6 already has real ecology history.
	if current.get("version") != 7 or not current.get("land_resources") is Dictionary or current.land_resources.get("version") != 4 or not current.land_resources.get("sources") is Dictionary:
		return {}
	if not prior.get("land_resources") is Dictionary or not prior.land_resources.get("sources") is Dictionary or current.land_resources.sources.size() != prior.land_resources.sources.size():
		return {}
	var result: Dictionary = current.duplicate(true)
	var old_land_version: int = int(prior.land_resources.get("version", -1))
	if old_land_version == 3:
		if prior.get("version") != 6:
			return {}
		result.version = 6
		result.land_resources.version = 3
		for id: String in result.land_resources.sources:
			var row: Variant = result.land_resources.sources[id]
			var old_row: Variant = prior.land_resources.sources.get(id)
			if not row is Dictionary or not old_row is Dictionary or not row.get("ecology") is Dictionary or not old_row.get("ecology") is Dictionary:
				return {}
			if row.ecology.is_empty() != old_row.ecology.is_empty():
				return {}
			if not row.ecology.is_empty():
				if row.ecology.get("version") != 2 or old_row.ecology.get("version") != 1:
					return {}
				row.ecology.version = 1
		return result
	if old_land_version != 2 or int(prior.get("version", -1)) not in [4, 5] or not result.get("config") is Dictionary or not result.config.get("actions") is Dictionary:
		return {}
	result.version = prior.version
	result.config.actions.erase("irrigate_herb")
	result.land_resources.version = 2
	for id: String in result.land_resources.sources:
		var row: Variant = result.land_resources.sources[id]
		var old_row: Variant = prior.land_resources.sources.get(id)
		if not row is Dictionary or not old_row is Dictionary or not row.get("ecology") is Dictionary or old_row.has("ecology") or not old_row.has("next_growth_ms"):
			return {}
		row.erase("ecology")
		row.next_growth_ms = old_row.next_growth_ms
	return result


static func prior_empty_heat(current: Dictionary, prior: Dictionary) -> Dictionary:
	# These archived worlds had no source, cell, flux or historical input.
	# Validate the precise saved-present conversion before removing its fields;
	# retain last_sample_ms and every original fact for the caller's comparison.
	if current.get("version") != 2 or current.get("rules_version") != 2 or prior.get("version") != 1 or prior.get("rules_version") != 1:
		return {}
	for field: String in ["cells", "receipts", "last_sample_cells"]:
		if not prior.get(field) is Dictionary or not prior[field].is_empty():
			return {}
	if not prior.get("flows") is Array or not prior.flows.is_empty():
		return {}
	for field: String in ["input_energy", "loss_energy", "last_sample_input", "last_sample_loss"]:
		if prior.get(field) != 0:
			return {}
	if not prior.has("last_ms") or prior.get("segment_started_ms") != prior.last_ms:
		return {}
	if current.get("last_ms") != prior.last_ms or current.get("segment_started_ms") != prior.last_ms or current.get("model_started_ms") != prior.last_ms:
		return {}
	if current.get("ambient_in") != 0 or current.get("last_sample_ambient_in") != 0 or current.get("last_sample_mode") != "legacy_excess":
		return {}
	var expected_limits: Dictionary = {"at_ms": int(prior.last_ms), "input_energy": 0, "cells": []}
	if canonical(current.get("legacy_limits")) != canonical(expected_limits):
		return {}
	var result: Dictionary = current.duplicate(true)
	result.version = 1
	result.rules_version = 1
	for field: String in ["model_started_ms", "ambient_in", "last_sample_ambient_in", "last_sample_mode", "legacy_limits"]:
		result.erase(field)
	return result


static func prior_environment(current: Dictionary, prior: Dictionary) -> Dictionary:
	if current.get("version") != 3 or prior.get("version") != 2:
		return {}
	var result: Dictionary = current.duplicate(true)
	result.version = 2
	return result


static func prior_thermal_world(current: Dictionary, prior: Dictionary) -> Dictionary:
	# Shared narrow projection for v32-v41 archives with the proven empty v1
	# field. Other domain additions stay intact for each caller to check.
	if not current.get("regions") is Dictionary or not prior.get("regions") is Dictionary or current.regions.size() != prior.regions.size() or not current.get("local_heat") is Dictionary or not prior.get("local_heat") is Dictionary or not current.get("environment") is Dictionary or not prior.get("environment") is Dictionary:
		return {}
	var result: Dictionary = current.duplicate(true)
	result.local_heat = prior_empty_heat(current.local_heat, prior.local_heat)
	result.environment = prior_environment(current.environment, prior.environment)
	if result.local_heat.is_empty() or result.environment.is_empty():
		return {}
	for id: String in result.regions:
		if not result.regions[id] is Dictionary or not prior.regions.get(id) is Dictionary:
			return {}
		result.regions[id] = prior_village(result.regions[id], prior.regions[id])
		if result.regions[id].is_empty():
			return {}
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
				var actual: Dictionary = new_world[field]
				if field == "local_heat":
					actual = prior_empty_heat(actual, expected)
				if field == "environment":
					actual = prior_environment(actual, expected)
				if field == "artifacts":
					runner.assert_eq(int(expected.version), 4, "the real ecology archive has the original artifact v4 envelope")
					# Subsequent migrations explicitly update the original envelope.
					expected.version = SimArtifacts.VERSION
				if field == "health":
					expected.version = 2
					expected["conflict_source_floor"] = 1
				runner.assert_eq(canonical(actual), canonical(expected), "activation preserves real in-flight domain with only explicit schema additions: " + field)
			var expected_conflicts: Dictionary = SimConflicts.empty_state()
			expected_conflicts.perception_since_ms = int(old_world.elapsed_ms)
			runner.assert_eq(canonical(new_world.conflicts), canonical(expected_conflicts), "old ecology archive gains only saved-present perception activation and no imagined combat or teaching")
			runner.assert_eq(new_world.spirit_sources.version, SimSpiritSources.VERSION, "later source activation explicitly reaches current cost reconciliation")
			runner.assert_eq(canonical(new_world.capability_practice), canonical(SimCapabilityPractice.empty_state()), "old ecology archive gains no invented advanced practice or learning history")
			runner.assert_eq(canonical(migrated.simulation), canonical(new_world.regions.home), "root and home remain the same body and inventory")
		runner.assert_eq(canonical(source), before, "pure migration leaves its input unchanged: v%d" % version)
		runner.assert_eq(FileAccess.get_file_as_string(path), original, "real historical file remains unchanged: v%d" % version)
	_projection_contract(runner, content)


func _projection_contract(runner: Object, content: ReolContentDB) -> void:
	# This later archive has established ecology, so projecting its signed
	# format must not erase or reinitialize the existing soil facts.
	const PATH: String = "res://tests/fixtures/session_v34.json"
	var original: String = FileAccess.get_file_as_string(PATH)
	var source: Dictionary = JSON.parse_string(original)
	var migrated: Dictionary = SessionSaveSchema.upgrade(source, content)
	runner.assert_true(not migrated.is_empty(), "the genuine v34 ecology archive reaches the signed current format")
	if migrated.is_empty():
		return
	var old_world: Dictionary = source.continuity.world
	var new_world: Dictionary = migrated.continuity.world
	var before: String = canonical(new_world)
	var projected: Dictionary = prior_thermal_world(new_world, old_world)
	runner.assert_true(not projected.is_empty(), "the shared projection accepts the actual empty historical thermal state")
	if projected.is_empty():
		return
	for region: String in old_world.regions:
		runner.assert_eq(canonical(projected.regions[region]), canonical(old_world.regions[region]), "signed village projection retains every existing body, inventory and soil fact: " + region)
	runner.assert_eq(canonical(projected.local_heat), canonical(old_world.local_heat), "signed heat projection retains the actual old sample instant and ledger")
	runner.assert_eq(canonical(projected.environment), canonical(old_world.environment), "signed environment projection retains all historical exposure samples")
	var mutated_village: Dictionary = new_world.regions.home.duplicate(true)
	var ecology: Dictionary = mutated_village.land_resources.sources.herb_slope.ecology
	ecology.water = int(ecology.water) + 1
	runner.assert_true(canonical(prior_village(mutated_village, old_world.regions.home)) != canonical(old_world.regions.home), "projecting format labels does not hide a changed historical soil value")
	ecology.version = 1
	runner.assert_true(prior_village(mutated_village, old_world.regions.home).is_empty(), "a mislabeled current ecology is not projected as a valid conversion")
	var mutated_world: Dictionary = new_world.duplicate(true)
	mutated_world.local_heat.ambient_in = 1
	runner.assert_true(prior_thermal_world(mutated_world, old_world).is_empty(), "an invented ambient input cannot be projected away")
	projected.regions.home.actors.player.qi = -1
	runner.assert_eq(canonical(new_world), before, "mutating a projected result cannot change the migrated source")
	runner.assert_eq(FileAccess.get_file_as_string(PATH), original, "projection checks leave the genuine archive untouched")


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
