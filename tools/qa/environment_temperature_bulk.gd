extends SceneTree
## Bounded bulk preparation probe of the isolated temperature owner. Run with
## an external 30s/1GiB owned-process guard: -- [side [resume_budget]].
## This measures one <=64-block window, not Main, FPS or full-world capacity.

const State = preload("res://scripts/sim/environment_temperature_state.gd")
const BLOCK: int = 16
const SLOTS: int = 256
const INITIAL_END: int = 60_000
const CHANGE_AT: int = 20_000
const FUTURE_AT: int = 32_347
const CANCEL_AT: int = 25_000


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 2:
		_fail("expected optional side [resume_budget]")
		return
	for arg: String in args:
		if not arg.is_valid_int():
			_fail("arguments must be integers")
			return
	var side: int = int(args[0]) if args.size() > 0 else 64
	var budget: int = int(args[1]) if args.size() > 1 else 256
	if side not in [16, 32, 64, 128] or budget not in [1, 17, 256]:
		_fail("side must be 16/32/64/128; budget must be 1/17/256")
		return
	@warning_ignore("integer_division")
	var blocks_axis: int = side / BLOCK
	var blocks: int = blocks_axis * blocks_axis
	# Include a one-cell border to prove untracked cells remain explicit holes.
	var map_size := Vector2i(side + 1, side + 1)
	var owner := State.new()
	if not owner.configure(map_size, side * side, 0):
		_fail("configure")
		return
	var before: Dictionary = owner.snapshot()
	var cold: Dictionary = _run_batch(owner, side, budget, 0, "initial", false)
	if not bool(cold.get("ok", false)):
		_fail("initial bulk: " + str(cold))
		return
	var empty_check: Dictionary = owner.actual_at(Vector2i(side, side), 12_347)
	if bool(empty_check.get("ok", true)) or str(empty_check.get("reason", "")) != "untracked":
		_fail("border hole after initial bulk")
		return
	if int(cold.changed) != side * side or int(cold.offered_chunks) != blocks or int(cold.at_ms) != 0:
		_fail("initial counts")
		return
	var expected_cold := {"ok": true, "actual": 20.0 + 180.0 * (1.0 - exp(-1.2347))}
	var check_cold: Dictionary = owner.actual_at(Vector2i.ZERO, 12_347)
	if not bool(check_cold.get("ok", false)) or absf(float(check_cold.value_c) - float(expected_cold.actual)) > 1.0e-8:
		_fail("initial analytical temperature")
		return
	var cold_checksum: Dictionary = _sample_all(owner, side, 12_347)
	if not bool(cold_checksum.ok):
		_fail("initial sampling")
		return
	var initial_snapshot: Dictionary = owner.snapshot()
	if initial_snapshot.cells.size() != side * side or before.cells.size() != 0:
		_fail("initial snapshot counts")
		return
	# Small inputs also run an independent owner through the existing narrow
	# dictionary API; do this outside all timed bulk sections and disclose it.
	var reference: RefCounted
	if side <= 32:
		reference = State.new()
		if not reference.configure(map_size, side * side, 0):
			_fail("reference configure")
			return
		var reference_initial: Array[Dictionary] = _reference_changes(side, "initial")
		var reference_plan: Dictionary = reference.prepare_targets(reference_initial, 0, reference_initial.size())
		if not bool(reference_plan.get("ok", false)) or not bool(reference.commit(reference_plan).get("ok", false)) or reference.snapshot() != initial_snapshot:
			_fail("initial narrow-reference snapshot differs")
			return
	var original_at_boundary: Dictionary = owner.actual_at(Vector2i.ZERO, CHANGE_AT)
	if not bool(original_at_boundary.get("ok", false)):
		_fail("prechange sample")
		return
	var changed: Dictionary = _run_batch(owner, side, budget, CHANGE_AT, "change", false)
	if not bool(changed.get("ok", false)):
		_fail("changed bulk: " + str(changed))
		return
	var expected_count: int = 0
	for index: int in side * side:
		if (index * 61) % 100 < 10:
			expected_count += 1
	if int(changed.changed) != expected_count or int(changed.at_ms) != CHANGE_AT:
		_fail("changed count or shared time")
		return
	if reference != null:
		var reference_change: Array[Dictionary] = _reference_changes(side, "change")
		var reference_plan: Dictionary = reference.prepare_targets(reference_change, CHANGE_AT, reference_change.size())
		if not bool(reference_plan.get("ok", false)) or not bool(reference.commit(reference_plan).get("ok", false)) or reference.snapshot() != owner.snapshot():
			_fail("changed narrow-reference snapshot differs")
			return
	var now: Dictionary = owner.actual_at(Vector2i.ZERO, CHANGE_AT)
	var future: Dictionary = owner.actual_at(Vector2i.ZERO, FUTURE_AT)
	var expected_future: float = -100.0 + (float(original_at_boundary.value_c) + 100.0) * exp(-1.2347)
	if not bool(now.get("ok", false)) or float(now.value_c) != float(original_at_boundary.value_c) or not bool(future.get("ok", false)) or absf(float(future.value_c) - expected_future) > 1.0e-8:
		_fail("changed boundary continuity or analytical future")
		return
	var changed_checksum: Dictionary = _sample_all(owner, side, FUTURE_AT)
	if not bool(changed_checksum.ok):
		_fail("changed sampling")
		return
	var before_cancel: Dictionary = owner.snapshot()
	var future_before_cancel: Dictionary = owner.actual_at(Vector2i.ZERO, FUTURE_AT)
	# Cancellation proposes a third target, distinct from both previously
	# committed targets, so accidental publication changes the actual future.
	var cancelled: Dictionary = _run_batch(owner, side, budget, CANCEL_AT, "cancel", true)
	if not bool(cancelled.get("ok", false)):
		_fail("cancel bulk: " + str(cancelled))
		return
	if owner.snapshot() != before_cancel or owner.actual_at(Vector2i.ZERO, FUTURE_AT) != future_before_cancel:
		_fail("cancel changed actual state or future")
		return
	if int(cancelled.processed) != expected_count:
		_fail("cancel fixture did not cover the expected changed cells")
		return
	if reference != null and (reference.snapshot() != owner.snapshot() or reference.actual_at(Vector2i.ZERO, FUTURE_AT) != future_before_cancel):
		_fail("narrow-reference future differs")
		return
	var hole: Dictionary = owner.actual_at(Vector2i(side, side), FUTURE_AT)
	if bool(hole.get("ok", true)) or str(hole.get("reason", "")) != "untracked":
		_fail("border hole after cancel")
		return
	print("TEMPERATURE_BULK_JSON:", JSON.stringify({"side": side, "map_size": [side + 1, side + 1],
		"tracked_cells": side * side, "blocks": blocks, "resume_budget": budget,
		"initial": cold, "initial_checksum": cold_checksum,
		"change": changed, "changed_checksum": changed_checksum, "cancel": cancelled,
		"narrow_reference_checked": reference != null,
		"checks": ["initial/future analytical points", "shared boundary continuity", "snapshot equality after cancel", "untracked border"],
		"limitations": ["isolated owner only; not Main, frame time or FPS", "at most 64 blocks per transaction; not full 512x512 atomic capacity", "one cold batch, one change batch and one cancel batch; repeated-call percentiles are not multi-run percentiles", "side <= 32 includes a second narrow-reference owner in process peak memory", "external guard records time and peak memory"]}, "", true, true))
	quit(0)


