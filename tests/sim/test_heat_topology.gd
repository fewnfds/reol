extends RefCounted
## Construction's transaction boundary: old geometry is visible before a
## successful change, and new geometry only after all dependent roofs settle.
## Real heat accounting is exercised separately by the local-heat suite.


class HeatObserver extends RefCounted:
	var construction: WeakRef
	var cells: Array[Vector2i] = []
	var events: Array[Dictionary] = []
	var preflights: Array[Dictionary] = []
	var allow: bool = true
	var allow_before: bool = true
	var reject_cell: Variant = null


	func can_change_topology(now: int, changed_cells: Array[Vector2i]) -> bool:
		var domain: SimConstruction = construction.get_ref()
		var barriers: Array[bool] = []
		var roofs: Array[bool] = []
		for cell: Vector2i in cells:
			barriers.append(domain.thermal_barrier(cell))
			roofs.append(domain.thermal_roofed(cell))
		preflights.append({"at_ms": now, "cells": changed_cells.duplicate(), "barriers": barriers, "roofs": roofs})
		return allow and (reject_cell == null or not changed_cells.has(reject_cell))


	func before_topology_change(now: int) -> bool:
		_record("before", now)
		return allow_before


	func after_topology_change(now: int) -> void:
		_record("after", now)


	func _record(kind: String, now: int) -> void:
		var domain: SimConstruction = construction.get_ref()
		var barriers: Array[bool] = []
		var roofs: Array[bool] = []
		for cell: Vector2i in cells:
			barriers.append(domain.thermal_barrier(cell))
			roofs.append(domain.thermal_roofed(cell))
		events.append({"kind": kind, "at_ms": now, "barriers": barriers, "roofs": roofs})


class Authority extends RegionalSimulation:
	# Use the real authority type required by the shared execution contract,
	# with only this transaction's original region/ledger and thermal observer.
	# No full world, opening content or unrelated process is assembled here.
	var structure_notifications: Array = []
	var outcomes: Array[Dictionary] = []

	func _init() -> void:
		elapsed_ms = 123456
		regions = {"home": VillageSimulation.new()}
		settings = {"routes": {}}
		construction = SimConstruction.new()
		environment_fields = HeatObserver.new()
		action_finished.connect(on_action_finished)


	func on_action_finished(outcome: Dictionary) -> void:
		outcomes.append(outcome.duplicate(true))


	func invalidate_region(_region: String, _actor_id: String = "") -> void:
		pass

	func on_structures_changed(cells: Array[Vector2i]) -> void:
		structure_notifications.append(cells.duplicate())


func run(runner: Object) -> void:
	_door_commit(runner)
	_rejected_changes(runner)
	_collapsing_roofs(runner)
	_nonthermal_reindex(runner)
	_rejected_build_and_retry(runner)
	_rejected_door_and_retry(runner)
	_rejected_roof_cascade_and_retry(runner)
	_invalid_inventory_preflight(runner)
	print("SCENARIO heat topology: actual construction transactions bracket old/new geometry, rejected changes stay silent, dependent roof collapse commits once, and reindex has no heat side effects")


func _world(runner: Object) -> Authority:
	var result := Authority.new()
	var village: VillageSimulation = result.regions.home
	village.actors = {"builder": {"cell": [90, 90], "position": [0.0, 0.0], "alive": true,
		"active": {}, "autonomous": false, "goal": "", "retry_ms": 0}}
	village.set_actor_cell("builder", Vector2i(90, 90))
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/construction.json"))
	rules["site"] = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/construction.json")).site
	runner.assert_true(result.construction.initialize(result, rules), "topology fixture uses the real construction rules")
	result.environment_fields.construction = weakref(result.construction)
	result.construction.structures_changed.connect(result.on_structures_changed)
	result.construction.sites.sect_yard = {"origin": [100, 100], "size": [7, 5]}
	return result


