extends SceneTree
## Bounded F1 probe of dense, rebuildable source projections. Run under an
## external process guard with optional positional arguments: size query_count.
## The index is populated densely, but the measured queries are only samples.

const Index = preload("res://scripts/sim/environment_field_index.gd")
const Tide = preload("res://scripts/sim/environment_field_tide.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")

const ALLOWED_SIZES: Array[int] = [32, 64, 128, 512, 1024, 2048]
const DEFAULT_SIZE: int = 64
const DEFAULT_QUERY_COUNT: int = 1024
const MAX_QUERY_COUNT: int = 16384
const MAX_CHANGES: int = 4096
const BATCH_SIZE: int = 64
const CHANNELS: int = 7
const TIDE_SEED: int = 20261105
const QUERY_TIME_MS: int = 123456789
const NEUTRAL_MILLI: int = 20000


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 2:
		_fail("expected optional positional arguments: size query_count")
		return
	for arg: String in args:
		if not arg.is_valid_int():
			_fail("size and query_count must be integers")
			return
	var size: int = int(args[0]) if args.size() >= 1 else DEFAULT_SIZE
	var query_count: int = int(args[1]) if args.size() >= 2 else DEFAULT_QUERY_COUNT
	if size not in ALLOWED_SIZES:
		_fail("size must be one of 32, 64, 128, 512, 1024 or 2048")
		return
	var source_count: int = size * size
	if query_count < 1 or query_count > mini(source_count, MAX_QUERY_COUNT):
		_fail("query_count must be between 1 and min(size squared, 16384)")
		return

	var started: int = Time.get_ticks_usec()
	var index: RefCounted = Index.new()
	if not index.configure(Vector2i(size, size), source_count):
		_fail("index rejected the requested map or source capacity")
		return
	print("FIELD_BENCH_PROGRESS: populate rows=0/%d sources=0/%d" % [size, source_count])
	for y: int in range(size):
		for x: int in range(size):
			var linear: int = y * size + x
			var result: Dictionary = index.set_source(_source(linear, size, false))
			if not bool(result.get("ok", false)) or not bool(result.get("changed", false)):
				_fail("source %d failed to populate: %s" % [linear, str(result)])
				return
		if (y + 1) % 16 == 0 or y + 1 == size:
			print("FIELD_BENCH_PROGRESS: populate rows=%d/%d sources=%d/%d elapsed_ms=%.3f" % [y + 1, size, (y + 1) * size, source_count, _ms_since(started)])
	var initialization_ms: float = _ms_since(started)
	var initial: Dictionary = index.diagnostics()
	if int(initial.get("source_count", -1)) != source_count or int(initial.get("revision", -1)) != source_count:
		_fail("populated index source count or revision differs from the actual source insertions")
		return

	# The bounded query coordinates are retained; base values are discarded
	# after each sample and later reacquired in batches of at most 64.
	var points: Array[Vector2i] = _sample_points(size, query_count)
	var visited_buckets: Dictionary = {}
	var edge_points: int = 0
	var base_batch_ms: Array[float] = []
	var checked_candidates: int = 0
	var base_checksum: int = 0
	started = Time.get_ticks_usec()
	for batch_start: int in range(0, query_count, BATCH_SIZE):
		var batch_started: int = Time.get_ticks_usec()
		var batch_end: int = mini(query_count, batch_start + BATCH_SIZE)
		for i: int in range(batch_start, batch_end):
			var cell: Vector2i = points[i]
			var base: Dictionary = index.sample_base(cell)
			if not bool(base.get("ok", false)):
				_fail("base query at %s failed: %s" % [str(cell), str(base)])
				return
			var values: PackedInt64Array = base.channels
			if values.size() != CHANNELS or int(base.get("candidate_count", -1)) < 0:
				_fail("base query returned malformed channels or candidate count at %s" % str(cell))
				return
			checked_candidates += int(base.candidate_count)
			for channel: int in CHANNELS:
				base_checksum += values[channel] * (channel + 1)
			@warning_ignore("integer_division")
			visited_buckets[Vector2i(cell.x / Index.BUCKET_SIZE, cell.y / Index.BUCKET_SIZE)] = true
			if cell.x == 0 or cell.y == 0 or cell.x == size - 1 or cell.y == size - 1:
				edge_points += 1
		base_batch_ms.append(_ms_since(batch_started))
		print("FIELD_BENCH_PROGRESS: base queries=%d/%d candidates=%d elapsed_ms=%.3f" % [batch_end, query_count, checked_candidates, _ms_since(started)])
	var base_total_ms: float = _ms_since(started)

	var tide_batch_ms: Array[float] = []
	var tide_checksum: int = 0
	started = Time.get_ticks_usec()
	for batch_start: int in range(0, query_count, BATCH_SIZE):
		var batch_started: int = Time.get_ticks_usec()
		var batch_end: int = mini(query_count, batch_start + BATCH_SIZE)
		for i: int in range(batch_start, batch_end):
			var tide: Dictionary = Tide.sample(TIDE_SEED, points[i], QUERY_TIME_MS)
			if not bool(tide.get("ok", false)):
				_fail("tide query at %s failed: %s" % [str(points[i]), str(tide)])
				return
			var multiplier: int = int(tide.multiplier)
			if multiplier < Tide.MIN_MULTIPLIER or multiplier > Tide.SCALE:
				_fail("tide multiplier is outside its declared range")
				return
			tide_checksum += multiplier
		tide_batch_ms.append(_ms_since(batch_started))
		print("FIELD_BENCH_PROGRESS: tide queries=%d/%d elapsed_ms=%.3f" % [batch_end, query_count, _ms_since(started)])
	var tide_total_ms: float = _ms_since(started)

	# Requery the same coordinates into a single small batch. Time preparation
	# separately, so applying the sampled values never hides a second index scan
	# inside its cost and no full-grid field is built even on a 32-square map.
	var prepare_batch_ms: Array[float] = []
	var apply_batch_ms: Array[float] = []
	var prepare_candidates: int = 0
	var prepare_base_checksum: int = 0
	var prepare_tide_checksum: int = 0
	var applied_checksum: int = 0
	started = Time.get_ticks_usec()
	for batch_start: int in range(0, query_count, BATCH_SIZE):
		var batch_end: int = mini(query_count, batch_start + BATCH_SIZE)
		var batch_bases: Array = []
		var batch_multipliers := PackedInt64Array()
		var prepare_started: int = Time.get_ticks_usec()
		for i: int in range(batch_start, batch_end):
			var base: Dictionary = index.sample_base(points[i])
			if not bool(base.get("ok", false)):
				_fail("preparation base query at %s failed: %s" % [str(points[i]), str(base)])
				return
			var values: PackedInt64Array = base.channels
			if values.size() != CHANNELS or int(base.get("candidate_count", -1)) < 0:
				_fail("preparation base query returned malformed channels or candidate count")
				return
			var tide: Dictionary = Tide.sample(TIDE_SEED, points[i], QUERY_TIME_MS)
			if not bool(tide.get("ok", false)):
				_fail("preparation tide query at %s failed: %s" % [str(points[i]), str(tide)])
				return
			var multiplier: int = int(tide.multiplier)
			batch_bases.append(values)
			batch_multipliers.append(multiplier)
			prepare_candidates += int(base.candidate_count)
			prepare_tide_checksum += multiplier
			for channel: int in CHANNELS:
				prepare_base_checksum += values[channel] * (channel + 1)
		prepare_batch_ms.append(_ms_since(prepare_started))
		var batch_started: int = Time.get_ticks_usec()
		for i: int in range(batch_bases.size()):
			var values: PackedInt64Array = batch_bases[i]
			var multiplier: int = batch_multipliers[i]
			var thermal: Dictionary = Rules.thermal_target(NEUTRAL_MILLI, values[5], values[6], multiplier)
			if not bool(thermal.get("ok", false)):
				_fail("thermal target at %s failed: %s" % [str(points[batch_start + i]), str(thermal)])
				return
			applied_checksum += int(thermal.temperature_milli)
			for channel: int in 5:
				@warning_ignore("integer_division")
				var scaled: int = (values[channel] * multiplier + Rules.SCALE / 2) / Rules.SCALE
				applied_checksum += scaled * (channel + 1)
		apply_batch_ms.append(_ms_since(batch_started))
		print("FIELD_BENCH_PROGRESS: apply queries=%d/%d elapsed_ms=%.3f" % [batch_end, query_count, _ms_since(started)])
	var apply_stage_wall_ms: float = _ms_since(started)
	if prepare_candidates != checked_candidates or prepare_base_checksum != base_checksum or prepare_tide_checksum != tide_checksum:
		_fail("repeated base/tide queries did not reproduce the original candidates or checksums")
		return
	var after_queries: Dictionary = index.diagnostics()
	if after_queries != initial:
		_fail("base/tide/thermal queries changed the index diagnostics or revision")
		return

	@warning_ignore("integer_division")
	var changed_count: int = mini(MAX_CHANGES, maxi(1, source_count / 100))
	var changed_points: Array[Vector2i] = _sample_points(size, changed_count)
	var changed_batch_ms: Array[float] = []
	var changed_total_area: int = 0
	var changed_bounds := Rect2i()
	var map_rect := Rect2i(Vector2i.ZERO, Vector2i(size, size))
	started = Time.get_ticks_usec()
	for batch_start: int in range(0, changed_count, BATCH_SIZE):
		var batch_started: int = Time.get_ticks_usec()
		var batch_end: int = mini(changed_count, batch_start + BATCH_SIZE)
		for i: int in range(batch_start, batch_end):
			var cell: Vector2i = changed_points[i]
			var linear: int = cell.y * size + cell.x
			var changed_row: Dictionary = _source(linear, size, true)
			var result: Dictionary = index.set_source(changed_row)
			if not bool(result.get("ok", false)) or not bool(result.get("changed", false)):
				_fail("grade-only projection update %d failed: %s" % [linear, str(result)])
				return
			var radius: int = int(changed_row.radius)
			var expected_rect := Rect2i(cell - Vector2i(radius, radius), Vector2i(radius * 2 + 1, radius * 2 + 1)).intersection(map_rect)
			var affected: Rect2i = result.affected
			if affected != expected_rect:
				_fail("grade-only update returned the wrong old/new affected rectangle at %s" % str(cell))
				return
			changed_total_area += affected.size.x * affected.size.y
			changed_bounds = affected if i == 0 else changed_bounds.merge(affected)
		changed_batch_ms.append(_ms_since(batch_started))
		print("FIELD_BENCH_PROGRESS: updates=%d/%d elapsed_ms=%.3f" % [batch_end, changed_count, _ms_since(started)])
	var changed_total_ms: float = _ms_since(started)
	var after_changes: Dictionary = index.diagnostics()
	if int(after_changes.get("source_count", -1)) != source_count or int(after_changes.get("revision", -1)) != int(initial.revision) + changed_count:
		_fail("updates did not preserve source count or advance revision exactly once per changed projection")
		return

	var report: Dictionary = {
		"version": 1, "size": size, "sources": source_count, "query_count": query_count,
		"engine": Engine.get_version_info(), "os": OS.get_name(), "debug_build": OS.has_feature("debug"),
		"historical_movement": false,
		"workload": {
			"density": "one independent source projection per grid cell",
			"channels": "seven nonzero deterministic grades in [1, 20000], including hot and cold",
			"radii": "4 and 8 in a checkerboard", "sample_seed": TIDE_SEED,
			"query_time_ms": QUERY_TIME_MS, "neutral_milli": NEUTRAL_MILLI,
			"sampling": "unique corners first, then a coprime odd linear stride over the power-of-two square",
			"sampled_buckets": visited_buckets.size(), "edge_samples": edge_points,
			"batch_size": BATCH_SIZE, "last_batch_queries": (query_count - 1) % BATCH_SIZE + 1,
		},
		"initialization_ms": initialization_ms,
		"initialization_scope": "configure, generate each projection, validate, index, build radius templates and print progress",
		"initial_diagnostics": initial,
		"base_query": {"total_wall_ms": base_total_ms, "batch_ms": _distribution(base_batch_ms),
			"samples": query_count, "checked_candidates": checked_candidates, "checksum": base_checksum},
		"tide_only": {"total_wall_ms": tide_total_ms, "batch_ms": _distribution(tide_batch_ms),
			"samples": query_count, "checksum": tide_checksum},
		"apply_preparation": {"sum_batch_ms": _sum(prepare_batch_ms), "batch_ms": _distribution(prepare_batch_ms),
			"samples": query_count, "checked_candidates": prepare_candidates,
			"note": "repeat the same base and tide queries in bounded batches; excluded from application timing"},
		"apply_stage_wall_ms": apply_stage_wall_ms,
		"thermal_and_five_channel_apply": {"sum_batch_ms": _sum(apply_batch_ms), "batch_ms": _distribution(apply_batch_ms),
			"samples": query_count, "checksum": applied_checksum},
		"query_diagnostics_unchanged": true,
		"changed_cost": {"updates": changed_count, "requested_fraction": 0.01,
			"actual_fraction": float(changed_count) / float(source_count), "limit": MAX_CHANGES,
			"operation": "change one grade on each existing ID, preserving cell and radius",
			"total_wall_ms": changed_total_ms, "batch_ms": _distribution(changed_batch_ms),
			"last_batch_updates": (changed_count - 1) % BATCH_SIZE + 1,
			"old_rect_area_sum": changed_total_area, "new_rect_area_sum": changed_total_area,
			"returned_union_rect_area_sum": changed_total_area,
			"enclosing_rect": {"x": changed_bounds.position.x, "y": changed_bounds.position.y,
				"width": changed_bounds.size.x, "height": changed_bounds.size.y},
			"area_semantics": "clipped per-source rectangle areas summed with overlaps; old, new and returned union coincide for grade-only updates; no cells enumerated"},
		"final_diagnostics": after_changes,
		"limitations": [
			"Independent projections only: not real item, pile, actor, or scene instances.",
			"At most 16384 point queries; even if they cover a small entire map, no full-field build or update is measured and full F1 capacity is not established.",
			"The update probe changes source grades at fixed positions; historical movement and object transfer are not measured.",
			"No ordinary-world integration, save/load, response history, rendering, frame time, or FPS is measured.",
			"Batch timings include validation, result bookkeeping and checksums; total wall times also include progress printing. The last batch may be partial.",
			"The caller must impose and report external time and memory limits; a partial or terminated run is not a passing result."
		],
	}
	print("FIELD_BENCH_JSON:" + JSON.stringify(report, "", true, true))
	quit(0)


