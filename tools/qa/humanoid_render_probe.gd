extends SceneTree
## Standalone visible-window presentation probe. No game world is constructed.
## Frame spacing includes this debug process, rendering, OS scheduling and its
## configured limiter. CPU command timers are not GPU frame measurements.

const WARMUP_FRAMES: int = 120
const SAMPLE_FRAMES: int = 240
const VIEW_COUNT: int = 48
const SIZE: Vector2i = Vector2i(1280, 720)
const REPORT_PATH: String = "res://logs/humanoid_render_probe.json"
const IMAGE_PATH: String = "res://logs/humanoid_render_probe_48.png"

var _views: Array[Node2D] = []
var _clock: PresentationClock
var _report: Dictionary = {}


class ProbeView extends Node2D:
	var pose: Dictionary = {}
	var clothes: Dictionary = {}
	var caption: String = ""
	var robe: Color = Color("#827861")
	var selected: bool = false
	var last_draw_cpu_us: int = 0


	func _draw() -> void:
		var started: int = Time.get_ticks_usec()
		PawnVisuals.draw_actor(self, Vector2.ZERO, Vector2.ZERO, robe, caption, selected, false, clothes, pose)
		last_draw_cpu_us = Time.get_ticks_usec() - started


class PresentationClock extends Node:
	var views: Array[Node2D] = []
	var frame: int = 0
	var last_update_cpu_us: int = 0


	func _process(_delta: float) -> void:
		var started: int = Time.get_ticks_usec()
		frame += 1
		# An explicit presentation-only 120Hz test timeline. It never advances
		# GameClock, a character, an item, or a simulation transaction.
		@warning_ignore("integer_division")
		var at_ms: int = frame * 1000 / 120
		for view: ProbeView in views:
			view.pose.time_ms = at_ms
			view.queue_redraw()
		last_update_cpu_us = Time.get_ticks_usec() - started


func _initialize() -> void:
	print("Humanoid render probe: custom SceneTree initialized.")
	call_deferred("_run_probe")


func _run_probe() -> void:
	print("Humanoid render probe: preparing actual window.")
	if DisplayServer.get_name() == "headless":
		printerr("Humanoid render probe requires a real window; headless cannot verify rendering.")
		quit(1)
		return
	root.title = "Reol A1 / 48 visible human views / presentation-only probe"
	root.size = SIZE
	var original_clock: Node = root.get_node_or_null("GameClock")
	if original_clock != null:
		original_clock.set_process(false)
	_clock = PresentationClock.new()
	root.add_child(_clock)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs"))
	_report = {
		"engine": Engine.get_version_info(), "os": OS.get_name(), "cpu": OS.get_processor_name(),
		"adapter": RenderingServer.get_video_adapter_name(), "adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"display_server": DisplayServer.get_name(), "window_size": [SIZE.x, SIZE.y],
		"debug_build": OS.is_debug_build(), "editor_hint": Engine.is_editor_hint(),
		"vsync_mode": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps,
		"warmup_frames": WARMUP_FRAMES, "samples_per_phase": SAMPLE_FRAMES,
		"test_time": "presentation-only 120Hz frame index; no game world or simulation tick",
		"scope": "standalone debug window; 48 Node2D views of shared family; captions, shadow, selection and optional visual parts included",
		"monitor_limits": "Performance monitors may update up to 1 second late; TIME_PROCESS is engine main process timing, not isolated character CPU; CPU timers cover script command creation only; GPU time is not measured",
		"baseline": {}, "crowd": {},
	}
	_report.baseline = await _measure("empty_window")
	var family: HumanoidAppearance = HumanoidAppearance.shared()
	if not family.diagnostics.is_empty() or family.textures.size() != 9:
		printerr("Humanoid render probe cannot draw the full family: " + str(family.diagnostics))
		quit(1)
		return
	_build_crowd()
	_report.crowd = await _measure("48_visible_humans")
	_report["frame_spacing_delta_p50_ms"] = float(_report.crowd.frame_spacing_ms.p50) - float(_report.baseline.frame_spacing_ms.p50)
	_report["frame_spacing_delta_p95_ms"] = float(_report.crowd.frame_spacing_ms.p95) - float(_report.baseline.frame_spacing_ms.p95)
	_report["process_monitor_delta_p50_ms"] = float(_report.crowd.process_monitor_ms.p50) - float(_report.baseline.process_monitor_ms.p50)
	_report["texture_memory_delta_bytes"] = int(_report.crowd.texture_memory_bytes.p50) - int(_report.baseline.texture_memory_bytes.p50)
	await RenderingServer.frame_post_draw
	var screenshot: Image = root.get_texture().get_image()
	var image_result: Error = screenshot.save_png(ProjectSettings.globalize_path(IMAGE_PATH))
	_report["image_path"] = IMAGE_PATH
	_report["image_result"] = image_result
	_report["image_size"] = [screenshot.get_width(), screenshot.get_height()]
	var file: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null or image_result != OK:
		printerr("Humanoid render probe could not persist its report or screenshot.")
		quit(1)
		return
	file.store_string(JSON.stringify(_report, "\t", true, true))
	file.flush()
	file.close()
	print("HUMANOID RENDER PROBE " + JSON.stringify(_report, "", true, true))
	print("Report: " + REPORT_PATH + " | Contact grid: " + IMAGE_PATH)
	quit(0)


