extends RefCounted
## Genuine histories stay intact; the new practice begins only in their future.

const ARCHIVES: Dictionary = {
	"session_v38.json": "79c390a681a1c711b6dc3044bc5d79718b539e5916899187e3132c051a9d6067",
	"session_v38_explained.json": "88f040041a96b6210af07bdb5ac2cc65e1be8a881709f0174dd56b4d69c16ca3",
	"session_v38_conflict.json": "c45d885fe93a4e5057685d89eb08b3e2d38bf93c6ac022ae14f9af4716257ea2",
}


func run(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var path: String = "user://tests/capability_migration_%d.json" % Time.get_ticks_usec()
	for name: String in ARCHIVES:
		var source_path: String = "res://tests/fixtures/" + name
		var original: String = FileAccess.get_file_as_string(source_path)
		var source: Dictionary = JSON.parse_string(original)
		runner.assert_eq(FileAccess.get_sha256(source_path), ARCHIVES[name], "practice migration starts from immutable genuine source: " + name)
		var error: Error = runtime.load_game(ProjectSettings.globalize_path(source_path))
		runner.assert_eq(error, OK, "ordinary loader accepts actual warning, explanation or paid conflict: " + name)
		if error != OK:
			continue
		var current: Dictionary = WorldSessionSnapshot.capture(runtime)
		runner.assert_eq(int(current.schema_version), SessionSaveSchema.VERSION, "genuine old root explicitly migrates")
		runner.assert_eq(int(current.continuity.world.version), RegionalSimulation.SCHEMA_VERSION, "genuine old region explicitly migrates")
		runner.assert_eq(_json(current.continuity.world.capability_practice), _json(SimCapabilityPractice.empty_state()), "old history gains no imagined training or mastery")
		runner.assert_true(not runtime.world_sim.capability_practice.learned("player"), "knowing old qi guard never grants new mobile use")
		var projected: Dictionary = current.continuity.world.duplicate(true)
		runner.assert_eq(SnapshotValues.normalized(projected.field_opportunities), SnapshotValues.normalized(SimFieldOpportunities.empty_state()), "historical world gains no invented field site, visitor or treasure")
		projected.erase("field_opportunities")
		projected.erase("capability_practice")
		projected.version = 34
		projected.spirit_sources.version = 2
		for baseline: Dictionary in projected.spirit_sources.qi_baselines.values():
			runner.assert_eq(int(baseline.practice_floor), 1, "old qi checkpoints start before any future practice spending")
			baseline.erase("practice_floor")
		for record: Dictionary in projected.spirit_sources.records.values():
			runner.assert_eq(int(record.practice_floor), 1, "old source record sees no invented practice")
			record.erase("practice_floor")
		runner.assert_eq(_json(projected), _json(source.continuity.world), "only explicit empty domain and payment floor differ; all actual old world facts remain")
		runner.assert_eq(_json(current.simulation), _json(source.simulation), "migration changes no original body, inventory or personal memory")
		runner.assert_eq(_json(current.clock), _json(source.clock), "migration changes no shared clock or pending wait")
		var before: String = _json(current)
		var forged: Dictionary = current.duplicate(true)
		forged.continuity.world.erase("capability_practice")
		_reject(runtime, forged, path, before, runner, "modern root cannot omit practice")
		forged = current.duplicate(true)
		forged.continuity.world = source.continuity.world.duplicate(true)
		_reject(runtime, forged, path, before, runner, "modern root cannot invoke old regional migration")
		forged = source.duplicate(true)
		forged.continuity.world["capability_practice"] = SimCapabilityPractice.empty_state()
		_reject(runtime, forged, path, before, runner, "old root cannot smuggle a modern domain")
		runner.assert_eq(FileAccess.get_file_as_string(source_path), original, "migration and rejection preserve actual archive bytes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.free()
	GameClock.restore_state(saved_clock)


func _reject(runtime: WorldContinuityRuntime, candidate: Dictionary, path: String, before: String, runner: Object, label: String) -> void:
	runner.assert_eq(SimSaveStore.save_file(path, candidate), OK, label + " fixture write")
	runner.assert_eq(runtime.load_game(path), ERR_INVALID_DATA, label)
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, label + " leaves the whole live session intact")


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
