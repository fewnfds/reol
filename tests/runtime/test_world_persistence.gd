extends RefCounted
## Exploration and real in-flight actions resume together on the ordinary world.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	_test_exploration_boundaries(runner)
	_test_joint_exploration_and_atomic_rejection(runner)
	_test_legacy_archives_are_refused(runner)
	_test_current_fresh_scene_roundtrip(runner)


func _test_exploration_boundaries(runner: Object) -> void:
	var world := Fixtures.FlatWorld.new()
	var fog := FogOfWar.new()
	fog.setup(world, Vector2i(10, 10))
	var before: Dictionary = fog.exploration_to_dict()
	runner.assert_true(FogOfWar.is_valid_exploration(before), "actual visible cells serialize as valid exploration")
	fog.set_focus(Vector2i(70, 70))
	fog.update_now()
	runner.assert_true(fog.is_explored(Vector2i(70, 70)), "a later visit creates real exploration")
	runner.assert_true(fog.restore_exploration(before, Vector2i(10, 10)), "saved exploration restores")
	runner.assert_true(not fog.is_explored(Vector2i(70, 70)), "later footprints are absent from an earlier save")
	runner.assert_true(fog.is_cell_visible(Vector2i(10, 10)), "current visibility is recomputed at restored focus")
	runner.assert_eq(fog.exploration_to_dict(), before, "repeated visibility updates do not expand saved memory")
	var size: int = ReolWorld.WORLD_SIZE * ReolWorld.WORLD_SIZE
	var boundary: Dictionary = {"encoding": FogOfWar.EXPLORATION_ENCODING, "runs": [[0, 1], [size - 1, 1]]}
	runner.assert_true(fog.restore_exploration(boundary, Vector2i(10, 10)), "first and last world cells are valid memories")
	runner.assert_true(fog.is_explored(Vector2i.ZERO) and fog.is_explored(Vector2i(511, 511)), "world boundary memory is retained")
	for runs: Variant in [
		[[0, 0]], [[-1, 2]], [[size, 1]], [[size - 1, 2]], [[1.5, 2]],
		[[0, 2], [1, 2]], [[0, 2], [2, 2]], [[4, 1], [0, 1]], [[0, 1, 2]], [[true, 1]], [[0, INF]], "bad",
	]:
		var invalid: Dictionary = {"encoding": FogOfWar.EXPLORATION_ENCODING, "runs": runs}
		var unchanged: Dictionary = fog.exploration_to_dict()
		runner.assert_true(not fog.restore_exploration(invalid, Vector2i(10, 10)), "malformed or noncanonical exploration is rejected: %s" % str(runs))
		runner.assert_eq(fog.exploration_to_dict(), unchanged, "failed exploration restore cannot clear live memory")
	fog.free()
	world.free()


