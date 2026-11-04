extends RefCounted
## Construction's transaction boundary: old geometry is visible before a
## successful change, and new geometry only after all dependent roofs settle.
## Real heat accounting is exercised separately by the local-heat suite.


class HeatObserver extends RefCounted:
	var construction: WeakRef
	var cells: Array[Vector2i] = []
	var events: Array[Dictionary] = []


	func before_topology_change(now: int) -> void:
		_record("before", now)


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


class Authority extends RefCounted:
	var elapsed_ms: int = 123456
	var regions: Dictionary = {"home": VillageSimulation.new()}
	# The original motion/road guard reads this explicit empty activity world.
	# Regions still use the real owner type even though no travel is scheduled.
	var settings: Dictionary = {"routes": {}}
	var construction := SimConstruction.new()
	var local_heat := HeatObserver.new()
	var services: RefCounted
	var personal_production: RefCounted
	var capability_practice: RefCounted
	var field_opportunities: RefCounted
	var soul_vessels: RefCounted
	var large_bodies: RefCounted
	var avian_life: RefCounted
	var resting: RefCounted
	var weather: RefCounted


	func invalidate_region(_region: String) -> void:
		pass


func run(runner: Object) -> void:
	_door_commit(runner)
	_rejected_changes(runner)
	_collapsing_roofs(runner)
	_nonthermal_reindex(runner)
	print("SCENARIO heat topology: actual construction transactions bracket old/new geometry, rejected changes stay silent, dependent roof collapse commits once, and reindex has no heat side effects")


func _world(runner: Object) -> Authority:
	var result := Authority.new()
	var village: VillageSimulation = result.regions.home
	village.actors = {"builder": {"cell": [90, 90], "position": [0.0, 0.0], "alive": true,
		"active": {}, "autonomous": false, "goal": "", "retry_ms": 0}}
	village.set_actor_cell("builder", Vector2i(90, 90))
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/construction.json"))
	runner.assert_true(result.construction.initialize(result, rules), "topology fixture uses the real construction rules")
	result.local_heat.construction = weakref(result.construction)
	result.construction.sites.sect_yard = {"origin": [100, 100]}
	return result


func _project(runner: Object, authority: Authority, type: String, cell: Vector2i, funded: bool = true) -> String:
	var domain: SimConstruction = authority.construction
	var id: String = "construction:%d" % domain.next_project
	domain.next_project += 1
	var stock: Dictionary = {"wood": int(domain.definitions.types[type].amount)} if funded else {}
	runner.assert_true(authority.regions.home.inventory.create_container(id, stock), "a real delivered material container exists for the construction transaction")
	domain.projects[id] = {"site": "sect_yard", "type": type, "cell": [cell.x, cell.y],
		"state": "blueprint", "open": false, "created_by": "builder", "created_ms": 0,
		"completed_ms": 0, "removed_ms": 0, "work_ms": 0,
		"material_cell": [cell.x, cell.y + 1], "carrier": "", "delivered": true, "line": ""}
	domain._reindex()
	return id


func _commit(authority: Authority, id: String, kind: String) -> void:
	var cell: Vector2i = SimRouteTravel.cell(authority.construction.projects[id].cell)
	# Invoke the ordinary completion path after its timed work has ended. This
	# suite tests geometry/cost commit ordering, not path travel or labor time.
	authority.construction._complete({"id": id + ":job:" + kind, "project": id,
		"actor": "builder", "kind": kind, "stand": [cell.x, cell.y + 1],
		"previous_autonomous": false})


func _door_commit(runner: Object) -> void:
	var authority: Authority = _world(runner)
	var cell := Vector2i(101, 101)
	authority.local_heat.cells = [cell]
	var id: String = _project(runner, authority, "wood_door", cell)
	runner.assert_true(not authority.construction.thermal_barrier(cell), "an unbuilt door is not a physical thermal barrier")
	_commit(authority, id, "build")
	runner.assert_eq(authority.regions.home.inventory.quantity(id, "wood"), 0, "the original stock is consumed before the real door becomes geometry")
	runner.assert_eq(authority.local_heat.events.size(), 2, "a successful door completion brackets one geometry change")
	runner.assert_eq(authority.local_heat.events[0].barriers, [false], "before sees the former open cell")
	runner.assert_eq(authority.local_heat.events[1].barriers, [true], "after sees the newly finished closed door")
	authority.local_heat.events.clear()
	authority.elapsed_ms += 2000
	_commit(authority, id, "open")
	runner.assert_eq(authority.local_heat.events[0].barriers, [true], "opening first settles the closed geometry")
	runner.assert_eq(authority.local_heat.events[1].barriers, [false], "opening then exposes a real thermal passage")
	runner.assert_eq(authority.local_heat.events[1].at_ms, authority.elapsed_ms, "thermal topology uses the original committed millisecond")
	authority.local_heat.events.clear()
	authority.elapsed_ms += 2000
	_commit(authority, id, "close")
	runner.assert_eq(authority.local_heat.events[0].barriers, [false], "closing retains the actual old opening until commit")
	runner.assert_eq(authority.local_heat.events[1].barriers, [true], "closing applies the new barrier only after completion")


