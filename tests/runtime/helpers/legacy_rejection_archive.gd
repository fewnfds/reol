extends RefCounted
## Actual retired archives remain immutable and cannot replace a live session.


static func run(runner: Object, archives: Dictionary, missing_domains: Array[String] = [], old_regions: Array[int] = [], old_artifacts: Array[int] = [], old_conflicts: Array[int] = []) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary main initializes before old archive rejection")
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var live: RegionalSimulation = runtime.world_sim
	var terrain: WorldMapData = live.map_data
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	if snapshot.is_empty():
		runner.assert_true(false, "capture a real current session before rejection")
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var before: String = _json(snapshot)
	for path: String in archives:
		var original: String = FileAccess.get_file_as_string(path)
		var sha: String = FileAccess.get_sha256(path)
		var expected_sha: String = str(archives[path])
		if not expected_sha.is_empty():
			runner.assert_eq(sha, expected_sha, "historical fixture retains its recorded hash: " + path)
		var parsed: Variant = JSON.parse_string(original)
		if original.is_empty() or not parsed is Dictionary:
			runner.assert_true(false, "historical fixture is a readable actual archive: " + path)
			continue
		var source: Dictionary = parsed
		var input: String = _json(source)
		runner.assert_eq(SessionSaveSchema.rejection_reason(source.get("schema_version")), SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT, "actual archive identifies the retired environment: " + path)
		runner.assert_true(SessionSaveSchema.upgrade(source).is_empty(), "actual old archive cannot enter the current schema: " + path)
		runner.assert_true(WorldSessionSnapshot.stage(runtime, source).is_empty(), "old candidate cannot stage into the current world: " + path)
		runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(path)), ERR_INVALID_DATA, "ordinary loader rejects the actual old archive: " + path)
		runner.assert_eq(_json(source), input, "rejected candidate is not rewritten in memory: " + path)
		runner.assert_eq(FileAccess.get_file_as_string(path), original, "rejected archive bytes are unchanged: " + path)
		runner.assert_eq(FileAccess.get_sha256(path), sha, "rejected archive hash is unchanged: " + path)
		_assert_live(runner, runtime, live, terrain, before, path)
		# Keep the mixed-envelope probes formerly coupled to successful imports.
		# The old root remains the reason to reject; no domain may revive it.
		if source.get("continuity") is Dictionary and source.continuity.get("world") is Dictionary:
			var old_world: Dictionary = source.continuity.world
			var mixed_region: Dictionary = snapshot.duplicate(true)
			mixed_region.continuity.world = old_world.duplicate(true)
			_reject_current(runner, runtime, live, terrain, before, mixed_region, "current root with old regional world from " + path)
			for domain: String in missing_domains:
				var mixed_domain: Dictionary = source.duplicate(true)
				mixed_domain.continuity.world[domain] = snapshot.continuity.world[domain].duplicate(true)
				_reject_current(runner, runtime, live, terrain, before, mixed_domain, "old root with current " + domain + " from " + path)
			if not old_artifacts.is_empty() and old_world.get("artifacts") is Dictionary:
				var mixed_artifact: Dictionary = source.duplicate(true)
				mixed_artifact.continuity.world.artifacts.version = SimArtifacts.VERSION
				_reject_current(runner, runtime, live, terrain, before, mixed_artifact, "old root with current artifact envelope from " + path)
	for domain: String in missing_domains:
		var bad: Dictionary = snapshot.duplicate(true)
		bad.continuity.world.erase(domain)
		_reject_current(runner, runtime, live, terrain, before, bad, "missing " + domain)
	for version: int in old_regions:
		var bad: Dictionary = snapshot.duplicate(true)
		bad.continuity.world.version = version
		_reject_current(runner, runtime, live, terrain, before, bad, "old regional version %d" % version)
	for version: int in old_artifacts:
		var bad: Dictionary = snapshot.duplicate(true)
		bad.continuity.world.artifacts.version = version
		_reject_current(runner, runtime, live, terrain, before, bad, "old artifact version %d" % version)
	for version: int in old_conflicts:
		var bad: Dictionary = snapshot.duplicate(true)
		bad.continuity.world.conflicts.version = version
		_reject_current(runner, runtime, live, terrain, before, bad, "old conflict version %d" % version)
	main.free()
	GameClock.restore_state(saved_clock)


static func _reject_current(runner: Object, runtime: WorldContinuityRuntime, live: RegionalSimulation, terrain: WorldMapData, before: String, bad: Dictionary, label: String) -> void:
	var candidate: String = _json(bad)
	runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "current candidate rejects " + label)
	runner.assert_eq(_json(bad), candidate, "validation does not repair " + label)
	var path: String = _unused_path()
	if path.is_empty():
		runner.assert_true(false, "allocate an unused temporary candidate path")
		return
	var written: Error = SimSaveStore.save_file(path, bad)
	runner.assert_eq(written, OK, "write malformed current candidate: " + label)
	if written == OK:
		var bytes: String = FileAccess.get_file_as_string(path)
		runner.assert_eq(runtime.load_game(path), ERR_INVALID_DATA, "ordinary loader rejects " + label)
		runner.assert_eq(FileAccess.get_file_as_string(path), bytes, "rejection preserves candidate file: " + label)
	_assert_live(runner, runtime, live, terrain, before, label)
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


static func _unused_path() -> String:
	for attempt: int in 100:
		var path: String = "user://tests/legacy_rejection_%d_%d.json" % [Time.get_ticks_usec(), attempt]
		var occupied: bool = false
		for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
			if FileAccess.file_exists(path + suffix):
				occupied = true
				break
		if not occupied:
			return path
	return ""


static func _assert_live(runner: Object, runtime: WorldContinuityRuntime, live: RegionalSimulation, terrain: WorldMapData, before: String, label: String) -> void:
	runner.assert_true(runtime.world_sim == live and runtime.world_sim.map_data == terrain, "rejection retains live owners: " + label)
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, "rejection preserves complete live session: " + label)


static func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