func _test_joint_exploration_and_atomic_rejection(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var fog := FogOfWar.new()
	fog.setup(fixture.world, fixture.player.cell)
	fixture.home._fog = fog
	GameClock.advance_ticks(27)
	runtime.travel_to("river")
	GameClock.advance_msec(100)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var path: String = "user://tests/exploration_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(SimSaveStore.save_file(path, snapshot), OK, "joint snapshot with exploration writes through existing atomic store")
	fog.set_focus(Vector2i(85, 85))
	fog.update_now()
	GameClock.advance_ticks(20)
	runner.assert_eq(runtime.load_game(path), OK, "joint world and exploration load together")
	runner.assert_true(not fog.is_explored(Vector2i(85, 85)), "successful joint load removes future exploration")
	runner.assert_eq(fog.exploration_to_dict(), snapshot.world.exploration, "saved exploration is restored exactly")
	var invalids: Array[Dictionary] = []
	var bad: Dictionary = snapshot.duplicate(true)
	bad.world.generator_version = 99
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.world.seed += 1
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.world.exploration.runs = [[262143, 2]]
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.erase("world")
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.schema_version = 99
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.schema_version = 1
	bad.erase("content_bundle")
	bad.erase("assembly")
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.world.exploration = FogOfWar.empty_exploration()
	bad.clock.tick_index = -1
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.continuity.world.erase("embodiment")
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.continuity.world.embodiment.controls["body:player"].erase("motion")
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.schema_version = 2
	bad.erase("content_bundle")
	bad.erase("assembly")
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.continuity.world.erase("artifacts")
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.schema_version = 3
	bad.erase("content_bundle")
	bad.erase("assembly")
	invalids.append(bad)
	for invalid: Dictionary in invalids:
		var before: String = JSON.stringify(WorldSessionSnapshot.capture(runtime), "", true, true)
		runner.assert_eq(SimSaveStore.save_file(path, invalid), OK, "negative fixture remains structurally valid JSON")
		runner.assert_true(runtime.load_game(path) != OK, "incompatible or corrupt world/session data is rejected")
		runner.assert_eq(JSON.stringify(WorldSessionSnapshot.capture(runtime), "", true, true), before, "failed joint load preserves clock, actors, cargo and fog")
	_remove_test_save(path)
	fixture.home._fog = null
	fog.free()
	fixtures._dispose(fixture)


func _test_legacy_archives_are_refused(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary scene initializes for original archive rejection")
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var live_world: RegionalSimulation = runtime.world_sim
	var live_content: ReolContentDB = runtime._home._content
	var live_map: WorldMapData = live_world.map_data
	var before: String = _snapshot(runtime)
	var clock: String = _canonical(GameClock.to_dict())
	var archives: Array[Dictionary] = [
		{"path": "res://tests/fixtures/session_v1.json", "version": 1},
		{"path": "res://tests/fixtures/session_v2.json", "version": 2},
		{"path": "res://tests/fixtures/session_v3.json", "version": 3},
		{"path": "res://tests/fixtures/session_v4.json", "version": 4},
		{"path": "res://tests/fixtures/session_v5.json", "version": 5},
		{"path": "res://tests/fixtures/session_v6.json", "version": 6},
		{"path": "res://tests/fixtures/session_v7.json", "version": 7},
		{"path": "res://tests/fixtures/session_v8.json", "version": 8},
		{"path": "res://tests/fixtures/session_v9.json", "version": 9},
		{"path": "res://tests/fixtures/session_v10.json", "version": 10},
		{"path": "res://tests/fixtures/overload_v10.json", "version": 10},
	]
	for entry: Dictionary in archives:
		var path: String = str(entry.path)
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		runner.assert_true(not bytes.is_empty() and parsed is Dictionary, "the original archive is readable: " + path)
		if not parsed is Dictionary:
			continue
		var source: Dictionary = parsed
		var before_source: String = _canonical(source)
		runner.assert_eq(int(source.get("schema_version", -1)), int(entry.version), "the source retains its real original version: " + path)
		runner.assert_eq(SessionSaveSchema.rejection_reason(source.get("schema_version")), SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT, "the old format has the explicit environment rejection: " + path)
		runner.assert_true(WorldSessionSnapshot.stage(runtime, source).is_empty(), "the old archive cannot stage a fabricated current environment: " + path)
		runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(path)), ERR_INVALID_DATA, "ordinary loading refuses the old archive: " + path)
		runner.assert_eq(runtime._notice, "旧环境格式不再支持，存档未改；请新开局。", "the old archive explains the rejection: " + path)
		runner.assert_true(runtime.world_sim == live_world and runtime._home._content == live_content and runtime.world_sim.map_data == live_map, "the old archive leaves the live owners untouched: " + path)
		runner.assert_eq(_canonical(GameClock.to_dict()), clock, "the old archive leaves the shared clock unchanged: " + path)
		runner.assert_eq(_snapshot(runtime), before, "the old archive leaves every live session fact unchanged: " + path)
		runner.assert_eq(_canonical(source), before_source, "staging does not mutate the original archive: " + path)
		runner.assert_eq(FileAccess.get_file_as_bytes(path), bytes, "ordinary loading never overwrites the original archive: " + path)
	main.free()
	GameClock.restore_state(saved_clock)


