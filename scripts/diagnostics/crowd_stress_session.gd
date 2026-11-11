extends Node
## Development-only full world opening. Uses real NPC bodies, original native
## work, pathfinding, fields and shared-clock recorder; never writes a save.

const MixedWorkload = preload("res://scripts/diagnostics/crowd_mixed_workload.gd")
const ComplexWorkload = preload("res://scripts/diagnostics/crowd_complex_workload.gd")

class FullRateProbe extends ReolSimulationPacing:
	# Diagnostic only: keep normal bounded admission and cooperative execution,
	# but isolate the cost of the adaptive admission policy.
	func observe(seconds: float, work: int, advanced: int, pending: bool, requested: float, owed: float = 0.0) -> void:
		super.observe(seconds, work, advanced, pending, requested, owed)
		rate = 1.0

var root: Window:
	get: return get_tree().root

var _main: Node
var _recorder: Node
var _clock: ReolGameClock
var _quit_after: bool = false
var _report: String = "user://diagnostics/crowd-stress.json"
var _seconds: int = 30
var _revision: String = "unknown"
var _source_dirty: bool = true
var _artifact_sha: String = ""
var _failures: Array[String] = []
var _moved: Dictionary = {}
var _starts: Dictionary = {}
var _status: Label
var _opening_wave: bool = false
var _orders: Dictionary = {}
var _legs: Dictionary = {}
var _last_sample_ms: int = 0
var _travel_actor_ms: int = 0
var _sampled_world_ms: int = 0
var _last_travelling: int = 0
var _next_count_ms: int = 0
var _redirects: int = 0
var _actor_workers: int = 4
var _profile_kernel: bool = false
var _profile_render: bool = false
var _profile_navigation: bool = false
var _pacing_policy: String = "auto"
var _mixed: RefCounted
var _complex: RefCounted
var _rooms: int = 48
var _sources: int = 128
var _circuit_due := SimParticipationIndex.new()
var _circuit_regions: Dictionary[String, String] = {}
var _circuit: ReolCrowdCircuit
var _actor_minimum: int = SimActorAdvance.PARALLEL_MINIMUM
const CIRCUIT: Array[String] = ["rest", "inspect", "check_store", "check_well"]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var assembly_started: int = Time.get_ticks_usec()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="):
			_seconds = clampi(argument.get_slice("=", 1).to_int(), 5, 300)
		elif argument.begins_with("--report="):
			_report = argument.trim_prefix("--report=")
		elif argument.begins_with("--revision="):
			_revision = argument.trim_prefix("--revision=")
		elif argument.begins_with("--source-dirty="):
			_source_dirty = argument.trim_prefix("--source-dirty=") == "1"
		elif argument.begins_with("--artifact-sha256="):
			_artifact_sha = argument.trim_prefix("--artifact-sha256=")
		elif argument == "--quit-after-capture":
			_quit_after = true
		elif argument == "--opening-wave":
			_opening_wave = true
		elif argument == "--mixed":
			_mixed = MixedWorkload.new()
		elif argument == "--complex":
			_complex = ComplexWorkload.new()
		elif argument.begins_with("--rooms="):
			_rooms = clampi(argument.get_slice("=", 1).to_int(), 1, 64)
		elif argument.begins_with("--sources="):
			_sources = clampi(argument.get_slice("=", 1).to_int(), 5, 512)
		elif argument == "--profile-kernel":
			_profile_kernel = true
		elif argument == "--profile-render":
			_profile_render = true
		elif argument == "--profile-navigation":
			_profile_navigation = true
		elif argument.begins_with("--pacing-policy="):
			_pacing_policy = argument.get_slice("=", 1)
		elif argument.begins_with("--actor-workers="):
			_actor_workers = clampi(argument.get_slice("=", 1).to_int(), -1, 64)
		elif argument.begins_with("--actor-minimum="):
			_actor_minimum = clampi(argument.get_slice("=", 1).to_int(), 1, 4096)
	if _mixed != null and (_opening_wave or _seconds < 45):
		push_error("Mixed capture requires at least 45 seconds and no --opening-wave")
		get_tree().quit(1)
		return
	_main = load("res://scenes/main.tscn").instantiate()
	_main.set_script(load("res://scripts/diagnostics/crowd_scene.gd"))
	if _complex != null and not ComplexWorkload.configure(_main):
		push_error("Complex fixture definitions/map were rejected")
		_main.free()
		get_tree().quit(1)
		return
	root.add_child(_main)
	get_tree().current_scene = _main
	_clock = root.get_node("GameClock")
	var runtime: WorldContinuityRuntime = _main.get("_continuity")
	if runtime == null or runtime.world_sim == null or not runtime.avatar_adapter.choose("subject:player"):
		push_error("Stress opening could not assemble the ordinary world")
		get_tree().quit(1)
		return
	for sim: VillageSimulation in runtime.world_sim.regions.values():
		sim.configure_actor_execution(_actor_workers, _actor_minimum)
		sim.profile_native = _profile_kernel
	runtime.body_publication_workers = _actor_workers
	# Original save hotkeys/panels must not overwrite an ordinary player slot.
	runtime.home_runtime().set_process_unhandled_key_input(false)
	for panel: Control in [runtime._panel, _main._village._panel, runtime.service_adapter.panel, _main.hud._pawn_panel]:
		# Ordinary refresh callbacks may show their panel again. A hidden parent
		# keeps this temporary demo's viewport clear without changing those APIs.
		var holder := Control.new()
		panel.get_parent().add_child(holder)
		holder.hide()
		panel.reparent(holder)
	for adapter: Node in [runtime.avatar_adapter, runtime.avatar_adapter.soul]:
		adapter.set_process_unhandled_input(false)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.layer = 100
	_status = Label.new()
	layer.add_child(_status)
	_status.position = Vector2(16, 146)
	_status.add_theme_font_size_override("font_size", 16)
	root.title = "Reol / temporary full-world crowd stress / no ordinary saves"
	_clock.set_paused(true)
	if _complex != null:
		var failure: String = _complex.prepare(runtime, _rooms, _sources)
		if not failure.is_empty():
			push_error(failure)
			_main.free()
			get_tree().quit(1)
			return
	if not _opening_wave:
		# One opening placement of the observer at the real gathering point lets
		# this demo exercise visible crowd rendering too. NPCs never teleport.
		var home: VillageSimulation = runtime.world_sim.regions.home
		var at: Vector2i = SimRouteTravel.cell(home.places.dorm.cell)
		home.set_actor_cell("player", at)
		_main.player.spawn_at(at)
		runtime.world_sim.invalidate_region("home")
		if _mixed != null:
			var failure: String = await _mixed.prepare(runtime, _clock)
			if not failure.is_empty():
				push_error("Mixed workload setup failed: " + failure)
				_main.free()
				get_tree().quit(1)
				return
			# The deliberately accelerated setup is not a throughput sample.
			_clock.pacing.reset()
			_main.player.spawn_at(at)
		_main.fog.set_focus(at)
		_main.fog.update_now()
		_main.camera.global_position = TileGrid.cell_to_world(at)
	# Settle the FINAL observer location. Warming before moving the camera left
	# its newly requested terrain inside the alleged steady-state measurement.
	var warmup_started: int = Time.get_ticks_usec()
	await get_tree().process_frame
	await get_tree().process_frame
	var until: int = Time.get_ticks_msec() + 15000
	while (not _main.world._pending_load.is_empty() or _main.world._painting_chunk.x >= 0 or _main.world._dirty_cursor < _main.world._dirty_order.size()) and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	await get_tree().process_frame
	var warmup_complete: bool = _main.world._pending_load.is_empty() and _main.world._painting_chunk.x < 0 and _main.world._dirty_cursor >= _main.world._dirty_order.size()
	var total: int = 0
	for region: String in runtime.world_sim.regions:
		# Explicit setup may leave a quiet region at its last local event. The
		# first ordinary order belongs to the current shared time, never its past.
		if not runtime.world_sim.advance_region_to_world(region):
			push_error("Crowd region could not reach the start of the capture: " + region)
			_main.free()
			get_tree().quit(1)
			return
		var sim: VillageSimulation = runtime.world_sim.regions[region]
		var bodies: Dictionary = sim.synchronize_actors()
		for id: String in bodies:
			total += 1
			_starts[id] = sim.actor_position(bodies[id])
			if id != "player" and (_mixed == null or not _mixed.uses_actor(id)):
				if _mixed != null and not bodies[id].active.is_empty():
					sim.cancel_action(id, "mixed_circuit_setup")
				_legs[id] = 0
				if sim.submit_action(id, CIRCUIT[0]):
					_orders[id] = str(bodies[id].active.id)
				_circuit_regions[id] = region
				_arm_circuit(sim, id)
		runtime.world_sim.invalidate_region(region)
	if _pacing_policy == "full-rate":
		_clock.pacing = FullRateProbe.new()
	_recorder = load("res://scripts/diagnostics/demo_recorder.gd").new()
	root.add_child(_recorder)
	_recorder.finished.connect(_finish)
	if not _recorder.configure(_main, {"seconds": _seconds, "report": _report, "revision": _revision, "dirty": _source_dirty, "artifact_sha256": _artifact_sha, "profile_kernel": _profile_kernel, "profile_render": _profile_render, "profile_navigation": _profile_navigation, "assembly_usec": Time.get_ticks_usec() - assembly_started,
		"terrain_warmup_usec": Time.get_ticks_usec() - warmup_started, "terrain_warmup_complete": warmup_complete, "pacing_policy": _pacing_policy}):
		get_tree().quit(1)
		return
	_status.text = "临时压力世界 · %d个真实身体 / 双聚落\n原寻路、生活、环境、共同时间 · %s\n不保存到普通档 · WASD / F3 · %d秒采样后%s" % [total, "搬运、生产、移动视野与交锋" if _mixed != null else ("单次出发" if _opening_wave else "抵达后用原命令持续巡行"), _seconds, "退出" if _quit_after else "可继续试玩"]
	_last_sample_ms = _clock.elapsed_ms
	if _mixed == null and not _opening_wave:
		# The temporary producer is pure data and follows the ordinary world's
		# owner, rather than adding serial command work to every render frame.
		_circuit = ReolCrowdCircuit.new()
		_circuit.configure(runtime.world_sim)
		_circuit.complex = _complex
		_circuit.starts = _starts
		_circuit.orders = _orders
		_circuit.legs = _legs
		_circuit.due = _circuit_due
		_circuit.regions = _circuit_regions
		runtime.ensure_simulation_host()
		runtime.simulation_host.runner.boundary_driver = _circuit.sample
	if _mixed != null:
		_mixed.start()
	_clock.set_paused(false)
	get_tree().process_frame.connect(_sample)


