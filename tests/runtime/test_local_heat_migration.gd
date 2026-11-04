extends RefCounted
## New local heat begins at the saved present. Genuine archives stay read-only;
## modern missing heat is corruption, not another chance to run a migration.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const HerbMigration = preload("res://tests/runtime/test_herb_ecology_migration.gd")
const SolarProjection = preload("res://tests/runtime/helpers/solar_legacy_projection.gd")
const ARCHIVE_31: String = "res://tests/fixtures/session_v31.json"
const SHA_31: String = "3753f178d701b26d2bd479f5acd06068037fcfa03bf2e5f7b58e5ebd6dacc991"
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_legacy_archives(runner)
	_existing_samples(runner)
	_rejected_legacy_shapes(runner)
	_modern_candidates(runner)
	print("SCENARIO local heat migration: read-only v1-v31 chain, saved-present activation, untouched rain/clothes/charge and historical samples, strict modern heat and atomic independent staging")


func _canonical(value: Variant) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(value), "", true, true)


func _content(runner: Object) -> ReolContentDB:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "local heat migration reads current ordinary content")
		return null
	return content


func _legacy_archives(runner: Object) -> void:
	var content: ReolContentDB = _content(runner)
	if content == null:
		return
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE_31), SHA_31, "the real travelling v31 archive retains its independently recorded bytes")
	for version: int in range(1, 32):
		var path: String = "res://tests/fixtures/session_v%d.json" % version
		var original: String = FileAccess.get_file_as_string(path)
		var source: Dictionary = JSON.parse_string(original)
		var before: String = _canonical(source)
		var migrated: Dictionary = SessionSaveSchema.upgrade(source, content)
		runner.assert_true(not migrated.is_empty(), "the real prior archive reaches the current heat migration: v%d" % version)
		if migrated.is_empty():
			continue
		runner.assert_eq(migrated.schema_version, SessionSaveSchema.VERSION, "migration reaches the current root version: v%d" % version)
		if migrated.has("continuity"):
			var regional: Dictionary = migrated.continuity.world
			var present: int = int(regional.elapsed_ms)
			# These archives predate heat. The later absolute-energy conversion
			# retains their empty excess sample and its saved-present bounds.
			var expected_heat: Dictionary = SimLocalHeat.empty_state(present)
			expected_heat.last_sample_mode = "legacy_excess"
			expected_heat.legacy_limits = {"at_ms": present, "input_energy": 0, "cells": []}
			runner.assert_eq(regional.version, RegionalSimulation.SCHEMA_VERSION, "the regional format advances with its new heat owner: v%d" % version)
			runner.assert_eq(_canonical(regional.local_heat), _canonical(expected_heat), "old worlds retain empty excess-sample conversion bounds without previous heat, source receipts, loss or sampled thermal benefit: v%d" % version)
			runner.assert_eq(regional.environment.version, 3, "the original environmental sample contract explicitly advances: v%d" % version)
			for sample: Dictionary in regional.environment.samples.values():
				runner.assert_eq(sample.heat_tenths, 0, "every actual pre-heat sample retains zero historical local heat: v%d" % version)
		runner.assert_eq(_canonical(source), before, "the pure migration never edits its input dictionary: v%d" % version)
		runner.assert_eq(FileAccess.get_file_as_string(path), original, "the immutable real archive is never rewritten: v%d" % version)


