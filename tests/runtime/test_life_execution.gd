extends RefCounted
## Shared-time regression: partial routes, exact work durations and recovery.

const VillageFixtures = preload("res://tests/sim/test_village_simulation.gd")
const RuntimeFixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
var _village_fixtures: RefCounted = VillageFixtures.new()


func run(runner: Object) -> void:
	_test_native_duration(runner)
	_test_sparse_matches_fine(runner)
	_test_recovery_remainder(runner)
	_test_journey_restore(runner)
	_test_visitor_duration(runner)
	_test_legacy_single_fraction(runner)


func _state(sim: VillageSimulation) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(sim.to_dict(), "", true, true)), "", true, true)


func _test_native_duration(runner: Object) -> void:
	var sim: VillageSimulation = _village_fixtures._make_simulation(runner)
	sim.advance_to_ms(59950)
	sim.set_actor_cell("player", SimRouteTravel.cell(sim.places.kitchen.cell))
	runner.assert_true(sim.submit_action("player", "check_kitchen"), "native visit can begin just before a minute boundary")
	var arrival: int = int(sim.actors.player.active.due_ms)
	sim.advance_to_ms(arrival)
	var finish: int = int(sim.actors.player.active.due_ms)
	runner.assert_eq(finish - arrival, 120000, "native work owes two complete minutes from its actual arrival")
	sim.advance_to_ms(finish - 1)
	runner.assert_true(not sim.actors.player.active.is_empty(), "minute crossings cannot grant early labor completion")
	sim.advance_to_ms(finish)
	runner.assert_true(sim.actors.player.active.is_empty(), "native work finishes at its exact millisecond boundary")
	var actor: String = "shi_tou"
	var start: Vector2 = sim.actor_position(sim.actors[actor])
	runner.assert_true(sim.submit_action(actor, "deliver_water"), "NPC uses the same continuous route implementation")
	sim.advance_to_ms(finish + 100)
	var distance: float = start.distance_to(sim.actor_position(sim.actors[actor]))
	runner.assert_true(distance > 23.0 and distance <= 24.01, "NPC travels about 24 pixels in 100ms at the shared 240px/s speed")
	var restored: VillageSimulation = _village_fixtures._make_simulation(runner)
	runner.assert_true(restored.restore(JSON.parse_string(JSON.stringify(sim.to_dict()))), "mid-segment NPC state validates and restores")
	for target: int in [finish + 133, finish + 999, finish + 301234]:
		sim.advance_to_ms(target)
		restored.advance_to_ms(target)
		runner.assert_eq(_state(restored), _state(sim), "NPC continuation preserves position, cargo and original completion at %d" % target)


func _test_sparse_matches_fine(runner: Object) -> void:
	var fine: VillageSimulation = _village_fixtures._make_simulation(runner, true)
	var sparse: VillageSimulation = _village_fixtures._make_simulation(runner, true)
	for target: int in [12345, 60049, 210345]:
		while fine.elapsed_ms < target:
			fine.advance_to_ms(mini(target, fine.elapsed_ms + 50))
		runner.assert_true(sparse.advance_to_ms(target), "absent-region simulation can jump to a fractional minute")
		runner.assert_eq(_state(sparse).hash(), _state(fine).hash(), "sparse and fine movement, needs, memories and RNG match at %dms" % target)
	print("SCENARIO life execution: NPC routes and needs match 50ms steps at fractional sparse targets")


func _test_recovery_remainder(runner: Object) -> void:
	var sim: VillageSimulation = _village_fixtures._make_simulation(runner)
	sim.advance_to_ms(137)
	var motion := SimLocalMotion.new()
	motion.bind_body(sim.actors.player)
	runner.assert_true(motion.begin_sidestep(sim.elapsed_ms, Vector2.RIGHT, sim.actors.player), "short action spends the persistent body's stamina")
	var recovery_at: int = int(sim.actors.player.exertion_until_ms)
	sim.advance_to_ms(recovery_at)
	runner.assert_eq(sim.actors.player.stamina, 92, "recovery cannot run during exertion or its delay")
	sim.advance_to_ms(recovery_at + 124)
	runner.assert_eq(sim.actors.player.stamina, 92, "fractional recovery cannot grant a whole stamina unit early")
	runner.assert_eq(sim.actors.player.stamina_carry, 992, "recovery retains its exact sub-unit numerator")
	var restored: VillageSimulation = _village_fixtures._make_simulation(runner)
	runner.assert_true(restored.restore(JSON.parse_string(JSON.stringify(sim.to_dict()))), "recovery remainder survives a real JSON round trip")
	sim.advance_to_ms(recovery_at + 125)
	runner.assert_eq(sim.actors.player.stamina, 93, "one stamina unit is restored only after its full 125ms")
	while restored.elapsed_ms < recovery_at + 1001:
		restored.advance_to_ms(mini(recovery_at + 1001, restored.elapsed_ms + 17))
	sim.advance_to_ms(recovery_at + 1001)
	runner.assert_eq(sim.actors.player.stamina, 100, "finite short action recovery stops at the original body's cap")
	runner.assert_eq(_state(restored), _state(sim), "small and sparse recovery steps preserve exact needs and remainders")


