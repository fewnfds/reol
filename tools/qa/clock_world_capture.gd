extends SceneTree
## Native, separate write/read processes exercising ordinary Main and its
## original cross-settlement journey. No world or body state is injected.

const SAVE: String = "res://logs/clock_world_checkpoint.json"
const EXPECTED: String = "res://logs/clock_world_expected.json"
const CHECKPOINT_MS: int = 1234
const FOLLOWUP_MS: int = 3217

var _main: Node
var _runtime: Node
var _clock: ReolGameClock
var _codec: Script
var _origin: Vector2
var _notifications: int = 0
var _last_notification_ms: int = 0
var _notification_error: String = ""
var _screenshots: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] not in ["write", "read"] or DisplayServer.get_name() == "headless":
		_fail("expected one native write/read phase")
		return
	var phase: String = args[0]
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs")) != OK:
		_fail("cannot create the dedicated evidence directory")
		return
	# This QA owns a new evidence path; preserve any previous complete or failed
	# run instead of overwriting its checkpoint or its declared expected future.
	if phase == "write" and (FileAccess.file_exists(SAVE) or FileAccess.file_exists(EXPECTED)):
		_fail("write evidence already exists; use the original read phase")
		return
	if phase == "write" and not _write_json(EXPECTED, {"status": "write_incomplete"}):
		_fail("cannot mark this write phase incomplete")
		return
	_clock = root.get_node_or_null("GameClock") as ReolGameClock
	if _clock == null:
		_fail("common clock was not assembled")
		return
	_clock.set_paused(true)
	root.size = Vector2i(1600, 900)
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	_codec = load("res://scripts/runtime/world_session_snapshot.gd") as Script
	if scene == null or _codec == null:
		_fail("ordinary scene or session codec is unavailable")
		return
	_main = scene.instantiate()
	root.add_child(_main)
	current_scene = _main
	_runtime = _main._continuity as Node
	if _runtime == null or _runtime.world_sim == null:
		_fail("ordinary Main did not assemble the world")
		return
	_last_notification_ms = _clock.elapsed_ms
	_clock.time_advanced.connect(_on_time_advanced)
	var passed: bool
	if phase == "write":
		passed = await _write_phase()
	else:
		passed = await _read_phase()
	if passed:
		print("CLOCK_WORLD_NATIVE_PASSED ", phase)
		quit(0)


func _write_phase() -> bool:
	if not _runtime.avatar_adapter.choose("subject:player"):
		return _fail("ordinary human selection failed")
	# Choosing an avatar resumes the clock; freeze it before any rendered frame.
	_clock.set_paused(true)
	_origin = SimRouteTravel.point(_runtime.world_sim.regions.home.synchronize_actors().player)
	if not _runtime.travel_to("river"):
		return _fail("ordinary cross-settlement journey was refused")
	if not _check_committed(0, false) or not _advance(CHECKPOINT_MS):
		return false
	print("CLOCK_WORLD_NATIVE_CHECKPOINT at_ms=", _clock.elapsed_ms, " body=", _body_report())
	if not await _capture_sizes("write_checkpoint"):
		return false
	if not _check_committed(CHECKPOINT_MS, true):
		return false
	if _runtime.save_game(ProjectSettings.globalize_path(SAVE)) != OK:
		return _fail("ordinary saver refused the in-flight checkpoint")
	if not _check_committed(CHECKPOINT_MS, true):
		return false
	var checkpoint_hash: String = _snapshot_hash()
	var saved: Dictionary = SimSaveStore.load_file(ProjectSettings.globalize_path(SAVE))
	if not bool(saved.get("ok", false)) or not saved.get("data") is Dictionary:
		return _fail("ordinary saved checkpoint could not be read back")
	if _hash_value(saved.data) != checkpoint_hash:
		return _fail("saved file and live complete checkpoint differ")
	var save_hash: String = FileAccess.get_sha256(SAVE)
	if save_hash.length() != 64:
		return _fail("could not hash the saved checkpoint file")
	var checkpoint_body: Dictionary = _body_report()
	if not _advance(FOLLOWUP_MS):
		return false
	var expected: Dictionary = {
		"status": "complete",
		"checkpoint_ms": CHECKPOINT_MS,
		"future_ms": CHECKPOINT_MS + FOLLOWUP_MS,
		"origin": [_origin.x, _origin.y],
		"checkpoint_sha256": checkpoint_hash,
		"save_sha256": save_hash,
		"future_sha256": _snapshot_hash(),
		"checkpoint_body": checkpoint_body,
		"future_body": _body_report(),
		"notifications": _notifications,
		"screenshots": _screenshots,
	}
	if not _write_json("res://logs/clock_world_write.json", expected):
		return _fail("cannot record write-phase evidence")
	if not _write_json(EXPECTED, expected):
		return _fail("cannot publish the complete independent-process evidence")
	print("CLOCK_WORLD_NATIVE_WRITE ", JSON.stringify(expected))
	return true


