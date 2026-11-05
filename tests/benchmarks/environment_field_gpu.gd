extends SceneTree
## Native isolated GPU probe; run under an external time and memory guard.
## Args after -- are [size [change_percentage [window_axis]]]. A zero window
## requests the full map; a nonzero window requests a centered compact area.

const Cache = preload("res://scripts/sim/environment_field_cache.gd")
const Index = preload("res://scripts/sim/environment_field_index.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const GPU = preload("res://scripts/runtime/environment_field_gpu.gd")
const CHANNELS: int = 7
var _thread: Thread


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 3:
		_fail("expected size, percentage and window_axis")
		return
	for arg: String in args:
		if not arg.is_valid_int():
			_fail("arguments must be integers")
			return
	var size: int = int(args[0]) if args.size() > 0 else 32
	var percentage: int = int(args[1]) if args.size() > 1 else 0
	var window_axis: int = int(args[2]) if args.size() > 2 else 0
	if size not in [32, 64, 512, 1024, 2048]:
		_fail("size must be 32/64/512/1024/2048")
		return
	if percentage not in [0, 1, 10, 100]:
		_fail("percentage must be 0/1/10/100")
		return
	if window_axis not in [0, 128, 256, 512] or window_axis > size:
		_fail("window_axis must be 0/128/256/512 and no larger than size")
		return
	var axis: int = size if window_axis == 0 else window_axis
	@warning_ignore("integer_division")
	var origin: int = (size - axis) / 2
	var area := Rect2i(Vector2i(origin, origin), Vector2i(axis, axis))
	var compact: bool = window_axis > 0
	var total_sources: int = size * size
	var cache := Cache.new()
	var oracle := Index.new()
	if not cache.configure(Vector2i(size, size), total_sources) or not oracle.configure(Vector2i(size, size), mini(total_sources, 4096)):
		_fail("configure")
		return
	var start: int = Time.get_ticks_usec()
	for y: int in size:
		for x: int in size:
			var slot: int = y * size + x
			var cell := Vector2i(x, y)
			var channels: PackedInt32Array = _channels(slot, cell, size, false)
			var radius: int = _radius(cell)
			if not bool(cache.set_source(slot, cell, radius, channels).ok):
				_fail("populate slot %d" % slot)
				return
			if size <= 64 and not bool(oracle.set_source({"id": "s_" + str(slot), "cell": cell, "radius": radius, "channels": Array(channels)}).ok):
				_fail("oracle populate slot %d" % slot)
				return
		if (y + 1) % 64 == 0 or y + 1 == size:
			print("GPU_FIELD_PROGRESS populated rows=%d/%d sources=%d ms=%.3f" % [y + 1, size, (y + 1) * size, _ms(start)])
	var populate_ms: float = _ms(start)
	var changed_slots := PackedByteArray()
	var initial: Dictionary = await _run_job(cache, area, compact)
	if not bool(initial.get("ok", false)):
		_fail("initial job: " + str(initial))
		return
	var initial_check: Dictionary = _verify(cache, oracle, area, size, changed_slots, initial.values)
	if not bool(initial_check.get("ok", false)):
		_fail("initial check: " + str(initial_check))
		return
	initial.erase("values")
	initial.erase("prepared")
	initial.merge(initial_check, true)
	var changes: Dictionary = {"percentage": percentage, "sources": 0,
		"operation": "unique dispersed slots, metal grade changed at fixed position/radius"}
	var second: Dictionary = {}
	if percentage > 0:
		if changed_slots.resize(total_sources) != OK:
			_fail("change-mask allocation")
			return
		changed_slots.fill(0)
		@warning_ignore("integer_division")
		var change_count: int = total_sources * percentage / 100
		@warning_ignore("integer_division")
		var stride: int = ((total_sources * 618033) / 1000000) | 1
		var api_us: int = 0
		var changed_actual: int = 0
		@warning_ignore("integer_division")
		var progress_interval: int = maxi(1, (change_count + 63) / 64)
		start = Time.get_ticks_usec()
		for i: int in change_count:
			# Every supported source count is a power of two. An odd stride is
			# coprime with it, so even 100% changes each slot exactly once.
			var slot: int = (i * stride) % total_sources
			@warning_ignore("integer_division")
			var cell := Vector2i(slot % size, slot / size)
			var channels: PackedInt32Array = _channels(slot, cell, size, true)
			var call_start: int = Time.get_ticks_usec()
			var update: Dictionary = cache.set_source(slot, cell, _radius(cell), channels)
			api_us += Time.get_ticks_usec() - call_start
			if not bool(update.get("ok", false)) or not bool(update.get("changed", false)) or changed_slots[slot] != 0:
				_fail("source change %d failed: %s" % [slot, str(update)])
				return
			changed_slots[slot] = 1
			changed_actual += 1
			if (i + 1) % progress_interval == 0 or i + 1 == change_count:
				print("GPU_FIELD_PROGRESS updates=%d/%d elapsed_ms=%.3f" % [i + 1, change_count, _ms(start)])
		var registration_wall_ms: float = _ms(start)
		# The independent small-map oracle is updated outside the source
		# registration timer. Large-map verification rebuilds a local oracle.
		if size <= 64:
			for i: int in change_count:
				var slot: int = (i * stride) % total_sources
				@warning_ignore("integer_division")
				var cell := Vector2i(slot % size, slot / size)
				var update: Dictionary = oracle.set_source({"id": "s_" + str(slot), "cell": cell,
					"radius": _radius(cell), "channels": Array(_channels(slot, cell, size, true))})
				if not bool(update.get("ok", false)) or not bool(update.get("changed", false)):
					_fail("oracle source change %d failed" % slot)
					return
		changes["sources"] = changed_actual
		changes["actual_fraction"] = float(changed_actual) / float(total_sources)
		changes["registration_wall_ms"] = registration_wall_ms
		changes["sum_set_source_call_ms"] = float(api_us) / 1000.0
		changes["pending_tiles_before_second"] = int(cache.diagnostics().pending_tiles)
		second = await _run_job(cache, area, compact)
		if not bool(second.get("ok", false)):
			_fail("second job: " + str(second))
			return
		var second_check: Dictionary = _verify(cache, oracle, area, size, changed_slots, second.values)
		if not bool(second_check.get("ok", false)):
			_fail("second check: " + str(second_check))
			return
		second.erase("values")
		second.erase("prepared")
		second.merge(second_check, true)

	# Keep initial fields at top-level for old one-argument invocations. Both
	# jobs create and destroy a fresh local device/pipeline, and both include
	# their respective setup in measured end_to_end_ms and worker_wall_ms.
	initial.merge({"size": size, "sources": total_sources, "populate_ms": populate_ms,
		"change_percentage": percentage, "window_axis": window_axis,
		"area": {"x": area.position.x, "y": area.position.y, "width": area.size.x, "height": area.size.y},
		"compact_requested": compact, "changes": changes, "second_job": second,
		"engine": Engine.get_version_info(), "os": OS.get_name(), "debug_build": OS.has_feature("debug"),
		"limitations": ["synthetic projections, not Main or real objects",
			"each job creates and destroys its own local RenderingDevice and pipeline; second job does not reuse them",
			"end_to_end_ms is wall time from snapshot through GPU setup, compute, readback, preparation and publish; excludes populate, changes and oracle checks",
			"dispatch_ms and percentile samples include submit/sync, not GPU-only execution",
			"worker wait frame intervals are not whole-game frame performance",
			"dense 4/8 radii only; large-radius, sparse sources, moving items, save/load and history remain"]}, true)
	print("GPU_FIELD_BENCH_JSON:", JSON.stringify(initial, "", true, true))
	quit(0)


func _run_job(cache: RefCounted, area: Rect2i, compact: bool) -> Dictionary:
	var overall_start: int = Time.get_ticks_usec()
	var job: Dictionary = cache.export_compute_job(area, compact)
	var pack_ms: float = _ms(overall_start)
	if not bool(job.get("ok", false)):
		return {"ok": false, "reason": "snapshot", "detail": job}
	var compute_params: PackedInt32Array = job.get("compute_params", job.params)
	_thread = Thread.new()
	if _thread.start(_compute.bind(job)) != OK:
		return {"ok": false, "reason": "worker_start"}
	var max_frame_ms: float = 0.0
	var previous: int = Time.get_ticks_usec()
	while _thread.is_alive():
		await process_frame
		max_frame_ms = maxf(max_frame_ms, _ms(previous))
		previous = Time.get_ticks_usec()
	var result: Dictionary = _thread.wait_to_finish()
	_thread = null
	if not bool(result.get("ok", false)):
		return result
	var publish_start: int = Time.get_ticks_usec()
	var accepted: Dictionary = cache.publish_compute_result(job, result.prepared)
	var publish_ms: float = _ms(publish_start)
	if not bool(accepted.get("ok", false)):
		return {"ok": false, "reason": "publish", "detail": accepted}
	result["pack_ms"] = pack_ms
	result["publish_ms"] = publish_ms
	result["end_to_end_ms"] = _ms(overall_start)
	result["published_tiles"] = int(accepted.published_tiles)
	result["pending_tiles_after_publish"] = int(accepted.pending_tiles)
	result["worker_wait_max_frame_ms"] = max_frame_ms
	result["input_cells"] = compute_params[0] * compute_params[1]
	result["input_slots"] = compute_params[2]
	result["input_bytes"] = (compute_params.size() + job.heads.size() + job.slots.size() + job.kernels.size() + job.radius_offsets.size()) * 4
	result["dispatch_timing_ms"] = _distribution(result.dispatch_ms)
	return result


func _compute(job: Dictionary) -> Dictionary:
	var worker_start: int = Time.get_ticks_usec()
	var device := GPU.new()
	var initialized: Dictionary = device.initialize()
	if not bool(initialized.get("ok", false)):
		return initialized
	var result: Dictionary = device.compute(job)
	result["setup_ms"] = float(initialized.get("setup_ms", 0.0))
	var close_start: int = Time.get_ticks_usec()
	device.close()
	result["close_ms"] = _ms(close_start)
	if bool(result.get("ok", false)):
		var started: int = Time.get_ticks_usec()
		result["prepared"] = Cache.prepare_compute_result(job, result.values)
		result["prepare_ms"] = _ms(started)
		result["gpu_total_ms"] = float(result.total_ms)
		result["total_ms"] = float(result.total_ms) + float(result.prepare_ms)
		if not bool(result.prepared.get("ok", false)):
			result["ok"] = false
			result["reason"] = "prepare"
	result["worker_wall_ms"] = _ms(worker_start)
	return result


func _verify(cache: RefCounted, oracle: RefCounted, area: Rect2i, size: int,
		changed_slots: PackedByteArray, values: PackedInt32Array) -> Dictionary:
	if values.size() != area.size.x * area.size.y * CHANNELS:
		return {"ok": false, "reason": "packed_length"}
	var checksum: int = 0
	var verified_cells: int = 0
	var points: Array[Vector2i] = []
	if size <= 64:
		for y: int in range(area.position.y, area.end.y):
			for x: int in range(area.position.x, area.end.x):
				points.append(Vector2i(x, y))
	else:
		# Sample within the requested result area; use a direct independent F0
		# kernel oracle without retaining a dictionary for every source.
		for index: int in 24:
			points.append(area.position + Vector2i((index * 173 + 7) % area.size.x, (index * 101 + 3) % area.size.y))
	for point: Vector2i in points:
		var expected: PackedInt64Array
		if size <= 64:
			var found: Dictionary = oracle.sample_base(point)
			if not bool(found.get("ok", false)):
				return {"ok": false, "reason": "oracle_query", "point": str(point)}
			expected = found.channels
		else:
			expected = _sample_oracle(point, size, changed_slots)
		var read: Dictionary = cache.read_base(point)
		if not bool(read.get("ok", false)) or bool(read.get("pending", true)):
			return {"ok": false, "reason": "pending_cache", "point": str(point)}
		var actual: PackedInt32Array = read.channels
		var buffer_index: int = ((point.y - area.position.y) * area.size.x + point.x - area.position.x) * CHANNELS
		for channel: int in CHANNELS:
			if actual[channel] != expected[channel] or values[buffer_index + channel] != expected[channel]:
				return {"ok": false, "reason": "field_mismatch", "point": str(point), "channel": channel,
					"expected": expected[channel], "published": actual[channel], "raw": values[buffer_index + channel]}
			checksum += actual[channel] * (channel + 1)
		verified_cells += 1
	return {"ok": true, "verified_cells": verified_cells, "checksum": checksum,
		"verification": "all area cells against F0 index" if size <= 64 else "24 area samples against independent local F0 kernel oracle"}


func _sample_oracle(point: Vector2i, size: int, changed_slots: PackedByteArray) -> PackedInt64Array:
	var expected := PackedInt64Array([0, 0, 0, 0, 0, 0, 0])
	for y: int in range(maxi(0, point.y - 7), mini(size, point.y + 8)):
		for x: int in range(maxi(0, point.x - 7), mini(size, point.x + 8)):
			var cell := Vector2i(x, y)
			var slot: int = y * size + x
			var changed: bool = slot < changed_slots.size() and changed_slots[slot] != 0
			var channels: PackedInt32Array = _channels(slot, cell, size, changed)
			var weight: int = int(Rules.kernel(cell - point, _radius(cell)).weight)
			for channel: int in CHANNELS:
				@warning_ignore("integer_division")
				var contribution: int = (int(channels[channel]) * weight + 500000) / 1000000
				expected[channel] = maxi(expected[channel], contribution)
	return expected


func _channels(slot: int, cell: Vector2i, size: int, changed: bool) -> PackedInt32Array:
	var channels := PackedInt32Array()
	for channel: int in CHANNELS:
		var mixed: int = slot * 1009 + channel * 104729 + (cell.x ^ cell.y) * 8191
		channels.append(1 + mixed % 20000)
	# Preserve the existing high-strength adversarial 32x32 baseline.
	if size == 32 and slot % 41 == 0:
		channels[slot % CHANNELS] = 1000000000 - slot
	if changed:
		channels[0] = 1 + channels[0] % 20000
	return channels


func _radius(cell: Vector2i) -> int:
	return 4 if (cell.x + cell.y) % 2 == 0 else 8


func _distribution(samples: Array) -> Dictionary:
	if samples.is_empty():
		return {"samples": 0, "p50": 0.0, "p95": 0.0, "p99": 0.0}
	var sorted: Array = samples.duplicate()
	sorted.sort()
	return {"samples": sorted.size(), "p50": float(sorted[maxi(0, ceili(sorted.size() * 0.50) - 1)]),
		"p95": float(sorted[maxi(0, ceili(sorted.size() * 0.95) - 1)]),
		"p99": float(sorted[maxi(0, ceili(sorted.size() * 0.99) - 1)])}


func _ms(start: int) -> float:
	return float(Time.get_ticks_usec() - start) / 1000.0


func _fail(reason: String) -> void:
	printerr("GPU_FIELD_ERROR: ", reason)
	quit(1)
