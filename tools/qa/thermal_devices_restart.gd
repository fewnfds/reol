extends SceneTree
## Native two-process evidence: -- --phase=write, then -- --phase=read.
## The only arranged state is the human body's location for real visibility.
## The checkpoint is never overwritten by the uninterrupted future.

const SAVE: String = "res://logs/thermal_devices_restart.json"
const EXPECTED: String = "res://logs/thermal_devices_expected.json"
const MARKER: String = "thermal_devices_restart_v1"
const DEVICE: String = "fire_stone"
const CHECKPOINT_STEP_MS: int = 173
const FUTURE_STEP_MS: int = 35000
const MAX_REAL_MS: int = 25000
const MAX_FOG_POLLS: int = 30
const MAX_BOUNDARIES: int = 8

var _main: Node
var _runtime: Node
var _adapter: Node
var _clock: ReolGameClock
var _codec: Variant
var _phase: String = "invalid"
var _kitchen: Vector2i
var _actions: Dictionary = {}
var _report: Dictionary = {}
var _started_ms: int = 0
var _failed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_started_ms = Time.get_ticks_msec()
	create_timer(float(MAX_REAL_MS) / 1000.0, true, false, true).timeout.connect(_watchdog)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] not in ["--phase=write", "--phase=read"]:
		_fail("pass exactly one of --phase=write or --phase=read after --")
		return
	_phase = "write" if args[0] == "--phase=write" else "read"
	_report = {"marker": MARKER, "phase": _phase, "result": "running",
		"engine": Engine.get_version_info(), "max_real_ms": MAX_REAL_MS,
		"scope": "ordinary new scene and object panel; real clock, device, field and two-process save/load",
		"commands": [], "screenshots": []}
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs")) != OK:
		_fail("cannot create the QA output directory")
		return
	_clock = root.get_node("GameClock")
	_clock.set_paused(true)
	root.size = Vector2i(1600, 900)
	root.position = Vector2i.ZERO
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_runtime = _main._continuity
	# This is loaded only after autoload and ordinary scene assembly.
	_codec = load("res://scripts/runtime/world_session_snapshot.gd")
	if not _require(_runtime != null and _runtime.world_sim != null and _codec != null, "ordinary scene assembly failed"):
		return
	if not _require(_within_budget(), "scene assembly exceeded its QA budget"):
		return
	_adapter = _runtime.object_adapter
	if not _require(_adapter != null and _adapter.panel != null, "original object panel is unavailable"):
		return
	var passed: bool
	if _phase == "write":
		passed = await _write_phase()
	else:
		passed = await _read_phase()
	if not passed or _failed:
		return
	_report["result"] = "passed"
	_report["elapsed_real_ms"] = Time.get_ticks_msec() - _started_ms
	if not _write_json(_report_path(), _report):
		_fail("cannot write final QA report")
		return
	print("THERMAL_DEVICES_NATIVE ", _phase, " passed report=", _report_path())
	quit(0)