func _read_phase() -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED))
	if not parsed is Dictionary:
		return _fail("write-phase evidence is missing or invalid")
	var expected: Dictionary = parsed
	if expected.get("status") != "complete" or int(expected.get("checkpoint_ms", -1)) != CHECKPOINT_MS or int(expected.get("future_ms", -1)) != CHECKPOINT_MS + FOLLOWUP_MS:
		return _fail("write-phase evidence is incomplete or from a different scenario")
	if not SnapshotValues.number_pair(expected.get("origin")):
		return _fail("write-phase origin is invalid")
	for field: String in ["checkpoint_sha256", "save_sha256", "future_sha256"]:
		if not expected.get(field) is String or str(expected[field]).length() != 64:
			return _fail("write-phase digest is invalid: " + field)
	if FileAccess.get_sha256(SAVE) != expected.save_sha256:
		return _fail("checkpoint file is missing or differs from the completed write")
	var saved: Dictionary = SimSaveStore.load_file(ProjectSettings.globalize_path(SAVE))
	if not bool(saved.get("ok", false)) or not saved.get("data") is Dictionary or _hash_value(saved.data) != expected.checkpoint_sha256:
		return _fail("saved complete checkpoint does not match the write process")
	_origin = Vector2(float(expected.origin[0]), float(expected.origin[1]))
	if _runtime.load_game(ProjectSettings.globalize_path(SAVE)) != OK:
		return _fail("ordinary loader refused the checkpoint")
	_clock.set_paused(true)
	_last_notification_ms = _clock.elapsed_ms
	if not _check_committed(CHECKPOINT_MS, true):
		return false
	if _snapshot_hash() != expected.checkpoint_sha256:
		return _fail("loaded complete checkpoint differs from the write process")
	print("CLOCK_WORLD_NATIVE_RELOADED at_ms=", _clock.elapsed_ms, " body=", _body_report())
	if not _advance(FOLLOWUP_MS):
		return false
	if _snapshot_hash() != expected.future_sha256:
		return _fail("independent complete future differs from the write process")
	if not await _capture_sizes("read_future_centered"):
		return false
	if not _check_committed(CHECKPOINT_MS + FOLLOWUP_MS, true):
		return false
	var report: Dictionary = {
		"status": "passed",
		"checkpoint_sha256": expected.checkpoint_sha256,
		"save_sha256": expected.save_sha256,
		"future_sha256": expected.future_sha256,
		"future_ms": _clock.elapsed_ms,
		"future_body": _body_report(),
		"notifications": _notifications,
		"screenshots": _screenshots,
	}
	if not _write_json("res://logs/clock_world_read.json", report):
		return _fail("cannot record read-phase evidence")
	print("CLOCK_WORLD_NATIVE_READ ", JSON.stringify(report))
	return true


func _advance(amount: int) -> bool:
	var start: int = _clock.elapsed_ms
	var before: int = _notifications
	_clock.advance_msec(amount)
	if not _notification_error.is_empty():
		return _fail(_notification_error)
	if _notifications <= before:
		return _fail("clock advance produced no committed time notification")
	return _check_committed(start + amount, true)


