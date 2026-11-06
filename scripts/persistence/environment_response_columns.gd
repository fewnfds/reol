class_name EnvironmentResponseColumns
extends RefCounted
## Compact, developer-session-only transfer of actual response anchors.
## The temperature/phase owners remain authoritative; the packed columns are
## detached snapshot data, never a second live world or a saved source index.
## Input comes from the session's plain-data binary archive, not engine objects.

const Temperature = preload("res://scripts/sim/environment_temperature_state.gd")
const Phases = preload("res://scripts/sim/environment_phase_state.gd")
const Response = preload("res://scripts/sim/environment_field_response.gd")
const Segments = preload("res://scripts/sim/environment_temperature_segments.gd")
const Tide = preload("res://scripts/sim/environment_field_tide.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const Compiler = preload("res://scripts/sim/environment_target_compiler.gd")
const VERSION: int = 1
const SIDE: int = 16
const CELLS: int = SIDE * SIDE


static func capture(temperature: RefCounted, phases: RefCounted, area: Rect2i) -> Dictionary:
	if not is_instance_of(temperature, Temperature) or not is_instance_of(phases, Phases):
		return _failure("owner_type")
	if not temperature._configured or not phases._configured or temperature._bulk != null or phases._bulk != null or temperature._issued_plan.get_ref() != null:
		return _failure("owner_busy")
	if temperature._size != phases._size or temperature._capacity != phases._capacity or temperature._activation_ms != phases._activation_ms or temperature._last_change_ms != phases._last_change_ms:
		return _failure("owner_mismatch")
	if not _valid_area(area, temperature._size) or temperature._tracked_count != area.size.x * area.size.y or phases._tracked_count != temperature._tracked_count:
		return _failure("coverage")
	var blocks: Array[Dictionary] = []
	for y: int in range(area.position.y, area.end.y, SIDE):
		for x: int in range(area.position.x, area.end.x, SIDE):
			var key := Vector2i(x >> 4, y >> 4)
			var thermal: Variant = temperature._chunks.get(key)
			var elemental: Variant = phases._chunks.get(key)
			if thermal == null or elemental == null:
				return _failure("coverage")
			blocks.append({"key": [key.x, key.y], "thermal": _copy_columns(thermal), "phases": _copy_columns(elemental)})
	return {"ok": true, "data": {"version": VERSION, "area": [area.position.x, area.position.y, area.size.x, area.size.y],
		"size": [temperature._size.x, temperature._size.y],
		"temperature": _metadata(temperature), "phases": _metadata(phases), "chunks": blocks}}


static func restore(temperature: RefCounted, phases: RefCounted, value: Variant) -> bool:
	# No live owner is changed until both complete detached candidates pass.
	if not is_instance_of(temperature, Temperature) or not is_instance_of(phases, Phases):
		return false
	if not _keys(value, ["version", "area", "size", "temperature", "phases", "chunks"]) or value.version != VERSION or not value.version is int or not _integer_array(value.area, 4) or not _integer_array(value.size, 2):
		return false
	for component: int in value.area:
		if component < 0 or component > Temperature.MAX_AXIS:
			return false
	for component: int in value.size:
		if component < 1 or component > Temperature.MAX_AXIS:
			return false
	var area := Rect2i(value.area[0], value.area[1], value.area[2], value.area[3])
	var size := Vector2i(value.size[0], value.size[1])
	if not _valid_area(area, size) or not _valid_metadata(value.temperature, size) or not _valid_metadata(value.phases, size):
		return false
	var thermal_meta: Dictionary = value.temperature
	var phase_meta: Dictionary = value.phases
	if thermal_meta.capacity != phase_meta.capacity or thermal_meta.activation_ms != phase_meta.activation_ms or thermal_meta.last_change_ms != phase_meta.last_change_ms:
		return false
	if thermal_meta.revision == 0 or phase_meta.revision == 0:
		return false # an aligned nonempty area has committed anchors
	if not value.chunks is Array:
		return false
	@warning_ignore("integer_division")
	var width: int = area.size.x / SIDE
	@warning_ignore("integer_division")
	var count: int = width * (area.size.y / SIDE)
	if value.chunks.size() != count or area.size.x * area.size.y > int(thermal_meta.capacity):
		return false
	var thermal_chunks: Dictionary = {}
	var phase_chunks: Dictionary = {}
	var thermal_boundaries: Dictionary = {}
	var phase_boundaries: Dictionary = {}
	var thermal_earliest: int = -1
	var phase_earliest: int = -1
	var newest: int = int(thermal_meta.activation_ms)
	for block_index: int in count:
		var block: Variant = value.chunks[block_index]
		if not _keys(block, ["key", "thermal", "phases"]) or not _integer_array(block.key, 2):
			return false
		@warning_ignore("integer_division")
		var expected := Vector2i((area.position.x >> 4) + block_index % width, (area.position.y >> 4) + block_index / width)
		if block.key != [expected.x, expected.y] or not _column_shape(block.thermal, 1) or not _column_shape(block.phases, Phases.CHANNELS):
			return false
		var t: Dictionary = block.thermal
		var p: Dictionary = block.phases
		for index: int in CELLS:
			if t.present[index] != 1 or p.present[index] != 1:
				return false
			var start: int = t.starts[index]
			var until: int = t.untils[index]
			var phase_until: int = p.untils[index]
			var tau: int = t.taus[index]
			if start < int(thermal_meta.activation_ms) or start > int(thermal_meta.last_change_ms) or until < start or until > Response.MAX_TIME or phase_until < start or phase_until > Response.MAX_TIME or tau < 1 or tau > Response.MAX_TAU_MS or p.starts[index] != start or p.taus[index] != tau:
				return false
			if not _thermal_segment(t.initials[index], t.targets[index], t.slopes[index], start, until):
				return false
			for channel: int in Phases.CHANNELS:
				var offset: int = index * Phases.CHANNELS + channel
				if not _phase_segment(p.initials[offset], p.targets[offset], p.slopes[offset], start, phase_until):
					return false
			newest = maxi(newest, start)
			thermal_boundaries[until] = int(thermal_boundaries.get(until, 0)) + 1
			phase_boundaries[phase_until] = int(phase_boundaries.get(phase_until, 0)) + 1
			if thermal_earliest < 0 or until < thermal_earliest:
				thermal_earliest = until
			if phase_earliest < 0 or phase_until < phase_earliest:
				phase_earliest = phase_until
		var thermal_chunk: RefCounted = Temperature.Chunk.new()
		var phase_chunk: RefCounted = Phases.Chunk.new()
		_assign_columns(thermal_chunk, t)
		_assign_columns(phase_chunk, p)
		thermal_chunks[expected] = thermal_chunk
		phase_chunks[expected] = phase_chunk
	if newest != int(thermal_meta.last_change_ms):
		return false
	# The duplicated packed-array handles are independent on mutation; Godot may
	# share their backing storage until a write. Owner publication is synchronous.
	temperature._size = size
	temperature._capacity = int(thermal_meta.capacity)
	temperature._activation_ms = int(thermal_meta.activation_ms)
	temperature._last_change_ms = int(thermal_meta.last_change_ms)
	temperature._revision = int(thermal_meta.revision)
	temperature._chunks = thermal_chunks
	temperature._tracked_count = area.size.x * area.size.y
	temperature._boundary_counts = thermal_boundaries
	temperature._earliest_boundary = thermal_earliest
	temperature._configured = true
	temperature._clear_prepared()
	temperature._bulk = null
	temperature._restore_identity = RefCounted.new()
	phases._size = size
	phases._capacity = int(phase_meta.capacity)
	phases._activation_ms = int(phase_meta.activation_ms)
	phases._last_change_ms = int(phase_meta.last_change_ms)
	phases._revision = int(phase_meta.revision)
	phases._chunks = phase_chunks
	phases._tracked_count = area.size.x * area.size.y
	phases._boundary_counts = phase_boundaries
	phases._earliest_boundary = phase_earliest
	phases._configured = true
	phases._bulk = null
	phases._identity = RefCounted.new()
	return true


static func validate_cell(thermal: RefCounted, elemental: RefCounted, index: int, cell: Vector2i, settings: Dictionary, at_ms: int, channels: PackedInt32Array, compiler: RefCounted = null) -> bool:
	# The caller traverses checked owner blocks under a frame budget. Require the
	# rebuilt original field to match the recorded target at its actual anchor,
	# rather than merely verifying that the packed numbers look well-formed. An
	# optional compiler must already be bound to these exact settings by the
	# private validator; the fallback retains the independent reference path.
	if thermal == null or elemental == null or index < 0 or index >= CELLS or channels.size() != 7 or thermal.present[index] != 1 or elemental.present[index] != 1:
		return false
	var start: int = thermal.starts[index]
	if start != elemental.starts[index] or thermal.taus[index] != elemental.taus[index] or thermal.taus[index] != int(settings.tau_ms) or start > at_ms or at_ms > thermal.untils[index] or at_ms > elemental.untils[index]:
		return false
	var grid: int = int(settings.tide_grid_ms)
	if grid <= 0:
		return false
	var compiled: Dictionary
	var multiplier: int
	if compiler == null:
		compiled = Segments.compile_segment(cell, start, settings.climate, settings.weather, int(settings.weather_epoch_ms), int(settings.seed), channels[5], channels[6], int(settings.tau_ms), grid, Temperature.MAX_TIME)
		if not bool(compiled.get("ok", false)):
			return false
		var sampled: Dictionary = Tide.sample(int(settings.seed), cell, start - posmod(start, grid))
		if not bool(sampled.get("ok", false)):
			return false
		multiplier = int(sampled.multiplier)
	else:
		if not is_instance_of(compiler, Compiler):
			return false
		compiled = compiler.compile(cell, start, channels[5], channels[6], Temperature.MAX_TIME)
		if not bool(compiled.get("ok", false)) or not compiled.get("multiplier") is int:
			return false
		multiplier = int(compiled.multiplier)
	if thermal.untils[index] != int(compiled.until_ms) or thermal.targets[index] != float(compiled.target_c) or thermal.slopes[index] != float(compiled.target_per_ms):
		return false
	var next_grid: int = start + mini(grid - posmod(start, grid), Temperature.MAX_TIME - start)
	if elemental.untils[index] != mini(int(compiled.until_ms), next_grid):
		return false
	var actual: float = Response._value_only_unchecked(start, at_ms, thermal.initials[index], thermal.targets[index], thermal.slopes[index], thermal.taus[index])
	if not Temperature._temperature(actual):
		return false
	for channel: int in Phases.CHANNELS:
		var offset: int = index * Phases.CHANNELS + channel
		if elemental.targets[offset] != float(Rules.effective_grade(channels[channel], multiplier)) or elemental.slopes[offset] != 0.0:
			return false
		actual = Response._value_only_unchecked(start, at_ms, elemental.initials[offset], elemental.targets[offset], elemental.slopes[offset], elemental.taus[index])
		if not Phases._valid_value(actual):
			return false
	return true


static func _valid_area(area: Rect2i, size: Vector2i) -> bool:
	return size.x >= 1 and size.x <= Temperature.MAX_AXIS and size.y >= 1 and size.y <= Temperature.MAX_AXIS and area.position.x >= 0 and area.position.y >= 0 and area.size.x >= SIDE and area.size.y >= SIDE and area.position.x % SIDE == 0 and area.position.y % SIDE == 0 and area.size.x % SIDE == 0 and area.size.y % SIDE == 0 and area.end.x <= size.x and area.end.y <= size.y


static func _metadata(owner: RefCounted) -> Dictionary:
	return {"capacity": owner._capacity, "activation_ms": owner._activation_ms,
		"last_change_ms": owner._last_change_ms, "revision": owner._revision}


static func _valid_metadata(data: Variant, size: Vector2i) -> bool:
	if not _keys(data, ["capacity", "activation_ms", "last_change_ms", "revision"]):
		return false
	if not data.capacity is int or not data.activation_ms is int or not data.last_change_ms is int or not data.revision is int:
		return false
	return Temperature._valid_configuration(size, data.capacity, data.activation_ms) and data.last_change_ms >= data.activation_ms and data.last_change_ms <= Response.MAX_TIME and data.revision >= 0 and data.revision <= Temperature.MAX_REVISION


static func _copy_columns(chunk: RefCounted) -> Dictionary:
	return {"present": chunk.present.duplicate(), "starts": chunk.starts.duplicate(), "untils": chunk.untils.duplicate(),
		"initials": chunk.initials.duplicate(), "targets": chunk.targets.duplicate(), "slopes": chunk.slopes.duplicate(), "taus": chunk.taus.duplicate()}


static func _assign_columns(chunk: RefCounted, columns: Dictionary) -> void:
	chunk.present = columns.present.duplicate()
	chunk.starts = columns.starts.duplicate()
	chunk.untils = columns.untils.duplicate()
	chunk.initials = columns.initials.duplicate()
	chunk.targets = columns.targets.duplicate()
	chunk.slopes = columns.slopes.duplicate()
	chunk.taus = columns.taus.duplicate()


static func _column_shape(value: Variant, channels: int) -> bool:
	if not _keys(value, ["present", "starts", "untils", "initials", "targets", "slopes", "taus"]):
		return false
	return value.present is PackedByteArray and value.present.size() == CELLS and value.starts is PackedInt64Array and value.starts.size() == CELLS and value.untils is PackedInt64Array and value.untils.size() == CELLS and value.taus is PackedInt32Array and value.taus.size() == CELLS and value.initials is PackedFloat64Array and value.initials.size() == CELLS * channels and value.targets is PackedFloat64Array and value.targets.size() == CELLS * channels and value.slopes is PackedFloat64Array and value.slopes.size() == CELLS * channels


static func _thermal_segment(initial: float, target: float, slope: float, start: int, until: int) -> bool:
	return Temperature._temperature(initial) and Temperature._temperature(target) and is_finite(slope) and absf(slope) <= Response.MAX_ABS_RATE_PER_MS and Temperature._temperature(target + slope * float(until - start))


static func _phase_segment(initial: float, target: float, slope: float, start: int, until: int) -> bool:
	return Phases._valid_value(initial) and Phases._valid_value(target) and is_finite(slope) and absf(slope) <= Response.MAX_ABS_RATE_PER_MS and Phases._valid_value(target + slope * float(until - start))


static func _keys(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func _integer_array(value: Variant, size: int) -> bool:
	if not value is Array or value.size() != size:
		return false
	for component: Variant in value:
		if not component is int:
			return false
	return true


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
