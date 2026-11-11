class_name SimEnvironmentSourceChange
extends RefCounted
## Coordinates one disposable source-field candidate and the original actual
## temperature owner's candidate. No item, clock, or live temperature is owned
## here. The item/action authority must still preflight its original object.
## All commit calls are synchronous, with no signal or user callback between
## the two domain publications. Pending preparation never publishes either.

const Field = preload("res://scripts/sim/environment_field_cache.gd")
const Temperature = preload("res://scripts/sim/environment_temperature_state.gd")
const Segments = preload("res://scripts/sim/environment_temperature_segments.gd")
const Climate = preload("res://scripts/sim/climate_rules.gd")
const Weather = preload("res://scripts/sim/weather.gd")
const Tide = preload("res://scripts/sim/environment_field_tide.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const Compiler = preload("res://scripts/sim/environment_target_compiler.gd")
const SIDE: int = 16
const SLOTS: int = SIDE * SIDE

var _field: RefCounted
var _temperature: RefCounted
var _settings: Dictionary = {}
var _initial_at: Callable
var _phases: RefCounted
var _phase_initial: Callable
var _compiler := Compiler.new()
var _active: Change
var _selective: bool = false
var workers: int = 0 # Production explicitly lends pure response readers.
var compute_work: Dictionary = {"batches": 0, "parallel_batches": 0, "tiles": 0, "prepare_usec": 0, "elapsed_usec": 0, "worker_usec": 0}


func configure(field: RefCounted, temperature: RefCounted, settings: Dictionary, initial_at: Callable, phases: RefCounted = null, phase_initial: Callable = Callable()) -> bool:
	if _field != null or not is_instance_of(field, Field) or not is_instance_of(temperature, Temperature) or not initial_at.is_valid():
		return false
	if not _keys(settings, ["climate", "weather", "weather_epoch_ms", "seed", "tau_ms", "tide_grid_ms"]) or not Climate.valid_definitions(settings.climate) or not Weather.valid_definitions(settings.weather):
		return false
	if not _integer(settings.weather_epoch_ms, 0, Temperature.MAX_TIME) or not settings.seed is int or not _integer(settings.tau_ms, 1, Temperature.Response.MAX_TAU_MS) or not _integer(settings.tide_grid_ms, 1, Temperature.MAX_TIME):
		return false
	if int(field.diagnostics().get("capacity", 0)) <= 0:
		return false
	if phases != null and (not phase_initial.is_valid() or not phases.has_method("begin_bulk")):
		return false
	if not _compiler.configure(settings):
		return false
	# Bound content is immutable for this coordinator. A different world/content
	# instance constructs another coordinator, never mutates an active context.
	_settings = settings.duplicate(true)
	_field = field
	_temperature = temperature
	_initial_at = initial_at
	_phases = phases
	_phase_initial = phase_initial
	_selective = field.has_candidate_change_masks()
	return true


func begin(slot: int, operation: String, source: Dictionary, at_ms: int, horizon_ms: int, allow_compute: bool = false) -> Dictionary:
	if _field == null:
		return _failure("not_configured")
	if _active != null:
		return _failure("busy")
	if at_ms < 0 or at_ms >= Temperature.MAX_TIME or horizon_ms <= at_ms or horizon_ms > Temperature.MAX_TIME:
		return _failure("time_out_of_range")
	var opened: Dictionary = _field.begin_source_change(slot, operation, source)
	if not bool(opened.get("ok", false)):
		return opened
	if allow_compute:
		_field.allow_source_compute(opened.handle)
	var tiles: Array[int] = opened.tile_ids
	var candidate := Change.new()
	candidate.handle = Handle.new()
	candidate.field_handle = opened.handle
	# The original full-tile contract reserves both owners at begin. A field
	# that supplies optional exact masks opens each response owner only if a
	# changed channel actually needs it. A missing mask still selects the full
	# tile, preserving complete initialization for a cold or dirty cache.
	if not _selective:
		var actual: Dictionary = _temperature.begin_bulk(at_ms, tiles.size())
		if not bool(actual.get("ok", false)):
			_field.cancel_source_change(opened.handle)
			return actual
		candidate.temperature_handle = actual.handle
		if _phases != null:
			var phase_opened: Dictionary = _phases.begin_bulk(at_ms, tiles.size())
			if not bool(phase_opened.get("ok", false)):
				_field.cancel_source_change(opened.handle)
				_temperature.cancel_bulk(actual.handle)
				return phase_opened
			candidate.phase_handle = phase_opened.handle
	candidate.tile_ids = tiles.duplicate()
	candidate.at_ms = at_ms
	candidate.horizon_ms = horizon_ms
	candidate.parallel_input = allow_compute and workers != 0 and tiles.size() > 1
	_active = candidate
	return {"ok": true, "handle": candidate.handle, "at_ms": at_ms, "tiles": tiles.size()}


func step(handle: Variant, field_work: int, cell_budget: int) -> Dictionary:
	if not _current(handle):
		return _failure("invalid_handle")
	if field_work < 1 or field_work > Field.MAX_WORK or cell_budget < 0 or cell_budget > SLOTS:
		return _failure("work_budget")
	if _active.phase == "ready":
		return _progress(0, 0)
	if _active.field_proof != null:
		var valid: Dictionary = _field.can_commit_source_change(_active.field_proof)
		if not bool(valid.get("ok", false)):
			return _abort(str(valid.get("reason", "source_stale")))
	if _active.phase == "field":
		var result: Dictionary = _field.step_source_change(_active.field_handle, field_work)
		if not bool(result.get("ok", false)):
			return _abort(str(result.get("reason", "source_unavailable")))
		if bool(result.get("done", false)):
			var finished: Dictionary = _field.finish_source_change(_active.field_handle)
			if not bool(finished.get("ok", false)):
				return _abort(str(finished.get("reason", "source_unavailable")))
			_active.field_proof = finished.proof
			_active.phase = "input"
		var progress: Dictionary = _progress(int(result.get("work", 0)), 0)
		progress.waiting = bool(result.get("waiting", false))
		return progress
	if _active.phase == "input":
		return _prepare_tile_input(cell_budget)
	if _active.phase == "temperature":
		var result: Dictionary = _temperature.resume_bulk(_active.temperature_handle, cell_budget)
		if not bool(result.get("ok", false)):
			return _abort(str(result.get("reason", "temperature_unavailable")))
		if result.get("status") == "chunk_done":
			if _active.chunk_has_phase:
				_active.phase = "phases"
			else:
				return _next_tile(int(result.get("visited", 0)))
		return _progress(0, int(result.get("visited", 0)))
	if _active.phase == "phases":
		var result: Dictionary = _phases.resume_bulk(_active.phase_handle, cell_budget)
		if not bool(result.get("ok", false)):
			return _abort(str(result.get("reason", "phase_unavailable")))
		if result.get("status") == "chunk_done":
			return _next_tile(int(result.get("visited", 0)))
		return _progress(0, int(result.get("visited", 0)))
	return _abort("invalid_phase")


func _next_tile(visited: int) -> Dictionary:
	_active.tile_index += 1
	_active.tile = {}
	_active.input = null
	_active.columns = {}
	_active.phase_columns = {}
	_active.chunk_has_phase = false
	_active.phase = "input"
	if _active.tile_index == _active.tile_ids.size():
		if _active.temperature_handle != null:
			var finished: Dictionary = _temperature.finish_bulk(_active.temperature_handle)
			if not bool(finished.get("ok", false)):
				return _abort(str(finished.get("reason", "temperature_unavailable")))
			_active.temperature_proof = finished.proof
		if _active.phase_handle != null:
			var done: Dictionary = _phases.finish_bulk(_active.phase_handle)
			if not bool(done.get("ok", false)):
				return _abort(str(done.get("reason", "phase_unavailable")))
			_active.phase_proof = done.proof
		_active.proof = Proof.new()
		_active.phase = "ready"
	return _progress(0, visited)


func _prepare_tile_input(budget: int) -> Dictionary:
	if budget == 0:
		return _progress(0, 0)
	if _active.parallel_input and _active.inputs.is_empty():
		var began: int = Time.get_ticks_usec()
		var tasks: Array[RefCounted] = []
		for tile_id: int in _active.tile_ids:
			var tile: Dictionary = _field.candidate_tile_copy(_active.field_proof, tile_id)
			if not bool(tile.get("ok", false)):
				return _abort(str(tile.get("reason", "source_tile_unavailable")))
			var input: SimFieldResponseInput = _new_input(tile, true)
			_active.inputs.append(input)
			tasks.append(input)
		compute_work.prepare_usec += Time.get_ticks_usec() - began
		_active.execution = SimBatchExecution.new()
		_active.execution.start(tasks, workers)
	if _active.parallel_input:
		# Input is the next required dependency. The coordinator can collect
		# directly; yielding to a millisecond timer cost more than these tiles.
		_active.execution.finish(true)
		if not _active.measured:
			_active.measured = true
			compute_work.batches += 1
			var worker_key: String = "workers_%d_batches" % _active.execution.worker_count
			compute_work[worker_key] = int(compute_work.get(worker_key, 0)) + 1
			compute_work.parallel_batches += int(_active.execution.parallel)
			compute_work.tiles += _active.inputs.size()
			compute_work.elapsed_usec += _active.execution.completed_usec - _active.execution.submitted_usec
			for item: SimFieldResponseInput in _active.inputs:
				compute_work.worker_usec += item.finished_usec - item.started_usec
		_active.input = _active.inputs[_active.tile_index]
	elif _active.input == null:
		var tile: Dictionary = _field.candidate_tile_copy(_active.field_proof, _active.tile_ids[_active.tile_index])
		if not bool(tile.get("ok", false)):
			return _abort(str(tile.get("reason", "source_tile_unavailable")))
		_active.input = _new_input(tile, false)
	var used: int = 0 if _active.parallel_input else _active.input.step(budget)
	if not _active.input.error.is_empty():
		return _abort(_active.input.error)
	_active.tile = _active.input.tile
	_active.columns = _active.input.thermal_columns
	_active.phase_columns = _active.input.phase_columns
	_active.cursor = _active.input.cursor
	var rect: Rect2i = _active.tile.rect
	if _active.cursor == SLOTS:
		@warning_ignore("integer_division")
		var key := Vector2i(rect.position.x / SIDE, rect.position.y / SIDE)
		_active.touched_chunks.append(key)
		var has_temperature: bool = not _active.columns.is_empty()
		_active.chunk_has_phase = not _active.phase_columns.is_empty()
		if has_temperature:
			if _active.temperature_handle == null:
				var opened: Dictionary = _temperature.begin_bulk(_active.at_ms, _active.tile_ids.size())
				if not bool(opened.get("ok", false)):
					return _abort(str(opened.get("reason", "temperature_unavailable")))
				_active.temperature_handle = opened.handle
			var offered: Dictionary = _temperature.offer_bulk_chunk(_active.temperature_handle, key, _active.columns)
			if not bool(offered.get("ok", false)):
				return _abort(str(offered.get("reason", "temperature_unavailable")))
			_active.temperature_chunks.append(key)
		if _active.chunk_has_phase:
			if _active.phase_handle == null:
				var phase_opened: Dictionary = _phases.begin_bulk(_active.at_ms, _active.tile_ids.size())
				if not bool(phase_opened.get("ok", false)):
					return _abort(str(phase_opened.get("reason", "phase_unavailable")))
				_active.phase_handle = phase_opened.handle
			var phase_offer: Dictionary = _phases.offer_bulk_chunk(_active.phase_handle, key, _active.phase_columns)
			if not bool(phase_offer.get("ok", false)):
				return _abort(str(phase_offer.get("reason", "phase_unavailable")))
			_active.phase_chunks.append(key)
		_active.columns = {}
		_active.phase_columns = {}
		if has_temperature:
			_active.phase = "temperature"
		elif _active.chunk_has_phase:
			_active.phase = "phases"
		else:
			return _next_tile(used)
	return _progress(0, used)


func _new_input(tile: Dictionary, private_cache: bool) -> SimFieldResponseInput:
	var input := SimFieldResponseInput.new()
	input.tile = tile
	input.compiler = _compiler.fork() if private_cache else _compiler
	input.temperature = _temperature
	input.phases = _phases
	input.initial_temperature = _initial_at
	input.initial_phase = _phase_initial
	input.at_ms = _active.at_ms
	input.horizon_ms = _active.horizon_ms
	input.tau_ms = int(_settings.tau_ms)
	input.grid_ms = int(_settings.tide_grid_ms)
	return input


func finish(handle: Variant) -> Dictionary:
	if not _current(handle):
		return _failure("invalid_handle")
	if _active.phase != "ready":
		return _failure("pending")
	var valid: Dictionary = _can_publish(_active.proof)
	if not bool(valid.get("ok", false)):
		return _abort(str(valid.get("reason", "candidate_stale")))
	var result: Dictionary = {"ok": true, "proof": _active.proof, "at_ms": _active.at_ms,
		"touched_chunks": _active.touched_chunks.duplicate(), "temperature_chunks": _active.temperature_chunks.duplicate(),
		"phase_chunks": _active.phase_chunks.duplicate()}
	result.make_read_only()
	return result


func can_commit(proof: Variant) -> Dictionary:
	return _can_publish(proof)


func commit(proof: Variant) -> Dictionary:
	var valid: Dictionary = _can_publish(proof)
	if not bool(valid.get("ok", false)):
		return valid
	# No user callback, signal, yield, allocation-dependent business preflight,
	# or other writer runs between these checked commits. Neither domain reads
	# the other's revision, so publication of the field cannot invalidate the
	# temperature proof. A failure here is an internal invariant violation, not
	# an allowed half-transaction recovery route.
	var started: int = Time.get_ticks_usec()
	var field: Dictionary = _field.commit_source_change(_active.field_proof)
	assert(bool(field.get("ok", false)), "preflighted field commit failed")
	var field_us: int = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var temperature: Dictionary = {"revision": -1}
	if _active.temperature_handle != null:
		temperature = _temperature.commit_bulk(_active.temperature_proof)
		assert(bool(temperature.get("ok", false)), "preflighted temperature commit failed")
	var temperature_us: int = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	if _active.phase_handle != null:
		var phases: Dictionary = _phases.commit_bulk(_active.phase_proof)
		assert(bool(phases.get("ok", false)), "preflighted phase commit failed")
	var at_ms: int = _active.at_ms
	var touched_chunks: Array[Vector2i] = _active.touched_chunks.duplicate()
	var temperature_chunks: Array[Vector2i] = _active.temperature_chunks.duplicate()
	var phase_chunks: Array[Vector2i] = _active.phase_chunks.duplicate()
	var phase_us: int = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	_active = null
	return {"ok": true, "at_ms": at_ms, "field_revision": int(field.revision),
		"temperature_revision": int(temperature.revision), "published_tiles": int(field.published_tiles),
		"touched_chunks": touched_chunks, "temperature_chunks": temperature_chunks, "phase_chunks": phase_chunks,
		"publish_us": {"field": field_us, "temperature": temperature_us, "phases": phase_us, "candidate_release": Time.get_ticks_usec() - started}}


func cancel(handle: Variant) -> Dictionary:
	if not _current(handle):
		return _failure("invalid_handle")
	if _active.execution != null:
		_active.execution.cancel()
		_active.execution.finish(true)
	_field.cancel_source_change(_active.field_handle)
	if _active.temperature_handle != null:
		_temperature.cancel_bulk(_active.temperature_handle)
	if _active.phase_handle != null:
		_phases.cancel_bulk(_active.phase_handle)
	_active = null
	return {"ok": true}


func _can_publish(proof: Variant) -> Dictionary:
	if _active == null or _active.phase != "ready" or not proof is Proof or not is_same(_active.proof, proof):
		return _failure("invalid_proof")
	var field: Dictionary = _field.can_commit_source_change(_active.field_proof)
	if not bool(field.get("ok", false)):
		return field
	if _active.temperature_handle != null and not _temperature.can_commit_bulk(_active.temperature_proof):
		return _failure("temperature_stale")
	if _active.phase_handle != null and not _phases.can_commit_bulk(_active.phase_proof):
		return _failure("phase_stale")
	return {"ok": true, "at_ms": _active.at_ms}


func _progress(field_work: int, cells: int) -> Dictionary:
	return {"ok": true, "pending": _active.phase != "ready", "phase": _active.phase,
		"field_work": field_work, "cells": cells, "completed_tiles": _active.tile_index,
		"tiles": _active.tile_ids.size(), "at_ms": _active.at_ms}


func _abort(reason: String) -> Dictionary:
	cancel(_active.handle)
	return _failure(reason)


func _current(handle: Variant) -> bool:
	return _active != null and handle is Handle and is_same(_active.handle, handle)


static func _empty_columns(channels: int = 1) -> Dictionary:
	return SimFieldResponseInput.empty_columns(channels)


static func _keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size():
		return false
	for key: String in expected:
		if not value.has(key):
			return false
	return true


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) >= float(minimum) and float(value) <= float(maximum) and floor(float(value)) == float(value)


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


class Handle:
	extends RefCounted


class Proof:
	extends RefCounted


class Change:
	extends RefCounted
	var handle: Handle
	var proof: Proof
	var field_handle: RefCounted
	var field_proof: RefCounted
	var temperature_handle: RefCounted
	var temperature_proof: RefCounted
	var phase_handle: RefCounted
	var phase_proof: RefCounted
	var at_ms: int = 0
	var horizon_ms: int = 0
	var phase: String = "field"
	var tile_ids: Array[int] = []
	var tile_index: int = 0
	var tile: Dictionary = {}
	var input: SimFieldResponseInput
	var inputs: Array[SimFieldResponseInput] = []
	var execution: SimBatchExecution
	var parallel_input: bool = false
	var measured: bool = false
	var columns: Dictionary = {}
	var phase_columns: Dictionary = {}
	var cursor: int = 0
	var chunk_has_phase: bool = false
	var touched_chunks: Array[Vector2i] = []
	var temperature_chunks: Array[Vector2i] = []
	var phase_chunks: Array[Vector2i] = []
