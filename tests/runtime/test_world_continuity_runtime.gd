extends RefCounted
## Player-visible continuity checks against the real scene adapter and clock.

const Runtime = preload("res://scripts/runtime/world_continuity_runtime.gd")


class FlatMap extends WorldMapData:
	func terrain_is_walkable(cell: Vector2i) -> bool:
		return cell.x >= 0 and cell.x <= 90 and cell.y >= 0 and cell.y <= 90


	func get_elevation(_cell: Vector2i) -> int:
		return 0


	func independent_copy() -> WorldMapData:
		return FlatMap.new()


class FlatWorld extends ReolWorld:
	func _init() -> void:
		bind_map_data(FlatMap.new())


	func _ready() -> void:
		pass


func run(runner: Object) -> void:
	_test_actual_travel_reentry_and_npc_continuity(runner)
	_test_two_region_save_resumes_player_and_cargo(runner)


func _fixture(runner: Object, bundle: Dictionary = {}) -> Dictionary:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var content := ReolContentDB.new()
	var loaded: bool = content.load_all() if bundle.is_empty() else content.load_bundle(bundle)
	if not loaded:
		runner.assert_true(false, "two-region runtime fixture loads definitions")
		return {}
	var world := FlatWorld.new()
	var player := PlayerCharacter.new()
	player.setup_state(PawnState.create(content.get_pawn(&"player"), content))
	player.spawn_at(Vector2i(30, 30))
	var pawns: Array[Pawn] = []
	var index: int = 0
	for id: StringName in content.pawns:
		if id == &"player":
			continue
		var pawn := Pawn.new()
		pawn.setup(content.get_pawn(id), content, world, Vector2i(31 + index, 30))
		pawns.append(pawn)
		index += 1
	var home := VillageRuntime.new()
	home.restore_map_factory = func(_descriptor: Dictionary) -> WorldMapData: return FlatMap.new()
	var continuity := Runtime.new()
	var result: Dictionary = {
		"clock": saved_clock, "world": world, "player": player,
		"pawns": pawns, "home": home, "continuity": continuity,
	}
	if not home.setup(world, player, pawns, content) or not continuity.setup(home):
		runner.assert_true(false, "two connected settlements initialize through the runtime")
		_dispose(result)
		return {}
	return result


func _dispose(fixture: Dictionary) -> void:
	(fixture.continuity as Node).free()
	(fixture.home as Node).free()
	for pawn: Pawn in fixture.pawns:
		pawn.free()
	(fixture.player as Node).free()
	(fixture.world as Node).free()
	GameClock.restore_state(fixture.clock)


