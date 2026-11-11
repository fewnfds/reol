extends SceneTree
## Small checks for current execution primitives. No world/content assembly.

const Kernel = preload("res://scripts/sim/execution/settlement_kernel.gd")
const ActorBatch = preload("res://scripts/sim/actor_advance.gd")
const Inventory = preload("res://scripts/sim/inventory_ledger.gd")
const SUITES: Array[String] = ["settlement", "actor_batch", "inventory", "input", "presentation", "spatial"]

class NavigationReadCheck extends RefCounted:
	var graph := SimGridNavigation.Search.new(16, true)
	var view: SimWorldGeometry.ReadView
	var result: Array[Vector2i] = []
	func run() -> void:
		result = graph.find_path(Vector2i(116, 120), Vector2i(130, 120), view.is_walkable, view.can_step, 4096)


func _spatial() -> bool:
	# Freeze once, change the authoritative terrain, then use the old input on
	# actual workers. It must remain readable but fail adoption as current data.
	var world := RegionalSimulation.new()
	world.bind_map_data(WorldMapData.from_descriptor(WorldMapData.flat_descriptor(17)))
	var patch: Array = []
	for y: int in range(100, 137):
		for x: int in range(100, 137):
			patch.append([x, y, WorldMapData.TERRAIN_GRASS])
	if not bool(world.map_data.apply_terrain_patch(patch).ok):
		return false
	var geometry: SimWorldGeometry = world.geometry_read()
	var view: SimWorldGeometry.ReadView = geometry.capture(Rect2i(100, 100, 37, 37))
	var built: int = int(geometry.work.built_pages)
	var repeated: SimWorldGeometry.ReadView = geometry.capture(view.bounds)
	if not geometry.is_current(view) or geometry.work.built_pages != built or repeated.pages != view.pages:
		return false
	var expected: Array[Vector2i] = SimGridNavigation.find_path(Vector2i(116, 120), Vector2i(130, 120), world.map_data.terrain_is_walkable, world.map_data.terrain_can_step, 16, 4096)
	if expected.is_empty() or not bool(world.map_data.apply_terrain_patch([[130, 120, WorldMapData.TERRAIN_ROCK]]).ok):
		return false
	if geometry.is_current(view) or not view.is_walkable(Vector2i(130, 120)) or geometry.is_walkable(Vector2i(130, 120)) or geometry.work.built_pages != built:
		return false
	var tasks: Array[RefCounted] = []
	for index: int in 2:
		var task := NavigationReadCheck.new()
		task.view = view
		tasks.append(task)
	var batch := SimBatchExecution.new()
	batch.start(tasks, 2)
	batch.finish(true)
	if not batch.parallel or tasks[0].result != expected or tasks[1].result != expected:
		return false
	world._retire_geometry()
	if geometry.is_current(view) or geometry.capture(view.bounds) != null or world.geometry_read().is_current(view):
		return false
	# Equal-distance targets straddle chunk boundaries. The first original row
	# wins even when another worker finishes first; shooter/height filters apply.
	var bodies := SimBodyReadView.new()
	for row: int in 512:
		bodies.ids.append(str(row))
		bodies.points.append(Vector2(200 + row * 4, 0))
		bodies.levels.append(0)
	bodies.points[0] = Vector2(10, 0)
	bodies.points[65] = Vector2(10, 0)
	var starts := PackedVector2Array()
	var ends := PackedVector2Array()
	var excluded := PackedStringArray()
	var levels := PackedInt32Array()
	for shot: int in 32:
		starts.append(Vector2.ZERO if shot != 31 else Vector2(0, 50))
		ends.append(Vector2(20, 0) if shot != 31 else Vector2(20, 50))
		excluded.append("0" if shot % 2 == 0 else "none")
		levels.append(0 if shot != 30 else 1)
	var serial := SimSpatialQueries.new()
	serial.start(bodies, starts, ends, excluded, levels, 1.0, 0)
	var parallel := SimSpatialQueries.new()
	parallel.start(bodies, starts, ends, excluded, levels, 1.0, 4)
	var expected_targets: PackedInt32Array = serial.collect(starts.size())
	if parallel.collect(starts.size()) != expected_targets or not parallel.execution.parallel:
		return false
	return expected_targets[0] == 65 and expected_targets[1] == 0 and expected_targets[30] == -1 and expected_targets[31] == -1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var selected: Array[String] = []
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = 0
	while index < arguments.size():
		if arguments[index] == "--list-suites":
			for name: String in SUITES:
				print(name)
			quit(0)
			return
		if arguments[index] != "--suite" or index + 1 >= arguments.size() or not SUITES.has(arguments[index + 1]):
			printerr("FAIL unknown smoke selection")
			quit(1)
			return
		selected.append(arguments[index + 1])
		index += 2
	var started: int = Time.get_ticks_usec()
	var completed: int = 0
	for name: String in SUITES:
		if not selected.is_empty() and not selected.has(name):
			continue
		print("RUN ", name)
		if call("_" + name) != true:
			printerr("FAIL ", name)
			quit(1)
			return
		completed += 1
		print("PASS ", name)
	print("Smoke: %d checks, %.3f ms; scope: execution primitives only" % [completed, (Time.get_ticks_usec() - started) / 1000.0])
	quit(0)