func _test_current_fresh_scene_roundtrip(runner: Object) -> void:
	# The other current-domain suites keep the detailed coverage formerly tied
	# to old archives: artifact_understanding_runtime, avian_life_runtime,
	# player_avatar, conflict_mobility, sparring_runtime, world_continuity_runtime
	# and test_artifacts. This test exercises a real opening and full replacement.
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var path: String = "user://tests/world_current_%d.json" % Time.get_ticks_usec()
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary scene initializes for current world persistence")
		_cleanup(main, path, saved_clock)
		return
	var selected: bool = main._avatar.choose("subject:player")
	runner.assert_true(selected, "the real opening chooses the original human body")
	if not selected:
		_cleanup(main, path, saved_clock)
		return
	var stone_cell: Vector2i = runtime.world_sim.artifacts.object_cell("hearth_stone")
	var travelled: bool = runtime.travel_to("home", stone_cell)
	runner.assert_true(travelled, "the ordinary travel command starts a real approach to the original object")
	if not travelled:
		_cleanup(main, path, saved_clock)
		return
	GameClock.advance_msec(137)
	runner.assert_true(not runtime.player_journey.is_empty(), "the player remains on the real path at the fractional checkpoint")
	if runtime.player_journey.is_empty():
		_cleanup(main, path, saved_clock)
		return
	var saved: Error = runtime.save_game(path)
	runner.assert_eq(saved, OK, "current travel and the rest of the world save together")
	if saved != OK:
		_cleanup(main, path, saved_clock)
		return
	var present: String = _snapshot(runtime)
	var present_point: Vector2 = main.player.motion.position
	var present_clock: int = GameClock.elapsed_ms
	GameClock.advance_msec(10000)
	runner.assert_true(runtime.player_journey.is_empty(), "the original journey reaches the real object")
	var arrival: String = _snapshot(runtime)
	main.free()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	main = packed.instantiate()
	runner.root.add_child(main)
	runtime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "the replacement scene initializes before journey restore")
		_cleanup(main, path, saved_clock)
		return
	var loaded: Error = runtime.load_game(path)
	runner.assert_eq(loaded, OK, "a new scene restores the current in-flight journey")
	if loaded != OK:
		_cleanup(main, path, saved_clock)
		return
	runner.assert_eq(GameClock.elapsed_ms, present_clock, "scene replacement restores the exact shared time")
	runner.assert_eq(main.player.motion.position, present_point, "scene replacement restores the same original body position")
	runner.assert_eq(_snapshot(runtime), present, "all bodies, objects, memory, exploration and time match the checkpoint")
	GameClock.advance_msec(10000)
	runner.assert_eq(_snapshot(runtime), arrival, "the complete journey and other world domains have the same fresh-scene future")
	if not runtime.player_journey.is_empty():
		runner.assert_true(false, "restored approach must finish before the real follow-up action")
		_cleanup(main, path, saved_clock)
		return
	var adapter: WorldObjectsRuntime = runtime.object_adapter
	var viewed: bool = adapter.select_object("hearth_stone")
	runner.assert_true(viewed, "the arrived player can actually see the original object")
	if not viewed:
		_cleanup(main, path, saved_clock)
		return
	var world: RegionalSimulation = runtime.world_sim
	var study: Dictionary = _start_after_object_work(runtime, adapter, "study")
	var study_context: Dictionary = {
		"reply": study, "clock_ms": GameClock.elapsed_ms,
		"world_ms": world.elapsed_ms, "target_ms": world.target_ms,
		"player_cell": runtime.controlled_cell(), "object_cell": world.artifacts.object_cell("hearth_stone"),
		"object": world.artifacts.objects.get("hearth_stone", {}),
		"artifact_actions": world.artifacts.active,
		"player_action": world.regions.home.actors.player.active,
	}
	runner.assert_true(bool(study.get("ok", false)), "the real object interface begins personal study: " + str(study_context))
	if not bool(study.get("ok", false)):
		_cleanup(main, path, saved_clock)
		return
	var domain: SimArtifacts = runtime.world_sim.artifacts
	var study_due: int = int(domain.active.player.due_ms)
	GameClock.advance_msec(study_due - GameClock.elapsed_ms)
	var learned: bool = bool(domain.describe("player", "hearth_stone").method)
	runner.assert_true(learned, "real completed study establishes the player's own use knowledge")
	if not learned:
		_cleanup(main, path, saved_clock)
		return
	var qi_before: int = int(runtime._home.simulation.actors.player.qi)
	var force: Dictionary = _start_after_object_work(runtime, adapter, "force")
	runner.assert_true(bool(force.get("ok", false)), "the actual object interface starts an overload: " + str(force))
	if not bool(force.get("ok", false)):
		_cleanup(main, path, saved_clock)
		return
	var job: Dictionary = domain.active.player.duplicate(true)
	var paid_qi: int = int(runtime._home.simulation.actors.player.qi)
	runner.assert_eq(paid_qi, qi_before - int(domain.definitions.verbs.force.qi), "the original action spends its qi exactly when accepted")
	GameClock.advance_msec(447)
	runner.assert_true(domain.active.has("player"), "the overload remains in flight at its fractional checkpoint")
	saved = runtime.save_game(path)
	runner.assert_eq(saved, OK, "the ordinary current save includes the original in-flight overload")
	if saved != OK:
		_cleanup(main, path, saved_clock)
		return
	present = _snapshot(runtime)
	var remaining: int = int(job.due_ms) - GameClock.elapsed_ms
	if remaining <= 0:
		runner.assert_true(false, "the overload checkpoint precedes its actual due time")
		_cleanup(main, path, saved_clock)
		return
	GameClock.advance_msec(remaining)
	runner.assert_eq(int(domain.objects.hearth_stone.damage), int(domain.definitions.types.warm_stone.damage_max), "the original weak seam fractures at completion")
	runner.assert_eq(int(domain.objects.hearth_stone.charge), 0, "the same original object loses its stored charge")
	runner.assert_eq(int(runtime._home.simulation.actors.player.qi), paid_qi, "completion does not spend the accepted qi twice")
	var future: String = _snapshot(runtime)
	main.free()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	main = packed.instantiate()
	runner.root.add_child(main)
	runtime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "the replacement scene initializes before overload restore")
		_cleanup(main, path, saved_clock)
		return
	loaded = runtime.load_game(path)
	runner.assert_eq(loaded, OK, "a new scene restores the actual in-flight overload")
	if loaded != OK:
		_cleanup(main, path, saved_clock)
		return
	domain = runtime.world_sim.artifacts
	runner.assert_eq(_snapshot(runtime), present, "the paid action and original object are restored with the complete current world")
	runner.assert_true(domain.active.has("player") and str(domain.active.player.id) == str(job.id), "load retains the same single pending action identity")
	runner.assert_eq(int(runtime._home.simulation.actors.player.qi), paid_qi, "loading does not charge the action again")
	GameClock.advance_msec(remaining)
	runner.assert_eq(_snapshot(runtime), future, "a fresh scene reaches the same fracture, resources and full world future")
	runner.assert_eq(int(domain.objects.hearth_stone.damage), int(domain.definitions.types.warm_stone.damage_max), "the restored single object retains its completed physical outcome")
	runner.assert_eq(int(runtime._home.simulation.actors.player.qi), paid_qi, "resuming the action does not pay twice")
	var completed: String = _snapshot(runtime)
	saved = runtime.save_game(path)
	runner.assert_eq(saved, OK, "the completed object and its history save as current state")
	if saved == OK:
		GameClock.advance_msec(1000)
		loaded = runtime.load_game(path)
		runner.assert_eq(loaded, OK, "the completed current state reloads")
		if loaded == OK:
			runner.assert_eq(_snapshot(runtime), completed, "a completed effect is restored, not executed a second time")
			runner.assert_true(not runtime.world_sim.artifacts.active.has("player"), "completed overload is not resurrected as an active job")
	_cleanup(main, path, saved_clock)
	print("SCENARIO world persistence: old archives rejected; actual current travel, paid action and completed object survive scene replacement")


