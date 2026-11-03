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
	var bed_cell: Vector2i = adapter.world_sim.construction.site_bounds().position + Vector2i(2, 2)
	_select_type(ui, "wood_bed")
	ui.select_cell(bed_cell)
	ui.place_selected()
	var bed: String = ui.selected_project()
	ui.act("build")
	GameClock.advance_msec(220000)
	_select_type(ui, "wood_wall")
	ui.select_cell(bed_cell + Vector2i.RIGHT)
	ui.place_selected()
	ui.act("build")
	GameClock.advance_msec(220000)
	_select_type(ui, "wood_roof")
	ui.select_cell(bed_cell)
	ui.place_selected()
	var roof: String = ui.selected_project()
	runner.assert_true(roof != bed and adapter.world_sim.construction.project_at(bed_cell) == bed and adapter.world_sim.construction.project_at(bed_cell, "roof") == roof, "roof selection draws a separate real upper project over the original bed")
	ui.act("build")
	GameClock.advance_msec(1234)
	var path: String = "user://tests/weather_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(adapter.save_game(path), OK, "normal save captures actual upper construction alongside climate phase")
	GameClock.advance_msec(1100000)
	runner.assert_true(adapter.world_sim.construction.roofed(bed_cell) and fixture.world.is_walkable(bed_cell), "real roof is shelter while ground furniture remains traversable")
	runner.assert_eq(adapter.world_sim.weather.current_kind("home"), "rain", "shared-time runtime reaches actual local rainfall")
	runner.assert_eq(adapter.world_sim.weather.bed_wetness(bed), 0, "supported roof actually protects the original bed from rain")
	var future: String = _canonical(adapter)
	var loaded: Error = adapter.load_game(path)
	runner.assert_eq(loaded, OK, "ordinary loader reconstructs roof/material/weather candidate")
	if loaded != OK:
		_fixtures._dispose(fixture)
		return
	GameClock.advance_msec(1100000)
	runner.assert_eq(_canonical(adapter), future, "loaded upper construction and climate continue the identical full session")
	ui.show_panel()
	_select_type(ui, "wood_bed")
	ui.select_cell(bed_cell)
	runner.assert_true(ui._space.text.contains("实际木屋面遮雨") and ui._bed_details.text.contains("干燥"), "book reports actual local coverage and dry bedding")
	_select_type(ui, "wood_roof")
	ui.select_cell(bed_cell)
	runner.assert_eq(ui.selected_project(), roof, "same grid cell selects its upper layer when the roof type is chosen")
	ui.act("demolish")
	GameClock.advance_msec(260000)
	runner.assert_true(adapter.world_sim.construction.is_bed(bed) and adapter.world_sim.weather.bed_is_wet(bed), "removing only overhead cover exposes the real underlying bed")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	_fixtures._dispose(fixture)
	_test_actual_archive(runner)
	_test_v17_migration(runner)
	print("SCENARIO weather book: independent upper selection, original real labor, cover/rain/dampness and joint continuation")


func _select_type(ui: ConstructionRuntime, type: String) -> void:
	for index: int in ui.type_choice.item_count:
		if ui.type_choice.get_item_metadata(index) == type:
			ui.type_choice.select(index)


func _canonical(adapter: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(adapter)), "", true, true)


func _test_actual_archive(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var path: String = "res://tests/fixtures/session_v18.json"
	var original: String = FileAccess.get_file_as_string(path)
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var adapter: WorldContinuityRuntime = main._continuity
	var loaded: Error = adapter.load_game(ProjectSettings.globalize_path(path))
	runner.assert_eq(loaded, OK, "genuine rainy roof-pickup archive loads with its real external material reservation")
	if loaded == OK:
		runner.assert_eq(GameClock.elapsed_ms, 5001311, "archive preserves fractional pickup and environmental phase")
		runner.assert_eq(adapter.world_sim.construction.active.player.phase, "pickup", "archive retains actual reserved wood before delivery")
		runner.assert_true(not adapter.world_sim.construction.roofed(Vector2i(264, 262)), "inflight roof still provides no shelter after restore")
		runner.assert_eq(adapter.world_sim.weather.bed_wetness("construction:1"), 48, "original exposed bed retains its actual accumulated rain")
		GameClock.advance_msec(600000)
		runner.assert_true(adapter.world_sim.construction.roofed(Vector2i(264, 262)), "archived real roof completes under the original supporting walls")
		runner.assert_eq(adapter.world_sim.weather.bed_wetness("construction:1"), 49, "completion shelters but does not instantly dry the previously soaked bed")
		GameClock.advance_msec(1200000)
		runner.assert_eq(adapter.world_sim.weather.bed_wetness("construction:1"), 0, "genuine bed gradually dries in the continued world")
		runner.assert_eq(adapter.world_sim.regions.home.inventory.quantity("store", "wood"), 34, "archived material is consumed only once")
		var future: String = _canonical(adapter)
		main.free()
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		main = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		adapter = main._continuity
		runner.assert_eq(adapter.load_game(ProjectSettings.globalize_path(path)), OK, "fresh scene reconstructs the same genuine roof/weather archive")
		GameClock.advance_msec(1800000)
		runner.assert_eq(_canonical(adapter), future, "fresh scene yields identical complete roof/weather/autonomous-world continuation")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "genuine v18 weather fixture is never rewritten")
	main.free()
	GameClock.restore_state(prior)


func _test_v17_migration(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var path: String = "res://tests/fixtures/session_v17.json"
	var original: String = FileAccess.get_file_as_string(path)
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var adapter: WorldContinuityRuntime = main._continuity
	var loaded: Error = adapter.load_game(ProjectSettings.globalize_path(path))
	runner.assert_eq(loaded, OK, "genuine previous bed archive migrates through the normal loader")
	if loaded == OK:
		runner.assert_eq(adapter.world_sim.weather.epoch_ms, 2998843, "old archive begins new climate at its own existing time")
		runner.assert_true(adapter.world_sim.weather.damp_beds.is_empty(), "migration invents no historical wet bed")
		for sim: VillageSimulation in adapter.world_sim.regions.values():
			for source: Dictionary in sim.land_resources.sources.values():
				runner.assert_eq(source.rainfall, 0, "old natural sources gain no invented historical rainfall")
		runner.assert_true(adapter.world_sim.resting.active.player.phase == "sleep", "migration preserves the actual body still sleeping")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "genuine v17 source remains byte-for-byte unchanged")
	main.free()
	GameClock.restore_state(prior)
