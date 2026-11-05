extends SceneTree
## Dense projection / compact-cache F1 probe. Optional positional arguments:
## size (32, 64, 512, 1024, 2048) and change percentage (0, 1, 10, 100).
## Run only under an external time/memory guard; this script does not set one.

const Cache = preload("res://scripts/sim/environment_field_cache.gd")
const Tide = preload("res://scripts/sim/environment_field_tide.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")

const SIZES: Array[int] = [32, 64, 512, 1024, 2048]
const CHANGE_PERCENTAGES: Array[int] = [0, 1, 10, 100]
const QUERY_COUNT: int = 1024
const CHANNELS: int = 7
const BATCH_SIZE: int = 64
const MAX_WORK_PER_CALL: int = 8192
const MAX_TILES_PER_CALL: int = 1
const MAX_REBUILD_PROGRESS: int = 128
const TIDE_SEED: int = 20261105
const QUERY_TIME_MS: int = 123456789
const NEUTRAL_MILLI: int = 20000


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 2:
		_fail("expected optional positional arguments: size change_percentage")
		return
	for arg: String in args:
		if not arg.is_valid_int():
			_fail("size and change_percentage must be integers")
			return
	var size: int = int(args[0]) if args.size() >= 1 else 64
	var percentage: int = int(args[1]) if args.size() >= 2 else 1
	if size not in SIZES or percentage not in CHANGE_PERCENTAGES:
		_fail("size must be 32/64/512/1024/2048 and change_percentage 0/1/10/100")
		return
	var total_sources: int = size * size
	@warning_ignore("integer_division")
	var tile_columns: int = (size + Cache.TILE_SIZE - 1) / Cache.TILE_SIZE
	var total_tiles: int = tile_columns * tile_columns
	var cache: RefCounted = Cache.new()
	var started: int = Time.get_ticks_usec()
	if not cache.configure(Vector2i(size, size), total_sources):
		_fail("cache rejected the requested size or capacity")
		return
	print("FIELD_CACHE_PROGRESS: populate rows=0/%d sources=0/%d" % [size, total_sources])
	for y: int in size:
		for x: int in size:
			var slot: int = y * size + x
			var cell := Vector2i(x, y)
			var result: Dictionary = cache.set_source(slot, cell, _radius(cell), _channels(slot, cell, false))
			if not bool(result.get("ok", false)) or not bool(result.get("changed", false)):
				_fail("populate slot %d failed: %s" % [slot, str(result)])
				return
		if (y + 1) % 16 == 0 or y + 1 == size:
			print("FIELD_CACHE_PROGRESS: populate rows=%d/%d sources=%d/%d elapsed_ms=%.3f" % [y + 1, size, (y + 1) * size, total_sources, _ms_since(started)])
	var populate_ms: float = _ms_since(started)
	var populated: Dictionary = cache.diagnostics()
	if int(populated.get("source_count", -1)) != total_sources or int(populated.get("revision", -1)) != total_sources or int(populated.get("cached_tiles", -1)) != 0 or int(populated.get("pending_tiles", -1)) != 0:
		_fail("dense population has incorrect source/revision counts or unexpectedly built tiles")
		return

	# Request exactly one cell in every tile; this queues the entire field
	# without enumerating or hashing its individual cell/channel values.
	started = Time.get_ticks_usec()
	print("FIELD_CACHE_PROGRESS: request_tiles=0/%d" % total_tiles)
	var requested: int = 0
	for tile_y: int in tile_columns:
		for tile_x: int in tile_columns:
			var cell := Vector2i(tile_x * Cache.TILE_SIZE, tile_y * Cache.TILE_SIZE)
			var result: Dictionary = cache.read_base(cell)
			if not bool(result.get("ok", false)) or not bool(result.get("pending", false)):
				_fail("initial tile request at %s failed or was already published: %s" % [str(cell), str(result)])
				return
			requested += 1
		if tile_y % 16 == 15 or tile_y + 1 == tile_columns:
			print("FIELD_CACHE_PROGRESS: request_tiles=%d/%d elapsed_ms=%.3f" % [requested, total_tiles, _ms_since(started)])
	var request_tiles_ms: float = _ms_since(started)
	var queued: Dictionary = cache.diagnostics()
	if int(queued.get("cached_tiles", -1)) != total_tiles or int(queued.get("pending_tiles", -1)) != total_tiles or int(queued.get("revision", -1)) != total_sources:
		_fail("full-map requests did not queue exactly one record per tile")
		return
	var initial_rebuild: Dictionary = _rebuild(cache, total_tiles, total_sources, "initial")
	if initial_rebuild.is_empty():
		return
	var built: Dictionary = cache.diagnostics()
	if int(built.get("source_count", -1)) != total_sources or int(built.get("revision", -1)) != total_sources or int(built.get("cached_tiles", -1)) != total_tiles or int(built.get("pending_tiles", -1)) != 0:
		_fail("initial rebuild did not publish all requested tiles")
		return

	var points: Array[Vector2i] = _sample_points(size, QUERY_COUNT)
	var multipliers := PackedInt64Array()
	var tide_batches := PackedInt64Array()
	var tide_checksum: int = 0
	started = Time.get_ticks_usec()
	for batch_start: int in range(0, QUERY_COUNT, BATCH_SIZE):
		var batch_started: int = Time.get_ticks_usec()
		for i: int in range(batch_start, mini(QUERY_COUNT, batch_start + BATCH_SIZE)):
			var tide: Dictionary = Tide.sample(TIDE_SEED, points[i], QUERY_TIME_MS)
			if not bool(tide.get("ok", false)):
				_fail("sampled tide query failed at %s: %s" % [str(points[i]), str(tide)])
				return
			var multiplier: int = int(tide.multiplier)
			if multiplier < Tide.MIN_MULTIPLIER or multiplier > Tide.SCALE:
				_fail("sampled tide multiplier is outside its declared range")
				return
			multipliers.append(multiplier)
			tide_checksum += multiplier
		tide_batches.append(Time.get_ticks_usec() - batch_started)
	var tide_wall_ms: float = _ms_since(started)

	# Query each sampled cell only once. Retain at most one 64-cell batch for
	# separately timed thermal/five-element application; do not scan the full
	# field again to produce a checksum.
	var query_batches := PackedInt64Array()
	var apply_batches := PackedInt64Array()
	var query_checksum: int = 0
	var applied_checksum: int = 0
	var sampled_tiles: Dictionary = {}
	var edge_samples: int = 0
	started = Time.get_ticks_usec()
	for batch_start: int in range(0, QUERY_COUNT, BATCH_SIZE):
		var batch_values: Array = []
		var batch_started: int = Time.get_ticks_usec()
		var batch_end: int = mini(QUERY_COUNT, batch_start + BATCH_SIZE)
		for i: int in range(batch_start, batch_end):
			var cell: Vector2i = points[i]
			var result: Dictionary = cache.read_base(cell)
			if not bool(result.get("ok", false)) or bool(result.get("pending", true)) or int(result.get("revision", -1)) != total_sources:
				_fail("published cache query at %s failed or remained pending: %s" % [str(cell), str(result)])
				return
			var values: PackedInt32Array = result.channels
			if values.size() != CHANNELS:
				_fail("published cache query did not return seven channels")
				return
			batch_values.append(values)
			for channel: int in CHANNELS:
				query_checksum += int(values[channel]) * (channel + 1)
			@warning_ignore("integer_division")
			sampled_tiles[Vector2i(cell.x / Cache.TILE_SIZE, cell.y / Cache.TILE_SIZE)] = true
			if cell.x == 0 or cell.y == 0 or cell.x == size - 1 or cell.y == size - 1:
				edge_samples += 1
		query_batches.append(Time.get_ticks_usec() - batch_started)
		batch_started = Time.get_ticks_usec()
		for offset: int in batch_values.size():
			var values: PackedInt32Array = batch_values[offset]
			var multiplier: int = multipliers[batch_start + offset]
			var target: Dictionary = Rules.thermal_target(NEUTRAL_MILLI, values[5], values[6], multiplier)
			if not bool(target.get("ok", false)):
				_fail("sampled thermal projection failed: %s" % str(target))
				return
			applied_checksum += int(target.temperature_milli)
			for channel: int in 5:
				@warning_ignore("integer_division")
				var scaled: int = (int(values[channel]) * multiplier + Rules.SCALE / 2) / Rules.SCALE
				applied_checksum += scaled * (channel + 1)
		apply_batches.append(Time.get_ticks_usec() - batch_started)
		print("FIELD_CACHE_PROGRESS: sampled_queries=%d/%d elapsed_ms=%.3f" % [batch_end, QUERY_COUNT, _ms_since(started)])
	var query_stage_wall_ms: float = _ms_since(started)
	var after_queries: Dictionary = cache.diagnostics()
	if after_queries != built:
		_fail("reading built tiles and tide changed cache diagnostics")
		return

	@warning_ignore("integer_division")
	var change_count: int = total_sources * percentage / 100
	@warning_ignore("integer_division")
	var stride: int = ((total_sources * 618033) / 1000000) | 1
	var touched: Array[bool] = []
	touched.resize(total_tiles)
	touched.fill(false)
	var expected_dirty: int = 0
	var old_area_sum: int = 0
	var new_area_sum: int = 0
	var update_api_us: int = 0
	var map_rect := Rect2i(Vector2i.ZERO, Vector2i(size, size))
	@warning_ignore("integer_division")
	var progress_interval: int = maxi(1, (change_count + 63) / 64)
	started = Time.get_ticks_usec()
	print("FIELD_CACHE_PROGRESS: updates=0/%d mode=%d%%" % [change_count, percentage])
	for i: int in change_count:
		# total_sources is a power of two and stride is odd: every slot is
		# unique, including the 100% mode, without a world-sized used set.
		var slot: int = (i * stride) % total_sources
		@warning_ignore("integer_division")
		var cell := Vector2i(slot % size, slot / size)
		var radius: int = _radius(cell)
		var channels: PackedInt64Array = _channels(slot, cell, true)
		var update_started: int = Time.get_ticks_usec()
		var result: Dictionary = cache.set_source(slot, cell, radius, channels)
		update_api_us += Time.get_ticks_usec() - update_started
		if not bool(result.get("ok", false)) or not bool(result.get("changed", false)):
			_fail("grade update at slot %d failed: %s" % [slot, str(result)])
			return
		var distance: int = radius - 1
		var expected_rect := Rect2i(cell - Vector2i(distance, distance), Vector2i(distance * 2 + 1, distance * 2 + 1)).intersection(map_rect)
		var old_area: Rect2i = result.old_area
		var new_area: Rect2i = result.new_area
		if old_area != expected_rect or new_area != expected_rect:
			_fail("grade update returned incorrect old/new footprints at slot %d" % slot)
			return
		old_area_sum += old_area.size.x * old_area.size.y
		new_area_sum += new_area.size.x * new_area.size.y
		expected_dirty += _mark_tiles(touched, old_area, tile_columns)
		expected_dirty += _mark_tiles(touched, new_area, tile_columns)
		if (i + 1) % progress_interval == 0 or i + 1 == change_count:
			print("FIELD_CACHE_PROGRESS: updates=%d/%d expected_dirty=%d elapsed_ms=%.3f" % [i + 1, change_count, expected_dirty, _ms_since(started)])
	var update_wall_ms: float = _ms_since(started)
	var dirty: Dictionary = cache.diagnostics()
	if int(dirty.get("source_count", -1)) != total_sources or int(dirty.get("revision", -1)) != total_sources + change_count or int(dirty.get("cached_tiles", -1)) != total_tiles or int(dirty.get("pending_tiles", -1)) != expected_dirty:
		_fail("source changes did not produce the expected deduplicated dirty tiles and revisions")
		return
	if change_count > 0 and expected_dirty == 0:
		_fail("changed projections did not mark any cached tile dirty")
		return
	var changed_rebuild: Dictionary = _rebuild(cache, expected_dirty, total_sources + change_count, "changed")
	if changed_rebuild.is_empty():
		return
	var final_state: Dictionary = cache.diagnostics()
	if int(final_state.get("pending_tiles", -1)) != 0 or int(final_state.get("cached_tiles", -1)) != total_tiles or int(final_state.get("source_count", -1)) != total_sources or int(final_state.get("revision", -1)) != total_sources + change_count:
		_fail("changed rebuild did not finish or altered source ownership")
		return

	var report: Dictionary = {
		"version": 1, "size": size, "sources": total_sources, "query_count": QUERY_COUNT,
		"change_percentage": percentage, "engine": Engine.get_version_info(),
		"os": OS.get_name(), "debug_build": OS.has_feature("debug"), "historical_movement": false,
		"workload": {
			"density": "one source projection per cell; numeric slot equals baseline s_<linear> ID",
			"channels": "identical baseline deterministic seven grades in [1,20000], including hot and cold",
			"radii": "4 and 8 in a checkerboard", "tile_size": Cache.TILE_SIZE,
			"sample_seed": TIDE_SEED, "query_time_ms": QUERY_TIME_MS, "neutral_milli": NEUTRAL_MILLI,
			"sampling": "same as baseline: four unique corners then a coprime odd linear stride",
			"sampled_tiles": sampled_tiles.size(), "edge_samples": edge_samples,
			"sample_batch_size": BATCH_SIZE, "max_tiles_per_rebuild_call": MAX_TILES_PER_CALL,
			"max_work_per_rebuild_call": MAX_WORK_PER_CALL,
		},
		"populate": {"wall_ms": populate_ms, "sources": total_sources,
			"scope": "configure, generate, validate and index projections plus kernel tables and progress printing"},
		"initial_tile_requests": {"tiles": requested, "wall_ms": request_tiles_ms},
		"initial_rebuild": initial_rebuild,
		"cached_query": {"samples": QUERY_COUNT, "sum_batch_ms": _sum_ms(query_batches),
			"batch_ms": _distribution_ms(query_batches), "checksum": query_checksum},
		"tide_only": {"samples": QUERY_COUNT, "wall_ms": tide_wall_ms,
			"sum_batch_ms": _sum_ms(tide_batches), "batch_ms": _distribution_ms(tide_batches), "checksum": tide_checksum},
		"thermal_and_five_channel_apply": {"samples": QUERY_COUNT, "sum_batch_ms": _sum_ms(apply_batches),
			"batch_ms": _distribution_ms(apply_batches), "checksum": applied_checksum},
		"query_and_apply_stage_wall_ms": query_stage_wall_ms, "query_diagnostics_unchanged": true,
		"changes": {"percentage": percentage, "sources": change_count, "actual_fraction": float(change_count) / float(total_sources),
			"operation": "grade-only change at dispersed unique numeric slots; cell and radius unchanged",
			"registration_wall_ms": update_wall_ms, "sum_set_source_call_ms": float(update_api_us) / 1000.0,
			"old_area_sum": old_area_sum, "new_area_sum": new_area_sum,
			"area_semantics": "clipped per-source rectangle sums with overlaps, old and new coincide",
			"deduplicated_dirty_tiles": expected_dirty, "pending_tiles_reported_by_cache": int(dirty.pending_tiles),
			"rebuild": changed_rebuild},
		"final_diagnostics": final_state,
		"limitations": [
			"Synthetic source projections only; no real item, pile, actor or scene entity is created.",
			"This isolated cache does not measure Main, normal-world integration, FPS, rendering or frame time.",
			"Source grade changes are at fixed positions; movement, object transfer, time history and save/load are not measured.",
			"Point-query and tide timings describe 1024 sampled cells; full-map work is reported separately by actual budgeted tile rebuild calls.",
			"Timings include validation and bookkeeping as labeled; wall times include progress logging. Partial and terminated runs are not passing results.",
			"Peak memory and process time limits are measured and imposed by the external guard, not this worker."
		],
	}
	print("FIELD_CACHE_BENCH_JSON:" + JSON.stringify(report, "", true, true))
	quit(0)


