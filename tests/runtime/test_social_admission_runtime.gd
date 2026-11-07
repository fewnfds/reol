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
	# Old archives lack causal field history; current behavior is tested above.
	load("res://tests/runtime/helpers/legacy_rejection_archive.gd").run(runner, {
		"res://tests/fixtures/session_v14.json": "",
		"res://tests/fixtures/session_v13.json": ""
	})