func _start_after_object_work(runtime: WorldContinuityRuntime, adapter: WorldObjectsRuntime, verb: String) -> Dictionary:
	# Another resident can legitimately have reached the unique stone first.
	# Wait only for an actual active holder's deadline; never cancel the NPC,
	# skip its work, or turn a different refusal into a silent retry.
	var result: Dictionary = {}
	for _attempt: int in 4:
		result = adapter.submit(verb)
		if bool(result.get("ok", false)) or str(result.get("line", "")) != "有人正在操作它，请稍等。":
			return result
		var due: int = SimInventory.MAX_COUNT
		for job: Dictionary in runtime.world_sim.artifacts.active.values():
			if str(job.get("object", "")) == "hearth_stone" or str(job.get("draw", {}).get("target", "")) == "hearth_stone":
				due = mini(due, int(job.get("due_ms", SimInventory.MAX_COUNT)))
		var before: int = GameClock.elapsed_ms
		if due <= before or due == SimInventory.MAX_COUNT or due - before > 1800000:
			return result
		GameClock.advance_msec(due - before)
		if GameClock.elapsed_ms != due:
			return {"ok": false, "line": "等待正在使用器物的角色时，共同时间未到达原截止点。", "prior": result}
	return result


func _cleanup(main: Node, path: String, saved_clock: Dictionary) -> void:
	if is_instance_valid(main):
		main.free()
	_remove_test_save(path)
	GameClock.restore_state(saved_clock)


func _remove_test_save(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _snapshot(runtime: WorldContinuityRuntime) -> String:
	return _canonical(WorldSessionSnapshot.capture(runtime))


func _canonical(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