func _settlement() -> bool:
	var order: Array[String] = []
	var kernel := Kernel.new([&"effects"])
	# Registration and alphabetical order both disagree with the dependency.
	if not kernel.add_step(&"attack", &"effects", func(_at: int) -> void: order.append("attack"), Kernel.CallMode.TIMED, [&"heal"]):
		return false
	if not kernel.add_step(&"heal", &"effects", func(_at: int) -> void: order.append("heal")):
		return false
	if not kernel.compile() or not kernel.begin(0, 17):
		return false
	if kernel.resume(1) != Kernel.Status.PENDING or order != ["heal"]:
		return false
	if kernel.resume(1) != Kernel.Status.COMPLETE or order != ["heal", "attack"]:
		return false
	if kernel.resume(1) != Kernel.Status.COMPLETE or order != ["heal", "attack"]:
		return false
	var ready: Array[bool] = [false]
	if not kernel.set_completion_readiness(func(_at: int) -> bool: return ready[0]) or not kernel.begin(17, 50):
		return false
	if kernel.resume(8) != Kernel.Status.PENDING or kernel.progress().step != "publication" or order != ["heal", "attack", "heal", "attack"]:
		return false
	var executed: int = kernel.executed_steps
	if kernel.resume(8) != Kernel.Status.PENDING or kernel.executed_steps != executed:
		return false
	ready[0] = true
	return kernel.resume(8) == Kernel.Status.COMPLETE and kernel.executed_steps == executed and not kernel.is_pending()


func _batch(workers: int) -> SimActorAdvance:
	var batch := ActorBatch.new()
	batch.at_ms = 1500
	var body: Dictionary = {"active": {}, "position": [32.0, 32.0], "facing": [1.0, 0.0],
		"hunger": 80.0, "energy": 60.0, "need_carry": {"hunger": 0, "energy": 0},
		"stamina": 50, "stamina_carry": 0, "exertion_until_ms": 0}
	for row: int in 64:
		batch.append(str(row), body, 0, 1000000, 2000000, true, 100, 10)
	batch.start(workers)
	batch.execution.finish(true)
	return batch


func _actor_batch() -> bool:
	var serial: SimActorAdvance = _batch(0)
	var parallel: SimActorAdvance = _batch(2)
	if not parallel.execution.parallel:
		return false
	for index: int in serial.chunks.size():
		if serial.chunks[index].output != parallel.chunks[index].output or serial.chunks[index].poses != parallel.chunks[index].poses:
			return false
	parallel.execution.cancel()
	return parallel.execution.cancelled and parallel.execution.finish()


func _inventory() -> bool:
	var inventory := Inventory.new()
	if not inventory.create_container("store", {"wood": 5}) or not inventory.create_container("bag", {}):
		return false
	if not inventory.transfer("take", "store", "bag", "wood", 3):
		return false
	if not inventory.transfer("take", "store", "bag", "wood", 3):
		return false
	if inventory.transfer("too_much", "store", "bag", "wood", 3):
		return false
	return inventory.quantity("store", "wood") == 2 and inventory.quantity("bag", "wood") == 3


