extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")
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
	# Current UI return and joint save are above; test_entrusted_goods.gd
	# separately checks real public/private batches and cancellation recovery.
	LegacyRejection.run(runner, {
		"res://tests/fixtures/session_v6.json": "",
		"res://tests/fixtures/session_v10.json": "",
		"res://tests/fixtures/session_v20.json": "6e306e51f366ae6f41aeb74433476e03ceceacc1a3e6fa924117efb8889a5fa2",
		"res://tests/fixtures/session_v21.json": "587729f03d145f53cf14f3f9464e58a89038ecc31c67b038279da66a3073ee79",
	})
	print("SCENARIO custody UI: real return button, visible responsibility, original joint save and explicit old-archive rejection")


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)