func _run_batch(owner: RefCounted, side: int, budget: int, at_ms: int, mode: String, cancel: bool) -> Dictionary:
	@warning_ignore("integer_division")
	var axis: int = side / BLOCK
	var total_blocks: int = axis * axis
	var total_started: int = Time.get_ticks_usec()
	var started: int = Time.get_ticks_usec()
	var opened: Dictionary = owner.begin_bulk(at_ms, total_blocks)
	var begin_ms: float = _ms(started)
	if not bool(opened.get("ok", false)):
		return {"ok": false, "reason": "begin", "detail": opened}
	var handle: Variant = opened.handle
	var construct_samples: Array[float] = []
	var offer_samples: Array[float] = []
	var resume_samples: Array[float] = []
	var build_offer_samples: Array[float] = []
	var processed: int = 0
	var visited: int = 0
	var offered: int = 0
	var offered_selected: int = 0
	for by: int in axis:
		for bx: int in axis:
			var key := Vector2i(bx, by)
			var build_start: int = Time.get_ticks_usec()
			var fields: Dictionary = _fields(key, side, mode)
			var construct_ms: float = _ms(build_start)
			construct_samples.append(construct_ms)
			if int(fields.selected) == 0:
				continue
			offered_selected += int(fields.selected)
			fields.erase("selected")
			started = Time.get_ticks_usec()
			var offered_result: Dictionary = owner.offer_bulk_chunk(handle, key, fields)
			var offer_ms: float = _ms(started)
			offer_samples.append(offer_ms)
			build_offer_samples.append(_ms(build_start))
			if not bool(offered_result.get("ok", false)):
				return {"ok": false, "reason": "offer", "detail": offered_result, "block": str(key)}
			offered += 1
			var done: bool = false
			for _call: int in SLOTS + 1:
				started = Time.get_ticks_usec()
				var step: Dictionary = owner.resume_bulk(handle, budget)
				resume_samples.append(_ms(started))
				if not bool(step.get("ok", false)) or int(step.get("visited", -1)) < 0 or int(step.get("visited", -1)) > budget or int(step.get("processed", -1)) < 0 or int(step.get("processed", -1)) > int(step.get("visited", -1)):
					return {"ok": false, "reason": "resume", "detail": step, "block": str(key)}
				visited += int(step.visited)
				processed += int(step.processed)
				if str(step.get("status", "")) == "chunk_done":
					done = true
					break
				if str(step.get("status", "")) != "pending" or int(step.visited) == 0:
					return {"ok": false, "reason": "resume_progress", "detail": step}
			if not done:
				return {"ok": false, "reason": "resume_limit", "block": str(key)}
			# This deliberately includes the final local payload release cost.
			started = Time.get_ticks_usec()
			fields = {}
			var release_ms: float = _ms(started)
			build_offer_samples[build_offer_samples.size() - 1] += release_ms
	if processed != offered_selected or visited != offered * SLOTS:
		return {"ok": false, "reason": "resume_counts", "expected_selected": offered_selected,
			"processed": processed, "expected_visited": offered * SLOTS, "visited": visited}
	var report: Dictionary = {"ok": true, "at_ms": at_ms, "offered_chunks": offered,
		"visited": visited, "processed": processed, "begin_ms": begin_ms,
		"construct_ms": _distribution(construct_samples), "offer_ms": _distribution(offer_samples),
		"construct_offer_release_ms": _distribution(build_offer_samples), "resume_ms": _distribution(resume_samples)}
	started = Time.get_ticks_usec()
	var finished: Dictionary = {}
	var committed: Dictionary = {}
	if cancel:
		var aborted: Dictionary = owner.cancel_bulk(handle)
		report["cancel_ms"] = _ms(started)
		if not bool(aborted.get("ok", false)):
			return {"ok": false, "reason": "cancel", "detail": aborted}
		report["changed"] = 0
	else:
		finished = owner.finish_bulk(handle)
		report["finish_ms"] = _ms(started)
		if not bool(finished.get("ok", false)):
			return {"ok": false, "reason": "finish", "detail": finished}
		started = Time.get_ticks_usec()
		committed = owner.commit_bulk(finished.proof)
		report["commit_ms"] = _ms(started)
		if not bool(committed.get("ok", false)):
			return {"ok": false, "reason": "commit", "detail": committed}
		report["changed"] = int(committed.get("changed", -1))
		report["revision"] = int(committed.get("revision", -1))
		report["at_ms"] = int(committed.get("at_ms", -1))
	# Include release of the session token and proof in the end-to-end measure.
	handle = null
	opened = {}
	finished = {}
	committed = {}
	report["total_wall_ms"] = _ms(total_started)
	return report


