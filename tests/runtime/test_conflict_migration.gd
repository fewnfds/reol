extends RefCounted
## Current equivalent source continuity is in test_spirit_source_continuity.gd;
## capped source output is in tests/sim/test_spirit_sources.gd. The actual
## in-flight staffed exchange and future are in test_workplace_runtime.gd.

const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")
const ARCHIVES: Dictionary = {
	"res://tests/fixtures/session_v34.json": "07e4a64c2e8415afd912220b3c017bd269947c52c0a23d1536b0888d9f090c78",
	"res://tests/fixtures/session_v34_workplace_exchange.json": "59528cf90f23e8b0215b692e86e122589d4500012cf87edb66d06ab50881dca2",
}


func run(runner: Object) -> void:
	LegacyRejection.run(runner, ARCHIVES, ["conflicts"], [30], [4])
	_current_opening_and_candidates(runner)
	print("SCENARIO retired conflict predecessors: source and staffed exchange archives are refused; current opening and cross-domain candidates remain strict")


func _current_opening_and_candidates(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary conflict opening initializes")
		main.free()
		GameClock.restore_state(clock)
		return
	var live: RegionalSimulation = runtime.world_sim
	var terrain: WorldMapData = live.map_data
	runner.assert_true(live.artifacts.objects.has("training_sword") and live.artifacts.objects.has("river_training_sword"), "current opening explicitly contains both original physical weapons")
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var before: String = _json(snapshot)
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, snapshot).is_empty(), "current conflict opening stages independently")
	for fault: String in ["unbacked_hit", "skipped_health_source", "private_register"]:
		var bad: Dictionary = snapshot.duplicate(true)
		match fault:
			"unbacked_hit": bad.continuity.world.conflicts.next_hit_id = 2
			"skipped_health_source": bad.continuity.world.health.conflict_source_floor = 2
			"private_register":
				bad.simulation.places.records.workspace.fixtures.register.institution = "private_notebook"
				bad.continuity.world.regions.home.places.records.workspace.fixtures.register.institution = "private_notebook"
		var input: String = _json(bad)
		runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "current conflict candidate rejects " + fault)
		runner.assert_true(runtime.world_sim == live and live.map_data == terrain, "rejected candidate retains original world and map: " + fault)
		runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, "rejected candidate leaves the complete live session intact: " + fault)
		runner.assert_eq(_json(bad), input, "candidate validation does not repair " + fault)
	main.free()
	GameClock.restore_state(clock)


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
