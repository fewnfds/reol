extends RefCounted

const Fixtures = preload("res://tests/sim/test_construction.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_test_structure_topology(runner)
	_test_bed_use_and_continuation(runner)
	_test_absent_routine_and_waking(runner)
	_test_invalid_candidates(runner)
	print("SCENARIO rooms/rest: derived enclosure, real bed materials, exclusive allocation, continuous original energy, obstruction, absent life and atomic joint candidates")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _fixtures._world(runner)
	_bind_navigation(world)
	_fixtures._site(runner, world)
	runner.assert_true(world.construction.space_at(Vector2i(110, 108)).get("enclosed") == false, "registration immediately derives open space without requiring a first blueprint")
	return world


func _bind_navigation(world: RegionalSimulation) -> void:
	var reference: WeakRef = weakref(world)
	world.regions.home.set_navigation(func(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
		return _path(reference.get_ref().construction, from, to), func(from: Vector2i, direction: Vector2i) -> bool:
			return not reference.get_ref().construction.blocked(from + direction))


func _path(construction: SimConstruction, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [from]
	var previous: Dictionary = {from: from}
	var cursor: int = 0
	while cursor < queue.size() and cursor < 4096:
		var cell: Vector2i = queue[cursor]
		cursor += 1
		if cell == to:
			var result: Array[Vector2i] = []
			while cell != from:
				result.push_front(cell)
				cell = previous[cell]
			return result
		for direction: Vector2i in SimConstruction.SIDES:
			var next: Vector2i = cell + direction
			if from.distance_to(next) <= 24 and not previous.has(next) and not construction.blocked(next):
				previous[next] = cell
				queue.append(next)
	return []


func _build(runner: Object, world: RegionalSimulation, type: String, cell: Vector2i) -> String:
	var id: String = _fixtures._place(runner, world, type, cell)
	var response: Dictionary = world.construction.begin("player", id)
	runner.assert_true(response.ok, "real work can reach and build " + type + ": " + str(response.line))
	if response.ok:
		_fixtures._finish(runner, world)
		runner.assert_eq(world.construction.projects[id].state, "built", "physical labor finishes " + type)
	return id


func _bed_world(runner: Object) -> Dictionary:
	var world: RegionalSimulation = _world(runner)
	var stock: int = world.regions.home.inventory.quantity("store", "wood")
	var bed: String = _build(runner, world, "wood_bed", Vector2i(110, 108))
	runner.assert_eq(world.regions.home.inventory.quantity("store", "wood"), stock - 5, "a bed consumes original real lumber, not a free resting marker")
	runner.assert_true(not world.construction.blocked(Vector2i(110, 108)), "low furniture is traversable, not a solid wall")
	return {"world": world, "bed": bed}


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _arrive(runner: Object, world: RegionalSimulation, actor: String) -> void:
	for _i: int in 160:
		if not world.resting.active.has(actor) or world.resting.active[actor].phase == "sleep":
			break
		runner.assert_true(world.advance_to_ms(world.resting.next_boundary_ms()), "bed route advances at exact world boundaries")
	runner.assert_true(world.resting.active.has(actor) and world.resting.active[actor].phase == "sleep", "body actually reaches its reserved bed before sleeping")


func _test_structure_topology(runner: Object) -> void:
	var fixture: Dictionary = _bed_world(runner)
	var world: RegionalSimulation = fixture.world
	var domain: SimConstruction = world.construction
	var bed_cell := Vector2i(110, 108)
	runner.assert_true(not domain.space_at(bed_cell).enclosed, "the work-yard boundary does not pretend to be an enclosing wall")
	var door: String = ""
	var wall: String = ""
	for y: int in range(107, 110):
		for x: int in range(109, 113):
			if x not in [109, 112] and y not in [107, 109] or Vector2i(x, y) == Vector2i(109, 108):
				continue
			var id: String = _build(runner, world, "wood_wall", Vector2i(x, y))
			if Vector2i(x, y) == Vector2i(110, 107):
				wall = id
	runner.assert_true(not domain.space_at(bed_cell).enclosed, "a missing doorway keeps the actual space open")
	var placed: Dictionary = domain.place("player", "wood_door", Vector2i(109, 108))
	door = str(placed.get("project", ""))
	runner.assert_true(placed.ok and not domain.space_at(bed_cell).enclosed, "a paper door blueprint provides no enclosure")
	runner.assert_true(domain.begin("player", door).ok, "complete the real doorway")
	_fixtures._finish(runner, world)
	var space: Dictionary = domain.space_at(bed_cell)
	runner.assert_true(space.enclosed and space.flat and not space.roofed and int(space.area) == 2 and int(space.doors) == 1, "flood fill derives the two-cell enclosure including furniture, without inventing a roof")
	runner.assert_true(not world.resting.begin("player", fixture.bed).ok, "closed physical door prevents unreachable bed use")
	runner.assert_true(domain.begin("player", door, "open").ok, "physically open the door")
	_fixtures._finish(runner, world)
	space = domain.space_at(bed_cell)
	runner.assert_true(space.enclosed and space.open_doors == 1, "open doorway preserves room identity and reports its physical opening")
	runner.assert_true(world.resting.begin("player", fixture.bed).ok, "the open doorway now permits actual bed access")
	_arrive(runner, world, "player")
	runner.assert_true(not domain.begin("shi_tou", fixture.bed, "demolish").ok, "construction cannot dismantle a bed with a live user")
	runner.assert_true(domain.begin("shi_tou", wall, "demolish").ok, "another available worker can remove the enclosing wall while the original user rests")
	_fixtures._finish(runner, world, "shi_tou")
	runner.assert_true(world.resting.owns_actor("player"), "opening an unroofed enclosure does not erase ongoing physical bed rest")
	world.resting.cancel("player")
	runner.assert_true(not domain.space_at(bed_cell).enclosed and domain.is_bed(fixture.bed), "breaching a wall opens the space without erasing furniture")
	domain.set_terrain(Callable(), func(cell: Vector2i) -> int: return 1 if cell == bed_cell else 0)
	var pure: Dictionary = domain.projects.duplicate(true)
	pure[wall].state = "built"
	space = SimEnclosedSpace.detect(domain.site_bounds(), pure, domain.definitions.types, domain._elevation)[bed_cell]
	runner.assert_true(space.enclosed and not space.flat and not space.roofed, "an enclosed slope is reported as uneven, never an indoor roof")


func _test_bed_use_and_continuation(runner: Object) -> void:
	var fixture: Dictionary = _bed_world(runner)
	var world: RegionalSimulation = fixture.world
	var bed: String = fixture.bed
	var sim: VillageSimulation = world.regions.home
	var domain: SimResting = world.resting
	runner.assert_true(not domain.assign("su_zhi", bed, "player").ok, "an ordinary user cannot allocate public beds")
	runner.assert_true(domain.assign("player", bed, "lao_zhou").ok, "authorized staff can arrange a specific member's bed")
	runner.assert_true(not domain.begin("player", bed).ok, "courtesy or building permission does not override someone else's bed arrangement")
	runner.assert_true(domain.assign("player", bed).ok, "the same physical bed can be returned to common use")
	sim.set_actor_cell("player", Vector2i(108, 106))
	sim.actors.player.energy = 20.0
	world.invalidate_region("home")
	runner.assert_true(domain.begin("player", bed).ok, "a valid user reserves and walks to the bed")
	runner.assert_true(not domain.begin("shi_tou", bed).ok and not domain.assign("player", bed, "shi_tou").ok, "in-transit reservation prevents both double use and reassignment")
	runner.assert_true(not sim.submit_action("player", "deliver_water"), "sleep route owns the same body as ordinary hauling")
	var before: float = float(sim.actors.player.energy)
	world.advance_to_ms(world.elapsed_ms + 73)
	runner.assert_true(float(sim.actors.player.energy) <= before, "walking toward a bed gives no bed recovery")
	var travel: Dictionary = JSON.parse_string(_canonical(world))
	var restored: RegionalSimulation = _world(runner)
	runner.assert_true(restored.restore(travel), "a real in-transit bed reservation restores with exact route and body")
	_arrive(runner, world, "player")
	var arrived: int = world.elapsed_ms
	var energy: float = float(sim.actors.player.energy)
	var sleep: Dictionary = JSON.parse_string(_canonical(world))
	runner.assert_true(restored.restore(sleep), "sleep phase restores without duplicating needs or furniture")
	var end: int = arrived + 187654
	world.advance_to_ms(end)
	while restored.elapsed_ms < end:
		restored.advance_to_ms(mini(end, restored.elapsed_ms + 997))
	runner.assert_eq(_canonical(restored), _canonical(world), "fine restored bed recovery and sparse absent life produce the identical entire world")
	runner.assert_true(float(sim.actors.player.energy) > energy + 6.0, "rest continuously replenishes original energy before completion")
	domain.cancel("player")
	var retained: float = float(sim.actors.player.energy)
	world.advance_to_ms(world.elapsed_ms + 60000)
	runner.assert_true(not domain.bed_reserved(bed) and float(sim.actors.player.energy) < retained, "interruption releases bed and keeps earned recovery without a ghost recovery rate")
	runner.assert_true(world.construction.begin("player", bed, "demolish").ok, "unoccupied beds use the existing dismantling process")
	_fixtures._finish(runner, world)
	runner.assert_true(not world.construction.is_bed(bed) and not domain.begin("player", bed).ok and domain.allocations.is_empty(), "removed furniture cannot host rest or leave stale allocations")
	runner.assert_eq(sim.inventory.quantity(bed, "wood"), 2, "dismantled bed leaves only its actual finite salvage")


func _test_absent_routine_and_waking(runner: Object) -> void:
	var fixture: Dictionary = _bed_world(runner)
	var world: RegionalSimulation = fixture.world
	var bed: String = fixture.bed
	var sim: VillageSimulation = world.regions.home
	world.resting.assign("player", bed, "lao_zhou")
	sim.set_actor_cell("lao_zhou", Vector2i(109, 106))
	sim.actors.lao_zhou.autonomous = true
	sim.actors.lao_zhou.energy = 20.0
	sim.actors.lao_zhou.hunger = 85.0
	sim.actors.lao_zhou.retry_ms = world.elapsed_ms + 1
	world.invalidate_region("home")
	var near: RegionalSimulation = _world(runner)
	runner.assert_true(near.restore(JSON.parse_string(_canonical(world))), "independent near-region copy starts the same autonomous bed choice")
	near.set_active_region("home")
	world.set_active_region("river")
	world.advance_to_ms(world.elapsed_ms + 180000)
	runner.assert_true(world.resting.active.has("lao_zhou") and world.resting.active.lao_zhou.phase == "sleep", "fatigued NPC finds its permitted nearby bed while the player is elsewhere")
	# This is an unroofed bed. The now-real rainy interval slows its recovery,
	# so allow a full rest period instead of assuming dry-bed timing forever.
	var until: int = world.elapsed_ms + 3000000
	world.advance_to_ms(until)
	while near.elapsed_ms < until:
		near.advance_to_ms(mini(until, near.elapsed_ms + 7919))
	var distant: Dictionary = JSON.parse_string(_canonical(world))
	var local: Dictionary = JSON.parse_string(_canonical(near))
	distant.active_region = ""
	local.active_region = ""
	runner.assert_eq(JSON.stringify(distant), JSON.stringify(local), "near/far scheduling and different step sizes preserve the same bed, needs and NPC future")
	runner.assert_true(not world.resting.owns_actor("lao_zhou") and sim.actors.lao_zhou.autonomous and float(sim.actors.lao_zhou.energy) >= 85.0, "NPC recovers on its exposed bed, wakes by the bounded rest period and returns to daily life")
	runner.assert_true(SimRouteTravel.cell(sim.actors.lao_zhou.cell) != SimRouteTravel.cell(world.construction.projects[bed].cell), "waking physically moves off the bed rather than leaving an idle body blocking its next user")
	sim.cancel_action("lao_zhou", "test_hunger")
	sim.actors.lao_zhou.autonomous = false
	sim.actors.lao_zhou.hunger = 55.01
	sim.actors.lao_zhou.energy = 20.0
	sim.set_actor_cell("lao_zhou", SimRouteTravel.cell(world.construction.projects[bed].cell))
	world.invalidate_region("home")
	runner.assert_true(world.resting.begin("lao_zhou", bed).ok, "same low-energy member can rest voluntarily")
	_arrive(runner, world, "lao_zhou")
	world.advance_to_ms(world.elapsed_ms + 60000)
	runner.assert_true(world.resting.recovery_for("lao_zhou") == 0, "hunger stops bed recovery before the body walks off it")
	var waking: Dictionary = JSON.parse_string(_canonical(world))
	runner.assert_true(near.restore(waking), "the physical waking/leave step can restore in progress")
	world.advance_to_ms(world.elapsed_ms + 1000)
	near.advance_to_ms(near.elapsed_ms + 1000)
	runner.assert_eq(_canonical(near), _canonical(world), "waking continues the same body position, released bed and needs after restore")
	runner.assert_true(not world.resting.owns_actor("lao_zhou") and str(sim.actors.lao_zhou.goal).contains("肚饿"), "hunger interrupts sleep instead of silently starving in an occupied bed")
	var fallback: RegionalSimulation = _world(runner)
	var old: VillageSimulation = fallback.regions.home
	old.actors.lao_zhou.autonomous = true
	old.actors.lao_zhou.hunger = 85.0
	old.actors.lao_zhou.energy = 20.0
	old.actors.lao_zhou.retry_ms = 1
	fallback.invalidate_region("home")
	fallback.advance_to_ms(50)
	runner.assert_eq(str(old.actors.lao_zhou.active.get("action", "")), "rest", "a world without beds retains the original dormitory rest fallback")


func _test_invalid_candidates(runner: Object) -> void:
	var fixture: Dictionary = _bed_world(runner)
	var world: RegionalSimulation = fixture.world
	world.regions.home.set_actor_cell("player", Vector2i(108, 106))
	world.invalidate_region("home")
	world.resting.begin("player", fixture.bed)
	world.advance_to_ms(world.elapsed_ms + 31)
	var stable: String = _canonical(world)
	var base: Dictionary = JSON.parse_string(stable)
	for kind: String in ["missing_bed", "double_user", "wrong_allocation", "fake_time", "fake_body", "missing_domain"]:
		var broken: Dictionary = base.duplicate(true)
		match kind:
			"missing_bed": broken.resting.active.player.bed = "construction:900"
			"double_user":
				broken.resting.active.shi_tou = broken.resting.active.player.duplicate(true)
				broken.resting.active.shi_tou.actor = "shi_tou"
				broken.resting.active.shi_tou.id = "bed_use:2"
				broken.resting.next_job = 3
				broken.regions.home.actors.shi_tou.position = broken.regions.home.actors.player.position.duplicate()
				broken.regions.home.actors.shi_tou.cell = broken.regions.home.actors.player.cell.duplicate()
			"wrong_allocation": broken.resting.allocations[fixture.bed] = "su_zhi"
			"fake_time": broken.resting.active.player.due_ms += 5
			"fake_body": broken.resting.active.player.segment_from[0] += 12.0
			"missing_domain": broken.erase("resting")
		runner.assert_true(not world.restore(broken), "invalid joint bed candidate is rejected: " + kind)
		runner.assert_eq(_canonical(world), stable, "rejection preserves the complete living world: " + kind)
	var obstructed: Dictionary = base.duplicate(true)
	var remaining: Array = obstructed.resting.active.player.path
	var next: Vector2i = SimRouteTravel.cell(remaining[0])
	world.construction._blocked[next] = true
	world.advance_to_ms(world.elapsed_ms + 40)
	runner.assert_true(not world.resting.owns_actor("player") and not world.resting.bed_reserved(fixture.bed), "a later blocked step cancels the route and releases its bed, rather than walking through")
