extends SceneTree
## Small checks for current execution primitives. No world/content assembly.

const Kernel = preload("res://scripts/sim/execution/settlement_kernel.gd")
const ActorBatch = preload("res://scripts/sim/actor_advance.gd")
const Inventory = preload("res://scripts/sim/inventory_ledger.gd")
const SUITES: Array[String] = ["settlement", "actor_batch", "inventory", "input"]


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
