extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	for sim: VillageSimulation in runtime.world_sim.regions.values():
		for actor: String in sim.actors:
			sim.cancel_action(actor, "fixture_setup")
			sim.actors[actor].autonomous = false
	var at: Vector2i = runtime.world_sim.artifacts.object_cell("hearth_stone")
	fixture.player.spawn_at(at)
	runtime._home.simulation.set_actor_cell("su_zhi", at)
	runtime.prepare_player_command()
	var ui: InteractionRequestsRuntime = runtime.interaction_adapter
	var before: String = _canonical(runtime)
	ui.show_panel()
	runner.assert_eq(ui.objects_for("converse"), [{"key": {"kind": "conversation_topic", "id": "ways"}, "label": "你平日能帮些什么？"}], "topic menu supplies public wording instead of target's hidden capabilities")
	runner.assert_eq(_canonical(runtime), before, "opening conversation choices changes no knowledge")
	var answer: Dictionary = ui.submit("subject:su_zhi", "converse", {"kind": "conversation_topic", "id": "ways"})
	runner.assert_true(answer.ok and ui._progress.text.contains("苏芷") and ui._progress.text.contains("石材接缝"), "same C UI displays a personally attributed self-report")
	var path: String = "user://tests/capability_conversation_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "ordinary joint save includes original private speech and consent")
	GameClock.advance_msec(100123)
	var future: String = _canonical(runtime)
	runner.assert_eq(runtime.load_game(path), OK, "ordinary atomic loader restores the conversation")
	ui.show_panel()
	runner.assert_eq(ui._receipt, answer.process, "reopening after load reconstructs own historical speech without querying current abilities")
	runner.assert_true(ui._progress.text.contains("石材接缝"), "remembered words return to the scrollable reply")
	GameClock.advance_msec(100123)
	runner.assert_eq(_canonical(runtime), future, "restoring and rebuilding UI cannot change subsequent world future")
	runner.assert_true(not runtime.world_sim.artifacts.describe("player", "hearth_stone").method, "talk UI never teaches an ability")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	fixtures._dispose(fixture)
	_actual_archives(runner)
	print("SCENARIO conversation UI: public topic, private attributed reply, ordinary save/recall and identical joint future")


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _actual_archives(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var old_path: String = "res://tests/fixtures/wage_claim_v26.json"
	var old_bytes: String = FileAccess.get_file_as_string(old_path)
	var path: String = "res://tests/fixtures/conversation_v26.json"
	var bytes: String = FileAccess.get_file_as_string(path)
	var expected: String = ""
	for attempt: int in 2:
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var runtime: WorldContinuityRuntime = main._continuity
		if attempt == 0:
			runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(old_path)), OK, "genuine wage v26 still loads without a new format or fabricated speech")
			runner.assert_true(SimCapabilityConversation.latest(runtime.world_sim, "player").is_empty(), "old wage archive invents no new social introduction")
		var err: Error = runtime.load_game(ProjectSettings.globalize_path(path))
		runner.assert_eq(err, OK, "genuine clicked conversation archive loads normally")
		if err != OK:
			main.free()
			continue
		runtime.interaction_adapter.show_panel()
		runner.assert_true(runtime.interaction_adapter._progress.text.contains("陈守拙") and runtime.interaction_adapter._progress.text.contains("代表公库"), "reopening reconstructs the participant's actual official introduction")
		runner.assert_eq(GameClock.elapsed_ms, 1001, "real conversation archive retains original fractional world time")
		var cook: Dictionary = runtime._home.simulation.actors.a_he
		runner.assert_true(cook.autonomous or runtime.world_sim.artifacts.active.get("a_he", {}).get("previous_autonomous", false), "genuine scene keeps autonomous life including original ongoing study")
		GameClock.advance_msec(180000)
		if attempt == 0:
			expected = _canonical(runtime)
		else:
			runner.assert_eq(_canonical(runtime), expected, "genuine private conversation yields identical entire future in new scenes")
		main.free()
	runner.assert_eq(FileAccess.get_file_as_string(path), bytes, "test never generates or rewrites clicked conversation fixture")
	runner.assert_eq(FileAccess.get_file_as_string(old_path), old_bytes, "previous wage fixture stays byte-for-byte original")
	GameClock.restore_state(prior)
