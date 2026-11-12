extends RefCounted
## Autonomous simulation, reliable commands/receipts, latest-value display.
## Main-thread display polling never schedules or lends the world.

const World = preload("res://scripts/sim/kernel/world.gd")
const Frame = preload("res://scripts/sim/kernel/frame.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")
const SessionIO = preload("res://scripts/sim/kernel/session_io.gd")
const Scenarios = preload("res://scripts/sim/kernel/scenarios.gd")
const MAX_PENDING: int = 4096
const STEP_USEC: int = 50000
const MAX_DEBT_USEC: float = 1000000.0
const ACTION_VISUALS: Dictionary = {
	"construct": Frame.Visual.BUILD, "continue_build": Frame.Visual.BUILD, "demolish": Frame.Visual.BUILD,
	"cook": Frame.Visual.CRAFT, "cut": Frame.Visual.HARVEST, "gather": Frame.Visual.HARVEST, "uproot": Frame.Visual.HARVEST,
	"tend": Frame.Visual.WATER, "sow": Frame.Visual.WATER, "plant": Frame.Visual.WATER,
	"rest": Frame.Visual.REST, "eat": Frame.Visual.EAT, "study": Frame.Visual.READ, "learn": Frame.Visual.READ,
	"talk": Frame.Visual.READ, "trade": Frame.Visual.READ, "practice": Frame.Visual.MEDITATE,
	"take": Frame.Visual.CARRY, "put": Frame.Visual.CARRY}
var _thread := Thread.new()
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _wake_pending: bool = false
var _commands: Array[Dictionary] = []
var _receipts: Array[Dictionary] = []
var _ready_receipts: Array[Dictionary] = [] # Owner-only until the matching Frame publishes.
var _outcomes: Array[Dictionary] = []
var _latest: RefCounted
var _closing: bool = false
var _paused: bool = false
var _speed: float = 1.0
var _inspect: int = 1
var _probe: int = -1
var _next_seq: int = 1
var _pending: int = 0 # Admission also counts receipts not yet collected.
var _count: int
var _workers: int
var _mixed: bool = false
# These fields are used exclusively by the simulation thread.
var _world: RefCounted
var _terrain_view: RefCounted
var _sequence: int = 0
var _snapshot_usec: int = 0
var _overload_usec: float = 0.0
var _steps_cost := PackedInt64Array()
var _worker_ids: Dictionary = {}
var _poses: Array[RefCounted] = []
var _object_revision: int = -1
var _object_view: Dictionary = {}
var _actor_view: Dictionary = {}
var _perception_revision: int = -1
var _perception_view: Dictionary = {}
var _io := SessionIO.new()
var _epoch: int = 1


func start(count: int = 1000, workers: int = -1, speed: float = 1.0, mixed: bool = false) -> Error:
	_count = clampi(count, 1, 60000)
	_workers = workers
	_mixed = mixed
	_speed = clampf(speed, 0.25, 16.0)
	return _thread.start(_run)


func send(value: Dictionary) -> int:
	if _pending >= MAX_PENDING or _closing:
		return 0
	var command: Dictionary = value.duplicate(true)
	command.seq = _next_seq
	_next_seq += 1
	_pending += 1
	_mutex.lock()
	if not command.has("epoch"):
		command.epoch = _latest.epoch if _latest != null else 1
	_commands.append(command)
	_notify_locked()
	_mutex.unlock()
	return command.seq


func control(paused: bool, speed: float) -> void:
	_mutex.lock()
	_paused = paused
	_speed = clampf(speed, 0.25, 16.0)
	_notify_locked()
	_mutex.unlock()


func inspect(id: int, tile: int) -> void:
	_mutex.lock()
	_inspect = id
	_probe = tile
	_notify_locked()
	_mutex.unlock()


func poll() -> Dictionary:
	_mutex.lock()
	var frame: RefCounted = _latest
	var receipts: Array[Dictionary] = _receipts
	var outcomes: Array[Dictionary] = _outcomes
	_receipts = []
	_outcomes = []
	_mutex.unlock()
	_pending -= receipts.size()
	return {"frame": frame, "receipts": receipts, "outcomes": outcomes}


func close() -> void:
	if not _thread.is_started():
		return
	_mutex.lock()
	_closing = true
	_notify_locked()
	_mutex.unlock()
	_thread.wait_to_finish() # Every lane batch is joined before a step returns.


func diagnostics() -> Dictionary:
	# Main-thread mailbox values only; never inspect a running world's internals.
	_mutex.lock()
	var result: Dictionary = {"queued": _commands.size(), "requested_pause": _paused, "closing": _closing}
	_mutex.unlock()
	result.pending = _pending
	result.thread_alive = _thread.is_alive()
	return result


func _notify_locked() -> void:
	# At most one wake token, including while the simulation is running.
	if not _wake_pending:
		_wake_pending = true
		_wake.post()


func _notify_io() -> void:
	_mutex.lock()
	_notify_locked()
	_mutex.unlock()


