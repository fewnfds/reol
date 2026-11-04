extends RefCounted
## Immutable in-flight v41 research and draw histories predate private exchange.

const HerbMigration = preload("res://tests/runtime/test_herb_ecology_migration.gd")
const ARCHIVES: Dictionary = {
	"session_v41_research.json": {"sha256": "bb08013411cdf841521107aeb3941636d117369004d1f7d3a9ee8b63d46c6fbc", "verb": "use_research"},
	"session_v41_draw.json": {"sha256": "a814606c6b8a9666267378ce7ad104fabbb3d1fbe7c2d340bec7ed3583e66143", "verb": "draw"},
}


func run(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary main initializes before private exchange migration")
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var path: String = "user://tests/private_exchange_migration_%d.json" % Time.get_ticks_usec()
	for name: String in ARCHIVES:
		var source_path: String = "res://tests/fixtures/" + name
		var bytes: String = FileAccess.get_file_as_string(source_path)
		var source: Dictionary = JSON.parse_string(bytes)
		var expected: Dictionary = ARCHIVES[name]
		runner.assert_eq(FileAccess.get_sha256(source_path), str(expected.sha256), "v41 migration uses the immutable independently recorded source: " + name)
		runner.assert_eq(int(source.schema_version), 41, "genuine source has its original root version: " + name)
		runner.assert_eq(int(source.continuity.world.version), 37, "genuine source has its original regional version: " + name)
		runner.assert_eq(int(source.continuity.world.artifacts.version), 5, "genuine source has its original artifact envelope: " + name)
		runner.assert_eq(str(source.continuity.world.artifacts.active.player.verb), str(expected.verb), "genuine source keeps its actual in-flight ring action: " + name)
		var original: String = _json(source)
		var upgraded: Dictionary = SessionSaveSchema.upgrade(source, runtime._home._content)
		runner.assert_true(not upgraded.is_empty(), "genuine v41 source has an explicit private-exchange migration: " + name)
		if upgraded.is_empty():
			continue
		runner.assert_eq(int(upgraded.schema_version), SessionSaveSchema.VERSION, "old root advances to the current version")
		runner.assert_eq(int(upgraded.continuity.world.version), RegionalSimulation.SCHEMA_VERSION, "old regional envelope advances explicitly")
		runner.assert_eq(int(upgraded.continuity.world.artifacts.version), SimArtifacts.VERSION, "old artifact envelope advances explicitly")
		runner.assert_eq(_json(upgraded.continuity.world.private_exchange), _json(SimPrivateExchange.empty_state()), "migration adds no proposal, consent, occupation, payment or transfer")
		var projected: Dictionary = upgraded.duplicate(true)
		var prior_world: Dictionary = HerbMigration.prior_thermal_world(upgraded.continuity.world, source.continuity.world)
		runner.assert_true(not prior_world.is_empty(), "private exchange archive retains the explicit empty-field conversion and established ecology: " + name)
		if prior_world.is_empty():
			continue
		projected.continuity.world = prior_world
		projected.simulation = HerbMigration.prior_village(upgraded.simulation, source.simulation)
		# The root now explicitly records the frozen v42 definitions. Remove only
		# that new envelope field when comparing all original v41 facts.
		projected.erase("content_bundle")
		projected.erase("assembly")
		runner.assert_eq(upgraded.world.terrain_overrides, [], "old v41 archive gains only the empty current terrain delta: " + name)
		projected.world.erase("terrain_overrides")
		projected.continuity.world.erase("private_exchange")
		projected.schema_version = source.schema_version
		projected.continuity.world.version = source.continuity.world.version
		projected.continuity.world.artifacts.version = source.continuity.world.artifacts.version
		runner.assert_eq(_json(projected), original, "after projecting the explicit new content/domain envelopes and thermal schema additions, every original session field remains unchanged: " + name)
		runner.assert_eq(_json(source), original, "pure migration never repairs or modifies its input")
		var loaded: Error = runtime.load_game(ProjectSettings.globalize_path(source_path))
		runner.assert_eq(loaded, OK, "ordinary loader accepts the actual in-flight v41 source: " + name)
		if loaded != OK:
			continue
		var current: Dictionary = WorldSessionSnapshot.capture(runtime)
		runner.assert_eq(_json(current.continuity.world), _json(upgraded.continuity.world), "ordinary load keeps the entire migrated regional world")
		runner.assert_eq(_json(HerbMigration.prior_village(current.simulation, source.simulation)), _json(source.simulation), "after explicit village and ecology version projection, ordinary load preserves the original body and inventory")
		runner.assert_eq(_json(current.clock), _json(source.clock), "ordinary load preserves the common clock and in-flight instant")
		var before: String = _json(current)
		var live: RegionalSimulation = runtime.world_sim
		var forged: Dictionary = current.duplicate(true)
		forged.continuity.world.erase("private_exchange")
		_reject(runtime, forged, path, before, live, runner, "current root cannot omit the private exchange domain")
		forged = current.duplicate(true)
		forged.continuity.world.artifacts.version = 5
		_reject(runtime, forged, path, before, live, runner, "current root cannot wrap an old artifact envelope")
		forged = current.duplicate(true)
		forged.continuity.world.version = 37
		_reject(runtime, forged, path, before, live, runner, "current root cannot wrap an old regional envelope")
		forged = source.duplicate(true)
		forged.continuity.world["private_exchange"] = SimPrivateExchange.empty_state()
		_reject(runtime, forged, path, before, live, runner, "old root cannot smuggle even an empty modern domain")
		forged = source.duplicate(true)
		forged.continuity.world.artifacts.version = SimArtifacts.VERSION
		_reject(runtime, forged, path, before, live, runner, "old root cannot smuggle a modern artifact envelope")
		runner.assert_eq(FileAccess.get_file_as_string(source_path), bytes, "migration and rejection preserve all genuine source bytes: " + name)
		_remove(path)
	main.free()
	GameClock.restore_state(saved_clock)
	print("SCENARIO private exchange migration: two real v41 in-flight histories, explicit empty domain and artifact envelope, atomic rejection of mixed versions")


func _reject(runtime: WorldContinuityRuntime, candidate: Dictionary, path: String, before: String, live: RegionalSimulation, runner: Object, label: String) -> void:
	var input: String = _json(candidate)
	runner.assert_eq(SimSaveStore.save_file(path, candidate), OK, label + " temporary candidate write")
	runner.assert_eq(runtime.load_game(path), ERR_INVALID_DATA, label)
	runner.assert_true(runtime.world_sim == live, label + " retains the original live authority")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, label + " preserves the entire live session")
	runner.assert_eq(_json(candidate), input, label + " never repairs the supplied candidate")


func _remove(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
