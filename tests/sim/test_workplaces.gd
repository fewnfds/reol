extends RefCounted
## Real native errands and visitor settlement share the same room/authority check.

const Workplaces = preload("res://scripts/sim/workplaces.gd")
const VillageFixture = preload("res://tests/sim/test_village_simulation.gd")
const ServiceFixture = preload("res://tests/sim/test_settlement_services.gd")


class FlatMap extends WorldMapData:
	func get_terrain(cell: Vector2i) -> int:
		return TERRAIN_GRASS if in_bounds(cell) else -1


	func get_elevation(cell: Vector2i) -> int:
		return 0 if in_bounds(cell) else -1


class ClosedMap extends FlatMap:
	func terrain_is_walkable(_cell: Vector2i) -> bool:
		return false


func run(runner: Object) -> void:
	_opening_and_geometry(runner)
	_strict_restore_and_legacy(runner)
	_native_registration(runner)
	_return_to_desk_and_resume(runner)
	_visitor_redemption(runner)
	print("SCENARIO workplaces: real rooms, old offices/books, native return after eating, interrupted redemption and saved in-flight return")


func _make(runner: Object) -> VillageSimulation:
	var sim: VillageSimulation = VillageFixture.new()._make_simulation(runner)
	if sim == null:
		return null
	if not Workplaces.enable_opening(sim.config, sim.places, sim.actors, FlatMap.new(), str(sim.config.institution.id), sim._content.workplaces):
		runner.assert_true(false, "fixed opening room fits original places and bodies")
		return null
	_bind_path(sim, [sim.places])
	return sim


func _bind_path(sim: VillageSimulation, areas: Array) -> void:
	sim.set_navigation(func(from: Vector2i, to: Vector2i) -> Array[Vector2i]: return _path(areas, from, to),
		func(_from: Vector2i, step: Vector2i) -> bool: return not _blocked(areas, _from + step))


func _opening_and_geometry(runner: Object) -> void:
	var sim: VillageSimulation = VillageFixture.new()._make_simulation(runner)
	if sim == null:
		return
	var original_places: String = _canonical(sim.places)
	var original_config: String = _canonical(sim.config)
	var original_book: String = _canonical(sim.institutions.to_dict())
	var original_inventory: String = _canonical(sim.inventory.to_dict())
	runner.assert_true(not Workplaces.enable_opening(sim.config, sim.places, sim.actors, ClosedMap.new(), "sect", sim._content.workplaces), "no room is generated on impassable terrain")
	runner.assert_eq(_canonical(sim.places), original_places, "failed room assembly preserves every original destination")
	runner.assert_eq(_canonical(sim.config), original_config, "failed room assembly does not enable a half-configured policy")
	runner.assert_true(Workplaces.enable_opening(sim.config, sim.places, sim.actors, FlatMap.new(), "sect", sim._content.workplaces), "a physical room attaches to original records target")
	_bind_path(sim, [sim.places])
	runner.assert_eq(_canonical(sim.places.records.cell), _canonical(JSON.parse_string(original_places).records.cell), "records travel anchor is preserved")
	runner.assert_eq(_canonical(sim.institutions.to_dict()), original_book, "walls and furniture mint no authority or contribution")
	runner.assert_eq(_canonical(sim.inventory.to_dict()), original_inventory, "opening furniture does not manufacture redeemable goods")
	runner.assert_true(Workplaces.valid_places(sim.places, sim.config, FlatMap.new(), sim._content.workplaces), "complete versioned room validates on its original flat terrain")
	var cells: Dictionary = {}
	for id: String in sim.actors:
		cells[id] = sim.actors[id].cell.duplicate()
	var initialized := VillageSimulation.new()
	runner.assert_true(initialized.initialize(sim._content, sim.config, cells, sim.places), "opening API produces directly initializable JSON-compatible config and places")
	var room: Dictionary = sim.places.records.workspace
	for raw: Array in room.walls:
		runner.assert_true(Workplaces.blocked(sim.places, SimRouteTravel.cell(raw)), "built wall is a real movement obstacle")
	for fixture: String in ["desk", "archive"]:
		runner.assert_true(Workplaces.blocked(sim.places, SimRouteTravel.cell(room.fixtures[fixture].cell)), "solid furniture blocks its actual tile: " + fixture)
	runner.assert_true(not Workplaces.blocked(sim.places, SimRouteTravel.cell(room.door)), "fixed doorway is an actual opening")
	runner.assert_true(not Workplaces.blocked(sim.places, SimRouteTravel.cell(room.clerk_cell)), "shared reception and clerk tile stays walkable")
	runner.assert_true(Workplaces.roofed(sim.places, SimRouteTravel.cell(room.clerk_cell)), "roof query comes from the saved room")
	for actor: Dictionary in sim.actors.values():
		runner.assert_true(not Workplaces.blocked(sim.places, SimRouteTravel.cell(actor.cell)), "no opening person is enclosed inside a wall or desk")
	var door: Vector2i = SimRouteTravel.cell(room.door)
	var outside: Vector2i = door + (door - SimRouteTravel.cell(room.clerk_cell)).sign()
	var path: Array[Vector2i] = sim.find_path(outside, SimRouteTravel.cell(room.clerk_cell))
	runner.assert_true(not path.is_empty(), "original routing can enter through the physical door")
	for cell: Vector2i in path:
		runner.assert_true(not Workplaces.blocked(sim.places, cell), "route never crosses a room wall or solid furniture")


