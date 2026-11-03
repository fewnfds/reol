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
	var prior: Dictionary = GameClock.to_dict()
	var path: String = "res://tests/fixtures/session_v18.json"
	var original: String = FileAccess.get_file_as_string(path)
	var old: Dictionary = JSON.parse_string(original)
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var adapter: WorldContinuityRuntime = main._continuity
	var loaded: Error = adapter.load_game(ProjectSettings.globalize_path(path))
	runner.assert_eq(loaded, OK, "genuine previous weather/pickup archive migrates through the ordinary loader")
	if loaded == OK:
		runner.assert_eq(adapter.world_sim.services.jobs.size(), old.continuity.world.services.jobs.size(), "migration invents no historical trade")
		runner.assert_eq(adapter.world_sim.regions.home.inventory.quantity("records", "coin"), old.continuity.world.regions.home.inventory.containers.records.get("coin", 0), "migration adds no public startup money")
		runner.assert_eq(adapter.world_sim.weather.bed_wetness("construction:1"), 48, "prior real environment and inflight roof remain intact")
		runner.assert_eq(adapter.world_sim.construction.active.player.phase, "pickup", "new trade rules do not steal a prior body's action")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "genuine v18 is never reserialized as a fake older source")
	main.free()
	GameClock.restore_state(prior)


func _test_actual_archive(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var path: String = "res://tests/fixtures/session_v19.json"
	var original: String = FileAccess.get_file_as_string(path)
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var adapter: WorldContinuityRuntime = main._continuity
	var loaded: Error = adapter.load_game(ProjectSettings.globalize_path(path))
	runner.assert_eq(loaded, OK, "genuine clicked trade archive restores through the ordinary file boundary")
	if loaded == OK:
		runner.assert_eq(GameClock.elapsed_ms, 455334, "archive retains fractional original handling time")
		runner.assert_true(adapter.world_sim.services.jobs["service:job:4"].phase == "work", "archive retains physical counting before exchange")
		runner.assert_eq(adapter.player_inventory().quantity("actor:player", "coin"), 6, "genuine quote has not prematurely charged the bag")
		runner.assert_eq(adapter.player_inventory().quantity("actor:player", "meal"), 0, "genuine unfinished purchase has no free food")
		GameClock.advance_msec(180000)
		var future: String = _canonical(adapter)
		runner.assert_eq(adapter.player_inventory().quantity("actor:player", "coin"), 4, "actual archive pays only once when original handling finishes")
		runner.assert_eq(adapter.player_inventory().quantity("actor:player", "meal"), 1, "actual archive obtains exactly one carried meal")
		main.free()
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		main = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		adapter = main._continuity
		runner.assert_eq(adapter.load_game(ProjectSettings.globalize_path(path)), OK, "new scene reconstructs the genuine same trade and autonomous world")
		GameClock.advance_msec(180000)
		runner.assert_eq(_canonical(adapter), future, "genuine trade archive continues the identical complete world in a fresh scene")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "genuine v19 source is never rewritten")
	main.free()
	GameClock.restore_state(prior)