func _rebuild(cache: RefCounted, tiles: int, revision: int, label: String) -> Dictionary:
	var pending: int = tiles
	var completed: int = 0
	var work_count: int = 0
	var calls: int = 0
	# Sparse microsecond histogram records every call exactly without keeping a
	# world-sized array of per-call timing samples on large maps.
	var duration_counts: Dictionary = {}
	var elapsed_us: int = 0
	var started: int = Time.get_ticks_usec()
	var last_log_ms: int = Time.get_ticks_msec()
	var logs: int = 0
	@warning_ignore("integer_division")
	var progress_step: int = maxi(1, (tiles + 63) / 64)
	var next_progress: int = progress_step
	print("FIELD_CACHE_PROGRESS: %s_rebuild tiles=0/%d work=0 calls=0" % [label, tiles])
	while pending > 0:
		var call_started: int = Time.get_ticks_usec()
		var result: Dictionary = cache.rebuild(MAX_TILES_PER_CALL, MAX_WORK_PER_CALL)
		var duration_us: int = Time.get_ticks_usec() - call_started
		duration_counts[duration_us] = int(duration_counts.get(duration_us, 0)) + 1
		elapsed_us += duration_us
		if not bool(result.get("ok", false)):
			_fail("%s rebuild call failed: %s" % [label, str(result)])
			return {}
		var made: int = int(result.get("completed", -1))
		var used: int = int(result.get("work", -1))
		var remaining: int = int(result.get("pending_tiles", -1))
		if made < 0 or made > MAX_TILES_PER_CALL or used < 1 or used > MAX_WORK_PER_CALL or remaining != pending - made or int(result.get("revision", -1)) != revision:
			_fail("%s rebuild violated its budget, revision, progress or queue accounting: %s" % [label, str(result)])
			return {}
		completed += made
		work_count += used
		pending = remaining
		calls += 1
		var now_ms: int = Time.get_ticks_msec()
		if logs < MAX_REBUILD_PROGRESS and (completed >= next_progress or now_ms - last_log_ms >= 1000 or pending == 0):
			print("FIELD_CACHE_PROGRESS: %s_rebuild tiles=%d/%d work=%d calls=%d elapsed_ms=%.3f" % [label, completed, tiles, work_count, calls, _ms_since(started)])
			last_log_ms = now_ms
			logs += 1
			while next_progress <= completed:
				next_progress += progress_step
	if completed != tiles:
		_fail("%s rebuild did not complete every queued tile" % label)
		return {}
	return {"tiles": completed, "calls": calls, "work_count": work_count,
		"max_tiles_per_call": MAX_TILES_PER_CALL, "max_work_per_call": MAX_WORK_PER_CALL,
		"wall_ms": _ms_since(started), "sum_call_ms": float(elapsed_us) / 1000.0,
		"call_ms": _histogram_distribution_ms(duration_counts, calls)}