func _project(runner: Object, authority: Authority, type: String, cell: Vector2i, funded: bool = true) -> String:
	var domain: SimConstruction = authority.construction
	var id: String = "construction:%d" % domain.next_project
	domain.next_project += 1
	var stock: Dictionary = {"wood": int(domain.definitions.types[type].amount)} if funded else {}
	runner.assert_true(authority.regions.home.inventory.create_container(id, stock), "a real delivered material container exists for the construction transaction")
	domain.projects[id] = {"site": "sect_yard", "type": type, "cell": [cell.x, cell.y],
		"rotation": 0, "hp": 0, "state": "blueprint", "open": false, "created_by": "builder", "created_ms": 0,
		"completed_ms": 0, "removed_ms": 0, "work_ms": 0,
		"material_cell": [cell.x, cell.y + 1], "carrier": "", "delivered": true, "line": ""}
	domain._reindex()
	return id


func _commit(authority: Authority, id: String, kind: String, previous_autonomous: bool = false) -> void:
	var cell: Vector2i = SimRouteTravel.cell(authority.construction.projects[id].cell)
	# Invoke the ordinary completion path after its timed work has ended. This
	# suite tests geometry/cost commit ordering, not path travel or labor time.
	var job: Dictionary = {"id": id + ":job:" + kind, "project": id,
		"actor": "builder", "kind": kind, "stand": [cell.x, cell.y + 1],
		"phase": "work", "work_started_ms": authority.elapsed_ms, "started_ms": authority.elapsed_ms - 1, "due_ms": authority.elapsed_ms,
		"previous_autonomous": previous_autonomous}
	authority.construction.active.builder = job
	authority.regions.home.actors.builder.autonomous = false
	authority.construction._complete(job)


func _door_commit(runner: Object) -> void:
	var authority: Authority = _world(runner)
	var cell := Vector2i(101, 101)
	authority.environment_fields.cells.assign([cell])
	var id: String = _project(runner, authority, "wood_door", cell)
	runner.assert_true(not authority.construction.thermal_barrier(cell), "an unbuilt door is not a physical thermal barrier")
	_commit(authority, id, "build")
	runner.assert_eq(authority.regions.home.inventory.quantity(id, "wood"), 0, "the original stock is consumed before the real door becomes geometry")
	runner.assert_true(authority.outcomes.back().domain == "construction" and authority.outcomes.back().status == "completed" and not authority.construction.active.has("builder"), "completed topology commits report the common outcome after original worker release")
	runner.assert_eq(authority.environment_fields.events.size(), 2, "a successful door completion brackets one geometry change")
	runner.assert_eq(authority.environment_fields.events[0].barriers, [false], "before sees the former open cell")
	runner.assert_eq(authority.environment_fields.events[1].barriers, [true], "after sees the newly finished closed door")
	authority.environment_fields.events.clear()
	authority.elapsed_ms += 2000
	_commit(authority, id, "open")
	runner.assert_eq(authority.environment_fields.events[0].barriers, [true], "opening first settles the closed geometry")
	runner.assert_eq(authority.environment_fields.events[1].barriers, [false], "opening then exposes a real thermal passage")
	runner.assert_eq(authority.environment_fields.events[1].at_ms, authority.elapsed_ms, "thermal topology uses the original committed millisecond")
	authority.environment_fields.events.clear()
	authority.elapsed_ms += 2000
	_commit(authority, id, "close")
	runner.assert_eq(authority.environment_fields.events[0].barriers, [false], "closing retains the actual old opening until commit")
	runner.assert_eq(authority.environment_fields.events[1].barriers, [true], "closing applies the new barrier only after completion")


