extends RefCounted
## The ordinary request page, body controller and joint file boundary agree.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
var fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_actual_body_care(runner)
	_legacy_rejection(runner)
	print("SCENARIO health runtime: private body sense, continuous-position care, both-body exclusion and cancellation, same joint-file future, explicit old-archive rejection")


func _fixture(runner: Object) -> Dictionary:
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return {}
	var runtime: WorldContinuityRuntime = fixture.continuity
	for region: String in runtime.world_sim.regions:
		var sim: VillageSimulation = runtime.world_sim.regions[region]
		for actor: String in sim.actors:
			sim.cancel_action(actor, "health_fixture_setup")
			sim.actors[actor].autonomous = false
		runtime.world_sim.invalidate_region(region)
	var cell: Vector2i = runtime.world_sim.artifacts.object_cell("hearth_stone")
	fixture.player.spawn_at(cell)
	runtime.prepare_player_command()
	return fixture


func _injure(runner: Object, runtime: WorldContinuityRuntime) -> void:
	var answer: Dictionary = runtime.world_sim.artifacts.begin("player", "heat", "hearth_stone")
	runner.assert_true(answer.ok, "normal runtime performs the actual risky untrained action")
	if answer.ok:
		GameClock.advance_msec(int(runtime.world_sim.artifacts.active.player.due_ms) - GameClock.elapsed_ms)
	runner.assert_true(not runtime.world_sim.health.current_source("player").is_empty(), "shared scene clock commits the original backlash and its continuing bodily effect")