func _channels(slot: int, cell: Vector2i, change_grade: bool) -> PackedInt64Array:
	# Exactly the same projection strengths as environment_field_baseline.gd.
	var result := PackedInt64Array()
	for channel: int in CHANNELS:
		var mixed: int = slot * 1009 + channel * 104729 + (cell.x ^ cell.y) * 8191
		result.append(1 + mixed % 20000)
	if change_grade:
		result[0] = 1 + result[0] % 20000
	return result


func _radius(cell: Vector2i) -> int:
	return 4 if (cell.x + cell.y) % 2 == 0 else 8


func _sample_points(size: int, count: int) -> Array[Vector2i]:
	# Keep this deterministic sequence aligned with the baseline worker.
	var total: int = size * size
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


func _mark_tiles(touched: Array[bool], area: Rect2i, columns: int) -> int:
	if area.size.x <= 0 or area.size.y <= 0:
		return 0
	@warning_ignore("integer_division")
	var min_x: int = area.position.x / Cache.TILE_SIZE
	@warning_ignore("integer_division")
	var min_y: int = area.position.y / Cache.TILE_SIZE
	@warning_ignore("integer_division")
	var max_x: int = (area.end.x - 1) / Cache.TILE_SIZE
	@warning_ignore("integer_division")
	var max_y: int = (area.end.y - 1) / Cache.TILE_SIZE
	var newly_touched: int = 0
	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			var id: int = y * columns + x
			if not touched[id]:
				touched[id] = true
				newly_touched += 1
	return newly_touched