func _rejected_changes(runner: Object) -> void:
	var authority: Authority = _world(runner)
	var cell := Vector2i(101, 101)
	authority.local_heat.cells = [cell]
	var id: String = _project(runner, authority, "wood_wall", cell, false)
	_commit(authority, id, "build")
	runner.assert_true(authority.local_heat.events.is_empty(), "failed material commit never reports a topology change")
	runner.assert_true(not authority.construction.thermal_barrier(cell), "an unpaid wall remains a blueprint")
	var door: String = _project(runner, authority, "wood_door", Vector2i(103, 101))
	_commit(authority, door, "build")
	_commit(authority, door, "open")
	authority.local_heat.events.clear()
	authority.regions.home.set_actor_cell("builder", Vector2i(103, 101))
	_commit(authority, door, "close")
	runner.assert_true(authority.local_heat.events.is_empty(), "a body obstructing door closure causes no fictitious heat boundary")
	runner.assert_true(not authority.construction.thermal_barrier(Vector2i(103, 101)), "rejected closure preserves the real opening")
	authority.regions.home.set_actor_cell("builder", Vector2i(90, 90))
	var unsupported: String = _project(runner, authority, "wood_roof", Vector2i(106, 104))
	_commit(authority, unsupported, "build")
	runner.assert_true(authority.local_heat.events.is_empty(), "a roof without actual support never reports thermal coverage")
	runner.assert_eq(authority.regions.home.inventory.quantity(unsupported, "wood"), 4, "unsupported roof retains the real unfitted material")


func _collapsing_roofs(runner: Object) -> void:
	var authority: Authority = _world(runner)
	var wall_cell := Vector2i(101, 101)
	var roof_cell := Vector2i(102, 101)
	authority.local_heat.cells = [wall_cell, roof_cell]
	var wall: String = _project(runner, authority, "wood_wall", wall_cell)
	_commit(authority, wall, "build")
	var roof: String = _project(runner, authority, "wood_roof", roof_cell)
	_commit(authority, roof, "build")
	runner.assert_true(authority.construction.thermal_roofed(roof_cell), "only a built and supported roof provides real thermal coverage")
	runner.assert_true(not authority.construction.thermal_barrier(roof_cell), "a roof alone is not a wall or a closed doorway")
	authority.local_heat.events.clear()
	_commit(authority, wall, "demolish")
	var first: Dictionary = authority.local_heat.events.front()
	var last: Dictionary = authority.local_heat.events.back()
	runner.assert_eq(first.barriers, [true, false], "dismantling first sees the original supporting wall")
	runner.assert_eq(first.roofs, [false, true], "dismantling settles the original supported roof before removal")
	runner.assert_eq(last.barriers, [false, false], "the final geometry contains no removed supporting wall")
	runner.assert_eq(last.roofs, [false, false], "the final geometry includes every resulting roof collapse")
	var after_count: int = 0
	for event: Dictionary in authority.local_heat.events:
		if event.kind == "after":
			after_count += 1
	runner.assert_eq(after_count, 1, "dependent collapse publishes one final new topology, rather than intermediate layouts")
	runner.assert_eq(authority.regions.home.inventory.quantity(wall, "wood"), 2, "the wall leaves only its original finite salvage")
	runner.assert_eq(authority.regions.home.inventory.quantity(roof, "wood"), 2, "the collapsed roof also leaves finite salvage without duplicating its old structure")


func _nonthermal_reindex(runner: Object) -> void:
	var authority: Authority = _world(runner)
	var bed: String = _project(runner, authority, "wood_bed", Vector2i(101, 101))
	_commit(authority, bed, "build")
	runner.assert_true(authority.local_heat.events.is_empty(), "finishing a bed does not change air passage or roof coverage")
	authority.construction._reindex()
	authority.construction.set_terrain(func(_cell: Vector2i) -> bool: return true)
	runner.assert_true(authority.local_heat.events.is_empty(), "generic index rebuild and restored geometry binding do not advance or resample heat")
