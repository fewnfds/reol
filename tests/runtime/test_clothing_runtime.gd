extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
var fixtures := Fixtures.new()


func run(runner: Object) -> void:
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	var wardrobe: ClothingRuntime = adapter.clothing_adapter
	var player: PlayerCharacter = fixture.player
	var sim: VillageSimulation = adapter.world_sim.regions.home
	runner.assert_true(wardrobe != null, "normal world assembles the clothing adapter")
	wardrobe.panel.show()
	wardrobe.refresh()
	runner.assert_true(not wardrobe.visible_objects().has("clothing:spare:0"), "distant stored personal clothes are not remotely listed")
	wardrobe.approach()
	runner.assert_true(not adapter.player_journey.is_empty(), "wardrobe approach uses an actual original player journey")
	GameClock.advance_msec(60000)
	runner.assert_true(adapter.player_journey.is_empty() and player.cell == SimRouteTravel.cell(sim.places.dorm.cell), "walking spends common time and arrives at the real stored clothes")
	wardrobe.refresh()
	runner.assert_true(wardrobe.visible_objects().has("clothing:spare:0"), "nearby owned clothing becomes available after actual arrival")
	_select(wardrobe, "clothing:spare:0")
	# Stopping between cell centers is normal in a continuous movement world.
	player.motion.relocate(TileGrid.cell_to_world(player.cell) + Vector2(3.5, 0))
	adapter.prepare_player_command()
	var position: Vector2 = player.motion.position
	wardrobe.act("take")
	runner.assert_true(adapter.world_sim.clothing.owns_actor("player"), "UI submits the same timed physical taking rule")
	runner.assert_true(not adapter.travel_to("river"), "travel cannot own the same body as handling clothes")
	runner.assert_true(not player.request_sidestep(Vector2.RIGHT), "short action cannot start during clothing work")
	runner.assert_true(player.motion.position.is_equal_approx(position), "handling clothes does not snap a continuous body to a cell center")
	GameClock.advance_msec(1000)
	var path: String = "user://tests/clothing_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(adapter.save_game(path), OK, "original joint save captures garment handling mid-action")
	GameClock.advance_msec(360000)
	var future: String = _canonical(adapter)
	runner.assert_true(adapter.world_sim.clothing.held("player", "clothing:spare:0"), "pending taking finishes once through the real scene clock")
	runner.assert_eq(adapter.load_game(path), OK, "candidate loader resumes original continuous body and pending garment")
	GameClock.advance_msec(360000)
	runner.assert_eq(_canonical(adapter), future, "ordinary runtime mid-change load reaches exactly the same full world future")
	wardrobe.panel.show()
	wardrobe.refresh()
	_select(wardrobe, "clothing:robe:player")
	wardrobe.act("remove")
	GameClock.advance_msec(5000)
	wardrobe.refresh()
	_select(wardrobe, "clothing:spare:0")
	wardrobe.act("wear")
	GameClock.advance_msec(5000)
	runner.assert_eq(player.clothing_appearance.body.color, "#345b79", "normal player view gets its changed robe from the one worn physical object")
	adapter.avatar_subject = "subject:avian:home_sparrow"
	wardrobe.refresh()
	runner.assert_true(not wardrobe.panel.visible, "a nonhuman controlled life cannot use the human clothing page")
	adapter.avatar_subject = "subject:player"
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	fixtures._dispose(fixture)
	_legacy(runner)
	_real_archive(runner)
	print("SCENARIO wardrobe runtime: actual approach/taking, continuous body ownership, visible robe projection, nonhuman limits and identical joint continuation")


func _select(wardrobe: ClothingRuntime, id: String) -> void:
	for index: int in wardrobe.choice.item_count:
		if wardrobe.choice.get_item_metadata(index) == id:
			wardrobe.choice.select(index)
			break


func _canonical(adapter: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(adapter)), "", true, true)


func _legacy(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var path: String = "res://tests/fixtures/session_v27.json"
	var original: String = FileAccess.get_file_as_string(path)
	var adapter: WorldContinuityRuntime = main._continuity
	runner.assert_eq(adapter.load_game(ProjectSettings.globalize_path(path)), OK, "genuine old autonomous world migrates through the normal loader")
	runner.assert_true(not adapter.world_sim.clothing.seeded and adapter.world_sim.clothing.objects.is_empty(), "legacy worlds get no invented clothes or historical rain exposure")
	runner.assert_eq(GameClock.elapsed_ms, 4050050, "empty clothing migration preserves the real common fractional time")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "real old clothing-free fixture stays untouched")
	main.free()
	GameClock.restore_state(prior)


func _real_archive(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var path: String = "res://tests/fixtures/session_v28.json"
	var original: String = FileAccess.get_file_as_string(path)
	var expected: String = ""
	for attempt: int in 2:
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var adapter: WorldContinuityRuntime = main._continuity
		var loaded: Error = adapter.load_game(ProjectSettings.globalize_path(path))
		runner.assert_eq(loaded, OK, "real clicked v28 rain-dressing archive loads into a fresh scene")
		if loaded != OK:
			main.free()
			continue
		runner.assert_eq(GameClock.elapsed_ms, 1445000, "real archive preserves the fractional rain exposure and original time")
		runner.assert_eq(adapter.world_sim.clothing.active.player.verb, "wear", "actual archive is saved while the outer garment is still being put on")
		runner.assert_eq(adapter.world_sim.clothing.objects["clothing:spare:0"].wet, 60, "original inner garment retains its real prior rain exposure")
		runner.assert_true(not adapter.world_sim.clothing.objects["clothing:spare:1"].worn, "pending outer clothing grants no early shelter")
		GameClock.advance_msec(3600000)
		runner.assert_eq(GameClock.elapsed_ms, 5045000, "one real hour of autonomous world time follows the archived change")
		runner.assert_true(adapter.world_sim.clothing.objects["clothing:spare:1"].worn, "same physical cape finishes being worn exactly once")
		runner.assert_eq(adapter.world_sim.clothing.objects["clothing:spare:0"].wet, 0, "protected inner garment gradually dries through the original weather pulses")
		var state: String = _canonical(adapter)
		if attempt == 0:
			expected = state
		else:
			runner.assert_eq(state, expected, "independent normal scenes resume the entire real dressing archive to one identical future")
		main.free()
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "genuine clothing archive is never regenerated or rewritten by tests")
	GameClock.restore_state(prior)
