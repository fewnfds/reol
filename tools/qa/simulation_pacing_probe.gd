extends SceneTree
## Native Main acceptance probe, outside permanent regression. Run once, then
## again with -- --resume to check the saved future in an independent process.
## Artificial CPU work wraps original callbacks; no game rules are replaced.
const REPORT: String = "res://logs/simulation-pacing-native.json"
const SAVE: String = "user://tests/simulation_pacing_native.json"
var clock
var main: Node
var runtime
var failures: Array[String] = []
var originals: Dictionary = {}
var publications: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(70.0, true, false, true).timeout.connect(func() -> void:
		push_error("Pacing native probe timed out")
		quit(1)
	)
	if DisplayServer.get_name() == "headless":
		push_error("Pacing probe requires native rendering")
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
	clock.time_advanced.connect(_published)
	if "--resume" in OS.get_cmdline_user_args():
		await _resume()
		return
	if not runtime.avatar_adapter.choose("subject:player"):
		push_error("Could not select the ordinary human opening")
		quit(1)
		return
	main.get("hud")._diagnostics.show()
	await create_timer(1.0, true, false, true).timeout
	var normal: Dictionary = await _measure("normal", 4.0)
	var kernel: SimSettlementKernel = runtime.world_sim.settlement
	for index: int in mini(16, kernel._plan.size()):
		var step: SimSettlementKernel.Step = kernel._plan[index]
		originals[step.id] = step.callback
		step.callback = _loaded.bind(step.callback)
	var loaded: Dictionary = await _measure("loaded_16x2500us", 8.0)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://logs/simulation-pacing-loaded.png")
	for step: SimSettlementKernel.Step in kernel._plan:
		if originals.has(step.id):
			step.callback = originals[step.id]
	var recovered: Dictionary = await _measure("recovered", 12.0)
	_expect(float(loaded.actual_speed) < float(normal.actual_speed) * 0.8, "injected CPU load reduces world speed")
	_expect(float(recovered.final_rate) > float(loaded.final_rate), "removing CPU load restores admission rate")
	_expect(float(loaded.max_debt_ms) <= 250.001, "new admitted debt remains within the selected 1x horizon")
	_expect(publications > 0, "ordinary Main publishes complete world boundaries")
	# Finish only the accepted old work, with zero new host time, then freeze a
	# genuine current session. No player's existing save is consulted or changed.
	for _attempt in 1000:
		clock.advance_frame(0.0)
		if not clock.has_pending_advance():
			break
	clock.set_paused(true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	_expect(runtime.save_game(SAVE) == OK, "ordinary current session saves at a complete boundary")
	clock.advance_msec(250)
	var future: String = _future_hash()
	_expect(runtime.load_game(SAVE) == OK, "saved current session reloads in the same process")
	clock.advance_msec(250)
	_expect(_future_hash() == future, "same-process restore has the same next world/clock/body")
	var report: Dictionary = {"engine": Engine.get_version_info().string, "renderer": RenderingServer.get_video_adapter_name(),
		"normal": normal, "loaded": loaded, "recovered": recovered, "publications": publications,
		"future_sha256": future, "save": SAVE, "failures": failures}
	var file: FileAccess = FileAccess.open(REPORT, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("PACING_NATIVE ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


func _loaded(at_ms: int, original: Callable) -> Variant:
	var until: int = Time.get_ticks_usec() + 2500
	while Time.get_ticks_usec() < until:
		pass
	return original.call(at_ms)


func _measure(label: String, duration: float) -> Dictionary:
	var start: int = Time.get_ticks_usec()
	var previous: int = start
	var world_start: int = clock.elapsed_ms
	var frames: Array[float] = []
	var work: Array[float] = []
	var max_debt: float = 0.0
	while float(Time.get_ticks_usec() - start) < duration * 1000000.0:
		await process_frame
		var now: int = Time.get_ticks_usec()
		frames.append(float(now - previous) / 1000.0)
		work.append(float(clock.pacing.last_work_usec) / 1000.0)
		previous = now
		max_debt = maxf(max_debt, clock._accumulator)
	frames.sort()
	work.sort()
	var seconds: float = float(Time.get_ticks_usec() - start) / 1000000.0
	var report: Dictionary = {"phase": label, "frames": frames.size(), "real_seconds": seconds,
		"world_ms": clock.elapsed_ms - world_start, "actual_speed": float(clock.elapsed_ms - world_start) / (seconds * 1000.0),
		"frame_p50_ms": frames[frames.size() / 2], "frame_p95_ms": frames[int(frames.size() * 0.95)], "frame_max_ms": frames.back(),
		"clock_work_p95_ms": work[int(work.size() * 0.95)], "clock_work_max_ms": work.back(),
		"max_debt_ms": max_debt, "final_rate": clock.pacing.rate}
	print("PACING_PHASE ", JSON.stringify(report))
	return report


func _published(_from: int, to: int) -> void:
	publications += 1
	_expect(not runtime.world_sim.settlement.is_pending() and runtime.world_sim.elapsed_ms == to, "public time exposes only complete world boundaries")


func _future_hash() -> String:
	return JSON.stringify(SnapshotValues.normalized({"world": runtime.world_sim.to_dict(), "clock": clock.to_dict(), "body": main.get("player").motion.to_dict()})).sha256_text()


func _resume() -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REPORT))
	_expect(runtime.load_game(SAVE) == OK, "independent process loads the same ordinary save")
	clock.advance_msec(250)
	_expect(_future_hash() == str(report.future_sha256), "independent stop/start preserves the same future")
	_expect(clock.pacing.rate == 1.0, "new process rebuilds machine-specific pacing")
	main.get("hud")._diagnostics.show()
	main.get("hud")._refresh_diagnostics()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://logs/simulation-pacing-resumed.png")
	print("PACING_RESUME ", JSON.stringify({"future_sha256": _future_hash(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition and not message in failures:
		failures.append(message)
		push_error(message)
