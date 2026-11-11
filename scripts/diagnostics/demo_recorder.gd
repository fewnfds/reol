extends Node
## Host-only callback timings. No rule, save, input or time-budget changes.

signal finished(ok: bool)

const MAX_SAMPLES: int = 20000
const MAX_SPIKES: int = 24
var _main: Node
var _clock
var _runtime
var _options: Dictionary
var _executor: Callable
var _kernel_ref: WeakRef
var _originals: Dictionary = {}
var _wrappers: Dictionary = {}
var _scopes: Dictionary = {}
var _frame_scopes: Dictionary = {}
var _frame_kernel_usec: int = 0
var _frame_executor_usec: int = 0
var _total_clock_usec: int = 0
var _total_executor_usec: int = 0
var _total_kernel_usec: int = 0
var _driver_usec: int = 0
var _total_driver_usec: int = 0
var _executor_calls: int = 0
var _executor_no_progress: int = 0
var _clock_publications: int = 0
var _publication_spans: Array[float] = []
var _initial_world_boundaries: int = 0
var _frame_count: int = 0
var _over_60fps_budget: int = 0
var _fog_updates: int = 0
var _frames: Array[float] = []
var _clock_samples: Array[float] = []
var _spikes: Array[Dictionary] = []
var _started: int = 0
var _last: int = 0
var _window: int = 0
var _last_world_ms: int = 0
var _last_world_id: int = 0
var _was_running: bool = false
var _running_usec: int = 0
var _advanced_ms: int = 0
var _requested_ms: float = 0.0
var _minimum_rate: float = 1.0
var _slow_usec: int = 0
var _windows: FileAccess
var _done: bool = false
var _sample_clock_work: bool = false
var _profile_kernel: bool = false
var _profile_render: bool = false
var _render_viewport := RID()
var _render_cpu: Array[float] = []
var _render_gpu: Array[float] = []
var _render_setup: Array[float] = []
var _initial_actor_execution: Dictionary = {}
var _initial_actor_world_id: int = 0
var _initial_spatial_work: Dictionary = {}
var _initial_geometry_work: Dictionary = {}
var _profile_navigation: bool = false
var _navigation_originals: Array[Dictionary] = []
var _navigation_calls: int = 0
var _navigation_usec: int = 0
var _navigation_max_usec: int = 0
var _navigation_queries: Array = []


func configure(main: Node, options: Dictionary) -> bool:
	_main = main
	_options = options
	_profile_kernel = bool(options.get("profile_kernel", false))
	_profile_navigation = bool(options.get("profile_navigation", false))
	_profile_render = bool(options.get("profile_render", false)) and RenderingServer.get_rendering_device() != null
	if _profile_render:
		_render_viewport = get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(_render_viewport, true)
	_clock = get_tree().root.get_node("GameClock")
	_runtime = main.get("_continuity")
	_executor = _clock._interval_executor
	if not _executor.is_valid():
		push_error("Demo recorder requires the ordinary clock executor")
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(str(options.report).get_base_dir()))
	_windows = FileAccess.open(str(options.report).trim_suffix(".json") + ".jsonl", FileAccess.WRITE)
	if _windows == null:
		push_error("Demo recorder cannot open its window log")
		return false
	_clock._interval_executor = _execute
	_clock.time_advanced.connect(_published)
	_initial_world_boundaries = int(_runtime.world_sim.simulation_work.boundaries)
	_initial_actor_execution = _actor_execution_summary()
	_initial_actor_world_id = _runtime.world_sim.get_instance_id()
	_initial_spatial_work = _runtime.world_sim.conflicts.spatial_work.duplicate()
	_initial_geometry_work = _runtime.world_sim.geometry_read().work.duplicate()
	if _profile_navigation:
		for sim: VillageSimulation in _runtime.world_sim.regions.values():
			_profile_navigation_owner(sim)
		if _runtime.world_sim.services != null:
			_profile_navigation_owner(_runtime.world_sim.services)
	_bind_kernel()
	_main.get("fog").visibility_updated.connect(_fog_updated)
	get_tree().process_frame.connect(_before_frame)
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100000
	_started = Time.get_ticks_usec()
	_last = _started
	_window = _started
	_last_world_ms = int(_clock.elapsed_ms)
	_last_world_id = _runtime.world_sim.get_instance_id()
	return true


