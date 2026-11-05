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
const SIDE: int = 16
const SLOTS: int = SIDE * SIDE

var _field: RefCounted
var _temperature: RefCounted
var _settings: Dictionary = {}
var _initial_at: Callable
var _phases: RefCounted
var _phase_initial: Callable
var _active: Change


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
	# Bound content is immutable for this coordinator. A different world/content
	# instance constructs another coordinator, never mutates an active context.
	_settings = settings.duplicate(true)
	_field = field
	_temperature = temperature
	_initial_at = initial_at
	_phases = phases
	_phase_initial = phase_initial
	return true


func begin(slot: int, operation: String, source: Dictionary, at_ms: int, horizon_ms: int) -> Dictionary:
	if _field == null:
		return _failure("not_configured")
	if _active != null:
		return _failure("busy")
	if at_ms < 0 or at_ms >= Temperature.MAX_TIME or horizon_ms <= at_ms or horizon_ms > Temperature.MAX_TIME:
		return _failure("time_out_of_range")
	var opened: Dictionary = _field.begin_source_change(slot, operation, source)
	if not bool(opened.get("ok", false)):
		return opened
	var tiles: Array[int] = opened.tile_ids
	var actual: Dictionary = _temperature.begin_bulk(at_ms, tiles.size())
	if not bool(actual.get("ok", false)):
		_field.cancel_source_change(opened.handle)
		return actual
	var candidate := Change.new()
	candidate.handle = Handle.new()
	candidate.field_handle = opened.handle
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
		return _progress(int(result.get("work", 0)), 0)
	if _active.phase == "input":
		return _prepare_tile_input(cell_budget)
	if _active.phase == "temperature":
		var result: Dictionary = _temperature.resume_bulk(_active.temperature_handle, cell_budget)
		if not bool(result.get("ok", false)):
			return _abort(str(result.get("reason", "temperature_unavailable")))
		if result.get("status") == "chunk_done":
			if _phases != null:
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
	_active.columns = {}
	_active.phase_columns = {}
	_active.phase = "input"
	if _active.tile_index == _active.tile_ids.size():
		var finished: Dictionary = _temperature.finish_bulk(_active.temperature_handle)
		if not bool(finished.get("ok", false)):
			return _abort(str(finished.get("reason", "temperature_unavailable")))
		_active.temperature_proof = finished.proof
		if _phases != null:
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
	if _active.tile.is_empty():
		var tile: Dictionary = _field.candidate_tile_copy(_active.field_proof, _active.tile_ids[_active.tile_index])
		if not bool(tile.get("ok", false)):
			return _abort(str(tile.get("reason", "source_tile_unavailable")))
		_active.tile = tile
		_active.columns = _empty_columns()
		if _phases != null:
			_active.phase_columns = _empty_columns(5)
		_active.cursor = 0
	var rect: Rect2i = _active.tile.rect
	var channels: PackedInt32Array = _active.tile.channels
	var used: int = 0
	while _active.cursor < SLOTS and used < budget:
		var index: int = _active.cursor
		_active.cursor += 1
		used += 1
		var cell: Vector2i = rect.position + Vector2i(index & 15, index >> 4)
		if not rect.has_point(cell):
			continue
		var offset: int = ((cell.y - rect.position.y) * rect.size.x + cell.x - rect.position.x) * 7
		var target: Dictionary = Segments.compile_segment(cell, _active.at_ms,
			_settings.climate, _settings.weather, int(_settings.weather_epoch_ms), int(_settings.seed),
			channels[offset + 5], channels[offset + 6], int(_settings.tau_ms), int(_settings.tide_grid_ms), _active.horizon_ms)
		if not bool(target.get("ok", false)):
			return _abort(str(target.get("reason", "target_unavailable")))
		if _phases != null:
			var phase_result: Dictionary = _prepare_phase_cell(index, cell, channels, offset, int(target.until_ms))
			if not bool(phase_result.get("ok", false)):
				return _abort(str(phase_result.get("reason", "phase_unavailable")))
		var actual: Dictionary = _temperature.actual_at(cell, _active.at_ms)
		if not bool(actual.get("ok", false)):
			if actual.get("reason") != "untracked":
				return _abort(str(actual.get("reason", "actual_unavailable")))
			# Only the real environment authority may supply the actual initial
			# condition of an untracked cell. Never infer it from the new source,
			# invent zero/20 C, or ask a view to manufacture an old temperature.
			var initial: Variant = _initial_at.call(cell, _active.at_ms)
			if not initial is Dictionary or not initial.get("ok") is bool or not initial.ok or not _number(initial.get("value_c")):
				return _abort("initial_unavailable")
			_active.columns.initial_mask[index] = 1
			_active.columns.initial[index] = float(initial.value_c)
		_active.columns.mask[index] = 1
		_active.columns.target[index] = float(target.target_c)
		_active.columns.slope[index] = float(target.target_per_ms)
		_active.columns.until_ms[index] = int(target.until_ms)
		_active.columns.tau_ms[index] = int(target.tau_ms)
	if _active.cursor == SLOTS:
		@warning_ignore("integer_division")
		var key := Vector2i(rect.position.x / SIDE, rect.position.y / SIDE)
		var offered: Dictionary = _temperature.offer_bulk_chunk(_active.temperature_handle, key, _active.columns)
		if not bool(offered.get("ok", false)):
			return _abort(str(offered.get("reason", "temperature_unavailable")))
		if _phases != null:
			var phase_offer: Dictionary = _phases.offer_bulk_chunk(_active.phase_handle, key, _active.phase_columns)
			if not bool(phase_offer.get("ok", false)):
				return _abort(str(phase_offer.get("reason", "phase_unavailable")))
		_active.columns = {}
		_active.phase = "temperature"
	return _progress(0, used)


