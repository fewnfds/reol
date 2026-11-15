extends RefCounted
## Autonomous simulation, reliable commands/receipts, latest-value display.
## Main-thread display polling never schedules or lends the world.

const World = preload("res://scripts/sim/kernel/world.gd")
const Frame = preload("res://scripts/sim/kernel/frame.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")
const SessionIO = preload("res://scripts/sim/kernel/session_io.gd")
const Scenarios = preload("res://scripts/sim/kernel/scenarios.gd")
const MAX_PENDING: int = 4096
const DEFAULT_HZ: int = 60
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
var _side_view := PackedByteArray()
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
var _capacity: bool = false
var _sim_hz: int = DEFAULT_HZ
var _combat_lab: bool = false
var _drive: Dictionary = {}
var _control_generation: int = 0 # Mutex-protected input lifetime, independent of session epoch.
var _adopted_control_generation: int = 0 # Owner-only.
var _slow_frame: RefCounted
var _slow_selected: int = -1
var _slow_probe: int = -2
var _inspected_view: Dictionary = {}
var _player_view: Dictionary = {}
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
var _sight_revision: int = -1
var _loss_view := PackedByteArray()
var _perception_view: Dictionary = {}
var _io := SessionIO.new()
var _epoch: int = 1
var _combat_probe: RefCounted
var _full_publications: int = 0


func start(count: int = 1000, workers: int = -1, speed: float = 1.0, mixed: bool = false, capacity: bool = false, sim_hz: int = DEFAULT_HZ, combat_lab: bool = false, combat_probe: bool = false) -> Error:
	if not World.Combat.Defs.ERRORS.is_empty():
		push_error("Combat catalog: " + "; ".join(World.Combat.Defs.ERRORS))
		return ERR_INVALID_DATA
	_count = clampi(count, 1, 60000)
	_workers = workers
	_mixed = mixed
	_capacity = capacity
	_sim_hz = sim_hz if sim_hz in [20, 60, 100] else DEFAULT_HZ
	_combat_lab = combat_lab
	if combat_probe: _combat_probe = preload("res://scripts/sim/diagnostics/combat_probe.gd").new()
	_speed = clampf(speed, 0.25, 16.0)
	return _thread.start(_run)


func send(value: Dictionary) -> int:
	if _pending >= MAX_PENDING or _closing:
		return 0
	var command: Dictionary = value.duplicate(true)
	if command.has("_trace"):
		command._trace.enqueued_usec = Time.get_ticks_usec()
	command.seq = _next_seq
	_next_seq += 1
	_pending += 1
	_mutex.lock()
	if not command.has("epoch"):
		command.epoch = _latest.epoch if _latest != null else 1
	if command.get("kind", "") == "action": command.control_generation = _control_generation
	_commands.append(command)
	_notify_locked()
	_mutex.unlock()
	return command.seq


func drive(value: Dictionary) -> void:
	# Continuous intent has one overwrite slot, never a growing mouse-event queue.
	_mutex.lock()
	_drive = value.duplicate(true)
	_drive.epoch = _latest.epoch if _latest != null else 1
	_drive.control_generation = _control_generation
	_notify_locked()
	_mutex.unlock()


func invalidate_control() -> void:
	# This fact survives a later drive overwrite, including UI open/close in one frame.
	_mutex.lock()
	_control_generation += 1
	_drive = {} # Generation adoption clears old state before admitting fresh edges.
	_notify_locked()
	_mutex.unlock()


