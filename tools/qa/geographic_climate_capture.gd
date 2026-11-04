extends SceneTree
## Ordinary creation, not an edited running save. Each mode is a separate
## native process under a 30s/1GiB guard: warm, write, then read.

const SAVE: String = "res://logs/geographic_native_checkpoint.json"
const EXPECTED: String = "res://logs/geographic_native_expected.json"
const FOLLOWUP_MS: int = 12347
var _main: Node
var _runtime: Node
var _clock: Node
var _codec: Script


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] not in ["warm", "write", "read"] or DisplayServer.get_name() == "headless":
		_fail("expected native warm/write/read")
		return
	_clock = root.get_node("GameClock")
	_clock.set_paused(true)
	root.size = Vector2i(1600, 900)
	_main = load("res://scenes/main.tscn").instantiate()
	if args[0] != "read":
		var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/world_geography.json"))
		profile.solar.latitude_mdeg = 0 if args[0] == "warm" else 70000
		if not _main.configure_opening_geography(profile):
			_main.free()
			_fail("ordinary creation refused independent geography")
			return
	root.add_child(_main)
	current_scene = _main
	_runtime = _main._continuity
	_codec = load("res://scripts/runtime/world_session_snapshot.gd")
	if _runtime == null or _runtime.world_sim == null:
		_fail("ordinary scene did not assemble")
		return
	var report: Dictionary = {}
	if args[0] == "read":
		if _runtime.load_game(ProjectSettings.globalize_path(SAVE)) != OK:
			_fail("ordinary loader refused native checkpoint")
			return
		_clock.set_paused(true)
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED))
		if _hash() != expected.checkpoint_sha256:
			_fail("independent checkpoint differs")
			return
		report = await _capture("restarted_cold")
		_clock.advance_msec(FOLLOWUP_MS)
		if _hash() != expected.future_sha256:
			_fail("independent complete future differs")
			return
	else:
		if not _runtime.avatar_adapter.choose("subject:player"):
			_fail("ordinary opening choice failed")
			return
		_clock.set_paused(true)
		report = await _capture("warm" if args[0] == "warm" else "cold")
		if report.is_empty():
			_fail("ordinary opening capture failed")
			return
		if args[0] == "write":
			var at: Vector2i = _runtime.world_sim.artifacts.object_cell("fire_stone")
			if not _runtime.travel_to("home", at):
				_fail("ordinary source journey failed")
				return
			for _step: int in 200:
				if _runtime.player_journey.is_empty():
					break
				_clock.advance_msec(100)
			if not _runtime.player_journey.is_empty():
				_fail("source journey did not finish")
				return
			for verb: String in ["study", "enable"]:
				var result: Dictionary = _runtime.world_sim.artifacts.begin("player", verb, "fire_stone")
				if not bool(result.ok):
					_fail("ordinary source action failed: " + verb)
					return
				_clock.advance_msec(int(_runtime.world_sim.artifacts.active.player.due_ms) - int(_clock.elapsed_ms))
			report.active = await _capture("cold_with_fire")
			if report.active.is_empty():
				_fail("active source capture failed")
				return
			report.checkpoint_sha256 = _hash()
			if _runtime.save_game(ProjectSettings.globalize_path(SAVE)) != OK:
				_fail("ordinary saver refused current checkpoint")
				return
			_clock.advance_msec(FOLLOWUP_MS)
			report.future_sha256 = _hash()
			if not _write(EXPECTED, report):
				_fail("cannot record expected native future")
				return
	if report.is_empty() or not _write("res://logs/geographic_native_%s.json" % args[0], report):
		_fail("native capture failed")
		return
	print("GEOGRAPHIC_NATIVE_PASSED ", args[0], " ", JSON.stringify(report))
	quit(0)


func _capture(label: String) -> Dictionary:
	for _frame: int in 8:
		await process_frame
	var world: RegionalSimulation = _runtime.world_sim
	var cell: Vector2i = _runtime.controlled_cell()
	var condition: Dictionary = world.environment.local_conditions("player")
	var sky: Dictionary = SimNaturalLight.at_cell(world, cell)
	var background: Dictionary = SimClimateRules.background_at(world._content.climate, world.weather.definitions, world.weather.epoch_ms, cell, world.elapsed_ms)
	var picture: Image = root.get_texture().get_image()
	var path: String = "res://logs/geographic_native_%s.png" % label
	if world.elapsed_ms != _clock.elapsed_ms or condition.is_empty() or background.is_empty() or not bool(sky.supported) or picture.save_png(path) != OK:
		return {}
	return {"label": label, "path": path, "at_ms": world.elapsed_ms, "condition": condition,
		"background": background, "sky": sky, "content_digest": world._content.content_bundle().digest,
		"caption": _runtime.weather_adapter._caption.text}


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
	printerr("GEOGRAPHIC_NATIVE_FAILED " + message)
	quit(1)