func _bind_kernel() -> void:
	if not _profile_kernel:
		return
	var kernel = _runtime.world_sim.settlement
	if _kernel_ref != null and _kernel_ref.get_ref() == kernel:
		return
	_unwrap_kernel()
	_kernel_ref = weakref(kernel)
	for step in kernel._plan:
		var id: String = String(step.id)
		_originals[id] = step.callback
		var wrapper: Callable
		match step.mode:
			SimSettlementKernel.CallMode.UNTIMED, SimSettlementKernel.CallMode.CHECKED_UNTIMED:
				wrapper = _untimed.bind(step.callback, id)
			SimSettlementKernel.CallMode.BUDGETED:
				wrapper = _budgeted.bind(step.callback, id)
			_:
				wrapper = _timed.bind(step.callback, id)
		_wrappers[id] = wrapper
		step.callback = wrapper


func _profile_navigation_owner(owner: RefCounted) -> void:
	var original: Callable = owner.get("_navigation")
	if not original.is_valid():
		return
	var wrapper: Callable = _navigate.bind(original)
	_navigation_originals.append({"owner": weakref(owner), "original": original, "wrapper": wrapper})
	owner.set("_navigation", wrapper)


func _navigate(from: Vector2i, to: Vector2i, original: Callable) -> Array[Vector2i]:
	var started: int = Time.get_ticks_usec()
	var result: Array[Vector2i] = original.call(from, to)
	var usec: int = Time.get_ticks_usec() - started
	_navigation_calls += 1
	_navigation_usec += usec
	_navigation_max_usec = maxi(_navigation_max_usec, usec)
	if _navigation_queries.size() < 4096:
		_navigation_queries.append([from.x, from.y, to.x, to.y])
	return result


func _unprofile_navigation() -> void:
	for row: Dictionary in _navigation_originals:
		var owner: RefCounted = row.owner.get_ref()
		if owner != null and owner.get("_navigation") == row.wrapper:
			owner.set("_navigation", row.original)
	_navigation_originals.clear()


func _unwrap_kernel() -> void:
	var old = _kernel_ref.get_ref() if _kernel_ref != null else null
	if old != null:
		for step in old._plan:
			var id: String = String(step.id)
			if _wrappers.has(id) and step.callback == _wrappers[id]:
				step.callback = _originals[id]
	_originals.clear()
	_wrappers.clear()
	_kernel_ref = null


func _execute(from_ms: int, to_ms: int) -> Variant:
	_bind_kernel() # Loading replaces the kernel; no former world is retained.
	var started: int = Time.get_ticks_usec()
	var result: Variant = _executor.call(from_ms, to_ms)
	_frame_executor_usec += Time.get_ticks_usec() - started
	_executor_calls += 1
	if result == from_ms:
		_executor_no_progress += 1
	return result


func _published(from_ms: int, to_ms: int) -> void:
	_clock_publications += 1
	if _publication_spans.size() < MAX_SAMPLES:
		_publication_spans.append(float(to_ms - from_ms))


func _timed(at_ms: int, callback: Callable, id: String) -> Variant:
	var started: int = Time.get_ticks_usec()
	var result: Variant = callback.call(at_ms)
	_record(id, Time.get_ticks_usec() - started)
	return result


func _untimed(callback: Callable, id: String) -> Variant:
	var started: int = Time.get_ticks_usec()
	var result: Variant = callback.call()
	_record(id, Time.get_ticks_usec() - started)
	return result


func _budgeted(at_ms: int, budget: int, callback: Callable, id: String) -> Variant:
	var started: int = Time.get_ticks_usec()
	var result: Variant = callback.call(at_ms, budget)
	_record(id, Time.get_ticks_usec() - started)
	return result


