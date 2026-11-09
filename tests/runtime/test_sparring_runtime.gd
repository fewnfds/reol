extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	var home: VillageSimulation = fixture.home.simulation
	var player: PlayerCharacter = fixture.player
	for id: String in home.actors:
		home.actors[id].autonomous = false
	home.set_actor_position("shi_tou", player.motion.position + Vector2(80, 0))
	adapter._home.select_actor("shi_tou")
	runner.assert_true(bool(adapter.sparring_adapter.invite_selected().ok), "real runtime selection can invite a nearby consenting resident")
	runner.assert_true(not GameClock.request_wait(), "explicit wait cannot skip a player's current practice")
	runner.assert_true(not adapter.travel_to("river"), "automatic travel cannot continue in parallel with practice")
	runner.assert_true(adapter.sparring_adapter.strike(), "runtime can submit the actual phased palm strike")
	runner.assert_true(not player.request_sidestep(Vector2.LEFT), "preparation cannot overlap a second main short action")
	player._intent = Vector2.LEFT
	var point: Vector2 = player.motion.position
	GameClock.advance_msec(150)
	player._intent = Vector2.ZERO
	runner.assert_eq(player.motion.position, point, "runtime does not slide the body while a main strike owns motion")
	var path: String = "user://tests/practice_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(adapter.save_game(path), OK, "runtime saves preparation, body costs, NPC and common clock together")
	GameClock.advance_msec(600)
	var expected: int = JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(adapter)), "", true, true).hash()
	runner.assert_eq(adapter.load_game(path), OK, "runtime restores practice in the middle of preparation")
	GameClock.advance_msec(600)
	runner.assert_eq(JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(adapter)), "", true, true).hash(), expected, "runtime resume cannot pay again, repeat a hit or change the NPC's future")
	adapter.sparring_adapter.stop()
	runner.assert_true(not adapter.world_sim.sparring.owns_actor("player"), "runtime stop releases all practice execution")
	runner.assert_true(player.request_sidestep(Vector2.LEFT), "idle body regains the existing sidestep after practice")
	fixtures._dispose(fixture)
	_test_actual_sidestep_avoids_contact(runner)


func _test_actual_sidestep_avoids_contact(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	var home: VillageSimulation = fixture.home.simulation
	var player: PlayerCharacter = fixture.player
	for id: String in home.actors:
		home.actors[id].autonomous = false
	var point: Vector2 = player.motion.position
	home.set_actor_position("shi_tou", point + Vector2(80, 0))
	adapter._home.select_actor("shi_tou")
	runner.assert_true(bool(adapter.sparring_adapter.invite_selected().ok), "actual evasion sample begins with a consenting partner")
	GameClock.advance_msec(150)
	runner.assert_eq(adapter.world_sim.sparring.phase("shi_tou", GameClock.elapsed_ms), "prepare", "NPC gives a visible preparation window before the hit")
	runner.assert_true(player.request_sidestep(Vector2.LEFT), "an idle practice body can use its existing physical sidestep")
	runner.assert_true(adapter.world_sim.sparring.owns_actor("player"), "manual evasion preserves the consenting bout and its original phases")
	if not adapter.world_sim.sparring.owns_actor("player"):
		fixtures._dispose(fixture)
		return
	GameClock.advance_msec(400)
	runner.assert_true(player.motion.position.distance_to(point + Vector2(-120, 0)) < 0.1, "evasion is actual terrain-checked movement over shared time within subpixel precision")
	runner.assert_eq(home.actors.player.stamina, 92, "outside the fan, the body pays only its sidestep and receives no phantom hit")
	runner.assert_eq(adapter.world_sim.sparring.bout.people.shi_tou.hits, 0, "NPC cannot track its old palm through an opponent's genuine displacement")
	fixtures._dispose(fixture)
