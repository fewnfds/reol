extends RefCounted
## Real v39 training and conflict histories gain no imagined field adventures.

const ARCHIVES: Dictionary = {
	"session_v39.json": "396fe171bc0384335bece4120fa7ac4e7aecfee0cd1f8c3629909d1cf0976bab",
	"session_v39_guard.json": "fe8629a5aa8ea068adc2112720801bfaa9538562c566f57cabcd6acc8f382f2e",
}


func run(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var path: String = "user://tests/field_opportunity_migration_%d.json" % Time.get_ticks_usec()
	for name: String in ARCHIVES:
		var source_path: String = "res://tests/fixtures/" + name
		var original: String = FileAccess.get_file_as_string(source_path)
		var source: Dictionary = JSON.parse_string(original)
		runner.assert_eq(FileAccess.get_sha256(source_path), ARCHIVES[name], "field migration starts from immutable genuine source: " + name)
		var error: Error = runtime.load_game(ProjectSettings.globalize_path(source_path))
		runner.assert_eq(error, OK, "ordinary loader accepts actual ongoing practice or moving guard: " + name)
		if error != OK:
			continue
		var current: Dictionary = WorldSessionSnapshot.capture(runtime)
		runner.assert_eq(int(current.schema_version), SessionSaveSchema.VERSION, "genuine old root explicitly migrates")
		runner.assert_eq(int(current.continuity.world.version), RegionalSimulation.SCHEMA_VERSION, "genuine old region explicitly migrates")
		runner.assert_eq(_json(current.continuity.world.field_opportunities), _json(SimFieldOpportunities.empty_state()), "old history gains no invented site, traveler or treasure")
		var projected: Dictionary = current.continuity.world.duplicate(true)
		runner.assert_eq(SnapshotValues.normalized(projected.private_exchange), SnapshotValues.normalized(SimPrivateExchange.empty_state()), "historical world gains no invented private exchange, consent, or receipt")
		projected.erase("private_exchange")
		projected.erase("field_opportunities")
		projected.version = 35
		projected.artifacts.version = source.continuity.world.artifacts.version
		runner.assert_eq(_json(projected), _json(source.continuity.world), "only explicit empty field domain differs; all existing bodies, abilities, costs and life remain")
		runner.assert_eq(_json(current.simulation), _json(source.simulation), "migration changes no original body, inventory or personal memory")
		runner.assert_eq(_json(current.clock), _json(source.clock), "migration changes no shared clock or pending wait")
		var before: String = _json(current)
		var forged: Dictionary = current.duplicate(true)
		forged.continuity.world.erase("field_opportunities")
		_reject(runtime, forged, path, before, runner, "modern root cannot omit field state")
		forged = current.duplicate(true)
		forged.continuity.world = source.continuity.world.duplicate(true)
		_reject(runtime, forged, path, before, runner, "modern root cannot invoke old regional migration")
		forged = source.duplicate(true)
		forged.continuity.world["field_opportunities"] = SimFieldOpportunities.empty_state()
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
