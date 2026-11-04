extends RefCounted
## Original motion owners and real same-millisecond structural changes.

const Clearance = preload("res://scripts/sim/motion_clearance.gd")
const Rooms = preload("res://tests/sim/test_rooms_and_rest.gd")
const ServiceFixture = preload("res://tests/sim/test_settlement_services.gd")
const FlatMap = preload("res://tests/sim/test_structure_query.gd").FlatMap
var _rooms := Rooms.new()
var _service_fixture := ServiceFixture.new()


func run(runner: Object) -> void:
	_segment_and_active_owners(runner)
	_fixed_roads(runner)
	_real_door_and_rest(runner)
	_real_diagonal_wall(runner)
	_real_road_rejection(runner, false)
	_real_road_rejection(runner, true)
	_real_traversable_completion(runner, "wood_bed")
	_real_traversable_completion(runner, "wood_roof")
	print("SCENARIO motion clearance: original active legs, diagonal sides, fixed roads, and same-boundary door/bed continuation")


func _segment_and_active_owners(runner: Object) -> void:
	# The real service fixture configures services and retains the navigation
	# provider for the lifetime of its world; the room fixture has no service.
	var world: RegionalSimulation = _service_fixture._make_world(runner)
	if world == null:
		return
	var sim: VillageSimulation = world.regions.home
	var origin := Vector2i(80, 80)
	var target := Vector2i(81, 81)
	var diagonal_side := Vector2i(81, 80)
	var large: SimLargeBodies = world.large_bodies
	runner.assert_true(large != null, "the large-body authority is available for shared clearance checks")
	sim.set_actor_cell("player", origin)
	world.invalidate_region("home")
	if large != null:
		runner.assert_true(not large.occupied_by_other(diagonal_side), "without an active leg the unrelated diagonal side remains clear for a large body")
	var body: Dictionary = sim.actors.player
	var route: Dictionary = {
		"path": [[target.x, target.y], [82, 81]],
		"segment_from": body.position.duplicate(), "segment_started_ms": world.elapsed_ms,
		"due_ms": world.elapsed_ms + 500,
	}
	var stable: String = _rooms._canonical(world)
	for cell: Vector2i in [origin, target, Vector2i(81, 80), Vector2i(80, 81)]:
		runner.assert_true(Clearance.segment_reserves(body, route, cell), "one active diagonal retains its endpoint and both side cells")
	runner.assert_true(not Clearance.segment_reserves(body, route, Vector2i(82, 81)), "the later route is not part of the current segment")
	runner.assert_true(_rooms._canonical(world) == stable, "segment queries never move the original body or alter the world")
	var after_crossing: Vector2 = TileGrid.cell_to_world(origin).lerp(TileGrid.cell_to_world(target), 0.75)
	SimRouteTravel.put(body, after_crossing)
	runner.assert_eq(SimRouteTravel.cell(body.cell), target, "the original body really crossed into the target cell")
	runner.assert_true(Clearance.segment_reserves(body, route, Vector2i(80, 81)), "a diagonal side remains reserved until the leg reaches its center")
	var recenter: Dictionary = {"path": [[81, 81]], "segment_from": body.position.duplicate()}
	runner.assert_true(Clearance.segment_reserves(body, recenter, target), "a same-cell recentering still reserves its real cell")
	runner.assert_true(not Clearance.segment_reserves(body, recenter, origin), "same-cell recentering does not reserve an unrelated previous cell")
	runner.assert_true(not Clearance.segment_reserves(body, {"path": []}, origin), "an empty route has no moving first segment")
	runner.assert_true(Clearance.segment_reserves(body, {"path": [[81, 81]]}, Vector2i(500, 500)), "malformed active segment fails closed")
	SimRouteTravel.put(body, TileGrid.cell_to_world(origin))
	var leg: Dictionary = route.duplicate(true)
	leg["phase"] = "travel"
	var before_action: Dictionary = body.active
	body.active = leg
	runner.assert_true(Clearance.active_segment_reserves(world, target), "native action reads the actor's original active first leg")
	runner.assert_true(not Clearance.active_segment_reserves(world, Vector2i(82, 81)), "native action does not reserve a future leg")
	if large != null:
		runner.assert_true(large.occupied_by_other(diagonal_side), "large bodies also protect a native action's diagonal side")
	body.active = before_action

	var cases: Array = [
		[world.construction, "to_site"], [world.resting, "travel"],
		[world.resting, "leave"], [world.personal_production, "travel"],
		[world.capability_practice, "walk"],
	]
	for entry: Array in cases:
		var domain: RefCounted = entry[0]
		runner.assert_true(domain != null, "the original active domain is available for " + str(entry[1]))
		if domain == null:
			continue
		var previous: Dictionary = domain.active
		var row: Dictionary = route.duplicate(true)
		row["phase"] = entry[1]
		domain.active = {"player": row}
		runner.assert_true(Clearance.active_segment_reserves(world, diagonal_side), "the original active domain protects its diagonal first leg: " + str(entry[1]))
		if large != null:
			runner.assert_true(large.occupied_by_other(diagonal_side), "large bodies use the same active-domain diagonal side: " + str(entry[1]))
		domain.active = previous
	var practice: RefCounted = world.capability_practice
	if practice != null:
		var previous_practice: Dictionary = practice.active
		leg = route.duplicate(true)
		leg["phase"] = "prepare"
		practice.active = {"player": leg}
		runner.assert_true(not Clearance.active_segment_reserves(world, target), "a prepared future practice path is not a moving first leg")
		if large != null:
			runner.assert_true(not large.occupied_by_other(diagonal_side), "a future practice leg does not reserve a large body's path")
		practice.active = previous_practice

	var service: RefCounted = world.services
	runner.assert_true(service != null, "the actual configured service domain is available for the active-index checks")
	if service != null:
		var old_jobs: Dictionary = service.jobs
		var old_active_jobs: Dictionary = service.active_jobs
		leg = route.duplicate(true)
		leg["phase"] = "travel"
		leg["status"] = "active"
		var historical: Dictionary = leg.duplicate(true)
		historical["status"] = "cancelled"
		service.jobs = {"guard": leg, "historical": historical}
		service.active_jobs = {"player": "guard"}
		runner.assert_true(Clearance.active_segment_reserves(world, target), "services resolve the active job rather than historical jobs")
		if large != null:
			runner.assert_true(large.occupied_by_other(diagonal_side), "large bodies also protect the active service's diagonal side")
		service.jobs.guard["road_paused"] = true
		runner.assert_true(not Clearance.active_segment_reserves(world, target), "a road-paused service is stationary until its original segment resumes")
		if large != null:
			runner.assert_true(not large.occupied_by_other(diagonal_side), "a stationary paused service does not reserve a diagonal side")
		service.active_jobs = {}
		runner.assert_true(not Clearance.active_segment_reserves(world, target), "terminal service history does not reserve space")
		if large != null:
			runner.assert_true(not large.occupied_by_other(diagonal_side), "historical service jobs do not obstruct a large body")
		service.jobs = old_jobs
		service.active_jobs = old_active_jobs

	var field: RefCounted = world.field_opportunities
	runner.assert_true(field != null, "the field authority is available for the original active-trip checks")
	if field != null:
		var old_purposes: Dictionary = field.purposes
		var old_trips: Dictionary = field.trips
		leg = route.duplicate(true)
		leg["status"] = "active"
		field.purposes = {"player": {"phase": "outbound", "trip": "guard"}}
		field.trips = {"guard": leg}
		runner.assert_true(Clearance.active_segment_reserves(world, target), "field travel reads its active purpose and original trip")
		if large != null:
			runner.assert_true(large.occupied_by_other(diagonal_side), "large bodies also protect the active field trip's diagonal side")
		field.purposes.player.phase = "waiting"
		runner.assert_true(not Clearance.active_segment_reserves(world, target), "a nonmoving field purpose does not reserve its historical trip")
		if large != null:
			runner.assert_true(not large.occupied_by_other(diagonal_side), "historical field trips do not obstruct a large body")
		field.purposes = old_purposes
		field.trips = old_trips

	runner.assert_true(world.soul_vessels != null, "the soul-vessel authority is available for errand checks")
	if world.soul_vessels != null:
		var agency: RefCounted = world.soul_vessels.agency
		runner.assert_true(agency != null, "the actual soul-agency domain is available for active errands")
		if agency != null:
			var old_errands: Dictionary = agency.errands
			leg = route.duplicate(true)
			leg["phase"] = "carry"
			agency.errands = {"player": leg}
			runner.assert_true(Clearance.active_segment_reserves(world, target), "a soul-requested errand uses the human's original body and route")
			if large != null:
				runner.assert_true(large.occupied_by_other(diagonal_side), "large bodies also protect the active errand's diagonal side")
			agency.errands.player.phase = "pickup"
			runner.assert_true(not Clearance.active_segment_reserves(world, target), "a stationary pickup does not reserve a future leg")
			if large != null:
				runner.assert_true(not large.occupied_by_other(diagonal_side), "a stationary pickup does not obstruct a diagonal side")
			agency.errands = old_errands