func _existing_samples(runner: Object) -> void:
	var content: ReolContentDB = _content(runner)
	if content == null:
		return
	for version: int in [30, 31]:
		var path: String = "res://tests/fixtures/session_v%d.json" % version
		var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var migrated: Dictionary = SessionSaveSchema.upgrade(source, content)
		if migrated.is_empty():
			runner.assert_true(false, "actual environmental archive migrates before history comparison: v%d" % version)
			continue
		var old_world: Dictionary = source.continuity.world
		var new_world: Dictionary = migrated.continuity.world
		var old_exposure: Dictionary = old_world.environment
		var restored_old_exposure: Dictionary = SolarProjection.prior_environment(new_world.environment, old_exposure, migrated)
		runner.assert_true(not restored_old_exposure.is_empty() and old_exposure.get("version") == 1, "the old exposure comparison requires the fixed solar migration and its original shape: v%d" % version)
		if restored_old_exposure.is_empty() or old_exposure.get("version") != 1:
			continue
		runner.assert_eq(restored_old_exposure.activation_ms, old_exposure.activation_ms, "local heat does not restart the established exposure domain: v%d" % version)
		runner.assert_eq(restored_old_exposure.last_pulse_ms, old_exposure.last_pulse_ms, "local heat does not move the prior minute pulse: v%d" % version)
		for actor: String in restored_old_exposure.samples:
			var sample: Dictionary = restored_old_exposure.samples[actor]
			runner.assert_eq(sample.heat_tenths, 0, "the old sampled body is never credited heat from an invented source: " + actor)
			sample.erase("heat_tenths")
		restored_old_exposure.version = old_exposure.version
		runner.assert_eq(_canonical(restored_old_exposure), _canonical(old_exposure), "all existing sample fields survive without repricing old exposure: v%d" % version)
		for field: String in ["weather", "clothing", "artifacts", "heat_methods", "construction", "health"]:
			var expected: Dictionary = old_world[field].duplicate(true)
			if field == "artifacts":
				runner.assert_eq(int(expected.version), 4, "the real pre-heat archive has the original artifact v4 envelope")
				expected.version = SimArtifacts.VERSION
			if field == "health":
				expected.version = 2
				expected["conflict_source_floor"] = 1
			runner.assert_eq(_canonical(new_world[field]), _canonical(expected), "activation preserves real rain, pending work and physical resources with explicit schema additions: v%d/%s" % [version, field])
		var expected_conflicts: Dictionary = SimConflicts.empty_state()
		expected_conflicts.perception_since_ms = int(old_world.elapsed_ms)
		runner.assert_eq(_canonical(new_world.conflicts), _canonical(expected_conflicts), "pre-conflict heat archive gains only saved-present perception activation and no imagined combat or teaching: v%d" % version)
		runner.assert_eq(new_world.spirit_sources.version, SimSpiritSources.VERSION, "later source activation explicitly reaches the current cost contract")
		runner.assert_eq(_canonical(new_world.capability_practice), _canonical(SimCapabilityPractice.empty_state()), "old heat archive gains no invented advanced practice or costs")
		runner.assert_eq(new_world.local_heat.activation_ms, old_world.elapsed_ms, "new heat starts at the actual saved present, independent of older exposure time: v%d" % version)
		if version == 31:
			var previous_fields: Dictionary = new_world.duplicate(true)
			runner.assert_eq(SnapshotValues.normalized(previous_fields.private_exchange), SnapshotValues.normalized(SimPrivateExchange.empty_state()), "historical world gains no invented private exchange, consent, or receipt")
			previous_fields.erase("private_exchange")
			runner.assert_eq(SnapshotValues.normalized(previous_fields.field_opportunities), SnapshotValues.normalized(SimFieldOpportunities.empty_state()), "historical world gains no invented field site, visitor or treasure")
			previous_fields.erase("field_opportunities")
			previous_fields.erase("local_heat")
			previous_fields.erase("spirit_sources")
			previous_fields.erase("conflicts")
			runner.assert_eq(_canonical(previous_fields.site_affairs), _canonical(SimSiteAffairs.empty_state()), "old heat archive gains no invented local borrowing arrangement")
			previous_fields.erase("site_affairs")
			runner.assert_eq(_canonical(previous_fields.source_care), _canonical(SimSourceCare.empty_state()), "old heat archive gains no invented source care")
			previous_fields.erase("source_care")
			previous_fields.erase("capability_practice")
			previous_fields.health.version = old_world.health.version
			previous_fields.health.erase("conflict_source_floor")
			previous_fields.environment = restored_old_exposure
			previous_fields.version = old_world.version
			previous_fields.artifacts.version = old_world.artifacts.version
			# The later ecology migration adds care/config/source state after
			# heat. Project only those documented additions back to v31, then
			# compare every original regional fact, action and inventory field.
			for region: String in previous_fields.regions:
				previous_fields.regions[region] = HerbMigration.prior_village(previous_fields.regions[region], old_world.regions[region])
			runner.assert_eq(_canonical(previous_fields), _canonical(old_world), "v31 retains every prior field after explicitly projecting later heat, ecology and conflict additions")


