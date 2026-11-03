extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var player: PlayerCharacter = fixture.player
	var adapter: WorldContinuityRuntime = fixture.continuity
	var start: Vector2 = player.motion.position
	player._intent = Vector2.RIGHT
	player._physics_process(0.5)
	runner.assert_eq(player.global_position, start, "physics/input sampling alone cannot move the shared body")
	player._intent = Vector2.RIGHT
	GameClock.advance_msec(150)
	player._intent = Vector2.ZERO
	runner.assert_true(player.global_position.x > start.x, "only committed fine world steps move the actual body")
	var stamina: int = int(fixture.home.simulation.actors.player.stamina)
	runner.assert_true(player.request_sidestep(Vector2.RIGHT), "runtime starts short action through existing control and body")
	runner.assert_eq(int(fixture.home.simulation.actors.player.stamina), stamina - 8, "runtime cost belongs to the original simulation body")
	runner.assert_true(not fixture.home.simulation.submit_action("player", "check_kitchen"), "minute labor cannot own a body while a short action is active")
	runner.assert_true(not bool(adapter.world_sim.services.begin("player", "home", "rest").ok), "visitor work cannot share a short-action body")
	runner.assert_true(not adapter.travel_to("river"), "automatic travel cannot overwrite a short action")
	runner.assert_true(not GameClock.request_wait(), "world wait is refused during a short action")
	GameClock.advance_msec(200)
	GameClock.set_paused(true)
	var saved: Dictionary = WorldSessionSnapshot.capture(adapter)
	var midway: Vector2 = player.global_position
	runner.assert_eq(GameClock.tick_index, 0, "seconds of movement do not advance minute products or distant facts early")
	runner.assert_eq(fixture.home.simulation.actors.player.cell, [player.cell.x, player.cell.y], "continuous body updates its single grid projection immediately")
	var path: String = "user://tests/shared_action_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(adapter.save_game(path), OK, "fractional-minute in-flight body saves through the joint store")
	GameClock.advance_msec(350)
	var final_position: Vector2 = player.global_position
	var final_world: Dictionary = adapter.world_sim.to_dict()
	runner.assert_eq(adapter.load_game(path), OK, "joint load restores one precise in-flight body")
	runner.assert_eq(GameClock.elapsed_ms, 350, "load retains milliseconds inside the original minute")
	runner.assert_eq(player.global_position, midway, "load restores exact continuous location")
	runner.assert_eq(int(fixture.home.simulation.actors.player.stamina), stamina - 8, "loading the pending action does not spend a second time")
	GameClock.advance_msec(350)
	runner.assert_eq(player.global_position, final_position, "resumed action reaches exactly the same endpoint")
	runner.assert_eq(VillageRuntime._json_normalized(adapter.world_sim.to_dict()), VillageRuntime._json_normalized(final_world), "short action leaves the identical minute world")
	var bad: Dictionary = saved.duplicate(true)
	bad.player.motion.action.direction = [3, 0]
	runner.assert_eq(SimSaveStore.save_file(path, bad), OK, "bad trajectory fixture writes valid JSON")
	var unchanged: String = JSON.stringify(WorldSessionSnapshot.capture(adapter), "", true, true)
	runner.assert_true(adapter.load_game(path) != OK, "bad saved short action is rejected before replacement")
	runner.assert_eq(JSON.stringify(WorldSessionSnapshot.capture(adapter), "", true, true), unchanged, "bad trajectory cannot partially replace world/body/time")
	player._intent = Vector2.RIGHT
	GameClock.advance_msec(6000)
	player._intent = Vector2.ZERO
	runner.assert_eq(adapter.current_region, "river", "entering another settlement refreshes local interactions before a full minute")
	runner.assert_eq(GameClock.tick_index, 0, "local arrival never forces future minute work early")
	var body: String = adapter.world_sim.embodiment.carrier_for_source("village_actor", "player")
	player.request_sidestep(Vector2.LEFT)
	adapter.world_sim.embodiment.release_control("subject:player", body, "motion")
	GameClock.advance_msec(50)
	runner.assert_true(player.motion.action.is_empty(), "same control loss stops real fine motion on its next shared step")
	adapter.world_sim.embodiment.grant_control("subject:player", body, "motion")
	adapter.world_sim.set_active_region("home")
	player.spawn_at(Vector2i(30, 30))
	fixture.home._sync_player_cell()
	fixture.home.simulation.actors.player.stamina = 0
	runner.assert_true(fixture.home.simulation.submit_action("player", "check_kitchen"), "exhausted body can still arrange a normal visit")
	var job: Dictionary = fixture.home.simulation.actors.player.active.duplicate(true)
	runner.assert_true(not player.request_sidestep(Vector2.RIGHT), "exhausted body refuses an exertion command")
	runner.assert_eq(fixture.home.simulation.actors.player.active, job, "refused short command does not cancel unrelated pending work")
	fixtures._dispose(fixture)
	print("SCENARIO shared time: fixed movement→short action→joint fractional save→same future, no concurrent labor/travel/wait")
