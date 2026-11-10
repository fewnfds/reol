extends SceneTree
## Development entry only. Ordinary Main never loads the recorder.

var _main: Node
var _recorder: Node
var _quit_after: bool = false
var _capture_ok: bool = true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var options: Dictionary = {"seconds": 120, "report": "res://logs/demo-profile.json", "revision": "unknown", "dirty": true}
	var auto_start: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-seconds="):
			options.seconds = clampi(arg.trim_prefix("--capture-seconds=").to_int(), 1, 300)
		elif arg.begins_with("--report="):
			options.report = arg.trim_prefix("--report=")
		elif arg.begins_with("--revision="):
			options.revision = arg.trim_prefix("--revision=")
		elif arg.begins_with("--dirty="):
			options.dirty = arg.trim_prefix("--dirty=") == "true"
		elif arg == "--auto-start":
			auto_start = true
		elif arg == "--quit-after-capture":
			_quit_after = true
		elif arg == "--profile-kernel":
			options["profile_kernel"] = true
	var started: int = Time.get_ticks_usec()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	if _main.get("_continuity") == null:
		push_error("Demo diagnostics could not assemble ordinary Main")
		quit(1)
		return
	options["assembly_usec"] = Time.get_ticks_usec() - started
	_recorder = load("res://tools/diagnostics/demo_recorder.gd").new()
	root.add_child(_recorder)
	_recorder.finished.connect(_recording_finished)
	auto_accept_quit = false
	root.close_requested.connect(_close)
	if not _recorder.configure(_main, options):
		quit(1)
		return
	if auto_start and not _main.get("_continuity").avatar_adapter.choose("subject:player"):
		push_error("Demo diagnostics could not choose the ordinary human opening")
		quit(1)


func _recording_finished(ok: bool) -> void:
	_capture_ok = ok
	if _quit_after or not ok:
		_main.free()
		quit(0 if ok else 1)


func _close() -> void:
	_recorder.finish()
	if is_instance_valid(_main):
		_main.free()
	quit(0 if _capture_ok else 1)
