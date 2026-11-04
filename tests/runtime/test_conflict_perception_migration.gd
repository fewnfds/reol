extends RefCounted
## A genuine v35 preparation gains no imagined past sight on a modern load.

const ARCHIVE: String = "res://tests/fixtures/session_v35.json"
const SOURCE_SHA: String = "b0765c3a7147ce6789b6211fa4d1f222646a4086e2b47594fa8ab4d32e4dd37f"
const ENCOUNTER: String = "conflict:encounter:1"
const FUTURE_MS: int = 126500


func run(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	var bytes: String = FileAccess.get_file_as_string(ARCHIVE)
	var source: Dictionary = JSON.parse_string(bytes)
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SOURCE_SHA, "perception migration starts from the independently frozen real v35 preparation")
	var expected: String = ""
	for attempt: int in 2:
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var runtime: WorldContinuityRuntime = main._continuity
		if runtime == null or runtime.world_sim == null:
			runner.assert_true(false, "ordinary main initializes before perception migration")
			main.free()
			continue
		var path: String = "user://tests/perception_migration_%d_%d.json" % [Time.get_ticks_usec(), attempt]
		var bad_path: String = path + ".bad.json"
		var opening_path: String = path + ".opening.json"
		runner.assert_eq(runtime.save_game(opening_path), OK, "ordinary saver preserves the independent modern opening")
		var opening: String = _canonical(WorldSessionSnapshot.capture(runtime))
		var future: String = _replay(runtime, source, path, bad_path, runner)
		runner.assert_true(not future.is_empty(), "real perception migration reaches its full continuation: %d" % attempt)
		if attempt == 0:
			expected = future
		else:
			runner.assert_eq(future, expected, "independently initialized main scenes produce the identical joint world after old sight activation and a modern reload")
		runner.assert_eq(runtime.load_game(opening_path), OK, "the same scene returns from the real old conflict to its saved modern opening")
		runner.assert_eq(_canonical(WorldSessionSnapshot.capture(runtime)), opening, "old-to-new replacement clears old sight and all unrelated session state without duplicating bodies or costs")
		_remove(path)
		_remove(bad_path)
		_remove(opening_path)
		main.free()
	runner.assert_eq(FileAccess.get_file_as_string(ARCHIVE), bytes, "perception migration never overwrites the old real paid-preparation fixture")
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SOURCE_SHA, "the old conflict fixture remains byte-identical after all modern and rejected loads")
	GameClock.restore_state(clock)
	print("SCENARIO perception migration: actual v35 paid preparation, explicit present activation and unknown past, first future sight, historical checkpoint save/load, rejection atomicity and independent full futures")


