extends SceneTree
## Short counterexamples for the current kernel, not a historical regression suite.

const World = preload("res://scripts/sim/kernel/world.gd")
const Runner = preload("res://scripts/sim/kernel/runner.gd")
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")
var _errors: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	if not ok:
		_errors += 1
		push_error(message)


func _run() -> void:
	var serial := World.new()
	serial.initialize(512, 0)
	var parallel := World.new()
	parallel.initialize(512, 4)
	for step: int in 120:
		serial.step()
		parallel.step()
	check(serial.stored > 0 and serial.counters().material == serial.initial_material, "No real work or lost materials")
	check(serial.stored == parallel.stored and serial.harvested == parallel.harvested, "Workers changed shared resource effects")
	for index: int in serial.pages.size():
		check(serial.pages[index].positions == parallel.pages[index].positions, "Parallel movement changed the same scenario")
		check(serial.pages[index].elements == parallel.pages[index].elements, "Parallel environment sampling diverged")
	var page: RefCounted = serial.pages[0]
	page.positions[0] = Terrain.center(Terrain.index(Vector2i(170, 170)))
	page.positions[1] = page.positions[0]
	page.health[1] = 20
	check(serial.command({"kind": "heal", "actor": 2}).ok, "Heal rejected")
	check(serial.command({"kind": "attack", "actor": 1, "target": 2}).ok and page.health[1] == 35, "Heal before hit did not survive")
	serial.attack_due[0] = 0
	page.health[1] = 20
	serial.command({"kind": "attack", "actor": 1, "target": 2})
	check(not serial.command({"kind": "heal", "actor": 2}).ok and page.health[1] == 0, "Hit before heal resurrected dead unit")
	var deaths: int = serial.deaths
	serial.kill(2)
	check(serial.deaths == deaths, "Death was committed twice")
	serial.reservations[serial.source_objects[page.source_ids[2]]] = 3
	page.modes[2] = 1
	serial.command({"kind": "stop", "actor": 3})
	check(not serial.reservations.has(serial.source_objects[page.source_ids[2]]), "Cancel leaked a reservation")
	var door: int = Terrain.index(Vector2i(182, 184))
	check(serial.terrain.blocked[door] == 0 and serial.terrain.enclosures[door] == 1, "Door must be walkable and enclose a room")
	serial.terrain.rebuild_rooms()
	check(serial.terrain.room_cells.size() == 50, "Door traversal merged rooms with outside")
	var wall: int = Terrain.index(Vector2i(180, 181))
	check(serial.command({"kind": "build", "actor": 1, "tile": wall, "structure": 0}).ok, "Remove wall failed")
	serial.flush_topology()
	check(serial.terrain.room_cells.size() == 49, "Breach did not update room topology")
	check(serial.command({"kind": "build", "actor": 1, "tile": wall, "structure": 1}).ok, "Wall repair rejected")
	serial.flush_topology()
	check(serial.terrain.room_cells.size() == 50, "Wall repair did not restore room")
	check(serial.lanes[0].graph.is_point_solid(Terrain.cell(wall)), "Native navigation did not get new blocker")
	var tides: PackedInt32Array = serial.environment.tides.duplicate()
	serial.environment.update(59000, serial.pages)
	check(tides == serial.environment.tides, "Tides changed before one minute")
	serial.environment.update(60000, serial.pages)
	for amount: int in serial.environment.tides:
		check(amount >= 95 and amount <= 105, "Tide percentage out of range")
	_same_step_causality()
	_inventory_session()
	_build_and_live()
	_nature_cycle()
	preload("res://tests/feature_smoke.gd").run(check)
	preload("res://tests/sight_smoke.gd").run(check)
	await _disk_restart()
	_thread_boundary()
	print("KERNEL_SMOKE errors=", _errors)
	quit(0 if _errors == 0 else 1)