func _sample() -> void:
	var runtime: Node = _main.get("_continuity")
	if not runtime.simulation_accessible():
		return
	var world: RegionalSimulation = runtime.world_sim
	if _circuit != null:
		return
	if not world.accepts_commands() or int(_clock.elapsed_ms) == _last_sample_ms:
		return
	var began: int = Time.get_ticks_usec()
	var span: int = int(_clock.elapsed_ms) - _last_sample_ms
	_sampled_world_ms += span
	_travel_actor_ms += _last_travelling * span
	_last_sample_ms = int(_clock.elapsed_ms)
	if _mixed != null and world.elapsed_ms == world.target_ms:
		_mixed.sample()
	if _complex != null and world.elapsed_ms == world.target_ms:
		_complex.sample()
	# This diagnostic driver wakes original orders at their actual route end,
	# rather than polling every body on every rendered frame.
	for id: String in _circuit_due.due_ids(&"circuit", _clock.elapsed_ms):
		var region: String = _circuit_regions[id]
		var sim: VillageSimulation = world.regions[region]
		if not _moved.has(id) and sim.projected_actor_position(id) != _starts[id]:
			_moved[id] = true
		var person: Dictionary = sim.actor_state(id)
		if not _opening_wave and _legs.has(id) and bool(person.alive):
			var ready: bool = person.active.is_empty() or (person.active.get("id", "") == _orders.get(id, "") and person.active.get("phase") == "work")
			if ready and not world.advance_region_to_world(region):
				continue
			# Redirect only our own arrived order through the original commands.
			if person.active.get("id", "") == _orders.get(id, "") and person.active.get("phase") == "work":
				sim.cancel_action(id, "stress_circuit")
				world.invalidate_region(world.clothing.home(id), id)
				_legs[id] = (int(_legs[id]) + 1) % CIRCUIT.size()
				_redirects += 1
			if person.active.is_empty() and sim.submit_action(id, CIRCUIT[int(_legs[id])]):
				_orders[id] = str(person.active.id)
				world.invalidate_region(world.clothing.home(id), id)
		_arm_circuit(sim, id)
	# A bounded low-frequency count is measurement, not workload scheduling.
	if _clock.elapsed_ms >= _next_count_ms:
		_next_count_ms = _clock.elapsed_ms + 500
		_last_travelling = 0
		for sim: VillageSimulation in world.regions.values():
			for id: String in sim.actors:
				if sim.actor_state(id).active.get("phase") == "travel":
					_last_travelling += 1
				if not _moved.has(id) and sim.projected_actor_position(id) != _starts.get(id, Vector2.ZERO):
					_moved[id] = true
		if _mixed != null:
			_last_travelling += _mixed.travelling()
	_recorder.note_driver_work(Time.get_ticks_usec() - began)


