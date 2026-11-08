extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	_test_panel_practice(runner)
	_test_other_life_practice(runner)
	print("SCENARIO method UI: real foundation→draft→trial→consenting practice→joint restart; historical archives are refused")


func _test_panel_practice(runner: Object) -> void:
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
	if not _select_artifact(runner, adapter, "hearth_stone"):
		fixtures._dispose(fixture)
		return
	adapter.title_edit.text = "小灶留火"
	adapter.compose_selected()
	runner.assert_true(world.heat_methods.methods.is_empty(), "UI naming cannot bypass an unlearned foundation")
	if not world.heat_methods.methods.is_empty():
		fixtures._dispose(fixture)
		return
	var studying: bool = bool(world.artifacts.begin("player", "study", "hearth_stone").ok)
	runner.assert_true(studying, "same person first learns the existing real foundation")
	if not studying:
		fixtures._dispose(fixture)
		return
	GameClock.advance_msec(240000)
	var learned_base: bool = bool(world.artifacts.describe("player", "hearth_stone").get("method", false))
	runner.assert_true(learned_base, "the original warm-stone study actually completes before authoring")
	if not learned_base or not _select_artifact(runner, adapter, "cold_stone"):
		fixtures._dispose(fixture)
		return
	adapter.compose_selected()
	runner.assert_true(world.heat_methods.methods.is_empty(), "learning the warm stone cannot create its method from the distinct cold stone")
	if not world.heat_methods.methods.is_empty():
		fixtures._dispose(fixture)
		return
	if not _select_artifact(runner, adapter, "hearth_stone"):
		fixtures._dispose(fixture)
		return
	adapter.compose_selected()
	var id: String = adapter.selected_method()
	var drafted: bool = not id.is_empty() and world.heat_methods.methods.has(id)
	runner.assert_true(drafted, "UI saves bounded steps into the actual version directory: " + adapter._reply.text)
	if not drafted:
		fixtures._dispose(fixture)
		return
	adapter.act("trial")
	var trial_started: bool = world.artifacts.active.has("player") and not world.heat_methods.knows("player", id)
	runner.assert_true(trial_started, "UI starts original trial without early learning: " + adapter._reply.text)
	if not trial_started:
		fixtures._dispose(fixture)
		return
	GameClock.advance_msec(60000)
	var learned: bool = world.heat_methods.knows("player", id)
	runner.assert_true(learned and str(adapter._note.text).contains("亲手练过"), "completion refreshes authorized understanding immediately")
	runner.assert_true(adapter.method_choice.item_count > 0 and adapter.method_choice.get_item_text(0).contains("已练"), "dropdown and detailed note agree after real completion")
	if not learned:
		fixtures._dispose(fixture)
		return
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
	var save_result: Error = runtime.save_game(path)
	runner.assert_eq(save_result, OK, "original joint save contains practice, teacher, paid costs and version")
	if save_result != OK:
		_remove_test_save(path)
		fixtures._dispose(fixture)
		return
	GameClock.advance_msec(70000)
	var future: String = _canonical(runtime)
	runner.assert_true(runtime.world_sim.heat_methods.knows("su_zhi", id), "completion teaches the named learner")
	var load_result: Error = runtime.load_game(path)
	runner.assert_eq(load_result, OK, "normal file load restores unfinished human instruction")
	if load_result != OK:
		_remove_test_save(path)
		fixtures._dispose(fixture)
		return
	runner.assert_true(not adapter.panel.visible, "load clears temporary UI selections and future text")
	adapter.show_panel()
	GameClock.advance_msec(70000)
	runner.assert_eq(_canonical(runtime), future, "restored method panel cannot repeat input or change the saved future")
	_remove_test_save(path)
	fixtures._dispose(fixture)


func _select_artifact(runner: Object, adapter: HeatMethodsRuntime, id: String) -> bool:
	for index: int in adapter.object_choice.item_count:
		var metadata: Variant = adapter.object_choice.get_item_metadata(index)
		if metadata is Dictionary and metadata.get("kind") == "artifact" and metadata.get("id") == id:
			adapter.object_choice.select(index)
			runner.assert_eq(adapter.selected_object(), id, "the method panel selects the intended visible original artifact")
			return adapter.selected_object() == id
	runner.assert_true(false, "the method panel offers the intended visible original artifact: " + id)
	return false


func _remove_test_save(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _test_other_life_practice(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	# This long-advance domain fixture is not a work-budget performance test.
	runtime.settlement_work_budget = 2147483647
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
	main.free()
	GameClock.restore_state(prior)
	# The current UI case above already saves and resumes a genuine in-flight
	# two-person lesson. The actual earlier sessions cannot enter this world.
	load("res://tests/runtime/helpers/legacy_rejection_archive.gd").run(runner, {
		"res://tests/fixtures/session_v14.json": "",
		"res://tests/fixtures/session_v15.json": "",
	})
