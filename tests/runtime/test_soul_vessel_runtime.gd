extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	_test_visible_commands_and_joint_practice(runner)
	_test_legacy_world_has_no_invented_ring(runner)
	_test_actual_in_progress_archive(runner)
	_test_manual_override_releases_transmission(runner)


func _finish_trip(runtime: WorldContinuityRuntime, runner: Object) -> void:
	var deadline: int = GameClock.elapsed_ms + 120000
	while not runtime.player_journey.is_empty() and GameClock.elapsed_ms < deadline:
		GameClock.advance_msec(1000)
	runner.assert_true(runtime.player_journey.is_empty(), "holder actually finishes the shared-time walk")


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _test_visible_commands_and_joint_practice(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	var runtime: WorldContinuityRuntime = fixture.continuity
	# Isolate commands from autonomous use of the lesson material, while keeping
	# all bodies, inventory, clock and routes owned by their normal domains.
	for sim: VillageSimulation in runtime.world_sim.regions.values():
		for actor: String in sim.actors:
			sim.cancel_action(actor)
			sim.actors[actor].autonomous = false
	var adapter: SoulVesselRuntime = runtime.soul_adapter
	runner.assert_true(adapter.select_vessel("old_ring"), "visible ring has an ordinary selectable interaction panel")
	runner.assert_true(bool(adapter.submit("approach").ok), "ring panel routes approach through the original player journey")
	_finish_trip(runtime, runner)
	for verb: String in ["take", "wake"]:
		runner.assert_true(bool(adapter.submit(verb).ok), "ring panel starts the real action " + verb)
		GameClock.advance_msec(int(runtime.world_sim.soul_vessels.definitions.verbs[verb].ms))
	fixture.home.simulation.set_actor_cell("a_he", runtime.world_sim.soul_vessels.vessel_cell("old_ring"))
	runner.assert_true(bool(runtime.world_sim.artifacts.begin("a_he", "study", "hearth_stone").ok), "a different person can already be busy with the visible lesson material")
	var refused: Dictionary = adapter.submit("guide")
	runner.assert_true(not bool(refused.ok) and str(refused.line).contains("约定"), "a busy visible object is still an explicit request target, so the actual unmet agreement explains refusal")
	runtime.world_sim.artifacts.cancel("a_he")
	runner.assert_true(bool(adapter.submit("promise").ok), "holder makes the actual personal promise after a refusal")
	GameClock.advance_msec(int(runtime.world_sim.soul_vessels.definitions.verbs.promise.ms))
	runner.assert_true(runtime.object_adapter.select_object("hearth_stone"), "original stone panel remains available alongside the resident system")
	runner.assert_true(bool(runtime.object_adapter.submit("take").ok), "the lesson uses an actually taken stone")
	GameClock.advance_msec(int(runtime.world_sim.artifacts.definitions.verbs.take.minutes) * 60000)
	adapter.select_vessel("old_ring")
	runner.assert_true(bool(adapter.submit("to_garden").ok), "promise asks the same human body to carry the same ring to the actual garden")
	_finish_trip(runtime, runner)
	runner.assert_true(bool(adapter.submit("fulfill").ok), "garden interaction fulfills this person's own promise")
	GameClock.advance_msec(int(runtime.world_sim.soul_vessels.definitions.verbs.fulfill.ms))
	runner.assert_true(bool(adapter.submit("guide").ok), "panel can request willing embodied practice")
	GameClock.advance_msec(12345)
	runner.assert_true(adapter.panel._activity.text.contains("48秒"), "visible instruction countdown refreshes on shared time rather than waiting for a whole minute")
	runner.assert_true(runtime.service_adapter.panel._activity.text.contains("指点"), "original living activity displays the ongoing practice at a fractional minute")
	var path: String = "user://tests/soul_lesson_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "normal save captures pupil, teacher, ring, stone, pact and unfinished practice")
	var captured: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_eq(captured.schema_version, SessionSaveSchema.VERSION, "new root explicitly identifies the independent-resident domain")
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, captured).is_empty(), "joint candidate validates all domain references before commit")
	var corrupt: Dictionary = captured.duplicate(true)
	corrupt.continuity.world.erase("soul_vessels")
	var before: String = _canonical(runtime)
	runner.assert_true(WorldSessionSnapshot.stage(runtime, corrupt).is_empty(), "modern missing resident domain cannot silently become an empty old world")
	runner.assert_eq(_canonical(runtime), before, "joint rejection leaves the active lesson and clock untouched")
	GameClock.advance_msec(100000)
	var expected: String = _canonical(runtime)
	runner.assert_true(runtime.world_sim.soul_vessels.learned("player", "hearth_stone"), "runtime completion creates actual private learning")
	runner.assert_eq(runtime.load_game(path), OK, "normal load returns to the unfinished instruction")
	GameClock.advance_msec(100000)
	runner.assert_eq(_canonical(runtime), expected, "normal runtime continuation is identical and never pays or teaches twice")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	fixtures._dispose(fixture)
	print("SCENARIO soul vessel: actual custody and kept word enable private embodied instruction; unfinished joint save resumes once")


