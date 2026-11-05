extends SceneTree
## Measures the isolated known-segment owner, not Main, GPU throughput or FPS.
## Run one side length per process under tools/world_benchmark.py::run_guarded.

const State = preload("res://scripts/sim/environment_temperature_state.gd")
const MAX_SIDE: int = 128


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_valid_int():
		_fail("expected side length")
		return
	var side: int = args[0].to_int()
	if side < 1 or side > MAX_SIDE:
		_fail("side outside 1..128")
		return
	var count: int = side * side
	var state := State.new()
	if not state.configure(Vector2i(side, side), count, 0):
		_fail("configure")
		return
	var changes: Array[Dictionary] = []
	for y: int in side:
		for x: int in side:
			changes.append({"cell": Vector2i(x, y), "initial_c": 20.0,
				"target_c": 200.0 if (x + y) % 2 == 0 else -100.0,
				"target_per_ms": 0.0, "until_ms": 60_000, "tau_ms": 10_000})
	var start: int = Time.get_ticks_usec()
	var plan: Dictionary = state.prepare_targets(changes, 0, count)
	var prepare_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	if not bool(plan.get("ok", false)):
		_fail("prepare " + str(plan.get("reason")))
		return
	start = Time.get_ticks_usec()
	var committed: Dictionary = state.commit(plan)
	var commit_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	if not bool(committed.get("ok", false)):
		_fail("commit " + str(committed.get("reason")))
		return
	# Release plans/inputs before measuring persistent projection workloads.
	changes.clear()
	plan = {}
	start = Time.get_ticks_usec()
	var checksum: float = 0.0
	for y: int in side:
		for x: int in side:
			var result: Dictionary = state.actual_at(Vector2i(x, y), 12_347)
			if not bool(result.get("ok", false)):
				_fail("sample")
				return
			checksum += float(result.value_c)
	var sample_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	var timings: Array[float] = []
	for _repeat: int in 20:
		start = Time.get_ticks_usec()
		if state.next_boundary_ms() != 60_000:
			_fail("boundary")
			return
		timings.append(float(Time.get_ticks_usec() - start) / 1000.0)
	timings.sort()
	start = Time.get_ticks_usec()
	var snapshot: Dictionary = state.snapshot()
	var snapshot_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	print("TEMPERATURE_CAPACITY_JSON:", JSON.stringify({"side": side, "tracked_cells": count,
		"prepare_ms": prepare_ms, "commit_ms": commit_ms, "all_samples_ms": sample_ms,
		"boundary_repeats": 20, "boundary_p95_ms": timings[18], "boundary_p99_ms": timings[19],
		"snapshot_ms": snapshot_ms, "snapshot_cells": snapshot.cells.size(), "checksum": checksum}))
	quit(0)


func _fail(reason: String) -> void:
	printerr("TEMPERATURE_CAPACITY_ERROR: ", reason)
	quit(1)
