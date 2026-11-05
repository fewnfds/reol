extends "res://tools/benchmarks/environment_ground_cache.gd"
## Real-owner CPU/GPU field comparison. One backend per process; repeat the
## same options for an independent comparison. This is not a frame-rate test.

const ComputeRuntime = preload("res://scripts/runtime/environment_field_compute_runtime.gd")
const POLLS_PER_FRAME: int = 8
const MAX_CASE_MS: int = 900_000
const LARGE_REFERENCE_SAMPLES: int = 24

var _bench_ground: RefCounted
var _bench_runtime: RefCounted
var _bench_world: RegionalSimulation
var _bench_oracle: SimEnvironmentSourceBindings
var _bench_side: int = 64
var _bench_backend: String = "cpu"


func _run() -> void:
	var options: Dictionary = _compute_options(OS.get_cmdline_user_args())
	if not bool(options.ok):
		await _finish_failure("arguments", options)
		return
	_bench_side = int(options.side)
	_bench_backend = str(options.backend)
	_report = {
		"benchmark": "environment_ground_compute",
		"ok": false,
		"scope": "offline real lifecycle ground artifacts and material piles; one backend per process",
		"limitations": "base-target cache only; no Main FPS, actual temperature, motion, or save/load",
		"side": _bench_side,
		"source_count_expected": _bench_side * _bench_side,
		"radius_mode": str(options.radii),
		"requested_backend": _bench_backend,
		"changes_requested": bool(options.changes),
		"processor": OS.get_processor_name(),
		"logical_processors": OS.get_processor_count(),
		"engine": Engine.get_version_info(),
		"memory_scope": "static counters are not process RSS; external supervisor samples process memory",
		"advance_budget": {"work": ADVANCE_WORK, "target_usec": ADVANCE_USEC, "max_polls_per_frame": POLLS_PER_FRAME},
		"first_failure": null,
	}
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	_report["render_device_available"] = rd != null
	_report["adapter"] = rd.get_device_name() if rd != null else ""
	_report["static_before_bytes"] = OS.get_static_memory_usage()
	var start: int = Time.get_ticks_usec()
	_bench_world = _fixture._make_world(self)
	if _bench_world == null or not _fixture_failures.is_empty():
		await _finish_failure("fixture", {"assertions": _fixture_failures})
		return
	_bench_world.bind_map_data(FlatMap.new())
	if _bench_world.object_lifecycle == null or _bench_world.artifacts == null or _bench_world.construction == null:
		await _finish_failure("fixture_missing_owners")
		return
	if int(_bench_world.object_lifecycle.ground.stats().active) != 0:
		await _finish_failure("fixture_ground_not_empty", _bench_world.object_lifecycle.ground.stats())
		return
	_report["fixture_setup_ms"] = _elapsed_ms(start)
	var inventory: SimInventory = _bench_world.regions.home.inventory
	for item: String in ["wood", "grain", "water"]:
		inventory.containers.store[item] = inventory.quantity("store", item) + _bench_side * _bench_side
	start = Time.get_ticks_usec()
	var created: Dictionary = _create_sources(_bench_world, _bench_side)
	_report["creation_ms"] = _elapsed_ms(start)
	_report["creation"] = created
	if not bool(created.get("ok", false)) or int(created.get("blocked", -1)) != 0 \
			or int(_bench_world.object_lifecycle.ground.stats().active) != _bench_side * _bench_side:
		await _finish_failure("source_creation", created)
		return
	_report["static_after_creation_bytes"] = OS.get_static_memory_usage()
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/environment_sources.json"))
	if not raw is Dictionary or not raw.get("profiles") is Dictionary or not raw.get("bindings") is Dictionary:
		await _finish_failure("definition_file")
		return
	var prepared: Dictionary = _prepare_definitions(raw, str(options.radii))
	if not bool(prepared.get("ok", false)):
		await _finish_failure("definition_profiles", prepared)
		return
	start = Time.get_ticks_usec()
	var definitions := EnvironmentSourceDefinitions.new()
	_bench_oracle = SimEnvironmentSourceBindings.new()
	_bench_ground = Cache.new()
	if not definitions.configure(raw) or not _bench_oracle.configure(_bench_world, definitions) \
			or not _bench_ground.configure(_bench_world, definitions):
		await _finish_failure("configuration")
		return
	_report["configuration_ms"] = _elapsed_ms(start)
	_report["configuration_digest"] = definitions.digest()
	_report["configuration_scope"] = "definition validation, independent A1 oracle and ground cache; sources are assembled separately"
	var initial_time: int = _bench_world.elapsed_ms
	var initial_target: int = _bench_world.target_ms
	start = Time.get_ticks_usec()
	var assembly: Dictionary = _drain(_bench_ground)
	_report["assembly_ms"] = _elapsed_ms(start)
	_report["assembly"] = assembly
	if not bool(assembly.get("ok", false)):
		await _finish_failure("assembly", assembly)
		return
	_report["static_after_assembly_bytes"] = OS.get_static_memory_usage()
	start = Time.get_ticks_usec()
	_bench_runtime = ComputeRuntime.new()
	if not _bench_runtime.configure(_bench_ground, _bench_backend):
		await _finish_failure("runtime_configuration", _bench_ground.diagnostics())
		return
	_report["runtime_configuration_usec"] = Time.get_ticks_usec() - start
	_report["latency_scope"] = "wall time includes frame scheduling/yields; CPU performs at most eight polls per frame, GPU at most one while worker is active"
	var area := Rect2i(0, 0, _bench_side, _bench_side)
	var initial: Dictionary = await _compute(area)
	_report["initial_field"] = initial
	if not bool(initial.get("ok", false)):
		await _finish_failure("initial_field", initial)
		return
	var reference: Dictionary = await _reference(area, _bench_side == 64)
	_report["initial_reference"] = reference
	if not bool(reference.get("ok", false)):
		await _finish_failure("initial_reference", reference)
		return
	if bool(options.changes):
		@warning_ignore("integer_division")
		var window := Rect2i((_bench_side / 32) * 16, (_bench_side / 32) * 16, 16, 16)
		var pool: PackedInt32Array = _local_artifacts(_bench_world, _bench_side, window)
		if pool.size() < 64:
			await _finish_failure("insufficient_local_artifacts", {"count": pool.size()})
			return
		var changes: Dictionary = {}
		for amount: int in [1, 16, 64]:
			var selected := PackedInt32Array()
			for i: int in amount:
				selected.append(pool[i])
			var label: String = "local_%d" % amount
			var result: Dictionary = await _measure_batch(selected, label)
			changes[label] = result
			if not bool(result.get("ok", false)):
				_report["changes"] = changes
				await _finish_failure("local_change", result)
				return
		var scattered := PackedInt32Array()
		@warning_ignore("integer_division")
		var scattered_count: int = maxi(1, int(_bench_world.object_lifecycle.ground.stats().active) / 100)
		for i: int in scattered_count:
			@warning_ignore("integer_division")
			var at: int = i * _artifact_cells.size() / scattered_count
			scattered.append(_artifact_cells[at])
		var scattered_result: Dictionary = await _measure_batch(scattered, "scattered_1_percent")
		changes["scattered_1_percent"] = scattered_result
		_report["changes"] = changes
		if not bool(scattered_result.get("ok", false)):
			await _finish_failure("scattered_change", scattered_result)
			return
	else:
		_report["changes"] = {"status": "not_requested"}
	if _bench_world.elapsed_ms != initial_time or _bench_world.target_ms != initial_target:
		await _finish_failure("world_time_changed", {"before": initial_time, "elapsed": _bench_world.elapsed_ms, "target": _bench_world.target_ms})
		return
	_report["world_time_ms"] = initial_time
	_report["static_peak_bytes"] = OS.get_static_memory_peak_usage()
	_report["diagnostics_before_close"] = _bench_ground.diagnostics()
	await _shutdown(true)