func _inventory_session() -> void:
	var world := World.new()
	world.initialize(4, 0)
	var page: RefCounted = world.pages[0]
	var source: int = world.source_objects[0]
	var chest: int = world.depot_objects[0]
	page.positions[0] = Terrain.center(world.objects.records[source].tile)
	check(world.command({"kind": "take", "actor": 1, "target": source, "amount": 7}).ok, "Take was rejected")
	world.step()
	check(world.objects.amount(1, "wood") == 0, "Timed action completed before work time")
	var snapshot: Dictionary = Persistence.capture(world)
	var loaded: RefCounted = Persistence.candidate(snapshot, 0)
	check(loaded != null, "Valid current-format candidate was rejected")
	if loaded == null:
		return
	for step: int in 8:
		world.step()
		loaded.step()
	check(world.objects.amount(1, "wood") == 7 and loaded.objects.amount(1, "wood") == 7, "In-progress take did not resume once")
	check(world.environment.rng.randi() == loaded.environment.rng.randi(), "Restored random stream lost its seed/state")
	check(snapshot.domains.objects.records[1].inventory.get("wood", 0) == 0, "Captured inventory aliases the live world")
	loaded.command({"kind": "put", "actor": 1, "target": chest, "amount": 7})
	loaded.command({"kind": "stop", "actor": 1})
	check(loaded.objects.amount(1, "wood") == 7 and not loaded.actions.has(1), "Cancel erased committed goods")
	page = loaded.pages[0]
	page.positions[0] = Terrain.center(loaded.objects.records[chest].tile)
	loaded.command({"kind": "put", "actor": 1, "target": chest, "amount": 7})
	for step: int in 8:
		loaded.step()
	check(loaded.objects.amount(1, "wood") == 0 and loaded.objects.amount(chest, "wood") >= 7, "Box did not receive actual goods")
	check(loaded.objects.audit_total("wood") == loaded.initial_material, "Transfer violated inventory conservation")
	var removed: int = 2
	var old_slot: int = loaded.actor_slots[removed]
	check(loaded.remove_actor(removed), "Actor could not be removed")
	var born: int = loaded.spawn_actor(Terrain.index(Vector2i(170, 170)))
	check(born > 4 and loaded.actor_slots[born] == old_slot and not loaded.command({"kind": "heal", "actor": removed}).ok, "Reused body slot reused an old identity")
	var again: RefCounted = Persistence.candidate(Persistence.capture(loaded), 0)
	check(again != null and again.actor_slots.has(born) and not again.actor_slots.has(removed), "Spawn/remove did not survive state restore")
	var invalid: Dictionary = Persistence.capture(loaded)
	invalid.domains.objects.records[chest].inventory.wood = -4
	check(Persistence.candidate(invalid, 0) == null and loaded.objects.amount(chest, "wood") >= 7, "Invalid load damaged the live session")


func _disk_restart() -> void:
	var path: String = "user://kernel-smoke-session.reol"
	var first := Runner.new()
	first.control(true, 1)
	first.start(4, 0, 1)
	var deadline: int = Time.get_ticks_usec() + 2000000
	var frame: RefCounted
	while frame == null and Time.get_ticks_usec() < deadline:
		await process_frame
		frame = first.poll().frame
	if frame == null:
		check(false, "Save test runner never started")
		first.close()
		return
	for attempt: int in 4:
		var saved_seq: int = first.send({"kind": "save", "path": path})
		var receipts: Array = []
		while receipts.is_empty() and Time.get_ticks_usec() < deadline:
			await process_frame
			receipts = first.poll().receipts
		check(receipts.size() == 1 and receipts[0].seq == saved_seq and receipts[0].ok, "Repeated save did not complete on disk")
	first.close()
	var second := Runner.new()
	second.control(true, 1)
	second.start(2, 0, 1)
	second.send({"kind": "load", "path": path})
	var loaded: bool = false
	deadline = Time.get_ticks_usec() + 2000000
	while not loaded and Time.get_ticks_usec() < deadline:
		await process_frame
		var result: Dictionary = second.poll()
		for receipt: Dictionary in result.receipts:
			loaded = receipt.ok and receipt.reason == "loaded"
		if loaded:
			check(result.frame.counters.actors == 4 and result.frame.paused, "New runner did not adopt saved population")
	second.close()
	check(loaded, "A fresh runner could not resume the disk save")


