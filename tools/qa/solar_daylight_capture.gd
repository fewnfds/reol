extends SceneTree
## Run native under the project's external time/memory guard, -- --phase=write
## then bounded --phase=advance processes and a separate --phase=read process.
## Each invocation advances for at most 12 seconds of measured work, then
## saves real unfinished progress. No old fixture is written.

const SAVE: String = "res://logs/solar_native_checkpoint.json"
const EXPECTED: String = "res://logs/solar_native_future.json"
const FOLLOWUP_MS: int = 12347
const NIGHT_MS: int = 13 * 3600000 + 173
const CHECKPOINTS: Array[int] = [10 * 3600000, NIGHT_MS]
const ADVANCE_BUDGET_MS: int = 12000
var _main: Node
var _runtime: Node
var _clock: Node
var _codec: Variant
var _light_query: Variant
var _sky_view: Variant
var _report: Dictionary = {"frames": []}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 1 or arguments[0] not in ["--phase=write", "--phase=advance", "--phase=read"]:
		_fail("expected one write/advance/read phase")
		return
	_clock = root.get_node("GameClock")
	_clock.set_paused(true)
	root.size = Vector2i(1600, 900)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_runtime = _main._continuity
	if _runtime == null or _runtime.world_sim == null:
		_fail("ordinary main did not assemble")
		return
	# Script-mode entry is parsed before autoload singletons are registered.
	# Load collaborators which name GameClock only after normal scene assembly.
	_codec = load("res://scripts/runtime/world_session_snapshot.gd")
	_light_query = load("res://scripts/sim/natural_light.gd")
	_sky_view = load("res://scripts/world/day_night.gd")
	_report["phase"] = arguments[0]
	if arguments[0] == "--phase=read":
		if _runtime.load_game(ProjectSettings.globalize_path(SAVE)) != OK:
			_fail("ordinary restart did not load its checkpoint")
			return
		_clock.set_paused(true)
		if not await _capture("restored_night"):
			return
		_clock.advance_msec(FOLLOWUP_MS)
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED))
		if expected.get("future_sha256") != _state_hash():
			_fail("complete restarted future differs from uninterrupted original")
			return
	else:
		if arguments[0] == "--phase=write":
			if not _runtime.avatar_adapter.choose("subject:player"):
				_fail("ordinary opening choice failed")
				return
			_clock.set_paused(true)
			if not _write(EXPECTED, {"result": "write_incomplete"}):
				_fail("cannot initialize this run's expected result")
				return
			if not await _capture("day"):
				return
		elif _runtime.load_game(ProjectSettings.globalize_path(SAVE)) != OK or int(_clock.elapsed_ms) < 0 or int(_clock.elapsed_ms) >= NIGHT_MS:
			_fail("bounded continuation has no unfinished checkpoint")
			return
		# Advance only the original public clock and all ordinary world systems;
		# no solar/scene state is assigned to manufacture a night screenshot.
		var deadline: int = Time.get_ticks_msec() + ADVANCE_BUDGET_MS
		for target: int in CHECKPOINTS:
			if target <= int(_clock.elapsed_ms):
				continue
			while int(_clock.elapsed_ms) < target and Time.get_ticks_msec() < deadline:
				_clock.advance_msec(mini(60000, target - int(_clock.elapsed_ms)))
			break
		var label: String = "night" if int(_clock.elapsed_ms) == NIGHT_MS else "horizon" if int(_clock.elapsed_ms) == 10 * 3600000 else "checkpoint_%d" % int(_clock.elapsed_ms)
		if not await _capture(label):
			return
		if _runtime.save_game(ProjectSettings.globalize_path(SAVE)) != OK:
			_fail("ordinary saver refused the current accepted checkpoint")
			return
		if int(_clock.elapsed_ms) == NIGHT_MS:
			_clock.advance_msec(FOLLOWUP_MS)
			if not _write(EXPECTED, {"future_sha256": _state_hash(), "at_ms": _runtime.world_sim.elapsed_ms}):
				_fail("cannot store uninterrupted future evidence")
				return
	_report["at_ms"] = _runtime.world_sim.elapsed_ms
	_report["pending"] = arguments[0] != "--phase=read" and int(_clock.elapsed_ms) < NIGHT_MS
	_report["result"] = "passed"
	if not _write("res://logs/solar_native_%s_%d.json" % [arguments[0].trim_prefix("--phase="), int(_clock.elapsed_ms)], _report):
		_fail("cannot write report")
		return
	if not _write("res://logs/solar_native_progress.json", _report):
		_fail("cannot write this invocation's progress")
		return
	print("SOLAR_NATIVE_PASSED ", arguments[0], " ", _report)
	quit(0)


func _capture(label: String) -> bool:
	for _frame: int in 8:
		await process_frame
	var world: RefCounted = _runtime.world_sim
	var light: Dictionary = _light_query.sky(world, _runtime.controlled_cell())
	var tint: Node = _main.get_node("DayNight")
	if not bool(light.supported) or world.elapsed_ms != _clock.elapsed_ms or tint.color != _sky_view.color_for_sky(light):
		_fail("sky, visible tint and accepted clock disagree at " + label)
		return false
	if (label == "day" and int(light.total_relative) <= 0) or (label in ["night", "restored_night"] and light.sky_phase != "night"):
		_fail("the original clock did not reach the declared solar phase " + label)
		return false
	var picture: Image = root.get_texture().get_image()
	var path: String = "res://logs/solar_native_%s.png" % label
	if picture.get_size() != Vector2i(1600, 900) or picture.save_png(path) != OK:
		_fail("native framebuffer capture failed")
		return false
	_report.frames.append({"label": label, "path": path, "sky": light,
		"tint": [tint.color.r, tint.color.g, tint.color.b],
		"caption": _runtime.weather_adapter._caption.text})
	return true


func _state_hash() -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(_codec.capture(_runtime))).sha256_text()


func _write(path: String, data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.close()
	return true


func _fail(message: String) -> void:
	printerr("SOLAR_NATIVE_FAILED ", message)
	quit(1)
