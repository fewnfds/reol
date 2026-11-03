extends RefCounted
## Shared original bodies and read-only wardrobe/near views, including migration.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
var fixtures := Fixtures.new()


func run(runner: Object) -> void:
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	var player: PlayerCharacter = fixture.player
	var wardrobe: ClothingRuntime = adapter.clothing_adapter
	var original: String = _canonical(adapter)
	wardrobe.panel.show()
	wardrobe.refresh()
	wardrobe.preview_direction.select(6)
	wardrobe.preview_action.select(1)
	wardrobe.preview_accessories.button_pressed = true
	wardrobe.update_preview_pose()
	runner.assert_eq(_canonical(adapter), original, "preview turning/animated sword and jade never turn bodies, grant things or spend world time")
	var sample: Dictionary = HumanoidAppearance.shared().sample(wardrobe.preview.body.pose)
	runner.assert_eq(sample.direction_id, "W", "wardrobe uses the same explicit eight-direction sampler")
	runner.assert_eq(sample.action, "walk", "wardrobe's walk preview uses the shared action contract")
	runner.assert_true(not bool(player.appearance_pose.get("technical_accessories", false)), "technical accessories are never automatically equipped by the player's normal view")
	for pawn: Pawn in fixture.home._pawns.values():
		runner.assert_true(not pawn.appearance_pose.is_empty(), "native resident view receives original body pose")
		runner.assert_true(not bool(pawn.appearance_pose.get("technical_accessories", false)), "native resident is not granted technical preview gear")
	runner.assert_true(adapter.travel_to("river"), "animation test starts the original physical journey")
	GameClock.advance_msec(73)
	runner.assert_true(not adapter.player_journey.is_empty(), "real continuous route remains in progress")
	runner.assert_eq(player.appearance_pose.action, "walk", "player's original timed route selects shared walking frames")
	runner.assert_true((player.appearance_pose.direction as Vector2).is_equal_approx(player.motion.facing), "automatic travel updates the same heading seen by the player motion facade")
	var saved: Dictionary = WorldSessionSnapshot.capture(adapter)
	var expected_pose: Dictionary = player.appearance_pose.duplicate(true)
	var target_time: int = GameClock.elapsed_ms
	GameClock.set_paused(true)
	wardrobe.preview.body._process(1.0)
	var paused_frame: Dictionary = HumanoidAppearance.shared().sample(wardrobe.preview.body.pose)
	wardrobe.preview.body._process(10.0)
	runner.assert_eq(HumanoidAppearance.shared().sample(wardrobe.preview.body.pose), paused_frame, "real seconds alone cannot advance a paused preview")
	runner.assert_eq(GameClock.elapsed_ms, target_time, "drawing paused frames never advances original world time")
	GameClock.advance_msec(120000)
	var expected: String = _canonical(adapter)
	var path: String = "user://tests/humanoid_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(SimSaveStore.save_file(path, saved), OK, "physical journey is archived with persistent original headings")
	runner.assert_eq(adapter.load_game(path), OK, "normal loader reconstructs the in-progress eight-way body")
	runner.assert_eq(player.appearance_pose.action, expected_pose.action, "reloaded continuous route resumes the same action")
	runner.assert_eq(HumanoidAppearance.shared().sample(player.appearance_pose).frame, HumanoidAppearance.shared().sample(expected_pose).frame, "reloaded original time resumes the exact shared walking frame")
	GameClock.set_paused(true)
	GameClock.advance_msec(120000)
	runner.assert_eq(_canonical(adapter), expected, "body-heading save continues to exactly the same entire world future")
	runner.assert_eq(adapter.current_region, "river", "real physical journey reaches the distant settlement")
	runner.assert_true(not adapter._remote_views.is_empty(), "distant original residents regain their own near views")
	for id: String in adapter._remote_views:
		var pawn: Pawn = adapter._remote_views[id]
		runner.assert_true(not HumanoidAppearance.shared().sample(pawn.appearance_pose).is_empty(), "distant near view shares the same complete animation contract")
	var live_before: String = _canonical(adapter)
	var wrong: Dictionary = WorldSessionSnapshot.capture(adapter)
	wrong.player.motion.facing = [-float(wrong.player.motion.facing[0]), -float(wrong.player.motion.facing[1])]
	runner.assert_true(WorldSessionSnapshot.stage(adapter, wrong).is_empty(), "two conflicting persisted player headings are rejected")
	runner.assert_eq(_canonical(adapter), live_before, "failed heading candidate cannot change live body, things or time")
	player._intent = Vector2.RIGHT
	var move_from: Vector2 = player.motion.position
	GameClock.advance_msec(200)
	runner.assert_true(not move_from.is_equal_approx(player.motion.position) and player.appearance_pose.action == "walk", "manual movement selects walking only after real original displacement")
	player._intent = Vector2.ZERO
	GameClock.advance_msec(300)
	runner.assert_true(player.motion.velocity.is_zero_approx() and player.appearance_pose.action == "idle", "a coarse advance ending at rest shows idle immediately instead of retaining its earlier walking state")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	fixtures._dispose(fixture)
	_pose_edges(runner)
	print("SCENARIO eight-way runtime: shared human/near/preview pose, actual route, paused sample, no preview grants, consistent candidate and identical continuation")


func _canonical(adapter: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(adapter)), "", true, true)


func _pose_edges(runner: Object) -> void:
	var body: Dictionary = {"position": [32.0, 32.0], "cell": [0, 0], "facing": [1.0, 0.0], "active": {}}
	var before: Dictionary = body.duplicate(true)
	var pose: Dictionary = HumanoidPose.from_body(body, 450)
	runner.assert_eq(pose.action, "idle", "a remembered nonzero facing does not mean walking at a wall")
	var route: Dictionary = {"path": [[1, 0]], "segment_from": [32.0, 32.0], "segment_started_ms": 0, "due_ms": 1000, "road_paused": true}
	runner.assert_eq(HumanoidPose.from_body(body, 450, route).action, "idle", "a closed road does not produce on-the-spot walking")
	route.road_paused = false
	runner.assert_eq(HumanoidPose.from_body(body, 450, route).action, "walk", "a valid current route produces walking without moving a presentation-owned body")
	runner.assert_eq(body, before, "pose projection never writes original coordinates or remembered heading")
