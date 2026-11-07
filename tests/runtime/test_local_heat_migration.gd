extends RefCounted
## Retired local-heat archives are immutable; current field candidates are strict.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")
const SHA_31: String = "3753f178d701b26d2bd479f5acd06068037fcfa03bf2e5f7b58e5ebd6dacc991"
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	var archives: Dictionary = {}
	for version: int in range(1, 32):
		var path: String = "res://tests/fixtures/session_v%d.json" % version
		archives[path] = SHA_31 if version == 31 else ""
	LegacyRejection.run(runner, archives)
	_modern_candidates(runner)
	print("SCENARIO retired local heat: real v1-v31 archives are refused and current field/body samples are independently validated")


func _canonical(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _modern_candidates(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	GameClock.advance_msec(60000)
	var source: Dictionary = WorldSessionSnapshot.capture(adapter)
	var live: RegionalSimulation = adapter.world_sim
	var terrain: WorldMapData = live.map_data
	var clock: Dictionary = GameClock.to_dict()
	var before: String = _canonical(source)
	var staged: Dictionary = WorldSessionSnapshot.stage(adapter, source)
	runner.assert_true(not staged.is_empty(), "an ordinary current snapshot stages with its actual world-field owner")
	if not staged.is_empty():
		runner.assert_true(staged.world != live and staged.world.environment_fields != live.environment_fields, "field validation constructs independent authorities")
		runner.assert_eq(_canonical(staged.world.environment_fields.to_dict()), _canonical(source.continuity.world.local_heat), "successful staging preserves the actual saved field")
	runner.assert_true(source.continuity.world.environment.samples.has("player"), "current candidate checks use a real body exposure sample")
	if not source.continuity.world.environment.samples.has("player"):
		_fixtures._dispose(fixture)
		return
	for kind: String in ["missing_heat", "heat_not_record", "missing_temperature", "wrong_model", "old_field_version", "wrong_source_digest", "future_activation", "future_settlement", "invalid_temperature", "forged_receipt", "invalid_sample", "missing_heat_sample", "false_heat_sample", "old_environment"]:
		var bad: Dictionary = source.duplicate(true)
		var regional: Dictionary = bad.continuity.world
		match kind:
			"missing_heat": regional.erase("local_heat")
			"heat_not_record": regional.local_heat = []
			"missing_temperature": regional.local_heat.erase("temperature")
			"wrong_model": regional.local_heat.model = "retired_heat_model"
			"old_field_version": regional.local_heat.version = 3
			"wrong_source_digest": regional.local_heat.source_digest = "invalid"
			"future_activation": regional.local_heat.activation_ms = int(bad.clock.elapsed_ms) + 1
			"future_settlement": regional.local_heat.last_ms = int(bad.clock.elapsed_ms) + 1
			"invalid_temperature": regional.local_heat.temperature = []
			"forged_receipt": regional.local_heat.receipts["forged"] = {}
			"invalid_sample": regional.local_heat.samples["0,0"] = "not an integer"
			"missing_heat_sample": regional.environment.samples.player.erase("heat_tenths")
			"false_heat_sample": regional.environment.samples.player.heat_tenths += 1
			"old_environment": regional.environment.version = 1
		var bad_before: String = _canonical(bad)
		runner.assert_true(WorldSessionSnapshot.stage(adapter, bad).is_empty(), "current field candidate rejects " + kind)
		runner.assert_true(adapter.world_sim == live and live.map_data == terrain, "rejected field candidate retains original owners: " + kind)
		runner.assert_eq(_canonical(WorldSessionSnapshot.capture(adapter)), before, "rejected field leaves the complete live session unchanged: " + kind)
		runner.assert_eq(GameClock.to_dict(), clock, "rejected field leaves the shared clock unchanged: " + kind)
		runner.assert_eq(_canonical(bad), bad_before, "candidate validation does not repair malformed input: " + kind)
	_fixtures._dispose(fixture)
