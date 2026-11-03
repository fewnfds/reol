extends RefCounted


func run(runner: Object) -> void:
	_test_short_conversation_and_identity(runner)
	_test_actual_collection_archive(runner)


func _scene(runner: Object) -> Node:
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	return main


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _test_short_conversation_and_identity(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var main: Node = _scene(runner)
	var runtime: WorldContinuityRuntime = main._continuity
	main._avatar.choose("subject:player")
	GameClock.set_paused(true)
	runtime._home._selected_actor = "a_he"
	runner.assert_true(runtime.service_adapter.submit("talk:claim").ok, "ordinary talk-page intent starts the finite statement in the real scene")
	GameClock.advance_msec(2000)
	runner.assert_true(not runtime.travel_to("river") and not runtime.start_home_work("deliver_wood").ok, "ongoing speech cannot be overlaid with travel or labor")
	var saved: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, saved).is_empty(), "short conversation has a valid joint candidate before a world minute ends")
	GameClock.advance_msec(3000)
	var row: Dictionary = runtime.world_sim.admissions.entries.back()
	runner.assert_eq(runtime.service_adapter.panel._notice.text, row.line, "fractional-minute completion immediately refreshes its player-visible reason")
	runner.assert_true(not runtime.world_sim.services.has_access("player", "home", "gate"), "a conversation cannot turn into a formal player permit")
	var bad: Dictionary = saved.duplicate(true)
	bad.player.motion.action = {"phase": "travel"}
	runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "a saved talk cannot grant a second short-action owner")
	main.free()
	GameClock.restore_state(prior)


func _test_actual_collection_archive(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var main: Node = _scene(runner)
	var runtime: WorldContinuityRuntime = main._continuity
	var path: String = ProjectSettings.globalize_path("res://tests/fixtures/session_v14.json")
	var source: String = FileAccess.get_file_as_string(path)
	runner.assert_eq(runtime.load_game(path), OK, "actual UI-created one-use collection archive loads through normal storage")
	runner.assert_eq(GameClock.elapsed_ms, 22100, "real archive resumes before any medicine is handed over")
	runner.assert_eq(runtime.world_sim.services.jobs["service:job:1"].options.admission, "admission:2", "ongoing collection refers to the actual colleague's consent")
	GameClock.advance_msec(400000)
	var expected: String = _canonical(runtime)
	runner.assert_eq(runtime.player_inventory().quantity("actor:player", "herb"), 1, "real branch arrives only after the original collection process")
	runner.assert_true(not runtime.world_sim.services.has_access("player", "home", "gate"), "completion preserves the difference between discretionary access and formal registration")
	main.free()
	main = _scene(runner)
	runtime = main._continuity
	runner.assert_eq(runtime.load_game(path), OK, "fresh main scene restores the same original consent and goods")
	GameClock.advance_msec(400000)
	runner.assert_eq(_canonical(runtime), expected, "actual in-progress admission and all other world domains reach the same future after restart")
	runner.assert_eq(FileAccess.get_file_as_string(path), source, "real v14 source remains unchanged")
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path("res://tests/fixtures/session_v13.json")), OK, "same scene still migrates the actual previous-format soul carry")
	runner.assert_true(runtime.soul_player_active() and runtime.world_sim.admissions.entries.is_empty(), "old timeline retains its soul identity without inventing statements or permits")
	main.free()
	GameClock.restore_state(prior)
	print("SCENARIO actual admission UI: timed private speech and one-use collection persist; previous soul identity migrates without invented evidence")
