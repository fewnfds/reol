extends RefCounted
## Current saved-future coverage: tests/sim/test_source_loan.gd.
## Actual older source histories remain immutable and are refused.

const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")
const ARCHIVES: Dictionary = {
	"res://tests/fixtures/session_v36.json": "c26b67a75d5ad39d3579c2fda49496a2208b2b9c9c2b64e03a791f52ec8edd73",
}


func run(runner: Object) -> void:
	LegacyRejection.run(runner, ARCHIVES, ["site_affairs"], [30, 31, 32, 33, 34], [], [])
	_current_opening(runner)
	print("SCENARIO retired source-loan archives: genuine histories are refused; current opening and strict domains remain valid")


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
	runner.assert_true(not snapshot.continuity.world.site_affairs.cases.is_empty(), "ordinary opening explicitly creates source arrangements")
	runner.assert_true(snapshot.continuity.world.site_affairs.notes.is_empty(), "an opening alone grants no signed borrowing")
	var staged: Dictionary = WorldSessionSnapshot.stage(runtime, snapshot)
	runner.assert_true(not staged.is_empty() and staged.get("world") != live, "current opening stages as an independent world")
	if not staged.is_empty():
		runner.assert_eq(_json(staged.world.site_affairs.to_dict()), _json(snapshot.continuity.world.site_affairs), "current arrangement survives independent staging")
	runner.assert_true(runtime.world_sim == live, "independent staging leaves the current live owner intact")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), _json(snapshot), "independent staging leaves the complete live opening intact")
	main.free()
	GameClock.restore_state(clock)


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
