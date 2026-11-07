extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	for sim: VillageSimulation in runtime.world_sim.regions.values():
		for actor: String in sim.actors:
			sim.cancel_action(actor, "fixture_setup")
			sim.actors[actor].autonomous = false
	var panel: SettlementServicesPanel = runtime.service_adapter.panel
	panel.personal_gather.button_pressed = true
	panel._submit("work:gather_herb")
	var sim: VillageSimulation = runtime.world_sim.regions.home
	runner.assert_eq(sim.actors.player.active.get("action"), "keep_herb", "normal gather button maps explicit personal mode to its own real action")
	runner.assert_true(panel._notice.text.contains("实物自留") and not panel._notice.text.contains("功德堂"), "personal work feedback does not incorrectly promise a public report reward")
	panel.personal_gather.button_pressed = false
	runner.assert_eq(sim.actors.player.active.get("action"), "keep_herb", "changing a future input mode never converts already-started labor")
	GameClock.advance_msec(12345)
	var path: String = "user://tests/personal_foraging_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "normal loader can capture original in-progress personal gathering")
	GameClock.advance_msec(1600000)
	var future: String = _canonical(runtime)
	runner.assert_eq(runtime.player_inventory().quantity("actor:player", "herb"), 2, "completed normal UI work keeps the real harvest in the player's bag")
	runner.assert_true(runtime.world_sim.regions.home.actors.player.receipts.is_empty(), "personal UI work creates no public credit receipt")
	runner.assert_eq(runtime.load_game(path), OK, "saved personal work restores without changing its original purpose")
	GameClock.advance_msec(1600000)
	runner.assert_eq(_canonical(runtime), future, "same session file resumes the identical shared world and retained output")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	_fixtures._dispose(fixture)
	_test_old_worlds(runner)
	_test_actual_archive(runner)
	print("SCENARIO personal gather UI: explicit kept/public intent, original actor/source/time, current/old saves and unchanged prior jobs")


func _canonical(adapter: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(adapter)), "", true, true)


func _test_old_worlds(runner: Object) -> void:
	# Old archives lack causal field history; current behavior is tested above.
	load("res://tests/runtime/helpers/legacy_rejection_archive.gd").run(runner, {
		"res://tests/fixtures/session_v10.json": "",
		"res://tests/fixtures/session_v11.json": "",
		"res://tests/fixtures/session_v19.json": ""
	})


func _test_actual_archive(runner: Object) -> void:
	# Old archives lack causal field history; current behavior is tested above.
	load("res://tests/runtime/helpers/legacy_rejection_archive.gd").run(runner, {
		"res://tests/fixtures/session_v20.json": ""
	})
