extends SceneTree
## Ordinary Main, synchronous minute advancement, no signal removal or profiler.
## Run sequential independent processes under tools/world_benchmark.py's guard:
## -- production, -- reference, then -- restart. Not a frame/FPS benchmark.

const SAMPLES: int = 25
const STEP_MS: int = 60000
const FUTURE_MS: int = 12347
const SAVE: String = "res://logs/world_fast_forward_checkpoint.json"
const EXPECTED: String = "res://logs/world_fast_forward_production.json"
var _runtime: Node
var _clock: Node
var _codec: Script


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] not in ["production", "reference", "restart"]:
		_fail("expected production/reference/restart")
		return
	var mode: String = args[0]
	_clock = root.get_node("GameClock")
	_clock.set_paused(true)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_runtime = main._continuity
	_codec = load("res://scripts/runtime/world_session_snapshot.gd")
	if _runtime == null:
		_fail("ordinary Main did not assemble")
		return
	if mode == "restart":
		if _runtime.load_game(ProjectSettings.globalize_path(SAVE)) != OK:
			_fail("ordinary checkpoint did not load")
			return
	elif not _runtime.avatar_adapter.choose("subject:player"):
		_fail("ordinary opening choice failed")
		return
	_clock.set_paused(true)
	if mode == "reference":
		var bodies: RefCounted = _runtime.world_sim.large_bodies
		bodies.set_geometry(bodies._terrain, bodies._elevation, bodies._incoming, false)
	# Let ordinary startup projections settle; the clock remains paused.
	for _frame: int in 3:
		await process_frame
	var report: Dictionary = {"benchmark": "world_fast_forward", "mode": mode,
		"reuse_static_geometry": bool(_runtime.world_sim.large_bodies._reuse_static_geometry),
		"engine": Engine.get_version_info(), "processor": OS.get_processor_name(),
		"logical_processors": OS.get_processor_count(), "display": DisplayServer.get_name(),
		"samples": SAMPLES, "step_ms": STEP_MS, "future_ms": FUTURE_MS,
		"limits": "External owned-process guard required: 30 seconds / 1 GiB.",
		"scope": "Development executable; ordinary 512-square two-region opening. Synchronous minute commands, no frames between samples; includes original rules, notifications and knowledge. Not FPS, continuous 13-hour capacity or player wait-interruption proof."}
	if mode != "restart":
		report.initial_sha256 = _hash()
		var costs: Array[int] = []
		for _sample: int in SAMPLES:
			var start: int = Time.get_ticks_usec()
			_clock.advance_msec(STEP_MS)
			costs.append(Time.get_ticks_usec() - start)
			if _clock.elapsed_ms != _runtime.world_sim.elapsed_ms or not _runtime.world_sim.errors.is_empty():
				_fail("minute did not fully settle")
				return
		report.minute_us = costs
		report.checkpoint_sha256 = _hash()
		report.world_boundaries = _runtime.world_sim.simulation_work.boundaries
		report.regions = _runtime.world_sim.regions.size()
		report.people = RegionalSimulation._actor_ids(_runtime.world_sim.regions).size()
		report.large_bodies = _runtime.world_sim.large_bodies.bodies.size()
		report.birds = _runtime.world_sim.avian_life.birds.size()
		if mode == "production" and _runtime.save_game(ProjectSettings.globalize_path(SAVE)) != OK:
			_fail("ordinary saver refused the complete checkpoint")
			return
	else:
		report.checkpoint_sha256 = _hash()
	_clock.advance_msec(FUTURE_MS)
	report.future_sha256 = _hash()
	report.at_ms = _runtime.world_sim.elapsed_ms
	if mode in ["reference", "restart"]:
		var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED))
		if not expected is Dictionary or expected.get("checkpoint_sha256") != report.checkpoint_sha256 or expected.get("future_sha256") != report.future_sha256:
			_fail("complete reference/restart checkpoint or future differs")
			return
	var file: FileAccess = FileAccess.open("res://logs/world_fast_forward_%s.json" % mode, FileAccess.WRITE)
	if file == null:
		_fail("cannot write benchmark report")
		return
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	print("BENCHMARK_JSON " + JSON.stringify(report, "", true, true))
	quit(0)


func _hash() -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(_codec.capture(_runtime))).sha256_text()


func _fail(message: String) -> void:
	printerr("FAST_FORWARD_FAILED " + message)
	quit(1)