func _source(linear: int, size: int, change_grade: bool) -> Dictionary:
	@warning_ignore("integer_division")
	var cell := Vector2i(linear % size, linear / size)
	var channels := PackedInt64Array()
	for channel: int in CHANNELS:
		var mixed: int = linear * 1009 + channel * 104729 + (cell.x ^ cell.y) * 8191
		channels.append(1 + mixed % 20000)
	if change_grade:
		channels[0] = 1 + channels[0] % 20000
	return {"id": "s_" + str(linear), "cell": cell, "radius": 4 if (cell.x + cell.y) % 2 == 0 else 8, "channels": channels}


func _sample_points(size: int, count: int) -> Array[Vector2i]:
	var total: int = size * size
	# Every supported total is a power of two, so any odd stride is coprime.
	@warning_ignore("integer_division")
	var stride: int = ((total * 618033) / 1000000) | 1
	var points: Array[Vector2i] = []
	var used: Dictionary = {}
	for corner: Vector2i in [Vector2i.ZERO, Vector2i(size - 1, 0), Vector2i(0, size - 1), Vector2i(size - 1, size - 1)]:
		if points.size() >= count:
			break
		points.append(corner)
		used[corner.y * size + corner.x] = true
	var step: int = 0
	while points.size() < count:
		var linear: int = (step * stride) % total
		if not used.has(linear):
			@warning_ignore("integer_division")
			points.append(Vector2i(linear % size, linear / size))
			used[linear] = true
		step += 1
	return points


func _ms_since(started: int) -> float:
	return float(Time.get_ticks_usec() - started) / 1000.0


func _distribution(values: Array[float]) -> Dictionary:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return {"samples": sorted.size(), "p50": _percentile(sorted, 0.50),
		"p95": _percentile(sorted, 0.95), "p99": _percentile(sorted, 0.99)}


func _sum(values: Array[float]) -> float:
	var total: float = 0.0
	for value: float in values:
		total += value
	return total


func _percentile(sorted: Array[float], fraction: float) -> float:
	return sorted[maxi(0, ceili(float(sorted.size()) * fraction) - 1)]


func _fail(message: String) -> void:
	push_error("FIELD_BENCH_ERROR: " + message)
	quit(1)