func _fixed_roads(runner: Object) -> void:
	var world: RegionalSimulation = _rooms._world(runner)
	if world == null:
		return
	var road: Dictionary = world.settings.routes.river_road
	var old_path: Variant = road.get("path")
	road["path"] = [[80, 80], [81, 81], [82, 81]]
	for cell: Vector2i in [Vector2i(80, 80), Vector2i(81, 81), Vector2i(81, 80), Vector2i(80, 81), Vector2i(82, 81)]:
		runner.assert_true(Clearance.fixed_road_reserves(world, cell), "a fixed road retains its real path and diagonal side cells")
	runner.assert_true(not Clearance.fixed_road_reserves(world, Vector2i(82, 82)), "a fixed road does not claim unrelated terrain")
	if old_path == null:
		road.erase("path")
		var source: Vector2i = SimRouteTravel.cell(world.regions[road.from].places[road.source].cell)
		var target: Vector2i = SimRouteTravel.cell(world.regions[road.to].places[road.target].cell)
		var midpoint: Vector2i = TileGrid.world_to_cell(TileGrid.cell_to_world(source).lerp(TileGrid.cell_to_world(target), 0.5))
		runner.assert_true(Clearance.fixed_road_reserves(world, midpoint), "a legacy road without an encoded path retains the courier's original straight projection")
	else:
		road.path = old_path