func _on_time_advanced(from_ms: int, to_ms: int) -> void:
	_notifications += 1
	if _notification_error.is_empty():
		if from_ms != _last_notification_ms or to_ms <= from_ms:
			_notification_error = "clock notifications were not a continuous positive interval"
		elif _clock.elapsed_ms != to_ms or _runtime.world_sim.elapsed_ms != to_ms:
			_notification_error = "clock notified before the world and clock shared the committed time"
		else:
			_notification_error = _body_error(to_ms)
	_last_notification_ms = to_ms


func _check_committed(expected_ms: int, must_have_moved: bool) -> bool:
	if not _notification_error.is_empty():
		return _fail(_notification_error)
	if not _clock.paused or _clock.has_pending_advance() or _clock.elapsed_ms != expected_ms:
		return _fail("clock was not paused at the requested committed time without pending work")
	if _runtime.world_sim.elapsed_ms != expected_ms or _runtime.world_sim.target_ms != expected_ms:
		return _fail("world time or its pending target differs from the common clock")
	var body_error: String = _body_error(expected_ms)
	if not body_error.is_empty():
		return _fail(body_error)
	if must_have_moved and SimRouteTravel.point(_runtime.world_sim.regions.home.synchronize_actors().player).is_equal_approx(_origin):
		return _fail("the original body has not moved from the journey origin")
	return true


func _body_error(at_ms: int) -> String:
	if _runtime.avatar_subject != "subject:player":
		return "human avatar identity changed"
	var world: RegionalSimulation = _runtime.world_sim
	var home: Node = _runtime.home_runtime()
	var player: PlayerCharacter = home._player
	var body: Dictionary = world.regions.home.synchronize_actors().player
	if not is_same(home.simulation, world.regions.home) or not is_same(player.motion._body, body):
		return "the player motion is not bound to the world's original body"
	var journey: Dictionary = _runtime.player_journey
	if journey.is_empty() or journey.get("destination") != "river" or not journey.get("path") is Array or journey.path.is_empty():
		return "cross-settlement journey is no longer in progress"
	if not SimRouteTravel.valid_segment(journey, body, at_ms, float(player.motion.rules.motion.speed)):
		return "the in-flight body is not at the route's common-time projection"
	var point: Vector2 = SimRouteTravel.point(body)
	var cell: Vector2i = SimRouteTravel.cell(body.cell)
	if not player.motion.position.is_equal_approx(point) or not player.global_position.is_equal_approx(point):
		return "body, motion and displayed player positions differ"
	if player.motion.cell() != cell or player.cell != cell or _runtime.controlled_cell() != cell:
		return "body, motion, displayed player and controlled cells differ"
	return ""


func _body_report() -> Dictionary:
	var body: Dictionary = _runtime.world_sim.regions.home.synchronize_actors().player
	var journey: Dictionary = _runtime.player_journey
	return {"position": body.position.duplicate(), "cell": body.cell.duplicate(),
		"destination": journey.destination, "due_ms": journey.due_ms, "remaining_cells": journey.path.size()}


func _capture_sizes(label: String) -> bool:
	var at_ms: int = _clock.elapsed_ms
	# Use the ordinary free camera's existing centre action for evidence. A
	# paused explicit advance does not imply that the player enabled follow.
	Input.action_press("center_camera")
	await process_frame
	Input.action_release("center_camera")
	for size: Vector2i in [Vector2i(1280, 900), Vector2i(1600, 900)]:
		root.size = size
		for _frame: int in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		if not _check_committed(at_ms, true):
			return false
		var picture: Image = root.get_texture().get_image()
		var path: String = "res://logs/clock_world_%s_%dx%d.png" % [label, size.x, size.y]
		if picture == null or picture.get_size() != size or picture.save_png(path) != OK:
			return _fail("native screenshot has the wrong dimensions or failed to save: " + path)
		_screenshots.append({"path": path, "width": size.x, "height": size.y, "at_ms": at_ms})
		print("CLOCK_WORLD_NATIVE_SCREENSHOT ", path, " ", size)
	return true


func _snapshot_hash() -> String:
	return _hash_value(_codec.capture(_runtime))


func _hash_value(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value)).sha256_text()


func _write_json(path: String, value: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t", true, true))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return error == OK


func _fail(message: String) -> bool:
	printerr("CLOCK_WORLD_NATIVE_FAILED " + message)
	quit(1)
	return false
