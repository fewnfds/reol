extends RefCounted
## Current finite sight, bad observations and independent future are exercised
## in tests/sim/test_conflict_perception.gd from a current world.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")
const ARCHIVES: Dictionary = {
	"res://tests/fixtures/session_v34.json": "07e4a64c2e8415afd912220b3c017bd269947c52c0a23d1536b0888d9f090c78",
	"res://tests/fixtures/session_v35.json": "b0765c3a7147ce6789b6211fa4d1f222646a4086e2b47594fa8ab4d32e4dd37f",
}
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	LegacyRejection.run(runner, ARCHIVES, [], [30, 31], [], [1])
	_current_envelopes(runner)
	print("SCENARIO retired perception archives: actual old records are refused and current single-region and activation envelopes remain strict")


func _current_envelopes(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var live: RegionalSimulation = runtime.world_sim
	var terrain: WorldMapData = live.map_data
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var before: String = _json(snapshot)
	for fault: String in ["missing_activation", "future_activation", "malformed_world"]:
		var bad: Dictionary = snapshot.duplicate(true)
		match fault:
			"missing_activation": bad.continuity.world.conflicts.erase("perception_since_ms")
			"future_activation": bad.continuity.world.conflicts.perception_since_ms = int(bad.clock.elapsed_ms) + 1
			"malformed_world": bad.continuity.world = []
		var input: String = _json(bad)
		runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "current perception envelope rejects " + fault)
		runner.assert_true(runtime.world_sim == live and live.map_data == terrain, "bad envelope preserves the live authorities: " + fault)
		runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, "bad envelope preserves the entire live session: " + fault)
		runner.assert_eq(_json(bad), input, "validation never repairs the candidate: " + fault)
	var standalone: Dictionary = snapshot.duplicate(true)
	standalone.erase("continuity")
	runner.assert_true(SessionSaveSchema.upgrade(standalone).is_empty(), "removing continuity cannot leave a joint assembly pretending to be standalone")
	standalone.assembly = ReolWorldAssemblyInputs.standalone(standalone.simulation.config)
	runner.assert_eq(_json(SessionSaveSchema.upgrade(standalone)), _json(standalone), "current standalone envelope retains explicit no-continuity semantics")
	_fixtures._dispose(fixture)


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