func _rejected_changes(runner: Object) -> void:
	var authority: Authority = _world(runner)
	var cell := Vector2i(101, 101)
	authority.environment_fields.cells.assign([cell])
	var id: String = _project(runner, authority, "wood_wall", cell, false)
	var original_stock: Dictionary = authority.regions.home.inventory.to_dict()
	_commit(authority, id, "build", true)
	runner.assert_true(authority.environment_fields.events.is_empty(), "failed material commit never reports a topology change")
	runner.assert_true(authority.structure_notifications.is_empty(), "an unpaid blueprint publishes no completed structure change")
	runner.assert_eq(authority.regions.home.inventory.to_dict(), original_stock, "failed material commit does not consume or create a ledger operation")
	runner.assert_true(not authority.construction.thermal_barrier(cell), "an unpaid wall remains a blueprint")
	runner.assert_eq(int(authority.construction.projects[id].work_ms), int(authority.construction.definitions.types.wood_wall.work_ms), "an unpaid completed-work attempt retains the already finished labor")
	runner.assert_true(not authority.construction.active.has("builder") and bool(authority.regions.home.actors.builder.autonomous), "an unpaid completion releases the worker to its previous autonomy")
	var door: String = _project(runner, authority, "wood_door", Vector2i(103, 101))
	_commit(authority, door, "build")
	_commit(authority, door, "open")
	authority.environment_fields.events.clear()
	authority.environment_fields.preflights.clear()
	authority.structure_notifications.clear()
	authority.regions.home.set_actor_cell("builder", Vector2i(103, 101))
	_commit(authority, door, "close")
	runner.assert_true(authority.environment_fields.events.is_empty(), "a body obstructing door closure causes no fictitious heat boundary")
	runner.assert_true(authority.structure_notifications.is_empty(), "occupied closure publishes no structure notification")
	runner.assert_true(not authority.construction.thermal_barrier(Vector2i(103, 101)), "rejected closure preserves the real opening")
	authority.regions.home.set_actor_cell("builder", Vector2i(90, 90))
	var unsupported: String = _project(runner, authority, "wood_roof", Vector2i(106, 104))
	_commit(authority, unsupported, "build")
	runner.assert_true(authority.environment_fields.events.is_empty(), "a roof without actual support never reports thermal coverage")
	runner.assert_true(authority.structure_notifications.is_empty(), "unsupported roof work publishes no structure notification")
	runner.assert_eq(authority.regions.home.inventory.quantity(unsupported, "wood"), 4, "unsupported roof retains the real unfitted material")


func _collapsing_roofs(runner: Object) -> void:
	var authority: Authority = _world(runner)
	var wall_cell := Vector2i(101, 101)
	var roof_cell := Vector2i(102, 101)
	authority.environment_fields.cells.assign([wall_cell, roof_cell])
	var wall: String = _project(runner, authority, "wood_wall", wall_cell)
	_commit(authority, wall, "build")
	var roof: String = _project(runner, authority, "wood_roof", roof_cell)
	_commit(authority, roof, "build")
	runner.assert_true(authority.construction.thermal_roofed(roof_cell), "only a built and supported roof provides real thermal coverage")
	runner.assert_true(not authority.construction.thermal_barrier(roof_cell), "a roof alone is not a wall or a closed doorway")
	authority.environment_fields.events.clear()
	_commit(authority, wall, "demolish")
	var first: Dictionary = authority.environment_fields.events.front()
	var last: Dictionary = authority.environment_fields.events.back()
	runner.assert_eq(first.barriers, [true, false], "dismantling first sees the original supporting wall")
	runner.assert_eq(first.roofs, [false, true], "dismantling settles the original supported roof before removal")
	runner.assert_eq(last.barriers, [false, false], "the final geometry contains no removed supporting wall")
	runner.assert_eq(last.roofs, [false, false], "the final geometry includes every resulting roof collapse")
	var after_count: int = 0
	for event: Dictionary in authority.environment_fields.events:
		if event.kind == "after":
			after_count += 1
	runner.assert_eq(after_count, 1, "dependent collapse publishes one final new topology, rather than intermediate layouts")
	runner.assert_eq(authority.regions.home.inventory.quantity(wall, "wood"), 2, "the wall leaves only its original finite salvage")
	runner.assert_eq(authority.regions.home.inventory.quantity(roof, "wood"), 2, "the collapsed roof also leaves finite salvage without duplicating its old structure")