func _record(id: String, usec: int) -> void:
	var row: Dictionary = _scopes.get(id, {"calls": 0, "logical_boundaries": 0, "last_at_ms": -1, "total_usec": 0, "max_usec": 0})
	row.calls = int(row.calls) + 1
	var at_ms: int = int(_runtime.world_sim.settlement.at_ms)
	if int(row.last_at_ms) != at_ms:
		row.logical_boundaries = int(row.logical_boundaries) + 1
		row.last_at_ms = at_ms
	row.total_usec = int(row.total_usec) + usec
	row.max_usec = maxi(int(row.max_usec), usec)
	_scopes[id] = row
	_frame_scopes[id] = int(_frame_scopes.get(id, 0)) + usec
	_frame_kernel_usec += usec


func _fog_updated() -> void:
	_fog_updates += 1


func _before_frame() -> void:
	# Capture the clock's admission condition before its _process. A wait may
	# pause on completion in this frame; that frame still did real CPU work.
	_sample_clock_work = (not _clock.paused or bool(_clock._explicit_allow_paused)) and not _clock._save_boundary_held()


func note_driver_work(usec: int) -> void:
	_driver_usec += usec


func _process(_delta: float) -> void:
	if _done:
		return
	_bind_kernel()
	var now: int = Time.get_ticks_usec()
	var span: int = now - _last
	_frame_count += 1
	if span * 60 > 1000000:
		_over_60fps_budget += 1
	var world_id: int = _runtime.world_sim.get_instance_id()
	var running: bool = not _clock.paused and int(_clock.wait_target_ms) == 0
	if running and _was_running and world_id == _last_world_id and int(_clock.elapsed_ms) >= _last_world_ms:
		_running_usec += span
		_advanced_ms += int(_clock.elapsed_ms) - _last_world_ms
		_requested_ms += float(span) / 1000.0 * float(_clock.speed)
		_minimum_rate = minf(_minimum_rate, float(_clock.pacing.rate))
		if float(_clock.pacing.rate) < 0.97:
			_slow_usec += span
	var clock_usec: int = int(_clock.pacing.last_work_usec) if _sample_clock_work else 0
	_total_clock_usec += clock_usec
	_total_executor_usec += _frame_executor_usec
	_total_kernel_usec += _frame_kernel_usec
	_total_driver_usec += _driver_usec
	if _frames.size() < MAX_SAMPLES:
		_frames.append(float(span) / 1000.0)
		_clock_samples.append(float(clock_usec) / 1000.0)
		if _profile_render:
			_render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(_render_viewport))
			_render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_render_viewport))
			_render_setup.append(RenderingServer.get_frame_setup_time_cpu())
	if _spikes.size() < MAX_SPIKES or float(span) / 1000.0 > float(_spikes[-1].frame_ms):
		var row: Dictionary = _snapshot(now, clock_usec)
		row["frame_ms"] = float(span) / 1000.0
		row["top_kernel_usec"] = _top_frame()
		_spikes.append(row)
		_spikes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.frame_ms) > float(b.frame_ms))
		if _spikes.size() > MAX_SPIKES:
			_spikes.resize(MAX_SPIKES)
	if now - _window >= 1000000:
		var row: Dictionary = _snapshot(now, clock_usec)
		row["running_seconds"] = float(_running_usec) / 1000000.0
		row["world_ms"] = _advanced_ms
		row["top_kernel_cumulative"] = _scope_rows().slice(0, 8)
		_windows.store_line(JSON.stringify(row))
		_windows.flush()
		_window = Time.get_ticks_usec() # Report I/O is not a rule or simulated time.
	_frame_scopes.clear()
	_frame_executor_usec = 0
	_frame_kernel_usec = 0
	_driver_usec = 0
	_fog_updates = 0
	_last = now
	_last_world_ms = int(_clock.elapsed_ms)
	_last_world_id = world_id
	_was_running = running
	if not _runtime.world_sim.errors.is_empty() or now - _started >= int(_options.seconds) * 1000000:
		finish()