func _build_and_live() -> void:
	var world := World.new()
	world.initialize(1, 0)
	world.objects.transfer(world.source_objects[0], 1, "wood", 30)
	world._sync_inventory(1)
	var tile: int = Terrain.index(Vector2i(160, 170))
	var page: RefCounted = world.pages[0]
	page.positions[0] = Terrain.center(tile - 1)
	check(world.command({"kind": "construct", "definition": "long_bed", "tile": tile}).ok, "Multicell blueprint rejected")
	var target: int = world.actions[1].target
	world.objects.records[target].remaining_ms = 500
	for step: int in 4:
		world.step()
	world.command({"kind": "stop", "actor": 1})
	var remaining: int = world.objects.records[target].remaining_ms
	check(remaining > 0 and remaining < 500 and world.objects.amount(target, "wood") == 8, "Interrupted construction lost material or paid work")
	check(world.command({"kind": "continue_build", "target": target}).ok, "Construction could not resume")
	for step: int in 12:
		world.step()
	check(world.objects.records[target].kind == "bed" and world.objects.by_tile[tile + Terrain.SIZE].has(target), "Multicell fixture did not complete")
	check(world.objects.audit_total("wood") == world.initial_material, "Structural material disappeared")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(world), 0)
	check(restored != null and restored.objects.by_tile[tile + Terrain.SIZE].has(target), "Multicell fixture did not survive loading")
	page.energy[0] = 500
	check(world.command({"kind": "rest", "target": target}).ok, "Bed cannot be used")
	for step: int in 44:
		world.step()
	check(page.energy[0] > 2000, "Bed did not restore real energy")
	world.facilities.demolish(world, target)
	world.flush_topology()
	check(not world.objects.records.has(target) and world.objects.audit_total("wood") == world.initial_material, "Demolition lost invested material")
	var stove: int = world.objects.by_tile[Terrain.index(Vector2i(174, 185))][0]
	world.objects.add(1, "grain", 2)
	world.objects.add(1, "water", 1)
	page.positions[0] = Terrain.center(world.facilities.interaction_tile(world, stove))
	var meals: int = world.objects.amount(stove, "meal")
	var grain: int = world.objects.amount(1, "grain")
	check(world.command({"kind": "cook", "target": stove}).ok, "Cooking rejected")
	for step: int in 84:
		world.step()
	check(world.objects.amount(stove, "meal") == meals + 3 and world.objects.amount(1, "grain") == grain - 2, "Cooking did not consume real ingredients once")
	page.hunger[0] = 500
	world.command({"kind": "eat", "target": stove})
	for step: int in 24:
		world.step()
	check(page.hunger[0] > 3000 and world.objects.amount(stove, "meal") == meals + 2, "Eating did not consume real food")


func _nature_cycle() -> void:
	var w := World.new()
	w.initialize(1, 0)
	var tile: int = Terrain.index(Vector2i(155, 160))
	check(not w.nature.can_plant(w, "lotus", tile).ok, "Lotus accepted dry soil")
	var planter: int = w.objects.by_tile[Terrain.index(Vector2i(173, 182))][0]
	check(w.nature.can_plant(w, "perennial_herb", w.objects.records[planter].tile).ok, "Planter rejected independent plant")
	var id: int = w.nature.create(w, "fire_herb", tile)
	var rec: Dictionary = w.objects.records[id]
	rec.growth_ms = int(w.nature.definitions.fire_herb.mature_ms) - 1000
	w.nature.evaluate(w, id, 2000)
	check(rec.stage == 2 and rec.sources.size() == 2, "Maturing herb did not register its explicit sources")
	var values := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	w.environment.sample_raw(tile, values, 0)
	check(values[5] >= 45, "Fire herb produced no fire influence")
	var other: int = w.environment.add_source(tile + 1, 5, 60)
	w.nature.remove(w, id)
	w.environment.sample_raw(tile, values, 0)
	check(values[5] > 0 and values[5] < 60, "Removing max source erased overlapping live source")
	w.environment.release_source(other)
	var tree: int = w.nature.create(w, "old_tree", tile)
	w.objects.records[tree].stage = 2
	w.nature._sync(w, tree)
	var before: int = w.objects.total("wood")
	check(w.nature.finish(w, 1, {"kind": "cut", "target": tree}, 0) == "completed", "Tree cutting failed")
	check(w.objects.records[tree].stage == 3 and w.objects.total("wood") == before + 8 and w.objects.audit_total("wood") == w.objects.total("wood"), "Tree stump/physical products duplicated or disappeared")
	w.flush_topology()
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null and restored.objects.records[tree].stage == 3, "Plant state failed current-format restore")


