extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	_test_panel_records(runner)
	_test_previous_archive(runner)
	_test_actual_archive(runner)
	print("SCENARIO record UI: original wood/body/time, draft→physical inscription→reading→actual practice, joint resume and explicit empty prior migration")


func _test_panel_records(runner: Object) -> void:
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
	if not _select_hearth_stone(runner, ui):
		fixtures._dispose(fixture)
		return
	var studying: bool = bool(world.artifacts.begin("player", "study", "hearth_stone").ok)
	runner.assert_true(studying, "normal record UI body first learns original foundation")
	if not studying:
		fixtures._dispose(fixture)
		return
	GameClock.advance_msec(240000)
	var learned_base: bool = bool(world.artifacts.describe("player", "hearth_stone").get("method", false))
	runner.assert_true(learned_base, "the original warm-stone foundation completes before the record draft")
	if not learned_base or not _select_hearth_stone(runner, ui):
		fixtures._dispose(fixture)
		return
	ui.title_edit.text = "旅途留火"
	ui.compose_selected()
	var method: String = ui.selected_method()
	var drafted: bool = not method.is_empty() and world.heat_methods.methods.has(method)
	runner.assert_true(drafted, "normal M panel writes a private method draft: " + ui._reply.text)
	if not drafted:
		fixtures._dispose(fixture)
		return
	ui.tabs.current_tab = 1
	ui.record_action("write")
	runner.assert_true(world.method_records.active.is_empty(), "UI cannot manufacture a record without actual material")
	world.regions.home.inventory.containers["actor:player"].wood = 2
	ui.record_action("write")
	var writing: bool = world.method_records.owns_actor("player")
	runner.assert_true(writing, "actual M record page starts inscription on original body: " + ui._reply.text)
	if not writing:
		fixtures._dispose(fixture)
		return
	runner.assert_true(not runtime.travel_to("river"), "inscription blocks conflicting automatic travel")
	runner.assert_true(not runtime._home._player_can_act() and runtime._home._automatic_player_motion(), "original movement and short actions respect this body owner")
	GameClock.advance_msec(12345)
	var path: String = "user://tests/method_records_%d.json" % Time.get_ticks_usec()
	var save_result: Error = runtime.save_game(path)
	runner.assert_eq(save_result, OK, "normal joint saver captures paid writing and all live systems")
	if save_result != OK:
		_remove_test_save(path)
		fixtures._dispose(fixture)
		return
	var saved: Dictionary = WorldSessionSnapshot.capture(runtime)
	var bad: Dictionary = saved.duplicate(true)
	bad.player.motion.velocity[0] = 1.0
	runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "joint staging rejects concurrent motion during paid inscription")
	GameClock.advance_msec(150000)
	var future: String = _canonical(runtime)
	runner.assert_true(runtime.world_sim.method_records.objects.size() == 1 and ui.record_choice.item_count == 1, "completion refreshes actual unique carrier into M page")
	var load_result: Error = runtime.load_game(path)
	runner.assert_eq(load_result, OK, "normal loader restores original writing process")
	if load_result != OK:
		_remove_test_save(path)
		fixtures._dispose(fixture)
		return
	runner.assert_true(not ui.panel.visible and ui.record_choice.item_count == 0, "load clears future selections and text")
	ui.show_panel()
	if not _select_hearth_stone(runner, ui):
		_remove_test_save(path)
		fixtures._dispose(fixture)
		return
	ui.tabs.current_tab = 1
	GameClock.advance_msec(150000)
	runner.assert_eq(_canonical(runtime), future, "normal saved inscription resumes identical material and world future")
	ui.record_action("read")
	runner.assert_true(runtime.world_sim.method_records.owns_actor("player") and not runtime.world_sim.method_records.has_read("player", method), "read button starts a process without immediate knowledge")
	GameClock.advance_msec(60000)
	runner.assert_true(runtime.world_sim.method_records.has_read("player", method) and not runtime.world_sim.heat_methods.knows("player", method), "normal read gives remembered steps without mastery")
	runner.assert_true(ui._note.text.contains("读过") and ui.method_choice.item_count > 0 and ui.method_choice.get_item_text(0).contains("已读待练"), "UI distinguishes read steps from actual practice")
	ui.tabs.current_tab = 0
	ui.act("record")
	runner.assert_true(runtime.world_sim.artifacts.active.has("player"), "read-backed attempt still runs original artifact process")
	GameClock.advance_msec(60000)
	runner.assert_true(runtime.world_sim.heat_methods.knows("player", method), "normal real practice finally verifies the recorded version")
	_remove_test_save(path)
	fixtures._dispose(fixture)


func _select_hearth_stone(runner: Object, ui: HeatMethodsRuntime) -> bool:
	for index: int in ui.object_choice.item_count:
		var metadata: Variant = ui.object_choice.get_item_metadata(index)
		if metadata is Dictionary and metadata.get("kind") == "artifact" and metadata.get("id") == "hearth_stone":
			ui.object_choice.select(index)
			runner.assert_eq(ui.selected_object(), "hearth_stone", "record UI selects the intended visible warm stone")
			return ui.selected_object() == "hearth_stone"
	runner.assert_true(false, "record UI offers the intended visible warm stone")
	return false


func _remove_test_save(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _test_previous_archive(runner: Object) -> void:
	# Old archives lack causal field history; current behavior is tested above.
	load("res://tests/runtime/helpers/legacy_rejection_archive.gd").run(runner, {
		"res://tests/fixtures/session_v22.json": ""
	})


func _test_actual_archive(runner: Object) -> void:
	# Old archives lack causal field history; current behavior is tested above.
	load("res://tests/runtime/helpers/legacy_rejection_archive.gd").run(runner, {
		"res://tests/fixtures/session_v23.json": ""
	})
