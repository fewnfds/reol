extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")


func run(runner: Object) -> void:
	_test_original_work_panel_and_joint_save(runner)
	_test_current_opening_and_candidate(runner)
	# test_land_resources._test_saved_work_and_bad_candidates verifies current fractional harvest,
	# extraction, delivery and identical future without a historical archive.
	LegacyRejection.run(runner, {
		"res://tests/fixtures/session_v10.json": "",
		"res://tests/fixtures/session_v11.json": "",
	})


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


func _test_current_opening_and_candidate(runner: Object) -> void:
	var prior_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var path: String = "user://tests/resource_opening_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "new world with explicit natural sources can be saved")
	runner.assert_eq(runtime.load_game(path), OK, "the ordinary scene restores its current finite-source opening")
	runner.assert_eq(runtime.world_sim.regions.river.land_resources.sources.size(), 4, "remote current sources restore against the original scenario")
	var before: String = _canonical(runtime)
	var damaged: Dictionary = WorldSessionSnapshot.capture(runtime)
	damaged.simulation.erase("land_resources")
	damaged.continuity.world.regions.home.erase("land_resources")
	runner.assert_true(WorldSessionSnapshot.stage(runtime, damaged).is_empty(), "current opening cannot omit its original finite-source authority")
	runner.assert_true(_canonical(runtime) == before, "rejected source candidate does not alter identity, time or either region")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	main.free()
	GameClock.restore_state(prior_clock)
	print("SCENARIO source persistence: current finite-source opening restores; a missing-source candidate is rejected atomically")


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)
