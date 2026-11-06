extends SceneTree
## Headless real-owner continuous-response benchmark. A bounded external guard
## owns this process; it does not report rendered FPS or GPU performance.

const Definitions = preload("res://scripts/data/environment_source_definitions.gd")
const Session = preload("res://scripts/runtime/environment_response_session.gd")
const Snapshot = preload("res://scripts/persistence/environment_response_snapshot.gd")
const Values = preload("res://scripts/persistence/snapshot_values.gd")
const Transport = preload("res://scripts/persistence/environment_response_file.gd")
const MAX_PUMPS: int = 5_000_000
var _fixture: RefCounted
var _fixture_failures: Array[String] = []
var _report: Dictionary = {"benchmark": "environment_response_ground", "ok": false,
	"scope": "headless original lifecycle/stock/world + closed continuous-response session",
	"limits": "not rendered FPS, GPU timing, Main integration, real moving-source path, or complete-game load",
	"memory_scope": "Godot static counters exclude other allocations; the external guard samples process memory",
	"first_failure": null}


func _initialize() -> void:
	call_deferred("_run")


func assert_true(condition: bool, label: String) -> void:
	if not condition:
		_fixture_failures.append(label)


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fixture_failures.append("%s: %s != %s" % [label, str(actual), str(expected)])


func _new_world() -> RegionalSimulation:
	return _fixture._world(self)


