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
	var home: VillageSimulation = runtime.world_sim.regions.home
	fixture.player.spawn_at(SimRouteTravel.cell(home.places.store.cell))
	runtime.prepare_player_command()
	home.inventory.containers["actor:player"].wood = 3
	var ui: SettlementServicesRuntime = runtime.service_adapter
	ui.panel._submit("work:deliver_wood")
	GameClock.advance_msec(100)
	runner.assert_eq(runtime.player_inventory().entrusted("actor:player", "wood"), 3, "normal work UI actually picks up a public consignment")
	ui.panel._submit("cancel")
	ui.refresh()
	runner.assert_true(ui.panel._details.text.contains("其中受托"), "the same inventory view explains protected goods alongside total carried goods")
	var found: bool = false
	for button: Button in ui.panel._local_buttons:
		if button.get_meta("service_action", "") == "return_goods":
			found = true
			button.pressed.emit()
	runner.assert_true(found and runtime.world_sim.services.status("player").get("kind") == "return_goods", "real UI button routes an actual return service")
	GameClock.advance_msec(1000)
	var path: String = "user://qa_entrusted_goods_runtime_test.json"
	runner.assert_eq(runtime.save_game(path), OK, "joint save stores real return handling and its consignment")
	GameClock.advance_msec(180000)
	var future: String = _canonical(runtime)
	runner.assert_eq(runtime.player_inventory().quantity("actor:player", "wood"), 3, "UI return leaves same-type personal wood untouched")
	runner.assert_eq(runtime.load_game(path), OK, "normal candidate loader accepts actual protected-material return")
	GameClock.advance_msec(180000)
	runner.assert_true(_canonical(runtime) == future, "joint save resumes original return, body and remote world without another batch")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	_fixtures._dispose(fixture)
	_test_real_old_carrying(runner)
	_test_actual_archive(runner)
	print("SCENARIO custody UI: real return button, visible responsibility, original joint save and genuine old carrying-action migration")


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _test_real_old_carrying(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	for version: int in [6, 10, 20]:
		var path: String = "res://tests/fixtures/session_v%d.json" % version
		var original: String = FileAccess.get_file_as_string(path)
		var raw: Dictionary = JSON.parse_string(original)
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var runtime: WorldContinuityRuntime = main._continuity
		var result: Error = runtime.load_game(ProjectSettings.globalize_path(path))
		runner.assert_eq(result, OK, "genuine old carrying world explicitly migrates: v%d" % version)
		if result == OK:
			for region: String in raw.continuity.world.regions:
				var sim: VillageSimulation = runtime.world_sim.regions[region]
				for container: String in raw.continuity.world.regions[region].inventory.containers:
					for item: String in raw.continuity.world.regions[region].inventory.containers[container]:
						runner.assert_eq(sim.inventory.quantity(container, item), int(raw.continuity.world.regions[region].inventory.containers[container][item]), "migration changes no real material balance: v%d/%s/%s" % [version, container, item])
			if version == 6:
				runner.assert_eq(runtime.world_sim.regions.home.inventory.entrusted("actor:lao_zhou", "wood"), 3, "genuine old ongoing public wood becomes explicitly entrusted")
			if version == 10:
				runner.assert_eq(runtime.world_sim.regions.river.inventory.entrusted("actor:river_a_he", "grain"), 2, "genuine old ongoing cooking receives only its actual ingredient responsibility")
			GameClock.advance_msec(180000)
			var future: String = _canonical(runtime)
			runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(path)), OK, "reloading the same historical source repeats no pickup")
			GameClock.advance_msec(180000)
			runner.assert_true(_canonical(runtime) == future, "old carrying future remains identical after independent candidate recovery: v%d" % version)
		runner.assert_eq(FileAccess.get_file_as_string(path), original, "real old fixture is never rewritten: v%d" % version)
		main.free()
	GameClock.restore_state(prior)


func _test_actual_archive(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var path: String = "res://tests/fixtures/session_v21.json"
	var original: String = FileAccess.get_file_as_string(path)
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var result: Error = runtime.load_game(ProjectSettings.globalize_path(path))
	runner.assert_eq(result, OK, "real v21 returns after actual private foraging and public pickup")
	if result == OK:
		runner.assert_eq(runtime.player_inventory().quantity("actor:player", "wood"), 6, "real in-progress bag contains both actual batches")
		runner.assert_eq(runtime.player_inventory().available("actor:player", "wood"), 3, "real in-progress custody protects only the public batch")
		GameClock.advance_msec(180000)
		var future: String = _canonical(runtime)
		runner.assert_eq(runtime.player_inventory().quantity("actor:player", "wood"), 3, "real completed return retains actual privately gathered wood")
		runner.assert_eq(runtime.world_sim.regions.home.institutions.balance("sect", "player"), 0, "real return never issues contribution")
		main.free()
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		main = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		runtime = main._continuity
		runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(path)), OK, "new actual scene recovers the genuine return archive")
		GameClock.advance_msec(180000)
		runner.assert_true(_canonical(runtime) == future, "real return and autonomous world have the identical full future in a fresh scene")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "genuine v21 archive remains immutable")
	main.free()
	GameClock.restore_state(prior)