func _run() -> void:
	_world = World.new()
	_world.initialize(_count, _workers)
	if _mixed:
		Scenarios.mixed(_world)
	_terrain_view = _world.terrain.detached()
	_mutex.lock()
	var paused: bool = _paused
	var speed: float = _speed
	var selected: int = _inspect
	var probe: int = _probe
	_mutex.unlock()
	_publish(paused, speed, selected, probe)
	var last: int = Time.get_ticks_usec()
	var debt: float = 0.0
	while true:
		var now: int = Time.get_ticks_usec()
		if not paused:
			debt += (now - last) * speed
		last = now
		_mutex.lock()
		_wake.try_wait()
		_wake_pending = false
		var closing: bool = _closing
		var next_paused: bool = _paused
		var next_speed: float = _speed
		var next_selected: int = _inspect
		var next_probe: int = _probe
		var commands: Array[Dictionary] = _commands
		_commands = []
		_mutex.unlock()
		if closing:
			# Shutdown cancels unexecuted admissions with receipts, rather than
			# silently dropping them or running a long queued construction batch.
			for command: Dictionary in commands:
				_ready_receipts.append({"seq": command.seq, "kind": command.get("kind", ""), "at_ms": _world.elapsed_ms, "ok": false, "reason": "closed"})
			_publish(true, speed, selected, probe)
			break
		var changed: bool = paused != next_paused or speed != next_speed or selected != next_selected or probe != next_probe or not commands.is_empty()
		paused = next_paused
		if paused:
			debt = 0.0
		speed = next_speed
		selected = next_selected
		probe = next_probe
		var replies: Array[Dictionary] = []
		var io_result: Dictionary = _io.poll()
		if not io_result.is_empty():
			var io_command: Dictionary = io_result.command
			if io_result.ok and io_command.kind == "load":
				var candidate: RefCounted = io_result.candidate
				if candidate != null:
					_world = candidate
					_epoch += 1
					_poses.clear()
					_object_revision = -1
					_perception_revision = -1
					_terrain_view = _world.terrain.detached()
					_steps_cost.clear()
					_worker_ids.clear()
					debt = 0.0
					last = Time.get_ticks_usec()
					io_result.reason = "loaded"
				else:
					io_result.ok = false
					io_result.reason = "invalid_state"
			replies.append({"seq": io_command.seq, "kind": io_command.kind, "at_ms": _world.elapsed_ms, "ok": io_result.ok, "reason": io_result.reason})
			changed = true
		for command: Dictionary in commands:
			if command.get("epoch", _epoch) != _epoch:
				replies.append({"seq": command.seq, "kind": command.get("kind", ""), "at_ms": _world.elapsed_ms, "ok": false, "reason": "session_changed"})
			elif command.get("kind", "") in ["save", "load"]:
				var state: Dictionary = {}
				if command.kind == "save" and not _io.busy:
					_world.flush_topology()
					state = Persistence.capture(_world)
				if not _io.submit(command, state, _notify_io, _workers):
					replies.append({"seq": command.seq, "kind": command.kind, "at_ms": _world.elapsed_ms, "ok": false, "reason": "io_busy_or_failed"})
			else:
				replies.append(_world.command(command))
		_world.flush_topology()
		if _terrain_view.revision != _world.terrain.revision:
			_terrain_view = _world.terrain.detached()
		if not replies.is_empty():
			_ready_receipts.append_array(replies)
		if debt > MAX_DEBT_USEC:
			_overload_usec += debt - MAX_DEBT_USEC
			debt = MAX_DEBT_USEC # Time demand is capped; no committed effect is dropped.
		if not paused and debt >= STEP_USEC:
			var begin: int = Time.get_ticks_usec()
			_world.step()
			_steps_cost.append(Time.get_ticks_usec() - begin)
			if _steps_cost.size() > 4096:
				_steps_cost = _steps_cost.slice(2048)
			for lane: RefCounted in _world.lanes:
				_worker_ids[lane.thread_id] = true
			debt -= STEP_USEC
			_publish(paused, speed, selected, probe)
		elif changed:
			_publish(paused, speed, selected, probe)
		elif paused:
			_wake.wait()
		else:
			# Godot Semaphore has no timed wait. Sleep rather than busy-spin.
			OS.delay_usec(clampi(int((STEP_USEC - debt) / speed), 100, 2000))
	# Complete an admitted cold I/O job once even when closing the session.
	_io.close()
	var final_io: Dictionary = _io.poll()
	if not final_io.is_empty():
		_mutex.lock()
		_receipts.append({"seq": final_io.command.seq, "kind": final_io.command.kind, "at_ms": _world.elapsed_ms, "ok": final_io.ok and final_io.command.kind == "save", "reason": "saved" if final_io.ok and final_io.command.kind == "save" else "closed"})
		_mutex.unlock()


