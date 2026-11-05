extends SceneTree
## Isolated CPU source-change capacity probe, not a Main/world/FPS benchmark.
## Run under an external 30 s / 1 GiB process guard with user arguments:
## -- [side=512] [radius=8] [field_work=4096] [cell_budget=17]
## All source projections exist at world time zero; 20 C is an explicit test
## initial condition, not a recovered temperature for a historical world.

const Cache = preload("res://scripts/sim/environment_field_cache.gd")
const Index = preload("res://scripts/sim/environment_field_index.gd")
const Temperature = preload("res://scripts/sim/environment_temperature_state.gd")
const SourceChange = preload("res://scripts/sim/environment_source_change.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const DEADLINE_USEC: int = 25_000_000
const CHANNELS: int = 7
const TILE_SIDE: int = 16
const CHECK_INTERVAL: int = 64
const HORIZON_MS: int = 60_000
const SPECIAL: Array[int] = [50_000, 50_000, 50_000, 50_000, 50_000, 50_000, 20_000]
const CHECKSUM_MODULUS: int = 1_000_000_007

var _started_usec: int = 0
var _phase: String = "arguments"
var _populated: int = 0
var _side: int = 0
var _finished: bool = false


func _initialize() -> void:
	_started_usec = Time.get_ticks_usec()
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 4:
		_fail("expected side [radius [field_work [cell_budget]]]")
		return
	for arg: String in args:
		if not arg.is_valid_int():
			_fail("all arguments must be integers")
			return
	_side = int(args[0]) if args.size() > 0 else 512
	var radius: int = int(args[1]) if args.size() > 1 else 8
	var work_budget: int = int(args[2]) if args.size() > 2 else 4096
	var cell_budget: int = int(args[3]) if args.size() > 3 else 17
	if _side not in [64, 512, 1024, 2048] or radius not in [4, 8] or work_budget < 1 or work_budget > Cache.MAX_WORK or cell_budget < 1 or cell_budget > TILE_SIDE * TILE_SIDE:
		_fail("side must be 64/512/1024/2048, radius 4/8, work 1..MAX_WORK, cells 1..256")
		return
	var map_size := Vector2i(_side, _side)
	var count: int = _side * _side
	var destination := Vector2i(_side - 1, _side - 1)
	_phase = "construct"
	var started: int = Time.get_ticks_usec()
	var field := Cache.new()
	var temperature := Temperature.new()
	var coordinator := SourceChange.new()
	var construct_ms: float = _ms(started)
	if not _within_deadline():
		return
	_phase = "field_configure"
	started = Time.get_ticks_usec()
	var field_configured: bool = field.configure(map_size, count)
	var field_configure_ms: float = _ms(started)
	if not field_configured:
		_fail("field configure rejected the fixture")
		return
	if not _within_deadline():
		return
	_phase = "temperature_configure"
	started = Time.get_ticks_usec()
	var temperature_configured: bool = temperature.configure(map_size, 512, 0)
	var temperature_configure_ms: float = _ms(started)
	if not temperature_configured:
		_fail("temperature configure rejected the fixture")
		return
	if not _within_deadline():
		return
	_phase = "load_settings"
	started = Time.get_ticks_usec()
	var climate: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/climate.json"))
	var weather: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/weather.json"))
	var settings_load_ms: float = _ms(started)
	if not climate is Dictionary or not weather is Dictionary:
		_fail("climate or weather content is unavailable")
		return
	if not _within_deadline():
		return
	_phase = "coordinator_configure"
	var settings: Dictionary = {"climate": climate, "weather": weather, "weather_epoch_ms": 0,
		"seed": 42, "tau_ms": 1000, "tide_grid_ms": 1000}
	started = Time.get_ticks_usec()
	var coordinator_configured: bool = coordinator.configure(field, temperature, settings, Callable(self, "_initial"))
	var coordinator_configure_ms: float = _ms(started)
	if not coordinator_configured:
		_fail("source-change coordinator rejected the fixture")
		return
	if not _within_deadline():
		return
	_phase = "populate"
	started = Time.get_ticks_usec()
	var channels: Array[int] = [0, 0, 0, 0, 0, 0, 0]
	for slot: int in count:
		_fill_channels(slot, channels)
		@warning_ignore("integer_division")
		var cell := Vector2i(slot % _side, slot / _side)
		var accepted: Dictionary = field.set_source(slot, cell, radius, channels)
		if not bool(accepted.get("ok", false)) or not bool(accepted.get("changed", false)):
			_fail("real source insertion failed at slot %d: %s" % [slot, str(accepted)])
			return
		_populated = slot + 1
		if (slot & 255) == 0 and not _within_deadline():
			return
	var populate_ms: float = _ms(started)
	if not _within_deadline():
		return
	var before_field: Dictionary = field.diagnostics()
	var before_temperature: Dictionary = temperature.snapshot()
	if int(before_field.source_count) != count or int(before_field.revision) != count or not before_temperature.get("cells", []).is_empty():
		_fail("populated fixture count, revision, or initial temperature is invalid")
		return
	_phase = "begin"
	started = Time.get_ticks_usec()
	var opened: Dictionary = coordinator.begin(0, "set", {"cell": destination, "radius": radius, "channels": SPECIAL}, 0, HORIZON_MS)
	var begin_ms: float = _ms(started)
	if not bool(opened.get("ok", false)) or int(opened.get("tiles", -1)) != 2:
		_fail("opposite corners must produce exactly two candidate tiles: " + str(opened))
		return
	if not _within_deadline() or not _private_unchanged(field, temperature, count, before_field, before_temperature):
		return
	var handle: Variant = opened.handle
	_phase = "premature_finish"
	started = Time.get_ticks_usec()
	var premature: Dictionary = coordinator.finish(handle)
	var premature_finish_ms: float = _ms(started)
	if bool(premature.get("ok", true)) or str(premature.get("reason", "")) != "pending":
		_fail("incomplete candidate unexpectedly finished")
		return
	var phase_name: String = "field"
	var field_samples: Array[float] = []
	var input_samples: Array[float] = []
	var temperature_samples: Array[float] = []
	var total_work: int = 0
	var input_cells: int = 0
	var temperature_cells: int = 0
	var iterations: int = 0
	var drive_started: int = Time.get_ticks_usec()
	while true:
		_phase = "step_" + phase_name
		if not _within_deadline():
			return
		started = Time.get_ticks_usec()
		var progress: Dictionary = coordinator.step(handle, work_budget, cell_budget)
		var step_ms: float = _ms(started)
		if not bool(progress.get("ok", false)):
			_fail("candidate step failed: " + str(progress))
			return
		var work: int = int(progress.get("field_work", -1))
		var cells: int = int(progress.get("cells", -1))
		if work < 0 or work > work_budget or cells < 0 or cells > cell_budget or int(progress.get("tiles", -1)) != 2:
			_fail("step exceeded a declared budget or changed tile count")
			return
		match phase_name:
			"field":
				field_samples.append(step_ms)
				total_work += work
			"input":
				input_samples.append(step_ms)
				input_cells += cells
			"temperature":
				temperature_samples.append(step_ms)
				temperature_cells += cells
			_:
				_fail("unexpected phase: " + phase_name)
				return
		iterations += 1
		if iterations % CHECK_INTERVAL == 0 and not _private_unchanged(field, temperature, count, before_field, before_temperature):
			return
		phase_name = str(progress.get("phase", ""))
		if not bool(progress.get("pending", true)):
			if phase_name != "ready" or int(progress.get("completed_tiles", -1)) != 2:
				_fail("candidate claimed completion without two ready tiles")
				return
			break
	var drive_ms: float = _ms(drive_started)
	if input_cells != 512 or temperature_cells != 512:
		_fail("candidate must visit exactly two full 16x16 tiles in each temperature phase")
		return
	if not _within_deadline() or not _private_unchanged(field, temperature, count, before_field, before_temperature):
		return
	_phase = "finish"
	started = Time.get_ticks_usec()
	var sealed: Dictionary = coordinator.finish(handle)
	var finish_ms: float = _ms(started)
	if not bool(sealed.get("ok", false)) or not coordinator.can_commit(sealed.get("proof")).get("ok", false):
		_fail("ready candidate did not seal and preflight")
		return
	if not _within_deadline() or not _private_unchanged(field, temperature, count, before_field, before_temperature):
		return
	_phase = "commit"
	started = Time.get_ticks_usec()
	var committed: Dictionary = coordinator.commit(sealed.proof)
	var commit_ms: float = _ms(started)
	if not bool(committed.get("ok", false)) or int(committed.get("published_tiles", -1)) != 2:
		_fail("field and temperature commit failed: " + str(committed))
		return
	var after_field: Dictionary = field.diagnostics()
	var after_temperature: Dictionary = temperature.snapshot()
	if int(after_field.source_count) != count or int(after_field.revision) != int(before_field.revision) + 1 or after_temperature.get("cells", []).size() != 512:
		_fail("commit published incorrect source, revision, or tracked-cell counts")
		return
	for row: Dictionary in after_temperature.cells:
		if int(row.response.start_ms) != 0 or float(row.response.initial_value) != 20.0 or int(row.response.until_ms) < 500:
			_fail("a published temperature anchor lost its explicit initial condition")
			return
	if not _within_deadline():
		return
	_phase = "temperature_checks"
	var checked_points: Array[Vector2i] = [Vector2i.ZERO, destination]
	var actual: Dictionary = _check_actual(temperature, after_temperature, checked_points)
	if not bool(actual.get("ok", false)):
		return
	_phase = "oracle"
	var first: Dictionary = _compare_tile(field, radius, Rect2i(Vector2i.ZERO, Vector2i(TILE_SIDE, TILE_SIDE)), false)
	if not bool(first.get("ok", false)):
		return
	var last: Dictionary = _compare_tile(field, radius, Rect2i(Vector2i(_side - TILE_SIDE, _side - TILE_SIDE), Vector2i(TILE_SIDE, TILE_SIDE)), true)
	if not bool(last.get("ok", false)):
		return
	if int(first.changed_cells) + int(last.changed_cells) == 0 or not _within_deadline():
		if not _finished:
			_fail("the moved source did not alter any sampled channel")
		return
	var report: Dictionary = {"status": "passed", "side": _side, "radius": radius,
		"world_time_ms": 0, "horizon_ms": HORIZON_MS, "source_count": count,
		"source_revision_before": before_field.revision, "source_revision_after": after_field.revision,
		"source_pattern": "one projection per map cell; slot 0 moves to the opposite corner",
		"source_channels": SPECIAL, "candidate_tiles": 2, "candidate_temperature_cells": 512,
		"actual_changed_field_cells": int(first.changed_cells) + int(last.changed_cells),
		"oracle_cells": int(first.cells) + int(last.cells), "oracle_channels": (int(first.cells) + int(last.cells)) * CHANNELS,
		"oracle_first": first, "oracle_last": last, "temperature_points": actual.points,
		"budgets": {"field_work": work_budget, "cells": cell_budget},
		"steps": {"iterations": iterations, "field_work": total_work, "input_cells": input_cells,
			"temperature_cells": temperature_cells, "field": _stats(field_samples),
			"input": _stats(input_samples), "temperature": _stats(temperature_samples)},
		"timing_ms": {"construct": construct_ms, "field_configure": field_configure_ms,
			"temperature_configure": temperature_configure_ms, "settings_load": settings_load_ms,
			"coordinator_configure": coordinator_configure_ms, "populate": populate_ms,
			"begin": begin_ms, "premature_finish": premature_finish_ms, "drive": drive_ms,
			"finish": finish_ms, "commit": commit_ms, "total": _ms(_started_usec)},
		"hardware": {"engine": Engine.get_version_info(), "os": OS.get_name(),
			"processor": OS.get_processor_name(), "logical_processors": OS.get_processor_count(),
			"debug_build": OS.has_feature("debug")},
		"limitations": ["isolated projections, not actual items or ordinary Main", "not FPS, room, GPU, or full-map rebuild",
			"all sources created at world time zero; provider explicitly supplies 20 C",
			"only two corner tiles and their local halos are checked", "step percentiles are within one run, not repeated-run percentiles",
			"external process guard records memory and enforces 30 s / 1 GiB", "optional cancellation scenario not run"]}
	if not _within_deadline():
		return
	_finished = true
	print("SOURCE_CHANGE_CAPACITY_JSON:", JSON.stringify(report, "", true, true))
	quit(0)


func _initial(_cell: Vector2i, _at_ms: int) -> Dictionary:
	return {"ok": true, "value_c": 20.0}


func _private_unchanged(field: RefCounted, temperature: RefCounted, count: int, before_field: Dictionary, before_temperature: Dictionary) -> bool:
	var current: Dictionary = field.diagnostics()
	if int(current.source_count) != count or int(current.revision) != int(before_field.revision) or temperature.snapshot() != before_temperature:
		_fail("candidate published a source or temperature before commit")
		return false
	return _within_deadline()


func _check_actual(temperature: RefCounted, snapshot: Dictionary, points: Array[Vector2i]) -> Dictionary:
	var report: Array[Dictionary] = []
	for cell: Vector2i in points:
		var now: Dictionary = temperature.actual_at(cell, 0)
		var future: Dictionary = temperature.actual_at(cell, 500)
		var target: float = NAN
		for row: Dictionary in snapshot.cells:
			if row.cell == [cell.x, cell.y]:
				target = float(row.response.target_value)
				break
		if not bool(now.get("ok", false)) or not bool(future.get("ok", false)) or not is_finite(target):
			_fail("temperature projection unavailable at %s" % str(cell))
			return {"ok": false}
		var at_zero: float = float(now.value_c)
		var at_500: float = float(future.value_c)
		var expected: float = target + (20.0 - target) * exp(-0.5)
		if not is_finite(at_500) or at_zero != 20.0 or absf(at_500 - expected) > maxf(1.0e-7, absf(expected) * 1.0e-10) or absf(at_500 - target) > absf(at_zero - target):
			_fail("temperature did not remain continuous and approach its target at %s" % str(cell))
			return {"ok": false}
		report.append({"cell": [cell.x, cell.y], "at_0_c": at_zero, "at_500_c": at_500, "target_c": target})
	return {"ok": true, "points": report}


func _compare_tile(field: RefCounted, radius: int, rect: Rect2i, destination_tile: bool) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var halo: int = radius - 1
	var min_x: int = maxi(0, rect.position.x - halo)
	var min_y: int = maxi(0, rect.position.y - halo)
	var max_x: int = mini(_side, rect.end.x + halo)
	var max_y: int = mini(_side, rect.end.y + halo)
	var index := Index.new()
	if not index.configure(Vector2i(_side, _side), (max_x - min_x) * (max_y - min_y) + 1):
		_fail("local reference index configuration failed")
		return {"ok": false}
	var channels: Array[int] = [0, 0, 0, 0, 0, 0, 0]
	var source_count: int = 0
	for y: int in range(min_y, max_y):
		for x: int in range(min_x, max_x):
			var slot: int = y * _side + x
			if slot == 0:
				continue
			_fill_channels(slot, channels)
			var inserted: Dictionary = index.set_source({"id": "s%d" % slot, "cell": Vector2i(x, y), "radius": radius, "channels": channels})
			if not bool(inserted.get("ok", false)):
				_fail("local oracle source rejected: " + str(inserted))
				return {"ok": false}
			source_count += 1
		if not _within_deadline():
			return {"ok": false}
	var build_ms: float = _ms(started)
	started = Time.get_ticks_usec()
	var without_moved: Array[PackedInt64Array] = []
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var baseline: Dictionary = index.sample_base(Vector2i(x, y))
			if not bool(baseline.get("ok", false)) or baseline.channels.size() != CHANNELS:
				_fail("local oracle baseline query failed")
				return {"ok": false}
			without_moved.append(baseline.channels)
		if not _within_deadline():
			return {"ok": false}
	var baseline_ms: float = _ms(started)
	var moved: Dictionary = index.set_source({"id": "moved", "cell": Vector2i(_side - 1, _side - 1), "radius": radius, "channels": SPECIAL})
	if not bool(moved.get("ok", false)):
		_fail("local oracle could not insert moved source")
		return {"ok": false}
	started = Time.get_ticks_usec()
	var checksum: int = 0
	var before_checksum: int = 0
	var changed: int = 0
	var sampled: int = 0
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			var observed: Dictionary = field.read_base(cell)
			var expected: Dictionary = index.sample_base(cell)
			if not bool(observed.get("ok", false)) or bool(observed.get("pending", true)) or not bool(expected.get("ok", false)) or observed.channels.size() != CHANNELS or expected.channels.size() != CHANNELS:
				_fail("published tile or reference result unavailable at %s" % str(cell))
				return {"ok": false}
			var weight: int = 0
			if not destination_tile:
				var kernel: Dictionary = Rules.kernel(cell, radius)
				if not bool(kernel.get("ok", false)):
					_fail("old-location kernel unavailable")
					return {"ok": false}
				weight = int(kernel.weight)
			var differs: bool = false
			for channel: int in CHANNELS:
				var actual: int = int(observed.channels[channel])
				var reference: int = int(expected.channels[channel])
				if actual != reference:
					_fail("field/oracle mismatch at %s channel %d: %d != %d" % [str(cell), channel, actual, reference])
					return {"ok": false}
				var previous: int = int(without_moved[sampled][channel])
				if not destination_tile:
					@warning_ignore("integer_division")
					var old_special: int = (SPECIAL[channel] * weight + Rules.SCALE / 2) / Rules.SCALE
					previous = maxi(previous, old_special)
				differs = differs or previous != reference
				checksum = (checksum * 65_599 + reference) % CHECKSUM_MODULUS
				before_checksum = (before_checksum * 65_599 + previous) % CHECKSUM_MODULUS
			if differs:
				changed += 1
			sampled += 1
		if not _within_deadline():
			return {"ok": false}
	return {"ok": true, "origin": [rect.position.x, rect.position.y], "cells": sampled,
		"changed_cells": changed, "reference_sources": source_count + 1,
		"halo_bounds": [min_x, min_y, max_x, max_y], "checksum": checksum,
		"before_checksum": before_checksum, "build_ms": build_ms, "baseline_ms": baseline_ms,
		"compare_ms": _ms(started)}


static func _fill_channels(slot: int, channels: Array[int]) -> void:
	for channel: int in CHANNELS:
		channels[channel] = 1000 + posmod(slot * 73 + channel * 997, 7001)
	if slot == 0:
		for channel: int in CHANNELS:
			channels[channel] = SPECIAL[channel]


static func _stats(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {"samples": 0, "p95_ms": 0.0, "p99_ms": 0.0, "max_ms": 0.0}
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	var count: int = sorted.size()
	return {"samples": count, "p95_ms": sorted[maxi(0, ceili(count * 0.95) - 1)],
		"p99_ms": sorted[maxi(0, ceili(count * 0.99) - 1)], "max_ms": sorted[count - 1]}


func _within_deadline() -> bool:
	if Time.get_ticks_usec() - _started_usec > DEADLINE_USEC:
		_fail("25-second internal deadline exceeded")
		return false
	return true


static func _ms(started: int) -> float:
	return float(Time.get_ticks_usec() - started) / 1000.0


func _fail(reason: String) -> void:
	if _finished:
		return
	_finished = true
	printerr("SOURCE_CHANGE_CAPACITY_ERROR: ", reason)
	print("SOURCE_CHANGE_CAPACITY_JSON:", JSON.stringify({"status": "failed", "phase": _phase,
		"reason": reason, "side": _side, "populated_sources": _populated, "elapsed_ms": _ms(_started_usec)}, "", true, true))
	quit(1)
