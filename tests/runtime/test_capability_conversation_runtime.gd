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
	# Current real speech, authorized UI recall and the joint future remain in run().
	load("res://tests/runtime/helpers/legacy_rejection_archive.gd").run(runner, {
		"res://tests/fixtures/wage_claim_v26.json": "1ebf265690d16bea20290261292abbe20232b74d8f7a266e79a83fa731350c19",
		"res://tests/fixtures/conversation_v26.json": "d493d2c58815eaf289ebd5a91399a86cd0ab07514dedcc0eb9e59f73d77d342a",
	})
