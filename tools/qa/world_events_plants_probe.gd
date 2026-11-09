extends SceneTree
## Native Main acceptance. Run, stop the process, then run with -- --resume.
## Uses its own test save; never reads or replaces the player's ordinary slot.
const REPORT: String = "res://logs/world-events-plants-native.json"
var clock
var main: Node
var runtime
var failures: Array[String] = []
var receipts: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		push_error("World events and plants probe timed out")
		quit(1)
	)
	if DisplayServer.get_name() == "headless":
		push_error("This acceptance requires native rendering")
		quit(1)
		return
	Engine.max_fps = 60
	clock = root.get_node("GameClock")
	clock.set_paused(true)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	runtime = main.get("_continuity")
	if runtime == null:
		push_error("Main did not assemble continuity")
		quit(1)
		return
	_expect(runtime._panel.save_requested.is_connected(runtime.home_runtime().request_save), "ordinary save button uses the queued session entry")
	if "--resume" in OS.get_cmdline_user_args():
		await _resume()
		return
	_expect(runtime.avatar_adapter.choose("subject:player"), "ordinary human opening is selected")
	clock.set_paused(true)
	_expect(runtime.world_sim.plants.bodies.size() >= 6, "ordinary Main assembles original resource plants and representative specimens")
	_expect(runtime.world_sim.plants.bodies["opening:old_tree"].subject.is_empty(), "the old tree starts without an invented mind")
	runtime.settings.event_budget = 4096
	runtime.settlement_work_budget = 4096
	var due_started: int = Time.get_ticks_usec()
	clock.advance_msec(60000)
	var awaken_frames: int = 0
	while clock.has_pending_advance() and awaken_frames < 3000:
		awaken_frames += 1
		await process_frame
	_expect(not clock.has_pending_advance(), "a real minute settles without losing accepted time")
	var due_wall_ms: float = float(Time.get_ticks_usec() - due_started) / 1000.0
	_expect(runtime.world_sim.plants.bodies["opening:old_tree"].subject == "subject:plant:opening:old_tree", "the global event awakens the same original tree")
	var sample: Vector2i = runtime.world_sim.plants.cell_of("opening:fire_herb")
	_expect(runtime.natural_adapter.observe(sample), "ordinary right-click observation can select the visible sample")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://logs/world-events-plants-observation.png")
	_expect(runtime.travel_to("river"), "original body starts a real inter-region journey")
	runtime.settings.event_budget = 1
	runtime.settlement_work_budget = 1
	clock.advance_msec(75)
	_expect(clock.has_pending_advance(), "the original clock has budgeted work when saving is requested")
	var path: String = "user://tests/world_events_plants_native_%d.json" % Time.get_ticks_usec()
	runtime.save_finished.connect(func(_path: String, result: Error) -> void: receipts.append(result))
	_expect(runtime.home_runtime().request_save(path) == OK, "ordinary save entry accepts the request")
	_expect(receipts.is_empty() and not FileAccess.file_exists(path), "request acceptance does not claim a written file")
	clock.set_paused(true)
	var frames: int = 0
	while runtime._saves.pending() and frames < 1000:
		frames += 1
		await process_frame
	_expect(receipts == [OK], "the native frame loop emits exactly one successful receipt")
	_expect(clock.elapsed_ms == 60075 and clock.paused and not clock.has_pending_advance(), "save drains exactly the accepted time while preserving user pause")
	var checkpoint: String = _hash()
	runtime.settings.event_budget = 4096
	runtime.settlement_work_budget = 4096
	clock.advance_msec(250)
	_expect(not clock.has_pending_advance(), "reference future reaches a complete boundary")
	var future: String = _hash()
	_expect(runtime.load_game(path) == OK, "ordinary loader accepts the newly written session")
	_expect(_hash() == checkpoint, "same-process loading preserves the entire checkpoint")
	runtime.settings.event_budget = 4096
	clock.advance_msec(250)
	_expect(_hash() == future, "same-process loading preserves the entire future")
	var performance: Dictionary = await _measure_running()
	performance["minute_advance_wall_ms"] = due_wall_ms
	performance["minute_advance_yield_frames"] = awaken_frames
	main.get("hud")._diagnostics.show()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://logs/world-events-plants-native.png")
	var report: Dictionary = {"engine": Engine.get_version_info().string, "renderer": RenderingServer.get_video_adapter_name(),
		"save": path, "drain_frames": frames, "checkpoint": checkpoint, "future": future, "performance": performance, "failures": failures}
	var file: FileAccess = FileAccess.open(REPORT, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("WORLD_EVENTS_PLANTS_NATIVE ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


func _measure_running() -> Dictionary:
	var view: Node = main.get("world")
	var streamed_frames: int = 0
	while not _stream_idle(view) and streamed_frames < 1000:
		streamed_frames += 1
		await process_frame
	_expect(_stream_idle(view), "the bounded frame sample starts after ordinary terrain streaming")
	clock.set_paused(false)
	for _frame: int in 60:
		await process_frame
	var samples: Array[float] = []
	var previous: int = Time.get_ticks_usec()
	var started: int = int(clock.elapsed_ms)
	var max_debt: int = 0
	for _frame: int in 180:
		await process_frame
		var now: int = Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
		max_debt = maxi(max_debt, int(runtime.world_sim.target_ms) - int(runtime.world_sim.settled_ms()))
	clock.set_paused(true)
	samples.sort()
	_expect(runtime.world_sim.errors.is_empty(), "normal frame sampling records no world failure")
	return {"plants": runtime.world_sim.plants.bodies.size(), "plant_sample_ms": runtime.world_sim.plants.definitions.sample_ms,
		"action_count": runtime.world_sim.plants.active.size(), "frames": samples.size(), "warmup_frames": 60,
		"stream_wait_frames": streamed_frames,
		"frame_p95_ms": samples[170], "frame_p99_ms": samples[178], "frame_max_ms": samples[-1],
		"advanced_ms": int(clock.elapsed_ms) - started, "max_debt_ms": max_debt,
		"engine_static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC)}


func _stream_idle(view: Node) -> bool:
	return view._pending_load.is_empty() and view._pending_unload.is_empty() and view._painting_chunk.x < 0 and view._priority_index >= view._priority_cells.size() and view._dirty_cursor >= view._dirty_order.size()


func _resume() -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REPORT))
	_expect(runtime.load_game(str(report.save)) == OK, "independent process loads the saved session")
	_expect(_hash() == str(report.checkpoint), "independent process restores the exact checkpoint")
	runtime.settings.event_budget = 4096
	runtime.settlement_work_budget = 4096
	clock.advance_msec(250)
	_expect(_hash() == str(report.future), "complete stop/start preserves the same original world and future")
	main.get("hud")._diagnostics.show()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://logs/world-events-plants-resumed.png")
	print("WORLD_EVENTS_PLANTS_RESUME ", JSON.stringify({"checkpoint": report.checkpoint, "future": _hash(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _hash() -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized({"world": runtime.world_sim.to_dict(), "clock": clock.to_dict(), "motion": main.get("player").motion.to_dict()})).sha256_text()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