func _prepare_phase_cell(index: int, cell: Vector2i, channels: PackedInt32Array, offset: int, until_ms: int) -> Dictionary:
	var actual: Dictionary = _phases.actual_at(cell, _active.at_ms)
	if not bool(actual.get("ok", false)):
		if actual.get("reason") != "untracked":
			return actual
		var initial: Variant = _phase_initial.call(cell, _active.at_ms)
		if not initial is Dictionary or initial.get("ok") != true or not initial.get("values") is PackedFloat64Array or initial.values.size() != 5:
			return _failure("phase_initial_unavailable")
		_active.phase_columns.initial_mask[index] = 1
		for channel: int in 5:
			_active.phase_columns.initial[index * 5 + channel] = initial.values[channel]
	var grid: int = int(_settings.tide_grid_ms)
	var at_ms: int = _active.at_ms
	var tide: Dictionary = Tide.sample(int(_settings.seed), cell, at_ms - posmod(at_ms, grid))
	if not bool(tide.get("ok", false)):
		return tide
	_active.phase_columns.mask[index] = 1
	_active.phase_columns.until_ms[index] = mini(until_ms, at_ms + mini(grid - posmod(at_ms, grid), Temperature.MAX_TIME - at_ms))
	_active.phase_columns.tau_ms[index] = int(_settings.tau_ms)
	for channel: int in 5:
		_active.phase_columns.target[index * 5 + channel] = Rules.effective_grade(channels[offset + channel], int(tide.multiplier))
	return {"ok": true}


func finish(handle: Variant) -> Dictionary:
	if not _current(handle):
		return _failure("invalid_handle")
	if _active.phase != "ready":
		return _failure("pending")
	var valid: Dictionary = _can_publish(_active.proof)
	if not bool(valid.get("ok", false)):
		return _abort(str(valid.get("reason", "candidate_stale")))
	var result: Dictionary = {"ok": true, "proof": _active.proof, "at_ms": _active.at_ms}
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
	var temperature: Dictionary = _temperature.commit_bulk(_active.temperature_proof)
	assert(bool(temperature.get("ok", false)), "preflighted temperature commit failed")
	var temperature_us: int = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	if _phases != null:
		var phases: Dictionary = _phases.commit_bulk(_active.phase_proof)
		assert(bool(phases.get("ok", false)), "preflighted phase commit failed")
	var at_ms: int = _active.at_ms
	var phase_us: int = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	_active = null
	return {"ok": true, "at_ms": at_ms, "field_revision": int(field.revision),
		"temperature_revision": int(temperature.revision), "published_tiles": int(field.published_tiles),
		"publish_us": {"field": field_us, "temperature": temperature_us, "phases": phase_us, "candidate_release": Time.get_ticks_usec() - started}}


func cancel(handle: Variant) -> Dictionary:
	if not _current(handle):
		return _failure("invalid_handle")
	_field.cancel_source_change(_active.field_handle)
	_temperature.cancel_bulk(_active.temperature_handle)
	if _phases != null:
		_phases.cancel_bulk(_active.phase_handle)
	_active = null
	return {"ok": true}


func _can_publish(proof: Variant) -> Dictionary:
	if _active == null or _active.phase != "ready" or not proof is Proof or not is_same(_active.proof, proof):
		return _failure("invalid_proof")
	var field: Dictionary = _field.can_commit_source_change(_active.field_proof)
	if not bool(field.get("ok", false)):
		return field
	if not _temperature.can_commit_bulk(_active.temperature_proof):
		return _failure("temperature_stale")
	if _phases != null and not _phases.can_commit_bulk(_active.phase_proof):
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
	var mask := PackedByteArray()
	var initial_mask := PackedByteArray()
	var initial := PackedFloat64Array()
	var target := PackedFloat64Array()
	var slope := PackedFloat64Array()
	var until := PackedInt64Array()
	var tau := PackedInt32Array()
	mask.resize(SLOTS)
	initial_mask.resize(SLOTS)
	initial.resize(SLOTS * channels)
	target.resize(SLOTS * channels)
	slope.resize(SLOTS * channels)
	until.resize(SLOTS)
	tau.resize(SLOTS)
	return {"mask": mask, "initial_mask": initial_mask, "initial": initial,
		"target": target, "slope": slope, "until_ms": until, "tau_ms": tau}


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
	var columns: Dictionary = {}
	var phase_columns: Dictionary = {}
	var cursor: int = 0