func _nonthermal_reindex(runner: Object) -> void:
	var authority: Authority = _world(runner)
	var bed: String = _project(runner, authority, "wood_bed", Vector2i(101, 101))
	_commit(authority, bed, "build")
	runner.assert_true(authority.environment_fields.events.is_empty(), "finishing a bed does not change air passage or roof coverage")
	authority.construction._reindex()
	authority.construction.set_terrain(func(_cell: Vector2i) -> bool: return true)
	runner.assert_true(authority.environment_fields.events.is_empty(), "generic index rebuild and restored geometry binding do not advance or resample heat")


func _rejected_build_and_retry(runner: Object) -> void:
	for type: String in ["wood_wall", "wood_roof"]:
		var authority: Authority = _world(runner)
		var cell := Vector2i(101, 101)
		authority.environment_fields.cells.assign([cell])
		if type == "wood_roof":
			var support: String = _project(runner, authority, "wood_wall", Vector2i(100, 101))
			_commit(authority, support, "build")
			runner.assert_eq(authority.construction.projects[support].state, "built", "roof rejection fixture has an actual supporting wall")
		var id: String = _project(runner, authority, type, cell)
		_clear_observers(authority)
		var inventory_before: Dictionary = authority.regions.home.inventory.to_dict()
		var geometry_before: Dictionary = _physical_projects(authority, [id])
		authority.environment_fields.allow = false
		_commit(authority, id, "build", true)
		runner.assert_eq(authority.environment_fields.preflights.size(), 1, "completed " + type + " asks for one pure topology preflight")
		if not authority.environment_fields.preflights.is_empty():
			runner.assert_eq(authority.environment_fields.preflights[0].cells, [cell], "build preflight identifies the actual changed cell")
			runner.assert_eq(authority.environment_fields.preflights[0].barriers, [false], "build preflight observes the old non-wall geometry")
			runner.assert_eq(authority.environment_fields.preflights[0].roofs, [false], "build preflight observes the old unroofed geometry")
		_assert_rejected_transaction(runner, authority, [id], geometry_before, inventory_before, type + " preflight", false)
		runner.assert_eq(int(authority.construction.projects[id].work_ms), int(authority.construction.definitions.types[type].work_ms), "rejected " + type + " retains its completed work time")
		runner.assert_true(not authority.regions.home.inventory.operations.has(id + ":build"), "rejected " + type + " does not record a material consumption")
		authority.environment_fields.allow = true
		_clear_observers(authority)
		_commit(authority, id, "build")
		runner.assert_eq(authority.construction.projects[id].state, "built", "cleared " + type + " preflight permits the original blueprint to finish")
		runner.assert_eq(authority.regions.home.inventory.quantity(id, "wood"), 0, "the successful retry consumes the original delivered material once")
		runner.assert_true(authority.regions.home.inventory.operations.has(id + ":build"), "the successful retry records the one original build debit")
		runner.assert_eq(authority.regions.home.inventory.operations.size(), inventory_before.operations.size() + 1, "the successful retry creates exactly one build operation")
		runner.assert_eq(authority.environment_fields.events.size(), 2, "successful retry brackets geometry exactly once")
		runner.assert_eq(authority.structure_notifications.size(), 1, "successful retry publishes exactly one completed structure change")
		if authority.environment_fields.events.size() == 2:
			runner.assert_eq(authority.environment_fields.events[0].roofs, [false], "before retains the original uncovered cell")
			runner.assert_eq(authority.environment_fields.events[1].roofs, [type == "wood_roof"], "after exposes the completed roof only for a roof build")
			runner.assert_eq(authority.environment_fields.events[1].barriers, [type == "wood_wall"], "after exposes the completed barrier only for a wall build")

	# A successful pure preflight does not make a failed old-geometry settlement
	# safe to commit. The observer records this attempt separately from after.
	var blocked: Authority = _world(runner)
	var blocked_cell := Vector2i(101, 101)
	blocked.environment_fields.cells.assign([blocked_cell])
	var blocked_id: String = _project(runner, blocked, "wood_wall", blocked_cell)
	var blocked_inventory: Dictionary = blocked.regions.home.inventory.to_dict()
	var blocked_geometry: Dictionary = _physical_projects(blocked, [blocked_id])
	blocked.environment_fields.allow_before = false
	_commit(blocked, blocked_id, "build", true)
	runner.assert_eq(blocked.environment_fields.preflights.size(), 1, "a settlement refusal follows the accepted pure preflight")
	_assert_rejected_transaction(runner, blocked, [blocked_id], blocked_geometry, blocked_inventory, "failed before-settlement", true)
	runner.assert_eq(int(blocked.construction.projects[blocked_id].work_ms), int(blocked.construction.definitions.types.wood_wall.work_ms), "a failed settlement retains completed build labor")
	blocked.environment_fields.allow_before = true
	_clear_observers(blocked)
	_commit(blocked, blocked_id, "build")
	runner.assert_eq(blocked.construction.projects[blocked_id].state, "built", "a later successful settlement can finish the same prepared wall")
	runner.assert_eq(blocked.regions.home.inventory.quantity(blocked_id, "wood"), 0, "the corrected settlement debits delivered material only on success")
	runner.assert_eq(blocked.environment_fields.events.size(), 2, "corrected settlement creates one before/after pair")