func _strict_restore_and_legacy(runner: Object) -> void:
	var legacy: VillageSimulation = VillageFixture.new()._make_simulation(runner)
	if legacy == null:
		return
	var legacy_saved: Dictionary = legacy.to_dict()
	runner.assert_true(legacy.restore(JSON.parse_string(_canonical(legacy_saved))), "old snapshots restore through their original rules")
	runner.assert_true(not legacy.places.records.has("workspace"), "legacy restore does not invent a room or official carrier")
	runner.assert_true(Workplaces.assessment(legacy, "chen_shouzhuo", "record").ok, "legacy registrar retains previous nearby-counter behavior")
	var sim: VillageSimulation = _make(runner)
	if sim == null:
		return
	var saved: Dictionary = sim.to_dict()
	var before: String = _canonical(saved)
	var mutations: Array[String] = ["room_missing", "version", "institution", "private_book", "missing_wall", "extra_balance", "return_action", "body_in_wall"]
	for mutation: String in mutations:
		var bad: Dictionary = JSON.parse_string(before)
		match mutation:
			"room_missing": bad.places.records.erase("workspace")
			"version": bad.places.records.workspace.version = true
			"institution": bad.places.records.workspace.institution = "foreign_sect"
			"private_book": bad.places.records.workspace.fixtures.register.kind = "private_notebook"
			"missing_wall": bad.places.records.workspace.walls.pop_back()
			"extra_balance": bad.places.records.workspace.fixtures.register.balance = 999
			"return_action": bad.config.actions.workspace_return.minutes = 0
			"body_in_wall":
				var cell: Array = bad.places.records.workspace.walls[0]
				bad.actors.player.cell = cell.duplicate()
				var point: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(cell))
				bad.actors.player.position = [point.x, point.y]
		runner.assert_true(not sim.restore(bad), "damaged modern room is refused: " + mutation)
		runner.assert_eq(_canonical(sim.to_dict()), before, "refused room cannot change the live world: " + mutation)
	runner.assert_true(sim.restore(JSON.parse_string(before)), "valid modern room survives JSON save/restore")
	runner.assert_eq(_canonical(sim.to_dict()), before, "loaded room retains exact original layout and official reference")
	var wrong_policy: Dictionary = sim.config.duplicate(true)
	wrong_policy.erase("workplaces_version")
	runner.assert_true(not Workplaces.valid_places(sim.places, wrong_policy, null, sim._content.workplaces), "modern metadata without its policy cannot silently become legacy")


