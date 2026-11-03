extends SceneTree
## Repeatable standalone rendering/clock measurement; never loaded by the game.
## godot --path . --script res://tools/qa/profile_game.gd --resolution 1280x720 -- tag

const SAMPLE_FRAMES: int = 120
const WARMUP_MS: int = 1200
const FRAME_LIMIT: int = 120
const FIXTURE_PATH: String = "res://tests/fixtures/session_v11.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	var clock: Node = root.get_node("GameClock")
	while not main.world._pending_load.is_empty():
		await process_frame
	var results: Array[Dictionary] = []
	var original_vsync: int = DisplayServer.window_get_vsync_mode()
	var original_max: int = Engine.max_fps
	Engine.max_fps = FRAME_LIMIT
	for mode: int in [DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_DISABLED]:
		DisplayServer.window_set_vsync_mode(mode)
		if main._continuity.load_game(ProjectSettings.globalize_path(FIXTURE_PATH)) != OK:
			push_error("Profile could not load its real shared-time fixture")
			quit(1)
			return
		clock.set_paused(true)
		results.append(await _measure("world_static", clock, mode))
		clock.set_paused(false)
		results.append(await _measure("world_and_simulation_1x", clock, mode))
		clock.set_paused(true)
		main.world.hide()
		results.append(await _measure("terrain_hidden", clock, mode))
		main.world.show()
	var loaded_chunks: int = main.world._loaded.size()
	main.free()
	for mode: int in [DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_DISABLED]:
		DisplayServer.window_set_vsync_mode(mode)
		results.append(await _measure("blank_root", clock, mode))
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var tag: String = args[0].validate_filename() if not args.is_empty() else "default"
	var report: Dictionary = {
		"godot": Engine.get_version_info().string, "window": [root.size.x, root.size.y],
		"display": DisplayServer.get_name(), "samples_per_phase": SAMPLE_FRAMES,
		"native_window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"adapter": RenderingServer.get_video_adapter_name(), "vendor": RenderingServer.get_video_adapter_vendor(),
		"renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(),
		"loaded_chunks": loaded_chunks, "max_fps": Engine.max_fps, "results": results,
		"configured_vsync": original_vsync, "configured_max_fps": original_max,
		"scope": "standalone development process; same adapter and window, real v11 world; process monitor can include presentation wait and be stale while the scene tree is paused",
	}
	var file: FileAccess = FileAccess.open("res://logs/profile_%s.json" % tag, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	print("PROFILE %s" % JSON.stringify(report, "", true, true))
	DisplayServer.window_set_vsync_mode(original_vsync)
	Engine.max_fps = original_max
	quit(0)


func _measure(label: String, clock: Node, mode: int) -> Dictionary:
	var warm_until: int = Time.get_ticks_msec() + WARMUP_MS
	while Time.get_ticks_msec() < warm_until:
		await process_frame
	var clock_start: int = int(clock.elapsed_ms)
	var frames: Array[float] = []
	var process_cost: Array[float] = []
	var calls: Array[float] = []
	var previous: int = Time.get_ticks_usec()
	for _index in SAMPLE_FRAMES:
		await process_frame
		var now: int = Time.get_ticks_usec()
		frames.append(float(now - previous) / 1000.0)
		previous = now
		process_cost.append(1000.0 * Performance.get_monitor(Performance.TIME_PROCESS))
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	frames.sort()
	process_cost.sort()
	calls.sort()
	@warning_ignore("integer_division")
	var median_index: int = SAMPLE_FRAMES / 2
	return {"phase": label, "vsync": mode, "frame_median_ms": frames[median_index], "frame_p95_ms": frames[ceili(SAMPLE_FRAMES * 0.95) - 1],
		"process_median_ms": process_cost[median_index], "process_monitor_may_be_stale": bool(clock.paused), "draw_calls_median": calls[median_index],
		"clock_advanced_ms": int(clock.elapsed_ms) - clock_start}