func _replay(runtime: WorldContinuityRuntime, source: Dictionary, path: String, bad_path: String, runner: Object) -> String:
	var error: Error = runtime.load_game(ProjectSettings.globalize_path(ARCHIVE))
	runner.assert_eq(error, OK, "ordinary main loader accepts the actual pre-perception session")
	if error != OK:
		return ""
	var world: RegionalSimulation = runtime.world_sim
	var domain: SimConflicts = world.conflicts
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_eq(int(snapshot.schema_version), SessionSaveSchema.VERSION, "old real preparation migrates through the explicit current root version")
	runner.assert_eq(int(world.to_dict().version), RegionalSimulation.SCHEMA_VERSION, "old real preparation migrates through the explicit current regional version")
	runner.assert_eq(int(domain.to_dict().version), SimConflicts.VERSION, "old real conflict reaches the current explicit conflict version")
	runner.assert_eq(int(domain.to_dict().perception_since_ms), 125200, "perception starts at the saved actual instant, never the imagined beginning of the fight")
	runner.assert_eq(GameClock.elapsed_ms, 125200, "migration neither advances nor rewinds the world")
	runner.assert_eq(_canonical(snapshot.simulation), _canonical(source.simulation), "migration leaves every original local body, inventory, claim and unfinished occupation intact")
	var projected: Dictionary = domain.to_dict()
	projected.version = 1
	projected.erase("perception_since_ms")
	for encounter: Dictionary in projected.conflicts.values():
		runner.assert_true(encounter.cause.is_empty(), "old encounter gains no invented source-care cause")
		encounter.erase("cause")
		for person: Dictionary in encounter.people.values():
			runner.assert_true(person.sight.is_empty(), "migration adds no remembered position even though the old opponents currently stand in sight")
			person.erase("sight")
	runner.assert_eq(_canonical(projected), _canonical(source.continuity.world.conflicts), "all original actions, payment identities, lessons, flight, guards and withdrawal facts survive without reinterpretation")
	runner.assert_eq(int(domain.body("player").qi), 17, "already paid original spell remains paid once")
	var forged: Dictionary = source.duplicate(true)
	forged.continuity.world.conflicts["perception_since_ms"] = 125200
	_reject(runtime, bad_path, forged, runner, "legacy v1 domain cannot smuggle a modern activation marker")
	forged = source.duplicate(true)
	forged.continuity.world.conflicts.conflicts[ENCOUNTER].people.player["sight"] = {}
	_reject(runtime, bad_path, forged, runner, "legacy v1 person cannot smuggle even an empty modern sight record")
	forged = snapshot.duplicate(true)
	forged.continuity.world.conflicts.erase("perception_since_ms")
	_reject(runtime, bad_path, forged, runner, "modern state cannot silently invent a missing activation boundary")
	forged = snapshot.duplicate(true)
	forged.continuity.world.conflicts.perception_since_ms = 125201
	_reject(runtime, bad_path, forged, runner, "perception cannot start in the future")
	_advance(runtime, 125249, runner)
	for person: Dictionary in domain.conflicts[ENCOUNTER].people.values():
		runner.assert_true(person.sight.is_empty(), "a query or sub-boundary advance cannot fabricate past observations")
	_advance(runtime, 125251, runner)
	var people: Dictionary = domain.conflicts[ENCOUNTER].people
	for actor: String in people:
		var sight: Dictionary = people[actor].sight
		runner.assert_true(not sight.is_empty(), "first real future conflict boundary supplies physically visible sight: " + actor)
		if not sight.is_empty():
			runner.assert_eq(int(sight.at_ms), 125250, "last sight retains the real common-boundary observation time: " + actor)
			runner.assert_eq(int(sight.level), world.map_data.get_elevation(SimRouteTravel.cell(domain.body(actor).cell)), "sight belongs to the observer's actual height: " + actor)
	var remembered: Dictionary = domain.to_dict()
	runner.assert_eq(runtime.save_game(path), OK, "ordinary saver writes the actual previous-boundary sight checkpoint")
	var present: String = _canonical(WorldSessionSnapshot.capture(runtime))
	forged = WorldSessionSnapshot.capture(runtime)
	forged.continuity.world.version = 31
	forged.continuity.world.conflicts.version = 1
	forged.continuity.world.conflicts.erase("perception_since_ms")
	for encounter: Dictionary in forged.continuity.world.conflicts.conflicts.values():
		for person: Dictionary in encounter.people.values():
			person.erase("sight")
	_reject(runtime, bad_path, forged, runner, "current root cannot downgrade its regional state and erase saved sight through legacy migration")
	forged = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/session_v34.json"))
	forged.schema_version = SessionSaveSchema.VERSION
	forged["content_bundle"] = runtime._home._content.content_bundle()
	_reject(runtime, bad_path, forged, runner, "current root cannot smuggle genuine regional v30 state through standalone conflict compatibility")
	forged = WorldSessionSnapshot.capture(runtime)
	forged.continuity.world = []
	_reject(runtime, bad_path, forged, runner, "current root requires a dictionary regional world rather than malformed compatibility input")
	var standalone: Dictionary = WorldSessionSnapshot.capture(runtime)
	standalone.erase("continuity")
	runner.assert_eq(_canonical(SessionSaveSchema.upgrade(standalone)), _canonical(standalone), "current single-region envelope retains its explicit no-continuity semantics")
	forged = WorldSessionSnapshot.capture(runtime)
	forged.continuity.world.conflicts.conflicts[ENCOUNTER].people.player.erase("sight")
	_reject(runtime, bad_path, forged, runner, "modern participants cannot omit their explicit unknown-or-known sight state")
	forged = WorldSessionSnapshot.capture(runtime)
	forged.continuity.world.conflicts.conflicts[ENCOUNTER].people.player.sight.at_ms = 125199
	_reject(runtime, bad_path, forged, runner, "remembered sight cannot predate explicit perception activation")
	forged = WorldSessionSnapshot.capture(runtime)
	forged.continuity.world.conflicts.conflicts[ENCOUNTER].people.player.sight.at_ms = 125252
	_reject(runtime, bad_path, forged, runner, "remembered sight cannot come from the future")
	forged = WorldSessionSnapshot.capture(runtime)
	var sight: Dictionary = forged.continuity.world.conflicts.conflicts[ENCOUNTER].people.player.sight
	sight.position = [float(sight.observer_position[0]) + float(domain.rules.sight_radius) + 1.0, float(sight.observer_position[1])]
	_reject(runtime, bad_path, forged, runner, "historical sight must fit its recorded observer's real finite sight range")
	forged = WorldSessionSnapshot.capture(runtime)
	forged.continuity.world.conflicts.conflicts[ENCOUNTER].people.player.sight.level = 4
	_reject(runtime, bad_path, forged, runner, "historical sight cannot invent a height outside the world's bounded layers")
	forged = WorldSessionSnapshot.capture(runtime)
	forged.continuity.world.conflicts.conflicts[ENCOUNTER].people.player.sight["omniscient_target"] = "shi_tou"
	_reject(runtime, bad_path, forged, runner, "a bounded sight checkpoint cannot smuggle an extra global target channel")
	_advance(runtime, FUTURE_MS, runner)
	var expected: String = _canonical(WorldSessionSnapshot.capture(runtime))
	runner.assert_eq(runtime.load_game(path), OK, "ordinary loader restores the genuine last-seen checkpoint between conflict boundaries")
	if GameClock.elapsed_ms != 125251:
		runner.assert_true(false, "sight restore resumes the exact saved fractional time")
		return ""
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(runtime)), present, "ordinary sight reload preserves the complete saved present")
	runner.assert_eq(_canonical(runtime.world_sim.conflicts.to_dict()), _canonical(remembered), "reading a checkpoint does not refresh it from the target's current position")
	_advance(runtime, FUTURE_MS, runner)
	var future: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_eq(_canonical(future), expected, "saved old observation and direct continuation reach the identical full joint future")
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, future).is_empty(), "continued sight, actual costs, flight and bodily results remain independently valid")
	return _canonical(future)