func _apply_direct_action(command: Dictionary) -> Dictionary:
	# Linearize input invalidation against the short action-start commit, not World.step/I/O.
	_mutex.lock()
	var reply: Dictionary
	if int(command.get("control_generation", -1)) != _control_generation:
		reply = {"seq": command.seq, "kind": "action", "at_ms": _world.elapsed_ms, "ok": false, "reason": "input_canceled"}
	elif _paused:
		reply = {"seq": command.seq, "kind": "action", "at_ms": _world.elapsed_ms, "ok": false, "reason": "paused"}
	else:
		reply = _world.command(command)
	_mutex.unlock()
	return reply


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
	_world.initialize(_count, _workers, _mixed or _capacity)
	if _capacity:
		Scenarios.capacity(_world)
	elif _mixed:
		Scenarios.mixed(_world)
	if _combat_probe != null: _combat_probe.setup(_world)
	elif _combat_lab: Scenarios.combat_lab(_world, "mixed", "bloodblade")
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
	var tick: int = 0
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
		var drive_input: Dictionary = _drive
		_drive = {}
		var control_generation: int = _control_generation
		_mutex.unlock()
		if closing:
			# Shutdown cancels unexecuted admissions with receipts, rather than
			# silently dropping them or running a long queued construction batch.
			for command: Dictionary in commands:
				_ready_receipts.append({"seq": command.seq, "kind": command.get("kind", ""), "at_ms": _world.elapsed_ms, "ok": false, "reason": "closed"})
			_publish(true, speed, selected, probe)
			break
		var changed: bool = paused != next_paused or speed != next_speed or selected != next_selected or probe != next_probe or not commands.is_empty()
		if control_generation != _adopted_control_generation:
			_world.combat.set_control(_world, {"enabled": false})
			_adopted_control_generation = control_generation
		paused = next_paused
		if paused:
			debt = 0.0
			_world.combat.set_control(_world, {"enabled": false})
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
					_world.combat.set_control(_world, {"enabled": false})
					_epoch += 1
					_poses.clear()
					_object_revision = -1
					_perception_revision = -1
					_sight_revision = -1
					_terrain_view = _world.terrain.detached()
					_steps_cost.clear()
					_worker_ids.clear()
					_slow_frame = null
					drive_input = {}
					debt = 0.0
					last = Time.get_ticks_usec()
					io_result.reason = "loaded"
				else:
					io_result.ok = false
					io_result.reason = "invalid_state"
			replies.append({"seq": io_command.seq, "kind": io_command.kind, "at_ms": _world.elapsed_ms, "ok": io_result.ok, "reason": io_result.reason})
			changed = true
		for command: Dictionary in commands:
			# Diagnostic envelope belongs to Runner, never to a world action/save.
			var trace: Dictionary = command.get("_trace", {})
			command.erase("_trace")
			var reply_count: int = replies.size()
			if not trace.is_empty():
				trace.received_usec = Time.get_ticks_usec()
			if command.get("epoch", _epoch) != _epoch:
				replies.append({"seq": command.seq, "kind": command.get("kind", ""), "at_ms": _world.elapsed_ms, "ok": false, "reason": "session_changed"})
			elif paused and command.get("kind", "") == "action":
				replies.append({"seq": command.seq, "kind": "action", "at_ms": _world.elapsed_ms, "ok": false, "reason": "paused"})
			elif command.get("kind", "") == "action":
				replies.append(_apply_direct_action(command))
			elif command.get("kind", "") in ["save", "load"]:
				var state: Dictionary = {}
				if command.kind == "save" and not _io.busy:
					_world.flush_topology()
					state = Persistence.capture(_world)
				if not _io.submit(command, state, _notify_io, _workers):
					replies.append({"seq": command.seq, "kind": command.kind, "at_ms": _world.elapsed_ms, "ok": false, "reason": "io_busy_or_failed"})
			elif command.get("kind", "") == "combat_practice":
				var mode: String = str(command.get("mode", "light"))
				var loadout: String = str(command.get("loadout", _world.combat.profile(_world, 1).id))
				if not _combat_lab or mode not in ["light", "heavy", "mixed"] or not _world.combat.Defs.LOADOUTS.has(loadout) or not _world.combat.Defs.LOADOUTS.get(loadout, {}).get("playable", false) or _io.busy:
					replies.append({"seq": command.seq, "kind": "combat_practice", "at_ms": _world.elapsed_ms, "ok": false, "reason": "practice_unavailable"})
				else:
					_world = World.new()
					_world.initialize(_count, _workers)
					Scenarios.combat_lab(_world, mode, loadout)
					_epoch += 1
					_poses.clear()
					_object_revision = -1
					_perception_revision = -1
					_sight_revision = -1
					_terrain_view = _world.terrain.detached()
					_slow_frame = null
					drive_input = {}
					debt = 0.0
					last = Time.get_ticks_usec()
					tick = 0
					replies.append({"seq": command.seq, "kind": "combat_practice", "at_ms": 0, "ok": true, "reason": "practice_ready"})
			else:
				replies.append(_world.command(command))
			if not trace.is_empty() and replies.size() > reply_count:
				trace.applied_usec = Time.get_ticks_usec()
				replies.back().trace = trace
		_mutex.lock()
		var still_current: bool = control_generation == _control_generation
		_mutex.unlock()
		if not still_current:
			_world.combat.set_control(_world, {"enabled": false})
		elif not paused and not drive_input.is_empty() and drive_input.epoch == _epoch:
			_world.combat.set_control(_world, drive_input)
		_world.flush_topology()
		if _terrain_view.revision != _world.terrain.revision:
			_terrain_view = _world.terrain.detached()
		if not replies.is_empty():
			_ready_receipts.append_array(replies)
		if debt > MAX_DEBT_USEC:
			_overload_usec += debt - MAX_DEBT_USEC
			debt = MAX_DEBT_USEC # Time demand is capped; no committed effect is dropped.
		var delta_ms: int = (tick + 1) * 1000 / _sim_hz - tick * 1000 / _sim_hz
		var step_usec: int = delta_ms * 1000
		if not paused and debt >= step_usec:
			if _combat_probe != null: _combat_probe.advance(_world)
			var begin: int = Time.get_ticks_usec()
			_world.step(delta_ms)
			tick += 1
			_steps_cost.append(Time.get_ticks_usec() - begin)
			if _steps_cost.size() > 4096:
				_steps_cost = _steps_cost.slice(2048)
			for lane: RefCounted in _world.lanes:
				_worker_ids[lane.thread_id] = true
			debt -= step_usec
			_publish(paused, speed, selected, probe)
		elif changed:
			_publish(paused, speed, selected, probe)
		elif paused:
			_wake.wait()
		else:
			# Godot Semaphore has no timed wait. Sleep rather than busy-spin.
			OS.delay_usec(clampi(int((step_usec - debt) / speed), 100, 2000))
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
	frame.practice_mode = str(_world.objects.records[1].get("practice_mode", "")) if _combat_lab else ""
	frame.reactions = {}
	for actor: int in _world.combat.status:
		frame.reactions[actor] = _world.combat.status[actor].duplicate(true)
		frame.reactions[actor]["heavy"] = bool(_world.combat.status[actor].get("punishable", false))
	frame.epoch = _epoch
	frame.world_ms = _world.elapsed_ms
	frame.speed = speed
	frame.paused = paused
	frame.interpolation_ms = 1000.0 / _sim_hz
	frame.combat = _world.combat.view()
	frame.loadout = _world.combat.profile(_world, 1) # Recursively read-only compiled definition.
	frame.areas = _world.State.copy(_world.areas.records)
	frame.implements = _world.State.copy(_world.implements.records)
	frame.effects = _world.State.copy(_world.effects.records)
	frame.entities = _world.State.copy(_world.entities.records)
	for id: int in frame.entities:
		frame.entities[id]["position"] = _world.combat.position(_world, id)
		frame.entities[id]["hp"] = int(_world.objects.records[id].get("hp", 0))
	frame.action_trace = _world.reactions.trace.duplicate(true)
	frame.pools = _world.State.copy(_world.pools.records.get(1, {}))
	frame.shields = _world.State.copy(_world.defense.shields)
	frame.guards = _world.State.copy(_world.defense.guards)
	frame.cooldowns = _world.State.copy(_world.combat.cooldowns.get(1, {}))
	for page: RefCounted in _world.pages:
		frame.ids.append_array(page.ids)
		frame.positions.append_array(page.positions)
		frame.health.append_array(page.health)
		frame.max_health.append_array(page.max_health)
		frame.modes.append_array(page.modes)
		frame.flight.append_array(page.flight)
		frame.radii.append_array(page.radii)
		frame.aims.append_array(page.aims)
		var base: int = frame.visuals.size()
		frame.visuals.resize(base + page.ids.size())
		for row: int in page.ids.size():
			# Small display codes, not a presentation dependency in simulation.
			if frame.combat.has(page.ids[row]):
				frame.visuals[base + row] = Frame.Visual.SHOOT if frame.combat[page.ids[row]].visual == "shoot" else Frame.Visual.MELEE
			elif page.modes[row] == World.Units.Mode.HARVEST: frame.visuals[base + row] = Frame.Visual.HARVEST
			elif page.cargo[row] > 0: frame.visuals[base + row] = Frame.Visual.CARRY
	for id: int in _world.actions:
		if not _world.actor_slots.has(id):
			continue
		var slot: int = _world.actor_slots[id]
		if frame.modes[slot] == World.Units.Mode.ACTION:
			frame.visuals[slot] = ACTION_VISUALS.get(_world.actions[id].kind, Frame.Visual.IDLE)
	if _poses.is_empty() or _poses.back().world_ms != frame.world_ms:
		var pose := Frame.Pose.new()
		pose.world_ms = frame.world_ms
		pose.completed_usec = Time.get_ticks_usec()
		pose.positions = frame.positions # Detached once, immutable in both owners.
		pose.ids = frame.ids
		pose.projectile_segments = _world.combat.projectile_segments
		pose.action_segments = _world.combat.action_segments
		pose.reaction_segments = _world.combat.reaction_segments
		pose.implement_segments = _world.implements.segments
		var offset: int = 0
		for page: RefCounted in _world.pages:
			for row: int in page.motion:
				pose.motion[offset + row] = page.motion[row] # Immutable after this step.
			offset += page.ids.size()
		_poses.append(pose)
		while _poses.size() > 2 and _poses[1].world_ms < frame.world_ms - 100:
			_poses.pop_front()
	frame.history = _poses.duplicate()
	# Reliable notifications refresh details immediately, without rebuilding all
	# statistics/environment views. Layout and inspection changes remain immediate.
	var management_changed: bool = false
	for receipt: Dictionary in _ready_receipts:
		if receipt.kind != "action": management_changed = true; break
	var full: bool = paused or management_changed or _slow_frame == null or frame.world_ms - _slow_frame.world_ms >= 100 or selected != _slow_selected or probe != _slow_probe or _object_revision != _world.objects.layout_revision or _terrain_view.revision != _slow_frame.terrain.revision
	if full or not _ready_receipts.is_empty() or not _world.outcomes.is_empty():
		_inspected_view = _world.describe(selected)
		_player_view = _inspected_view if selected == 1 else _world.describe(1)
	frame.inspected = _inspected_view
	frame.player = _player_view
	for bolt: Dictionary in _world.combat.bolts.values():
		frame.projectiles.append(bolt.position)
		frame.projectile_velocities.append(bolt.velocity)
	if full:
		_full_publications += 1
		if _object_revision != _world.objects.layout_revision:
			_object_revision = _world.objects.layout_revision
			_object_view = _world.objects.layout()
			_actor_view = _world.actor_slots.duplicate()
			_side_view = PackedByteArray() # Previous Frames retain their immutable column.
			_side_view.resize(frame.ids.size())
			for slot: int in frame.ids.size():
				_side_view[slot] = int(_world.objects.records.get(frame.ids[slot], {}).get("side", 0))
		frame.objects = _object_view
		frame.sides = _side_view
		if _sight_revision != _world.sight.revision:
			_sight_revision = _world.sight.revision
			_loss_view = _world.sight.smooth_loss.to_byte_array()
		if _perception_revision != _world.perception.revision:
			_perception_revision = _world.perception.revision
			_perception_view = {"revision": _perception_revision, "tiles": _world.perception.tiles.duplicate(),
				"loss_revision": _sight_revision, "loss": _loss_view,
				"softness": _world.perception.softness.duplicate(), "explored": _world.perception.explored.duplicate(), "ground": _world.perception.ground.duplicate(),
				"memories": _world.State.copy(_world.perception.memories), "fringe": _world.State.copy(_world.perception.fringe)}
		frame.perception = _perception_view
		frame.visible = _world.perception.visible.duplicate()
		frame.actor_slots = _actor_view
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
				"ambient": _world.environment.ambient_at(probe), "heat": values[0], "cold": values[1],
				"elements": elements, "room": _world.terrain.rooms[probe], "blocked": _world.terrain.blocked[probe],
				"substrate": _world.terrain.substrate(probe), "cover": _world.terrain.cover[probe], "flooring": _world.terrain.flooring[probe]}
		_slow_frame = frame
		_slow_selected = selected
		_slow_probe = probe
	else:
		for field: String in Frame.SLOW_FIELDS: frame.set(field, _slow_frame.get(field))
	_snapshot_usec += Time.get_ticks_usec() - start
	if _combat_probe != null:
		frame.profile = _combat_probe.report(_world)
		frame.profile["snapshot_usec"] = _snapshot_usec
		frame.profile["full_publications"] = _full_publications
	frame.published_usec = Time.get_ticks_usec()
	_mutex.lock()
	for outcome: Dictionary in _world.outcomes:
		outcome.epoch = _epoch
	_outcomes.append_array(_world.outcomes)
	for receipt: Dictionary in _ready_receipts:
		if receipt.has("trace"):
			receipt.trace.published_usec = Time.get_ticks_usec()
			receipt.trace.frame_sequence = frame.sequence
	_receipts.append_array(_ready_receipts)
	_ready_receipts.clear()
	_latest = frame
	_mutex.unlock()
	_world.outcomes.clear()
