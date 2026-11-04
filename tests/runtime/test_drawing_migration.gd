extends RefCounted
const HerbMigration = preload("res://tests/runtime/test_herb_ecology_migration.gd")
## The three immutable v40 saves are ordinary in-flight histories, not hand-built
## drawings. Migration may change only envelope versions, never invent mastery.

const ARCHIVES: Dictionary = {
	"session_v40.json": "383717fbed1a214a2e0d3e38ae4ff495a4d9b33666ff245fdb75e0900649a8b1",
	"session_v40_take.json": "8a97fabf282c80a69cd718496a92889dfd30aa97be0ca728c4b17f2d065d4d02",
	"session_v40_npc.json": "27186018991b78ee1201e2d1286e16af206c72d7d3e9289cdf328fc40acbf7c0",
}
const RING: String = "stele_drawing_ring"


func run(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var path: String = "user://tests/drawing_migration_%d.json" % Time.get_ticks_usec()
	for name: String in ARCHIVES:
		var source_path: String = "res://tests/fixtures/" + name
		var original: String = FileAccess.get_file_as_string(source_path)
		var source: Dictionary = JSON.parse_string(original)
		runner.assert_eq(FileAccess.get_sha256(source_path), ARCHIVES[name], "drawing migration uses the immutable genuine v40 source: " + name)
		var error: Error = runtime.load_game(ProjectSettings.globalize_path(source_path))
		runner.assert_eq(error, OK, "ordinary loader accepts the genuine v40 field history: " + name)
		if error != OK:
			continue
		var current: Dictionary = WorldSessionSnapshot.capture(runtime)
		runner.assert_eq(int(current.schema_version), SessionSaveSchema.VERSION, "old root migrates to the current root version")
		runner.assert_eq(int(current.continuity.world.version), RegionalSimulation.SCHEMA_VERSION, "old regional owner migrates to the current version")
		runner.assert_eq(int(current.continuity.world.artifacts.version), SimArtifacts.VERSION, "old artifact envelope migrates to the current version")
		runner.assert_eq(_json(current.continuity.world.field_opportunities), _json(source.continuity.world.field_opportunities), "old field state and its real route or slot are untouched")
		var projected: Dictionary = HerbMigration.prior_thermal_world(current.continuity.world, source.continuity.world)
		runner.assert_eq(SnapshotValues.normalized(projected.private_exchange), SnapshotValues.normalized(SimPrivateExchange.empty_state()), "old field history gains no invented private exchange, consent, or receipt")
		projected.erase("private_exchange")
		projected.version = source.continuity.world.version
		projected.artifacts.version = source.continuity.world.artifacts.version
		runner.assert_eq(_json(projected), _json(source.continuity.world), "migration preserves all existing objects, personal evidence, active work and original qi")
		runner.assert_eq(_json(HerbMigration.prior_village(current.simulation, source.simulation)), _json(source.simulation), "migration preserves the original body and inventory state")
		runner.assert_eq(_json(current.clock), _json(source.clock), "migration preserves the shared clock and pending wait")
		for event: Dictionary in current.continuity.world.artifacts.events:
			runner.assert_true(event.kind != "use_learned", "old artifact history receives no invented ring use")
		runner.assert_true(not runtime.world_sim.artifacts.describe("player", RING).get("method", false), "old possession or outer shape gives no new use mastery")
		var before: String = _json(current)
		var forged: Dictionary = current.duplicate(true)
		forged.continuity.world.artifacts.version = source.continuity.world.artifacts.version
		_reject(runtime, forged, path, before, runner, "current root refuses an old artifact envelope")
		forged = current.duplicate(true)
		forged.continuity.world = source.continuity.world.duplicate(true)
		_reject(runtime, forged, path, before, runner, "current root refuses an old regional envelope")
		forged = source.duplicate(true)
		forged.continuity.world.artifacts.version = SimArtifacts.VERSION
		_reject(runtime, forged, path, before, runner, "root 40 cannot smuggle a modern artifact envelope")
		runner.assert_eq(FileAccess.get_file_as_string(source_path), original, "migration and refused candidates never rewrite the source: " + name)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.free()
	GameClock.restore_state(saved_clock)
	print("SCENARIO drawing migration: three genuine v40 histories retain every object, body, event and clock; mixed versions cannot replace the live session")


func _reject(runtime: WorldContinuityRuntime, candidate: Dictionary, path: String, before: String, runner: Object, label: String) -> void:
	var input: String = _json(candidate)
	runner.assert_eq(SimSaveStore.save_file(path, candidate), OK, label + " fixture write")
	runner.assert_eq(runtime.load_game(path), ERR_INVALID_DATA, label)
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, label + " leaves the entire live session unchanged")
	runner.assert_eq(_json(candidate), input, label + " does not repair its supplied candidate")


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