func _test_journey_restore(runner: Object) -> void:
	var fixtures := RuntimeFixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	var player: PlayerCharacter = fixture.player
	var start: Vector2 = player.motion.position
	runner.assert_true(adapter.travel_to("river"), "automatic journey begins from the same body")
	GameClock.advance_msec(100)
	runner.assert_true(player.motion.position.distance_to(start) > 23 and player.motion.position.distance_to(start) <= 24.01, "automatic travel has the same physical route speed as NPC work")
	var point: Vector2 = player.motion.position
	var path: String = "user://tests/life_route_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(adapter.save_game(path), OK, "partial route is saved before its first cell center")
	GameClock.advance_msec(1100)
	var expected: Dictionary = WorldSessionSnapshot.capture(adapter)
	runner.assert_eq(adapter.load_game(path), OK, "partial automatic route restores without snapping to a cell")
	runner.assert_eq(player.motion.position, point, "automatic-route restore preserves the precise single body point")
	GameClock.advance_msec(1100)
	runner.assert_eq(JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(adapter)), "", true, true).hash(), JSON.stringify(VillageRuntime._json_normalized(expected), "", true, true).hash(), "restored journey, remote people and clock reach the identical future")
	fixtures._dispose(fixture)


func _test_visitor_duration(runner: Object) -> void:
	var fixtures := RuntimeFixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	GameClock.advance_msec(59950)
	var home: VillageSimulation = fixture.home.simulation
	fixture.player.spawn_at(SimRouteTravel.cell(home.places.kitchen.cell))
	fixture.home._sync_player_cell()
	home.inventory.containers["actor:player"]["meal"] = 1
	var result: Dictionary = adapter.world_sim.services.begin("player", "home", "eat")
	runner.assert_true(bool(result.ok), "visitor meal begins at a precise late-minute time")
	var job: Dictionary = adapter.world_sim.services.jobs[result.id]
	GameClock.advance_msec(int(job.due_ms) - GameClock.elapsed_ms)
	var finish: int = int(job.due_ms)
	runner.assert_eq(finish - int(job.segment_started_ms), int(job.spec.minutes) * 60000, "visitor's full eating duration begins at actual arrival")
	GameClock.advance_msec(finish - GameClock.elapsed_ms - 1)
	runner.assert_eq(home.inventory.quantity("actor:player", "meal"), 1, "visitor cannot consume the meal one millisecond early")
	GameClock.advance_msec(1)
	runner.assert_eq(home.inventory.quantity("actor:player", "meal"), 0, "visitor consumes the actual meal at its completion boundary")
	runner.assert_true(not adapter.world_sim.services.owns_actor("player"), "precise completion releases the visitor body")
	fixtures._dispose(fixture)


func _test_legacy_single_fraction(runner: Object) -> void:
	var content := ReolContentDB.new()
	runner.assert_true(content.load_all(), "legacy standalone migration loads the actual content")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/session_v5.json"))
	source.erase("continuity")
	var upgraded: Dictionary = SessionSaveSchema.upgrade(source, content)
	runner.assert_true(not upgraded.is_empty(), "a standalone v5 fractional clock can follow the explicit migration chain")
	if upgraded.is_empty():
		return
	runner.assert_eq(upgraded.simulation.elapsed_ms, 2800, "standalone migration anchors native life to the same captured milliseconds")
	runner.assert_eq(upgraded.simulation.tick_index, source.simulation.tick_index, "standalone migration does not replay an unknown partial minute")
	var restored := VillageSimulation.new()
	var cells: Dictionary = {}
	for id: String in upgraded.simulation.actors:
		cells[id] = upgraded.simulation.actors[id].cell
	runner.assert_true(restored.initialize(content, upgraded.simulation.config, cells, upgraded.simulation.places) and restored.restore(upgraded.simulation), "standalone native candidates retain valid routes after phase anchoring")
