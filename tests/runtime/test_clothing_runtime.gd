extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")
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
	# Current timed handling is above; test_clothing.gd also restores a real
	# pending rain dressing and checks dry/wet continuity across fine steps.
	LegacyRejection.run(runner, {
		"res://tests/fixtures/session_v27.json": "ad45652fbdc5cc6db88e0af152cb4074a171e65f7948abfa5e9b79243f23e502",
		"res://tests/fixtures/session_v28.json": "72b76bfaafdf0b8ea740cacdeffe0332f1326e1b12919bbe7bf6d9f790626f23",
	}, ["clothing"])
	print("SCENARIO wardrobe runtime: actual approach/taking, continuous body ownership, visible robe projection, nonhuman limits and identical joint continuation")


func _select(wardrobe: ClothingRuntime, id: String) -> void:
	for index: int in wardrobe.choice.item_count:
		if wardrobe.choice.get_item_metadata(index) == id:
			wardrobe.choice.select(index)
			break


func _canonical(adapter: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(adapter)), "", true, true)