func _input() -> bool:
	# Backlog must offer a completed boundary before starting another interval.
	var clock := ReolGameClock.new()
	var calls: Array[int] = [0]
	var boundaries: Array[int] = []
	clock.bind_interval_executor(func(from: int, to: int) -> int:
		calls[0] += 1
		return from if calls[0] == 1 else to)
	clock.input_boundary.connect(func() -> void:
		if not clock.has_pending_advance(): boundaries.append(clock.elapsed_ms))
	clock.advance_frame(0.2)
	clock.request_input_boundary()
	clock.advance_frame(0.0)
	var offered: bool = boundaries == [50] and calls[0] == 2
	clock.advance_frame(0.0)
	var caught_up: bool = clock.elapsed_ms == 200 and boundaries == [50]
	clock.free()
	if not offered or not caught_up:
		return false
	# Never execute a replaced destination, expired dodge or prior-avatar input.
	var buffer := ReolPlayerCommandBuffer.new()
	var finished: Array[int] = []
	buffer.finished.connect(func(id: int, _kind: String, _result: Dictionary) -> void: finished.append(id))
	buffer.enqueue("travel", {"region": "home"}, "session:a", 0)
	buffer.enqueue("travel", {"region": "river"}, "session:a", 1)
	buffer.enqueue("sidestep", {"direction": Vector2.RIGHT}, "session:a", 2)
	buffer.expire("session:a", 303)
	var command: Dictionary = buffer.take()
	if finished != [1, 3] or command.get("id") != 2 or command.args.region != "river" or buffer.pending():
		return false
	buffer.enqueue("cancel", {}, "session:a", 304)
	buffer.expire("session:b", 305)
	return not buffer.pending() and finished == [1, 3, 4]


func _presentation() -> bool:
	var queue := ReolPresentationWork.new()
	var now: Array[int] = [0]
	var order: Array[String] = []
	queue.host_time = func() -> int: return now[0]
	queue.request(&"terrain", func() -> bool: order.append("old"); return true,
		ReolPresentationWork.Priority.BACKGROUND, 10)
	queue.request(&"light", func() -> bool: order.append("light"); now[0] += 1200; return true,
		ReolPresentationWork.Priority.VISIBLE, 10)
	queue.run_pending(1000)
	var valid: bool = order == ["light"] and queue.diagnostics().pending == 1
	# Repeated changes keep the original deadline but use the latest projection.
	now[0] = 5000
	queue.request(&"terrain", func() -> bool: order.append("latest"); return true,
		ReolPresentationWork.Priority.BACKGROUND, 10)
	queue.request(&"new_light", func() -> bool: order.append("new_light"); return true,
		ReolPresentationWork.Priority.VISIBLE, 0)
	now[0] = 10000
	queue.run_pending(0)
	queue.run_pending(0)
	valid = valid and order == ["light", "new_light", "latest"] and queue.diagnostics().pending == 0
	# A blocked completed-world query must not starve another overdue projection.
	queue.request(&"blocked", func() -> bool: return false, ReolPresentationWork.Priority.VISIBLE, 0)
	queue.request(&"ready", func() -> bool: order.append("ready"); return true, ReolPresentationWork.Priority.BACKGROUND, 0)
	queue.run_pending(0)
	valid = valid and order.back() == "ready" and queue.diagnostics().pending == 1
	queue.clear()
	# A newer dirty mark inside a callback survives acknowledgement of old work.
	queue.request(&"replace", func() -> bool:
		queue.request(&"replace", func() -> bool: order.append("replacement"); return true,
			ReolPresentationWork.Priority.VISIBLE, 0)
		return true, ReolPresentationWork.Priority.VISIBLE, 0)
	queue.run_pending(1000)
	valid = valid and queue.diagnostics().pending == 1
	queue.run_pending(1000)
	valid = valid and order.back() == "replacement" and queue.diagnostics().pending == 0
	queue.request(&"cancelled", func() -> bool: order.append("wrong"); return true,
		ReolPresentationWork.Priority.VISIBLE, 0)
	queue.clear()
	queue.run_pending(1000)
	valid = valid and order.back() == "replacement"
	queue.free()
	return valid