func _compute(area: Rect2i) -> Dictionary:
	var total_start: int = Time.get_ticks_usec()
	var request_start: int = Time.get_ticks_usec()
	var started: Dictionary = _bench_runtime.request(area)
	var request_usec: int = Time.get_ticks_usec() - request_start
	if not bool(started.get("ok", false)) or not bool(started.get("pending", false)):
		return {"ok": false, "reason": "request", "result": started}
	var poll_times: Array[int] = []
	var deadline: int = Time.get_ticks_msec() + MAX_CASE_MS
	var result: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		for _i: int in POLLS_PER_FRAME:
			var poll_start: int = Time.get_ticks_usec()
			result = _bench_runtime.poll(4, ADVANCE_WORK)
			poll_times.append(Time.get_ticks_usec() - poll_start)
			if not bool(result.get("ok", false)) or not bool(result.get("pending", false)):
				break
			# Do not busy-poll an active GPU worker within one frame.
			if str(result.get("backend", "")) == "gpu":
				break
		if not bool(result.get("ok", false)):
			return {"ok": false, "reason": "poll", "result": result}
		if not bool(result.get("pending", false)):
			if bool(result.get("cancelled", false)) or str(result.get("status", "")) != "complete":
				return {"ok": false, "reason": "terminal", "result": result}
			return {"ok": true, "area": [area.position.x, area.position.y, area.size.x, area.size.y],
				"request_to_ready_ms": _elapsed_ms(total_start), "request_usec": request_usec,
				"poll_usec": _percentiles(poll_times), "requested_backend": _bench_backend,
				"actual_backend": str(result.get("backend", "")), "fallback_reason": str(result.get("fallback_reason", "")),
				"gpu": result.get("gpu", {}), "terminal": result}
		await process_frame
	return {"ok": false, "reason": "deadline", "last": result, "request_usec": request_usec, "poll_usec": _percentiles(poll_times)}


