extends RefCounted
## New arrangements are explicit content; actual old worlds never gain them.

const ARCHIVE: String = "res://tests/fixtures/session_v36.json"
const SOURCE_SHA: String = "c26b67a75d5ad39d3579c2fda49496a2208b2b9c9c2b64e03a791f52ec8edd73"
const FUTURE_MS: int = 134050


func run(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	var source_bytes: String = FileAccess.get_file_as_string(ARCHIVE)
	var source: Dictionary = JSON.parse_string(source_bytes)
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SOURCE_SHA, "source-loan migration uses the immutable genuine v36 hidden-walk archive")
	var expected: String = ""
	for attempt: int in 2:
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var runtime: WorldContinuityRuntime = main._continuity
		if runtime == null or runtime.world_sim == null:
			runner.assert_true(false, "ordinary main initializes before source-loan migration")
			main.free()
			continue
		var path: String = "user://tests/source_loan_migration_%d_%d.json" % [Time.get_ticks_usec(), attempt]
		var bad_path: String = path + ".bad.json"
		var opening: Dictionary = WorldSessionSnapshot.capture(runtime)
		runner.assert_eq(int(opening.schema_version), SessionSaveSchema.VERSION, "new explicit opening writes the current root format")
		runner.assert_eq(int(opening.continuity.world.version), RegionalSimulation.SCHEMA_VERSION, "new explicit opening writes the current regional format")
		runner.assert_true(not runtime.world_sim.site_affairs.cases.is_empty(), "ordinary new main explicitly installs the local source arrangement")
		runner.assert_true(runtime.world_sim.site_affairs.notes.is_empty(), "new public arrangement grants no signed borrowing before an actual request")
		runner.assert_eq(runtime.save_game(path), OK, "ordinary saver captures the explicit new arrangement for a real return load")
		var opening_json: String = _canonical(WorldSessionSnapshot.capture(runtime))
		var loaded: Error = runtime.load_game(ProjectSettings.globalize_path(ARCHIVE))
		runner.assert_eq(loaded, OK, "ordinary loader accepts the genuine pre-arrangement v36 world")
		if loaded == OK:
			var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
			runner.assert_eq(int(snapshot.schema_version), SessionSaveSchema.VERSION, "real v36 envelope explicitly migrates to the current root version")
			runner.assert_eq(int(snapshot.continuity.world.version), RegionalSimulation.SCHEMA_VERSION, "real v36 regional envelope explicitly migrates to the current version")
			runner.assert_eq(_canonical(runtime.world_sim.site_affairs.to_dict()), _canonical(SimSiteAffairs.empty_state()), "old load adds only empty affairs, without past announcements, permits, observations or returns")
			var projected: Dictionary = snapshot.continuity.world.duplicate(true)
			runner.assert_eq(SnapshotValues.normalized(projected.field_opportunities), SnapshotValues.normalized(SimFieldOpportunities.empty_state()), "historical world gains no invented field site, visitor or treasure")
			projected.erase("field_opportunities")
			runner.assert_eq(_canonical(projected.capability_practice), _canonical(SimCapabilityPractice.empty_state()), "old source-loan archive gains no invented advanced practice or cost history")
			projected.erase("capability_practice")
			runner.assert_eq(int(projected.spirit_sources.version), SimSpiritSources.VERSION, "old source-loan archive explicitly reaches the current joint source-cost format")
			projected.spirit_sources.version = source.continuity.world.spirit_sources.version
			for field: String in ["qi_baselines", "records"]:
				for row: Dictionary in projected.spirit_sources[field].values():
					runner.assert_eq(int(row.practice_floor), 1, "pre-practice source-loan archive skips no future real practice costs")
					row.erase("practice_floor")
			projected.version = 32
			projected.artifacts.version = source.continuity.world.artifacts.version
			projected.erase("site_affairs")
			runner.assert_eq(_canonical(projected.source_care), _canonical(SimSourceCare.empty_state()), "old perception archive gains no imagined source care")
			projected.erase("source_care")
			projected.conflicts.version = 2
			for encounter: Dictionary in projected.conflicts.conflicts.values():
				runner.assert_true(encounter.cause.is_empty(), "old perception encounter has no invented care cause")
				encounter.erase("cause")
			runner.assert_eq(_canonical(projected), _canonical(source.continuity.world), "affairs migration preserves every prior world fact including genuine old sight and paid actions")
			runner.assert_eq(_canonical(snapshot.simulation), _canonical(source.simulation), "affairs migration adds no local bodies, original items, source energy or institutional credit")
			var forged: Dictionary = source.duplicate(true)
			forged.continuity.world["site_affairs"] = SimSiteAffairs.empty_state()
			_reject(runtime, bad_path, forged, runner, "historical v36 envelope cannot smuggle a modern empty affairs field")
			forged = snapshot.duplicate(true)
			forged.continuity.world.erase("site_affairs")
			_reject(runtime, bad_path, forged, runner, "modern missing affairs cannot silently use legacy supplementation")
			for historical: int in [30, 31, 32, 33, 34]:
				forged = snapshot.duplicate(true)
				forged.continuity.world.version = historical
				_reject(runtime, bad_path, forged, runner, "current root cannot wrap historical regional version %d and erase domain history" % historical)
			GameClock.advance_msec(FUTURE_MS - GameClock.elapsed_ms)
			runner.assert_eq(runtime.world_sim.site_affairs.to_dict(), SimSiteAffairs.empty_state(), "ordinary old-world continuation does not auto-install the new opening when people act")
			var future: Dictionary = WorldSessionSnapshot.capture(runtime)
			runner.assert_true(not WorldSessionSnapshot.stage(runtime, future).is_empty(), "actual old conflict future stays independently valid after empty affairs migration")
			var future_json: String = _canonical(future)
			if attempt == 0:
				expected = future_json
			else:
				runner.assert_eq(future_json, expected, "independent main scenes produce the same full actual old future with no imagined arrangement")
		runner.assert_eq(runtime.load_game(path), OK, "same ordinary scene returns from the old archive to its saved new opening")
		runner.assert_eq(_canonical(WorldSessionSnapshot.capture(runtime)), opening_json, "new-old-new replacement restores the explicit new case exactly once without cross-world stale evidence")
		_remove(path)
		_remove(bad_path)
		main.free()
	runner.assert_eq(FileAccess.get_file_as_string(ARCHIVE), source_bytes, "ordinary migration and new-old-new replacement never overwrite the genuine old archive")
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SOURCE_SHA, "genuine old source bytes and SHA remain unchanged")
	GameClock.restore_state(clock)
	print("SCENARIO source-loan migration: explicit new arrangement, genuine v36 unchanged facts, empty old-world affairs, modern/historical envelope rejection, original future and new-old-new replacement")


func _reject(runtime: WorldContinuityRuntime, path: String, forged: Dictionary, runner: Object, label: String) -> void:
	var before: String = _canonical(WorldSessionSnapshot.capture(runtime))
	var live: RegionalSimulation = runtime.world_sim
	var map_data: WorldMapData = live.map_data
	runner.assert_eq(SimSaveStore.save_file(path, forged), OK, label + " writes an otherwise readable JSON candidate")
	runner.assert_true(runtime.load_game(path) != OK, label + " is rejected by the ordinary loader")
	runner.assert_true(runtime.world_sim == live and runtime.world_sim.map_data == map_data, label + " preserves the original live world and map owners")
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(runtime)), before, label + " changes no original time, affairs, body, resource, action or memory")


func _canonical(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _remove(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