func _write_phase() -> bool:
	# Invalidate any prior metadata before touching the checkpoint. A failed
	# write process must never let a later read report an older run as success.
	if not _write_json(EXPECTED, {"marker": MARKER, "status": "write_incomplete"}):
		_fail("cannot initialize write-phase metadata")
		return false
	if not _require(_runtime.avatar_adapter.choose("subject:player"), "ordinary opening selection failed"):
		return false
	# Choosing a life resumes the clock; pause before any frame can advance it.
	_clock.set_paused(true)
	if not _clock_consistent():
		return false
	var domain: SimArtifacts = _runtime.world_sim.artifacts
	if not _require(domain.objects.has(DEVICE) and domain.objects.has("cold_stone"), "new-game devices are missing"):
		return false
	var item: Dictionary = domain.objects[DEVICE]
	var initial_q: int = int(domain.definitions.types[item.definition].thermal.opening_q)
	if not _require(item.definition == DEVICE and item.region == "home" and item.container == "kitchen" and not bool(item.enabled) and int(item.stored_q) == initial_q and not bool(domain.objects.cold_stone.enabled) and not domain.shape_studied("player", DEVICE), "new-game device state is not the original unlearned, disabled state"):
		return false
	_kitchen = SimRouteTravel.cell(_runtime.world_sim.regions.home.places.kitchen.cell)
	# This one relocation only establishes the sight and reach needed for the UI.
	_runtime._home._player.spawn_at(_kitchen)
	_runtime._home._sync_player_cell()
	if not await _wait_for_visibility():
		return false
	if not _require(_runtime.controlled_cell() == _kitchen and domain.object_cell(DEVICE) == _kitchen and domain.can_see("player", DEVICE), "player or original device is not visible at the kitchen"):
		return false
	if not _require(_adapter.select_object(DEVICE), "original object inspection panel rejected the visible device"):
		return false
	if not _command("study", "studied") or not _require(domain.shape_studied("player", DEVICE), "personal study record did not unlock the method"):
		return false
	if not _command("enable", "enabled") or not _verify_device():
		return false
	var heat: SimLocalHeat = _runtime.world_sim.local_heat
	var boundary_attempts: int = 0
	while heat.next_boundary_ms() - _clock.elapsed_ms <= CHECKPOINT_STEP_MS:
		var boundary: int = heat.next_boundary_ms()
		if not _require(boundary_attempts < MAX_BOUNDARIES and boundary > _clock.elapsed_ms, "no bounded frozen segment is available for the checkpoint"):
			return false
		if not _advance(boundary - _clock.elapsed_ms):
			return false
		boundary_attempts += 1
	var before_ms: int = _clock.elapsed_ms
	var before_q: int = int(item.stored_q)
	var before_input: int = int(heat.device_input.get(DEVICE, 0))
	var segment_start: int = heat.segment_started_ms
	var segment_end: int = heat.next_boundary_ms()
	var frozen_flows: Array = heat.flows.duplicate(true)
	var device_rate: int = _device_rate(frozen_flows)
	if not _require(heat.last_ms == before_ms and device_rate > 0, "enabled device has no current outgoing frozen flow"):
		return false
	if not _advance(CHECKPOINT_STEP_MS):
		return false
	var transferred: int = before_q - int(item.stored_q)
	if not _require(heat.segment_started_ms == segment_start and heat.next_boundary_ms() == segment_end and heat.flows == frozen_flows and _clock.elapsed_ms == before_ms + CHECKPOINT_STEP_MS and _clock.elapsed_ms < segment_end, "173 ms did not remain inside the same frozen segment"):
		return false
	if not _require(transferred == device_rate * CHECKPOINT_STEP_MS and int(heat.device_input.get(DEVICE, 0)) - before_input == transferred and transferred > 0, "actual device stock and field receipt disagree"):
		return false
	if not _verify_device() or not _conserved():
		return false
	if not _require(_runtime.save_game(ProjectSettings.globalize_path(SAVE)) == OK, "ordinary checkpoint save failed"):
		return false
	var saved_digest: String = _digest()
	var saved_sha: String = FileAccess.get_sha256(SAVE)
	var saved_file: Dictionary = SimSaveStore.load_file(ProjectSettings.globalize_path(SAVE))
	if not _require(bool(saved_file.get("ok", false)) and not saved_sha.is_empty() and _value_digest(saved_file.get("data")) == saved_digest, "saved file does not match the complete live checkpoint"):
		return false
	var expected: Dictionary = {"marker": MARKER, "save_sha256": saved_sha,
		"saved_digest": saved_digest, "saved_ms": _clock.elapsed_ms,
		"future_ms": _clock.elapsed_ms + FUTURE_STEP_MS, "actions": _actions.duplicate(true),
		"checkpoint": _observation(), "pre_step_stored_q": before_q,
		"pre_step_device_input": before_input, "frozen_rate_q_per_ms": device_rate,
		"checkpoint_step_ms": CHECKPOINT_STEP_MS, "boundary_attempts": boundary_attempts}
	if not _advance(FUTURE_STEP_MS) or not _verify_device() or not _conserved() or not _verify_progress(expected.checkpoint):
		return false
	expected["future_digest"] = _digest()
	expected["future"] = _observation()
	if not _require(FileAccess.get_sha256(SAVE) == saved_sha, "future advancement modified the checkpoint file"):
		return false
	if not _write_json(EXPECTED, expected):
		_fail("cannot write uninterrupted future metadata")
		return false
	_report["checkpoint"] = expected.checkpoint
	_report["checkpoint_transfer"] = {"duration_ms": CHECKPOINT_STEP_MS, "frozen_rate_q_per_ms": device_rate,
		"stored_q_before": before_q, "transferred_q": transferred, "segment_started_ms": segment_start,
		"segment_until_ms": segment_end, "boundary_attempts": boundary_attempts}
	_report["saved_digest"] = saved_digest
	_report["save_sha256"] = saved_sha
	_report["future"] = expected.future
	_report["future_digest"] = expected.future_digest
	_report["restart_status"] = "checkpoint and uninterrupted future written; fresh process still required"
	return true