func _sync_sources() -> Dictionary:
	var start: int = Time.get_ticks_usec()
	var times: Array[int] = []
	var deadline: int = Time.get_ticks_msec() + MAX_CASE_MS
	while Time.get_ticks_msec() < deadline:
		for _i: int in POLLS_PER_FRAME:
			var info: Dictionary = _bench_ground.diagnostics()
			if info.get("state") == "ready" and int(info.get("pending_sources", -1)) == 0:
				return {"ok": true, "total_ms": _elapsed_ms(start), "advance_usec": _percentiles(times)}
			var step_start: int = Time.get_ticks_usec()
			var step: Dictionary = _bench_ground.advance(ADVANCE_WORK, ADVANCE_USEC)
			times.append(Time.get_ticks_usec() - step_start)
			if not bool(step.get("ok", false)):
				return {"ok": false, "reason": "advance", "result": step}
		await process_frame
	return {"ok": false, "reason": "deadline", "advance_usec": _percentiles(times)}


func _reference(area: Rect2i, full: bool) -> Dictionary:
	var count: int = area.size.x * area.size.y if full else mini(LARGE_REFERENCE_SAMPLES, area.size.x * area.size.y)
	var total: int = area.size.x * area.size.y
	var hash := HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK:
		return {"ok": false, "reason": "digest_start"}
	for i: int in count:
		@warning_ignore("integer_division")
		var index: int = i if full or count <= 1 else i * (total - 1) / (count - 1)
		@warning_ignore("integer_division")
		var cell := area.position + Vector2i(index % area.size.x, index / area.size.x)
		var actual: Dictionary = _bench_ground.read_base(cell)
		var expected: Dictionary = _bench_oracle.sample_base(cell, SAMPLE_BUDGET)
		if not bool(actual.get("ok", false)) or bool(actual.get("pending", true)) \
				or not bool(expected.get("ok", false)) or not bool(expected.get("complete", false)) \
				or actual.get("elements") != expected.get("elements") or actual.get("thermal_grade") != expected.get("thermal_grade"):
			return {"ok": false, "reason": "a1_mismatch", "cell": [cell.x, cell.y], "actual": actual, "expected": expected}
		hash.update(var_to_bytes([cell.x, cell.y, actual.elements, int(actual.thermal_grade)]))
		if full and i % area.size.x == area.size.x - 1:
			await process_frame
	return {"ok": true, "cells": count, "fields": "five elements and net thermal grade via independent real-owner A1 oracle",
		"scope": "all cells" if full else "24 deterministic row-major distributed samples",
		"digest_sha256": hash.finish().hex_encode()}