func _arm_circuit(sim: VillageSimulation, id: String) -> void:
	var completion: Dictionary = sim.native_route_projections().get(id, {})
	_circuit_due.set_member(&"circuit", id)
	_circuit_due.set_due(&"circuit", id, maxi(sim.elapsed_ms + 1, int(completion.get("at_ms", sim.elapsed_ms + 250))))


func _finish(ok: bool) -> void:
	if _circuit != null:
		_moved = _circuit.moved
		_redirects = _circuit.redirects
		_travel_actor_ms = _circuit.travel_actor_ms
		_sampled_world_ms = _circuit.sampled_world_ms
	get_tree().process_frame.disconnect(_sample)
	# Capture after timing ends so the GPU readback is not a gameplay spike.
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png(_report.trim_suffix(".json") + ".png")
	var visible: int = 1 if _main.player.is_visible_in_tree() else 0
	for pawn: Node2D in _main._village._pawns.values():
		if pawn.is_visible_in_tree():
			visible += 1
	for pawn: Node2D in _main._continuity._remote_views.values():
		if pawn.is_visible_in_tree():
			visible += 1
	var runtime: Node = _main.get("_continuity")
	var crowd: Dictionary = {"actors": _starts.size(), "moved": _moved.size(), "mode": "mixed" if _mixed != null else ("opening_wave" if _opening_wave else "sustained_circuit"), "mean_travelling": float(_travel_actor_ms) / maxi(1, _sampled_world_ms), "visible_at_finish": visible, "redirects": _redirects,
		"environment_compute": runtime._field_compute.diagnostics() if runtime._field_compute != null else {}}
	if _circuit != null:
		crowd["driver_thread"] = "simulation owner"
		crowd["driver_usec"] = _circuit.work_usec
	crowd["environment_sampling"] = runtime.world_sim.environment_fields.motion_sampling_work.duplicate()
	crowd["environment_response_compute"] = runtime.world_sim.environment_fields._sources._changes.compute_work.duplicate()
	crowd["environment_sampling_scope"] = "session_including_setup"
	if _mixed != null:
		var mixed: Dictionary = _mixed.evidence()
		crowd["mixed"] = mixed
		var outcomes: Dictionary = mixed.completed
		if int(outcomes.get("haul:completed", 0)) < 4 or int(outcomes.get("cook:completed", 0)) < 1 or not mixed.door_built or int(mixed.projectiles_emitted) < 1 or int(mixed.observer_cell_changes) < 10 or not mixed.source_carried:
			_failures.append("Mixed capture did not exercise all intended activity: " + JSON.stringify(mixed))
	if _complex != null:
		crowd["complex"] = _complex.evidence()
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(_report))
	if not raw is Dictionary:
		push_error("Crowd recorder did not write a valid report")
		_main.free()
		get_tree().quit(1)
		return
	var report: Dictionary = raw
	report["crowd"] = crowd
	var file := FileAccess.open(_report, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not append workload evidence to the report")
	else:
		file.store_string(JSON.stringify(report, "\t", true))
		file.close()
	print("CROWD_STRESS ", JSON.stringify(crowd), " ok=", ok, " report=", _report)
	if _moved.size() < _starts.size() / 2:
		_failures.append("Too few original NPCs actually moved; this is not a valid movement load")
	if _quit_after and not _opening_wave and float(report.get("running_seconds", 0.0)) < _seconds * 0.9:
		_failures.append("The sustained capture paused early; frame/speed figures are not comparable. Runtime notice: " + str(_main._continuity._notice))
	if not _failures.is_empty():
		push_error(str(_failures))
	if _quit_after or not ok or not _failures.is_empty():
		_main.free()
		get_tree().quit(0 if ok and _failures.is_empty() else 1)
	elif not _opening_wave and _mixed == null:
		# Keep the same circuit playable after recording stops.
		get_tree().process_frame.connect(_sample)