func _native_registration(runner: Object) -> void:
	var sim: VillageSimulation = _make(runner)
	if sim == null:
		return
	runner.assert_true(sim.submit_action("player", "deliver_wood"), "original labour still begins using real source material")
	_finish_native(sim, "player", runner)
	runner.assert_true(not sim.actors.player.receipts.is_empty(), "completed labour leaves its original evidence")
	var credit: int = sim.institutions.balance("sect", "player")
	var receipt_count: int = sim.actors.player.receipts.size()
	runner.assert_true(not sim.report_work("player"), "a nearby but away-from-desk registrar cannot post public records")
	runner.assert_eq(sim.institutions.balance("sect", "player"), credit, "off-duty refusal creates no credit")
	runner.assert_eq(sim.actors.player.receipts.size(), receipt_count, "off-duty refusal preserves evidence for later")
	sim.set_actor_cell("chen_shouzhuo", SimRouteTravel.cell(sim.places.records.cell))
	runner.assert_true(Workplaces.assessment(sim, "chen_shouzhuo", "record").ok, "same incumbent can use the institution's existing official register")
	runner.assert_true(not Workplaces.assessment(sim, "shi_tou", "record").ok, "desk and public register do not grant an unappointed person authority")
	runner.assert_true(sim.report_work("player"), "native labour can be registered through the real staffed room")
	var registered: int = sim.institutions.balance("sect", "player")
	runner.assert_true(registered > credit, "only validated completed work adds contribution")
	sim.report_work("player")
	runner.assert_eq(sim.institutions.balance("sect", "player"), registered, "returning to the desk cannot register evidence twice")
	runner.assert_true(sim.institutions.appoint("sect", "registrar", "shi_tou"), "the existing institutional appointment changes the officer")
	sim.set_actor_cell("shi_tou", SimRouteTravel.cell(sim.places.records.cell))
	runner.assert_true(not Workplaces.assessment(sim, "chen_shouzhuo", "record").ok, "old desk user loses record authority after office changes")
	runner.assert_true(Workplaces.assessment(sim, "shi_tou", "record").ok, "successor uses the same institution record without reseeding balances")
	runner.assert_eq(sim.institutions.balance("sect", "player"), registered, "succession preserves official historical entries")


func _return_to_desk_and_resume(runner: Object) -> void:
	var sim: VillageSimulation = _make(runner)
	if sim == null:
		return
	var officer: Dictionary = sim.actors.chen_shouzhuo
	officer.autonomous = true
	officer.hunger = 20.0
	officer.energy = 90.0
	runner.assert_true(sim.advance_to_ms(int(sim.motion_rules.clock.fixed_step_ms)), "native decision boundary advances on the common clock")
	runner.assert_eq(officer.active.get("action", ""), "eat", "food takes priority over office attendance")
	_finish_native(sim, "chen_shouzhuo", runner)
	officer.retry_ms = sim.elapsed_ms + int(sim.motion_rules.clock.fixed_step_ms)
	var prior: Array = officer.position.duplicate()
	runner.assert_true(sim.advance_to_ms(int(officer.retry_ms)), "officer makes a later ordinary decision after eating")
	runner.assert_eq(officer.active.get("action", ""), "workspace_return", "incumbent actually starts a return journey")
	runner.assert_eq(officer.position, prior, "choosing office duty does not teleport the officer")
	var saved: Dictionary = JSON.parse_string(_canonical(sim.to_dict()))
	var restored: VillageSimulation = _make(runner)
	if restored == null:
		return
	runner.assert_true(restored.restore(saved), "in-flight native office return restores with its original route")
	_bind_path(restored, [restored.places])
	var future: int = sim.elapsed_ms + 20 * VillageSimulation.MINUTE_MS
	runner.assert_true(sim.advance_to_ms(future) and restored.advance_to_ms(future), "both native returns finish under the same world time")
	runner.assert_true(Workplaces.at_desk(sim, "chen_shouzhuo"), "real movement eventually reaches the desk")
	runner.assert_true(Workplaces.assessment(sim, "chen_shouzhuo", "record").ok, "finished return makes the original officer available")
	runner.assert_eq(_canonical(restored.to_dict()), _canonical(sim.to_dict()), "save/restore preserves the entire future of the return and daily needs")


