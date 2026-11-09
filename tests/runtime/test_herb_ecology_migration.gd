extends RefCounted
## Retired archives are read-only; current plant/source delegation is strict.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")
const SolarProjection = preload("res://tests/runtime/helpers/solar_legacy_projection.gd")
const ARCHIVE: String = "res://tests/fixtures/session_v32.json"
const SOURCE_SHA: String = "a804cc0707f0e1be89372868bbdb58dc4544b4b1aa4e296a00dd999c185cd88a"
var _fixtures: RefCounted = Fixtures.new()


func run(runner: Object) -> void:
	LegacyRejection.run(runner, {ARCHIVE: SOURCE_SHA}, [], [28], [4])
	_bad_legacy(runner)
	_modern(runner)
	print("SCENARIO retired herb archive: genuine v32 rejection and atomic current plant/source handoff validation")


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
	if current.get("version") != 3 or current.get("rules_version") != 3 or prior.get("version") != 1 or prior.get("rules_version") != 1:
		return {}
	for field: String in ["cells", "receipts", "last_sample_cells"]:
		if not prior.get(field) is Dictionary or not prior[field].is_empty():
			return {}
	if not prior.get("flows") is Array or not prior.flows.is_empty():
		return {}
	for field: String in ["input_energy", "loss_energy", "last_sample_input", "last_sample_loss"]:
		if not SnapshotValues.valid_integer(prior.get(field), 0) or prior[field] != 0:
			return {}
	if not SnapshotValues.valid_integer(prior.get("last_ms"), 0) or prior.get("segment_started_ms") != prior.last_ms:
		return {}
	for field: String in ["cells", "receipts", "last_sample_cells"]:
		if not current.get(field) is Dictionary or not current[field].is_empty():
			return {}
	if not current.get("flows") is Array or not current.flows.is_empty():
		return {}
	for field: String in ["input_energy", "loss_energy", "last_sample_input", "last_sample_loss"]:
		if not SnapshotValues.valid_integer(current.get(field), 0) or current[field] != 0:
			return {}
	if current.get("last_ms") != prior.last_ms or current.get("segment_started_ms") != prior.last_ms or current.get("model_started_ms") != prior.last_ms:
		return {}
	for field: String in ["ambient_in", "last_sample_ambient_in", "continuous_input", "absorbed_energy", "last_sample_continuous_input", "last_sample_absorbed"]:
		if not SnapshotValues.valid_integer(current.get(field), 0) or current[field] != 0:
			return {}
	for field: String in ["device_input", "device_absorbed", "device_switches"]:
		if not current.get(field) is Dictionary or not current[field].is_empty():
			return {}
	if not SnapshotValues.valid_integer(current.get("segment_until_ms"), 0) or current.segment_until_ms != SimLocalHeat.MAX_INTEGER or current.get("last_sample_mode") != "legacy_excess":
		return {}
	var expected_limits: Dictionary = {"at_ms": int(prior.last_ms), "input_energy": 0, "cells": []}
	if canonical(current.get("legacy_limits")) != canonical(expected_limits):
		return {}
	var result: Dictionary = current.duplicate(true)
	result.version = 1
	result.rules_version = 1
	for field: String in ["model_started_ms", "ambient_in", "last_sample_ambient_in", "last_sample_mode", "legacy_limits", "segment_until_ms", "continuous_input", "absorbed_energy", "device_input", "device_absorbed", "device_switches", "last_sample_continuous_input", "last_sample_absorbed"]:
		result.erase(field)
	return result


static func prior_environment(current: Dictionary, prior: Dictionary, snapshot: Dictionary) -> Dictionary:
	if current.get("version") != 3 or prior.get("version") != 2:
		return {}
	var result: Dictionary = SolarProjection.prior_environment(current, prior, snapshot)
	if result.is_empty():
		return {}
	result.version = 2
	return result


static func prior_thermal_world(current: Dictionary, prior: Dictionary, snapshot: Dictionary) -> Dictionary:
	# Shared narrow projection for v32-v41 archives with the proven empty v1
	# field. Other domain additions stay intact for each caller to check.
	if not current.get("regions") is Dictionary or not prior.get("regions") is Dictionary or current.regions.size() != prior.regions.size() or not current.get("local_heat") is Dictionary or not prior.get("local_heat") is Dictionary or not current.get("environment") is Dictionary or not prior.get("environment") is Dictionary:
		return {}
	# Old formats did not contain this domain. Never hide later real ground,
	# receipts, creations or actions when comparing with historical archives.
	var empty_lifecycle: Dictionary = _empty_lifecycle_for_test()
	if prior.has("object_lifecycle") or not current.get("object_lifecycle") is Dictionary or canonical(current.object_lifecycle) != canonical(empty_lifecycle):
		return {}
	var result: Dictionary = current.duplicate(true)
	result.erase("object_lifecycle")
	result.local_heat = prior_empty_heat(current.local_heat, prior.local_heat)
	result.environment = prior_environment(current.environment, prior.environment, snapshot)
	if result.local_heat.is_empty() or result.environment.is_empty():
		return {}
	for id: String in result.regions:
		if not result.regions[id] is Dictionary or not prior.regions.get(id) is Dictionary:
			return {}
		result.regions[id] = prior_village(result.regions[id], prior.regions[id])
		if result.regions[id].is_empty():
			return {}
	return result




static func _empty_lifecycle_for_test() -> Dictionary:
	return {"version": 1, "ground": {"version": 1, "slots": {}}, "receipts": {}, "created": {}, "actions": {}}


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
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, source).is_empty(), "the actual delegated source stages as an independent full candidate")
	for kind: String in ["missing_ecology", "old_source", "unknown_field", "dual_growth", "wrong_delegate", "orphan_delegate", "missing_body", "future_activation", "unbacked_irrigation", "orphan_consume", "dry_rain"]:
		var bad: Dictionary = source.duplicate(true)
		var sim: Dictionary = bad.continuity.world.regions.river
		var land: Dictionary = sim.land_resources.sources.herb_slope
		var plant_id: String = str(land.plant_id)
		match kind:
			"missing_ecology": sim.land_resources.sources.herb_slope.erase("ecology")
			"old_source": sim.land_resources.version = 2
			"unknown_field": land.ecology["growth_bonus"] = 3
			"dual_growth": land.next_growth_ms = int(sim.elapsed_ms) + 1
			"wrong_delegate": land.plant_id = "missing_plant"
			"orphan_delegate": land.plant_id = ""
			"missing_body": bad.continuity.world.plants.bodies.erase(plant_id)
			"future_activation": bad.continuity.world.plants.bodies[plant_id].born_ms = int(sim.elapsed_ms) + 1
			"unbacked_irrigation": land.ecology["irrigation_receipts"] = {"fake": {"actor": "river_player", "at_ms": sim.elapsed_ms, "amount": 1, "water_units": 60000000}}
			"orphan_consume": sim.inventory.operations["fake:irrigate"] = {"kind": "consume", "container": "actor:river_player", "item": "water", "amount": 1}
			"dry_rain":
				# Delegation cannot revive the retired per-source water balance.
				land.ecology["rain_input"] = 1
				land.ecology["overflow"] = 1
		var bad_before: String = canonical(bad)
		runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "modern ecology rejects malformed source: " + kind)
		runner.assert_true(runtime.world_sim == live, "bad source never swaps live authority: " + kind)
		runner.assert_eq(canonical(WorldSessionSnapshot.capture(runtime)), before, "bad source leaves complete live world unchanged: " + kind)
		runner.assert_eq(canonical(bad), bad_before, "candidate never repairs malformed input: " + kind)
	_fixtures._dispose(fixture)
