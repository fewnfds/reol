class_name ReolSimulationHost
extends Node
## Host-side exclusive lease. Drawing retains only previously captured data.
## Gameplay callbacks resume after a complete reply;
## cached drawing, camera and detached body interpolation remain on the host.
var runner: SimWorldRunner
var runtime: WorldContinuityRuntime
var busy: bool = false
var threaded: bool = true
var work: Dictionary = {"requests": 0, "elapsed_usec": 0, "pending_wait_usec": 0,
	"handoff_usec": 0, "prepare_usec": 0, "signal_usec": 0, "input_count": 0, "input_delay_usec": 0,
	"input_max_delay_usec": 0, "thread_ids": {}}
var _bridge := ReolSimulationSignalBridge.new()
var _scene: Node
var _modes: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _request: Dictionary = {}
var _ready: Dictionary = {}
var _gated_at: int
var _probe_enabled: bool = false
var _probe_next_usec: int = 0
var _probe_pending_usec: int = -1
var _probe_samples: Array[float] = []


func configure(adapter: WorldContinuityRuntime) -> void:
	runtime = adapter
	_scene = adapter.home_runtime().get_parent()
	runner = SimWorldRunner.new()
	runner.configure(adapter.world_sim, adapter.home_runtime()._player.motion)
	_bridge.discover(adapter.world_sim)
	_register_tree(_scene)
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--simulation-thread=off":
			threaded = false
		elif argument == "--input-probe":
			_probe_enabled = true


func begin(request: Dictionary) -> void:
	assert(not busy)
	busy = true
	_gated_at = Time.get_ticks_usec()
	_request = request
	_bridge.lend()
	for row: Dictionary in _modes:
		var node: Node = row.node.get_ref()
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED if node == _scene else Node.PROCESS_MODE_INHERIT
	work.prepare_usec += Time.get_ticks_usec() - _gated_at
	work.requests += 1
	if threaded:
		var error: Error = runner.submit(_request)
		assert(error == OK, "Simulation coordinator could not start: " + error_string(error))
		_request = {}
	else:
		_ready = runner.execute(_request)
		_request = {}


func collect() -> Dictionary:
	if not busy:
		return {}
	var reply: Dictionary = runner.take_reply() if threaded else _ready
	if reply.is_empty():
		return {}
	_ready = {}
	busy = false
	var began: int = Time.get_ticks_usec()
	_ungate_tree()
	_bridge.reclaim()
	work.signal_usec += Time.get_ticks_usec() - began
	for key: String in ["elapsed_usec", "pending_wait_usec"]:
		work[key] += int(reply.work[key])
	work.handoff_usec += Time.get_ticks_usec() - _gated_at
	work.thread_ids[int(reply.work.thread_id)] = true
	_finish_probe()
	return reply


func _register_tree(node: Node) -> void:
	# Override old ALWAYS adapters too. The small whitelist has no live-world
	# reads in either process or draw, and only uses published body/clock data.
	if node is Pawn or node is PlayerCharacter or node is CameraController:
		node.process_mode = Node.PROCESS_MODE_ALWAYS
		return
	if node == _scene or node.process_mode != Node.PROCESS_MODE_INHERIT:
		_modes.append({"node": weakref(node), "mode": node.process_mode})
	for child: Node in node.get_children():
		_register_tree(child)


func _ungate_tree() -> void:
	for row: Dictionary in _modes:
		var node: Node = row.node.get_ref()
		if node != null:
			node.process_mode = int(row.mode)


func _input(event: InputEvent) -> void:
	if not busy:
		return
	# Time controls have no world mutation; they remain immediate during a
	# long computation. Finishing the accepted boundary is still mandatory.
	if event.is_action_pressed("toggle_pause"):
		GameClock.toggle_pause()
	elif event.is_action_pressed("speed_1"):
		GameClock.set_speed(1.0)
	elif event.is_action_pressed("speed_2"):
		GameClock.set_speed(2.0)
	elif event.is_action_pressed("speed_4"):
		GameClock.set_speed(4.0)
	elif event is InputEventMouseMotion:
		return # Camera drag is host-only. No disabled gameplay handler runs.
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		return
	else:
		_events.append({"event": event.duplicate(), "at": Time.get_ticks_usec()})
		GameClock.request_input_boundary()
	get_viewport().set_input_as_handled()


func replay_inputs() -> void:
	if busy or _events.is_empty():
		return
	var events: Array[Dictionary] = _events
	_events = []
	for row: Dictionary in events:
		var delay: int = Time.get_ticks_usec() - int(row.at)
		work.input_count += 1
		work.input_delay_usec += delay
		work.input_max_delay_usec = maxi(work.input_max_delay_usec, delay)
		get_viewport().push_input(row.event, true)


func _process(_delta: float) -> void:
	# This node lives outside the gated game scene. Save-boundary draining must
	# remain alive even when a save was requested during a background interval.
	if GameClock._save_boundary_held() and runtime._saves != null:
		runtime._saves.process_save()
	if busy and runtime.presentation_work != null:
		# The ordinary scene is gated. Detached Node projection still has work;
		# other view callbacks retain their ordinary complete-world window.
		runtime.presentation_work.run_pending(GameClock.presentation_budget_usec(), true)
	if not _probe_enabled:
		return
	var now: int = Time.get_ticks_usec()
	if now >= _probe_next_usec and _probe_pending_usec < 0:
		_probe_pending_usec = now
		_probe_next_usec = now + 250000
		GameClock.request_input_boundary()
	if not busy:
		_finish_probe()


func _finish_probe() -> void:
	if _probe_pending_usec >= 0:
		_probe_samples.append((Time.get_ticks_usec() - _probe_pending_usec) / 1000.0)
		_probe_pending_usec = -1


func input_probe() -> Dictionary:
	var values: Array[float] = _probe_samples.duplicate()
	values.sort()
	return {"scope": "host intent receipt to complete-world handoff; harmless probe, not motion-to-photon",
		"samples": values.size(), "p50_ms": values[values.size() / 2] if not values.is_empty() else null,
		"p95_ms": values[mini(values.size() - 1, int(values.size() * 0.95))] if not values.is_empty() else null,
		"max_ms": values[-1] if not values.is_empty() else null}


func close() -> void:
	if runner != null:
		runner.shutdown()
	_bridge.reclaim(false)
	_ungate_tree()
	busy = false
	_events.clear()
	_ready = {}
	_request = {}


func _exit_tree() -> void:
	close()