func _rejected_legacy_shapes(runner: Object) -> void:
	var content: ReolContentDB = _content(runner)
	if content == null:
		return
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ARCHIVE_31))
	for kind: String in ["existing_heat", "already_new_environment", "missing_environment", "missing_samples", "unknown_environment_key"]:
		var bad: Dictionary = source.duplicate(true)
		match kind:
			"existing_heat": bad.continuity.world["local_heat"] = SimLocalHeat.empty_state(int(bad.clock.elapsed_ms))
			"already_new_environment": bad.continuity.world.environment.version = 2
			"missing_environment": bad.continuity.world.erase("environment")
			"missing_samples": bad.continuity.world.environment.erase("samples")
			"unknown_environment_key": bad.continuity.world.environment["invented_heat"] = 12
		var before: String = _canonical(bad)
		runner.assert_true(SessionSaveSchema.upgrade(bad, content).is_empty(), "a mismatched old schema cannot launder newly invented heat: " + kind)
		runner.assert_eq(_canonical(bad), before, "rejected legacy migration preserves its input: " + kind)
	# v30 includes actual established samples. Its facing migration must not
	# erase a forged new field to make the later heat migration accept it.
	var old_sample: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/session_v30.json"))
	old_sample.continuity.world.environment.samples.player["heat_tenths"] = 99
	runner.assert_true(SessionSaveSchema.upgrade(old_sample, content).is_empty(), "an allegedly old sample cannot bring unrecorded local heat through the facing migration")


func _modern_candidates(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	GameClock.advance_msec(60000)
	var source: Dictionary = WorldSessionSnapshot.capture(adapter)
	var live: RegionalSimulation = adapter.world_sim
	var clock: Dictionary = GameClock.to_dict()
	var before: String = _canonical(source)
	var staged: Dictionary = WorldSessionSnapshot.stage(adapter, source)
	runner.assert_true(not staged.is_empty(), "an ordinary current snapshot stages with its actual local-heat owner")
	if not staged.is_empty():
		runner.assert_true(staged.world != live, "heat validation constructs an independent candidate authority")
		runner.assert_eq(_canonical(staged.world.local_heat.to_dict()), _canonical(source.continuity.world.local_heat), "successful staging preserves heat rather than activating it again")
	runner.assert_true(source.continuity.world.environment.samples.has("player"), "modern candidate checks use an established real body exposure sample")
	if not source.continuity.world.environment.samples.has("player"):
		_fixtures._dispose(fixture)
		return
	for kind: String in ["missing_heat", "heat_not_record", "missing_field", "wrong_rules", "future_activation", "future_settlement", "free_heat", "unknown_flow", "missing_heat_sample", "false_heat_sample", "old_environment"]:
		var bad: Dictionary = source.duplicate(true)
		var regional: Dictionary = bad.continuity.world
		match kind:
			"missing_heat": regional.erase("local_heat")
			"heat_not_record": regional.local_heat = []
			"missing_field": regional.local_heat.erase("last_sample_cells")
			"wrong_rules": regional.local_heat.rules_version = 99
			"future_activation": regional.local_heat.activation_ms = int(bad.clock.elapsed_ms) + 1
			"future_settlement": regional.local_heat.last_ms = int(bad.clock.elapsed_ms) + 1
			"free_heat":
				regional.local_heat.cells = {"30,30": {"cell": [30, 30], "energy": 1}}
				regional.local_heat.input_energy = 1
			"unknown_flow": regional.local_heat.flows = [{"from": "absent", "to": "", "rate": 1}]
			"missing_heat_sample": regional.environment.samples.player.erase("heat_tenths")
			"false_heat_sample": regional.environment.samples.player.heat_tenths = 1
			"old_environment": regional.environment.version = 1
		var bad_before: String = _canonical(bad)
		runner.assert_true(WorldSessionSnapshot.stage(adapter, bad).is_empty(), "current-format local heat is validated strictly instead of filled by a migration: " + kind)
		runner.assert_true(adapter.world_sim == live, "rejected heat candidate cannot replace the live authority: " + kind)
		runner.assert_eq(_canonical(WorldSessionSnapshot.capture(adapter)), before, "rejected heat leaves bodies, stock, pending actions and heat unchanged: " + kind)
		runner.assert_eq(GameClock.to_dict(), clock, "rejected local heat leaves the shared clock unchanged: " + kind)
		runner.assert_eq(_canonical(bad), bad_before, "candidate validation does not repair its malformed input in place: " + kind)
	_fixtures._dispose(fixture)
