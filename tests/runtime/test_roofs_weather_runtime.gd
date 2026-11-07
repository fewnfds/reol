extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")
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
	# Current roof, wet-bed and gradual drying behavior also has independent
	# regional coverage in tests/sim/test_roofs_and_weather.gd.
	LegacyRejection.run(runner, {"res://tests/fixtures/session_v17.json": "", "res://tests/fixtures/session_v18.json": ""})
	print("SCENARIO weather book: independent upper selection, original real labor, cover/rain/dampness and joint continuation")


func _select_type(ui: ConstructionRuntime, type: String) -> void:
	for index: int in ui.type_choice.item_count:
		if ui.type_choice.get_item_metadata(index) == type:
			ui.type_choice.select(index)


func _canonical(adapter: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(adapter)), "", true, true)
