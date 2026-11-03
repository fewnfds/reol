extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	var adapter: HeatMethodsRuntime = runtime.heat_method_adapter
	var cell: Vector2i = world.artifacts.object_cell("hearth_stone")
	fixture.player.spawn_at(cell)
	for sim: VillageSimulation in world.regions.values():
		for actor: String in sim.actors:
			sim.cancel_action(actor, "fixture_setup")
			sim.actors[actor].autonomous = false
	world.regions.home.set_actor_cell("su_zhi", cell)
	runtime.prepare_player_command()
	adapter.show_panel()
	runner.assert_true(adapter.panel.visible and adapter.method_choice.item_count == 0, "method panel starts from this subject's actual empty notes")
	adapter.title_edit.text = "小灶留火"
	adapter.compose_selected()
	runner.assert_true(world.heat_methods.methods.is_empty(), "UI naming cannot bypass an unlearned foundation")
	runner.assert_true(world.artifacts.begin("player", "study", "hearth_stone").ok, "same person first learns the existing real foundation")
	GameClock.advance_msec(240000)
	adapter.compose_selected()
	var id: String = adapter.selected_method()
	runner.assert_true(not id.is_empty() and world.heat_methods.methods.has(id), "UI saves bounded steps into the actual version directory")
	adapter.act("trial")
	runner.assert_true(world.artifacts.active.has("player") and not world.heat_methods.knows("player", id), "UI starts original trial without early learning")
	GameClock.advance_msec(60000)
	runner.assert_true(world.heat_methods.knows("player", id) and str(adapter._note.text).contains("亲手练过"), "completion refreshes authorized understanding immediately")
	runner.assert_true(adapter.method_choice.get_item_text(0).contains("已练"), "dropdown and detailed note agree after real completion")
	for index: int in adapter.learner_choice.item_count:
		if adapter.learner_choice.get_item_metadata(index) == "subject:su_zhi":
			adapter.learner_choice.select(index)
	adapter.teach_selected()
	runner.assert_true(world.artifacts.owns_actor("player") and world.artifacts.owns_actor("su_zhi"), "panel request starts the actual consenting two-person lesson")
	if not world.artifacts.owns_actor("su_zhi"):
		fixtures._dispose(fixture)
		return
	runner.assert_true(not runtime.travel_to("river"), "teacher cannot leave through a competing automatic travel command")
	GameClock.advance_msec(12345)
	var path: String = "user://tests/heat_methods_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "original joint save contains practice, teacher, paid costs and version")
	GameClock.advance_msec(70000)
	var future: String = _canonical(runtime)
	runner.assert_true(runtime.world_sim.heat_methods.knows("su_zhi", id), "completion teaches the named learner")
	runner.assert_eq(runtime.load_game(path), OK, "normal file load restores unfinished human instruction")
	runner.assert_true(not adapter.panel.visible, "load clears temporary UI selections and future text")
	adapter.show_panel()
	GameClock.advance_msec(70000)
	runner.assert_eq(_canonical(runtime), future, "restored method panel cannot repeat input or change the saved future")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	fixtures._dispose(fixture)
	_test_other_life_practice(runner)
	print("SCENARIO method UI: real foundation→draft→trial→consenting practice→joint restart; old version has no invented techniques")


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _test_other_life_practice(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	main._avatar.choose("subject:avian:moss_sparrow")
	GameClock.set_paused(true)
	var world: RegionalSimulation = runtime.world_sim
	for sim: VillageSimulation in world.regions.values():
		for actor: String in sim.actors:
			sim.cancel_action(actor, "fixture_setup")
			sim.actors[actor].autonomous = false
	for actor: String in ["chen_shouzhuo", "player"]:
		world.regions.home.set_actor_cell(actor, world.artifacts.object_cell("hearth_stone"))
	var draft: Dictionary = world.heat_methods.compose("chen_shouzhuo", "hearth_stone", "旁人生计", 1, 1)
	runner.assert_true(draft.ok and world.heat_methods.start("chen_shouzhuo", "hearth_stone", str(draft.method)).ok, "another human prepares a technique while the player lives as a bird")
	GameClock.advance_msec(60000)
	world.regions.home.actors.player.autonomous = true
	runner.assert_true(world.heat_methods.teach("chen_shouzhuo", "player", "hearth_stone", str(draft.method)).ok, "former human may independently agree to the same world interaction")
	var saved: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, saved).is_empty(), "temporary practice occupancy preserves autonomous-human provenance under bird identity")
	world.artifacts.cancel("player")
	runner.assert_true(bool(world.regions.home.actors.player.autonomous) and runtime.bird_player_active(), "cancelling human study restores its own agency without changing the player's life")
	var path: String = ProjectSettings.globalize_path("res://tests/fixtures/session_v14.json")
	var raw: String = FileAccess.get_file_as_string(path)
	runner.assert_eq(runtime.load_game(path), OK, "genuine v14 archive migrates in its real terrain/setup through normal file loading")
	runner.assert_true(runtime.world_sim.heat_methods.methods.is_empty(), "old archive receives no invented draft or knowledge")
	runner.assert_eq(FileAccess.get_file_as_string(path), raw, "historic v14 fixture remains unchanged")
	var current_path: String = ProjectSettings.globalize_path("res://tests/fixtures/session_v15.json")
	var current_source: String = FileAccess.get_file_as_string(current_path)
	runner.assert_eq(runtime.load_game(current_path), OK, "real M-panel-created two-person lesson archive loads")
	runner.assert_eq(GameClock.elapsed_ms, 315445, "actual archive resumes during its original paid practice")
	runner.assert_true(not runtime.world_sim.heat_methods.knows("su_zhi", "heat_method:1"), "actual unfinished archive has no future student mastery")
	GameClock.advance_msec(70000)
	var future: String = _canonical(runtime)
	runner.assert_true(runtime.world_sim.heat_methods.knows("su_zhi", "heat_method:1"), "actual archived practice really completes")
	main.free()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	main = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	runtime = main._continuity
	runner.assert_eq(runtime.load_game(current_path), OK, "new main scene restores the original v15 practice")
	GameClock.advance_msec(70000)
	runner.assert_eq(_canonical(runtime), future, "actual authored lesson and the whole world preserve their future across fresh main scenes")
	runner.assert_eq(FileAccess.get_file_as_string(current_path), current_source, "actual v15 source is never rewritten to fit a later implementation")
	main.free()
	GameClock.restore_state(prior)