func _visitor_redemption(runner: Object) -> void:
	var fixture: RefCounted = ServiceFixture.new()
	var world: RegionalSimulation = fixture._make_world(runner)
	if world == null:
		return
	var areas: Array = []
	for local: VillageSimulation in world.regions.values():
		runner.assert_true(Workplaces.enable_opening(local.config, local.places, local.actors, FlatMap.new(), str(local.config.institution.id), local._content.workplaces), "each original settlement receives its own room and institutional carrier")
		areas.append(local.places)
	for local: VillageSimulation in world.regions.values():
		_bind_path(local, areas)
	world.services.set_navigation(func(from: Vector2i, to: Vector2i) -> Array[Vector2i]: return _path(areas, from, to),
		func(from: Vector2i, step: Vector2i) -> bool: return not _blocked(areas, from + step))
	var sim: VillageSimulation = world.regions.home
	sim.set_actor_cell("player", SimRouteTravel.cell(sim.places.records.cell))
	runner.assert_true(sim.institutions.issue("fixture:workplaces_credit", "sect", "chen_shouzhuo", "player", 4, "fixture:recognized_work"), "visitor scenario starts with explicitly recognized work credit")
	var credit: int = sim.institutions.balance("sect", "player")
	var meals: int = sim.inventory.quantity("kitchen", "meal")
	runner.assert_eq(world.services.issuer("home", "player", "record"), "chen_shouzhuo", "real service issuer finds the staffed official room")
	runner.assert_true(world.services.redeem("player", "home", "meal").ok, "original visitor executor begins stocked redemption")
	sim.set_actor_cell("chen_shouzhuo", SimRouteTravel.cell(sim.places.kitchen.cell))
	world.invalidate_region("home")
	fixture._finish(world, "player", runner)
	runner.assert_eq(sim.institutions.balance("sect", "player"), credit, "leaving during processing prevents an unauthorized debit")
	runner.assert_eq(sim.inventory.quantity("kitchen", "meal"), meals, "failed staffed processing transfers no food")
	sim.set_actor_cell("chen_shouzhuo", SimRouteTravel.cell(sim.places.records.cell))
	world.invalidate_region("home")
	runner.assert_true(world.services.redeem("player", "home", "meal").ok, "same original service can be requested after actual return")
	fixture._finish(world, "player", runner)
	runner.assert_eq(sim.institutions.balance("sect", "player"), credit - 1, "staffed redemption debits once from the original book")
	runner.assert_eq(sim.inventory.quantity("kitchen", "meal"), meals - 1, "staffed redemption consumes original institution stock only")
	runner.assert_eq(sim.inventory.quantity("actor:player", "meal"), 1, "same player's original bag receives the actual reward")
	var committed: String = _canonical(world.to_dict())
	runner.assert_true(world.advance_to_ms(world.elapsed_ms), "revisiting the same shared instant is permitted")
	runner.assert_eq(_canonical(world.to_dict()), committed, "a completed desk service cannot repeat a transfer at the same instant")


func _finish_native(sim: VillageSimulation, actor: String, runner: Object) -> void:
	var stop: int = sim.elapsed_ms + 30 * VillageSimulation.MINUTE_MS
	while not sim.actors[actor].active.is_empty() and sim.elapsed_ms < stop:
		if not sim.advance_to_ms(mini(stop, sim.next_boundary_ms())):
			break
	runner.assert_true(sim.actors[actor].active.is_empty(), "original native action reaches a terminal state")


func _blocked(areas: Array, cell: Vector2i) -> bool:
	for places: Dictionary in areas:
		if Workplaces.blocked(places, cell):
			return true
	return false


func _path(areas: Array, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if _blocked(areas, from) or _blocked(areas, to):
		return result
	var bounds := Rect2i(Vector2i(mini(from.x, to.x) - 8, mini(from.y, to.y) - 8), Vector2i(absi(from.x - to.x) + 17, absi(from.y - to.y) + 17))
	var queue: Array[Vector2i] = [from]
	var previous: Dictionary = {from: from}
	var cursor: int = 0
	while cursor < queue.size() and not previous.has(to):
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for step: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
			var next: Vector2i = cell + step
			if bounds.has_point(next) and not previous.has(next) and not _blocked(areas, next):
				previous[next] = cell
				queue.append(next)
	if not previous.has(to):
		return result
	var current: Vector2i = to
	while current != from:
		result.push_front(current)
		current = previous[current]
	result.push_front(from)
	return result


func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)