func _run() -> void:
	# Loading the lifecycle fixture before SceneTree's autoloads are registered
	# makes GameClock-dependent scene scripts fail compilation in --script mode.
	var fixture_script: Script = load("res://tests/sim/test_object_lifecycle.gd")
	if fixture_script == null:
		_fail("fixture_load")
		return
	_fixture = fixture_script.new()
	var options: Dictionary = _arguments(OS.get_cmdline_user_args())
	if not bool(options.get("ok", false)):
		_fail("arguments", options)
		return
	var side: int = int(options.size)
	var events: int = int(options.events)
	@warning_ignore("integer_division")
	var a := Vector2i(side / 2, side / 2)
	var b := a + Vector2i.RIGHT
	_report.merge({"size": side, "requested_background_cells": side * side - 2, "direct_events": events,
		"radius_cells": 16, "field_work": options.field_work, "cell_budget": options.cell_budget,
		"engine": Engine.get_version_info(), "processor": OS.get_processor_name(),
		"logical_processors": OS.get_processor_count(), "static_before_bytes": OS.get_static_memory_usage()})
	var started: int = Time.get_ticks_usec()
	var world: RegionalSimulation = _new_world()
	if world == null or not _fixture_failures.is_empty():
		_fail("world_fixture", {"assertions": _fixture_failures})
		return
	_report["fixture_ms"] = _ms(started)
	started = Time.get_ticks_usec()
	var fill: Dictionary = _fill(world, side, a, b)
	_report["fill_ms"] = _ms(started)
	_report["fill"] = fill
	if not bool(fill.get("ok", false)):
		_fail("fill", fill)
		return
	_report["static_after_fill_bytes"] = OS.get_static_memory_usage()
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/environment_sources.json"))
	if not raw is Dictionary or not raw.get("profiles") is Dictionary:
		_fail("definitions_file")
		return
	raw.profiles.ordinary_plant.radius_cells = 16
	raw.profiles.ordinary_earth.radius_cells = 16
	raw.profiles.ordinary_earth.thermal_grade = 2000
	var definitions := Definitions.new()
	if not definitions.configure(raw):
		_fail("definitions_configuration")
		return
	var settings: Dictionary = {"climate": world.environment.definitions.duplicate(true),
		"weather": world.weather.definitions.duplicate(true), "weather_epoch_ms": world.weather.epoch_ms,
		"seed": 42, "tau_ms": 1000, "tide_grid_ms": 3_600_000}
	var session := Session.new()
	session.field_work = int(options.field_work)
	session.cell_budget = int(options.cell_budget)
	started = Time.get_ticks_usec()
	if not session.configure(world, definitions, settings, Rect2i(0, 0, side, side)):
		_fail("session_configuration")
		return
	var activation_pumps: Array[int] = []
	var activation: Dictionary = _drive(session, activation_pumps)
	activation["configure_and_total_ms"] = _ms(started)
	activation["pump_us"] = _percentiles(activation_pumps)
	_report["activation"] = activation
	if not bool(activation.get("ok", false)):
		_fail("session_activation", activation)
		return
	_report["static_after_activation_bytes"] = OS.get_static_memory_usage()
	_report["phase_owner_after_activation"] = session._phases.diagnostics()
	# One real action remains active during a 500ms game-time wait. The later
	# location change is an event-time transfer, not a walking-source trail.
	var timed: Dictionary = _fixture._move("bench_timed", "bench_slate", {"region": "home", "container": "ground:bench_slate_start"}, {"region": "home", "cell": [b.x, b.y]})
	started = Time.get_ticks_usec()
	var scheduled: Dictionary = session.schedule(timed, "player", 500)
	var schedule_us: int = Time.get_ticks_usec() - started
	if not bool(scheduled.get("ok", false)):
		_fail("timed_schedule", scheduled)
		return
	started = Time.get_ticks_usec()
	var advanced: Dictionary = session.advance_to_ms(1000)
	var advance_start_us: int = Time.get_ticks_usec() - started
	if not bool(advanced.get("ok", false)):
		_fail("timed_advance_start", advanced)
		return
	var timed_pumps: Array[int] = []
	var timed_result: Dictionary = _drive(session, timed_pumps)
	timed_result["pump_us"] = _percentiles(timed_pumps)
	timed_result["schedule_us"] = schedule_us
	timed_result["first_advance_us"] = advance_start_us
	timed_result["action_status"] = world.object_lifecycle.actions.bench_timed.status
	timed_result["action_due_ms"] = world.object_lifecycle.actions.bench_timed.due_ms
	_report["timed_action"] = timed_result
	if not bool(timed_result.get("ok", false)) or timed_result.action_status != "completed":
		_fail("timed_action", timed_result)
		return
	var totals: Array[int] = []
	var first_calls: Array[int] = []
	var last_pumps: Array[int] = []
	var all_pumps: Array[int] = []
	var time_pumps: Array[int] = []
	var completed: Array[Dictionary] = []
	for index: int in events:
		var destination: Vector2i = a if index % 2 == 0 else b
		var item: Dictionary = world.artifacts.objects.bench_slate
		var move: Dictionary = _fixture._move("bench_move_%d" % index, "bench_slate", {"region": item.region, "container": item.container}, {"region": "home", "cell": [destination.x, destination.y]})
		started = Time.get_ticks_usec()
		var result: Dictionary = session.execute(move)
		var first_us: int = Time.get_ticks_usec() - started
		first_calls.append(first_us)
		if not bool(result.get("ok", false)):
			_fail("move_start", {"index": index, "result": result})
			return
		var pumping: Dictionary = _drive(session, all_pumps)
		var total_us: int = Time.get_ticks_usec() - started
		totals.append(total_us)
		last_pumps.append(int(pumping.get("last_us", 0)))
		var status: Dictionary = session.status()
		if not bool(pumping.get("ok", false)) or not bool(status.result.get("ok", false)):
			_fail("move_completion", {"index": index, "pump": pumping, "status": status})
			return
		completed.append({"index": index, "at_ms": status.at_ms, "total_us": total_us, "calls": pumping.get("calls", 0),
			"response_publish_us": session._ground.diagnostics().get("response_commit_us", {})})
		# Distinct positive-duration game-time intervals allow actual effects to
		# establish and decay; the event itself remains a single source change.
		var future_ms: int = int(status.at_ms) + 1000
		started = Time.get_ticks_usec()
		var step: Dictionary = session.advance_to_ms(future_ms)
		time_pumps.append(Time.get_ticks_usec() - started)
		if not bool(step.get("ok", false)):
			_fail("time_start", {"index": index, "result": step})
			return
		var time_progress: Dictionary = _drive(session, time_pumps)
		if not bool(time_progress.get("ok", false)) or int(session.status().at_ms) != future_ms:
			_fail("time_completion", {"index": index, "result": time_progress, "status": session.status()})
			return
	_report["source_changes"] = {"count": events, "events": completed,
		"total_per_event_us": _percentiles(totals), "initial_call_us": _percentiles(first_calls),
		"pump_us": _percentiles(all_pumps), "final_pump_including_commit_us": _percentiles(last_pumps),
		"time_advance_calls_us": _percentiles(time_pumps),
		"scope": "single source at a time, alternating two neighboring cells; final pump includes commit and possibly remaining preparation"}
	_report["phase_owner_after_changes"] = session._phases.diagnostics()
	_report["static_before_snapshot_bytes"] = OS.get_static_memory_usage()
	# Preserve measured compute stages even if a later archive hits
	# the external process budget. This is partial evidence, never a passed run.
	print("ENV_RESPONSE_GROUND_PROGRESS " + JSON.stringify(_report, "", true, true))
	if bool(options.snapshot):
		var persisted: Dictionary = _snapshot_roundtrip(session, definitions, settings, a, b)
		_report["snapshot"] = persisted
		if not bool(persisted.get("ok", false)):
			_fail("snapshot", persisted)
			return
	else:
		_report["snapshot"] = {"status": "not_requested"}
	started = Time.get_ticks_usec()
	var closed: bool = session.close()
	_report["session_close_us"] = Time.get_ticks_usec() - started
	_report["static_after_close_bytes"] = OS.get_static_memory_usage()
	_report["static_peak_bytes"] = OS.get_static_memory_peak_usage()
	if not closed:
		_fail("session_close")
		return
	_report["ok"] = true
	_finish(0)