func _fields(key: Vector2i, side: int, mode: String) -> Dictionary:
	var mask := PackedByteArray()
	var initial_mask := PackedByteArray()
	var initial := PackedFloat64Array()
	var target := PackedFloat64Array()
	var slope := PackedFloat64Array()
	var until := PackedInt64Array()
	var tau := PackedInt32Array()
	mask.resize(SLOTS)
	initial_mask.resize(SLOTS)
	initial.resize(SLOTS)
	target.resize(SLOTS)
	slope.resize(SLOTS)
	until.resize(SLOTS)
	tau.resize(SLOTS)
	var selected: int = 0
	for local: int in SLOTS:
		var x: int = key.x * BLOCK + (local & 15)
		var y: int = key.y * BLOCK + (local >> 4)
		var selected_cell: bool = mode == "initial" or (y * side + x) * 61 % 100 < 10
		if not selected_cell:
			continue
		selected += 1
		mask[local] = 1
		initial_mask[local] = 1 if mode == "initial" else 0
		initial[local] = 20.0 if mode == "initial" else 0.0
		var warm: bool = (x + y) % 2 == 0
		if mode == "initial":
			target[local] = 200.0 if warm else -100.0
		elif mode == "cancel":
			target[local] = 50.0
		else:
			target[local] = -100.0 if warm else 200.0
		slope[local] = 0.0
		until[local] = INITIAL_END
		tau[local] = 10_000
	return {"mask": mask, "initial_mask": initial_mask, "initial": initial, "target": target,
		"slope": slope, "until_ms": until, "tau_ms": tau, "selected": selected}