func _ms_since(started: int) -> float:
	return float(Time.get_ticks_usec() - started) / 1000.0


func _sum_ms(values: PackedInt64Array) -> float:
	var total: int = 0
	for value: int in values:
		total += value
	return float(total) / 1000.0


func _distribution_ms(values: PackedInt64Array) -> Dictionary:
	if values.is_empty():
		return {"samples": 0, "p50": 0.0, "p95": 0.0, "p99": 0.0}
	var sorted: PackedInt64Array = values.duplicate()
	sorted.sort()
	return {"samples": sorted.size(), "p50": _percentile_ms(sorted, 0.50),
		"p95": _percentile_ms(sorted, 0.95), "p99": _percentile_ms(sorted, 0.99)}


func _histogram_distribution_ms(counts: Dictionary, samples: int) -> Dictionary:
	if samples == 0:
		return {"samples": 0, "p50": 0.0, "p95": 0.0, "p99": 0.0}
	var keys: Array = counts.keys()
	keys.sort()
	var targets: Array[int] = [ceili(float(samples) * 0.50), ceili(float(samples) * 0.95), ceili(float(samples) * 0.99)]
	var values: Array[float] = []
	var accumulated: int = 0
	for key: Variant in keys:
		accumulated += int(counts[key])
		while values.size() < targets.size() and accumulated >= targets[values.size()]:
			values.append(float(int(key)) / 1000.0)
	return {"samples": samples, "p50": values[0], "p95": values[1], "p99": values[2]}


func _percentile_ms(sorted: PackedInt64Array, fraction: float) -> float:
	var index: int = maxi(0, ceili(float(sorted.size()) * fraction) - 1)
	return float(sorted[index]) / 1000.0


func _fail(message: String) -> void:
	push_error("FIELD_CACHE_BENCH_ERROR: " + message)
	quit(1)