func _read_phase() -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED))
	if not _require(parsed is Dictionary and parsed.get("marker") == MARKER and parsed.get("save_sha256") is String and parsed.get("saved_digest") is String and parsed.get("future_digest") is String and parsed.get("checkpoint") is Dictionary and parsed.get("future") is Dictionary and parsed.get("actions") is Dictionary and SnapshotValues.valid_integer(parsed.get("saved_ms"), 0) and SnapshotValues.valid_integer(parsed.get("future_ms"), 0) and SnapshotValues.valid_integer(parsed.get("checkpoint_step_ms"), 0) and SnapshotValues.valid_integer(parsed.get("pre_step_stored_q"), 0) and SnapshotValues.valid_integer(parsed.get("pre_step_device_input"), 0) and SnapshotValues.valid_integer(parsed.get("frozen_rate_q_per_ms"), 1), "missing or invalid write-phase metadata"):
		return false
	var expected: Dictionary = parsed
	_actions = expected.actions.duplicate(true)
	if not _require(_actions.get("study") is String and _actions.get("enable") is String and not str(expected.save_sha256).is_empty() and FileAccess.get_sha256(SAVE) == str(expected.save_sha256), "checkpoint file or action metadata differs from the write process"):
		return false
	if not _require(_runtime.load_game(ProjectSettings.globalize_path(SAVE)) == OK, "fresh-process ordinary loader rejected the checkpoint"):
		return false
	if not _require(_within_budget(), "checkpoint load exceeded its QA budget"):
		return false
	# No frame or UI selection can add observations before this comparison.
	var saved_digest: String = _digest()
	if not _require(saved_digest == str(expected.saved_digest) and _clock.elapsed_ms == int(expected.saved_ms) and _clock.paused, "fresh-process complete checkpoint differs"):
		return false
	if not _clock_consistent() or not _verify_device() or not _conserved():
		return false
	if not _require(_value_digest(_observation()) == _value_digest(expected.checkpoint), "checkpoint device or frozen segment differs after load"):
		return false
	var checkpoint: Dictionary = _observation()
	if not _require(int(expected.checkpoint_step_ms) == CHECKPOINT_STEP_MS and int(expected.pre_step_stored_q) - int(checkpoint.fire_stored_q) == int(expected.frozen_rate_q_per_ms) * CHECKPOINT_STEP_MS and int(checkpoint.device_input) - int(expected.pre_step_device_input) == int(expected.frozen_rate_q_per_ms) * CHECKPOINT_STEP_MS, "loaded checkpoint does not retain the original 173 ms transfer"):
		return false
	if not _require(int(expected.future_ms) == _clock.elapsed_ms + FUTURE_STEP_MS, "future time metadata is invalid"):
		return false
	if not _advance(FUTURE_STEP_MS) or not _verify_device() or not _conserved() or not _verify_progress(checkpoint):
		return false
	var future_digest: String = _digest()
	if not _require(future_digest == str(expected.future_digest) and _value_digest(_observation()) == _value_digest(expected.future), "fresh-process future differs from uninterrupted complete session"):
		return false
	if not _require(FileAccess.get_sha256(SAVE) == str(expected.save_sha256), "read phase changed the original checkpoint file"):
		return false
	_report["checkpoint"] = checkpoint
	_report["checkpoint_transfer"] = {"duration_ms": CHECKPOINT_STEP_MS,
		"frozen_rate_q_per_ms": int(expected.frozen_rate_q_per_ms),
		"stored_q_before": int(expected.pre_step_stored_q),
		"transferred_q": int(expected.pre_step_stored_q) - int(checkpoint.fire_stored_q)}
	_report["saved_digest"] = saved_digest
	_report["save_sha256"] = str(expected.save_sha256)
	_report["future"] = _observation()
	_report["future_digest"] = future_digest
	_kitchen = SimRouteTravel.cell(_runtime.world_sim.regions.home.places.kitchen.cell)
	if not await _prepare_and_capture():
		return false
	_report["restart_status"] = "fresh-process checkpoint and equal future matched complete canonical snapshots"
	return true


