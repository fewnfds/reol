extends SceneTree
## Measures the isolated known-segment owner, not Main, GPU throughput or FPS.
## Run under tools/world_benchmark.py::run_guarded with positional arguments
## after --: side [dense|sparse [1|10|100]]. Timings are single samples except
## for the explicitly repeated boundary query.

const State = preload("res://scripts/sim/environment_temperature_state.gd")
const MAX_SIDE: int = 512
const MAX_SPARSE_SIDE: int = 64
const SPARSE_SPACING: int = 16
const CHANGE_AT_MS: int = 20_000
const FOLLOWUP_AT_MS: int = 32_347


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty() or args.size() > 3 or not args[0].is_valid_int():
		_fail("expected side [dense|sparse [1|10|100]]")
		return
	var side: int = args[0].to_int()
	if side < 1 or side > MAX_SIDE:
		_fail("side outside 1..512")
		return
	var mode: String = args[1] if args.size() > 1 else "dense"
	if mode not in ["dense", "sparse"]:
		_fail("mode must be dense or sparse")
		return
	if mode == "sparse" and side > MAX_SPARSE_SIDE:
		_fail("sparse side outside 1..64")
		return
	if args.size() > 2 and not args[2].is_valid_int():
		_fail("change percentage must be an integer")
		return
	var percentage: int = int(args[2]) if args.size() > 2 else 1
	if percentage not in [1, 10, 100]:
		_fail("change percentage must be 1, 10 or 100")
		return
	var spacing: int = SPARSE_SPACING if mode == "sparse" else 1
	var map_axis: int = side * spacing
	var count: int = side * side
	var state := State.new()
	if not state.configure(Vector2i(map_axis, map_axis), count, 0):
		_fail("configure")
		return
	var untracked_checks: int = 0
	if mode == "sparse":
		for cell: Vector2i in [Vector2i(1, 0), Vector2i(map_axis - 1, map_axis - 1)]:
			var missing: Dictionary = state.actual_at(cell, 0)
			if bool(missing.get("ok", true)) or str(missing.get("reason", "")) != "untracked":
				_fail("sparse initial hole must be untracked")
				return
			untracked_checks += 1
	var changes: Array[Dictionary] = []
	for y: int in side:
		for x: int in side:
			changes.append({"cell": Vector2i(x * spacing, y * spacing), "initial_c": 20.0,
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
			var result: Dictionary = state.actual_at(Vector2i(x * spacing, y * spacing), 12_347)
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
	var snapshot_cells: int = snapshot.cells.size()
	if snapshot_cells != count:
		_fail("snapshot tracked count")
		return
	snapshot = {}
	if mode == "sparse":
		for cell: Vector2i in [Vector2i(1, 0), Vector2i(map_axis - 1, map_axis - 1)]:
			var missing: Dictionary = state.actual_at(cell, CHANGE_AT_MS)
			if bool(missing.get("ok", true)) or str(missing.get("reason", "")) != "untracked":
				_fail("sparse hole must remain untracked after initial publication")
				return
			untracked_checks += 1
	# Multiplication by 61 permutes each 100-position group, spreading changes
	# over the original row-major grid without randomness or duplicate cells.
	var followup: Array[Dictionary] = []
	var first_changed := Vector2i(-1, -1)
	for y: int in side:
		for x: int in side:
			var linear: int = y * side + x
			if (linear * 61) % 100 >= percentage:
				continue
			var cell := Vector2i(x * spacing, y * spacing)
			if first_changed.x < 0:
				first_changed = cell
			followup.append({"cell": cell, "target_c": -100.0 if (x + y) % 2 == 0 else 200.0,
				"target_per_ms": 0.0, "until_ms": 60_000, "tau_ms": 10_000})
	var changed_count: int = followup.size()
	if changed_count == 0:
		_fail("no changes selected")
		return
	var before_change: Dictionary = state.actual_at(first_changed, CHANGE_AT_MS)
	if not bool(before_change.get("ok", false)):
		_fail("pre-change actual temperature")
		return
	start = Time.get_ticks_usec()
	var next_plan: Dictionary = state.prepare_targets(followup, CHANGE_AT_MS, changed_count)
	var change_prepare_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	if not bool(next_plan.get("ok", false)):
		_fail("change prepare " + str(next_plan.get("reason")))
		return
	start = Time.get_ticks_usec()
	var updated: Dictionary = state.commit(next_plan)
	var change_commit_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	if not bool(updated.get("ok", false)) or int(updated.get("changed", -1)) != changed_count or int(updated.get("at_ms", -1)) != CHANGE_AT_MS:
		_fail("change commit " + str(updated))
		return
	followup.clear()
	next_plan = {}
	var after_change: Dictionary = state.actual_at(first_changed, CHANGE_AT_MS)
	if not bool(after_change.get("ok", false)) or float(after_change.value_c) != float(before_change.value_c):
		_fail("change must preserve actual temperature at the boundary")
		return
	start = Time.get_ticks_usec()
	var changed_checksum: float = 0.0
	for y: int in side:
		for x: int in side:
			var result: Dictionary = state.actual_at(Vector2i(x * spacing, y * spacing), FOLLOWUP_AT_MS)
			if not bool(result.get("ok", false)):
				_fail("post-change sample")
				return
			changed_checksum += float(result.value_c)
	var change_sample_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	# The first selected cell is (0,0), whose original target is 200 C and
	# whose replacement target is -100 C. Check its new future independently
	# of the checksum and outside the measured full-sampling interval.
	var first_future: Dictionary = state.actual_at(first_changed, FOLLOWUP_AT_MS)
	var expected_future: float = -100.0 + (float(before_change.value_c) + 100.0) * exp(-1.2347)
	if not bool(first_future.get("ok", false)) or absf(float(first_future.value_c) - expected_future) > 1.0e-8:
		_fail("changed target future")
		return
	if mode == "sparse":
		for cell: Vector2i in [Vector2i(1, 0), Vector2i(map_axis - 1, map_axis - 1)]:
			var missing: Dictionary = state.actual_at(cell, FOLLOWUP_AT_MS)
			if bool(missing.get("ok", true)) or str(missing.get("reason", "")) != "untracked":
				_fail("sparse hole must remain untracked after changed publication")
				return
			untracked_checks += 1
	print("TEMPERATURE_CAPACITY_JSON:", JSON.stringify({"side": side, "tracked_cells": count,
		"prepare_ms": prepare_ms, "commit_ms": commit_ms, "all_samples_ms": sample_ms,
		"boundary_repeats": 20, "boundary_p95_ms": timings[18], "boundary_p99_ms": timings[19],
		"snapshot_ms": snapshot_ms, "snapshot_cells": snapshot_cells, "checksum": checksum,
		"mode": mode, "map_width": map_axis, "map_height": map_axis, "spacing": spacing,
		"untracked_checks": untracked_checks, "initial_sample_at_ms": 12_347,
		"changes": {"percentage": percentage, "actual_count": changed_count,
			"at_ms": CHANGE_AT_MS, "sample_at_ms": FOLLOWUP_AT_MS,
			"prepare_ms": change_prepare_ms, "commit_ms": change_commit_ms,
			"all_samples_ms": change_sample_ms, "checksum": changed_checksum,
			"temperature_continuity_checked": true, "changed_target_future_checked": true},
		"timing_scope": "prepare/commit/full sampling/snapshot are one sample each; boundary has 20 samples",
		"limitations": ["isolated known-segment owner; not Main, whole-game FPS, GPU throughput or save/restart",
			"deterministic fixed locations and one batch; no movement, climate or target compilation",
			"external process guard owns time/memory limits and peak measurements"]}))
	quit(0)


func _fail(reason: String) -> void:
	printerr("TEMPERATURE_CAPACITY_ERROR: ", reason)
	quit(1)
