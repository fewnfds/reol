extends SceneTree
## Standalone native Main probe. The ordinary new-world scenario and human
## opening choice are used; no existing save is loaded and no save is written.
## Launch under an external 30-second process guard. This script checks a
## 20-second monotonic deadline and also installs a real-time SceneTree timer.

const MAIN_PATH: String = "res://scenes/main.tscn"
const WARMUP_FRAMES: int = 30
const SAMPLE_FRAMES: int = 180
const TIMEOUT_US: int = 20000000

var _started_us: int = 0
var _done: bool = false
var _clock: Node
var _main: Node
var _runtime: Node
var _world: Node
var _original_paused: bool = false
var _original_speed: float = 1.0
var _clock_captured: bool = false


func _initialize() -> void:
	_started_us = Time.get_ticks_usec()
	call_deferred("_run")


func _run() -> void:
	if _expired("starting"):
		return
	var remaining_seconds: float = maxf(0.000001, float(TIMEOUT_US - (Time.get_ticks_usec() - _started_us)) / 1000000.0)
	create_timer(remaining_seconds, true, false, true).timeout.connect(_on_timeout)
	if DisplayServer.get_name() == "headless":
		_fail("this probe requires a native rendering window")
		return
	_clock = root.get_node_or_null("GameClock")
	if not is_instance_valid(_clock) or not _clock.has_method("set_paused") or not _clock.has_method("set_speed"):
		_fail("the ordinary GameClock autoload is unavailable")
		return
	_original_paused = bool(_clock.get("paused"))
	_original_speed = float(_clock.get("speed"))
	_clock_captured = true
	_clock.call("set_paused", true)
	if int(_clock.get("elapsed_ms")) != 0 or int(_clock.get("wait_target_ms")) != 0:
		_fail("a fresh zero-time clock without a pending wait is required")
		return

	# Load only after the autoload exists. No fixture archive or user save is
	# consulted: Main assembles its own ordinary default new-world scenario.
	var packed: PackedScene = load(MAIN_PATH)
	if packed == null:
		_fail("ordinary Main scene could not be loaded")
		return
	_main = packed.instantiate()
	if not is_instance_valid(_main):
		_fail("ordinary Main scene could not be instantiated")
		return
	root.add_child(_main)
	current_scene = _main
	if _expired("assembling Main"):
		return
	_runtime = _main.get("_continuity")
	_world = _main.get("world")
	if not is_instance_valid(_runtime) or not is_instance_valid(_world) or not is_instance_valid(_runtime.get("world_sim")):
		_fail("ordinary Main did not assemble its world and regional simulation")
		return
	var avatar: Node = _runtime.get("avatar_adapter")
	if not is_instance_valid(avatar) or not avatar.has_method("choose") or not bool(avatar.call("choose", "subject:player")):
		_fail("the ordinary new-world human opening could not be selected")
		return
	if _expired("selecting the human opening"):
		return
	if not _runtime.has_method("human_player_active") or not bool(_runtime.call("human_player_active")):
		_fail("the selected opening is not the human player")
		return
	_clock.call("set_speed", 1.0)
	_clock.call("set_paused", true)
	if not bool(_clock.get("paused")) or int(_clock.get("elapsed_ms")) != 0:
		_fail("the new human opening did not remain paused at time zero")
		return
	print("WORLD_FRAME_PROBE_PROGRESS: human new world assembled")

	var paused_phase: Dictionary = await _measure_phase("paused", true)
	if _done or paused_phase.is_empty():
		return
	_clock.call("set_paused", false)
	var running_phase: Dictionary = await _measure_phase("running_1x", false)
	if _done or running_phase.is_empty():
		return
	if _expired("completing report"):
		return

	var window_size: Vector2i = DisplayServer.window_get_size()
	var report: Dictionary = {
		"version": 1,
		"fixture": "ordinary default new Main world; selected subject:player; no archive loaded or saved",
		"engine": Engine.get_version_info(),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"window_size": [window_size.x, window_size.y],
		"viewport_size": [root.size.x, root.size.y],
		"os": OS.get_name(), "processor": OS.get_processor_name(), "logical_processors": OS.get_processor_count(),
		"max_fps": Engine.max_fps,
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"debug_build": OS.is_debug_build(),
		"warmup_stable_frames_per_phase": WARMUP_FRAMES,
		"sample_frames_per_phase": SAMPLE_FRAMES,
		"timeout_seconds": float(TIMEOUT_US) / 1000000.0,
		"wall_ms": float(Time.get_ticks_usec() - _started_us) / 1000.0,
		"phases": [paused_phase, running_phase],
		"limitations": [
			"One native process and the ordinary new human opening; this is not a large-world, combat, population-scale or general FPS capacity test.",
			"The paused and running phases are sequential; only the running phase advances through the normal 1x GameClock.",
			"Frame intervals use monotonic process-frame signals and include rendering, scheduling, configured frame cap and this probe's monitoring overhead.",
			"Performance monitors can update less often than frames and may be stale while paused; static memory is unavailable in release builds and is not process peak memory.",
			"Canvas viewport render counters describe the previous rendered frame; zero can also mean the renderer did not provide the statistic.",
			"The monotonic deadline and real-time timer run when the main thread yields; the external guard is required for a blocked main thread."
		],
	}
	print("WORLD_FRAME_PROBE_JSON:" + JSON.stringify(report, "", true, true))
	_finish(0)