func _test_actual_travel_reentry_and_npc_continuity(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	if fixture.is_empty():
		return
	var runtime: Runtime = fixture.continuity
	var player: PlayerCharacter = fixture.player
	var start: Vector2i = player.cell
	var remote: VillageSimulation = runtime.world_sim.regions.river
	var identities: Array = remote.actors.keys()
	runner.assert_true(runtime._remote_views.is_empty(), "absent region has no instantiated NPC views")
	runner.assert_true(runtime.travel_to("river"), "player can order a terrain-backed journey to the other settlement")
	runner.assert_eq(player.cell, start, "travel order does not teleport the player")
	GameClock.advance_msec(100)
	runner.assert_eq(player.cell, start, "movement respects actual distance before its first grid crossing")
	GameClock.advance_msec(1000)
	runner.assert_true(player.cell != start, "journey moves through actual intermediate cells")
	runner.assert_true(not runtime.player_journey.is_empty(), "cross-settlement journey remains in flight")
	runtime.world_sim.synchronize_region("river")
	var actor_id: String = "river_lao_zhou"
	remote.cancel_action(actor_id, "fixture_new_work")
	remote.actors[actor_id].autonomous = false
	remote.set_actor_cell(actor_id, SimRouteTravel.cell(remote.places.dorm.cell.duplicate()))
	runner.assert_true(remote.submit_action(actor_id, "rest"), "distant person starts a concrete unfinished action")
	runtime.world_sim.invalidate_region("river")
	var action_id: String = str(remote.actors[actor_id].active.id)
	var stop: int = GameClock.tick_index + 250
	while not runtime.player_journey.is_empty() and GameClock.tick_index < stop:
		GameClock.advance_ticks(1)
	runner.assert_true(runtime.player_journey.is_empty(), "player reaches the other settlement after spending travel time")
	runner.assert_eq(player.cell, runtime.centers.river, "journey ends at its actual destination")
	runner.assert_eq(runtime.current_region, "river", "entering changes near-region presentation")
	runner.assert_true(runtime.world_sim.regions.river == remote, "arrival reuses the distant simulation rather than cold-initializing it")
	runner.assert_eq(remote.actors.keys(), identities, "arrival preserves the same persistent inhabitants")
	runner.assert_true(not runtime._remote_views.is_empty(), "near-region NPC views unfold from current state")
	# This fixture deliberately has no Fog node. Its fallback perception now
	# uses real distance too, so approaching the dorm is part of observing a
	# person whose original resting action began before the player arrived.
	runner.assert_true(runtime.travel_to("river", SimRouteTravel.cell(remote.actors[actor_id].cell)), "arrival can continue along a real route to the known resting place")
	while not runtime.player_journey.is_empty() and GameClock.tick_index < stop:
		GameClock.advance_ticks(1)
	runner.assert_true(runtime._remote_views.has(actor_id), "physically approaching the resting person makes the original body visible")
	if not runtime._remote_views.has(actor_id):
		_dispose(fixture)
		return
	var selected: Pawn = runtime._remote_views[actor_id]
	runtime._selected_remote = actor_id
	runtime._refresh_panel()
	runner.assert_eq(runtime._selected_remote, actor_id, "visible local inhabitant can remain selected")
	selected.visible = false
	runtime._refresh_panel()
	runner.assert_eq(runtime._selected_remote, "", "leaving sight clears the selection instead of revealing live remote activity")
	selected.visible = true
	runner.assert_true(not remote.actors[actor_id].active.is_empty(), "arrival can reveal an action that began before the player arrived")
	if not remote.actors[actor_id].active.is_empty():
		runner.assert_eq(remote.actors[actor_id].active.id, action_id, "arrival does not restart or replace the NPC's work")
	runtime.world_sim.synchronize_region("home")
	var resident_sim: VillageSimulation = runtime.world_sim.regions.home
	var continued: bool = not resident_sim.actors.shi_tou.active.is_empty()
	for event: Dictionary in resident_sim.social.events:
		continued = continued or event.actor == "shi_tou" and event.kind == "completed"
	runner.assert_true(resident_sim.actors.shi_tou.hunger < 65.0 and continued, "home resident spends time and either continues or actually finishes original work while player travels")
	runner.assert_true(runtime.travel_to("home"), "player can return along a real route")
	stop = GameClock.tick_index + 250
	while not runtime.player_journey.is_empty() and GameClock.tick_index < stop:
		GameClock.advance_ticks(1)
	runner.assert_eq(runtime.current_region, "home", "returning reconnects home presentation")
	runner.assert_true(runtime.world_sim.regions.river == remote, "leaving unloads views while keeping distant social state")
	runner.assert_true(runtime._remote_views.is_empty(), "distant NPC nodes can unload without freezing their simulation")
	print("SCENARIO visible continuity: travelled home→river→home in %d minutes; persistent residents retained" % GameClock.tick_index)
	_dispose(fixture)


func _test_two_region_save_resumes_player_and_cargo(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	if fixture.is_empty():
		return
	var runtime: Runtime = fixture.continuity
	GameClock.advance_ticks(27)
	runtime.travel_to("river")
	GameClock.advance_msec(100)
	var resident: String = "river_su_zhi"
	var distant: VillageSimulation = runtime.world_sim.regions.river
	runtime.world_sim.synchronize_region("river")
	distant.cancel_action(resident, "fixture_specific_journey")
	distant.actors[resident].autonomous = false
	distant.set_actor_cell(resident, SimRouteTravel.cell(distant.places.store.cell))
	runner.assert_true(distant.submit_action(resident, "inspect"), "absent resident starts a real walking job for the pending save")
	runtime.world_sim.invalidate_region("river")
	var path: String = "user://tests/world_continuity_%d.json" % Time.get_ticks_usec()
	var before_position: Vector2 = fixture.player.global_position
	var before_journey: Dictionary = _normal(runtime.player_journey)
	var before_world: String = _world_state(runtime)
	var before_clock: Dictionary = GameClock.to_dict()
	runner.assert_true(not runtime.player_journey.is_empty(), "save fixture is midway through player travel")
	runner.assert_true(not runtime.world_sim.shipments.is_empty(), "save fixture also contains an NPC cargo journey")
	runner.assert_eq(runtime.save_game(path), OK, "runtime saves both settlements and their in-flight work")
	GameClock.advance_ticks(100)
	var expected_world: String = _world_state(runtime)
	var expected_position: Vector2 = fixture.player.global_position
	var expected_journey: Dictionary = _normal(runtime.player_journey)
	runner.assert_eq(runtime.load_game(path), OK, "runtime reloads a coherent two-settlement snapshot")
	runner.assert_eq(fixture.player.global_position, before_position, "load restores the exact point along the player route")
	runner.assert_eq(_normal(runtime.player_journey), before_journey, "load restores remaining player steps and movement timer")
	runner.assert_eq(GameClock.to_dict(), before_clock, "load restores the shared clock")
	runner.assert_true(_world_state(runtime) == before_world, "load restores distant work, messages, cargo and institutional state")
	var invalid_remote: Dictionary = SimSaveStore.load_file(path).data
	var remote_actor: Dictionary = {}
	for actor: Dictionary in invalid_remote.continuity.world.regions.river.actors.values():
		if not actor.active.is_empty() and not actor.active.path.is_empty():
			remote_actor = actor
			break
	runner.assert_true(not remote_actor.is_empty(), "saved remote village includes a real unfinished walking route")
	if not remote_actor.is_empty():
		remote_actor.active.path[0] = [90, 90]
		runner.assert_eq(SimSaveStore.save_file(path, invalid_remote), OK, "bad remote route fixture remains valid JSON")
		var before_invalid: String = _world_state(runtime)
		runner.assert_true(runtime.load_game(path) != OK, "remote route with an impossible terrain jump is rejected")
		runner.assert_true(_world_state(runtime) == before_invalid, "bad remote route cannot replace a live distant executor")
	GameClock.advance_ticks(100)
	runner.assert_true(_world_state(runtime) == expected_world, "loaded player and distant NPC journeys produce identical continuation")
	runner.assert_eq(fixture.player.global_position, expected_position, "continued travel reaches the same exact position")
	runner.assert_eq(_normal(runtime.player_journey), expected_journey, "continued travel retains the same remaining work")
	var loaded: Dictionary = SimSaveStore.load_file(path)
	if loaded.get("ok", false):
		var bad: Dictionary = loaded.data
		bad.continuity.player_journey.path = [[90, 90]]
		SimSaveStore.save_file(path, bad)
		var healthy: String = _world_state(runtime)
		var healthy_position: Vector2 = fixture.player.global_position
		runner.assert_true(runtime.load_game(path) != OK, "disconnected saved player route is rejected")
		runner.assert_true(_world_state(runtime) == healthy, "invalid journey cannot partly replace the two-region world")
		runner.assert_eq(fixture.player.global_position, healthy_position, "invalid journey leaves current player location intact")
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		var file: String = ProjectSettings.globalize_path(path + suffix)
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	print("SCENARIO visible save: player route and NPC cargo resume together through minute %d" % GameClock.tick_index)
	_dispose(fixture)


func _normal(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true, true))


func _world_state(runtime: Runtime) -> String:
	return JSON.stringify(_normal(runtime.world_sim.to_dict()), "", true, true)