func _rejected_door_and_retry(runner: Object) -> void:
	var authority: Authority = _world(runner)
	var cell := Vector2i(101, 101)
	authority.environment_fields.cells.assign([cell])
	var door: String = _project(runner, authority, "wood_door", cell)
	_commit(authority, door, "build")
	for verb: String in ["open", "close"]:
		_clear_observers(authority)
		var inventory_before: Dictionary = authority.regions.home.inventory.to_dict()
		var geometry_before: Dictionary = _physical_projects(authority, [door])
		var old_open: bool = bool(authority.construction.projects[door].open)
		authority.environment_fields.allow = false
		_commit(authority, door, verb, true)
		runner.assert_eq(authority.environment_fields.preflights.size(), 1, verb + " preflight examines the physical doorway")
		if not authority.environment_fields.preflights.is_empty():
			runner.assert_eq(authority.environment_fields.preflights[0].cells, [cell], verb + " preflight names the door's cell")
			runner.assert_eq(authority.environment_fields.preflights[0].barriers, [not old_open], verb + " preflight sees the previous door state")
		_assert_rejected_transaction(runner, authority, [door], geometry_before, inventory_before, "door " + verb, false)
		runner.assert_eq(bool(authority.construction.projects[door].open), old_open, "refused " + verb + " retains the old opening")
		authority.environment_fields.allow = true
		_clear_observers(authority)
		_commit(authority, door, verb)
		runner.assert_eq(bool(authority.construction.projects[door].open), verb == "open", "retry commits the requested real door state")
		runner.assert_eq(authority.regions.home.inventory.to_dict(), inventory_before, "opening or closing does not create a material operation")
		runner.assert_eq(authority.environment_fields.events.size(), 2, "accepted door operation has one before/after pair")
		runner.assert_eq(authority.structure_notifications.size(), 1, "accepted door operation publishes once")


func _two_roof_fixture(runner: Object) -> Dictionary:
	var authority: Authority = _world(runner)
	var wall_cell := Vector2i(101, 101)
	var first_cell := Vector2i(102, 101)
	var second_cell := Vector2i(101, 102)
	authority.environment_fields.cells.assign([wall_cell, first_cell, second_cell])
	var wall: String = _project(runner, authority, "wood_wall", wall_cell)
	_commit(authority, wall, "build")
	var first: String = _project(runner, authority, "wood_roof", first_cell)
	_commit(authority, first, "build")
	var second: String = _project(runner, authority, "wood_roof", second_cell)
	_commit(authority, second, "build")
	var ready: bool = authority.construction.projects[wall].state == "built" and authority.construction.projects[first].state == "built" and authority.construction.projects[second].state == "built" and authority.construction.thermal_roofed(first_cell) and authority.construction.thermal_roofed(second_cell)
	runner.assert_true(ready, "one real wall supports both separately funded roofs")
	if not ready:
		return {}
	_clear_observers(authority)
	return {"world": authority, "wall": wall, "first": first, "second": second,
		"wall_cell": wall_cell, "first_cell": first_cell, "second_cell": second_cell}