func _real_door_and_rest(runner: Object) -> void:
	var fixture: Dictionary = _rooms._bed_world(runner)
	var world: RegionalSimulation = fixture.world
	if world == null:
		return
	var bed: String = fixture.bed
	var door_cell := Vector2i(109, 108)
	var door: String = _rooms._build(runner, world, "wood_door", door_cell)
	if door.is_empty():
		return
	var domain: SimConstruction = world.construction
	var opened: Dictionary = domain.begin("player", door, "open")
	runner.assert_true(opened.ok, "the actual built door can be opened before the other person approaches")
	if not opened.ok:
		return
	_rooms._fixtures._finish(runner, world)
	var sim: VillageSimulation = world.regions.home
	sim.set_actor_cell("player", Vector2i(108, 108))
	sim.set_actor_cell("shi_tou", Vector2i(109, 107))
	world.invalidate_region("home")
	runner.assert_true(not Clearance.fixed_road_reserves(world, door_cell), "the test doorway is not on the independently protected fixed road")
	var closing: Dictionary = domain.begin("shi_tou", door, "close")
	runner.assert_true(closing.ok, "a second real worker begins the timed door operation")
	if not closing.ok:
		return
	for _index: int in 20:
		if not domain.active.has("shi_tou") or domain.active.shi_tou.phase == "work":
			break
		if not world.advance_to_ms(domain.next_boundary_ms()):
			runner.assert_true(false, "the door operator reaches the original work boundary")
			return
	if not domain.active.has("shi_tou") or domain.active.shi_tou.phase != "work":
		runner.assert_true(false, "the real door operation enters its work phase")
		return
	var close_at: int = int(domain.active.shi_tou.due_ms)
	if not world.advance_to_ms(close_at - 100):
		runner.assert_true(false, "world reaches the short interval before closure")
		return
	var resting: Dictionary = world.resting.begin("player", bed)
	runner.assert_true(resting.ok, "the other body reserves the real bed and starts walking")
	if not resting.ok:
		return
	var leg: Dictionary = world.resting.active.player
	var correct_leg: bool = leg.phase == "travel" and not leg.path.is_empty() and SimRouteTravel.cell(leg.path[0]) == door_cell and int(leg.due_ms) > close_at
	runner.assert_true(correct_leg, "the active first leg enters the doorway after the pending close boundary")
	if not correct_leg:
		return
	runner.assert_eq(SimRouteTravel.cell(sim.actors.player.cell), Vector2i(108, 108), "the walker has not yet entered the doorway")
	runner.assert_true(Clearance.active_segment_reserves(world, door_cell), "the original resting process protects its active doorway leg")
	var from := Vector2(float(leg.segment_from[0]), float(leg.segment_from[1]))
	var expected: Vector2 = from.lerp(TileGrid.cell_to_world(door_cell), float(close_at - int(leg.segment_started_ms)) / float(int(leg.due_ms) - int(leg.segment_started_ms)))
	var snapshot: Dictionary = JSON.parse_string(_rooms._canonical(world))
	var sliced: RegionalSimulation = _rooms._world(runner)
	var restored: bool = sliced != null and sliced.restore(snapshot)
	runner.assert_true(restored, "an independent candidate restores both real in-progress operations")
	if not restored:
		return
	var whole_events: Array = []
	var sliced_events: Array = []
	world.construction.structures_changed.connect(func(cells: Array[Vector2i]) -> void: whole_events.append(cells.duplicate()))
	sliced.construction.structures_changed.connect(func(cells: Array[Vector2i]) -> void: sliced_events.append(cells.duplicate()))
	runner.assert_true(world.advance_to_ms(close_at), "the complete interval reaches the common closure boundary")
	while sliced.elapsed_ms < close_at:
		if not sliced.advance_to_ms(mini(close_at, sliced.elapsed_ms + 10)):
			runner.assert_true(false, "the sliced interval reaches the same boundary")
			return
	runner.assert_true(bool(world.construction.projects[door].open), "the timed closure waits for the original in-flight body")
	runner.assert_true(world.resting.owns_actor("player") and world.resting.bed_reserved(bed), "failed closure neither cancels the walk nor releases the original bed")
	runner.assert_true(SimRouteTravel.point(world.regions.home.actors.player).is_equal_approx(expected), "the body advances through the entire old-geometry interval")
	runner.assert_true(whole_events.is_empty() and sliced_events.is_empty(), "a rejected physical closure publishes no structure change")
	runner.assert_true(_rooms._canonical(sliced) == _rooms._canonical(world), "whole and sliced advancement after restore preserve the same complete state")
	_rooms._arrive(runner, world, "player")
	var retried: Dictionary = world.construction.begin("shi_tou", door, "close")
	runner.assert_true(retried.ok, "the original worker may retry once the doorway is actually clear")
	if retried.ok:
		_rooms._fixtures._finish(runner, world, "shi_tou")
		runner.assert_true(not bool(world.construction.projects[door].open), "the same door closes normally after the body passes")


