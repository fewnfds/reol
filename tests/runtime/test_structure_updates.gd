extends RefCounted

const Rooms = preload("res://tests/sim/test_rooms_and_rest.gd")
const FlatMap = preload("res://tests/sim/test_structure_query.gd").FlatMap


func run(runner: Object) -> void:
	_committed_notifications(runner)
	_stationary_sight(runner)
	print("SCENARIO structure updates: one post-transaction notification, collateral roof collapse, silent rejection/restore, and local stationary wall/door visibility")


func _committed_notifications(runner: Object) -> void:
	var helper := Rooms.new()
	var world: RegionalSimulation = helper._world(runner)
	if world == null:
		return
	var domain: SimConstruction = world.construction
	var seen: Array[Array] = []
	var listener: Callable = func(cells: Array[Vector2i]) -> void:
		runner.assert_true(not domain.active.has("player"), "structure observer runs after original worker release")
		runner.assert_true(domain.space_valid(), "structure observer sees the completed original spatial state")
		seen.append(cells.duplicate())
	domain.structures_changed.connect(listener)
	var cell := Vector2i(110, 108)
	var id: String = helper._fixtures._place(runner, world, "wood_door", cell)
	runner.assert_true(seen.is_empty(), "paper blueprint publishes no physical geometry change")
	runner.assert_true(domain.begin("player", id).ok, "original door construction starts")
	helper._fixtures._finish(runner, world)
	runner.assert_eq(seen.size(), 1, "one completed door publishes one notification")
	runner.assert_eq(seen[0], [cell], "notification identifies the real changed cell")
	var bed_cell := Vector2i(110, 109)
	var bed: String = helper._build(runner, world, "wood_bed", bed_cell)
	var roof: String = helper._build(runner, world, "wood_roof", bed_cell)
	runner.assert_eq(seen.size(), 3, "original bed and upper roof each publish their own physical commit")
	for verb: String in ["open", "close"]:
		var previous: int = seen.size()
		runner.assert_true(domain.begin("player", id, verb).ok, "original door " + verb + " starts")
		helper._fixtures._finish(runner, world)
		runner.assert_eq(seen.size(), previous + 1, "one " + verb + " completion publishes one real change")
	var before: int = seen.size()
	runner.assert_true(not domain.begin("player", id, "build").ok, "built door cannot be built again")
	runner.assert_eq(seen.size(), before, "rejected operation publishes no physical change")
	runner.assert_true(domain.restore(domain.to_dict()), "current original structures rebuild their indexes")
	runner.assert_eq(seen.size(), before, "restoring indexes invents no new physical event")
	runner.assert_true(domain.begin("player", id, "demolish").ok, "original support dismantling starts")
	helper._fixtures._finish(runner, world)
	runner.assert_eq(seen.size(), before + 1, "dismantling and its collateral roof collapse publish once together")
	runner.assert_true(seen[-1].has(cell) and seen[-1].has(bed_cell) and seen[-1].size() == 2, "single committed notification includes support and collapsed upper roof")
	runner.assert_true(domain.is_bed(bed) and domain.projects[roof].state == "removed", "roof event does not destroy or duplicate the original bed")
	domain.structures_changed.disconnect(listener)


func _stationary_sight(runner: Object) -> void:
	var helper := Rooms.new()
	var simulation: RegionalSimulation = helper._world(runner)
	if simulation == null:
		return
	var domain: SimConstruction = simulation.construction
	var door_cell := Vector2i(110, 108)
	var id: String = helper._build(runner, simulation, "wood_door", door_cell)
	var view := ReolWorld.new()
	view.bind_map_data(FlatMap.new())
	view.set_obstacle_provider(domain.blocked)
	view.set_sight_obstacle_provider(domain.blocks_sight)
	var eye: Vector2i = door_cell + Vector2i.LEFT
	var behind: Vector2i = door_cell + Vector2i.RIGHT
	var fog := FogOfWar.new()
	fog.setup(view, eye)
	view.set_sight_obstacle_provider(domain.blocks_sight)
	runner.assert_true(fog._visibility_dirty, "rebinding geometry invalidates a stationary observer with a typed full-refresh event")
	fog.update_now()
	domain.structures_changed.connect(view.notify_sight_obstacles_changed)
	runner.assert_true(not fog.is_cell_visible(behind), "stationary observer cannot see through the real closed wooden door")
	runner.assert_true(fog.is_cell_visible(door_cell), "the occluding door itself remains visible")
	runner.assert_true(domain.begin("player", id, "open").ok, "real door opening starts for stationary visibility")
	helper._fixtures._finish(runner, simulation)
	runner.assert_true(fog._visibility_dirty, "post-transaction change invalidates the nearby stationary observer")
	fog._process(FogOfWar.UPDATE_INTERVAL)
	runner.assert_true(fog.is_cell_visible(behind), "stationary observer sees through the completed original opening")
	runner.assert_true(not fog._visibility_dirty, "visibility update consumes only the local invalidation")
	view.notify_sight_obstacles_changed([Vector2i(400, 400)])
	runner.assert_true(not fog._visibility_dirty, "unrelated far geometry does not force a local sight recomputation")
	runner.assert_true(domain.begin("player", id, "close").ok, "real door closure starts for stationary visibility")
	helper._fixtures._finish(runner, simulation)
	fog._process(FogOfWar.UPDATE_INTERVAL)
	runner.assert_true(not fog.is_cell_visible(behind) and fog.is_explored(behind), "closing the original door hides live facts and keeps prior explored memory")
	# The fixed opening's furniture is solid for movement, but not an opaque
	# wall. Test this fact on an actual attached layout, not collision aliases.
	var sim: VillageSimulation = simulation.regions.home
	runner.assert_true(SimWorkplaces.enable_opening(sim.config, sim.places, sim.actors, FlatMap.new(), str(sim.config.institution.id)), "fixed workplace geometry assembles for separate furniture facts")
	var desk: Vector2i = SimRouteTravel.cell(sim.places.records.workspace.fixtures.desk.cell)
	runner.assert_true(domain.blocked(desk) and not domain.blocks_sight(desk), "physical desk collision does not become opaque-wall geometry")
	fog.free()
	view.free()