func _measure_batch(indices: PackedInt32Array, label: String) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var durations: Array[int] = []
	for index: int in indices:
		var id: String = _object_id(index)
		var item: Dictionary = _bench_world.artifacts.objects[id]
		var request: Dictionary = {"command": "compute_bench_%s_hold_%d" % [label, index], "op": "move", "id": id,
			"from": {"region": item.region, "container": item.container}, "to": {"region": "home", "container": "actor:player"}}
		var one: int = Time.get_ticks_usec()
		var result: Dictionary = _bench_world.object_lifecycle.execute(request)
		durations.append(Time.get_ticks_usec() - one)
		if not bool(result.get("ok", false)):
			return {"ok": false, "reason": "hold", "result": result, "index": index}
	var commit_ms: float = _elapsed_ms(started)
	var commit_to_ready_start: int = Time.get_ticks_usec()
	var sync: Dictionary = await _sync_sources()
	if not bool(sync.get("ok", false)):
		return {"ok": false, "reason": "sync", "result": sync}
	var area: Rect2i = _affected_area(indices)
	var computed: Dictionary = await _compute(area)
	var removed_ready_ms: float = _elapsed_ms(commit_to_ready_start)
	if not bool(computed.get("ok", false)):
		return {"ok": false, "reason": "removed_compute", "result": computed}
	var removed_reference: Dictionary = await _reference(area, false)
	if not bool(removed_reference.get("ok", false)):
		return {"ok": false, "reason": "removed_reference", "result": removed_reference}
	started = Time.get_ticks_usec()
	for index: int in indices:
		var id: String = _object_id(index)
		var item: Dictionary = _bench_world.artifacts.objects[id]
		@warning_ignore("integer_division")
		var point := Vector2i(index % _bench_side, index / _bench_side)
		var request: Dictionary = {"command": "compute_bench_%s_restore_%d" % [label, index], "op": "move", "id": id,
			"from": {"region": item.region, "container": item.container}, "to": {"region": "home", "cell": [point.x, point.y]}}
		var result: Dictionary = _bench_world.object_lifecycle.execute(request)
		if not bool(result.get("ok", false)):
			return {"ok": false, "reason": "restore", "result": result, "index": index}
	var restore_commit_ms: float = _elapsed_ms(started)
	var restore_ready_start: int = Time.get_ticks_usec()
	var restore_sync: Dictionary = await _sync_sources()
	if not bool(restore_sync.get("ok", false)):
		return {"ok": false, "reason": "restore_sync", "result": restore_sync}
	var restored: Dictionary = await _compute(area)
	var restore_ready_ms: float = _elapsed_ms(restore_ready_start)
	if not bool(restored.get("ok", false)):
		return {"ok": false, "reason": "restore_compute", "result": restored}
	var restored_reference: Dictionary = await _reference(area, false)
	if not bool(restored_reference.get("ok", false)):
		return {"ok": false, "reason": "restore_reference", "result": restored_reference}
	return {"ok": true, "count": indices.size(), "commit_total_ms": commit_ms,
		"commit_usec": _percentiles(durations), "removed_sync": sync, "removed_compute": computed,
		"post_commit_to_readable_ms": removed_ready_ms, "removed_reference": removed_reference,
		"restore_commit_ms": restore_commit_ms, "restore_sync": restore_sync, "restore_compute": restored,
		"post_restore_to_readable_ms": restore_ready_ms, "restored_reference": restored_reference}


