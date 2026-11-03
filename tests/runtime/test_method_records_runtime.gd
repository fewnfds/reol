extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	for sim: VillageSimulation in world.regions.values():
		for actor: String in sim.actors:
			sim.cancel_action(actor, "fixture_setup")
			sim.actors[actor].autonomous = false
	fixture.player.spawn_at(world.artifacts.object_cell("hearth_stone"))
	runtime.prepare_player_command()
	var ui: HeatMethodsRuntime = runtime.heat_method_adapter
	ui.show_panel()
	runner.assert_true(world.artifacts.begin("player", "study", "hearth_stone").ok, "normal record UI body first learns original foundation")
	GameClock.advance_msec(240000)
	ui.title_edit.text = "旅途留火"
	ui.compose_selected()
	var method: String = ui.selected_method()
	runner.assert_true(not method.is_empty(), "normal M panel writes a private method draft")
	ui.tabs.current_tab = 1
	ui.record_action("write")
	runner.assert_true(world.method_records.active.is_empty(), "UI cannot manufacture a record without actual material")
	world.regions.home.inventory.containers["actor:player"].wood = 2
	ui.record_action("write")
	runner.assert_true(world.method_records.owns_actor("player"), "actual M record page starts inscription on original body")
	runner.assert_true(not runtime.travel_to("river"), "inscription blocks conflicting automatic travel")
	runner.assert_true(not runtime._home._player_can_act() and runtime._home._automatic_player_motion(), "original movement and short actions respect this body owner")
	GameClock.advance_msec(12345)
	var path: String = "user://qa_method_records_runtime_test.json"
	runner.assert_eq(runtime.save_game(path), OK, "normal joint saver captures paid writing and all live systems")
	var saved: Dictionary = WorldSessionSnapshot.capture(runtime)
	var bad: Dictionary = saved.duplicate(true)
	bad.player.motion.velocity[0] = 1.0
	runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "joint staging rejects concurrent motion during paid inscription")
	GameClock.advance_msec(150000)
	var future: String = _canonical(runtime)
	runner.assert_true(runtime.world_sim.method_records.objects.size() == 1 and ui.record_choice.item_count == 1, "completion refreshes actual unique carrier into M page")
	runner.assert_eq(runtime.load_game(path), OK, "normal loader restores original writing process")
	runner.assert_true(not ui.panel.visible and ui.record_choice.item_count == 0, "load clears future selections and text")
	ui.show_panel()
	ui.tabs.current_tab = 1
	GameClock.advance_msec(150000)
	runner.assert_eq(_canonical(runtime), future, "normal saved inscription resumes identical material and world future")
	ui.record_action("read")
	runner.assert_true(runtime.world_sim.method_records.owns_actor("player") and not runtime.world_sim.method_records.has_read("player", method), "read button starts a process without immediate knowledge")
	GameClock.advance_msec(60000)
	runner.assert_true(runtime.world_sim.method_records.has_read("player", method) and not runtime.world_sim.heat_methods.knows("player", method), "normal read gives remembered steps without mastery")
	runner.assert_true(ui._note.text.contains("读过") and ui.method_choice.get_item_text(0).contains("已读待练"), "UI distinguishes read steps from actual practice")
	ui.tabs.current_tab = 0
	ui.act("record")
	runner.assert_true(runtime.world_sim.artifacts.active.has("player"), "read-backed attempt still runs original artifact process")
	GameClock.advance_msec(60000)
	runner.assert_true(runtime.world_sim.heat_methods.knows("player", method), "normal real practice finally verifies the recorded version")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	fixtures._dispose(fixture)
	_test_previous_archive(runner)
	_test_actual_archive(runner)
	print("SCENARIO record UI: original wood/body/time, draft→physical inscription→reading→actual practice, joint resume and explicit empty prior migration")


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _test_previous_archive(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var path: String = "res://tests/fixtures/session_v22.json"
	var original: String = FileAccess.get_file_as_string(path)
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(path)), OK, "genuine prior v22 migrates through the normal complete session loader")
	runner.assert_true(runtime.world_sim.method_records.objects.is_empty() and runtime.world_sim.method_records.events.is_empty(), "old characters acquire no invented historical documents or reading")
	runner.assert_true(runtime.world_sim.standing_work.entries.has("standing:home:request_4"), "new record domain preserves old actual cooperative work")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "genuine historical fixture is never rewritten")
	main.free()
	GameClock.restore_state(prior)


func _test_actual_archive(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var path: String = "res://tests/fixtures/session_v23.json"
	var original: String = FileAccess.get_file_as_string(path)
	var future: String = ""
	for attempt: int in 2:
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var runtime: WorldContinuityRuntime = main._continuity
		runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(path)), OK, "genuine v23 restores original physical cross-settlement handover")
		runner.assert_eq(GameClock.elapsed_ms, 2450050, "real archive is during paid handling, not after a fabricated completion")
		runner.assert_true(runtime.world_sim.method_records.held("player", "method_record:1") and not runtime.world_sim.method_records.has_read("river_a_he", "heat_method:1"), "genuine receiver has neither carrier nor steps early")
		GameClock.advance_msec(45000)
		runner.assert_true(runtime.travel_to("home"), "genuine donor can leave only after completing actual handover")
		GameClock.advance_msec(300000)
		runner.assert_eq(runtime.current_region, "home", "normal physical journey returns the donor home")
		runner.assert_true(runtime.world_sim.method_records.held("river_a_he", "method_record:1") and runtime.world_sim.method_records.has_read("river_a_he", "heat_method:1") and not runtime.world_sim.heat_methods.knows("river_a_he", "heat_method:1"), "absent real recipient autonomously reads original carrier without free practical mastery")
		runner.assert_true(runtime.world_sim.method_records.visible("player").is_empty() and not str(runtime.world_sim.method_records.status("player").line).contains("已读"), "distant donor sees no remote reading conclusion")
		if attempt == 0:
			future = _canonical(runtime)
		else:
			runner.assert_eq(_canonical(runtime), future, "fresh full scene and genuine joint archive produce identical absent future")
		main.free()
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "genuine v23 fixture is never rewritten")
	GameClock.restore_state(prior)
