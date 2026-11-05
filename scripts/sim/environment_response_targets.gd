class_name SimEnvironmentResponseTargets
extends RefCounted
## Compiles a bounded aligned group of real base-field cells into private
## temperature and five-element response candidates. The caller owns the
## ground cache, event context, overall session publication and shared clock.
## A read callback must return the checked ground cache's seven channels and
## field revision; no source positions or second field are stored here.

const Temperature = preload("res://scripts/sim/environment_temperature_state.gd")
const Phase = preload("res://scripts/sim/environment_phase_state.gd")
const SourceChange = preload("res://scripts/sim/environment_source_change.gd")
const Segments = preload("res://scripts/sim/environment_temperature_segments.gd")
const Climate = preload("res://scripts/sim/climate_rules.gd")
const Weather = preload("res://scripts/sim/weather.gd")
const Tide = preload("res://scripts/sim/environment_field_tide.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const SIDE: int = 16
const SLOTS: int = 256
const MAX_CHUNKS: int = 64

var _temperature: RefCounted
var _phases: RefCounted
var _settings: Dictionary = {}
var _read_channels: Callable
var _active: Batch


func configure(temperature: RefCounted, phases: RefCounted, settings: Dictionary, read_channels: Callable) -> bool:
	if _temperature != null or not is_instance_of(temperature, Temperature) or not is_instance_of(phases, Phase) or not read_channels.is_valid():
		return false
	if not _keys(settings, ["climate", "weather", "weather_epoch_ms", "seed", "tau_ms", "tide_grid_ms"]) or not Climate.valid_definitions(settings.climate) or not Weather.valid_definitions(settings.weather):
		return false
	if not _integer(settings.weather_epoch_ms, 0, Temperature.MAX_TIME) or not settings.seed is int or not _integer(settings.tau_ms, 1, Temperature.Response.MAX_TAU_MS) or not _integer(settings.tide_grid_ms, 1, Temperature.MAX_TIME):
		return false
	if not bool(phases.diagnostics().get("configured", false)):
		return false
	_temperature = temperature
	_phases = phases
	_settings = settings.duplicate(true)
	_read_channels = read_channels
	return true


func begin(area: Rect2i, at_ms: int, activation: bool = false, event_context: Variant = null) -> Dictionary:
	if _temperature == null:
		return _failure("not_configured")
	if _active != null:
		return _failure("busy")
	if at_ms < 0 or at_ms >= Temperature.MAX_TIME:
		return _failure("time_out_of_range")
	var size: Vector2i = _phases.diagnostics().get("size", Vector2i.ZERO)
	if area.position.x < 0 or area.position.y < 0 or area.size.x < SIDE or area.size.y < SIDE or area.position.x % SIDE != 0 or area.position.y % SIDE != 0 or area.size.x % SIDE != 0 or area.size.y % SIDE != 0 or area.end.x > size.x or area.end.y > size.y:
		return _failure("invalid_area")
	@warning_ignore("integer_division")
	var chunk_count: int = (area.size.x / SIDE) * (area.size.y / SIDE)
	if chunk_count > MAX_CHUNKS:
		return _failure("chunk_limit")
	var thermal: Dictionary = _temperature.begin_bulk(at_ms, chunk_count)
	if not bool(thermal.get("ok", false)):
		return thermal
	var elemental: Dictionary = _phases.begin_bulk(at_ms, chunk_count)
	if not bool(elemental.get("ok", false)):
		_temperature.cancel_bulk(thermal.handle)
		return elemental
	var batch := Batch.new()
	batch.handle = Handle.new()
	batch.temperature_handle = thermal.handle
	batch.phase_handle = elemental.handle
	batch.area = area
	batch.at_ms = at_ms
	batch.activation = activation
	batch.context = event_context
	batch.chunk_count = chunk_count
	batch.chunk_x = area.position.x
	batch.chunk_y = area.position.y
	_active = batch
	return {"ok": true, "handle": batch.handle, "chunks": chunk_count, "at_ms": at_ms}


func step(handle: Variant, cell_budget: int) -> Dictionary:
	if not _current(handle):
		return _failure("invalid_handle")
	if cell_budget < 0 or cell_budget > SLOTS:
		return _failure("invalid_budget")
	if _active.stage == "ready":
		return _progress(0)
	if _active.stage == "input":
		return _compile_input(cell_budget)
	if _active.stage == "temperature":
		var result: Dictionary = _temperature.resume_bulk(_active.temperature_handle, cell_budget)
		if not bool(result.get("ok", false)):
			return _abort(str(result.get("reason", "temperature_unavailable")))
		if result.get("status") == "chunk_done":
			_active.stage = "phases"
		return _progress(int(result.get("visited", 0)))
	if _active.stage == "phases":
		var result: Dictionary = _phases.resume_bulk(_active.phase_handle, cell_budget)
		if not bool(result.get("ok", false)):
			return _abort(str(result.get("reason", "phase_unavailable")))
		if result.get("status") == "chunk_done":
			return _next_chunk(int(result.get("visited", 0)))
		return _progress(int(result.get("visited", 0)))
	return _abort("invalid_stage")


func _compile_input(budget: int) -> Dictionary:
	if budget == 0:
		return _progress(0)
	if _active.temperature_columns.is_empty():
		_active.temperature_columns = SourceChange._empty_columns()
		_active.phase_columns = SourceChange._empty_columns(5)
		_active.cursor = 0
	var used: int = 0
	while _active.cursor < SLOTS and used < budget:
		var index: int = _active.cursor
		_active.cursor += 1
		used += 1
		var cell := Vector2i(_active.chunk_x + (index & 15), _active.chunk_y + (index >> 4))
		var read: Dictionary = _read_checked(cell)
		if not bool(read.get("ok", false)):
			return _abort(str(read.get("reason", "field_unavailable")))
		var channels: PackedInt32Array = read.channels
		var compiled: Dictionary = _compile_cell(index, cell, channels)
		if not bool(compiled.get("ok", false)):
			return _abort(str(compiled.get("reason", "target_unavailable")))
	if _active.cursor == SLOTS:
		var key := Vector2i(_active.chunk_x >> 4, _active.chunk_y >> 4)
		var offered: Dictionary = _temperature.offer_bulk_chunk(_active.temperature_handle, key, _active.temperature_columns)
		if not bool(offered.get("ok", false)):
			return _abort(str(offered.get("reason", "temperature_unavailable")))
		offered = _phases.offer_bulk_chunk(_active.phase_handle, key, _active.phase_columns)
		if not bool(offered.get("ok", false)):
			return _abort(str(offered.get("reason", "phase_unavailable")))
		_active.temperature_columns = {}
		_active.phase_columns = {}
		_active.stage = "temperature"
	return _progress(used)


func _compile_cell(index: int, cell: Vector2i, channels: PackedInt32Array) -> Dictionary:
	var at_ms: int = _active.at_ms
	var segment: Dictionary = Segments.compile_segment(cell, at_ms,
		_settings.climate, _settings.weather, int(_settings.weather_epoch_ms), int(_settings.seed),
		channels[5], channels[6], int(_settings.tau_ms), int(_settings.tide_grid_ms), Temperature.MAX_TIME)
	if not bool(segment.get("ok", false)):
		return segment
	if _active.activation:
		var background: Dictionary = Climate.background_at(_settings.climate, _settings.weather, int(_settings.weather_epoch_ms), cell, at_ms)
		if not background.get("temperature_tenths") is int:
			return _failure("background_unavailable")
		_active.temperature_columns.initial_mask[index] = 1
		_active.temperature_columns.initial[index] = float(background.temperature_tenths) / 10.0
		_active.phase_columns.initial_mask[index] = 1
	# Bulk preparation validates tracked/untracked, cell bounds and the old
	# known segment in both owners. Do not project the same six actual values a
	# second time during input compilation before those checked preparations.
	var grid: int = int(_settings.tide_grid_ms)
	var grid_start: int = at_ms - posmod(at_ms, grid)
	var tide: Dictionary = Tide.sample(int(_settings.seed), cell, grid_start)
	if not bool(tide.get("ok", false)):
		return tide
	var next_grid: int = at_ms + mini(grid - posmod(at_ms, grid), Temperature.MAX_TIME - at_ms)
	_active.temperature_columns.mask[index] = 1
	_active.temperature_columns.target[index] = float(segment.target_c)
	_active.temperature_columns.slope[index] = float(segment.target_per_ms)
	_active.temperature_columns.until_ms[index] = int(segment.until_ms)
	_active.temperature_columns.tau_ms[index] = int(segment.tau_ms)
	_active.phase_columns.mask[index] = 1
	_active.phase_columns.until_ms[index] = mini(int(segment.until_ms), next_grid)
	_active.phase_columns.tau_ms[index] = int(_settings.tau_ms)
	for channel: int in Phase.CHANNELS:
		var offset: int = index * Phase.CHANNELS + channel
		var target: int = Rules.effective_grade(channels[channel], int(tide.multiplier))
		_active.phase_columns.target[offset] = target
		if _active.activation:
			_active.phase_columns.initial[offset] = target
	return {"ok": true}


func _next_chunk(visited: int) -> Dictionary:
	_active.completed_chunks += 1
	if _active.completed_chunks == _active.chunk_count:
		var thermal: Dictionary = _temperature.finish_bulk(_active.temperature_handle)
		if not bool(thermal.get("ok", false)):
			return _abort(str(thermal.get("reason", "temperature_unavailable")))
		_active.temperature_proof = thermal.proof
		var phases: Dictionary = _phases.finish_bulk(_active.phase_handle)
		if not bool(phases.get("ok", false)):
			return _abort(str(phases.get("reason", "phase_unavailable")))
		_active.phase_proof = phases.proof
		_active.proof = Proof.new()
		_active.stage = "ready"
		return _progress(visited)
	_active.chunk_x += SIDE
	if _active.chunk_x == _active.area.end.x:
		_active.chunk_x = _active.area.position.x
		_active.chunk_y += SIDE
	_active.stage = "input"
	return _progress(visited)


func finish(handle: Variant) -> Dictionary:
	if not _current(handle):
		return _failure("invalid_handle")
	if _active.stage != "ready":
		return _failure("pending")
	var valid: Dictionary = can_commit(_active.proof)
	if not bool(valid.get("ok", false)):
		return _abort(str(valid.get("reason", "candidate_stale")))
	var result: Dictionary = {"ok": true, "proof": _active.proof, "at_ms": _active.at_ms}
	result.make_read_only()
	return result


func can_commit(proof: Variant) -> Dictionary:
	if _active == null or _active.stage != "ready" or not proof is Proof or not is_same(_active.proof, proof):
		return _failure("invalid_proof")
	# Revalidate checked owner epochs/context and the field revision after the
	# last compiled cell. A stale candidate is never silently rebased.
	var checked: Dictionary = _read_checked(_active.area.position)
	if not bool(checked.get("ok", false)):
		return checked
	if not _temperature.can_commit_bulk(_active.temperature_proof):
		return _failure("temperature_stale")
	if not _phases.can_commit_bulk(_active.phase_proof):
		return _failure("phase_stale")
	return {"ok": true, "at_ms": _active.at_ms}


func commit(proof: Variant) -> Dictionary:
	var valid: Dictionary = can_commit(proof)
	if not bool(valid.get("ok", false)):
		return valid
	# The checked publications contain no external callback or yield. Both
	# preflighted domain commits must be infallible internal operations here.
	var thermal: Dictionary = _temperature.commit_bulk(_active.temperature_proof)
	assert(bool(thermal.get("ok", false)), "preflighted thermal commit failed")
	var elemental: Dictionary = _phases.commit_bulk(_active.phase_proof)
	assert(bool(elemental.get("ok", false)), "preflighted phase commit failed")
	var at_ms: int = _active.at_ms
	var chunks: int = _active.completed_chunks
	_active = null
	return {"ok": true, "at_ms": at_ms, "chunks": chunks,
		"temperature_revision": int(thermal.revision), "phase_revision": int(elemental.revision)}


func cancel(handle: Variant) -> Dictionary:
	if not _current(handle):
		return _failure("invalid_handle")
	_temperature.cancel_bulk(_active.temperature_handle)
	_phases.cancel_bulk(_active.phase_handle)
	_active = null
	return {"ok": true}


func _read_checked(cell: Vector2i) -> Dictionary:
	var value: Variant = _read_channels.call(cell, _active.context)
	if not value is Dictionary or not value.get("ok") is bool or not value.ok:
		return _failure(str(value.get("reason", "field_unavailable")) if value is Dictionary else "field_unavailable")
	if not value.get("pending") is bool or value.pending:
		return _failure("field_pending")
	if not value.get("revision") is int or value.revision < 0:
		return _failure("field_revision")
	if _active.field_revision < 0:
		_active.field_revision = value.revision
	elif _active.field_revision != value.revision:
		return _failure("field_stale")
	if not value.get("channels") is PackedInt32Array or value.channels.size() != 7:
		return _failure("field_channels")
	for channel: int in value.channels:
		if channel < 0 or channel > Rules.MAX_GRADE_MILLI:
			return _failure("field_channel_value")
	return value


func _progress(used: int) -> Dictionary:
	return {"ok": true, "pending": _active.stage != "ready", "stage": _active.stage,
		"cells": used, "completed_chunks": _active.completed_chunks,
		"chunks": _active.chunk_count, "at_ms": _active.at_ms}


func _abort(reason: String) -> Dictionary:
	cancel(_active.handle)
	return _failure(reason)


func _current(handle: Variant) -> bool:
	return _active != null and handle is Handle and is_same(_active.handle, handle)


static func _keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size():
		return false
	for key: String in expected:
		if not value.has(key):
			return false
	return true


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	if not (value is int or value is float) or not is_finite(float(value)):
		return false
	return float(value) >= float(minimum) and float(value) <= float(maximum) and floor(float(value)) == float(value)


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


class Handle:
	extends RefCounted


class Proof:
	extends RefCounted


class Batch:
	extends RefCounted
	var handle: Handle
	var proof: Proof
	var temperature_handle: RefCounted
	var temperature_proof: RefCounted
	var phase_handle: RefCounted
	var phase_proof: RefCounted
	var area := Rect2i()
	var at_ms: int = 0
	var activation: bool = false
	var context: Variant
	var field_revision: int = -1
	var chunk_count: int = 0
	var completed_chunks: int = 0
	var chunk_x: int = 0
	var chunk_y: int = 0
	var stage: String = "input"
	var cursor: int = 0
	var temperature_columns: Dictionary = {}
	var phase_columns: Dictionary = {}