func _test_legacy_world_has_no_invented_ring(runner: Object) -> void:
	var prior_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var new_opening: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path("res://tests/fixtures/session_v11.json")), OK, "actual v11 gathering archive explicitly migrates into the new session")
	runner.assert_true(runtime.world_sim.soul_vessels.vessels.is_empty() and runtime.world_sim.soul_vessels.residents.is_empty(), "migration never invents a historical ring or someone else's old memory")
	var staged: Dictionary = WorldSessionSnapshot.stage(runtime, new_opening)
	runner.assert_true(not staged.is_empty(), "same scene can return to its current opening after an old ringless world")
	var changed_version: Dictionary = new_opening.duplicate(true)
	changed_version.schema_version = 11
	changed_version.continuity.world.version = 8
	runner.assert_true(WorldSessionSnapshot.stage(runtime, changed_version).is_empty(), "a modern soul world cannot masquerade as old by changing two version tags")
	main.free()
	GameClock.restore_state(prior_clock)


func _test_actual_in_progress_archive(runner: Object) -> void:
	var prior_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	runner.root.add_child(main)
	var path: String = ProjectSettings.globalize_path("res://tests/fixtures/session_v12.json")
	var original: String = FileAccess.get_file_as_string(path)
	var runtime: WorldContinuityRuntime = main._continuity
	runner.assert_eq(runtime.load_game(path), OK, "actual clicked v12 instruction archive loads into the normal scene")
	runner.assert_eq(GameClock.elapsed_ms, 572395, "actual instruction preserves its fractional shared start")
	runner.assert_true(not runtime.world_sim.soul_vessels.learned("player", "hearth_stone"), "actual unfinished practice has not awarded its knowledge early")
	runner.assert_eq(runtime.world_sim.soul_vessels.active.player.started_ms, 560050, "actual pledge and physical arrival preceded this lesson")
	GameClock.advance_msec(100000)
	runner.assert_true(runtime.world_sim.soul_vessels.learned("player", "hearth_stone"), "actual continued practice finishes learning")
	runner.assert_eq(runtime.world_sim.regions.home.actors.player.qi, 18, "real archive resumes already-paid human qi once")
	runner.assert_eq(runtime.world_sim.soul_vessels.residents.yan_heng.energy, 4, "real archive resumes already-paid teacher attention once")
	var expected: String = _canonical(runtime)
	main.free()
	main = packed.instantiate()
	runner.root.add_child(main)
	runtime = main._continuity
	runner.assert_eq(runtime.load_game(path), OK, "fresh scene restores original physical custody and independent resident")
	GameClock.advance_msec(100000)
	runner.assert_eq(_canonical(runtime), expected, "real v12 archived instruction and both settlements continue identically in a fresh scene")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "v12 source archive remains immutable")
	main.free()
	GameClock.restore_state(prior_clock)


func _test_manual_override_releases_transmission(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	var runtime: WorldContinuityRuntime = fixture.continuity
	for sim: VillageSimulation in runtime.world_sim.regions.values():
		for actor: String in sim.actors:
			sim.cancel_action(actor)
			sim.actors[actor].autonomous = false
	var domain: SimSoulVessels = runtime.world_sim.soul_vessels
	fixture.home.simulation.set_actor_cell("player", domain.vessel_cell("old_ring"))
	fixture.player.spawn_at(domain.vessel_cell("old_ring"))
	runner.assert_true(bool(domain.begin("player", "take", "old_ring").ok), "manual override fixture takes original ring")
	GameClock.advance_msec(1000)
	var qi: int = int(fixture.home.simulation.actors.player.qi)
	runner.assert_true(bool(domain.begin("player", "wake", "old_ring").ok), "manual override fixture starts a paid transmission")
	GameClock.advance_msec(1234)
	fixture.player.manual_movement_started.emit()
	runner.assert_true(not domain.owns_actor("player"), "normal manual movement signal interrupts transmission ownership")
	runner.assert_eq(fixture.home.simulation.actors.player.qi, qi - 1, "manual movement does not refund the paid original qi")
	runner.assert_true(not domain.residents.yan_heng.awake, "unfinished wake does not reveal the resident as if it completed")
	runner.assert_eq(domain.vessels.old_ring.container, "actor:player", "manual override leaves the same actual carried ring in the same custody")
	fixtures._dispose(fixture)