func _measure_phase(label: String, expect_paused: bool) -> Dictionary:
	print("WORLD_FRAME_PROBE_PROGRESS: %s warmup" % label)
	var stable: int = 0
	var warmup_frames: int = 0
	var warmup_start_clock: int = int(_clock.get("elapsed_ms"))
	var last_drawn: int = Engine.get_frames_drawn()
	while stable < WARMUP_FRAMES:
		await process_frame
		if _expired(label + " warmup"):
			return {}
		if not _valid_phase(expect_paused):
			_fail(label + " phase lost its world or expected pause state")
			return {}
		warmup_frames += 1
		var drawn: int = Engine.get_frames_drawn()
		if _presentation_idle() and drawn > last_drawn:
			stable += 1
		else:
			stable = 0
		last_drawn = drawn
		if warmup_frames % 120 == 0:
			print("WORLD_FRAME_PROBE_PROGRESS: %s warmup_frames=%d stable=%d" % [label, warmup_frames, stable])
	var start_world: Dictionary = _snapshot()
	if start_world.is_empty() or int(start_world.errors) != 0:
		_fail(label + " phase could not inspect a healthy ordinary world")
		return {}
	var clock_before: int = int(_clock.get("elapsed_ms"))
	var frames_drawn_before: int = Engine.get_frames_drawn()
	var viewport_rid: RID = root.get_viewport_rid()
	var render_info_available: bool = viewport_rid.is_valid() and frames_drawn_before >= 2
	var frame_ms: Array[float] = []
	var process_ms: Array[float] = []
	var physics_ms: Array[float] = []
	var node_counts: Array[float] = []
	var static_memory_bytes: Array[float] = []
	var canvas_objects: Array[float] = []
	var canvas_primitives: Array[float] = []
	var canvas_draw_calls: Array[float] = []
	var unsettled_frames: int = 0
	var previous: int = Time.get_ticks_usec()
	for _index: int in SAMPLE_FRAMES:
		await process_frame
		if _expired(label + " sampling"):
			return {}
		if not _valid_phase(expect_paused):
			_fail(label + " phase changed pause state or lost its world while sampling")
			return {}
		var now: int = Time.get_ticks_usec()
		frame_ms.append(float(now - previous) / 1000.0)
		previous = now
		process_ms.append(1000.0 * Performance.get_monitor(Performance.TIME_PROCESS))
		physics_ms.append(1000.0 * Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
		node_counts.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		static_memory_bytes.append(Performance.get_monitor(Performance.MEMORY_STATIC))
		if render_info_available:
			canvas_objects.append(float(RenderingServer.viewport_get_render_info(viewport_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)))
			canvas_primitives.append(float(RenderingServer.viewport_get_render_info(viewport_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)))
			canvas_draw_calls.append(float(RenderingServer.viewport_get_render_info(viewport_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)))
		if not _presentation_idle():
			unsettled_frames += 1
	var clock_after: int = int(_clock.get("elapsed_ms"))
	var end_world: Dictionary = _snapshot()
	if end_world.is_empty() or int(end_world.errors) != 0:
		_fail(label + " phase lost its world or recorded simulation errors")
		return {}
	if int(start_world.target_ms) > clock_before or int(end_world.target_ms) > clock_after:
		_fail(label + " phase has a world target beyond its original clock")
		return {}
	if expect_paused and (clock_after != clock_before or int(end_world.elapsed_ms) != int(start_world.elapsed_ms)):
		_fail("paused phase unexpectedly advanced the shared world clock")
		return {}
	if not expect_paused and (clock_after <= clock_before or int(end_world.elapsed_ms) <= int(start_world.elapsed_ms)):
		_fail("normal running frames did not advance the original clock and simulation")
		return {}
	var render_info: Dictionary = {"available": render_info_available,
		"source": "RenderingServer viewport canvas counters, previous rendered frame",
		"zero_may_mean_unavailable": true}
	if render_info_available:
		render_info["objects_in_frame"] = _distribution(canvas_objects)
		render_info["primitives_in_frame"] = _distribution(canvas_primitives)
		render_info["draw_calls_in_frame"] = _distribution(canvas_draw_calls)
	print("WORLD_FRAME_PROBE_PROGRESS: %s samples=%d" % [label, frame_ms.size()])
	return {"phase": label, "paused": expect_paused, "speed": float(_clock.get("speed")),
		"warmup_frames_waited": warmup_frames, "consecutive_stable_warmup_frames": stable,
		"warmup_clock_before_ms": warmup_start_clock, "warmup_clock_after_ms": clock_before,
		"samples": frame_ms.size(), "frames_drawn_during_samples": Engine.get_frames_drawn() - frames_drawn_before,
		"streaming_unsettled_sample_frames": unsettled_frames,
		"clock_before_ms": clock_before, "clock_after_ms": clock_after, "clock_advanced_ms": clock_after - clock_before,
		"world_before": start_world, "world_after": end_world,
		"clock_world_lag_before_ms": clock_before - int(start_world.elapsed_ms),
		"clock_world_lag_after_ms": clock_after - int(end_world.elapsed_ms),
		"process_frame_interval_ms": _distribution(frame_ms),
		"performance_monitors": {
			"time_process_ms": _distribution(process_ms), "time_physics_process_ms": _distribution(physics_ms),
			"object_node_count": _distribution(node_counts),
			"memory_static_bytes": {"available_in_this_build": OS.is_debug_build(), "samples": _distribution(static_memory_bytes)}},
		"render_info": render_info}


func _valid_phase(expected_paused: bool) -> bool:
	return is_instance_valid(_clock) and is_instance_valid(_main) and is_instance_valid(_runtime) and is_instance_valid(_world) and bool(_clock.get("paused")) == expected_paused and paused == expected_paused


func _presentation_idle() -> bool:
	# Read bounded queue lengths only; never scan world cells or entities here.
	var pending_load: Array = _world.get("_pending_load")
	var pending_unload: Array = _world.get("_pending_unload")
	var priority_cells: Array = _world.get("_priority_cells")
	var dirty_order: Array = _world.get("_dirty_order")
	var painting: Vector2i = _world.get("_painting_chunk")
	return pending_load.is_empty() and pending_unload.is_empty() and painting.x < 0 and int(_world.get("_priority_index")) >= priority_cells.size() and int(_world.get("_dirty_cursor")) >= dirty_order.size()


func _snapshot() -> Dictionary:
	# World/region counts and heat storage are inspected only at phase bounds.
	var simulation: Object = _runtime.get("world_sim")
	if not is_instance_valid(simulation):
		return {}
	var regions: Dictionary = simulation.get("regions")
	var per_region: Dictionary = {}
	var actor_count: int = 0
	for region_id: Variant in regions:
		var region: Object = regions[region_id]
		if not is_instance_valid(region):
			return {}
		var actors: Dictionary = region.get("actors")
		per_region[str(region_id)] = actors.size()
		actor_count += actors.size()
	var heat: Object = simulation.get("environment_fields")
	var artifacts: Object = simulation.get("artifacts")
	var map: Object = simulation.get("map_data")
	if not is_instance_valid(heat) or not heat.has_method("cell_count") or not heat.has_method("storage_summary") or not is_instance_valid(artifacts) or not is_instance_valid(map) or not map.has_method("descriptor"):
		return {}
	var objects: Dictionary = artifacts.get("objects")
	var loaded: Dictionary = _world.get("_loaded")
	var pending: Array = _world.get("_pending_load")
	var pending_unload: Array = _world.get("_pending_unload")
	var priority_cells: Array = _world.get("_priority_cells")
	var dirty_order: Array = _world.get("_dirty_order")
	var painting: Vector2i = _world.get("_painting_chunk")
	var errors: Array = simulation.get("errors")
	var elapsed_ms: int = int(simulation.get("elapsed_ms"))
	var target_ms: int = int(simulation.get("target_ms"))
	return {"elapsed_ms": elapsed_ms, "target_ms": target_ms,
		"owed_world_ms": maxi(0, target_ms - elapsed_ms), "region_count": regions.size(),
		"actor_count": actor_count, "actor_count_by_region": per_region,
		"artifact_objects": objects.size(), "heat_cells": int(heat.call("cell_count")),
		"heat_storage": heat.call("storage_summary"), "loaded_chunks": loaded.size(),
		"pending_load_chunks": pending.size(), "pending_unload_chunks": pending_unload.size(),
		"painting_chunk_active": painting.x >= 0,
		"priority_cells_remaining": maxi(0, priority_cells.size() - int(_world.get("_priority_index"))),
		"dirty_cells_remaining": maxi(0, dirty_order.size() - int(_world.get("_dirty_cursor"))),
		"map": map.call("descriptor"), "errors": errors.size()}


func _distribution(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"samples": 0}
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return {"samples": sorted.size(), "p50": _percentile(sorted, 0.50),
		"p95": _percentile(sorted, 0.95), "p99": _percentile(sorted, 0.99), "max": sorted[-1]}


func _percentile(sorted: Array[float], fraction: float) -> float:
	return sorted[maxi(0, ceili(float(sorted.size()) * fraction) - 1)]


func _expired(stage: String) -> bool:
	if _done:
		return true
	if Time.get_ticks_usec() - _started_us >= TIMEOUT_US:
		_fail("20-second monotonic deadline exceeded during " + stage)
		return true
	return false


func _on_timeout() -> void:
	if not _done:
		_fail("20-second real-time watchdog expired")


func _fail(message: String) -> void:
	if _done:
		return
	push_error("WORLD_FRAME_PROBE_ERROR: " + message)
	_finish(1)


func _finish(exit_code: int) -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(_clock) and _clock_captured:
		_clock.call("set_paused", true)
	if is_instance_valid(_main):
		current_scene = null
		_main.queue_free()
	if is_instance_valid(_clock) and _clock_captured:
		_clock.call("set_speed", _original_speed)
		_clock.call("set_paused", _original_paused)
	quit(exit_code)