func _reference_changes(side: int, mode: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for y: int in side:
		for x: int in side:
			if mode != "initial" and (y * side + x) * 61 % 100 >= 10:
				continue
			var warm: bool = (x + y) % 2 == 0
			var row: Dictionary = {"cell": Vector2i(x, y),
				"target_c": (200.0 if warm else -100.0) if mode == "initial" else (-100.0 if warm else 200.0),
				"target_per_ms": 0.0, "until_ms": INITIAL_END, "tau_ms": 10_000}
			if mode == "initial":
				row["initial_c"] = 20.0
			rows.append(row)
	return rows


func _sample_all(owner: RefCounted, side: int, at_ms: int) -> Dictionary:
	var start: int = Time.get_ticks_usec()
	var checksum: float = 0.0
	for y: int in side:
		for x: int in side:
			var result: Dictionary = owner.actual_at(Vector2i(x, y), at_ms)
			if not bool(result.get("ok", false)):
				return {"ok": false, "cell": [x, y], "detail": result}
			checksum += float(result.value_c)
	return {"ok": true, "samples": side * side, "checksum": checksum, "wall_ms": _ms(start)}


func _distribution(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {"samples": 0, "p50_ms": 0.0, "p95_ms": 0.0, "p99_ms": 0.0, "max_ms": 0.0}
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	var count: int = sorted.size()
	return {"samples": count, "p50_ms": sorted[maxi(0, ceili(count * 0.5) - 1)],
		"p95_ms": sorted[maxi(0, ceili(count * 0.95) - 1)],
		"p99_ms": sorted[maxi(0, ceili(count * 0.99) - 1)], "max_ms": sorted[count - 1]}


func _ms(start: int) -> float:
	return float(Time.get_ticks_usec() - start) / 1000.0


func _fail(reason: String) -> void:
	printerr("TEMPERATURE_BULK_ERROR: ", reason)
	quit(1)
