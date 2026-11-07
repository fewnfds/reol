extends RefCounted
## Current saved-future coverage: tests/sim/test_source_care.gd.
## Actual older source histories remain immutable and are refused.

const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")
const ARCHIVES: Dictionary = {
	"res://tests/fixtures/session_v37.json": "64c9ee3cf0bfa3cd8bf012a1461f8c2b0992740d4907cd1d8de7b66886bd030a",
	"res://tests/fixtures/session_v37_inspection.json": "3dd9795a3acef897120af35cb7389537d6337c2366e929a2b48d1587ac2e2fa3",
}


func run(runner: Object) -> void:
	LegacyRejection.run(runner, ARCHIVES, ["source_care"], [30, 31, 32, 33, 34], [], [2])
	_current_opening(runner)
	print("SCENARIO retired source-care archives: genuine histories are refused; current opening and strict domains remain valid")


func _current_opening(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary opening initializes its current source arrangements")
		main.free()
		GameClock.restore_state(clock)
		return
	var live: RegionalSimulation = runtime.world_sim
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var state: Dictionary = snapshot.continuity.world.source_care
	var arrangement: bool = false
	for key: String in SimSourceCare.empty_state():
		if state.get(key) is Dictionary and not state[key].is_empty():
			arrangement = true
	runner.assert_true(arrangement, "ordinary opening explicitly creates bounded care arrangements")
	var staged: Dictionary = WorldSessionSnapshot.stage(runtime, snapshot)
	runner.assert_true(not staged.is_empty() and staged.get("world") != live, "current opening stages as an independent world")
	if not staged.is_empty():
		runner.assert_eq(_json(staged.world.source_care.to_dict()), _json(snapshot.continuity.world.source_care), "current arrangement survives independent staging")
	runner.assert_true(runtime.world_sim == live, "independent staging leaves the current live owner intact")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), _json(snapshot), "independent staging leaves the complete live opening intact")
	main.free()
	GameClock.restore_state(clock)


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
