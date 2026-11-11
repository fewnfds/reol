class_name SimWorldRunner
extends RefCounted
## One writer for the original world. The host lends exclusive ownership for
## an interval; the mailbox returns it only at a complete boundary. No Nodes,
## engine frame deadlines or Input calls are used on this thread.
const SLICE_USEC: int = 12000
var _world: WeakRef
var world: RegionalSimulation:
	get: return _world.get_ref() if _world != null else null
var motion: SimLocalMotion
var journey: Dictionary = {}
var manual_moving: bool = false
var boundary_driver: Callable
var _intent: Vector2
var _subject: String
var _altitude: int
var _notice: String = ""
var _thread: Thread
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _closing: bool = false
var _request: Dictionary = {}
var _reply: Dictionary = {}
var _in_flight: bool = false


func configure(authority: RegionalSimulation, player_motion: SimLocalMotion) -> void:
	_world = weakref(authority)
	motion = player_motion
	world.set_local_action_owner(_local_action_owns)
	world.set_manual_motion_executor(_advance_motion)
	world.settlement.set_completion_readiness(Callable())
	world.sparring.set_geometry(_practice_contact, world.geometry_read().can_step)
	world.avian_life.set_landing_check(world.geometry_read().is_walkable)
	world.large_bodies.set_geometry(world.map_data.terrain_is_walkable, world.map_data.get_elevation, _incoming_occupancy, true)
	world.construction.set_incoming_occupancy(_incoming_occupancy)


func submit(request: Dictionary) -> Error:
	_mutex.lock()
	if _in_flight or _closing:
		_mutex.unlock()
		return ERR_BUSY
	_request = request
	_in_flight = true
	_mutex.unlock()
	if _thread == null:
		_thread = Thread.new()
		var error: Error = _thread.start(_run)
		if error != OK:
			_thread = null
			_mutex.lock()
			_in_flight = false
			_request = {}
			_mutex.unlock()
			return error
	_wake.post()
	return OK


func take_reply() -> Dictionary:
	_mutex.lock()
	var reply: Dictionary = _reply
	if not reply.is_empty():
		_reply = {}
		_in_flight = false
	_mutex.unlock()
	if reply.is_empty() and _in_flight and _thread != null and not _thread.is_alive():
		_thread.wait_to_finish()
		_thread = null
		_in_flight = false
		world.errors.append("Simulation thread ended without a complete reply")
		reply = {"at_ms": world.settled_ms(), "failed": true, "journey": journey,
			"manual_moving": manual_moving, "publication": null, "notice": "模拟线程意外结束，世界已停止。",
			"had_events": false, "work": {"elapsed_usec": 0, "pending_wait_usec": 0, "thread_id": -1}}
	return reply


func shutdown() -> void:
	_mutex.lock()
	_closing = true
	_mutex.unlock()
	if _thread != null:
		_wake.post()
		_thread.wait_to_finish()
		_thread = null
	_request = {}
	_reply = {}
	_in_flight = false
	boundary_driver = Callable()


func _should_stop() -> bool:
	_mutex.lock()
	var stopping: bool = _closing
	_mutex.unlock()
	return stopping


func _run() -> void:
	OS.set_thread_name("Reol simulation")
	while true:
		_wake.wait()
		_mutex.lock()
		var stopping: bool = _closing
		var request: Dictionary = _request
		_request = {}
		_mutex.unlock()
		if stopping:
			break
		var reply: Dictionary = execute(request)
		_mutex.lock()
		_reply = reply
		_mutex.unlock()


