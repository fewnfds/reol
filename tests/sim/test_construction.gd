extends RefCounted

const Fixtures = preload("res://tests/sim/test_regional_simulation.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_test_real_material_and_interruptions(runner)
	_test_door_and_recovery(runner)
	_test_remote_duty_and_candidates(runner)
	_test_shortages_obstruction_and_clearance(runner)
	print("SCENARIO construction: reserved real lumber, carried/dropped material, preserved work, door occupancy, dismantling and absent autonomous labor")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _fixtures._make_world(runner)
	var sim: VillageSimulation = world.regions.home
	sim.set_actor_cell("player", Vector2i(108, 104))
	sim.set_actor_cell("shi_tou", Vector2i(107, 104))
	world.invalidate_region("home")
	return world


func _site(runner: Object, world: RegionalSimulation) -> void:
	runner.assert_true(world.construction.register_site("player", Vector2i(108, 106)).ok, "authorized staff registers a physical public work yard")
	runner.assert_true(not world.construction.register_site("su_zhi", Vector2i(108, 106)).ok, "unassigned staff cannot grant public land/material rights")


func _place(runner: Object, world: RegionalSimulation, type: String = "wood_wall", cell: Vector2i = Vector2i(109, 107)) -> String:
	var result: Dictionary = world.construction.place("player", type, cell)
	runner.assert_true(result.ok, "a visible empty work cell accepts a blueprint")
	return str(result.get("project", ""))


func _finish(runner: Object, world: RegionalSimulation, actor: String = "player") -> void:
	for _i: int in 120:
		if not world.construction.active.has(actor):
			return
		var now: int = world.elapsed_ms
		var boundary: int = maxi(now + 1, world.construction.next_boundary_ms())
		if not world.advance_to_ms(boundary):
			runner.assert_true(false, "construction advances at its true route/work boundary")
			return
	runner.assert_true(false, "bounded construction settles without spinning")


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _test_real_material_and_interruptions(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	_site(runner, world)
	var domain: SimConstruction = world.construction
	var sim: VillageSimulation = world.regions.home
	var id: String = _place(runner, world)
	var cell := Vector2i(109, 107)
	runner.assert_true(not domain.blocked(cell), "paper blueprint does not block movement")
	runner.assert_true(not domain.place("player", "wood_door", cell).ok, "two live structures cannot occupy one cell")
	var stock: int = sim.inventory.quantity("store", "wood")
	var response: Dictionary = domain.begin("player", id)
	runner.assert_true(response.ok, "construction takes an exclusive body and stock reservation: " + str(response.line))
	if not response.ok:
		return
	runner.assert_eq(sim.inventory.quantity("store", "wood"), stock, "reserving does not teleport wood out of its store")
	var reserved_copy: RegionalSimulation = _world(runner)
	runner.assert_true(reserved_copy.restore(JSON.parse_string(_canonical(world))), "unfetched public construction reservation survives both village validation passes")
	runner.assert_true(not sim.submit_action("player", "deliver_water"), "the same body cannot haul water while constructing")
	runner.assert_true(not domain.begin("shi_tou", id).ok, "another worker cannot claim the same order")
	for _i: int in 40:
		if str(domain.active.player.phase) == "to_site" and not str(domain.projects[id].carrier).is_empty():
			break
		world.advance_to_ms(domain.next_boundary_ms())
	runner.assert_eq(sim.inventory.quantity("store", "wood"), stock - 3, "only reaching and picking up actually removes the batch")
	runner.assert_eq(sim.inventory.quantity(id, "wood"), 3, "one actual carried batch exists in the original ledger")
	runner.assert_true(not domain.blocked(cell), "carrying materials is not a completed wall")
	world.advance_to_ms(world.elapsed_ms + 77)
	var carried: Dictionary = JSON.parse_string(_canonical(world))
	var continued: RegionalSimulation = _world(runner)
	runner.assert_true(continued.restore(carried), "a carried construction batch restores with its original reservation receipt")
	domain.cancel("player")
	runner.assert_eq(domain.projects[id].carrier, "", "interruption drops the material at its actual carrier position")
	runner.assert_true(domain.material_cell_referenced(SimRouteTravel.cell(domain.projects[id].material_cell)), "live terrain guard indexes the actual dropped material coordinate")
	runner.assert_true(continued.construction.material_cell_referenced(SimRouteTravel.cell(continued.construction.projects[id].material_cell)), "independent carried restore rebuilds material references without saving an index")
	runner.assert_eq(sim.inventory.quantity("store", "wood"), stock - 3, "cancel does not silently refund moved material")
	runner.assert_true(domain.begin("player", id).ok, "resume routes to the real dropped batch")
	for _i: int in 80:
		if domain.active.player.phase == "work":
			break
		world.advance_to_ms(domain.next_boundary_ms())
	world.advance_to_ms(world.elapsed_ms + 65432)
	domain.cancel("player")
	runner.assert_eq(domain.projects[id].work_ms, 65432, "partial work is retained independently of presentation frames")
	runner.assert_true(domain.begin("player", id).ok, "resume uses delivered lumber and remaining labor")
	var mid: Dictionary = JSON.parse_string(_canonical(world))
	var restored: RegionalSimulation = _world(runner)
	runner.assert_true(restored.restore(mid), "ongoing construction restores without making free material or free progress")
	_finish(runner, world)
	var end: int = world.elapsed_ms
	var cursor: int = restored.elapsed_ms
	while cursor < end:
		cursor = mini(end, cursor + 997)
		restored.advance_to_ms(cursor)
	runner.assert_eq(_canonical(restored), _canonical(world), "fine-grained restored work has the same complete world future")
	runner.assert_true(domain.blocked(cell), "only completed wall now changes ground passage")
	runner.assert_eq(sim.inventory.quantity(id, "wood"), 0, "completed structure consumes its original batch once")
	runner.assert_eq(sim.inventory.quantity("store", "wood"), stock - 3, "resuming never fetches a duplicate batch")
	var saved: Dictionary = JSON.parse_string(_canonical(world))
	runner.assert_true(restored.restore(saved) and restored.restore(saved), "repeated loading cannot repeat construction cost or create materials")


func _test_door_and_recovery(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	_site(runner, world)
	var domain: SimConstruction = world.construction
	var sim: VillageSimulation = world.regions.home
	var stock: int = sim.inventory.quantity("store", "wood")
	var cell := Vector2i(109, 107)
	var id: String = _place(runner, world, "wood_door", cell)
	var response: Dictionary = domain.begin("player", id)
	runner.assert_true(response.ok, "door uses its own real cost and construction duration: " + str(response.line))
	if not response.ok:
		return
	_finish(runner, world)
	runner.assert_true(domain.blocked(cell) and domain.begin("player", id, "open").ok, "a finished closed door can be approached and handled")
	runner.assert_true(domain.blocked(cell), "clicking open does not instantly operate the remote door")
	_finish(runner, world)
	runner.assert_true(not domain.blocked(cell), "after handling the doorway really opens")
	sim.set_actor_cell("shi_tou", cell)
	runner.assert_true(domain.begin("player", id, "close").ok, "door closing still takes a real action")
	_finish(runner, world)
	runner.assert_true(not domain.blocked(cell), "closure cannot enclose a living body in solid space")
	sim.set_actor_cell("shi_tou", Vector2i(107, 104))
	runner.assert_true(domain.begin("player", id, "close").ok, "clear the doorway and close it again")
	_finish(runner, world)
	runner.assert_true(domain.blocked(cell), "unoccupied door closes after its action")
	runner.assert_true(domain.begin("player", id, "demolish").ok, "authorized dismantling is a timed job")
	_finish(runner, world)
	runner.assert_true(not domain.blocked(cell), "only completed dismantling removes collision")
	runner.assert_eq(sim.inventory.quantity(id, "wood"), 2, "dismantling leaves a finite smaller batch on the ground")
	runner.assert_eq(sim.inventory.quantity("store", "wood"), stock - 4, "salvage is not already back in the warehouse")
	runner.assert_true(domain.begin("player", id, "recover").ok, "leftover materials need an actual return journey")
	_finish(runner, world)
	runner.assert_eq(sim.inventory.quantity("store", "wood"), stock - 2, "real recovery returns only the salvaged amount")
	var resumed: RegionalSimulation = _world(runner)
	runner.assert_true(resumed.restore(JSON.parse_string(_canonical(world))), "dismantled and recovered material receipts restore together")
	var reference: Vector2i = SimRouteTravel.cell(domain.projects[id].material_cell)
	runner.assert_true(domain.material_cell_referenced(reference) and resumed.construction.material_cell_referenced(reference), "zero-stock terminal coordinates retain the current archive's declared spatial protection after restore")


func _test_remote_duty_and_candidates(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	_site(runner, world)
	var id: String = _place(runner, world)
	world.regions.home.actors.shi_tou.autonomous = true
	world.regions.home.actors.shi_tou.retry_ms = 1
	world.regions.home.actors.shi_tou.hunger = 100.0
	var raw: Dictionary = JSON.parse_string(_canonical(world))
	var remote: RegionalSimulation = _world(runner)
	runner.assert_true(remote.restore(raw), "public work order restores before being claimed")
	world.set_active_region("home")
	remote.set_active_region("river")
	world.advance_to_ms(600000)
	var cursor: int = remote.elapsed_ms
	while cursor < 600000:
		cursor = mini(600000, cursor + 4391)
		remote.advance_to_ms(cursor)
	remote.set_active_region(world.active_region)
	runner.assert_eq(_canonical(remote), _canonical(world), "absent work duty uses the same fine/coarse world rules")
	runner.assert_eq(world.construction.projects[id].state, "built", "nearby autonomous duty-holder actually hauls and completes construction")
	if world.construction.projects[id].state != "built":
		print("Construction pending: ", world.construction.to_dict(), " actor=", world.regions.home.actors.shi_tou)
		return
	var before: String = _canonical(world)
	for variant: int in 5:
		var bad: Dictionary = JSON.parse_string(before)
		match variant:
			0: bad.construction.sites.sect_yard.owner = "player"
			1: bad.construction.projects[id].work_ms = 0
			2: bad.regions.home.inventory.containers[id].wood = 3
			3: bad.construction.projects[id].created_by = "su_zhi"
			4: bad.regions.home.inventory.operations[id + ":supply"].amount = 4
		runner.assert_true(not world.restore(bad), "inconsistent rights/material/progress rejected at candidate boundary %d" % variant)
		runner.assert_eq(_canonical(world), before, "rejected construction load preserves the whole live world %d" % variant)


func _test_shortages_obstruction_and_clearance(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	_site(runner, world)
	var domain: SimConstruction = world.construction
	var sim: VillageSimulation = world.regions.home
	var id: String = _place(runner, world)
	var stock: int = sim.inventory.quantity("store", "wood")
	sim.inventory.containers.store.wood = 0
	runner.assert_true(not domain.begin("player", id).ok and domain.active.is_empty() and sim.inventory.reservations.is_empty(), "short stock leaves a real unclaimed blueprint without partial reservations")
	sim.inventory.containers.store.wood = stock
	runner.assert_true(not domain.begin("su_zhi", id).ok, "being a nearby human does not grant material/land permissions")
	runner.assert_true(domain.begin("player", id).ok, "new actual supply allows the same original blueprint to start")
	for _i: int in 40:
		if domain.active.player.phase == "to_site" and not domain.projects[id].carrier.is_empty():
			break
		world.advance_to_ms(domain.next_boundary_ms())
	sim._step_validator = func(_from: Vector2i, _direction: Vector2i) -> bool: return false
	world.advance_to_ms(world.elapsed_ms + 1)
	runner.assert_true(not domain.owns_actor("player") and domain.projects[id].carrier.is_empty(), "a newly blocked first step interrupts movement and grounds its actual load")
	runner.assert_eq(sim.inventory.quantity(id, "wood"), 3, "blocked route does not delete or refund its carried lumber")
	var restored: RegionalSimulation = _world(runner)
	runner.assert_true(restored.restore(JSON.parse_string(_canonical(world))), "dropped material after route obstruction is a valid ongoing world")
	runner.assert_true(domain.cancel_project("player", id).ok, "canceling the blueprint preserves its dropped physical materials")
	runner.assert_true(domain.next_check_ms == SimInventory.MAX_COUNT, "canceled last blueprint leaves no ghost work polling deadline")
	runner.assert_true(restored.restore(JSON.parse_string(_canonical(world))), "canceled blueprint and exact leftover inventory remain loadable")
	var shortage: RegionalSimulation = _world(runner)
	_site(runner, shortage)
	var held: String = _place(runner, shortage)
	shortage.regions.home.actors.shi_tou.autonomous = true
	shortage.regions.home.actors.shi_tou.hunger = 5.0
	shortage.advance_to_ms(60000)
	runner.assert_true(not shortage.construction.owns_actor("shi_tou") and shortage.construction.projects[held].state == "blueprint", "urgent personal food need takes precedence over optional construction duty")
	var clear: RegionalSimulation = _world(runner)
	_site(runner, clear)
	var clear_id: String = _place(runner, clear)
	clear.regions.home.set_actor_cell("shi_tou", Vector2i(109, 107))
	runner.assert_true(clear.construction.begin("player", clear_id).ok, "work may proceed while the intended final footprint is temporarily occupied")
	_finish(runner, clear)
	runner.assert_eq(clear.construction.projects[clear_id].state, "blueprint", "completed labor does not embed a living body in a wall")
	runner.assert_eq(clear.construction.projects[clear_id].work_ms, 180000, "waiting for site clearance preserves fully completed labor")
	clear.regions.home.set_actor_cell("shi_tou", Vector2i(107, 104))
	runner.assert_true(clear.construction.begin("player", clear_id).ok, "cleared project can be finalized from its already delivered materials")
	_finish(runner, clear)
	runner.assert_true(clear.construction.blocked(Vector2i(109, 107)), "clearance permits the real wall to finish without repeating labor")