func _rejected_roof_cascade_and_retry(runner: Object) -> void:
	var fixture: Dictionary = _two_roof_fixture(runner)
	if fixture.is_empty():
		return
	var authority: Authority = fixture.world
	var ids: Array[String] = [fixture.wall, fixture.first, fixture.second]
	var inventory_before: Dictionary = authority.regions.home.inventory.to_dict()
	var geometry_before: Dictionary = _physical_projects(authority, ids)
	authority.environment_fields.reject_cell = fixture.second_cell
	_commit(authority, str(fixture.wall), "demolish", true)
	runner.assert_eq(authority.environment_fields.preflights.size(), 1, "wall and dependent roofs are submitted in one topology preflight")
	if not authority.environment_fields.preflights.is_empty():
		var request: Dictionary = authority.environment_fields.preflights[0]
		runner.assert_eq(request.cells.size(), 3, "the prospective demolition includes the wall and both distinct roof cells")
		for cell: Vector2i in [fixture.wall_cell, fixture.first_cell, fixture.second_cell]:
			runner.assert_true(request.cells.has(cell), "the preflight includes every real changed footprint")
		runner.assert_eq(request.barriers, [true, false, false], "the pure preflight sees the still-standing original wall")
		runner.assert_eq(request.roofs, [false, true, true], "the pure preflight sees both still-supported original roofs")
	_assert_rejected_transaction(runner, authority, ids, geometry_before, inventory_before, "dependent roof refusal", false)
	for id: String in ids:
		runner.assert_true(not authority.regions.home.inventory.containers.has(id + ":salvage") and not authority.regions.home.inventory.operations.has(id + ":salvage"), "refused cascade creates no wall or roof salvage container or receipt")
	authority.environment_fields.reject_cell = null
	_clear_observers(authority)
	_commit(authority, str(fixture.wall), "demolish")
	runner.assert_eq(authority.environment_fields.preflights.size(), 1, "retry preflights the complete changed footprint once")
	runner.assert_eq(authority.environment_fields.events.size(), 2, "successful cascade settles old and new topology exactly once")
	runner.assert_eq(authority.structure_notifications.size(), 1, "successful cascade publishes one combined structure event")
	if authority.environment_fields.events.size() == 2:
		runner.assert_eq(authority.environment_fields.events[0].roofs, [false, true, true], "before retains both supported roofs")
		runner.assert_eq(authority.environment_fields.events[1].roofs, [false, false, false], "after contains neither removed roof")
	for id: String in ids:
		runner.assert_eq(authority.construction.projects[id].state, "removed", "successful cascade removes each original structure once")
		runner.assert_eq(authority.regions.home.inventory.quantity(id, "wood"), 2, "successful cascade releases each structure's single finite salvage batch")
		runner.assert_true(authority.regions.home.inventory.operations.has(id + ":salvage"), "each real removal records its own salvage transaction")
	runner.assert_eq(authority.regions.home.inventory.operations.size(), inventory_before.operations.size() + 3, "retry creates exactly the three wall/roof salvage operations")