func _command(verb: String, completed_kind: String) -> bool:
	_adapter.refresh()
	var button: Button = _adapter.panel._buttons.get(verb)
	if not _require(button != null and button.is_visible_in_tree() and not button.disabled, "original panel does not offer " + verb):
		return false
	button.pressed.emit()
	var active: Dictionary = _runtime.world_sim.artifacts.active.get("player", {})
	if not _require(active.get("verb") == verb and active.get("object") == DEVICE and int(active.get("due_ms", -1)) > _clock.elapsed_ms, "panel did not start the original " + verb + " action: " + str(_adapter._notice)):
		return false
	var action: String = str(active.id)
	var due: int = int(active.due_ms)
	_actions[verb] = action
	if not _advance(due - _clock.elapsed_ms):
		return false
	var event: Dictionary = _event_for(action, completed_kind)
	if not _require(not event.is_empty() and event.actor == "player" and event.object == DEVICE and event.verb == verb and int(event.at_ms) == due and not _runtime.world_sim.artifacts.active.has("player"), "original " + verb + " action did not complete successfully"):
		return false
	_report.commands.append({"verb": verb, "action": action, "started_ms": int(event.started_ms), "due_ms": due, "event": event.duplicate(true)})
	return true


func _event_for(action: String, kind: String) -> Dictionary:
	for event: Dictionary in _runtime.world_sim.artifacts.events:
		if event.get("action") == action and event.get("kind") == kind:
			return event
	return {}


func _verify_device() -> bool:
	var domain: SimArtifacts = _runtime.world_sim.artifacts
	var item: Dictionary = domain.objects.get(DEVICE, {})
	var study: Dictionary = _event_for(str(_actions.get("study", "")), "studied")
	var enabled: Dictionary = _event_for(str(_actions.get("enable", "")), "enabled")
	if not _require(not study.is_empty() and not enabled.is_empty() and domain.shape_studied("player", DEVICE) and item.get("definition") == DEVICE and item.get("region") == "home" and item.get("container") == "kitchen" and bool(item.get("enabled", false)), "original personal study, enable event or device state is missing"):
		return false
	var cell: Vector2i = domain.object_cell(DEVICE)
	var receipt: Dictionary = _runtime.world_sim.local_heat.device_switches.get(str(enabled.action), {})
	var expected: Dictionary = {"action": str(enabled.action), "actor": "player", "object": DEVICE,
		"at_ms": int(enabled.at_ms), "region": "home", "container": "kitchen",
		"cell": [cell.x, cell.y], "enabled": true}
	_report["study_event"] = study.duplicate(true)
	_report["enable_event"] = enabled.duplicate(true)
	_report["thermal_switch_receipt"] = receipt.duplicate(true)
	_report["expected_thermal_switch_receipt"] = expected.duplicate(true)
	# Loaded JSON numbers in device_switches retain float types; artifact event
	# cells and live values use ints. Normalize the complete structures before
	# comparison, exactly as the full snapshot digest does, without truncation.
	var cell_matches: bool = SnapshotValues.normalized(enabled.cell) == SnapshotValues.normalized(expected.cell)
	var receipt_matches: bool = SnapshotValues.normalized(receipt) == SnapshotValues.normalized(expected)
	if not _require(enabled.actor == "player" and enabled.object == DEVICE and enabled.verb == "enable" and enabled.effect_region == "home" and enabled.device_container == "kitchen" and cell_matches and receipt_matches, "original enable event and committed thermal switch receipt differ"):
		return false
	return true


