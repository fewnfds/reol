extends RefCounted
## Bounded rule checks: held seconds, independent minute percentages, no bonus
## accumulation, and the same future after a mid-second JSON roundtrip.
const Tide = preload("res://scripts/sim/environment_element_tide.gd")
const Phase = preload("res://scripts/sim/environment_phase_state.gd")
const Fields = preload("res://scripts/sim/world_environment_fields.gd")
const Columns = preload("res://scripts/sim/execution/field_response_input.gd")


static func run() -> bool:
	var previous := PackedInt32Array()
	var changes: int = 0
	var distinct_channels: bool = false
	for minute: int in 32:
		var percent: PackedInt32Array = Tide.percentages(17, Vector2i(256, 256), minute * 60000)
		if percent != Tide.percentages(17, Vector2i(256, 256), minute * 60000 + 59999):
			return false
		for channel: int in 5:
			if absi(percent[channel]) > 5:
				return false
			distinct_channels = distinct_channels or percent[channel] != percent[0]
		changes += 1 if percent != previous else 0
		previous = percent
	if changes <= 1 or not distinct_channels:
		return false
	var base := PackedFloat64Array([100, 100, 10, 10, 0])
	if Tide.apply(base, PackedInt32Array([5, -5, 5, -5, 5])) != PackedFloat64Array([105, 95, 11, 10, 0]):
		return false
	if Tide.apply(base, PackedInt32Array([-5, 5, -5, 5, -5])) != PackedFloat64Array([95, 105, 10, 11, 0]) or base != PackedFloat64Array([100, 100, 10, 10, 0]):
		return false
	# A settled base has no oscillator or per-second random input. Sampling an
	# unchanged equilibrium later must retain exactly the same five values.
	var settled := Phase.new()
	if not settled.configure(Vector2i(16, 16), 256, 0) or not _set_target(settled, 0, 1000.0, 1000.0):
		return false
	for at_ms: int in [0, 1000, 59000, 60000, 3600000]:
		if settled.actual_at(Vector2i.ZERO, at_ms).values != PackedFloat64Array([1000, 1000, 1000, 1000, 1000]): return false
	if not _steady_tide(settled): return false
	var phase := Phase.new()
	phase.anchor_quantum = 0.000000001
	if not phase.configure(Vector2i(16, 16), 256, 0) or not _set_target(phase, 0, 1000.0):
		return false
	if phase.actual_at(Vector2i.ZERO, 999).values != PackedFloat64Array([0, 0, 0, 0, 0]):
		return false
	var held: PackedFloat64Array = phase.actual_at(Vector2i.ZERO, 1000).values
	if held[0] <= 0.0 or not _set_target(phase, 1400, 0.0) or phase.actual_at(Vector2i.ZERO, 1499).values != held:
		return false
	if not _set_target(phase, 1900, 2000.0) or phase.actual_at(Vector2i.ZERO, 1999).values != held:
		return false
	var restored := Phase.new()
	restored.anchor_quantum = phase.anchor_quantum
	if not restored.restore(JSON.parse_string(JSON.stringify(phase.snapshot(), "", false, true))):
		return false
	for at_ms: int in [1999, 2000, 2500, 59999, 60000, 61000]:
		if restored.actual_at(Vector2i.ZERO, at_ms) != phase.actual_at(Vector2i.ZERO, at_ms):
			return false
	return phase.actual_at(Vector2i.ZERO, 2000).values[0] > held[0]


static func _steady_tide(phase: RefCounted) -> bool:
	# Exercise the real receiver composition with no world, source-field/GPU
	# backend or scheduler installed: a tide read must need none of them.
	var fields := Fields.new()
	fields._phases = phase
	fields._settings = {"seed": 17}
	fields._active = true
	var anchors: Dictionary = phase.snapshot()
	var previous := PackedFloat64Array()
	for at_ms: int in [59000, 59999, 60000, 60001, 60999, 61000]:
		fields.last_ms = at_ms
		var row: Dictionary = fields.elements_at(Vector2i.ZERO)
		var percent: PackedInt32Array = Tide.percentages(17, Vector2i.ZERO, at_ms)
		if not row.ok or row.base_values != PackedFloat64Array([1000, 1000, 1000, 1000, 1000]): return false
		if row.values != Tide.apply(row.base_values, percent) or row.tide_percent != percent: return false
		if at_ms == 59999 and row.values != previous or at_ms == 60000 and row.values == previous: return false
		if fields._element_samples.size() != 1: return false
		previous = row.values
	# A second receiver is lazy too; reading it creates no new source/response.
	if not fields.elements_at(Vector2i.ONE).ok or fields._element_samples.size() != 2: return false
	return phase.snapshot() == anchors


static func _set_target(phase: RefCounted, at_ms: int, target: float, initial: float = 0.0) -> bool:
	var columns: Dictionary = Columns.empty_columns(5)
	columns.mask[0] = 1
	columns.initial_mask[0] = 1 if phase.cell_boundary_ms(Vector2i.ZERO) < 0 else 0
	columns.until_ms[0] = Phase.MAX_TIME
	columns.tau_ms[0] = 30000
	for channel: int in 5:
		columns.target[channel] = target
		columns.initial[channel] = initial
	var opened: Dictionary = phase.begin_bulk(at_ms, 1)
	if not opened.ok or not phase.offer_bulk_chunk(opened.handle, Vector2i.ZERO, columns).ok:
		return false
	if not phase.resume_bulk(opened.handle, 256).ok:
		return false
	var finished: Dictionary = phase.finish_bulk(opened.handle)
	return finished.ok and phase.commit_bulk(finished.proof).ok