func _invalid_inventory_preflight(runner: Object) -> void:
	var fixture: Dictionary = _two_roof_fixture(runner)
	if fixture.is_empty():
		return
	var authority: Authority = fixture.world
	var ids: Array[String] = [fixture.wall, fixture.first, fixture.second]
	var inventory: SimInventory = authority.regions.home.inventory
	var conflict: String = str(fixture.second) + ":salvage"
	runner.assert_true(inventory.create_container(conflict, {"wood": 7}), "fixture supplies a conflicting already-existing roof salvage container")
	var stock_before: Dictionary = inventory.to_dict()
	var geometry_before: Dictionary = _physical_projects(authority, ids)
	_commit(authority, str(fixture.wall), "demolish", true)
	_assert_rejected_transaction(runner, authority, ids, geometry_before, stock_before, "dependent roof salvage conflict", false)
	for id: String in [str(fixture.wall), str(fixture.first)]:
		runner.assert_true(not inventory.containers.has(id + ":salvage") and not inventory.operations.has(id + ":salvage"), "a later roof conflict cannot leave an earlier half-created salvage")
	runner.assert_true(inventory.containers.has(conflict) and inventory.quantity(conflict, "wood") == 7, "the existing conflicting source container is preserved")
	# The conflicting container was deliberately injected by this isolated
	# fixture; remove that setup fault and retry the same prepared transaction.
	inventory.containers.erase(conflict)
	_clear_observers(authority)
	_commit(authority, str(fixture.wall), "demolish")
	for id: String in ids:
		runner.assert_eq(authority.construction.projects[id].state, "removed", "after correcting the fixture conflict, each actual structure can be removed")
		runner.assert_eq(inventory.quantity(id, "wood"), 2, "corrected cascade produces each finite salvage exactly once")
	runner.assert_eq(authority.structure_notifications.size(), 1, "corrected cascade reports one completed structure change")

	# An occupied operation ID is an independent conflict even if no salvage
	# container yet exists; it must not leave one behind during refusal.
	var operation_world: Authority = _world(runner)
	var wall: String = _project(runner, operation_world, "wood_wall", Vector2i(101, 101))
	_commit(operation_world, wall, "build")
	_clear_observers(operation_world)
	var ledger: SimInventory = operation_world.regions.home.inventory
	runner.assert_true(ledger.create_container("other_source", {"wood": 1}) and ledger.create_container("other_target", {}), "operation conflict fixture owns two original containers")
	runner.assert_true(ledger.transfer(wall + ":salvage", "other_source", "other_target", "wood", 1), "another existing operation already occupies this salvage ID")
	var ledger_before: Dictionary = ledger.to_dict()
	var wall_before: Dictionary = _physical_projects(operation_world, [wall])
	_commit(operation_world, wall, "demolish", true)
	_assert_rejected_transaction(runner, operation_world, [wall], wall_before, ledger_before, "salvage operation conflict", false)
	runner.assert_true(not ledger.containers.has(wall + ":salvage"), "occupied operation ID cannot leave a newly created salvage container")


func _physical_projects(authority: Authority, ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for id: String in ids:
		var project: Dictionary = authority.construction.projects[id].duplicate(true)
		# Failed completion may legitimately update its status line and preserve
		# finished build work, but must not change any physical project facts.
		project.erase("line")
		project.erase("work_ms")
		result[id] = project
	return result


func _clear_observers(authority: Authority) -> void:
	authority.environment_fields.events.clear()
	authority.environment_fields.preflights.clear()
	authority.structure_notifications.clear()
	authority.outcomes.clear()


func _assert_rejected_transaction(runner: Object, authority: Authority, ids: Array, geometry_before: Dictionary, inventory_before: Dictionary, label: String, expected_before: bool) -> void:
	runner.assert_eq(_physical_projects(authority, ids), geometry_before, label + " leaves all physical structure facts unchanged")
	runner.assert_eq(authority.regions.home.inventory.to_dict(), inventory_before, label + " leaves materials, containers and operation records unchanged")
	runner.assert_true(authority.structure_notifications.is_empty(), label + " publishes no structure-change signal")
	if expected_before:
		runner.assert_true(authority.environment_fields.events.size() == 1 and authority.environment_fields.events[0].kind == "before", label + " attempts only the old-topology settlement")
	else:
		runner.assert_true(authority.environment_fields.events.is_empty(), label + " has no before/after heat commit")
	runner.assert_true(not authority.construction.active.has("builder") and bool(authority.regions.home.actors.builder.autonomous), label + " releases the worker with its original autonomy")
	runner.assert_true(not authority.outcomes.is_empty() and authority.outcomes.back().status == "failed", label + " reports failure through the shared terminal contract")
