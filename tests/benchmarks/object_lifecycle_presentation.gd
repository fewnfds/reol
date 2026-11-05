extends SceneTree
## Native ordinary Main, real per-cell lifecycle objects, paused common time.
## Run with an external time/RSS guard; never use --headless. Example:
## godot --path . --script res://tests/benchmarks/object_lifecycle_presentation.gd -- --side 64
## Results and image are written under res://logs/world_lifecycle/ and are
## deliberately not overwritten on a subsequent run.

const SIDES: Array[int] = [64, 128, 256, 512]
const MAP_SIZE: int = 512
const MAP_SEED: int = 20261105
const BUILD_BATCH_CELLS: int = 64
const PROGRESS_CELLS: int = 4096
const WARMUP_FRAMES: int = 120
const SAMPLE_FRAMES: int = 1800
const OUTPUT_DIR: String = "res://logs/world_lifecycle"

var _main: Node
var _clock: Node
var _report: Dictionary = {
	"benchmark": "object_lifecycle_presentation",
	"ok": false,
	"scope": "standalone native ordinary Main, human opening, paused shared clock and real lifecycle placement",
	"limitations": [
		"Frame intervals include normal rendering, configured frame cap, vsync and operating-system scheduling; they are not an isolated GPU or simulation timing.",
		"Only one physical definition is generated. The square is centered on the starting player, and actual obstacles remain in place.",
		"Godot static memory excludes process RSS, driver allocations and GPU memory; an external time and memory guard is required.",
		"This is a paused-scene presentation measurement, not an active world simulation or a claim about full-game capacity."
	],
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var options: Dictionary = _arguments(OS.get_cmdline_user_args())
	if not bool(options.get("ok", false)):
		_fail("arguments", options)
		return
	if DisplayServer.get_name() == "headless":
		_fail("native_window_required")
		return
	var side: int = int(options.side)
	var prefix: String = OUTPUT_DIR + "/presentation-%d" % side + str(options.get("tag", ""))
	var png_path: String = prefix + ".png"
	var json_path: String = prefix + ".json"
	_report["side"] = side
	_report["requested_cells"] = side * side
	_report["map_seed"] = MAP_SEED
	_report["output_image"] = png_path
	_report["output_json"] = json_path
	if FileAccess.file_exists(png_path) or FileAccess.file_exists(json_path):
		_fail("output_exists", {"image": png_path, "json": json_path})
		return
	var output_absolute: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	var dir_error: Error = DirAccess.make_dir_recursive_absolute(output_absolute)
	if dir_error != OK and not DirAccess.dir_exists_absolute(output_absolute):
		_fail("output_directory", {"error": int(dir_error)})
		return

	# Autoloads must be looked up after SceneTree initialization. Loading Main
	# before the clock is registered can fail script compilation in --script mode.
	_clock = root.get_node_or_null("GameClock")
	if not is_instance_valid(_clock) or not _clock.has_method("set_paused"):
		_fail("game_clock_unavailable")
		return
	_clock.call("set_paused", true)
	if int(_clock.get("elapsed_ms")) != 0 or int(_clock.get("wait_target_ms")) != 0:
		_fail("fresh_clock_required")
		return
	_report["memory_static_before_main_bytes"] = OS.get_static_memory_usage()
	var setup_start: int = Time.get_ticks_usec()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var map_script: Variant = load("res://scripts/sim/world_map_data.gd")
	if packed == null or map_script == null:
		_fail("main_or_map_load")
		return
	_main = packed.instantiate()
	if not is_instance_valid(_main):
		_fail("main_instantiation")
		return
	var descriptor: Dictionary = map_script.flat_descriptor(MAP_SEED)
	if descriptor.is_empty() or int(descriptor.get("size", 0)) != MAP_SIZE or not bool(_main.call("configure_opening_map", descriptor)):
		_fail("flat_opening_configuration")
		return
	root.add_child(_main)
	current_scene = _main
	var runtime: Node = _main.get("_continuity")
	if not is_instance_valid(runtime) or runtime.get("world_sim") == null:
		_fail("ordinary_main_initialization")
		return
	var avatar: Node = runtime.get("avatar_adapter")
	if not is_instance_valid(avatar) or not bool(avatar.call("choose", "subject:player")):
		_fail("human_opening_selection")
		return
	# The normal choice unpauses; pause again before yielding a process frame.
	_clock.call("set_paused", true)
	var world: Variant = runtime.get("world_sim")
	var lifecycle: Variant = world.object_lifecycle
	var view: Node = runtime.get("object_adapter")
	if lifecycle == null or not is_instance_valid(view) or world.map_data == null or world.construction == null or not _clock_is_stable(world, 0):
		_fail("world_owners_or_clock")
		return
	_report["main_setup_wall_ms"] = _elapsed_ms(setup_start)
	_report["initial_artifacts"] = world.artifacts.objects.size()
	var initial_ground: int = int(lifecycle.ground.stats().active)
	_report["initial_active_ground"] = initial_ground
	var origin: Vector2i = runtime.call("controlled_cell")
	var min_cell := Vector2i(clampi(origin.x - (side >> 1), 0, MAP_SIZE - side), clampi(origin.y - (side >> 1), 0, MAP_SIZE - side))
	_report["player_cell"] = [origin.x, origin.y]
	_report["square_origin"] = [min_cell.x, min_cell.y]
	_report["generated"] = 0
	_report["blocked_terrain_cells"] = 0
	_report["blocked_built_structure_cells"] = 0
	_report["blocked_workspace_cells"] = 0
	_report["blocked_existing_ground_cells"] = 0
	var generation_start: int = Time.get_ticks_usec()
	var batch_start: int = generation_start
	var generation_active_usec: int = 0
	for y: int in range(min_cell.y, min_cell.y + side):
		for x: int in range(min_cell.x, min_cell.x + side):
			var cell := Vector2i(x, y)
			var index: int = (y - min_cell.y) * side + x - min_cell.x
			if not world.map_data.terrain_is_walkable(cell):
				_report.blocked_terrain_cells += 1
			elif world.construction.blocked(cell):
				if world.construction._blocked.has(cell):
					_report.blocked_built_structure_cells += 1
				else:
					_report.blocked_workspace_cells += 1
			else:
				var request: Dictionary = {"command": "presentation_spawn_%d" % index, "op": "spawn", "id": "presentation_slate_%d" % index,
					"definition": "plain_slate", "to": {"region": "home", "cell": [x, y]}}
				var result: Dictionary = lifecycle.execute(request)
				if bool(result.get("ok", false)):
					_report.generated += 1
				elif result.get("reason") == "ground_occupied":
					_report.blocked_existing_ground_cells += 1
				else:
					_fail("spawn_failed", {"cell": [x, y], "result": result})
					return
			if (index + 1) % BUILD_BATCH_CELLS == 0:
				generation_active_usec += Time.get_ticks_usec() - batch_start
				if (index + 1) % PROGRESS_CELLS == 0:
					print("PRESENTATION_BUILD_PROGRESS %d/%d created=%d" % [index + 1, side * side, int(_report.generated)])
				await process_frame
				batch_start = Time.get_ticks_usec()
				if not _clock_is_stable(world, 0):
					_fail("clock_changed_during_generation")
					return
	generation_active_usec += Time.get_ticks_usec() - batch_start
	_report["generation_wall_ms"] = _elapsed_ms(generation_start)
	_report["generation_batch_work_wall_ms"] = float(generation_active_usec) / 1000.0
	_report["generation_batch_size_cells"] = BUILD_BATCH_CELLS
	_report["memory_static_after_generation_bytes"] = OS.get_static_memory_usage()
	var blocked: int = int(_report.blocked_terrain_cells) + int(_report.blocked_built_structure_cells) + int(_report.blocked_workspace_cells) + int(_report.blocked_existing_ground_cells)
	if int(_report.generated) + blocked != side * side or int(lifecycle.ground.stats().active) != initial_ground + int(_report.generated) or world.artifacts.objects.size() != int(_report.initial_artifacts) + int(_report.generated):
		_fail("generation_count_mismatch", {"ground": lifecycle.ground.stats(), "objects": world.artifacts.objects.size()})
		return
	if int(_report.generated) == 0:
		_fail("no_real_objects_generated")
		return
	print("PRESENTATION_WARMUP %d frames" % WARMUP_FRAMES)
	for _frame: int in WARMUP_FRAMES:
		await process_frame
	if not _clock_is_stable(world, 0) or runtime.call("controlled_cell") != origin:
		_fail("clock_or_player_changed_during_warmup")
		return
	var frames_drawn_before: int = Engine.get_frames_drawn()
	var samples: Array[int] = []
	var previous: int = Time.get_ticks_usec()
	for _frame: int in SAMPLE_FRAMES:
		await process_frame
		var now: int = Time.get_ticks_usec()
		samples.append(now - previous)
		previous = now
	var frames_drawn_after: int = Engine.get_frames_drawn()
	if not _clock_is_stable(world, 0) or runtime.call("controlled_cell") != origin:
		_fail("clock_or_player_changed_during_sampling")
		return
	if frames_drawn_after <= frames_drawn_before:
		_fail("no_rendered_frames", {"before": frames_drawn_before, "after": frames_drawn_after})
		return
	samples.sort()
	_report["warmup_frames"] = WARMUP_FRAMES
	_report["sample_frames"] = SAMPLE_FRAMES
	_report["rendered_frames_during_sample"] = frames_drawn_after - frames_drawn_before
	_report["frame_interval_ms"] = {"p50": _percentile_ms(samples, 0.50), "p95": _percentile_ms(samples, 0.95), "p99": _percentile_ms(samples, 0.99), "max": float(samples.back()) / 1000.0}
	_report["shared_clock_ms"] = int(_clock.get("elapsed_ms"))
	_report["world_elapsed_ms"] = int(world.elapsed_ms)
	_report["world_target_ms"] = int(world.target_ms)
	_report["ground_stats"] = lifecycle.ground.stats()
	_report["actual_artifacts"] = world.artifacts.objects.size()
	var radius: int = int(world.regions[world.artifacts.actor_home("player")].config.observation_radius)
	var candidates: Dictionary = lifecycle.artifact_candidates(origin, radius)
	if not bool(candidates.get("ok", false)):
		_fail("visible_candidate_query", candidates)
		return
	var visible: Dictionary = view.call("_visible_display_points", world)
	var visible_managed: int = 0
	for id: String in visible:
		if id.begins_with("presentation_slate_") and lifecycle.manages(id):
			visible_managed += 1
	_report["nearby_candidate_count"] = candidates.ids.size()
	_report["nearby_query_work_used"] = candidates.get("work_used", null)
	_report["visible_artifact_count"] = visible.size()
	_report["visible_generated_count"] = visible_managed
	if visible_managed == 0:
		_fail("no_generated_objects_visible")
		return
	_report["engine"] = Engine.get_version_info()
	_report["operating_system"] = OS.get_name()
	_report["processor"] = OS.get_processor_name()
	_report["logical_processors"] = OS.get_processor_count()
	_report["display_server"] = DisplayServer.get_name()
	_report["video_adapter"] = RenderingServer.get_video_adapter_name()
	_report["video_vendor"] = RenderingServer.get_video_adapter_vendor()
	_report["video_driver_info"] = Array(OS.get_video_adapter_driver_info())
	_report["video_api_version"] = RenderingServer.get_video_adapter_api_version()
	_report["rendering_method"] = RenderingServer.get_current_rendering_method()
	_report["rendering_driver"] = RenderingServer.get_current_rendering_driver_name()
	var window_size: Vector2i = DisplayServer.window_get_size()
	_report["window_size"] = [window_size.x, window_size.y]
	_report["viewport_size"] = [root.size.x, root.size.y]
	_report["max_fps"] = Engine.max_fps
	_report["vsync_mode"] = DisplayServer.window_get_vsync_mode()
	_report["debug_build"] = OS.is_debug_build()
	_report["memory_static_end_bytes"] = OS.get_static_memory_usage()
	_report["memory_static_peak_bytes"] = OS.get_static_memory_peak_usage()
	# Capture exactly once, only after the sampled native scene has rendered.
	await RenderingServer.frame_post_draw
	if not _clock_is_stable(world, 0) or runtime.call("controlled_cell") != origin or FileAccess.file_exists(png_path) or FileAccess.file_exists(json_path):
		_fail("clock_changed_or_output_created_before_capture")
		return
	var capture: Image = root.get_texture().get_image()
	if capture == null or capture.is_empty():
		_fail("empty_viewport_capture")
		return
	var image_error: Error = capture.save_png(png_path)
	if image_error != OK:
		_fail("save_image", {"error": int(image_error)})
		return
	if FileAccess.file_exists(json_path):
		_fail("output_exists_after_capture", {"path": json_path})
		return
	_report["ok"] = true
	var file: FileAccess = FileAccess.open(json_path, FileAccess.WRITE)
	if file == null:
		_fail("save_report", {"error": int(FileAccess.get_open_error())})
		return
	file.store_string(JSON.stringify(_report, "\t", true, true))
	file.close()
	print("PRESENTATION_BENCHMARK_JSON:" + JSON.stringify(_report, "", true, true))
	_main.free()
	_main = null
	quit(0)


func _arguments(args: PackedStringArray) -> Dictionary:
	if args.is_empty():
		return {"ok": true, "side": 64, "tag": ""}
	if args.size() not in [2, 4] or args[0] != "--side" or not args[1].is_valid_int():
		return {"ok": false, "reason": "expected --side N [--tag unique_name]"}
	var side: int = int(args[1])
	if side not in SIDES:
		return {"ok": false, "reason": "unsupported side", "side": side}
	var tag: String = ""
	if args.size() == 4:
		if args[2] != "--tag" or args[3].length() < 1 or args[3].length() > 32:
			return {"ok": false, "reason": "invalid tag"}
		for character: String in args[3]:
			if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
				return {"ok": false, "reason": "invalid tag"}
		tag = "-" + args[3]
	return {"ok": true, "side": side, "tag": tag}


func _clock_is_stable(world: Variant, expected: int) -> bool:
	return bool(_clock.get("paused")) and int(_clock.get("elapsed_ms")) == expected and int(world.elapsed_ms) == expected and int(world.target_ms) == expected


func _percentile_ms(sorted: Array[int], percentile: float) -> float:
	var index: int = clampi(ceili(float(sorted.size()) * percentile) - 1, 0, sorted.size() - 1)
	return float(sorted[index]) / 1000.0


func _elapsed_ms(start: int) -> float:
	return float(Time.get_ticks_usec() - start) / 1000.0


func _fail(reason: String, detail: Dictionary = {}) -> void:
	_report["ok"] = false
	_report["first_failure"] = {"reason": reason, "detail": detail}
	print("PRESENTATION_BENCHMARK_JSON:" + JSON.stringify(_report, "", true, true))
	if is_instance_valid(_main):
		_main.free()
		_main = null
	quit(1)
