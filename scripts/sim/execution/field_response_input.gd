class_name SimFieldResponseInput
extends RefCounted
## Private response columns from one immutable base-field candidate tile.
## The original temperature/phase owners still validate history, capacity and
## all anchors before the source transaction commits. Workers never adopt.
const SIDE: int = 16
const SLOTS: int = 256
var tile: Dictionary
var compiler: SimEnvironmentTargetCompiler
var temperature: SimEnvironmentTemperatureState
var phases: SimEnvironmentPhaseState
var initial_temperature: Callable
var initial_phase: Callable
var at_ms: int
var horizon_ms: int
var tau_ms: int
var cursor: int = 0
var thermal_columns: Dictionary = {}
var phase_columns: Dictionary = {}
var error: String = ""
var started_usec: int
var finished_usec: int
var thread_id: int


func run() -> void:
	started_usec = Time.get_ticks_usec()
	thread_id = OS.get_thread_caller_id()
	step(SLOTS)
	finished_usec = Time.get_ticks_usec()
	# Results are private columns; do not retain original response owners.
	temperature = null
	phases = null
	initial_temperature = Callable()
	initial_phase = Callable()
	compiler = null


func step(budget: int) -> int:
	var used: int = 0
	while cursor < SLOTS and used < budget and error.is_empty():
		_compile_cell(cursor)
		cursor += 1
		used += 1
	return used


func _compile_cell(index: int) -> void:
	var rect: Rect2i = tile.rect
	var cell: Vector2i = rect.position + Vector2i(index & 15, index >> 4)
	if not rect.has_point(cell):
		return
	var receiver: int = (cell.y - rect.position.y) * rect.size.x + cell.x - rect.position.x
	var changed: int = int(tile.change_mask[receiver]) if tile.has("change_mask") else 127
	var thermal_changed: bool = (changed & 96) != 0
	var phases_changed: bool = phases != null and (changed & 31) != 0
	if not thermal_changed and not phases_changed:
		return
	var offset: int = receiver * 7
	var channels: PackedInt32Array = tile.channels
	var target: Dictionary = {}
	if thermal_changed:
		target = compiler.compile(cell, at_ms, channels[offset + 5], channels[offset + 6], horizon_ms)
		if not bool(target.get("ok", false)):
			error = str(target.get("reason", "target_unavailable"))
			return
	if phases_changed:
		if phase_columns.is_empty():
			phase_columns = empty_columns(5)
		if phases.cell_boundary_ms(cell) < 0:
			var initial: Variant = initial_phase.call(cell, at_ms)
			if not initial is Dictionary or initial.get("ok") != true or not initial.get("values") is PackedFloat64Array or initial.values.size() != 5:
				error = "phase_initial_unavailable"
				return
			phase_columns.initial_mask[index] = 1
			for channel: int in 5:
				phase_columns.initial[index * 5 + channel] = initial.values[channel]
		phase_columns.mask[index] = 1
		phase_columns.until_ms[index] = SimEnvironmentPhaseState.MAX_TIME
		phase_columns.tau_ms[index] = tau_ms
		for channel: int in 5:
			phase_columns.target[index * 5 + channel] = channels[offset + channel]
	if not thermal_changed:
		return
	if thermal_columns.is_empty():
		thermal_columns = empty_columns()
	if temperature.cell_boundary_ms(cell) < 0:
		var initial: Variant = initial_temperature.call(cell, at_ms)
		if not initial is Dictionary or initial.get("ok") != true or not (initial.get("value_c") is float or initial.get("value_c") is int) or not is_finite(float(initial.value_c)):
			error = "initial_unavailable"
			return
		thermal_columns.initial_mask[index] = 1
		thermal_columns.initial[index] = float(initial.value_c)
	thermal_columns.mask[index] = 1
	thermal_columns.target[index] = float(target.target_c)
	thermal_columns.slope[index] = float(target.target_per_ms)
	thermal_columns.until_ms[index] = int(target.until_ms)
	thermal_columns.tau_ms[index] = int(target.tau_ms)


static func empty_columns(channels: int = 1) -> Dictionary:
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
