extends RefCounted
## Autonomous simulation, reliable commands/receipts, latest-value display.
## Main-thread display polling never schedules or lends the world.

const World = preload("res://scripts/sim/kernel/world.gd")
const Frame = preload("res://scripts/sim/kernel/frame.gd")
const MAX_PENDING: int = 4096
const STEP_USEC: int = 50000
const MAX_DEBT_USEC: float = 1000000.0
var _thread := Thread.new()
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _wake_pending: bool = false
var _commands: Array[Dictionary] = []
var _receipts: Array[Dictionary] = []
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
# These fields are used exclusively by the simulation thread.
var _world: RefCounted
var _terrain_view: RefCounted
var _sequence: int = 0
var _snapshot_usec: int = 0
var _overload_usec: float = 0.0
var _steps_cost := PackedInt64Array()
var _worker_ids: Dictionary = {}
var _poses: Array[RefCounted] = []


func start(count: int = 1000, workers: int = -1, speed: float = 1.0) -> Error:
	_count = clampi(count, 1, 60000)
	_workers = workers
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


func _notify_locked() -> void:
	# At most one wake token, including while the simulation is running.
	if not _wake_pending:
		_wake_pending = true
		_wake.post()


func _run() -> void:
	_world = World.new()
	_world.initialize(_count, _workers)
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
			_mutex.lock()
			for command: Dictionary in commands:
				_receipts.append({"seq": command.seq, "kind": command.get("kind", ""), "at_ms": _world.elapsed_ms, "ok": false, "reason": "closed"})
			_mutex.unlock()
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
		for command: Dictionary in commands:
			replies.append(_world.command(command))
		if _terrain_view.revision != _world.terrain.revision:
			_terrain_view = _world.terrain.detached()
		if not replies.is_empty():
			_mutex.lock()
			_receipts.append_array(replies)
			_mutex.unlock()
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


func _publish(paused: bool, speed: float, selected: int, probe: int) -> void:
	var start: int = Time.get_ticks_usec()
	var frame := Frame.new()
	_sequence += 1
	frame.sequence = _sequence
	frame.world_ms = _world.elapsed_ms
	frame.speed = speed
	frame.paused = paused
	for page: RefCounted in _world.pages:
		frame.positions.append_array(page.positions)
		frame.health.append_array(page.health)
		frame.modes.append_array(page.modes)
	if _poses.is_empty() or _poses.back().world_ms != frame.world_ms:
		var pose := Frame.Pose.new()
		pose.world_ms = frame.world_ms
		pose.completed_usec = Time.get_ticks_usec()
		pose.positions = frame.positions # Detached once, immutable in both owners.
		_poses.append(pose)
		if _poses.size() > 8:
			_poses.pop_front()
	frame.history = _poses.duplicate()
	if selected > 0 and selected <= _world.actor_count:
		var page: RefCounted = _world.pages[(selected - 1) / 256]
		var row: int = (selected - 1) % 256
		frame.inspected = {"id": selected, "hp": page.health[row], "energy": page.energy[row], "hunger": page.hunger[row],
			"temperature": page.body_heat[row], "elements": page.elements.slice(row * 5, row * 5 + 5),
			"cargo": page.cargo[row], "potions": page.potions[row], "mode": page.modes[row], "position": page.positions[row]}
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
			"elements": elements, "room": _world.terrain.rooms[probe], "blocked": _world.terrain.blocked[probe]}
	_snapshot_usec += Time.get_ticks_usec() - start
	frame.published_usec = Time.get_ticks_usec()
	_mutex.lock()
	_outcomes.append_array(_world.outcomes)
	_latest = frame
	_mutex.unlock()
	_world.outcomes.clear()