func _same_step_causality() -> void:
	var world := World.new()
	world.initialize(3, 0)
	var page: RefCounted = world.pages[0]
	var source: int = page.source_ids[1]
	var tile: int = world.terrain.resources[source]
	page.positions[1] = Terrain.center(tile)
	page.health[1] = 1
	page.body_heat[1] = 500.0
	page.modes[1] = 1 # HARVEST due before the end-of-step thermal effect.
	page.due_ms[1] = 960
	world.reservations[world.source_objects[source]] = 2
	page.source_ids[2] = source
	page.positions[2] = Terrain.center(tile) - Vector2(0.1, 0)
	page.move_to(2, tile, 0)
	world.elapsed_ms = 950
	var before: int = world.objects.amount(world.source_objects[source], "wood")
	world.step()
	check(page.health[1] == 0 and page.cargo[1] == 1 and world.objects.amount(world.source_objects[source], "wood") == before - 1, "End-of-step death erased an earlier harvest")
	check(world.reservations[world.source_objects[source]] == 3, "Earlier harvest did not release reservation before another arrival")
	check(world.environment.mobile_cells[0] == -1, "Dead source was not removed")
	world.objects.transfer(world.source_objects[0], 1, "wood", 1)
	world._sync_inventory(1)
	world.command({"kind": "work", "actor": 1})
	check(world.actions.get(1, {}).get("kind", "") == "put", "Restarted work ignored cargo that must be delivered")
	var old: float = world.environment.room_temperature[0]
	world.environment.room_temperature[0] = 67.0
	world.command({"kind": "build", "actor": 1, "tile": Terrain.index(Vector2i(150, 150)), "structure": 1})
	world.flush_topology()
	var room: int = world.terrain.rooms[Terrain.index(Vector2i(181, 181))]
	check(absf(world.environment.room_temperature[room] - 67.0) < 0.001, "Unrelated construction erased room heat history")
	world.environment.room_temperature[room] = old
	var unique: Dictionary = {}
	for item: int in world.terrain.resources:
		unique[item] = true
	check(unique.size() == world.terrain.resources.size(), "Distinct resource fixtures overlap")


func _thread_boundary() -> void:
	var runner := Runner.new()
	check(runner.start(100, 4, 4.0) == OK, "Runner did not start")
	var limit: int = Time.get_ticks_usec() + 2000000
	var frame: RefCounted
	while frame == null and Time.get_ticks_usec() < limit:
		OS.delay_msec(5)
		frame = runner.poll().frame
	if frame == null:
		check(false, "Runner did not publish initial values")
		runner.close()
		return
	var held: RefCounted = frame
	var held_positions: PackedVector2Array = held.positions.duplicate()
	var held_time: int = held.world_ms
	OS.delay_msec(220) # No host frame or polling: simulation must continue itself.
	frame = runner.poll().frame
	check(frame.world_ms - held_time >= 650, "Simulation waits for display polling")
	check(held.positions == held_positions and held.world_ms == held_time, "Publishing overwrote a retained old frame")
	runner.control(true, 4.0)
	OS.delay_msec(30)
	frame = runner.poll().frame
	check(frame.paused, "Pause was not adopted at a boundary")
	var paused_at: int = frame.world_ms
	var command: int = runner.send({"kind": "stop", "actor": 1})
	OS.delay_msec(40)
	var result: Dictionary = runner.poll()
	check(result.frame.world_ms == paused_at, "Paused clock continued advancing")
	check(result.receipts.size() == 1 and result.receipts[0].seq == command, "Paused command receipt missing or duplicated")
	check(runner.poll().receipts.is_empty(), "Receipt replayed after consumption")
	var admitted: int = runner.send({"kind": "stop", "actor": 1})
	runner.close()
	var closing: Dictionary = runner.poll()
	check(closing.receipts.size() == 1 and closing.receipts[0].seq == admitted, "Shutdown silently lost an admitted command")