func _fill(world: RegionalSimulation, side: int, a: Vector2i, b: Vector2i) -> Dictionary:
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var inventory: SimInventory = world.regions.home.inventory
	inventory.containers.store.wood = inventory.quantity("store", "wood") + side * side
	var source: Dictionary = lifecycle.execute(_fixture._spawn("bench_slate_start", "bench_slate", "plain_slate", [a.x, a.y]))
	if not bool(source.get("ok", false)):
		return {"ok": false, "reason": "slate", "result": source}
	var stocks: int = 0
	var blocked: int = 0
	for y: int in side:
		for x: int in side:
			var cell := Vector2i(x, y)
			if cell == a or cell == b:
				continue
			if not world.map_data.terrain_is_walkable(cell) or world.construction.blocked(cell):
				blocked += 1
				continue
			var command: String = "bench_stock_%d_%d" % [x, y]
			var request: Dictionary = _fixture._transfer(command, _fixture._location("store"), _fixture._ground(x, y), "wood", 1)
			var result: Dictionary = lifecycle.execute(request)
			if not bool(result.get("ok", false)):
				return {"ok": false, "reason": "stock", "cell": [x, y], "result": result, "stocks": stocks}
			stocks += 1
	return {"ok": true, "stocks": stocks, "artifacts": 1, "blocked": blocked,
		"empty_destination": [b.x, b.y], "scope": "each background pile created by an original lifecycle transfer; one unit and one source per cell"}


func _drive(session: RefCounted, durations: Array[int] = []) -> Dictionary:
	var before: int = Time.get_ticks_usec()
	var count: int = 0
	var last: int = 0
	while count < MAX_PUMPS:
		var state: Dictionary = session.status()
		if state.get("state") == "ready":
			return {"ok": true, "calls": count, "total_ms": _ms(before), "last_us": last}
		if state.get("state") in ["closed", "error"]:
			return {"ok": false, "reason": "bad_state", "state": state, "calls": count}
		var call_started: int = Time.get_ticks_usec()
		var result: Dictionary = session.pump()
		last = Time.get_ticks_usec() - call_started
		durations.append(last)
		count += 1
		if not bool(result.get("ok", false)):
			return {"ok": false, "reason": "pump", "result": result, "calls": count}
	return {"ok": false, "reason": "pump_limit", "calls": count}