func _device_rate(flows: Array) -> int:
	var rate: int = 0
	for flow: Dictionary in flows:
		if str(flow.from) == "@artifact/" + DEVICE:
			rate += int(flow.rate)
	return rate


func _observation() -> Dictionary:
	var heat: SimLocalHeat = _runtime.world_sim.local_heat
	var item: Dictionary = _runtime.world_sim.artifacts.objects[DEVICE]
	var energy: int = 0
	for row: Dictionary in heat.cells.values():
		energy += int(row.energy)
	return {"world_ms": _runtime.world_sim.elapsed_ms, "target_ms": _runtime.world_sim.target_ms,
		"heat_ms": heat.last_ms, "segment_started_ms": heat.segment_started_ms,
		"segment_until_ms": heat.next_boundary_ms(), "flows": heat.flows.duplicate(true),
		"fire_stored_q": int(item.stored_q), "fire_enabled": bool(item.enabled),
		"fire_region": str(item.region), "fire_container": str(item.container),
		"device_input": int(heat.device_input.get(DEVICE, 0)), "continuous_input": heat.continuous_input,
		"absorbed_energy": heat.absorbed_energy, "input_energy": heat.input_energy,
		"ambient_in": heat.ambient_in, "loss_energy": heat.loss_energy,
		"cell_count": heat.cells.size(), "cell_energy": energy}


func _conserved() -> bool:
	var row: Dictionary = _observation()
	return _require(int(row.heat_ms) == _clock.elapsed_ms and int(row.cell_energy) + int(row.loss_energy) + int(row.absorbed_energy) == int(row.input_energy) + int(row.continuous_input) + int(row.ambient_in), "thermal field ledger or committed heat time diverged")


func _verify_progress(checkpoint: Dictionary) -> bool:
	var future: Dictionary = _observation()
	var emitted: int = int(checkpoint.fire_stored_q) - int(future.fire_stored_q)
	return _require(int(future.world_ms) > int(checkpoint.segment_until_ms) and emitted > 0 and int(future.device_input) - int(checkpoint.device_input) == emitted, "device did not continue the accounted transfer across its saved segment boundary")


func _advance(amount: int) -> bool:
	if not _require(amount > 0 and _within_budget(), "advance exceeded its bounded QA budget"):
		return false
	var target: int = _clock.elapsed_ms + amount
	_clock.advance_msec(amount)
	return _require(_clock.elapsed_ms == target and _within_budget(), "clock did not reach the requested time within budget") and _clock_consistent()


func _clock_consistent() -> bool:
	return _require(_clock.elapsed_ms == _runtime.world_sim.elapsed_ms and _clock.elapsed_ms == _runtime.world_sim.target_ms, "clock, committed world and retained target differ")


func _wait_for_visibility() -> bool:
	for _poll: int in MAX_FOG_POLLS:
		if not _require(_within_budget(), "visibility wait exceeded its bounded QA budget"):
			return false
		if _main.fog._focus_cell == _kitchen and _main.fog.is_cell_visible(_kitchen):
			return true
		await create_timer(0.05, true, false, true).timeout
		if _failed:
			return false
	return _require(false, "real fog did not update to the kitchen")