func _prepare_doctor(runtime: WorldContinuityRuntime) -> void:
	var sim: VillageSimulation = runtime.world_sim.regions.home
	sim.set_actor_cell("su_zhi", SimRouteTravel.cell(sim.actors.player.cell))
	sim.actors.su_zhi.autonomous = true
	sim.actors.su_zhi.retry_ms = GameClock.elapsed_ms + 6000000
	sim.actors.su_zhi.energy = 85.0
	runtime.world_sim.invalidate_region("home")


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _actual_body_care(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var panel: InteractionRequestsRuntime = runtime.interaction_adapter
	var player: PlayerCharacter = fixture.player
	panel.show_panel()
	runner.assert_true(panel._body_sense.text.contains("没有持续"), "C displays the original person's qualitative body sense")
	_injure(runner, runtime)
	panel.refresh_progress()
	runner.assert_true(panel._body_sense.text.contains("灼涩"), "body sense updates after an actual completed risk, without opening a second status authority")
	_prepare_doctor(runtime)
	player.motion.relocate(TileGrid.cell_to_world(player.cell) + Vector2(3.5, 0.0))
	runtime.prepare_player_command()
	var point: Vector2 = player.motion.position
	var reply: Dictionary = panel.submit("subject:su_zhi", "diagnose", {"kind": "body", "id": "player"})
	runner.assert_eq(reply.status, "started", "structured C request starts actual consensual examination")
	if reply.status != "started":
		fixtures._dispose(fixture)
		return
	runner.assert_true(player.motion.position.is_equal_approx(point), "requesting care preserves the exact continuous position between cell centers")
	runner.assert_true(not player.has_motion_control(), "medical body ownership reaches the ordinary manual movement guard")
	runner.assert_true(not player.request_sidestep(Vector2.RIGHT), "flash movement cannot bypass care ownership")
	runner.assert_true(not runtime.travel_to("river"), "a second journey cannot own the examining body")
	runner.assert_true(not runtime.world_sim.services.begin("player", "home", "eat").ok, "the service adapter cannot concurrently use the patient")
	player._intent = Vector2.RIGHT
	GameClock.advance_msec(1000)
	player._intent = Vector2.ZERO
	runner.assert_true(player.motion.position.is_equal_approx(point), "held movement input spends world time without moving the occupied body")
	runner.assert_true(not panel._progress.text.contains("查到"), "unfinished examination does not reveal its later diagnosis")
	runtime.stop_player_action()
	runner.assert_true(not runtime.world_sim.health.owns_actor("player") and not runtime.world_sim.health.owns_actor("su_zhi"), "normal stop cancels care and releases both original participants")
	runner.assert_true(runtime.world_sim.regions.home.actors.su_zhi.autonomous and not runtime.world_sim.regions.home.actors.player.autonomous, "stop restores each participant's original autonomy")
	runner.assert_true(player.has_motion_control() and player.motion.position.is_equal_approx(point), "stopping returns control at the same physical point")
	reply = panel.submit("subject:su_zhi", "diagnose", {"kind": "body", "id": "player"})
	runner.assert_eq(reply.status, "started", "a new real examination may be requested after cancellation")
	if reply.status != "started":
		fixtures._dispose(fixture)
		return
	GameClock.advance_msec(int(runtime.world_sim.health.jobs[reply.process.id].due_ms) - GameClock.elapsed_ms)
	runner.assert_true(panel._progress.text.contains("查到"), "the actual completed examination supplies its private conclusion")
	runtime.world_sim.regions.home.inventory.containers["actor:player"]["herb"] = 1
	reply = panel.submit("subject:su_zhi", "treat", {"kind": "body", "id": "player"})
	runner.assert_eq(reply.status, "started", "the same request page starts real treatment after diagnosis and patient supply")
	if reply.status != "started":
		fixtures._dispose(fixture)
		return
	runner.assert_true(player.motion.position.is_equal_approx(point), "actual treatment also preserves the continuous patient position")
	GameClock.advance_msec(31000)
	var path: String = "user://tests/health_runtime_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "normal joint file save captures both bodies and already invested medicine mid-treatment")
	var stored: Dictionary = SimSaveStore.load_file(path).data
	var horizon: int = 3600000
	GameClock.advance_msec(horizon)
	var future: String = _canonical(runtime)
	runner.assert_eq(runtime.load_game(path), OK, "normal candidate loader resumes the real in-progress treatment")
	runner.assert_true(runtime.world_sim.health.owns_actor("player") and not panel.panel.visible, "load preserves medical ownership but clears stale future UI")
	panel.show_panel()
	runner.assert_eq(panel._receipt, reply.process, "reopening C reconstructs the same original care process")
	runner.assert_true(panel._body_sense.text.contains("灼涩") and not panel._progress.text.contains("已完成"), "load presents current body sense without leaking a future cure")
	GameClock.advance_msec(horizon)
	runner.assert_eq(_canonical(runtime), future, "ordinary joint-file continuation reaches exactly the same complete future")
	runner.assert_eq(runtime.world_sim.regions.home.inventory.quantity("actor:player", "herb"), 0, "file continuation cannot refund or duplicate the invested herb")
	var stable: String = _canonical(runtime)
	stored.continuity.world.erase("health")
	var bad_path: String = path + "_invalid.json"
	runner.assert_eq(SimSaveStore.save_file(bad_path, stored), OK, "bad modern fixture is still ordinary valid JSON")
	runner.assert_eq(runtime.load_game(bad_path), ERR_INVALID_DATA, "modern session with a missing health authority is refused")
	runner.assert_eq(_canonical(runtime), stable, "failed modern load preserves every live body, time, medicine and consequence")
	_clean(path)
	_clean(bad_path)
	fixtures._dispose(fixture)


func _legacy_rejection(runner: Object) -> void:
	# The current in-flight medical care and independent continuation stay in
	# _actual_body_care. Near/far and natural recovery remain covered by the
	# current source-backed test_health.gd; old archives are immutable inputs.
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary scene initializes for historical health rejection")
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var world: RegionalSimulation = runtime.world_sim
	var content: ReolContentDB = runtime._home._content
	var terrain: WorldMapData = world.map_data
	var stable: String = _canonical(runtime)
	var clock: String = SnapshotValues.canonical_json(SnapshotValues.normalized(GameClock.to_dict()))
	var archives: Array[Dictionary] = [
		{"path": "res://tests/fixtures/session_v28.json", "version": 28, "sha": "72b76bfaafdf0b8ea740cacdeffe0332f1326e1b12919bbe7bf6d9f790626f23"},
		{"path": "res://tests/fixtures/session_v29.json", "version": 29, "sha": "78252157f410869b94ff9ffcb98fe898a02d3525b1815cf52bab8df3db59e1c1"},
	]
	for entry: Dictionary in archives:
		var path: String = str(entry.path)
		var original: PackedByteArray = FileAccess.get_file_as_bytes(path)
		var raw: Variant = JSON.parse_string(original.get_string_from_utf8())
		runner.assert_eq(FileAccess.get_sha256(path), str(entry.sha), "the real health archive retains its recorded digest: " + path)
		runner.assert_true(raw is Dictionary, "the historical health archive is readable: " + path)
		if not raw is Dictionary:
			continue
		var candidate: Dictionary = raw
		var source: String = SnapshotValues.canonical_json(SnapshotValues.normalized(candidate))
		runner.assert_eq(int(candidate.get("schema_version", -1)), int(entry.version), "the health archive retains its original version: " + path)
		runner.assert_eq(SessionSaveSchema.rejection_reason(candidate.schema_version), SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT, "the old archive has the explicit environment rejection: " + path)
		runner.assert_true(WorldSessionSnapshot.stage(runtime, candidate).is_empty(), "the historical care candidate cannot invent field history: " + path)
		runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(path)), ERR_INVALID_DATA, "ordinary loading refuses the historical health archive: " + path)
		runner.assert_eq(runtime._notice, "旧环境格式不再支持，存档未改；请新开局。", "the historical archive explains its refusal: " + path)
		runner.assert_true(runtime.world_sim == world and runtime._home._content == content and runtime.world_sim.map_data == terrain, "health archive rejection leaves all live owners unchanged: " + path)
		runner.assert_eq(SnapshotValues.canonical_json(SnapshotValues.normalized(GameClock.to_dict())), clock, "health archive rejection preserves the shared clock: " + path)
		runner.assert_eq(_canonical(runtime), stable, "health archive rejection preserves the full current body and world: " + path)
		runner.assert_eq(SnapshotValues.canonical_json(SnapshotValues.normalized(candidate)), source, "staging leaves the supplied old archive unchanged: " + path)
		runner.assert_eq(FileAccess.get_file_as_bytes(path), original, "health archive rejection never rewrites the file: " + path)
	main.free()
	GameClock.restore_state(saved_clock)


func _clean(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