func _snapshot_roundtrip(session: RefCounted, definitions: EnvironmentSourceDefinitions, settings: Dictionary, a: Vector2i, b: Vector2i) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var captured: Dictionary = Snapshot.capture(session)
	var capture_ms: float = _ms(started)
	if not bool(captured.get("ok", false)):
		return {"ok": false, "reason": "capture", "result": captured}
	var path: String = "user://response_bench_%d_%d.bin" % [OS.get_process_id(), Time.get_ticks_usec()]
	started = Time.get_ticks_usec()
	var written: Dictionary = Transport.write(path, captured.snapshot)
	if not bool(written.get("ok", false)):
		return {"ok": false, "reason": "file_write", "result": written}
	var bytes: int = int(written.bytes)
	var write_ms: float = _ms(started)
	captured = {} # release captured world BEFORE parsing a second original world
	started = Time.get_ticks_usec()
	var loaded: Dictionary = Transport.read(path)
	var read_parse_ms: float = _ms(started)
	var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not bool(loaded.get("ok", false)) or remove_error != OK:
		return {"ok": false, "reason": "read_or_cleanup", "remove_error": remove_error}
	started = Time.get_ticks_usec()
	var staged: Dictionary = Snapshot.stage(loaded.data, Callable(self, "_new_world"), definitions, settings)
	var stage_ms: float = _ms(started)
	loaded = {} # candidate owns its originals and detached packed response only
	if not bool(staged.get("ok", false)):
		return {"ok": false, "reason": "stage", "result": staged}
	var candidate: RefCounted = staged.candidate
	candidate.field_work = session.field_work
	candidate.cell_budget = session.cell_budget
	var restoration_pumps: Array[int] = []
	var restored: Dictionary = _drive(candidate, restoration_pumps)
	restored["pump_us"] = _percentiles(restoration_pumps)
	if not bool(restored.get("ok", false)):
		return {"ok": false, "reason": "restore", "result": restored}
	var matches: bool = Values.normalized(session.sample(a)) == Values.normalized(candidate.sample(a)) and Values.normalized(session.sample(b)) == Values.normalized(candidate.sample(b))
	started = Time.get_ticks_usec()
	var closed: bool = candidate.close()
	var candidate_close_us: int = Time.get_ticks_usec() - started
	return {"ok": matches and closed, "capture_ms": capture_ms, "file_write_ms": write_ms, "file_read_parse_ms": read_parse_ms,
		"bytes": bytes, "candidate_stage_ms": stage_ms, "candidate_rebuild": restored,
		"candidate_close_us": candidate_close_us, "samples_match": matches,
		"scope": "development snapshot to a uniquely named temporary file, read, detached world stage and real-session rebuild"}


func _arguments(args: PackedStringArray) -> Dictionary:
	var options: Dictionary = {"ok": true, "size": 64, "events": 1, "snapshot": false, "field_work": 128, "cell_budget": 32}
	for arg: String in args:
		if arg == "--snapshot":
			options.snapshot = true
		elif arg.begins_with("--size=") and arg.trim_prefix("--size=").is_valid_int():
			options.size = int(arg.trim_prefix("--size="))
		elif arg.begins_with("--events=") and arg.trim_prefix("--events=").is_valid_int():
			options.events = int(arg.trim_prefix("--events="))
		elif arg.begins_with("--field-work=") and arg.trim_prefix("--field-work=").is_valid_int():
			options.field_work = int(arg.trim_prefix("--field-work="))
		elif arg.begins_with("--cell-budget=") and arg.trim_prefix("--cell-budget=").is_valid_int():
			options.cell_budget = int(arg.trim_prefix("--cell-budget="))
		else:
			return {"ok": false, "reason": "unknown_argument", "argument": arg}
	if options.size not in [64, 128, 512] or options.events not in [1, 8, 32] or options.field_work < 1 or options.field_work > 100_000 or options.cell_budget < 1 or options.cell_budget > 256:
		return {"ok": false, "reason": "invalid_options", "options": options}
	return options


func _percentiles(values: Array[int]) -> Dictionary:
	if values.is_empty():
		return {"count": 0}
	values.sort()
	return {"count": values.size(), "p50": _percentile(values, 0.50), "p95": _percentile(values, 0.95), "p99": _percentile(values, 0.99), "max": values.back()}


func _percentile(values: Array[int], fraction: float) -> int:
	return values[clampi(int(ceil(float(values.size()) * fraction)) - 1, 0, values.size() - 1)]


func _ms(started: int) -> float:
	return float(Time.get_ticks_usec() - started) / 1000.0


func _fail(reason: String, detail: Dictionary = {}) -> void:
	_report["first_failure"] = {"reason": reason, "detail": detail}
	_finish(1)


func _finish(code: int) -> void:
	print("ENV_RESPONSE_GROUND_BENCHMARK " + JSON.stringify(_report, "", true, true))
	quit(code)