func execute(request: Dictionary) -> Dictionary:
	# Also used by the synchronous comparison path: identical rules/inputs.
	var began: int = Time.get_ticks_usec()
	var before_events: int = int(world.regions.home.simulation_work.boundary_count)
	var before_minute: int = world.regions.home.tick_index
	_intent = request.intent
	_subject = request.subject
	_altitude = request.altitude
	journey = request.journey
	_notice = ""
	var target: int = request.target_ms
	var allow_partial: bool = target - world.settled_ms() > int(motion.rules.clock.fixed_step_ms)
	var pending_wait_usec: int = 0
	var failure: bool = false
	var home: VillageSimulation = world.regions.home
	world.environment_fields._sources._changes.workers = int(request.workers)
	if _subject.begins_with("subject:avian:") and not bool(request.opening):
		world.avian_life.command_flight(_subject.trim_prefix("subject:avian:"), _intent)
	while world.settled_ms() < target or world.has_pending_boundary():
		if _should_stop():
			return {}
		var resuming: bool = world.has_pending_boundary()
		var end: int = world.pending_boundary_ms() if resuming else world.next_runtime_boundary_ms(target)
		if not resuming and not journey.is_empty():
			if not _motion_control():
				_cancel_journey()
				continue
			end = mini(end, int(journey.due_ms))
			var body: Dictionary = home.synchronize_actor("player")
			end = mini(end, SimRouteTravel.crossing_ms(journey, body, world.elapsed_ms))
			var cell: Vector2i = SimRouteTravel.cell(body.cell)
			if not journey.path.is_empty() and not world.geometry_read().can_step(cell, SimRouteTravel.cell(journey.path[0]) - cell):
				if not SimRouteTravel.repair(home, "player", journey, world.elapsed_ms):
					_cancel_journey()
					_notice = "道路已改变，暂时无法到达目的地。"
				continue
		var errors_before: int = world.errors.size()
		world.advance_to_ms(end, int(world.settings.event_budget), 4096, _should_stop)
		if world.settlement.has_failed() or world.errors.size() > errors_before:
			failure = true
			break
		if world.has_pending_boundary():
			var waited: int = Time.get_ticks_usec()
			# All independent batches have already been offered. Sleep on their
			# completion only; a work-budget yield simply continues immediately.
			for sim: VillageSimulation in world.regions.values():
				sim.wait_for_actor_compute()
			world.environment_fields._field.wait_for_source_compute()
			pending_wait_usec += Time.get_ticks_usec() - waited
			continue
		var walking: Dictionary = world.conflicts.walking_projection("player")
		motion.limit_walking_speed(float(walking.speed_fraction) if bool(walking.allowed) else 0.0)
		if motion.velocity.is_zero_approx() and motion.action.is_empty():
			manual_moving = false
		_advance_journey()
		if boundary_driver.is_valid():
			boundary_driver.call()
		if allow_partial and Time.get_ticks_usec() - began >= SLICE_USEC:
			break # Always hand back a complete, causally committed world.
	var completed: int = world.settled_ms()
	var publication: SimBodyPublication
	if not world.has_pending_boundary():
		publication = SimBodyPublication.capture(world, completed, int(request.workers), request.selected, journey, manual_moving, motion.action)
	return {"at_ms": completed, "failed": failure, "journey": journey, "notice": _notice,
		"manual_moving": manual_moving, "publication": publication,
		"had_events": before_events != int(home.simulation_work.boundary_count) or before_minute != home.tick_index,
		"work": {"elapsed_usec": Time.get_ticks_usec() - began, "pending_wait_usec": pending_wait_usec,
			"thread_id": OS.get_thread_caller_id()}, "progress": world.settlement.progress().duplicate()}


func _motion_control() -> bool:
	return _subject == "subject:player" and world.actor_controls("player", "motion") and not world.health.owns_actor("player")


func _local_action_owns(actor: String) -> bool:
	return actor == "player" and not motion.action.is_empty()


func _incoming_occupancy(cell: Vector2i) -> bool:
	return SimMotionClearance.segment_reserves(world.regions.home.synchronize_actor("player"), journey, cell)


func _cancel_journey() -> void:
	journey = {}
	world.interrupt_occupation("player", "manual_override", true)
	if world.conflicts.conflict_for("player").is_empty():
		world.conflicts.cancel("player")


func _advance_motion(from_ms: int, to_ms: int) -> void:
	var sim: VillageSimulation = world.regions.home
	sim.synchronize_actor("player")
	var controlled: bool = _motion_control()
	if controlled and motion.action.is_empty() and not _intent.is_zero_approx():
		_cancel_journey()
	if not journey.is_empty():
		sim.project_actor_route("player", journey, to_ms)
	var automatic: bool = sim.actor_has_action("player") or not journey.is_empty() or world.owns_for_scope("player", &"automatic_motion")
	var previous: Vector2 = motion.position
	if automatic and motion.action.is_empty():
		motion.velocity = Vector2.ZERO
	else:
		if not motion.action.is_empty():
			controlled = controlled and sim.actor_controls("player", "action") and not world.owns_for_scope("player", &"player_action")
		var walking: Dictionary = world.conflicts.walking_projection("player")
		controlled = controlled and (not motion.action.is_empty() or bool(walking.allowed))
		motion.advance(from_ms, to_ms, _intent, world.geometry_read().can_step, controlled, float(walking.speed_fraction))
	manual_moving = not automatic and motion.action.is_empty() and not motion.velocity.is_zero_approx() and not previous.is_equal_approx(motion.position)


func _advance_journey() -> void:
	if journey.is_empty():
		return
	if not _motion_control():
		_cancel_journey()
		_notice = "无法继续行走，停在当前位置。"
		return
	if world.elapsed_ms < int(journey.due_ms):
		return
	var sim: VillageSimulation = world.regions.home
	var path: Array = journey.path
	if not path.is_empty():
		sim.set_actor_cell("player", SimRouteTravel.cell(path.pop_front()))
	world.invalidate_region("home", "player")
	if path.is_empty():
		journey = {}
		_notice = "已到达目的地。"
	else:
		SimRouteTravel.begin_segment(journey, sim.synchronize_actor("player"), world.elapsed_ms, float(motion.rules.motion.speed))


func _practice_contact(from: Vector2, to: Vector2) -> bool:
	var geometry: SimWorldGeometry = world.geometry_read()
	var first: Vector2i = TileGrid.world_to_cell(from)
	if _altitude != 0 or world.map_data.get_elevation(first) != world.map_data.get_elevation(TileGrid.world_to_cell(to)):
		return false
	var count: int = maxi(1, ceili(from.distance_to(to) / float(motion.rules.motion.sweep_px)))
	var previous: Vector2i = first
	for index: int in range(1, count + 1):
		var cell: Vector2i = TileGrid.world_to_cell(from.lerp(to, float(index) / count))
		if cell != previous and not geometry.can_step(previous, cell - previous):
			return false
		previous = cell
	return true