func _advance(runtime: WorldContinuityRuntime, target_ms: int, runner: Object) -> void:
	GameClock.advance_msec(target_ms - GameClock.elapsed_ms)
	var home: VillageRuntime = runtime.home_runtime()
	home._sync_actor_views(true)
	if home._fog != null:
		home._fog.set_focus(runtime.controlled_cell())
		home._fog.update_now()
	runtime.conflict_adapter.refresh()
	runner.assert_true(GameClock.elapsed_ms == target_ms and runtime.world_sim.elapsed_ms == target_ms and runtime.world_sim.target_ms == target_ms, "perception replay shares the original clock and regional boundary")


func _reject(runtime: WorldContinuityRuntime, path: String, forged: Dictionary, runner: Object, label: String) -> void:
	var before: String = _canonical(WorldSessionSnapshot.capture(runtime))
	var live: RegionalSimulation = runtime.world_sim
	var terrain: WorldMapData = live.map_data
	runner.assert_eq(SimSaveStore.save_file(path, forged), OK, label + " writes an ordinary readable candidate")
	runner.assert_true(runtime.load_game(path) != OK, label + " is rejected by the ordinary loader")
	runner.assert_true(runtime.world_sim == live and runtime.world_sim.map_data == terrain, label + " retains the original live owners")
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(runtime)), before, label + " changes no sight, clock, position, action, cost, injury or stock")


func _canonical(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _remove(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
