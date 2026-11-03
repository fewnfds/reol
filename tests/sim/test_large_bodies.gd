extends RefCounted

const Fixtures = preload("res://tests/sim/test_regional_simulation.gd")


func run(runner: Object) -> void:
	_geometry(runner)
	_roaming_and_contact(runner)
	_dynamic_occupancy(runner)
	_candidates(runner)
	print("SCENARIO scale: complete footprint clearance, bounded motion, real edge feeding, interrupted routes and independent candidates")


func _geometry(runner: Object) -> void:
	var narrow: Callable = func(cell: Vector2i) -> bool:
		return cell.y >= 7 and cell.y <= 13 and (cell.x >= 2 and cell.x <= 6 or cell.x >= 14 and cell.x <= 18) or cell.y == 10 and cell.x >= 6 and cell.x <= 14
	var flat: Callable = func(_cell: Vector2i) -> int: return 0
	var a := Vector2i(4, 10)
	var b := Vector2i(16, 10)
	runner.assert_true(not SimBodyGeometry.find_path(a, b, Vector2i.ONE, narrow, flat, 20, 600).is_empty(), "human crosses an actual one-cell bridge")
	runner.assert_true(SimBodyGeometry.find_path(a, b, Vector2i(3, 3), narrow, flat, 20, 600).is_empty(), "large footprint cannot use the same narrow bridge")
	var wide: Callable = func(cell: Vector2i) -> bool:
		return narrow.call(cell) or cell.x >= 6 and cell.x <= 14 and cell.y >= 9 and cell.y <= 11
	runner.assert_true(not SimBodyGeometry.find_path(a, b, Vector2i(3, 3), wide, flat, 20, 600).is_empty(), "three-cell corridor carries the complete large body")
	runner.assert_true(SimBodyGeometry.find_path(a, b, Vector2i(3, 3), wide, flat, 20, 1).is_empty(), "bounded search returns failure rather than partial teleport")
	var corner: Callable = func(cell: Vector2i) -> bool: return cell != Vector2i(5, 2)
	runner.assert_true(SimBodyGeometry.can_stand(Vector2i(3, 3), Vector2i(3, 3), corner, flat) and SimBodyGeometry.can_stand(Vector2i(4, 4), Vector2i(3, 3), corner, flat), "diagonal endpoint clearances alone do not imply a clear sweep")
	runner.assert_true(not SimBodyGeometry.can_step(Vector2i(3, 3), Vector2i.ONE, Vector2i(3, 3), corner, flat), "diagonal side clearance prevents cutting through a corner")
	var bounded: Callable = func(cell: Vector2i) -> bool: return cell.x >= 0 and cell.y >= 0 and cell.x < 30 and cell.y < 30
	runner.assert_true(not SimBodyGeometry.can_stand(Vector2i.ZERO, Vector2i(3, 3), bounded, flat), "center in bounds is insufficient when the body overhangs the map")
	var cliff: Callable = func(cell: Vector2i) -> int: return 2 if cell.x == 5 else 0
	runner.assert_true(not SimBodyGeometry.can_stand(Vector2i(4, 4), Vector2i(3, 3), bounded, cliff), "one body cannot straddle a two-layer cliff")
	runner.assert_eq(SimBodyGeometry.cells(a, Vector2i(3, 3)).size(), 9, "square turn keeps the same nine occupied cells")
	var center: Vector2 = TileGrid.cell_to_world(a)
	runner.assert_eq(SimBodyGeometry.contact_distance(center + Vector2(TileGrid.TILE_SIZE * 2, 0), center, Vector2i(3, 3)), float(TileGrid.TILE_SIZE) * 0.5, "contact uses the large body boundary rather than its center")
	runner.assert_true(SimBodyGeometry.cells(a, Vector2i(0, 0)).is_empty(), "invalid footprints are rejected")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = Fixtures.new()._make_world(runner)
	world.large_bodies.set_geometry(func(cell: Vector2i) -> bool: return cell.x > 0 and cell.y > 0 and cell.x < 200 and cell.y < 200, func(_cell: Vector2i) -> int: return 0)
	runner.assert_true(world.large_bodies.add_body("test_beast", "巡坡山兽", "home", Vector2i(112, 114), Vector2i(117, 114)), "real body and unique subject stage together")
	return world


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _roaming_and_contact(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var domain: SimLargeBodies = world.large_bodies
	var sim: VillageSimulation = world.regions.home
	runner.assert_true(not sim.actors.has("test_beast") and world.embodiment.footprint(SimLargeBodies.carrier_id("test_beast")) == Vector2i(3, 3), "large source does not duplicate a human body or inventory")
	var start: Vector2 = domain.point("test_beast")
	sim.set_actor_cell("player", Vector2i(114, 114))
	sim.inventory.containers["actor:player"].meal = 3
	runner.assert_true(domain.offer_food("player", "test_beast", "meal").ok, "food can be handed from outside the nine-cell footprint")
	runner.assert_eq(sim.inventory.quantity("actor:player", "meal"), 2, "edge contact consumes one original meal")
	runner.assert_true(not domain.offer_food("player", "test_beast", "meal").ok, "same appetite state cannot repeatedly consume gifts")
	runner.assert_eq(domain.events.size(), 1, "repeated input adds no second feeding provenance")
	sim.set_actor_cell("player", Vector2i(100, 100))
	world.advance_to_ms(15400)
	runner.assert_true(not domain.bodies.test_beast.step.is_empty() and domain.point("test_beast") != start, "clock causes interpolated physical movement")
	runner.assert_true(domain.blocked(Vector2i(114, 114)) and domain.blocked(Vector2i(111, 114)), "active step occupies the full origin/destination sweep")
	var snapshot: Dictionary = JSON.parse_string(_canonical(world))
	var other: RegionalSimulation = _world(runner)
	runner.assert_true(other.restore(snapshot), "independent world restores a partially advanced multi-cell step")
	world.set_active_region("river")
	other.set_active_region("river")
	world.advance_to_ms(93000)
	for time: int in range(15401, 93000, 713):
		other.advance_to_ms(time)
	other.advance_to_ms(93000)
	runner.assert_eq(_canonical(other), _canonical(world), "fine/coarse remote advancement resumes the same whole world")
	var blockers: Dictionary = {}
	domain.set_geometry(func(cell: Vector2i) -> bool: return cell.x > 0 and cell.y > 0 and cell.x < 200 and cell.y < 200 and not blockers.has(cell), func(_cell: Vector2i) -> int: return 0)
	while not domain.bodies.test_beast.step.is_empty():
		world.advance_to_ms(domain.next_boundary_ms())
	var at: Vector2i = domain.body_cell("test_beast")
	var stop: Vector2 = domain.point("test_beast")
	for x: int in range(at.x - 2, at.x + 3):
		for y: int in range(at.y - 2, at.y + 3):
			if absi(x - at.x) == 2 or absi(y - at.y) == 2:
				blockers[Vector2i(x, y)] = true
	world.advance_to_ms(world.elapsed_ms + 30000)
	runner.assert_eq(domain.point("test_beast"), stop, "surrounded large body waits without crossing blocked terrain")
	blockers.clear()
	world.advance_to_ms(world.elapsed_ms + 10000)
	runner.assert_true(domain.point("test_beast") != stop, "opening the same passage lets the original body resume")


func _candidates(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	world.advance_to_ms(15400)
	var saved: Dictionary = JSON.parse_string(_canonical(world))
	var before: String = _canonical(world)
	for field: String in ["position", "step", "path", "last_fed_ms"]:
		var bad: Dictionary = saved.duplicate(true)
		if field == "position":
			bad.large_bodies.bodies.test_beast.position[0] += 8.0
		elif field == "step":
			bad.large_bodies.bodies.test_beast.step.due_ms += 1
		elif field == "path":
			bad.large_bodies.bodies.test_beast.path = [[180, 180]]
		else:
			bad.large_bodies.bodies.test_beast.last_fed_ms = 0
		runner.assert_true(not world.restore(bad), "invalid large-body " + field + " is refused")
		runner.assert_eq(_canonical(world), before, "failed body candidate leaves all live domains intact")
	var bad_registry: Dictionary = saved.duplicate(true)
	bad_registry.embodiment.carriers[SimLargeBodies.carrier_id("test_beast")].form = "human"
	runner.assert_true(not world.restore(bad_registry), "registry cannot replace the actual large source with a human form")
	var sim: VillageSimulation = world.regions.home
	sim.set_actor_cell("player", Vector2i(114, 114))
	world.advance_to_ms(23000)
	sim.inventory.containers["actor:player"].meal = 1
	runner.assert_true(sim.inventory.entrust("test_public_food", "actor:player", "meal", 1, {"domain": "test"}), "fixture has actual food under a custody obligation")
	runner.assert_true(not world.large_bodies.offer_food("player", "test_beast", "meal").ok, "entrusted food is not a disposable gift")
	runner.assert_eq(sim.inventory.quantity("actor:player", "meal"), 1, "refused public food remains in its original container")


func _dynamic_occupancy(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	var domain: SimLargeBodies = world.large_bodies
	var initial: Vector2 = domain.point("test_beast")
	sim.set_actor_cell("player", Vector2i(114, 114))
	world.set_active_region("river")
	world.advance_to_ms(22000)
	runner.assert_eq(domain.point("test_beast"), initial, "far beast waits for a real person occupying its next full footprint")
	sim.set_actor_cell("player", Vector2i(100, 100))
	world.invalidate_region("home")
	world.advance_to_ms(25000)
	runner.assert_true(domain.point("test_beast") != initial, "same far body resumes when the person actually leaves")
	var saved: Dictionary = JSON.parse_string(_canonical(world))
	var reference: String = _canonical(world)
	var bad: Dictionary = saved.duplicate(true)
	bad.large_bodies.elapsed_ms -= 1
	runner.assert_true(not world.restore(bad), "large bodies cannot restore on a private offset timeline")
	runner.assert_eq(_canonical(world), reference, "clock mismatch is rejected atomically")