func _prepare_and_capture() -> bool:
	if not await _wait_for_visibility():
		return false
	if not _require(_runtime.controlled_cell() == _kitchen and _adapter.select_object(DEVICE), "loaded visible device cannot be opened in the original panel"):
		return false
	for layer: Node in _main.find_children("*", "CanvasLayer", true, false):
		if not _adapter.is_ancestor_of(layer):
			layer.visible = false
	_adapter.show()
	_adapter.refresh()
	_main.camera.follow_focus = false
	_main.camera.zoom = Vector2(1.5, 1.5)
	_main.camera.global_position = TileGrid.cell_to_world(_kitchen) + Vector2(290, 0)
	_main.camera._clamp_to_world()
	_adapter.queue_redraw()
	await create_timer(0.2, true, false, true).timeout
	var half_view: Vector2 = Vector2(root.size) * 0.5 / _main.camera.zoom
	var view_start: Vector2i = Vector2i(((_main.camera.global_position - half_view) / TileGrid.TILE_SIZE).floor())
	var view_end: Vector2i = Vector2i(((_main.camera.global_position + half_view) / TileGrid.TILE_SIZE).ceil())
	view_end.y += ceili(float(ReolWorld.ELEVATION_LEVELS * ReolWorld.ELEVATION_PX) / TileGrid.TILE_SIZE)
	var view_rect := Rect2i(view_start, view_end - view_start)
	var view_ready: bool = false
	for _frame: int in 120:
		if _failed or not _within_budget():
			return _require(false, "view did not settle within the QA budget")
		await process_frame
		if _main.world.is_view_ready(view_rect):
			view_ready = true
			break
	if not _require(view_ready, "actual terrain did not finish drawing the camera view"):
		return false
	await RenderingServer.frame_post_draw
	if _failed:
		return false
	var disable: Button = _adapter.panel._buttons.get("disable")
	if not _require(_within_budget() and _main.fog.visible and _main.fog.is_cell_visible(_kitchen) and _adapter._visible(DEVICE) and _adapter.panel.is_visible_in_tree() and disable != null and disable.is_visible_in_tree(), "actual fog, device or enabled object panel is not visible"):
		return false
	var picture: Image = root.get_texture().get_image()
	var path: String = "res://logs/thermal_devices_read_future.png"
	if not _require(picture != null and picture.get_size() == Vector2i(1600, 900) and picture.save_png(path) == OK, "native 1600 x 900 screenshot failed"):
		return false
	_report.screenshots.append({"path": path, "size": [1600, 900], "fog_visible": true, "object": DEVICE, "panel": "ordinary object inspection"})
	return true


func _digest() -> String:
	return _value_digest(_codec.capture(_runtime))


func _value_digest(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value)).sha256_text()


func _within_budget() -> bool:
	return not _failed and Time.get_ticks_msec() - _started_ms <= MAX_REAL_MS


func _watchdog() -> void:
	_fail("25 second SceneTree watchdog expired")


func _require(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	_report["result"] = "failed"
	_report["failure"] = message
	_report["elapsed_real_ms"] = Time.get_ticks_msec() - _started_ms
	if _runtime != null and _runtime.world_sim != null:
		_report["world_ms"] = _runtime.world_sim.elapsed_ms
		_report["target_ms"] = _runtime.world_sim.target_ms
		_report["clock_ms"] = _clock.elapsed_ms if _clock != null else -1
	_write_json(_report_path(), _report)
	printerr("THERMAL_DEVICES_NATIVE_FAILED ", _phase, " ", message, " report=", _report_path())
	quit(1)


func _report_path() -> String:
	return "res://logs/thermal_devices_%s.json" % _phase


func _write_json(path: String, data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return error == OK
