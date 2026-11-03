extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	var ui: ConstructionRuntime = adapter.construction_adapter
	for sim: VillageSimulation in adapter.world_sim.regions.values():
		for actor: String in sim.actors:
			sim.cancel_action(actor, "fixture_setup")
			sim.actors[actor].autonomous = false
	ui.show_panel()
	ui.register_yard()
	var target: Vector2i = adapter.world_sim.construction.site_bounds().position + Vector2i(2, 2)
	ui.select_cell(target)
	for index: int in ui.type_choice.item_count:
		if ui.type_choice.get_item_metadata(index) == "wood_bed":
			ui.type_choice.select(index)
	ui.place_selected()
	var bed: String = ui.selected_project()
	ui.act("build")
	GameClock.advance_msec(240000)
	runner.assert_true(adapter.world_sim.construction.is_bed(bed) and fixture.world.is_walkable(target), "book builds a real traversable bed through original lumber and world time")
	ui.select_cell(target)
	ui.occupant_choice.select(1)
	ui.assign_bed()
	runner.assert_eq(str(adapter.world_sim.resting.allocations.get(bed, "")), "player", "allocation selector affects original bed-use rules")
	var before: float = float(adapter.world_sim.regions.home.actors.player.energy)
	ui.use_bed()
	runner.assert_true(adapter.world_sim.resting.owns_actor("player"), "book use starts the same persisted walking/rest process")
	runner.assert_true(not adapter.travel_to("river") and not fixture.player.request_sidestep(Vector2.RIGHT), "sleeping body cannot simultaneously travel or perform a short combat move")
	GameClock.advance_msec(23)
	var path: String = "user://tests/resting_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(adapter.save_game(path), OK, "normal joint save captures in-transit bed reservation")
	GameClock.advance_msec(180000)
	runner.assert_true(float(adapter.world_sim.regions.home.actors.player.energy) > before, "shared clock restores actual original energy during sleep")
	adapter.service_adapter.refresh()
	runner.assert_true(adapter.service_adapter.panel._phase.text.contains("持续休息"), "rest describes continuous recovery rather than promising an incorrect fixed finish countdown")
	var future: String = _canonical(adapter)
	runner.assert_eq(adapter.load_game(path), OK, "normal session loader restores bed use and its original body")
	runner.assert_true(not ui.panel.visible, "load discards future panel state")
	GameClock.advance_msec(180000)
	runner.assert_eq(_canonical(adapter), future, "loaded fractional sleep produces identical whole-session future including demand remainders")
	var stable: String = _canonical(adapter)
	var broken: Dictionary = WorldSessionSnapshot.capture(adapter)
	broken.continuity.world.resting.active.player.bed = "construction:999"
	runner.assert_true(WorldSessionSnapshot.stage(adapter, broken).is_empty(), "nonexistent bed cannot replace a living session")
	runner.assert_eq(_canonical(adapter), stable, "bad bed candidate preserves all current world state")
	broken = WorldSessionSnapshot.capture(adapter)
	broken.player.motion.velocity = [120.0, 0.0]
	runner.assert_true(WorldSessionSnapshot.stage(adapter, broken).is_empty(), "a sleeping player cannot retain a second manual movement velocity")
	ui.show_panel()
	ui.select_cell(target)
	runner.assert_true(ui._bed_details.text.contains("正在休息") and ui._space.text.contains("未覆顶"), "book exposes local actual rest and explicit lack of a roof")
	ui.stop()
	runner.assert_true(not adapter.world_sim.resting.owns_actor("player"), "existing stop command releases a sleeping body")
	ui.act("demolish")
	GameClock.advance_msec(70000)
	runner.assert_true(not adapter.world_sim.construction.is_bed(bed) and adapter.world_sim.resting.allocations.is_empty(), "actual demolition removes use and derived allocation, leaving real salvage")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	_fixtures._dispose(fixture)
	_test_actual_archive(runner)
	print("SCENARIO rest book: physical bed build/allocation/use, one body, continuous needs, joint restart and demolition")


func _canonical(adapter: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(adapter)), "", true, true)


func _test_actual_archive(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var path: String = "res://tests/fixtures/session_v17.json"
	var original: String = FileAccess.get_file_as_string(path)
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var adapter: WorldContinuityRuntime = main._continuity
	runner.assert_eq(adapter.load_game(ProjectSettings.globalize_path(path)), OK, "genuine clicked bed-use archive loads through the original file path")
	runner.assert_eq(GameClock.elapsed_ms, 2998843, "archive preserves fractional ongoing sleep time")
	runner.assert_true(adapter.world_sim.resting.active.player.phase == "sleep", "archive contains actual sleep, not a free future recovery")
	runner.assert_true(adapter.world_sim.construction.space_at(Vector2i(264, 262)).enclosed, "room topology reconstructs from the saved real structures")
	var before: float = float(adapter.world_sim.regions.home.actors.player.energy)
	GameClock.advance_msec(540000)
	var future: String = _canonical(adapter)
	runner.assert_true(float(adapter.world_sim.regions.home.actors.player.energy) > before and not adapter.world_sim.resting.owns_actor("player"), "actual archived user recovers and physically wakes out of bed")
	runner.assert_eq(SimRouteTravel.cell(adapter.world_sim.regions.home.actors.player.cell), Vector2i(263, 262), "waking ends on the actual doorway, not still on the bed")
	main.free()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	main = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	adapter = main._continuity
	runner.assert_eq(adapter.load_game(ProjectSettings.globalize_path(path)), OK, "fresh scene restores the same genuine ongoing sleep")
	GameClock.advance_msec(540000)
	runner.assert_eq(_canonical(adapter), future, "fresh scene preserves the full archived bed, resource and autonomous-world future")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "genuine v17 sleep fixture is never rewritten")
	main.free()
	GameClock.restore_state(prior)