func _snapshot(now: int, clock_usec: int) -> Dictionary:
	var view = _main.get("world")
	return {"host_ms": (now - _started) / 1000.0, "clock_ms": clock_usec / 1000.0, "driver_ms": _driver_usec / 1000.0,
		"interval_ms": _frame_executor_usec / 1000.0, "kernel_ms": _frame_kernel_usec / 1000.0 if _profile_kernel else null,
		"interval_outside_kernel_ms": maxi(0, _frame_executor_usec - _frame_kernel_usec) / 1000.0 if _profile_kernel else null,
		"clock_outside_interval_ms": maxi(0, clock_usec - _frame_executor_usec) / 1000.0,
		"pace": _clock.pacing_status(), "pending_step": _runtime.world_sim.settlement.progress().step,
		"paused": _clock.paused, "waiting": int(_clock.wait_target_ms) > 0,
		"fog_updates": _fog_updates, "terrain_pending_load": view._pending_load.size(),
		"terrain_painting": view._painting_chunk.x >= 0,
		"terrain_dirty": maxi(0, view._dirty_order.size() - int(view._dirty_cursor)),
		"process_monitor_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"render_cpu_ms": _render_cpu.back() if not _render_cpu.is_empty() else null,
		"render_gpu_ms": _render_gpu.back() if not _render_gpu.is_empty() else null,
		"render_setup_cpu_ms": _render_setup.back() if not _render_setup.is_empty() else null,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}


func _top_frame() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: String in _frame_scopes:
		rows.append({"step": id, "usec": int(_frame_scopes[id])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.usec) > int(b.usec))
	return rows.slice(0, 8)


func _scope_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: String in _scopes:
		var row: Dictionary = _scopes[id].duplicate()
		row.erase("last_at_ms")
		row["step"] = id
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.total_usec) > int(b.total_usec))
	return rows


func _summary(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {}
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	return {"samples": sorted.size(), "p50": sorted[sorted.size() / 2], "p95": sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))], "p99": sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))], "max": sorted[-1]}


