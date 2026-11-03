extends RefCounted


func run(runner: Object) -> void:
	_test_third_life_and_finite_perspective(runner)
	_test_actual_carry_archive_and_identity(runner)


func _new_scene(runner: Object) -> Node:
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	return main


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _test_third_life_and_finite_perspective(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var main: Node = _new_scene(runner)
	var runtime: WorldContinuityRuntime = main._continuity
	runner.assert_true(main._avatar.choose("subject:soul:yan_heng"), "new opening can bind the original independent soul exactly once")
	GameClock.set_paused(true)
	runner.assert_true(runtime.soul_player_active() and not runtime.bird_player_active() and not runtime.human_player_active(), "nonhuman life no longer implicitly means a bird")
	runner.assert_true(not main._avatar.choose("subject:player") and not main._avatar.choose("subject:avian:moss_sparrow"), "soul opening cannot freely reroll to a different living person")
	runner.assert_true(runtime.world_sim.regions.home.actors.player.autonomous and not main.player.avatar_active, "former human keeps an independent autonomous body")
	runner.assert_true(main._avatar.soul._sense.visible and not main.hud._pawn_panel.visible and not runtime._panel.visible and not runtime.service_adapter.panel.visible, "soul's own screen hides human status and institutional information")
	runner.assert_true(not main._avatar._bird_actions.visible and not main._avatar._bird_status.visible, "soul life does not show bird appetite or action controls")
	runner.assert_true(not runtime.start_home_work("forage_grain").ok and not runtime.travel_to("river") and not main.player.request_sidestep(Vector2.RIGHT), "soul cannot order the former body's work, route or sidestep")
	var agency: SimSoulAgency = runtime.world_sim.soul_vessels.agency
	var ring: String = str(runtime.world_sim.soul_vessels.residents.yan_heng.vessel)
	var point: Vector2 = agency.point("yan_heng")
	main.player._intent = Vector2.RIGHT
	GameClock.advance_msec(1000)
	runner.assert_eq(agency.point("yan_heng"), point, "held human movement intent never creates legs for the ring")
	runner.assert_eq(runtime.controlled_cell(), runtime.world_sim.soul_vessels.vessel_cell(ring), "camera and world loading follow the original carrier")
	runner.assert_true(not agency.perceive("yan_heng").has("stock") and not agency.perceive("yan_heng").has("qi"), "spiritual projection does not import a human inventory or power panel")
	for signal_row: Dictionary in agency.perceive("yan_heng").signals:
		runner.assert_eq(signal_row.label, "一道呼吸的气息", "visible human names remain unknown before an actual introduction")
	runner.assert_true(main._avatar.soul.submit("observe").ok, "soul action panel begins its own real perception action")
	GameClock.advance_msec(10000)
	runner.assert_true(agency.events.back().kind == "observed", "personal observation completes on the common world clock")
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, snapshot).is_empty(), "selected soul and original world compose a valid joint save")
	var damaged: Dictionary = snapshot.duplicate(true)
	damaged.avatar_subject = "subject:player"
	runner.assert_true(WorldSessionSnapshot.stage(runtime, damaged).is_empty(), "a save cannot grant human control while retaining a manual independent soul")
	var before: String = _canonical(runtime)
	damaged = snapshot.duplicate(true)
	damaged.continuity.world.soul_vessels.agency.manual = ""
	runner.assert_true(WorldSessionSnapshot.stage(runtime, damaged).is_empty(), "modern missing manual intention cannot silently reassign the player")
	runner.assert_eq(_canonical(runtime), before, "bad life bindings cannot partially change the live world")
	main.free()
	GameClock.restore_state(prior)


func _test_actual_carry_archive_and_identity(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var main: Node = _new_scene(runner)
	var runtime: WorldContinuityRuntime = main._continuity
	var path: String = ProjectSettings.globalize_path("res://tests/fixtures/session_v13.json")
	var original: String = FileAccess.get_file_as_string(path)
	runner.assert_eq(runtime.load_game(path), OK, "actual clicked third-life carry archive loads in the normal opening scene")
	runner.assert_eq(GameClock.elapsed_ms, 12000, "actual soul archive keeps its shared fractional travel time")
	runner.assert_eq(runtime.avatar_subject, "subject:soul:yan_heng", "actual archive resumes the same independent resident")
	runner.assert_eq(runtime.world_sim.soul_vessels.vessels.old_ring.container, "actor:player", "actual original human is carrying the actual unique ring")
	runner.assert_true(runtime.world_sim.soul_vessels.agency.errands.player.picked and not runtime.world_sim.regions.home.actors.player.autonomous, "accepted helper temporarily owns a physical carry job rather than becoming player-controlled")
	runner.assert_true(not main._avatar.opening.visible and main._avatar.soul._sense.visible, "loading a soul archive locks the opening and immediately restores its limited screen")
	runner.assert_eq(main._avatar.global_position, runtime.world_sim.soul_vessels.agency.point("yan_heng"), "loaded camera source comes from actual carried position")
	var saved: Dictionary = WorldSessionSnapshot.capture(runtime)
	main.player._intent = Vector2.RIGHT
	GameClock.advance_msec(100000)
	var expected: String = _canonical(runtime)
	runner.assert_true(runtime.world_sim.soul_vessels.agency.errands.is_empty() and runtime.world_sim.regions.home.actors.player.autonomous, "helper fulfills the carry and returns to his own life")
	runner.assert_eq(runtime.world_sim.soul_vessels.agency.events.back().at_ms, 12718, "actual approach and carrying finish only after physical travel time")
	main.free()
	main = _new_scene(runner)
	runtime = main._continuity
	runner.assert_eq(runtime.load_game(path), OK, "fresh scene restores the same real in-progress soul world")
	GameClock.advance_msec(100000)
	runner.assert_eq(_canonical(runtime), expected, "inputless fresh scene and human input during soul life have the same continued whole world")
	var corrupt: Dictionary = saved.duplicate(true)
	corrupt.continuity.world.soul_vessels.agency.social.requests = {}
	runner.assert_true(WorldSessionSnapshot.stage(runtime, corrupt).is_empty(), "joint carry without the actual helper's consent is rejected")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "actual v13 source archive remains immutable")
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path("res://tests/fixtures/session_v12.json")), OK, "same scene can still return to the actual older human lesson")
	runner.assert_true(runtime.human_player_active() and runtime.world_sim.soul_vessels.agency.manual.is_empty() and not main._avatar.soul._sense.visible, "old migration never steals player identity or invents a past manual soul")
	main.free()
	GameClock.restore_state(prior)
	print("SCENARIO soul player: finite anonymous senses, actual cooperation and original human carry; same identity and world survive restart")
