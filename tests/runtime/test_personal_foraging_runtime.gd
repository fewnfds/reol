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
	var prior: Dictionary = GameClock.to_dict()
	for version: int in [10, 11, 19]:
		var path: String = "res://tests/fixtures/session_v%d.json" % version
		var original: String = FileAccess.get_file_as_string(path)
		var raw: Dictionary = JSON.parse_string(original)
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var adapter: WorldContinuityRuntime = main._continuity
		var loaded: Error = adapter.load_game(ProjectSettings.globalize_path(path))
		runner.assert_eq(loaded, OK, "genuine historical world loads with explicit personal-work migration: v%d" % version)
		if loaded == OK:
			runner.assert_eq(adapter.world_sim.regions.home.config.actions.has("keep_herb"), version >= 11, "only worlds with prior natural sources receive future personal work: v%d" % version)
			runner.assert_eq(adapter.player_inventory().quantity("actor:player", "herb"), raw.simulation.inventory.containers["actor:player"].get("herb", 0), "migration adds no imaginary personal materials: v%d" % version)
			if version == 11:
				runner.assert_eq(adapter.world_sim.regions.home.actors.player.active.action, "forage_grain", "genuine old public gathering is not converted into a personal harvest")
			if version == 19:
				runner.assert_eq(adapter.world_sim.services.jobs["service:job:4"].phase, "work", "genuine old trade retains its original unfinished handling")
		runner.assert_eq(FileAccess.get_file_as_string(path), original, "genuine historical source remains unchanged: v%d" % version)
		main.free()
	GameClock.restore_state(prior)


func _test_actual_archive(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var path: String = "res://tests/fixtures/session_v20.json"
	var original: String = FileAccess.get_file_as_string(path)
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var adapter: WorldContinuityRuntime = main._continuity
	var loaded: Error = adapter.load_game(ProjectSettings.globalize_path(path))
	runner.assert_eq(loaded, OK, "genuine personal-mode UI archive restores through the original file loader")
	if loaded == OK:
		runner.assert_eq(GameClock.elapsed_ms, 456445, "genuine personal harvest retains fractional ongoing labor")
		runner.assert_eq(adapter.world_sim.regions.home.actors.player.active.action, "keep_herb", "genuine archive preserves its originally chosen self-kept purpose")
		runner.assert_eq(adapter.player_inventory().quantity("actor:player", "herb"), 1, "genuine archive has only the previous herb before actual harvesting")
		GameClock.advance_msec(1800000)
		var future: String = _canonical(adapter)
		runner.assert_eq(adapter.player_inventory().quantity("actor:player", "herb"), 3, "original finite source adds exactly two personally harvested herbs")
		runner.assert_eq(adapter.world_sim.regions.home.inventory.quantity("garden", "herb"), 11, "actual personal harvest does not also add goods to the public garden")
		runner.assert_true(adapter.world_sim.regions.home.actors.player.receipts.is_empty(), "actual personal harvest produces no public work credit")
		main.free()
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		main = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		adapter = main._continuity
		runner.assert_eq(adapter.load_game(ProjectSettings.globalize_path(path)), OK, "fresh scene loads the genuine same personal work")
		GameClock.advance_msec(1800000)
		runner.assert_eq(_canonical(adapter), future, "genuine personal harvest preserves the complete autonomous-world future across fresh scenes")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "genuine v20 source remains unchanged")
	main.free()
	GameClock.restore_state(prior)