func _publish(paused: bool, speed: float, selected: int, probe: int) -> void:
	var start: int = Time.get_ticks_usec()
	var frame := Frame.new()
	_sequence += 1
	frame.sequence = _sequence
	frame.epoch = _epoch
	frame.world_ms = _world.elapsed_ms
	frame.speed = speed
	frame.paused = paused
	for page: RefCounted in _world.pages:
		frame.ids.append_array(page.ids)
		frame.positions.append_array(page.positions)
		frame.health.append_array(page.health)
		frame.modes.append_array(page.modes)
		frame.flight.append_array(page.flight)
		frame.radii.append_array(page.radii)
		var base: int = frame.visuals.size()
		frame.visuals.resize(base + page.ids.size())
		for row: int in page.ids.size():
			# Small display codes, not a presentation dependency in simulation.
			if page.modes[row] == World.Units.Mode.IDLE and _world.attack_due[base + row] > frame.world_ms:
				frame.visuals[base + row] = Frame.Visual.MELEE # Includes one-shot manual attacks without a combat order.
			elif page.modes[row] == World.Units.Mode.HARVEST:
				frame.visuals[base + row] = Frame.Visual.HARVEST
			elif page.cargo[row] > 0:
				frame.visuals[base + row] = Frame.Visual.CARRY
	for id: int in _world.actions:
		if not _world.actor_slots.has(id):
			continue
		var slot: int = _world.actor_slots[id]
		if frame.modes[slot] == World.Units.Mode.ACTION:
			frame.visuals[slot] = ACTION_VISUALS.get(_world.actions[id].kind, Frame.Visual.IDLE)
	for id: int in _world.combat.orders:
		if _world.actor_slots.has(id):
			var slot: int = _world.actor_slots[id]
			if frame.modes[slot] == World.Units.Mode.IDLE and _world.attack_due[slot] > frame.world_ms:
				frame.visuals[slot] = Frame.Visual.SHOOT if _world.combat.orders[id].ranged else Frame.Visual.MELEE
	if _poses.is_empty() or _poses.back().world_ms != frame.world_ms:
		var pose := Frame.Pose.new()
		pose.world_ms = frame.world_ms
		pose.completed_usec = Time.get_ticks_usec()
		pose.positions = frame.positions # Detached once, immutable in both owners.
		pose.ids = frame.ids
		_poses.append(pose)
		if _poses.size() > 8:
			_poses.pop_front()
	frame.history = _poses.duplicate()
	if _object_revision != _world.objects.layout_revision:
		_object_revision = _world.objects.layout_revision
		_object_view = _world.objects.layout()
		_actor_view = _world.actor_slots.duplicate()
	frame.objects = _object_view
	if _perception_revision != _world.perception.revision:
		_perception_revision = _world.perception.revision
		_perception_view = {"revision": _perception_revision, "tiles": _world.perception.tiles.duplicate(),
			"softness": _world.perception.softness.duplicate(), "explored": _world.perception.explored.duplicate(), "ground": _world.perception.ground.duplicate(),
			"memories": _world.State.copy(_world.perception.memories)}
	frame.perception = _perception_view
	frame.visible = _world.perception.visible.duplicate()
	frame.actor_slots = _actor_view
	for bolt: Dictionary in _world.combat.bolts.values():
		frame.projectiles.append(bolt.position)
		frame.projectile_velocities.append(bolt.velocity)
	frame.inspected = _world.describe(selected)
	frame.player = frame.inspected if selected == 1 else _world.describe(1)
	frame.counters = _world.counters()
	frame.counters.snapshot_usec = _snapshot_usec
	frame.counters.overload_demand_usec = _overload_usec
	frame.counters.worker_thread_ids = _worker_ids.keys()
	frame.counters.step_window_usec = _steps_cost.duplicate()
	frame.tides = _world.environment.tides.duplicate()
	frame.mobile_cells = _world.environment.mobile_cells.duplicate()
	frame.source_enabled = _world.environment.enabled.duplicate()
	frame.room_temperature = _world.environment.room_temperature.duplicate()
	frame.terrain = _terrain_view
	if probe >= 0 and probe < _world.terrain.blocked.size():
		var values := PackedInt32Array()
		values.resize(7)
		_world.environment.sample_raw(probe, values, 0)
		var elements := PackedInt32Array()
		for channel: int in 5:
			elements.append(_world.environment.element(probe, values, 0, channel))
		frame.tile_probe = {"tile": probe, "temperature": _world.environment.temperature_at(probe, values, 0),
			"elements": elements, "room": _world.terrain.rooms[probe], "blocked": _world.terrain.blocked[probe],
			"substrate": _world.terrain.substrate(probe), "cover": _world.terrain.cover[probe], "flooring": _world.terrain.flooring[probe]}
	_snapshot_usec += Time.get_ticks_usec() - start
	frame.published_usec = Time.get_ticks_usec()
	_mutex.lock()
	for outcome: Dictionary in _world.outcomes:
		outcome.epoch = _epoch
	_outcomes.append_array(_world.outcomes)
	_receipts.append_array(_ready_receipts)
	_ready_receipts.clear()
	_latest = frame
	_mutex.unlock()
	_world.outcomes.clear()
