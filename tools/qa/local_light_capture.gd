extends SceneTree
## Native ordinary scene; an explicitly authored zero-time longitude makes the
## initial local sky night, without skipping world time or altering old saves.
## Run separate -- write then -- read processes under the 30s/1GiB guard.

const SAVE: String = "res://logs/local_light_native_checkpoint.json"
const REPORT: String = "res://logs/local_light_native_expected.json"
const INITIAL: String = "res://logs/local_light_native_opening.json"
const FOLLOWUP_MS: int = 12347
var _main: Node
var _runtime: Node
var _clock: Node
var _codec: Script
var _report: Dictionary = {"captures": []}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] not in ["write", "read"] or DisplayServer.get_name() == "headless":
		_fail("expected native write/read")
		return
	_clock = root.get_node("GameClock")
	_clock.set_paused(true)
	root.size = Vector2i(1600, 900)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_runtime = _main._continuity
	_codec = load("res://scripts/runtime/world_session_snapshot.gd")
	if _runtime == null:
		_fail("ordinary scene did not assemble")
		return
	if args[0] == "read":
		if _runtime.load_game(ProjectSettings.globalize_path(SAVE)) != OK:
			_fail("ordinary loader refused the completely stopped checkpoint")
			return
		_clock.set_paused(true)
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REPORT))
		if _hash() != expected.checkpoint_sha256 or not await _capture("restarted_on", true):
			_fail("the independent native checkpoint differs")
			return
		_clock.advance_msec(FOLLOWUP_MS)
		if _hash() != expected.future_sha256:
			_fail("the independent complete native future differs")
			return
	else:
		if not _runtime.avatar_adapter.choose("subject:player"):
			_fail("ordinary opening choice failed")
			return
		# At elapsed 0 only, a candidate's solar longitude is authored and the
		# portable content digest rebuilt. All other inputs/facts are preserved.
		var snapshot: Dictionary = _codec.capture(_runtime)
		if int(snapshot.clock.elapsed_ms) != 0:
			_fail("geography fixture must be authored before elapsed time")
			return
		snapshot.content_bundle.documents["res://data/definitions/climate.json"].solar.longitude_mdeg = 180000
		snapshot.content_bundle = ReolContentBundle.from_documents(snapshot.content_bundle.documents)
		if SimSaveStore.save_file(ProjectSettings.globalize_path(INITIAL), snapshot) != OK or _runtime.load_game(ProjectSettings.globalize_path(INITIAL)) != OK:
			_fail("ordinary isolated candidate rejected the authored new geography")
			return
		_clock.set_paused(true)
		var at: Vector2i = _runtime.world_sim.artifacts.object_cell("fire_stone")
		if not _runtime.travel_to("home", at):
			_fail("ordinary route to the fixed source failed")
			return
		for _step: int in 200:
			if _runtime.player_journey.is_empty():
				break
			_clock.advance_msec(100)
		if not _runtime.player_journey.is_empty() or not _action("study") or not await _capture("off", false) or not _action("enable") or not await _capture("on", true):
			_fail("ordinary source travel, personal action or light capture failed")
			return
		_report.checkpoint_sha256 = _hash()
		if _runtime.save_game(ProjectSettings.globalize_path(SAVE)) != OK:
			_fail("ordinary saver refused its current checkpoint")
			return
		_clock.advance_msec(FOLLOWUP_MS)
		_report.future_sha256 = _hash()
		if not _write(REPORT, _report):
			_fail("cannot record native expected future")
			return
	_report.result = "passed"
	_report.at_ms = _runtime.world_sim.elapsed_ms
	if not _write("res://logs/local_light_native_%s.json" % args[0], _report):
		_fail("cannot record native outcome")
		return
	print("LOCAL_LIGHT_NATIVE_PASSED ", args[0], " ", JSON.stringify(_report))
	quit(0)


func _action(verb: String) -> bool:
	var result: Dictionary = _runtime.world_sim.artifacts.begin("player", verb, "fire_stone")
	if not bool(result.ok):
		return false
	_clock.advance_msec(int(_runtime.world_sim.artifacts.active.player.due_ms) - int(_clock.elapsed_ms))
	return _runtime.world_sim.elapsed_ms == _clock.elapsed_ms


func _capture(label: String, expected: bool) -> bool:
	for _frame: int in 8:
		await process_frame
	var at: Vector2i = _runtime.world_sim.artifacts.object_cell("fire_stone")
	var rule: Dictionary = SimLocalLight.at_cell(_runtime.world_sim, at)
	var sky: Dictionary = SimNaturalLight.at_cell(_runtime.world_sim, at)
	var view: Node = _runtime.light_adapter
	if not bool(rule.supported) or not bool(sky.supported) or sky.sky_phase != "night" or (int(rule.artificial_relative) > 0) != expected or bool(view.light.enabled) != expected:
		return false
	var picture: Image = root.get_texture().get_image()
	var path: String = "res://logs/local_light_native_%s.png" % label
	if picture.get_size() != Vector2i(1600, 900) or picture.save_png(path) != OK:
		return false
	_report.captures.append({"label": label, "path": path, "at_ms": _runtime.world_sim.elapsed_ms,
		"rule": rule, "original_stored_q": _runtime.world_sim.artifacts.objects.fire_stone.stored_q})
	return true


func _hash() -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(_codec.capture(_runtime))).sha256_text()


func _write(path: String, value: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t", true, true))
	file.close()
	return true


func _fail(message: String) -> void:
	printerr("LOCAL_LIGHT_NATIVE_FAILED " + message)
	quit(1)
