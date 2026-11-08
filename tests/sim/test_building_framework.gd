extends RefCounted
## Primary contract owner: construction geometry and facility use. Failures here
## mean duplicate multi-cell instances, leaked claims or lost/duplicated stock.
const Fixture = preload("res://tests/sim/test_construction.gd")
var fixture := Fixture.new()

class DuringDamage extends RefCounted:
	var owner: WeakRef
	var rejected: bool = false
	func finished(_outcome: Dictionary) -> void:
		var world: RegionalSimulation = owner.get_ref()
		rejected = world.to_dict().is_empty() and not world.advance_to_ms(world.elapsed_ms + 1) and not world.construction.place("player", "wood_wall", Vector2i(113, 108)).ok


func run(runner: Object) -> void:
	_test_definitions(runner)
	_test_composition_and_storage(runner)
	_test_workbench(runner)
	_test_budgeted_facilities(runner)


func _test_budgeted_facilities(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	fixture._site(runner, world)
	var chairs: Array[String] = [_build(runner, world, "wood_chair", Vector2i(109, 107)), _build(runner, world, "wood_chair", Vector2i(111, 107))]
	for index: int in 2:
		var actor: String = "player" if index == 0 else "shi_tou"
		var slot: Dictionary = world.construction.operation_slots(chairs[index], "seat")[0]
		world.regions.home.set_actor_position(actor, TileGrid.cell_to_world(slot.cell))
		runner.assert_true(world.facility_use.begin(actor, chairs[index], slot.id, "sit", "", 0, 1000).ok, "two original actors reserve independent real seats")
	var original: Dictionary = JSON.parse_string(fixture._canonical(world))
	var reference: RegionalSimulation = _world(runner)
	runner.assert_true(reference.restore(original), "both in-flight seat jobs have a valid ordinary save boundary")
	var target: int = world.elapsed_ms + 2000
	runner.assert_true(reference.advance_to_ms(target), "unlimited facilities provide the reference joint future")
	var split_inside_owner: bool = false
	var finished: Array[Dictionary] = []
	var listener: Callable = func(outcome: Dictionary) -> void: finished.append(outcome.duplicate(true))
	world.action_finished.connect(listener)
	for _attempt: int in 2000:
		if world.advance_to_ms(target, 4096, 1):
			break
		if not split_inside_owner and world.settlement.progress().step == "facility_use" and world.facility_use._settlement_cursor == 1:
			split_inside_owner = true
			var job: Dictionary = world.facility_use.active.get("shi_tou", {}).duplicate(true)
			var finished_before: int = finished.size()
			var seat_cell: Vector2i = world.construction.operation_slots(chairs[1], "seat")[0].cell
			runner.assert_true(not job.is_empty() and world.facility_use.cell_reserved(seat_cell) and world.facility_use.project_reserved(chairs[1]), "the second original job still owns its operation position at the partial boundary")
			runner.assert_true(not world.facility_use.cancel("shi_tou"), "external cancellation cannot modify a partially settled facility stage")
			world.interrupt_occupation("shi_tou", "external_interrupt")
			runner.assert_true(world.facility_use.active.get("shi_tou", {}) == job and world.facility_use.cell_reserved(seat_cell) and world.facility_use.project_reserved(chairs[1]) and finished.size() == finished_before, "refused cancellation leaves the active job, both reservations and finish notifications unchanged")
	world.action_finished.disconnect(listener)
	runner.assert_true(split_inside_owner, "the shared kernel can yield between two real facility jobs at the same instant")
	runner.assert_true(not world.settlement.is_pending() and world.elapsed_ms == target, "the exact original stage and remaining jobs eventually finish")
	runner.assert_true(fixture._canonical(world) == fixture._canonical(reference), "splitting a real owner preserves all world state, materials, bodies and time")
	var seat: Dictionary = world.construction.operation_slots(chairs[0], "seat")[0]
	world.regions.home.set_actor_position("player", TileGrid.cell_to_world(seat.cell))
	runner.assert_true(world.facility_use.begin("player", chairs[0], seat.id).ok, "a completed boundary accepts a new ordinary facility job")
	runner.assert_true(world.facility_use.cancel("player") and not world.facility_use.owns_actor("player") and not world.facility_use.project_reserved(chairs[0]), "normal cancellation still releases the new job and its seat after completion")


func _build(runner: Object, world: RegionalSimulation, type: String, cell: Vector2i, rotation: int = 0) -> String:
	var result: Dictionary = world.construction.place("player", type, cell, rotation)
	runner.assert_true(result.ok, "generic blueprint accepts %s: %s" % [type, result.line])
	if not result.ok:
		return ""
	var id: String = result.project
	runner.assert_true(world.construction.begin("player", id).ok, "generic construction accepts " + type)
	fixture._finish(runner, world)
	runner.assert_eq(world.construction.projects[id].state, "built", "original material/work pipeline builds " + type)
	return id


func _finish_use(runner: Object, world: RegionalSimulation) -> void:
	for _index: int in 100:
		if not world.facility_use.owns_actor("player"):
			return
		runner.assert_true(world.advance_to_ms(world.facility_use.next_boundary_ms()), "facility uses the shared event boundaries")
	runner.assert_true(false, "facility action must finish within its bounded route")


func _test_definitions(runner: Object) -> void:
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/construction.json"))
	definitions["site"] = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/construction.json")).site
	runner.assert_true(SimConstruction.valid_definitions(definitions), "current definitions validate independent capabilities and geometry")
	var rule: Dictionary = definitions.types.wood_table
	var cells: Array[Vector2i] = SimConstructionGeometry.cells({"cell": [20, 30], "rotation": 1}, rule)
	runner.assert_eq(cells, [Vector2i(20, 30), Vector2i(20, 31)], "rotation changes real footprint rather than creating cell instances")
	var invalid: Dictionary = definitions.duplicate(true)
	invalid.types.wood_chest.slots[0].cell = [0, 0]
	runner.assert_true(not SimConstruction.valid_definitions(invalid), "solid furniture cannot put its operation slot inside itself")
	invalid = definitions.duplicate(true)
	invalid.types.wood_chair.capabilities["magic_unimplemented"] = {}
	runner.assert_true(not SimConstruction.valid_definitions(invalid), "unimplemented capabilities are refused, not advertised")
	var extension: Dictionary = definitions.duplicate(true)
	extension.types["another_table"] = definitions.types.wood_table.duplicate(true)
	runner.assert_true(SimConstruction.valid_definitions(extension), "another definition with implemented abilities requires no type-name branch")
	invalid = definitions.duplicate(true)
	invalid.types.wood_window.facts.sight_blocked = "false"
	runner.assert_true(not SimConstruction.valid_definitions(invalid), "physical facts are typed independently")


func _test_composition_and_storage(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	fixture._site(runner, world)
	runner.assert_true(not world.resting.begin("player", "missing_bed").ok, "unknown bed remains a business refusal without indexing missing state")
	var domain: SimConstruction = world.construction
	var second: Dictionary = domain.register_site("player", Vector2i(108, 111), Vector2i(5, 3))
	runner.assert_true(second.ok and domain.sites.size() == 2, "independent non-overlapping yards share one construction owner")
	runner.assert_true(not domain.register_site("player", Vector2i(110, 109)).ok, "overlapping yard registration is atomic")
	runner.assert_true(domain.designate("player", Rect2i(108, 106, 7, 5), "workshop").ok, "purpose is a separate designation")
	runner.assert_eq(domain.zones_at(Vector2i(109, 107))[0].purpose, "workshop", "designation does not spawn a functional building")
	var designation: Dictionary = domain.designate("player", Rect2i(108, 106, 7, 5), "quiet_courtyard")
	runner.assert_true(designation.ok and domain.zones.size() == 1 and domain.zones_at(Vector2i(109, 107))[0].purpose == "quiet_courtyard", "free purpose markers update the same area without a new mechanism")
	runner.assert_true(domain.clear_zone("player", designation.zone).ok and domain.zones_at(Vector2i(109, 107)).is_empty(), "clearing a designation leaves all original world objects alone")
	var stone: String = _build(runner, world, "stone_wall", Vector2i(108, 111))
	runner.assert_true(not stone.is_empty() and world.regions.home.inventory.quantity(stone, "stone") == 0, "another yard/material uses original one-time construction costs")
	var long_bed: String = _build(runner, world, "long_bed", Vector2i(111, 111))
	runner.assert_true(domain.is_bed(long_bed) and domain.project_cells(long_bed).size() == 2, "resting reads a capability on the same multi-cell instance")
	var window: String = _build(runner, world, "wood_window", Vector2i(114, 106))
	runner.assert_true(domain.blocked(Vector2i(114, 106)) and not domain.blocks_sight(Vector2i(114, 106)) and domain.fact(window, "enclosure_boundary"), "window independently blocks movement, permits sight and encloses")
	var table: String = _build(runner, world, "wood_table", Vector2i(109, 107), 1)
	if table.is_empty(): return
	runner.assert_eq(domain.project_at(Vector2i(109, 108)), table, "every footprint cell resolves to the original identity")
	var local: Dictionary = world.space.query(Rect2i(109, 107, 1, 2), ["construction"], "ground", 64)
	runner.assert_true(local.ok and local.references.size() == 1, "common live space deduplicates a multi-cell table: " + str(local))
	var chair: String = _build(runner, world, "desk_chair", Vector2i(109, 109))
	if chair.is_empty(): return
	runner.assert_true(world.facility_use.begin("player", chair, "seat").ok, "seat facing a real table accepts use")
	runner.assert_true(not world.facility_use.begin("shi_tou", chair, "seat").ok, "another body cannot reserve the same operation position")
	runner.assert_true(not domain.begin("shi_tou", table, "demolish").ok, "an actively used table cannot be dismantled through another domain")
	var saved: Dictionary = JSON.parse_string(fixture._canonical(world))
	var restored: RegionalSimulation = _world(runner)
	runner.assert_true(restored.restore(saved), "in-flight seat reservation restores in an independent candidate")
	_finish_use(runner, world)
	runner.assert_true(restored.advance_to_ms(world.elapsed_ms), "restored facility uses the same full interval")
	runner.assert_eq(fixture._canonical(restored), fixture._canonical(world), "in-flight facility has identical complete future after restore")
	var chest: String = _build(runner, world, "wood_chest", Vector2i(112, 109))
	if chest.is_empty(): return
	var inventory: SimInventory = world.regions.home.inventory
	inventory.containers["actor:player"].wood = 4
	runner.assert_true(world.facility_use.begin("player", chest, "front", "deposit", "wood", 4).ok, "deposit reserves actual original hand stock")
	runner.assert_eq(inventory.quantity(chest + ":contents", "wood"), 0, "requesting a deposit cannot teleport goods")
	var reserved: Dictionary = JSON.parse_string(fixture._canonical(world))
	var malformed: Dictionary = reserved.duplicate(true)
	malformed.facility_use.active.player.stand = "bad-cell"
	var stable_candidate: String = fixture._canonical(restored)
	runner.assert_true(not restored.restore(malformed) and fixture._canonical(restored) == stable_candidate, "malformed slot candidates are refused before cross-slot reads or live replacement")
	runner.assert_true(restored.restore(reserved), "pending deposit and original quantity reservation restore together")
	_finish_use(runner, world)
	runner.assert_eq(inventory.quantity(chest + ":contents", "wood"), 4, "arrival transfers goods once into the original ledger container")
	runner.assert_eq(inventory.quantity("actor:player", "wood"), 0, "the hand does not keep a duplicate")
	runner.assert_true(restored.advance_to_ms(world.elapsed_ms), "restored deposit reaches the same finish")
	runner.assert_eq(fixture._canonical(restored), fixture._canonical(world), "restored deposit has identical original ledger receipts")
	inventory.containers["actor:player"].wood = 25
	runner.assert_true(not world.facility_use.begin("player", chest, "front", "deposit", "wood", 25).ok, "aggregate capacity is checked before reserving")
	var hp: int = int(domain.projects[chest].hp)
	var hit: Dictionary = domain.damage(chest, 7)
	runner.assert_true(hit.ok and domain.projects[chest].hp == hp - 5, "building owner applies armor without inventing a pawn body")
	runner.assert_true(domain.damage(chest, 100000).destroyed, "lethal damage removes active structure capabilities")
	runner.assert_true(not domain.blocked(Vector2i(112, 109)) and domain.projects[chest].state == "ruined", "ruins remain an identifiable nonblocking entity")
	runner.assert_eq(inventory.quantity(chest + ":contents", "wood"), 4, "destruction keeps the same actual contents")
	runner.assert_true(not domain.begin("player", chest, "demolish").ok, "clearing a filled wreck cannot delete its contents")
	runner.assert_true(world.facility_use.begin("player", chest, "front", "withdraw", "wood", 4).ok, "contents can be recovered from the original wreck")
	_finish_use(runner, world)
	var salvage: int = inventory.quantity(chest, "wood")
	runner.assert_true(domain.begin("player", chest, "demolish").ok, "empty wreck can be cleared through the original action")
	fixture._finish(runner, world)
	runner.assert_eq(inventory.quantity(chest, "wood"), salvage, "clearing a wreck cannot issue salvage twice")
	runner.assert_true(restored.restore(JSON.parse_string(fixture._canonical(world))), "ruin recovery and clearing receipts restore together")
	runner.assert_true(world.facility_use.begin("player", chair, "seat").ok, "seat can be used again after releasing the original claim")
	var observer := DuringDamage.new()
	observer.owner = weakref(world)
	world.action_finished.connect(observer.finished)
	runner.assert_true(domain.damage(table, 100000).destroyed and not world.facility_use.owns_actor("player"), "loss of a required table cancels the real dependent seat action")
	world.action_finished.disconnect(observer.finished)
	runner.assert_true(observer.rejected, "damage callbacks cannot save, advance or mutate a half-committed structure transaction")
	runner.assert_true(not world.facility_use.begin("player", chair, "seat").ok, "a nearby chair does not invent its missing required table")
	runner.assert_true(restored.restore(JSON.parse_string(fixture._canonical(world))), "dependent cancellation and damaged layout restore together")
	var before: String = fixture._canonical(restored)
	var corrupt: Dictionary = JSON.parse_string(before)
	corrupt.construction.projects[table].rotation = 9
	runner.assert_true(not restored.restore(corrupt) and fixture._canonical(restored) == before, "bad footprint candidate cannot partly modify the live world")


func _test_workbench(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	fixture._site(runner, world)
	var stove: String = _build(runner, world, "cook_stove", Vector2i(110, 107))
	if stove.is_empty(): return
	world.regions.home.inventory.containers["actor:player"].merge({"wood": 1, "grain": 2, "water": 1}, true)
	var stand: Vector2i = world.construction.operation_slots(stove, "workbench")[0].cell
	world.regions.home.set_actor_cell("shi_tou", stand)
	var blocked: Dictionary = world.personal_production.create("player", "home", "cook_rations", stove)
	runner.assert_true(blocked.ok, "a claim alone does not teleport the actual occupant out of the work position")
	for _index: int in 120:
		if not world.personal_production.owns_actor("player"): break
		world.advance_to_ms(world.personal_production.next_boundary_ms())
	runner.assert_true(not world.personal_production.owns_actor("player") and world.personal_production.batches[blocked.batch].supplied_ms == -1, "actual occupied arrival is refused before ignition or ingredient investment")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "wood"), 1, "failed occupied arrival does not consume fuel")
	world.regions.home.set_actor_cell("shi_tou", Vector2i(107, 104))
	var result: Dictionary = world.personal_production.create("player", "home", "cook_rations", stove)
	runner.assert_true(result.ok, "a constructed workbench supplies the original production recipe conditions")
	if not result.ok: return
	var batch: String = result.batch
	runner.assert_true(not world.construction.begin("shi_tou", stove, "demolish").ok, "production reserves the actual workbench")
	for _index: int in 120:
		if world.personal_production.active.player.phase == "work": break
		world.advance_to_ms(world.personal_production.next_boundary_ms())
	world.advance_to_ms(world.elapsed_ms + 1234)
	var restored: RegionalSimulation = _world(runner)
	runner.assert_true(restored.restore(JSON.parse_string(fixture._canonical(world))), "workbench reference, real ingredients and work restore together")
	var deadline: int = int(world.personal_production.active.player.due_ms)
	runner.assert_true(world.advance_to_ms(deadline) and restored.advance_to_ms(deadline), "workbench production uses its original deadline")
	runner.assert_eq(fixture._canonical(restored), fixture._canonical(world), "restored workbench production has the same complete future")
	runner.assert_eq(world.regions.home.inventory.quantity(batch, "meal"), 6, "workbench creates only the original recipe output")
	var chair: String = _build(runner, world, "wood_chair", stand)
	runner.assert_true(world.facility_use.begin("shi_tou", chair, "seat").ok, "another supported process can reserve the shared physical position")
	runner.assert_true(not world.personal_production.begin("player", batch, "collect").ok, "collecting output respects an existing operation-position claim")
	world.facility_use.cancel("shi_tou")
	runner.assert_true(world.construction.damage(stove, 100000).destroyed, "completed stock stays in the original batch when its workbench is destroyed")
	runner.assert_true(world.personal_production.begin("player", batch, "collect").ok, "finished output can still be physically recovered from a destroyed workbench")
	while world.personal_production.owns_actor("player"):
		world.advance_to_ms(world.personal_production.next_boundary_ms())
	runner.assert_eq(world.regions.home.inventory.quantity(batch, "meal"), 0, "collection removes the original output rather than copying it")
	runner.assert_true(world.construction.begin("player", stove, "demolish").ok, "clear the first workbench wreck without issuing salvage again")
	fixture._finish(runner, world)
	stove = _build(runner, world, "cook_stove", Vector2i(110, 107))
	world.regions.home.inventory.containers["actor:player"].merge({"wood": 1, "grain": 2, "water": 1}, true)
	var interrupted: Dictionary = world.personal_production.create("player", "home", "cook_rations", stove)
	runner.assert_true(interrupted.ok, "a new batch reserves the same actual workbench after collection")
	if not interrupted.ok: return
	for _index: int in 120:
		if world.personal_production.active.player.phase == "work": break
		world.advance_to_ms(world.personal_production.next_boundary_ms())
	world.advance_to_ms(world.elapsed_ms + 2345)
	runner.assert_true(world.construction.damage(stove, 100000).destroyed and not world.personal_production.owns_actor("player"), "workbench destruction interrupts the original producer")
	runner.assert_eq(world.personal_production.batches[interrupted.batch].work_ms, 2345, "interruption retains completed labor")
	runner.assert_eq(world.regions.home.inventory.quantity(interrupted.batch, "grain"), 2, "unfinished ingredients retain their original batch container")
	runner.assert_true(not world.personal_production.begin("player", interrupted.batch, "make").ok, "destroyed workbench cannot silently finish a batch")
	runner.assert_true(restored.restore(JSON.parse_string(fixture._canonical(world))), "destroyed facility and retained in-process batch restore without re-ignition")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = fixture._world(runner)
	world.bind_map_data(preload("res://tests/sim/test_structure_query.gd").FlatMap.new())
	world.regions.home.set_navigation(_path.bind(weakref(world)))
	return world


func _path(from: Vector2i, to: Vector2i, reference: WeakRef) -> Array[Vector2i]:
	var world: RegionalSimulation = reference.get_ref()
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(90, 90, 50, 50)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE
	grid.update()
	for cell: Vector2i in SimConstruction.cells_in(grid.region):
		if world.construction.blocked(cell): grid.set_point_solid(cell)
	var result: Array[Vector2i] = []
	for cell: Vector2i in grid.get_id_path(from, to):
		if cell != from: result.append(cell)
	return result