func _affected_area(indices: PackedInt32Array) -> Rect2i:
	var min_x: int = _bench_side - 1
	var min_y: int = _bench_side - 1
	var max_x: int = 0
	var max_y: int = 0
	for index: int in indices:
		@warning_ignore("integer_division")
		var point := Vector2i(index % _bench_side, index / _bench_side)
		min_x = mini(min_x, point.x)
		min_y = mini(min_y, point.y)
		max_x = maxi(max_x, point.x)
		max_y = maxi(max_y, point.y)
	# Radius 16 is the largest profile in both benchmark modes. Clip to the
	# original requested square; align both endpoints to the 16-cell tile.
	@warning_ignore("integer_division")
	var first := Vector2i(maxi(0, min_x - 16) / 16 * 16, maxi(0, min_y - 16) / 16 * 16)
	@warning_ignore("integer_division")
	var last := Vector2i(mini(_bench_side, max_x + 17 + 15) / 16 * 16, mini(_bench_side, max_y + 17 + 15) / 16 * 16)
	return Rect2i(first, last - first)


func _compute_options(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"ok": true, "side": 64, "radii": "max", "backend": "cpu", "changes": true}
	var index: int = 0
	while index < args.size():
		var name: String = args[index]
		if name == "--no-changes":
			result.changes = false
		elif name in ["--side", "--radii", "--backend"]:
			index += 1
			if index >= args.size():
				return {"ok": false, "reason": "missing_option_value", "option": name}
			match name:
				"--side":
					if not args[index].is_valid_int():
						return {"ok": false, "reason": "invalid_side"}
					result.side = args[index].to_int()
				"--radii": result.radii = args[index]
				"--backend": result.backend = args[index]
		else:
			return {"ok": false, "reason": "unknown_argument", "argument": name}
		index += 1
	if result.side not in SIDES or result.radii not in ["max", "mixed"] or result.backend not in ["cpu", "gpu", "auto"]:
		return {"ok": false, "reason": "unsupported_options", "options": result}
	return result


func _finish_failure(reason: String, detail: Dictionary = {}) -> void:
	_report["first_failure"] = {"reason": reason, "detail": detail}
	await _shutdown(false)


func _shutdown(success: bool) -> void:
	if _bench_runtime != null:
		var cancellation_requested: bool = false
		while bool(_bench_runtime.diagnostics().get("busy", false)):
			var info: Dictionary = _bench_runtime.diagnostics()
			if not cancellation_requested and not bool(info.get("cancelled", false)):
				_bench_runtime.cancel(int(info.get("ticket", 0)))
				cancellation_requested = true
			_bench_runtime.poll(4, ADVANCE_WORK)
			if bool(_bench_runtime.diagnostics().get("busy", false)):
				await process_frame
		var started: int = Time.get_ticks_usec()
		if not _bench_runtime.close():
			success = false
			_report["first_failure"] = {"reason": "runtime_close", "detail": _bench_runtime.diagnostics()}
		_report["runtime_close_usec"] = Time.get_ticks_usec() - started
	if _bench_ground != null:
		var started: int = Time.get_ticks_usec()
		_bench_ground.close()
		_report["ground_close_usec"] = Time.get_ticks_usec() - started
	_report["static_after_close_bytes"] = OS.get_static_memory_usage()
	_report["ok"] = success
	print("ENV_GROUND_COMPUTE_BENCHMARK " + JSON.stringify(_report, "", true, true))
	quit(0 if success else 1)