func _real_diagonal_wall(runner: Object) -> void:
	var fixture: Dictionary = _rooms._bed_world(runner)
	var world: RegionalSimulation = fixture.world
	if world == null:
		return
	# Use the same eight-direction path search and step rules as the live world.
	# This is a targeted flat layout, not a claim about the ordinary opening.
	var geometry := ReolWorld.new()
	geometry.bind_map_data(FlatMap.new())
	geometry.set_obstacle_provider(world.construction.blocked)
	world.regions.home.set_navigation(
		func(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
			return VillageRuntime.find_grid_path(geometry, from, to, 24, 4096),
		geometry.can_step
	)
	_diagonal_wall_scenario(runner, world, str(fixture.bed), geometry)
	geometry.free()


func _diagonal_wall_scenario(runner: Object, world: RegionalSimulation, bed: String, geometry: ReolWorld) -> void:
	var sim: VillageSimulation = world.regions.home
	var domain: SimConstruction = world.construction
	var start := Vector2i(109, 107)
	var destination := Vector2i(110, 108)
	var side := Vector2i(110, 107)
	sim.set_actor_cell("player", start)
	sim.set_actor_cell("shi_tou", Vector2i(111, 107))
	world.invalidate_region("home")
	runner.assert_true(geometry.can_step(start, Vector2i.ONE), "the original flat geometry permits the intended diagonal bed leg")
	runner.assert_true(not Clearance.fixed_road_reserves(world, side), "the diagonal wall is not on the independent fixed road")
	var planned: Dictionary = domain.place("player", "wood_wall", side)
	runner.assert_true(planned.ok, "the worker receives a real wall blueprint at the diagonal side cell")
	if not planned.ok:
		return
	var project: String = str(planned.project)
	var amount: int = int(domain.definitions.types.wood_wall.amount)
	var stock_before: int = sim.inventory.quantity("store", "wood")
	var started: Dictionary = domain.begin("shi_tou", project)
	runner.assert_true(started.ok, "another real body takes the wall job and reserves its lumber")
	if not started.ok or not _construction_reaches_work(runner, world, "shi_tou"):
		return
	var finish_at: int = int(domain.active.shi_tou.due_ms)
	if not world.advance_to_ms(finish_at - 100):
		runner.assert_true(false, "the wall reaches the short interval before its physical completion")
		return
	var resting: Dictionary = world.resting.begin("player", bed)
	runner.assert_true(resting.ok, "the other person starts an actual bed journey")
	if not resting.ok:
		return
	var leg: Dictionary = world.resting.active.player
	var diagonal: bool = leg.phase == "travel" and not leg.path.is_empty() and SimRouteTravel.cell(leg.path[0]) == destination and int(leg.due_ms) > finish_at
	runner.assert_true(diagonal, "the real first walking leg is diagonal and still in progress at wall completion")
	if not diagonal:
		return
	runner.assert_true(not domain.occupied(side, false), "the wall cell is neither the walker nor worker nor a material location")
	runner.assert_true(domain.occupied(side), "the unified occupancy query includes the moving diagonal side")
	runner.assert_true(Clearance.active_segment_reserves(world, side), "the real diagonal leg reserves its side cell")
	var seen: Array = []
	domain.structures_changed.connect(func(cells: Array[Vector2i]) -> void: seen.append(cells.duplicate()))
	runner.assert_true(world.advance_to_ms(finish_at), "both original processes reach the wall completion boundary")
	runner.assert_eq(str(domain.projects[project].state), "blueprint", "the diagonal side blocks the physical wall commit")
	runner.assert_eq(int(domain.projects[project].work_ms), int(domain.definitions.types.wood_wall.work_ms), "all completed wall labor remains with the original project")
	runner.assert_eq(sim.inventory.quantity("store", "wood"), stock_before - amount, "the original store supplied the wall batch exactly once")
	runner.assert_eq(sim.inventory.quantity(project, "wood"), amount, "the supplied wall batch remains at the original worksite")
	runner.assert_true(not sim.inventory.operations.has(project + ":build") and seen.is_empty(), "rejected completion neither consumes lumber nor publishes a structure change")
	runner.assert_true(world.resting.owns_actor("player"), "the original walking process continues through the old open geometry")
	runner.assert_true(world.resting.cancel("player"), "stopping the real walk clears its reserved diagonal leg")
	var retry: Dictionary = domain.begin("shi_tou", project)
	runner.assert_true(retry.ok, "the same worker can retry the same completed wall after clearance")
	if not retry.ok:
		return
	_rooms._fixtures._finish(runner, world, "shi_tou")
	runner.assert_true(domain.projects[project].state == "built" and domain.blocked(side), "the original wall becomes solid after clearance")
	runner.assert_eq(sim.inventory.quantity("store", "wood"), stock_before - amount, "retry does not take a second batch from the store")
	runner.assert_eq(sim.inventory.quantity(project, "wood"), 0, "the single existing worksite batch is consumed at actual completion")
	runner.assert_true(sim.inventory.operations.has(project + ":supply") and sim.inventory.operations.has(project + ":build"), "the one supply and one build operation remain in the original ledger")
	runner.assert_eq(seen.size(), 1, "only the successful retry publishes one physical structure change")


func _real_road_rejection(runner: Object, project_is_road_cell: bool) -> void:
	var world: RegionalSimulation = _rooms._world(runner)
	if world == null:
		return
	var sim: VillageSimulation = world.regions.home
	var domain: SimConstruction = world.construction
	var side := Vector2i(110, 107)
	var road: Dictionary = world.settings.routes.river_road
	var source: Vector2i = SimRouteTravel.cell(world.regions[road.from].places[road.source].cell)
	var destination: Vector2i = SimRouteTravel.cell(world.regions[road.to].places[road.target].cell)
	# A fresh targeted assembly keeps the actual courier's source and target.
	# The existing geometry fixture proves each consecutive road step is legal.
	var path: Array = [[source.x, source.y]]
	for point: Vector2i in [Vector2i(112, 104), Vector2i(112, 107), Vector2i(111, 107)]:
		_append_road_to(path, point)
	if project_is_road_cell:
		_append_road_to(path, side)
	for point: Vector2i in [Vector2i(110, 108), Vector2i(108, 108), Vector2i(108, 104), destination]:
		_append_road_to(path, point)
	road["path"] = path
	var terrain: WorldMapData = FlatMap.new()
	var legal: bool = SimRouteTravel.cell(path[0]) == source and SimRouteTravel.cell(path[-1]) == destination
	for index: int in range(1, path.size()):
		var from: Vector2i = SimRouteTravel.cell(path[index - 1])
		var step: Vector2i = SimRouteTravel.cell(path[index]) - from
		legal = legal and step != Vector2i.ZERO and absi(step.x) <= 1 and absi(step.y) <= 1 and terrain.terrain_can_step(from, step)
	runner.assert_true(legal and world._valid_settings(world.settings, world.regions), "the targeted fixed road has valid settings, real endpoints, and continuous walkable steps")
	runner.assert_eq(path.has([side.x, side.y]), project_is_road_cell, "the test distinguishes a road cell from a diagonal side cell")
	runner.assert_true(Clearance.fixed_road_reserves(world, side), "the actual courier road reserves the planned wall cell")
	if world.large_bodies != null:
		runner.assert_true(not world.large_bodies.occupied_by_other(side), "a fixed road by itself does not claim large-body occupancy")
	var planned: Dictionary = domain.place("player", "wood_wall", side)
	runner.assert_true(planned.ok, "a real wall blueprint can be planned on the targeted road layout")
	if not planned.ok:
		return
	var project: String = str(planned.project)
	var amount: int = int(domain.definitions.types.wood_wall.amount)
	var stock_before: int = sim.inventory.quantity("store", "wood")
	var seen: Array = []
	domain.structures_changed.connect(func(cells: Array[Vector2i]) -> void: seen.append(cells.duplicate()))
	var started: Dictionary = domain.begin("player", project)
	runner.assert_true(started.ok, "the original construction process starts despite the paper road overlap")
	if not started.ok:
		return
	_rooms._fixtures._finish(runner, world)
	runner.assert_true(not domain.occupied(side) and domain.terrain_open(side), "the refusal is not caused by an occupied or unsuitable project cell")
	runner.assert_true(not Clearance.active_segment_reserves(world, side), "no active pedestrian leg explains the road rejection")
	runner.assert_eq(str(domain.projects[project].state), "blueprint", "actual wall completion rejects a fixed-road obstruction")
	runner.assert_eq(int(domain.projects[project].work_ms), int(domain.definitions.types.wood_wall.work_ms), "fixed-road rejection preserves all performed labor")
	runner.assert_eq(sim.inventory.quantity("store", "wood"), stock_before - amount, "fixed-road rejection retains the one supplied batch")
	runner.assert_eq(sim.inventory.quantity(project, "wood"), amount, "the real worksite retains that batch without consuming it")
	runner.assert_true(not sim.inventory.operations.has(project + ":build") and seen.is_empty(), "fixed-road rejection publishes no physical change and charges no completed build")


func _append_road_to(path: Array, target: Vector2i) -> void:
	var at: Vector2i = SimRouteTravel.cell(path[-1])
	while at != target:
		at += Vector2i(clampi(target.x - at.x, -1, 1), clampi(target.y - at.y, -1, 1))
		path.append([at.x, at.y])


func _construction_reaches_work(runner: Object, world: RegionalSimulation, actor: String) -> bool:
	for _index: int in 120:
		if not world.construction.active.has(actor):
			runner.assert_true(false, "the original worker remains active until reaching the work phase")
			return false
		if world.construction.active[actor].phase == "work":
			return true
		if not world.advance_to_ms(maxi(world.elapsed_ms + 1, world.construction.next_boundary_ms())):
			runner.assert_true(false, "the original construction reaches its next boundary")
			return false
	runner.assert_true(false, "the original construction reaches work within the fixture's bounded steps")
	return false


func _real_traversable_completion(runner: Object, type: String) -> void:
	var fixture: Dictionary = _rooms._bed_world(runner)
	var world: RegionalSimulation = fixture.world
	if world == null:
		return
	var bed: String = fixture.bed
	var domain: SimConstruction = world.construction
	var target := Vector2i(109, 108)
	if type == "wood_roof":
		var support: String = _rooms._build(runner, world, "wood_wall", Vector2i(109, 106))
		if support.is_empty() or not domain.roof_supported(target):
			runner.assert_true(false, "the test roof has its real nearby wall support")
			return
	var sim: VillageSimulation = world.regions.home
	sim.set_actor_cell("player", Vector2i(108, 108))
	sim.set_actor_cell("shi_tou", Vector2i(109, 107))
	world.invalidate_region("home")
	var planned: Dictionary = domain.place("player", type, target)
	runner.assert_true(planned.ok, "the actual traversable project accepts its blueprint: " + type)
	if not planned.ok:
		return
	var project: String = str(planned.project)
	var started: Dictionary = domain.begin("shi_tou", project)
	runner.assert_true(started.ok, "the other body starts real material and construction work: " + type)
	if not started.ok:
		return
	for _index: int in 120:
		if not domain.active.has("shi_tou") or domain.active.shi_tou.phase == "work":
			break
		if not world.advance_to_ms(maxi(world.elapsed_ms + 1, domain.next_boundary_ms())):
			runner.assert_true(false, "traversable construction reaches the original work phase")
			return
	if not domain.active.has("shi_tou") or domain.active.shi_tou.phase != "work":
		runner.assert_true(false, "the material and worker reached the traversable worksite")
		return
	var finish_at: int = int(domain.active.shi_tou.due_ms)
	if not world.advance_to_ms(finish_at - 100):
		runner.assert_true(false, "world reaches the short interval before traversable completion")
		return
	var resting: Dictionary = world.resting.begin("player", bed)
	runner.assert_true(resting.ok, "the original body begins walking to the already completed bed")
	if not resting.ok:
		return
	var leg: Dictionary = world.resting.active.player
	if leg.path.is_empty() or SimRouteTravel.cell(leg.path[0]) != target or int(leg.due_ms) <= finish_at:
		runner.assert_true(false, "the real rest leg crosses the planned traversable cell after completion")
		return
	runner.assert_true(Clearance.active_segment_reserves(world, target), "the same active leg is reserved even for the traversable control")
	# The native runtime supplies an additional swept-journey predicate. Its
	# motion-only reservation must not be confused with an actual body present
	# when a traversable bed/roof reaches its completion boundary.
	domain.set_incoming_occupancy(func(cell: Vector2i) -> bool: return cell == target)
	var seen: Array = []
	domain.structures_changed.connect(func(cells: Array[Vector2i]) -> void: seen.append(cells.duplicate()))
	runner.assert_true(world.advance_to_ms(finish_at), "the real construction and walk meet at one common boundary")
	runner.assert_eq(str(domain.projects[project].state), "built", "a nonblocking bed or roof completes despite the moving leg: " + type)
	runner.assert_true(not domain.blocked(target) and world.resting.owns_actor("player"), "the original walker continues through the still-walkable cell: " + type)
	runner.assert_eq(seen.size(), 1, "one accepted traversable physical completion is published: " + type)
