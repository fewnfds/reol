extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	var ui: ConstructionRuntime = adapter.construction_adapter
	var world: RegionalSimulation = adapter.world_sim
	for sim: VillageSimulation in world.regions.values():
		for actor: String in sim.actors:
			sim.cancel_action(actor, "fixture_setup")
			sim.actors[actor].autonomous = false
	ui.show_panel()
	runner.assert_true(ui.panel.visible and world.construction.sites.is_empty(), "B book begins without invented historic construction")
	ui.register_yard()
	runner.assert_true(world.construction.sites.has("sect_yard"), "book registers authorized terrain beside the real warehouse")
	if world.construction.sites.is_empty():
		_fixtures._dispose(fixture)
		return
	var target: Vector2i = world.construction.site_bounds().position + Vector2i(1, 1)
	fixture.player.spawn_at(target)
	adapter.prepare_player_command()
	var old: Dictionary = WorldSessionSnapshot.capture(adapter)
	fixture.player.spawn_at(SimRouteTravel.cell(world.regions.home.places.store.cell))
	adapter.prepare_player_command()
	# This scenario exercises a wall, not the first menu entry. Content bundle
	# serialization may reorder definition keys (a bed is not a ground blocker).
	for index: int in ui.type_choice.item_count:
		if str(ui.type_choice.get_item_metadata(index)) == "wood_wall":
			ui.type_choice.select(index)
			break
	runner.assert_eq(str(ui.type_choice.get_selected_metadata()), "wood_wall", "construction scenario explicitly selects its wall blueprint")
	ui.select_cell(target)
	ui.place_selected()
	var id: String = ui.selected_project()
	runner.assert_true(not id.is_empty() and world.construction.projects.has(id), "selected empty cell creates original project, not a rendered prop")
	ui.act("build")
	runner.assert_true(world.construction.owns_actor("player"), "book starts real construction ownership")
	runner.assert_true(not adapter.travel_to("river") and not fixture.player.request_sidestep(Vector2.RIGHT), "construction body cannot also travel or sidestep")
	GameClock.advance_msec(1517)
	var path: String = "user://tests/construction_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(adapter.save_game(path), OK, "joint save captures real material route and construction control")
	GameClock.advance_msec(300000)
	runner.assert_true(world.construction.blocked(target) and not fixture.world.is_walkable(target), "completed wall changes the original world's walkability")
	runner.assert_true(not fixture.world.can_step(target + Vector2i.LEFT, Vector2i.RIGHT), "ground movement and pathfinding cannot enter wall footprint")
	var staged_old: Dictionary = WorldSessionSnapshot.stage(adapter, old)
	runner.assert_true(not staged_old.is_empty(), "a live wall does not contaminate an earlier independent candidate at that coordinate")
	if not staged_old.is_empty():
		runner.assert_true(staged_old.world.map_data != world.map_data and staged_old.world.construction._terrain.get_object() == staged_old.map, "actual construction archive checks its own independent map rather than the active map or view")
	var future: String = _canonical(adapter)
	runner.assert_eq(adapter.load_game(path), OK, "normal load restores a mid-construction session with stock reservations")
	runner.assert_true(not ui.panel.visible and not adapter.world_sim.construction.blocked(target), "load discards UI future and restores pre-wall geometry")
	GameClock.advance_msec(300000)
	runner.assert_eq(_canonical(adapter), future, "shared motion, materials, worker and regional life resume the same entire future")
	var stable: String = _canonical(adapter)
	var damaged: Dictionary = WorldSessionSnapshot.capture(adapter)
	damaged.continuity.world.construction.projects[id].cell = [1, 1]
	runner.assert_true(WorldSessionSnapshot.stage(adapter, damaged).is_empty(), "bad footprint rejected before replacing any active navigation or world")
	runner.assert_eq(_canonical(adapter), stable, "failed spatial candidate leaves the live wall and session untouched")
	ui.show_panel()
	ui.select_cell(target)
	ui.act("demolish")
	GameClock.advance_msec(70000)
	runner.assert_true(fixture.world.is_walkable(target), "actual dismantling updates all original ground navigation")
	ui.act("recover")
	GameClock.advance_msec(30000)
	runner.assert_eq(adapter.world_sim.regions.home.inventory.quantity(id, "wood"), 0, "book recovery physically returns ground salvage")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	_fixtures._dispose(fixture)
	_test_actual_archive(runner)
	print("SCENARIO construction book: real terrain/ledger/motion, independent candidate obstacles and identical joint-session continuation")


func _canonical(adapter: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(adapter)), "", true, true)


func _test_actual_archive(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var path: String = "res://tests/fixtures/session_v16.json"
	var original: String = FileAccess.get_file_as_string(path)
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var adapter: WorldContinuityRuntime = main._continuity
	runner.assert_eq(adapter.load_game(ProjectSettings.globalize_path(path)), OK, "real N-book construction archive loads through the normal session path")
	runner.assert_eq(GameClock.elapsed_ms, 451445, "archive restores its original fractional work time")
	runner.assert_true(adapter.world_sim.construction.owns_actor("player") and adapter.world_sim.construction.projects["construction:1"].state == "blueprint", "archive contains unfinished paid construction, not invented finished scenery")
	GameClock.advance_msec(240000)
	var future: String = _canonical(adapter)
	runner.assert_true(adapter.world_sim.construction.blocked(Vector2i(263, 260)), "actual archived original material batch finishes as a real wall")
	main.free()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	main = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	adapter = main._continuity
	runner.assert_eq(adapter.load_game(ProjectSettings.globalize_path(path)), OK, "fresh main scene restores the genuine original construction file")
	GameClock.advance_msec(240000)
	runner.assert_eq(_canonical(adapter), future, "fresh-scene restart preserves all autonomous NPCs, physical costs and construction future")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "genuine archive is never rewritten to fit later code")
	main.free()
	GameClock.restore_state(prior)
