extends SceneTree
## Native ordinary creation/actions. Run write/read in separate guarded
## processes; headless cannot prove updated GPU texels or visible moving light.

const SAVE: String = "res://logs/intrinsic_native_checkpoint.json"
const REPORT: String = "res://logs/intrinsic_native_expected.json"
const PEARL: String = "amber_pearl"
const FOLLOWUP_MS: int = 31234
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
	if args[0] == "write":
		var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/world_geography.json"))
		profile.solar.longitude_mdeg = 180000
		if not _main.configure_opening_geography(profile):
			_main.free()
			_fail("new night geography rejected")
			return
	root.add_child(_main)
	current_scene = _main
	_runtime = _main._continuity
	_codec = load("res://scripts/runtime/world_session_snapshot.gd")
	if _runtime == null:
		_fail("ordinary world did not assemble")
		return
	if args[0] == "read":
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REPORT))
		if _runtime.load_game(ProjectSettings.globalize_path(SAVE)) != OK or _hash() != expected.checkpoint_sha256:
			_fail("independent in-flight checkpoint differs")
			return
		_clock.advance_msec(FOLLOWUP_MS)
		if _hash() != expected.future_sha256 or not await _capture("restarted_held"):
			_fail("independent complete future differs")
			return
	else:
		if not _runtime.avatar_adapter.choose("subject:player"):
			_fail("ordinary opening choice failed")
			return
		_clock.set_paused(true)
		var dorm: Vector2i = _runtime.world_sim.artifacts.object_cell(PEARL)
		if not _travel(dorm) or not await _capture("placed") or not _runtime.object_adapter.select_object(PEARL):
			_fail("ordinary approach/selection failed")
			return
		var taking: Dictionary = _runtime.object_adapter.submit("take")
		if not taking.ok:
			_fail("ordinary take failed")
			return
		_clock.advance_msec(30000)
		_report.checkpoint_sha256 = _hash()
		if _runtime.save_game(ProjectSettings.globalize_path(SAVE)) != OK:
			_fail("in-flight ordinary save failed")
			return
		_clock.advance_msec(FOLLOWUP_MS)
		_report.future_sha256 = _hash()
		if _runtime.world_sim.artifacts.objects[PEARL].container != "actor:player" or not await _capture("held"):
			_fail("original pearl did not reach the bearer")
			return
		var destination: Vector2i = _main.world.find_walkable_near(dorm + Vector2i(6, 0), 3)
		if destination.distance_to(dorm) < 4.0 or not _travel(destination) or not await _capture("moved"):
			_fail("actual lit bearer journey failed")
			return
		if not _travel(dorm) or not _runtime.object_adapter.select_object(PEARL):
			_fail("ordinary return failed")
			return
		var placing: Dictionary = _runtime.object_adapter.submit("place")
		if not placing.ok:
			_fail("ordinary placement failed")
			return
		_clock.advance_msec(int(_runtime.world_sim.artifacts.active.player.due_ms) - int(_clock.elapsed_ms))
		if _runtime.world_sim.artifacts.objects[PEARL].container != "dorm" or not await _capture("returned") or not _write(REPORT, _report):
			_fail("original place/capture report failed")
			return
	_write("res://logs/intrinsic_native_%s.json" % args[0], _report)
	print("INTRINSIC_NATIVE_PASSED ", args[0], " ", JSON.stringify(_report))
	quit(0)


func _travel(cell: Vector2i) -> bool:
	if not _runtime.travel_to("home", cell):
		return false
	for _step: int in 300:
		if _runtime.player_journey.is_empty():
			return _runtime.controlled_cell() == cell
		_clock.advance_msec(100)
	return false


func _capture(label: String) -> bool:
	# Use ordinary camera following and close the inspection window so the
	# actual source and its illumination remain reviewable in the screenshot.
	_main.camera.follow_focus = true
	_runtime.object_adapter.panel.hide()
	for _frame: int in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var light: Node = _runtime.light_adapter
	if not light.light.enabled or light.last_image == null:
		return false
	var center: Vector2i = TileGrid.world_to_cell(light.light.position)
	var gpu: Image = light.light.texture.get_image()
	for y: int in gpu.get_height():
		for x: int in gpu.get_width():
			var cell: Vector2i = center + Vector2i(x - light.RADIUS, y - light.RADIUS)
			if gpu.get_pixel(x, y) != light.last_image.get_pixel(x, y) or (not _main.fog.is_cell_visible(cell) and gpu.get_pixel(x, y) != Color.BLACK):
				return false
	var source: Vector2i = _runtime.world_sim.artifacts.object_cell(PEARL)
	var rule: Dictionary = SimLocalLight.at_cell(_runtime.world_sim, source)
	var sky: Dictionary = SimNaturalLight.at_cell(_runtime.world_sim, source)
	if not rule.supported or not sky.supported or sky.sky_phase != "night" or int(rule.artificial_relative) != 2000:
		return false
	var path: String = "res://logs/intrinsic_native_%s.png" % label
	if root.get_texture().get_image().save_png(path) != OK:
		return false
	_report.captures.append({"label": label, "at_ms": _runtime.world_sim.elapsed_ms, "source_cell": [source.x, source.y], "container": _runtime.world_sim.artifacts.objects[PEARL].container, "gpu_matches_upload": true, "path": path})
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
	printerr("INTRINSIC_NATIVE_FAILED " + message)
	quit(1)
