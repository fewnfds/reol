extends RefCounted
## Small geometric counterexamples, not a load matrix.
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Navigation = preload("res://scripts/sim/kernel/navigation.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const Motion = preload("res://scripts/sim/kernel/motion.gd")
const World = preload("res://scripts/sim/kernel/world.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")

static func wall(ground: RefCounted, rect: Rect2i) -> void:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var tile: int = Terrain.index(Vector2i(x, y))
			ground.blocked[tile] = 1
			if not ground.structures.has(tile): ground.structures.append(tile)


static func run(check: Callable) -> void:
	var ground := Terrain.new()
	ground.initialize(0, 1)
	wall(ground, Rect2i(8, 2, 1, 19))
	wall(ground, Rect2i(11, 4, 1, 14))
	wall(ground, Rect2i(11, 17, 11, 1))
	wall(ground, Rect2i(8, 20, 16, 1))
	wall(ground, Rect2i(26, 3, 1, 18))
	wall(ground, Rect2i(28, 3, 1, 18))
	wall(ground, Rect2i(40, 40, 1, 1))
	wall(ground, Rect2i(41, 41, 1, 1))
	var nav := Navigation.new(ground)
	var from := Vector2(10, 6.1)
	var goal := Vector2(18, 19)
	var route := nav.plan(from, goal, 0.9)
	check.call(not route.is_empty() and route[-1] == goal, "A large body lost a valid two-cell L passage")
	for point: Vector2 in route:
		check.call(ground.segment_clear(from, point, 0.9), "Large-body smoothing cut through a passage wall")
		from = point
	var edit: int = Terrain.index(Vector2i(9, 10))
	ground.blocked[edit] = 1
	nav.changed(PackedInt32Array([edit]))
	check.call(nav.large_graph.is_point_solid(Vector2i(10, 10)) and nav.large_graph.is_point_solid(Vector2i(10, 11)), "An edit did not update the large-body graph")
	ground.blocked[edit] = 0
	nav.changed(PackedInt32Array([edit]))
	check.call(not nav.large_graph.is_point_solid(Vector2i(10, 10)), "A removed wall left the large-body graph blocked")
	check.call(not nav.plan(Vector2(27.5, 4), Vector2(27.5, 19), 0.35).is_empty() and nav.plan(Vector2(27.5, 4), Vector2(27.5, 19), 0.9).is_empty(), "A one-cell passage ignored body size")
	check.call(not ground.segment_clear(Vector2(40.5, 41.5), Vector2(41.5, 40.5), 0.35), "A diagonal cut through touching walls")
	check.call(ground.segment_clear(Vector2(10, 19.05), Vector2(10, 19), 0.9), "A segment ending on a lattice boundary failed")
	var cells: PackedInt32Array = Terrain.trace_cells(Vector2(10,19.05), Vector2(11,18))
	check.call(cells.size() < 6 and cells[-1] == Terrain.index(Vector2i(11,18)), "An integer ray endpoint continued beyond the destination")
	check.call(ground.project_point(Vector2(26.95, 5.2), 0.35).is_equal_approx(Vector2(27.351, 5.2)), "A near-wall destination was not projected to usable clearance")
	var a := Vector2(3.17, 31.28)
	var b := Vector2(19.8, 36.91)
	check.call(nav.plan(a, b, 0.35) == PackedVector2Array([b]), "An open arbitrary-angle line retained grid waypoints")
	var page := Units.new()
	page.initialize(1, 1, ground)
	page.positions[0] = Vector2(3, 30)
	page.move_to(0, Vector2(3.1, 30.05), Units.Mode.MANUAL)
	page.routes[0] = PackedVector2Array([Vector2(3.1, 30), Vector2(3.1, 30.05)])
	page.end_ms = 50
	page.advance(nav)
	var knots: PackedVector3Array = page.motion[0]
	check.call(page.positions[0].is_equal_approx(Vector2(3.1,30.05)) and page.ready[1] == 30 and Motion.sample(knots,0.8).is_equal_approx(page.positions[0]), "Turn or stop timing was spread across the whole step")
	check.call(Motion.hit_fraction(Vector2(3.1,30),Vector2(3.1,30),Vector2(3,30),page.positions[0],0.02,knots) >= 0 and Motion.hit_fraction(Vector2(3.1,30),Vector2(3.1,30),Vector2(3,30),page.positions[0],0.02) < 0, "Projectile collision ignored the timed turn")
	_world_cases(check)


static func _world_cases(check: Callable) -> void:
	var world := World.new()
	world.initialize(1, 0)
	var page: RefCounted = world.pages[0]
	page.positions[0] = Vector2(30.2, 30.3)
	for point: Vector2 in [Vector2(31.1, 30.2), Vector2(31.8, 30.7)]:
		check.call(world.command({"kind": "move", "position": point}).ok, "A fractional destination was rejected")
		for step: int in 8: world.step()
		check.call(page.positions[0].is_equal_approx(point), "Two destinations in one tile were merged")
	world.command({"kind": "move", "position": Vector2(40.17, 35.23)})
	world.step()
	var stopped: Vector2 = page.positions[0]
	world.command({"kind": "stop"})
	world.step()
	check.call(page.positions[0] == stopped and not stopped.is_equal_approx(Terrain.center(Terrain.index(Vector2i(stopped)))) and page.routes[0].is_empty(), "Stop snapped the body to a cell centre or retained a route")
	var changed := Vector2(29.17, 32.91)
	world.command({"kind": "move", "position": changed})
	world.step()
	check.call(page.positions[0].is_equal_approx(stopped.move_toward(changed, 0.25)), "A replacement command started from a cell centre")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(world), 0)
	check.call(restored != null and restored.pages[0].targets[0] == changed, "Continuous destination did not survive restoration")
	if restored != null:
		for step: int in 30: restored.step()
		var arrivals: int = 0
		for event: Dictionary in restored.outcomes:
			if event.kind == "arrived": arrivals += 1
		check.call(restored.pages[0].positions[0].is_equal_approx(changed) and arrivals == 1, "Restored route arrived more than once or lost its endpoint")
	var invalid: Dictionary = Persistence.capture(world)
	invalid.pages[0].routes[0] = PackedVector2Array([Vector2(NAN, 0)])
	check.call(Persistence.candidate(invalid, 0) == null, "A non-finite route was adopted")
	page.positions[0] = Vector2(30.2, 40.4)
	world.command({"kind": "move", "position": Vector2(40.8, 40.6)})
	world.step()
	var middle: int = Terrain.index(Vector2i(35, 40))
	world.queue_structure(middle, true, false)
	world.flush_topology()
	check.call(page.routes[0].is_empty(), "A new wall in the middle of a long segment retained the route")
	world.step()
	var from: Vector2 = page.positions[0]
	for point: Vector2 in page.routes[0]:
		check.call(world.terrain.segment_clear(from, point, page.radii[0]), "Replanned route crossed a new wall")
		from = point
	world.command({"kind": "stop"})
	page.positions[0] = Vector2(48.8, 40.5)
	var neighbour: int = Terrain.index(Vector2i(49, 40))
	check.call(not world.command({"kind": "build", "tile": neighbour}).ok, "A wall was built through a body centred in the next tile")
	page.flight[0] = 1
	check.call(world.command({"kind": "build", "tile": neighbour}).ok, "A flying body incorrectly occupied a ground wall")
	world.flush_topology()
	world.objects.transfer(world.source_objects[0], 1, "wood", 4)
	var site: Dictionary = world.facilities.blueprint(world, 1, "wood_wall", Terrain.index(Vector2i(48, 41)))
	check.call(site.get("reason") == "accepted", "Wall completion probe could not place its blueprint")
	if site.has("target"):
		page.flight[0] = 0
		page.positions[0] = Vector2(48.8, 40.8)
		var action := {"kind": "construct", "target": site.target}
		check.call(world.facilities.finish(world, 1, action, world.elapsed_ms) == "occupied", "Construction completed through an adjacent body")
		page.flight[0] = 1
		check.call(world.facilities.finish(world, 1, action, world.elapsed_ms) == "completed", "A flying body prevented wall completion")
		world.flush_topology()
	var nav: RefCounted = world.lanes[0].navigation
	nav.preparations = 0
	check.call(nav.plan(Vector2(30.2, 40.4), Vector2(40.8, 40.6), 0.35).is_empty() and nav.deferred, "A queued request became a path failure")
	nav.begin_step()
	check.call(not nav.plan(Vector2(30.2, 40.4), Vector2(40.8, 40.6), 0.35).is_empty(), "A queued request never became runnable")
	# A closed pocket is labelled only after complete traversal. Removing a wall
	# must invalidate both positive corridors and negative connectivity evidence.
	var enclosure := PackedInt32Array()
	for y: int in range(60, 65):
		for x: int in range(60, 65):
			if x in [60, 64] or y in [60, 64]:
				var tile: int = Terrain.index(Vector2i(x, y))
				enclosure.append(tile)
				world.queue_structure(tile, true, false)
	world.flush_topology()
	nav.begin_step()
	check.call(nav.plan(Vector2(57, 62), Vector2(62, 62), 0.35).is_empty() and not nav.deferred, "A closed room was reachable")
	page.flight[0] = 0
	page.positions[0] = Vector2(57, 62)
	world.command({"kind": "attack_move", "position": Vector2(62, 62)})
	world.outcomes.clear()
	for step: int in 4: world.step()
	var failed: int = 0
	for event: Dictionary in world.outcomes:
		if event.kind == "path_failed": failed += 1
	check.call(not world.combat.orders.has(1) and failed == 1, "Unreachable attack-move retried the same failed destination forever")
	world.queue_structure(Terrain.index(Vector2i(60, 62)), false, false, true)
	world.flush_topology()
	check.call(not nav.plan(Vector2(57, 62), Vector2(62, 62), 0.35).is_empty(), "Removing a wall retained a stale unreachable component")
