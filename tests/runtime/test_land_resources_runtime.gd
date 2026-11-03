extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	_test_original_work_panel_and_joint_save(runner)
	_test_old_and_new_openings_in_the_same_scene(runner)
	_test_real_in_progress_archive(runner)


func _test_original_work_panel_and_joint_save(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	var runtime: WorldContinuityRuntime = fixture.continuity
	var panel: SettlementServicesPanel = runtime.service_adapter.panel
	panel._select_page(5)
	var button: Button
	for candidate: Button in panel._local_buttons:
		if candidate.get_meta("service_action", "") == "work:forage_grain":
			button = candidate
	runner.assert_true(button != null and not button.disabled, "original living panel offers gathering against the current human body")
	button.pressed.emit()
	runner.assert_eq(fixture.home.simulation.actors.player.active.action, "forage_grain", "gathering button routes to the native actor's real timed action")
	GameClock.advance_msec(34517)
	var path: String = "user://tests/resource_work_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "growth, reserved source, in-progress labor and physical position save together")
	GameClock.advance_msec(1800000)
	var expected: String = _canonical(runtime)
	runner.assert_eq(runtime.load_game(path), OK, "normal runtime read restores finite-source labor")
	GameClock.advance_msec(1800000)
	runner.assert_true(_canonical(runtime) == expected, "resumed gather and both settlements have the same future")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	fixtures._dispose(fixture)


func _test_old_and_new_openings_in_the_same_scene(runner: Object) -> void:
	var prior_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var path: String = "user://tests/resource_opening_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "new world with explicit natural sources can be saved")
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path("res://tests/fixtures/session_v10.json")), OK, "actual v10 world migrates without invented old sources")
	runner.assert_true(runtime._home.simulation.land_resources.sources.is_empty(), "old world keeps its own historical source absence")
	var panel: SettlementServicesPanel = runtime.service_adapter.panel
	for button: Button in panel._local_buttons:
		if button.get_meta("service_action", "") == "work:forage_grain":
			runner.assert_true(button.disabled, "legacy world cannot invoke a gathering source it never contained")
	runner.assert_eq(runtime.load_game(path), OK, "same scene can return from a legacy configuration to a current opening")
	runner.assert_eq(runtime.world_sim.regions.river.land_resources.sources.size(), 4, "remote current sources restore against the original scenario rather than the last loaded world")
	var before: String = _canonical(runtime)
	var damaged: Dictionary = WorldSessionSnapshot.capture(runtime)
	damaged.simulation.erase("land_resources")
	damaged.continuity.world.regions.home.erase("land_resources")
	runner.assert_true(WorldSessionSnapshot.stage(runtime, damaged).is_empty(), "modern missing-source fields cannot masquerade as the legacy opening")
	runner.assert_true(_canonical(runtime) == before, "rejected source candidate does not alter identity, time or either region")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	main.free()
	GameClock.restore_state(prior_clock)
	print("SCENARIO source persistence: actual v10 retains its history; current finite-source opening can be loaded again in the same scene")


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _test_real_in_progress_archive(runner: Object) -> void:
	var previous_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	runner.root.add_child(main)
	var path: String = ProjectSettings.globalize_path("res://tests/fixtures/session_v11.json")
	var original: String = FileAccess.get_file_as_string(path)
	var runtime: WorldContinuityRuntime = main._continuity
	runner.assert_eq(runtime.load_game(path), OK, "real v11 main-scene archive restores an actual clicked harvest")
	runner.assert_eq(GameClock.elapsed_ms, 58267, "actual harvest preserves its fractional shared time")
	runner.assert_eq(runtime._home.simulation.actors.player.active.phase, "work", "actual saved work has arrived and is still doing the full gathering labor")
	runner.assert_eq(runtime._home.simulation.inventory.quantity("resource:meadow", "grain"), 12, "in-progress labor has not prematurely extracted natural grain")
	GameClock.advance_msec(1800000)
	runner.assert_eq(runtime._home.simulation.land_resources.sources.meadow.extracted, 4, "actual restored harvest extracts only its promised real batch")
	runner.assert_eq(runtime._home.simulation.inventory.quantity("resource:meadow", "grain"), 8, "actual source retains its remaining mature grain")
	runner.assert_eq(runtime._home.simulation.inventory.operations["action:7:delivery"].target, "store", "the original harvested batch physically reaches the warehouse")
	var expected: String = _canonical(runtime)
	main.free()
	main = packed.instantiate()
	runner.root.add_child(main)
	runtime = main._continuity
	runner.assert_eq(runtime.load_game(path), OK, "fresh generated scene loads the same real harvest archive")
	GameClock.advance_msec(1800000)
	runner.assert_true(_canonical(runtime) == expected, "actual harvest and both living regions continue identically in a fresh scene")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "real v11 source archive stays immutable")
	main.free()
	GameClock.restore_state(previous_clock)