func _build_crowd() -> void:
	var heading := Label.new()
	heading.text = "A1 / 48 original technical human views / eight independent directions"
	heading.position = Vector2(26, 16)
	heading.add_theme_font_size_override("font_size", 21)
	root.add_child(heading)
	var note := Label.new()
	note.text = "Rows: idle / walk / gesture, repeated with real-view outer projection. Sword and jade are technical previews only."
	note.position = Vector2(26, 45)
	note.add_theme_font_size_override("font_size", 14)
	root.add_child(note)
	var colors: Array[Color] = [Color("#827861"), Color("#345b79"), Color("#b23a2f")]
	for index: int in VIEW_COUNT:
		@warning_ignore("integer_division")
		var row: int = index / 8
		var direction: int = index % 8
		var action: String = ["idle", "walk", "gesture"][row % 3]
		var view := ProbeView.new()
		view.name = "HumanView_%02d" % index
		view.position = Vector2(80 + direction * 160, 128 + row * 99)
		view.scale = Vector2(1.3, 1.3)
		view.pose = {"direction_index": direction, "time_ms": 0, "started_ms": 0,
			"action": action, "moving": action == "walk", "technical_accessories": true}
		view.robe = colors[row % colors.size()]
		view.clothes = {"body": {"shape": "robe", "color": "#" + view.robe.to_html(false), "wet": row == 1}}
		if row >= 3:
			view.clothes["outer"] = {"shape": "cape", "color": "#99834e", "wet": false}
		view.caption = "%s / %s" % [HumanoidAppearance.DIRECTIONS[direction], action]
		view.selected = index % 9 == 0
		root.add_child(view)
		_views.append(view)
	_clock.views.assign(_views)
	_clock.frame = 0


func _measure(label: String) -> Dictionary:
	print("Humanoid render probe: warming " + label)
	for _index: int in WARMUP_FRAMES:
		await process_frame
	var spacing: Array[float] = []
	var process_cpu: Array[float] = []
	var draw_commands: Array[float] = []
	var update_commands: Array[float] = []
	var draw_calls: Array[float] = []
	var texture_memory: Array[float] = []
	var video_memory: Array[float] = []
	var previous: int = Time.get_ticks_usec()
	for _index: int in SAMPLE_FRAMES:
		await process_frame
		var now: int = Time.get_ticks_usec()
		spacing.append(float(now - previous) / 1000.0)
		previous = now
		process_cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		var script_us: int = 0
		for view: ProbeView in _views:
			script_us += view.last_draw_cpu_us
		draw_commands.append(float(script_us) / 1000.0)
		update_commands.append(float(_clock.last_update_cpu_us) / 1000.0)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		texture_memory.append(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
		video_memory.append(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	var result: Dictionary = {"label": label, "frames": SAMPLE_FRAMES,
		"frame_spacing_ms": _summary(spacing), "process_monitor_ms": _summary(process_cpu),
		"draw_command_script_cpu_ms": _summary(draw_commands), "pose_update_script_cpu_ms": _summary(update_commands),
		"draw_calls": _summary(draw_calls), "texture_memory_bytes": _summary(texture_memory), "video_memory_bytes": _summary(video_memory)}
	print("Humanoid render phase " + JSON.stringify(result, "", true, true))
	return result


func _summary(values: Array[float]) -> Dictionary:
	values.sort()
	var count: int = values.size()
	return {"p50": values[int(float(count - 1) * 0.50)], "p95": values[int(float(count - 1) * 0.95)],
		"minimum": values[0], "maximum": values[count - 1]}