func finish() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	if _profile_render:
		RenderingServer.viewport_set_measure_render_time(_render_viewport, false)
	if _clock._interval_executor == Callable(self, "_execute"):
		_clock._interval_executor = _executor
	if _clock.time_advanced.is_connected(_published):
		_clock.time_advanced.disconnect(_published)
	_unwrap_kernel()
	if is_instance_valid(_main) and _main.get("fog").visibility_updated.is_connected(_fog_updated):
		_main.get("fog").visibility_updated.disconnect(_fog_updated)
	if get_tree().process_frame.is_connected(_before_frame):
		get_tree().process_frame.disconnect(_before_frame)
	_unprofile_navigation()
	_windows.close()
	var report: Dictionary = {"format": "demo_profile_v1", "revision": _options.revision, "dirty": _options.dirty,
		"debug_build": OS.is_debug_build(), "editor_build": OS.has_feature("editor"),
		"artifact_sha256": _options.get("artifact_sha256", ""),
		"kernel_timing_enabled": _profile_kernel,
		"render_timing_enabled": _profile_render,
		"pacing_policy": _options.get("pacing_policy", "auto"), "max_fps": Engine.max_fps,
		"engine": Engine.get_version_info().string, "renderer": RenderingServer.get_video_adapter_name(),
		"display": DisplayServer.get_name(), "assembly_ms": float(_options.assembly_usec) / 1000.0,
		"terrain_warmup_ms": float(_options.get("terrain_warmup_usec", 0)) / 1000.0,
		"terrain_warmup_complete": _options.get("terrain_warmup_complete"),
		"capture_seconds": (Time.get_ticks_usec() - _started) / 1000000.0,
		"running_seconds": _running_usec / 1000000.0, "world_ms": _advanced_ms,
		"requested_world_ms": _requested_ms, "achieved_fraction": _advanced_ms / _requested_ms if _requested_ms > 0.0 else null,
		"minimum_load_rate": _minimum_rate, "slow_seconds": _slow_usec / 1000000.0,
		"frame_ms": _summary(_frames), "clock_ms": _summary(_clock_samples),
		"frame_count": _frame_count, "frames_over_60fps_budget": _over_60fps_budget,
		"render_cpu_ms": _summary(_render_cpu), "render_gpu_ms": _summary(_render_gpu), "render_setup_cpu_ms": _summary(_render_setup),
		"work_totals_ms": {"clock": _total_clock_usec / 1000.0,
			"diagnostic_driver": _total_driver_usec / 1000.0,
			"runtime_interval": _total_executor_usec / 1000.0, "kernel_callbacks": _total_kernel_usec / 1000.0 if _profile_kernel else null,
			"interval_outside_kernel": maxi(0, _total_executor_usec - _total_kernel_usec) / 1000.0 if _profile_kernel else null},
		"execution_counts": {"executor_calls": _executor_calls, "executor_no_public_progress": _executor_no_progress,
			"world_boundaries": int(_runtime.world_sim.simulation_work.boundaries) - _initial_world_boundaries,
			"clock_publications": _clock_publications, "publication_span_ms": _summary(_publication_spans)},
		"kernel_scopes": _scope_rows(), "largest_frames": _spikes,
		"actor_execution": _actor_execution_summary(), "actor_execution_scope": "session_including_setup",
		"actor_execution_capture": _actor_execution_capture(),
		"actor_execution_capture_available": _runtime.world_sim.get_instance_id() == _initial_actor_world_id,
		"spatial_execution_capture": _counter_delta(_runtime.world_sim.conflicts.spatial_work, _initial_spatial_work) if _runtime.world_sim.get_instance_id() == _initial_actor_world_id else {},
		"geometry_read_capture": _counter_delta(_runtime.world_sim.geometry_read().work, _initial_geometry_work) if _runtime.world_sim.get_instance_id() == _initial_actor_world_id else {},
		"navigation_profile": {"enabled": _profile_navigation, "scope": "capture; native and service providers only; includes existing path cache hits; excludes conflict-space direct searches",
			"calls": _navigation_calls, "total_ms": _navigation_usec / 1000.0, "max_ms": _navigation_max_usec / 1000.0,
			"queries": _navigation_queries},
		"presentation_work": _runtime.presentation_work.diagnostics(),
		"world_errors": _runtime.world_sim.errors.duplicate(),
		"limits": "Instrumented process: check debug_build/editor_build for build type. Frame intervals include render/host waits. Optional kernel/render measurements add overhead; disabled timings are null/empty. Render timings are RenderingServer measurements of last available rendered frame, not this script's clock work; frame/GPU values must not be added. Interval residual includes scheduling and views. Fog/streaming flags indicate correlation. Paused/wait/load transitions excluded from achieved fraction. First 20000 frame samples; largest 24 frames retained."}
	if not report.world_errors.is_empty():
		var world: RegionalSimulation = _runtime.world_sim
		var fields: SimWorldEnvironmentFields = world.environment_fields as SimWorldEnvironmentFields
		if fields != null:
			report["failure_context"] = {"published_ms": _clock.elapsed_ms, "world_ms": world.elapsed_ms, "requested_ms": world.target_ms,
				"field_ms": fields.last_ms, "field_target_ms": fields._settle_cursor.get("target_ms"), "field_busy": fields._busy, "field_error": fields._error}
	var file := FileAccess.open(str(_options.report), FileAccess.WRITE)
	if file == null:
		push_error("Demo recorder cannot write its summary")
		finished.emit(false)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("DEMO_PROFILE ", _options.report, " achieved=", report.achieved_fraction, " top=", JSON.stringify(report.kernel_scopes.slice(0, 3)))
	finished.emit(report.world_errors.is_empty())


func _actor_execution_summary() -> Dictionary:
	var result: Dictionary = {}
	for id: String in _runtime.world_sim.regions:
		var sim: VillageSimulation = _runtime.world_sim.regions[id]
		result[id] = sim.actor_execution_work.duplicate(true)
		result[id]["configured_workers"] = sim.actor_execution_workers
		result[id]["minimum_rows"] = sim.actor_execution_minimum
		result[id]["owner_thread"] = OS.get_thread_caller_id()
	return result


func _actor_execution_capture() -> Dictionary:
	var result: Dictionary = {}
	if _runtime.world_sim.get_instance_id() != _initial_actor_world_id:
		return result # Replacement counters cannot be subtracted from the old world.
	for id: String in _runtime.world_sim.regions:
		var sim: VillageSimulation = _runtime.world_sim.regions[id]
		var before: Dictionary = _initial_actor_execution.get(id, {})
		result[id] = _counter_delta(sim.actor_execution_work, before)
	return result


func _counter_delta(current: Dictionary, initial: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in current:
		if current[key] is int:
			result[key] = int(current[key]) - int(initial.get(key, 0))
	return result
