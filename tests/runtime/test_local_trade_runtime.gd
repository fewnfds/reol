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
	var cell: Vector2i = SimRouteTravel.cell(home.places.records.cell)
	fixture.player.spawn_at(cell)
	home.set_actor_cell("chen_shouzhuo", cell)
	home.set_actor_cell("a_he", cell)
	runtime.prepare_player_command()
	var ui: InteractionRequestsRuntime = runtime.interaction_adapter
	ui.show_panel()
	for index: int in ui.verb_choice.item_count:
		if ui.verb_choice.get_item_metadata(index) == "trade":
			ui.verb_choice.select(index)
	ui.rebuild_choices()
	runner.assert_true(ui._lots_row.visible and ui.lots_choice.max_value == 5, "same structured request UI offers bounded explicit trade lots")
	runner.assert_eq(ui.objects_for("trade").size(), runtime.world_sim.services.definitions.trade.offers.size(), "policy choices describe prices without exposing a target's live stock or budget")
	var bird: Dictionary = runtime.world_sim.avian_life.birds.moss_sparrow
	var point: Vector2 = TileGrid.cell_to_world(cell)
	bird.position = [point.x, point.y]
	runner.assert_eq(ui.submit("subject:avian:moss_sparrow", "trade", {"kind": "trade_offer", "id": "buy_meal"}, "gesture", {"lots": 1}).status, "not_understood", "a bird hearing the same money/goods proposal does not become a shop")
	runner.assert_eq(ui.submit("subject:a_he", "trade", {"kind": "trade_offer", "id": "buy_meal"}, "spoken", {"lots": 1}).status, "incapable", "UI cannot substitute a friendly unappointed person for the public account")
	var reply: Dictionary = ui.submit("subject:chen_shouzhuo", "trade", {"kind": "trade_offer", "id": "buy_meal"}, "spoken", {"lots": 1})
	runner.assert_true(reply.ok and runtime.world_sim.services.owns_actor("player"), "structured public purchase starts the original service route/body")
	if not reply.ok:
		_fixtures._dispose(fixture)
		return
	GameClock.advance_msec(1234)
	var path: String = "user://tests/local_trade_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "inflight quoted purchase saves through the normal joint file boundary")
	GameClock.advance_msec(180000)
	var future: String = _canonical(runtime)
	runner.assert_eq(runtime.player_inventory().quantity("actor:player", "meal"), 1, "completed UI purchase provides actual carried food")
	runner.assert_true(ui._progress.text.contains("钱货已经"), "UI explains completed settlement rather than a free abstract reward")
	runner.assert_eq(runtime.load_game(path), OK, "normal loader reconstructs the same original pending trade")
	ui.show_panel()
	runner.assert_eq(ui._receipt, reply.process, "pending UI receipt reconstructs from the original service job")
	GameClock.advance_msec(180000)
	runner.assert_eq(_canonical(runtime), future, "joint save continues the same full world without another order or payment")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	_fixtures._dispose(fixture)
	_test_v18_migration(runner)
	_test_actual_archive(runner)
	print("SCENARIO trade UI: public policy/explicit lots, actual authority and handling, same joint-save future and no invented historical cash")


func _canonical(adapter: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(adapter)), "", true, true)


func _test_v18_migration(runner: Object) -> void:
	# Old archives lack causal field history; current behavior is tested above.
	load("res://tests/runtime/helpers/legacy_rejection_archive.gd").run(runner, {
		"res://tests/fixtures/session_v18.json": ""
	})


func _test_actual_archive(runner: Object) -> void:
	# Old archives lack causal field history; current behavior is tested above.
	load("res://tests/runtime/helpers/legacy_rejection_archive.gd").run(runner, {
		"res://tests/fixtures/session_v19.json": ""
	})
