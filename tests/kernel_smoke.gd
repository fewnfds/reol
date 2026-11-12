extends SceneTree
## Short counterexamples for the current kernel, not a historical regression suite.

const World = preload("res://scripts/sim/kernel/world.gd")
const Runner = preload("res://scripts/sim/kernel/runner.gd")
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
var _errors: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	if not ok:
		_errors += 1
		push_error(message)


func _run() -> void:
	var serial := World.new()
	serial.initialize(1000, 0)
	var parallel := World.new()
	parallel.initialize(1000, 4)
	for step: int in 400:
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
	serial.reservations[page.source_ids[2]] = 3
	page.modes[2] = 1
	serial.command({"kind": "stop", "actor": 3})
	check(serial.reservations[page.source_ids[2]] == 0, "Cancel leaked a reservation")
	var door: int = Terrain.index(Vector2i(182, 184))
	check(serial.terrain.blocked[door] == 0 and serial.terrain.enclosures[door] == 1, "Door must be walkable and enclose a room")
	serial.terrain.rebuild_rooms()
	check(serial.terrain.room_cells.size() == 50, "Door traversal merged rooms with outside")
	var wall: int = Terrain.index(Vector2i(180, 181))
	check(serial.command({"kind": "build", "actor": 1, "tile": wall, "structure": 0}).ok, "Remove wall failed")
	check(serial.terrain.room_cells.size() == 49, "Breach did not update room topology")
	check(serial.command({"kind": "build", "actor": 1, "tile": wall, "structure": 1}).ok and serial.terrain.room_cells.size() == 50, "Wall repair did not restore room")
	check(serial.lanes[0].graph.is_point_solid(Terrain.cell(wall)), "Native navigation did not get new blocker")
	var tides: PackedInt32Array = serial.environment.tides.duplicate()
	serial.environment.update(59000, serial.pages)
	check(tides == serial.environment.tides, "Tides changed before one minute")
	serial.environment.update(60000, serial.pages)
	for amount: int in serial.environment.tides:
		check(amount >= 95 and amount <= 105, "Tide percentage out of range")
	_same_step_causality()
	_thread_boundary()
	print("KERNEL_SMOKE errors=", _errors)
	quit(0 if _errors == 0 else 1)


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
	world.reservations[source] = 2
	page.source_ids[2] = source
	page.positions[2] = Terrain.center(tile) - Vector2(0.1, 0)
	page.move_to(2, tile, 0)
	world.elapsed_ms = 950
	var before: int = world.quantities[source]
	world.step()
	check(page.health[1] == 0 and page.cargo[1] == 1 and world.quantities[source] == before - 1, "End-of-step death erased an earlier harvest")
	check(world.reservations[source] == 3, "Earlier harvest did not release reservation before another arrival")
	check(world.environment.mobile_cells[0] == -1, "Dead source was not removed")
	page.cargo[0] = 1
	world.command({"kind": "work", "actor": 1})
	check(page.modes[0] == 2, "Restarted work ignored cargo that must be delivered")
	var old: float = world.environment.room_temperature[0]
	world.environment.room_temperature[0] = 67.0
	world.command({"kind": "build", "actor": 1, "tile": Terrain.index(Vector2i(150, 150)), "structure": 1})
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
