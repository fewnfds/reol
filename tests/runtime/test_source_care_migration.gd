extends RefCounted
## Actual old borrowing and real inspection remain their own unchanged worlds.

const LOAN: String = "res://tests/fixtures/session_v37.json"
const LOAN_SHA: String = "64c9ee3cf0bfa3cd8bf012a1461f8c2b0992740d4907cd1d8de7b66886bd030a"
const INSPECTION: String = "res://tests/fixtures/session_v37_inspection.json"
const INSPECTION_SHA: String = "3dd9795a3acef897120af35cb7389537d6337c2366e929a2b48d1587ac2e2fa3"
const LoanReplay = preload("res://tests/runtime/helpers/source_loan_replay.gd")


func run(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	var source_bytes: Dictionary = {LOAN: FileAccess.get_file_as_string(LOAN), INSPECTION: FileAccess.get_file_as_string(INSPECTION)}
	runner.assert_eq(FileAccess.get_sha256(LOAN), LOAN_SHA, "care migration starts from the actual immutable v37 source-in-progress archive")
	runner.assert_eq(FileAccess.get_sha256(INSPECTION), INSPECTION_SHA, "care migration starts from the actual immutable v37 inspector-in-progress archive")
	var expected: Dictionary = {}
	for attempt: int in 2:
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var runtime: WorldContinuityRuntime = main._continuity
		if runtime == null or runtime.world_sim == null:
			runner.assert_true(false, "ordinary main initializes before care migration")
			main.free()
			continue
		var path: String = "user://tests/source_care_migration_%d_%d.json" % [Time.get_ticks_usec(), attempt]
		var bad_path: String = path + ".bad.json"
		var new_snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
		runner.assert_eq(int(new_snapshot.schema_version), SessionSaveSchema.VERSION, "new explicit care opening writes the current root schema")
		runner.assert_eq(int(new_snapshot.continuity.world.version), RegionalSimulation.SCHEMA_VERSION, "new explicit care opening writes the current regional schema")
		runner.assert_true(_has_arrangements(new_snapshot.continuity.world.source_care), "ordinary main explicitly assembles a bounded care arrangement")
		runner.assert_eq(runtime.save_game(path), OK, "ordinary saver preserves the independent explicit new care opening")
		var opening: String = _canonical(WorldSessionSnapshot.capture(runtime))
		for archive: String in [LOAN, INSPECTION]:
			var source: Dictionary = JSON.parse_string(source_bytes[archive])
			var loaded: Error = runtime.load_game(ProjectSettings.globalize_path(archive))
			runner.assert_eq(loaded, OK, "ordinary loader restores genuine pre-care partial work: " + archive)
			if loaded != OK:
				continue
			_assert_migration(runtime, source, bad_path, runner)
			var future: String = _continue_original(runtime, source, archive, runner)
			if attempt == 0:
				expected[archive] = future
			else:
				runner.assert_eq(future, expected.get(archive, ""), "independent main loaders preserve the same complete old-world future without invented care: " + archive)
			runner.assert_eq(runtime.load_game(path), OK, "same ordinary scene returns from the pre-care archive to its genuine explicit new opening")
			runner.assert_eq(_canonical(WorldSessionSnapshot.capture(runtime)), opening, "old-to-new replacement restores only its own care arrangement and no stale warning or source process")
		_remove(path)
		_remove(bad_path)
		main.free()
	for archive: String in source_bytes:
		runner.assert_eq(FileAccess.get_file_as_string(archive), source_bytes[archive], "care migration never overwrites genuine original work: " + archive)
	runner.assert_eq(FileAccess.get_sha256(LOAN), LOAN_SHA, "real old source fixture remains byte-identical after care migration")
	runner.assert_eq(FileAccess.get_sha256(INSPECTION), INSPECTION_SHA, "real old inspection fixture remains byte-identical after care migration")
	GameClock.restore_state(clock)
	print("SCENARIO care migration: actual v37 loan and inspector archives, explicit empty old care/cause, retained original arrangements and unfinished work, modern-envelope refusal and identical independent futures")


func _has_arrangements(state: Dictionary) -> bool:
	var empty: Dictionary = SimSourceCare.empty_state()
	for key: String in empty:
		if empty[key] is Dictionary and state.get(key) is Dictionary and not state[key].is_empty():
			return true
	return false


func _assert_migration(runtime: WorldContinuityRuntime, source: Dictionary, bad_path: String, runner: Object) -> void:
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var world: RegionalSimulation = runtime.world_sim
	runner.assert_eq(int(snapshot.schema_version), SessionSaveSchema.VERSION, "genuine old envelope upgrades through the explicit care-root migration")
	runner.assert_eq(int(snapshot.continuity.world.version), RegionalSimulation.SCHEMA_VERSION, "genuine old world upgrades through the explicit care-region migration")
	runner.assert_eq(_canonical(world.source_care.to_dict()), _canonical(SimSourceCare.empty_state()), "old world gains only empty care, with no imagined duties, sightings, warnings or explanations")
	runner.assert_eq(_canonical(world.site_affairs.to_dict()), _canonical(source.continuity.world.site_affairs), "care migration preserves every real old signed promise, source association and inspection fact")
	var projected: Dictionary = snapshot.continuity.world.duplicate(true)
	runner.assert_eq(SnapshotValues.normalized(projected.field_opportunities), SnapshotValues.normalized(SimFieldOpportunities.empty_state()), "historical world gains no invented field site, visitor or treasure")
	projected.erase("field_opportunities")
	runner.assert_eq(_canonical(projected.capability_practice), _canonical(SimCapabilityPractice.empty_state()), "old care archive gains no invented practice or advanced capability")
	projected.erase("capability_practice")
	runner.assert_eq(int(projected.spirit_sources.version), SimSpiritSources.VERSION, "old care archive explicitly reaches the current joint source-cost format")
	projected.spirit_sources.version = source.continuity.world.spirit_sources.version
	for field: String in ["qi_baselines", "records"]:
		for row: Dictionary in projected.spirit_sources[field].values():
			runner.assert_eq(int(row.practice_floor), 1, "pre-practice care archive skips no future real practice costs")
			row.erase("practice_floor")
	projected.erase("source_care")
	projected.version = 33
	projected.conflicts.version = 2
	for encounter: Dictionary in projected.conflicts.conflicts.values():
		runner.assert_true(encounter.cause.is_empty(), "old actual encounter gains no invented care-warning cause")
		encounter.erase("cause")
	runner.assert_eq(_canonical(projected), _canonical(source.continuity.world), "care migration preserves all existing original world facts after explicit new-field projection")
	runner.assert_eq(_canonical(snapshot.simulation), _canonical(source.simulation), "care migration adds no body, equipment, source energy, local social record or duty")
	runner.assert_eq(GameClock.elapsed_ms, int(source.clock.elapsed_ms), "care migration does not advance either old in-progress clock")
	var forged: Dictionary = source.duplicate(true)
	forged.continuity.world["source_care"] = SimSourceCare.empty_state()
	_reject(runtime, bad_path, forged, runner, "historical old envelope cannot smuggle even an empty modern care field")
	forged = snapshot.duplicate(true)
	forged.continuity.world.erase("source_care")
	_reject(runtime, bad_path, forged, runner, "modern missing care cannot invoke old supplementation")
	forged = snapshot.duplicate(true)
	forged.continuity.world.conflicts.version = 2
	for encounter: Dictionary in forged.continuity.world.conflicts.conflicts.values():
		encounter.erase("cause")
	_reject(runtime, bad_path, forged, runner, "current care envelope cannot erase conflict cause using an old conflict format")
	for historical: int in [30, 31, 32, 33, 34]:
		forged = snapshot.duplicate(true)
		forged.continuity.world.version = historical
		_reject(runtime, bad_path, forged, runner, "current care root cannot wrap historical regional version %d" % historical)


func _continue_original(runtime: WorldContinuityRuntime, source: Dictionary, archive: String, runner: Object) -> String:
	var world: RegionalSimulation = runtime.world_sim
	if archive == LOAN:
		var helper := LoanReplay.new()
		var suffix: String = "care_old_%d" % Time.get_ticks_usec()
		var result: Dictionary = helper.replay_loan(runtime, suffix)
		runner.assert_true(bool(result.get("ok", false)), "ordinary original commands finish the actual old partial source and original return loop: " + str(result.get("error", "")))
		world = runtime.world_sim
	else:
		var active: String = str(world.services.active_jobs.get("chen_shouzhuo", ""))
		runner.assert_true(not active.is_empty(), "real old inspector archive retains the original executing officer")
		if not active.is_empty():
			var job: Dictionary = world.services.jobs[active]
			runner.assert_eq(job.kind, "site_return", "old saved officer still owns the original return-inspection service")
			runner.assert_eq(job.options.requester, "player", "old inspector and original applicant remain distinct during care migration")
		var limit: int = GameClock.elapsed_ms + 600000
		while world.services.owns_actor("chen_shouzhuo") and GameClock.elapsed_ms < limit:
			GameClock.advance_msec(1000)
		runner.assert_true(not world.services.owns_actor("chen_shouzhuo"), "old actual inspector completes its original finite route and registration without new care")
		runner.assert_true(world.site_affairs.notes["site:note:1"].closed_ms != -1, "old actual inspector completes the original public-equipment obligation")
		GameClock.advance_msec(60000)
	runner.assert_eq(_canonical(world.source_care.to_dict()), _canonical(SimSourceCare.empty_state()), "continuing an old world never auto-installs care from a matching case, place or resident")
	runner.assert_eq(world.artifacts.objects.size(), source.continuity.world.artifacts.objects.size(), "care migration and actual continuation create no replacement original objects")
	var future: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, future).is_empty(), "actual pre-care continuation remains independently valid with all original owners")
	return _canonical(future)


func _reject(runtime: WorldContinuityRuntime, path: String, forged: Dictionary, runner: Object, label: String) -> void:
	var before: String = _canonical(WorldSessionSnapshot.capture(runtime))
	var live: RegionalSimulation = runtime.world_sim
	var map_data: WorldMapData = live.map_data
	runner.assert_eq(SimSaveStore.save_file(path, forged), OK, label + " is a readable candidate")
	runner.assert_true(runtime.load_game(path) != OK, label + " is rejected by the normal candidate boundary")
	runner.assert_true(runtime.world_sim == live and runtime.world_sim.map_data == map_data, label + " preserves original live world and map owners")
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(runtime)), before, label + " leaves original time, work, cases, permits, sources and memories unchanged")


func _canonical(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _remove(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
