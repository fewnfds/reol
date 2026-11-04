extends RefCounted
## Exercise the runtime-owned journey through its real travel and save paths.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_real_journey_and_restore(runner)
	_real_door_close_during_journey(runner)
	print("SCENARIO runtime motion clearance: actual diagonal journey, crossed leg and candidate/load, timed door and continuation")


func _real_journey_and_restore(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var player: PlayerCharacter = fixture.player
	var origin: Vector2i = player.cell
	var destination: Vector2i = origin + Vector2i(3, 3)
	runner.assert_true(not runtime._incoming_occupancy(origin), "an idle runtime has no journey reservation")
	var started: bool = runtime.travel_to("home", destination)
	runner.assert_true(started, "runtime accepts a real multi-step diagonal travel order")
	if not started or runtime.player_journey.get("path", []).size() < 2:
		runner.assert_true(false, "travel order supplies a current leg and a later leg")
		_fixtures._dispose(fixture)
		return
	var journey: Dictionary = runtime.player_journey
	var target: Vector2i = SimRouteTravel.cell(journey.path[0])
	var future: Vector2i = SimRouteTravel.cell(journey.path[1])
	var step: Vector2i = target - origin
	var diagonal: bool = absi(step.x) == 1 and absi(step.y) == 1
	runner.assert_true(diagonal, "the actual first path segment is diagonal")
	if not diagonal:
		_fixtures._dispose(fixture)
		return
	var side_x: Vector2i = origin + Vector2i(step.x, 0)
	var side_y: Vector2i = origin + Vector2i(0, step.y)
	var stable: String = _canonical(runtime)
	_assert_reservations(runner, runtime, [origin, target, side_x, side_y], future, "starting leg")
	runner.assert_eq(_canonical(runtime), stable, "reservation reads do not change the original session")
	var started_ms: int = int(journey.segment_started_ms)
	var due_ms: int = int(journey.due_ms)
	var cross_at: int = started_ms + floori(float(due_ms - started_ms) * 0.75)
	GameClock.advance_msec(cross_at - GameClock.elapsed_ms)
	var body: Dictionary = runtime.world_sim.regions.home.actors.player
	if runtime.player_journey.is_empty() or runtime.player_journey.get("path", []).is_empty():
		runner.assert_true(false, "the real journey remains active before its first center")
		_fixtures._dispose(fixture)
		return
	runner.assert_eq(SimRouteTravel.cell(body.cell), target, "actual time advance crosses into the target cell")
	runner.assert_true(not SimRouteTravel.point(body).is_equal_approx(TileGrid.cell_to_world(target)), "the original body has not yet reached the target center")
	runner.assert_eq(SimRouteTravel.cell(runtime.player_journey.path[0]), target, "the old first leg is not consumed before reaching its center")
	_assert_reservations(runner, runtime, [origin, target, side_x, side_y], future, "after crossing before center")

	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var before_stage: String = _canonical(runtime)
	var candidate: Dictionary = WorldSessionSnapshot.stage(runtime, snapshot)
	runner.assert_true(not candidate.is_empty(), "the genuine crossed-leg session stages as an independent candidate")
	if not candidate.is_empty():
		var staged: RegionalSimulation = candidate.world
		runner.assert_true(staged != runtime.world_sim and staged.map_data != runtime.world_sim.map_data, "candidate owns an independent world and map")
		runner.assert_true(not staged.construction._incoming.is_valid(), "candidate construction does not call the live runtime journey")
		for side: Vector2i in [side_x, side_y]:
			runner.assert_true(SimMotionClearance.segment_reserves(staged.regions.home.actors.player, candidate.snapshot.continuity.player_journey, side), "candidate retains its own crossed diagonal side")
		runner.assert_true(not SimMotionClearance.segment_reserves(staged.regions.home.actors.player, candidate.snapshot.continuity.player_journey, future), "candidate does not reserve its later route")
		SimRouteTravel.put(staged.regions.home.actors.player, TileGrid.cell_to_world(destination))
		runner.assert_eq(_canonical(runtime), before_stage, "changing a staged candidate body cannot change the live journey or world")
	_assert_reservations(runner, runtime, [origin, target, side_x, side_y], future, "after staging")

	var path: String = "user://tests/motion_clearance_runtime_%d.json" % Time.get_ticks_usec()
	var saved_position: Vector2 = SimRouteTravel.point(body)
	var saved_journey: String = _json(runtime.player_journey)
	var saved: Error = runtime.save_game(path)
	runner.assert_eq(saved, OK, "normal save writes the actual in-flight journey")
	if saved == OK:
		GameClock.advance_msec(1)
		var loaded: Error = runtime.load_game(path)
		runner.assert_eq(loaded, OK, "normal load restores the in-flight journey")
		if loaded == OK:
			runner.assert_eq(_json(runtime.player_journey), saved_journey, "the same original segment and remaining path return")
			runner.assert_true(SimRouteTravel.point(runtime.world_sim.regions.home.actors.player).is_equal_approx(saved_position), "the same continuous point returns")
			_assert_reservations(runner, runtime, [origin, target, side_x, side_y], future, "restored crossed leg")
			GameClock.advance_msec(due_ms - GameClock.elapsed_ms + 1)
			runner.assert_true(not runtime.player_journey.is_empty(), "the original journey continues to its next leg")
			runner.assert_true(not runtime._incoming_occupancy(origin), "the completed first-leg origin is released")
			GameClock.advance_msec(3000)
			runner.assert_true(runtime.player_journey.is_empty() and player.cell == destination, "the restored original journey reaches its requested destination")
			runner.assert_true(not runtime._incoming_occupancy(side_x) and not runtime._incoming_occupancy(side_y), "a completed journey releases the old diagonal sides")
	_remove_files(path)
	_fixtures._dispose(fixture)


func _assert_reservations(runner: Object, runtime: WorldContinuityRuntime, reserved: Array[Vector2i], future: Vector2i, label: String) -> void:
	for cell: Vector2i in reserved:
		runner.assert_true(runtime._incoming_occupancy(cell), label + " reserves its actual endpoint and diagonal side: " + str(cell))
	runner.assert_true(not runtime._incoming_occupancy(future), label + " does not reserve a later path cell")


func _real_door_close_during_journey(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	var sim: VillageSimulation = world.regions.home
	var domain: SimConstruction = world.construction
	for region_id: String in world.regions:
		var region: VillageSimulation = world.regions[region_id]
		for actor: String in region.actors:
			region.cancel_action(actor, "clearance_fixture")
			region.actors[actor].autonomous = false
		world.invalidate_region(region_id)
	var ui: ConstructionRuntime = runtime.construction_adapter
	ui.register_yard()
	runner.assert_true(not domain.sites.is_empty(), "ordinary runtime registers the real construction yard")
	if domain.sites.is_empty():
		_fixtures._dispose(fixture)
		return
	# The door occupies one diagonal side, never the moving body's cell or its
	# first destination. Exclude the independently protected courier road.
	var door_cell := Vector2i(-1, -1)
	for cell: Vector2i in SimConstruction.cells_in(domain.site_bounds()):
		if domain.occupied(cell) or SimMotionClearance.fixed_road_reserves(world, cell):
			continue
		if fixture.world.is_walkable(cell + Vector2i.LEFT) and fixture.world.is_walkable(cell + Vector2i.DOWN) and fixture.world.is_walkable(cell + Vector2i.RIGHT):
			door_cell = cell
			break
	runner.assert_true(door_cell.x >= 0, "yard supplies a clear doorway away from the fixed road")
	if door_cell.x < 0:
		_fixtures._dispose(fixture)
		return
	var placed: Dictionary = domain.place("player", "wood_door", door_cell)
	runner.assert_true(placed.ok, "a real doorway blueprint is placed")
	if not placed.ok:
		_fixtures._dispose(fixture)
		return
	var door: String = str(placed.project)
	var build: Dictionary = domain.begin("player", door)
	runner.assert_true(build.ok, "the original player starts the real material and door work")
	if not build.ok:
		_fixtures._dispose(fixture)
		return
	GameClock.advance_msec(300000)
	var built: bool = domain.projects[door].state == "built"
	runner.assert_true(built, "real hauling, cost and work produce a physical door")
	if not built:
		_fixtures._dispose(fixture)
		return
	var opening: Dictionary = domain.begin("player", door, "open")
	runner.assert_true(opening.ok, "the original worker starts opening the built door")
	if not opening.ok:
		_fixtures._dispose(fixture)
		return
	GameClock.advance_msec(5000)
	runner.assert_true(bool(domain.projects[door].open), "the original door actually opens")
	if not bool(domain.projects[door].open):
		_fixtures._dispose(fixture)
		return
	var origin: Vector2i = door_cell + Vector2i.LEFT
	var target: Vector2i = door_cell + Vector2i.DOWN
	sim.set_actor_cell("shi_tou", door_cell + Vector2i.RIGHT)
	world.invalidate_region("home")
	var closing: Dictionary = domain.begin("shi_tou", door, "close")
	runner.assert_true(closing.ok, "a second actual worker starts the timed close")
	if not closing.ok:
		_fixtures._dispose(fixture)
		return
	for _index: int in 20:
		if not domain.active.has("shi_tou") or domain.active.shi_tou.phase == "work":
			break
		GameClock.advance_msec(maxi(1, domain.next_boundary_ms() - GameClock.elapsed_ms))
	var working: bool = domain.active.has("shi_tou") and domain.active.shi_tou.phase == "work"
	runner.assert_true(working, "the worker physically reaches the timed door operation")
	if not working:
		_fixtures._dispose(fixture)
		return
	var close_at: int = int(domain.active.shi_tou.due_ms)
	GameClock.advance_msec(close_at - GameClock.elapsed_ms - 25)
	(fixture.player as PlayerCharacter).spawn_at(origin)
	runtime.prepare_player_command()
	runner.assert_true(not domain.occupied(door_cell), "the pending close is clear before the new journey")
	var started: bool = runtime.travel_to("home", target)
	runner.assert_true(started, "player starts an actual diagonal journey beside the open door")
	if not started or runtime.player_journey.get("path", []).is_empty():
		_fixtures._dispose(fixture)
		return
	var leg: Dictionary = runtime.player_journey.duplicate(true)
	var correct_leg: bool = SimRouteTravel.cell(leg.path[0]) == target and int(leg.due_ms) > close_at and door_cell != target and door_cell != origin
	runner.assert_true(correct_leg, "the live first leg sweeps the door side at the close boundary")
	if not correct_leg:
		_fixtures._dispose(fixture)
		return
	runner.assert_true(runtime._incoming_occupancy(door_cell), "runtime-owned diagonal reserves the actual door side")
	var events: Array = []
	domain.structures_changed.connect(func(cells: Array[Vector2i]) -> void: events.append(cells.duplicate()))
	GameClock.advance_msec(25)
	runner.assert_eq(SimRouteTravel.cell(sim.actors.player.cell), origin, "close boundary arrives before the player enters the next cell")
	runner.assert_true(bool(domain.projects[door].open) and not domain.blocked(door_cell), "the reserved side prevents the timed door from closing")
	runner.assert_true(not domain.active.has("shi_tou") and events.is_empty(), "blocked close releases the real worker without publishing a geometry change")
	runner.assert_eq(_json(runtime.player_journey), _json(leg), "blocked closure preserves the original journey and its deadline")
	runner.assert_true(SimRouteTravel.point(sim.actors.player).distance_to(TileGrid.cell_to_world(origin)) > 0.0, "the original body still advances during the close interval")
	GameClock.advance_msec(int(leg.due_ms) - GameClock.elapsed_ms + 1)
	runner.assert_true(runtime.player_journey.is_empty() and (fixture.player as PlayerCharacter).cell == target, "the same journey continues to its actual destination")
	runner.assert_true(not runtime._incoming_occupancy(door_cell), "arrival releases the door side")
	_fixtures._dispose(fixture)


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return _json(WorldSessionSnapshot.capture(runtime))


func _json(value: Variant) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(value), "", true, true)


func _remove_files(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
