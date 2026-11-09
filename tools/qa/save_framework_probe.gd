extends SceneTree
## Native Main acceptance. Run, stop the process, then run with -- --resume.
## Uses its own test save; never reads or replaces the player's ordinary slot.
const REPORT: String = "res://logs/save-framework-native.json"
var clock
var main: Node
var runtime
var failures: Array[String] = []
var receipts: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func() -> void:
		push_error("Save framework probe timed out")
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
	_expect(runtime.travel_to("river"), "original body starts a real inter-region journey")
	runtime.settings.event_budget = 1
	runtime.settlement_work_budget = 1
	clock.advance_msec(75)
	_expect(clock.has_pending_advance(), "the original clock has budgeted work when saving is requested")
	var path: String = "user://tests/save_framework_native_%d.json" % Time.get_ticks_usec()
	runtime.save_finished.connect(func(_path: String, result: Error) -> void: receipts.append(result))
	_expect(runtime.home_runtime().request_save(path) == OK, "ordinary save entry accepts the request")
	_expect(receipts.is_empty() and not FileAccess.file_exists(path), "request acceptance does not claim a written file")
	clock.set_paused(true)
	var frames: int = 0
	while runtime._saves.pending() and frames < 1000:
		frames += 1
		await process_frame
	_expect(receipts == [OK], "the native frame loop emits exactly one successful receipt")
	_expect(clock.elapsed_ms == 75 and clock.paused and not clock.has_pending_advance(), "save drains exactly the accepted time while preserving user pause")
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
	main.get("hud")._diagnostics.show()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://logs/save-framework-native.png")
	var report: Dictionary = {"engine": Engine.get_version_info().string, "renderer": RenderingServer.get_video_adapter_name(),
		"save": path, "drain_frames": frames, "checkpoint": checkpoint, "future": future, "failures": failures}
	var file: FileAccess = FileAccess.open(REPORT, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SAVE_FRAMEWORK_NATIVE ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


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
	root.get_texture().get_image().save_png("res://logs/save-framework-resumed.png")
	print("SAVE_FRAMEWORK_RESUME ", JSON.stringify({"checkpoint": report.checkpoint, "future": _hash(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _hash() -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized({"world": runtime.world_sim.to_dict(), "clock": clock.to_dict(), "motion": main.get("player").motion.to_dict()})).sha256_text()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
