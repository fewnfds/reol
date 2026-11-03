extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	var body: String = world.embodiment.carrier_for_source("village_actor", "player")
	var subject: String = world.embodiment.subject_for_actor("player")
	runner.assert_true(fixture.player.has_motion_control(), "actual player view queries current authority")
	runner.assert_true(runtime.travel_to("river"), "authorized player begins existing continuous journey")
	GameClock.advance_ticks(3)
	var position_before: Vector2 = fixture.player.global_position
	var goods_before: Dictionary = fixture.home.simulation.inventory.to_dict()
	world.embodiment.release_control(subject, body, "motion")
	world.invalidate_region("home")
	runner.assert_true(not fixture.player.has_motion_control(), "manual movement sees a lost motion channel")
	fixture.player._world = fixture.world
	fixture.player._clock = GameClock
	Input.action_press("move_right")
	fixture.player._physics_process(0.1)
	Input.action_release("move_right")
	runner.assert_eq(fixture.player.global_position, position_before, "WASD cannot move a body without motion control")
	runner.assert_true(not runtime.travel_to("home"), "automatic travel command obeys the same control")
	GameClock.advance_ticks(1)
	runner.assert_true(runtime.player_journey.is_empty(), "already queued travel stops without teleporting")
	runner.assert_eq(fixture.player.global_position, position_before, "loss of travel control preserves the actual position")
	runner.assert_eq(fixture.home.simulation.inventory.to_dict(), goods_before, "stopping motion does not create a replacement bag")
	runner.assert_true(not bool(world.services.begin("player", "home", "rest").ok), "visitor services cannot bypass motion control")
	world.embodiment.grant_control(subject, body, "motion")
	world.embodiment.release_control(subject, body, "action")
	runner.assert_true(not bool(runtime.start_home_work("deliver_wood").ok), "playable labor command obeys action channel")
	world.embodiment.release_control(subject, body, "communication")
	var sim: VillageSimulation = fixture.home.simulation
	sim.cancel_action("chen_shouzhuo", "fixture_conversation")
	sim.actors.chen_shouzhuo.autonomous = false
	sim.set_actor_cell("chen_shouzhuo", SimRouteTravel.cell(sim.actors.player.cell.duplicate()))
	var events: int = sim.social.events.size()
	runner.assert_true(not bool(sim.tell_stock("player", "chen_shouzhuo", "kitchen", "wood", 0).ok), "silent subject cannot create spoken testimony")
	runner.assert_true(not bool(sim.ask_stock("player", "chen_shouzhuo", "kitchen", "wood").ok), "asking also requires one's communication channel")
	runner.assert_eq(sim.social.events.size(), events, "rejected speech leaves no fabricated event")
	var staged: Dictionary = WorldSessionSnapshot.stage(runtime, WorldSessionSnapshot.capture(runtime))
	runner.assert_true(not staged.is_empty(), "idle player with missing channels is a valid saved state")
	if not staged.is_empty():
		runner.assert_true(not staged.world.actor_controls("player", "action") and not staged.world.actor_controls("player", "communication"), "joint staging preserves distinct losses of control")
	fixtures._dispose(fixture)
