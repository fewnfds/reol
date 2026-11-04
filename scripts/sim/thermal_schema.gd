class_name SimThermalSchema
extends RefCounted
## Independent validation of the one fixed-reference field. No live assignment,
## clock settlement or reconstruction of unrecorded pre-conversion heat history.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const MAX_INTEGER: int = 9007199254740991


static func validate(heat: SimLocalHeat, data: Variant) -> bool:
	if heat == null or heat.world == null or not SimLocalHeat.valid_definitions(heat.definitions):
		return false
	if not Shape.keys(data, SimLocalHeat.empty_state(0).keys()) or not Shape.count(data.version, 2, 2) or not Shape.count(data.rules_version, int(heat.definitions.version), int(heat.definitions.version)):
		return false
	var now_value: Variant = heat.world.get("elapsed_ms")
	if not Shape.count(now_value, 0, MAX_INTEGER):
		return false
	var now: int = int(now_value)
	if not Shape.count(data.activation_ms, 0, now) or not Shape.count(data.model_started_ms, int(data.activation_ms), now) or not Shape.count(data.segment_started_ms, int(data.model_started_ms), now) or not Shape.count(data.last_ms, now, now):
		return false
	for field: String in ["cells", "receipts", "last_sample_cells", "legacy_limits"]:
		if not data[field] is Dictionary:
			return false
	if data.cells.size() > int(heat.definitions.max_cells) or not data.flows is Array or data.flows.size() > data.cells.size() * 6:
		return false
	if not Shape.count(data.input_energy, 0, int(heat.definitions.max_total_input)) or not Shape.count(data.ambient_in, 0, int(heat.definitions.max_exchange_energy)) or not Shape.count(data.loss_energy, 0, int(heat.definitions.max_exchange_energy)):
		return false
	if not _can_add(int(data.input_energy), int(data.ambient_in)):
		return false
	var total_input: int = int(data.input_energy) + int(data.ambient_in)
	var sum_q: int = 0
	var baseline_sum: int = 0
	for key: Variant in data.cells:
		var row: Variant = data.cells[key]
		if not key is String or not Shape.keys(row, ["cell", "energy", "allocated_ms", "baseline_energy"]) or not heat._cell_array(row.cell):
			return false
		var point := Vector2i(int(row.cell[0]), int(row.cell[1]))
		if key != heat._key(point) or not Shape.count(row.energy, 0, int(heat.definitions.max_cell_energy)) or not Shape.count(row.allocated_ms, int(data.model_started_ms), int(data.segment_started_ms)) or not Shape.count(row.baseline_energy, 0, int(heat.definitions.max_cell_energy)):
			return false
		if not _can_add(sum_q, int(row.energy)) or not _can_add(baseline_sum, int(row.baseline_energy)):
			return false
		sum_q += int(row.energy)
		baseline_sum += int(row.baseline_energy)
		if row.baseline_energy != heat._baseline(point, int(row.allocated_ms)):
			return false
	if not _can_add(sum_q, int(data.loss_energy)) or sum_q + int(data.loss_energy) != total_input or baseline_sum > int(data.ambient_in):
		return false

	var expected_cells: Dictionary = {}
	var before_model_cells: Dictionary = {}
	var through_model_cells: Dictionary = {}
	var receipt_sum: int = 0
	var before_model_input: int = 0
	var through_model_input: int = 0
	for action: Variant in data.receipts:
		var receipt: Variant = data.receipts[action]
		if not action is String or not heat._valid_receipt(receipt, int(data.activation_ms)) or action != receipt.action or int(receipt.at_ms) > now or not heat._source_matches(receipt):
			return false
		var amount: int = int(receipt.amount)
		if not _can_add(receipt_sum, amount):
			return false
		receipt_sum += amount
		var at_ms: int = int(receipt.at_ms)
		if at_ms < int(data.model_started_ms):
			if not _can_add(before_model_input, amount):
				return false
			before_model_input += amount
		if at_ms <= int(data.model_started_ms):
			if not _can_add(through_model_input, amount):
				return false
			through_model_input += amount
		var center := Vector2i(int(receipt.cell[0]), int(receipt.cell[1]))
		for point: Vector2i in heat._patch(center):
			var key: String = heat._key(point)
			if not data.cells.has(key):
				return false
			expected_cells[key] = mini(int(expected_cells.get(key, MAX_INTEGER)), at_ms)
			if at_ms < int(data.model_started_ms):
				before_model_cells[key] = true
			if at_ms <= int(data.model_started_ms):
				through_model_cells[key] = true
	if receipt_sum != int(data.input_energy) or expected_cells.size() != data.cells.size() or not heat._all_sources_present(data.receipts, int(data.activation_ms), now):
		return false
	for key: String in expected_cells:
		var expected_allocation: int = maxi(int(data.model_started_ms), int(expected_cells[key]))
		if int(data.cells[key].allocated_ms) != expected_allocation:
			return false
	if not _legacy_bounds(data, before_model_cells, through_model_cells, before_model_input, through_model_input, int(heat.definitions.pulse_energy)):
		return false
	if not _frozen_segment(heat, data, now, baseline_sum):
		return false
	return _sample(heat, data, now)


static func _frozen_segment(heat: SimLocalHeat, data: Dictionary, now: int, baseline_sum: int) -> bool:
	if not data.cells.is_empty() and (not heat._roofed.is_valid() or not heat._barrier.is_valid()):
		return false
	var segment: int = int(data.segment_started_ms)
	var dt: int = now - segment
	if not data.flows.is_empty() and dt > int(heat.definitions.step_ms):
		return false
	var anchors: Dictionary = data.cells.duplicate(true)
	var reverse_deltas: Dictionary = {}
	var seen_edges: Dictionary = {}
	var bath_in: int = 0
	var bath_out: int = 0
	for flow: Variant in data.flows:
		if not Shape.keys(flow, ["from", "to", "rate"]) or not flow.from is String or not flow.to is String or not Shape.count(flow.rate, 1, heat._maximum_rate()) or flow.from == flow.to:
			return false
		var origin: String = str(flow.from)
		var target: String = str(flow.to)
		if not origin.is_empty() and not data.cells.has(origin) or not target.is_empty() and not data.cells.has(target):
			return false
		var edge: String = origin + ">" + target
		if seen_edges.has(edge):
			return false
		seen_edges[edge] = true
		if not origin.is_empty() and not target.is_empty():
			var from: Array = data.cells[origin].cell
			var to: Array = data.cells[target].cell
			if absi(int(from[0]) - int(to[0])) + absi(int(from[1]) - int(to[1])) != 1:
				return false
		var rate: int = int(flow.rate)
		if not _can_multiply(rate, dt):
			return false
		var amount: int = rate * dt
		if origin.is_empty():
			if not _can_add(bath_in, amount):
				return false
			bath_in += amount
		elif not _accumulate_delta(reverse_deltas, origin, amount):
			return false
		if target.is_empty():
			if not _can_add(bath_out, amount):
				return false
			bath_out += amount
		elif not _accumulate_delta(reverse_deltas, target, -amount):
			return false
	if bath_in > int(data.ambient_in) or bath_out > int(data.loss_energy):
		return false
	var anchor_ambient: int = int(data.ambient_in) - bath_in
	var anchor_loss: int = int(data.loss_energy) - bath_out
	if anchor_ambient < baseline_sum or not _can_add(int(data.input_energy), anchor_ambient):
		return false
	var anchor_sum: int = 0
	for key: String in anchors:
		var energy: int = int(anchors[key].energy)
		var delta: int = int(reverse_deltas.get(key, 0))
		if delta < 0 and energy < -delta or delta > 0 and delta > int(heat.definitions.max_cell_energy) - energy:
			return false
		energy += delta
		if not Shape.count(energy, 0, int(heat.definitions.max_cell_energy)) or not _can_add(anchor_sum, energy):
			return false
		anchors[key].energy = energy
		anchor_sum += energy
	if not _can_add(anchor_sum, anchor_loss) or anchor_sum + anchor_loss != int(data.input_energy) + anchor_ambient:
		return false
	var expected: Array[Dictionary] = heat._build_flows(anchors, segment)
	if expected.size() != data.flows.size():
		return false
	for index: int in expected.size():
		if not Shape.same_record(data.flows[index], expected[index]):
			return false
	var boundary: int = heat._boundary_at(segment, anchors, expected)
	if not Shape.count(boundary, segment, MAX_INTEGER) or segment < MAX_INTEGER and boundary <= segment:
		return false
	return now <= boundary


static func _legacy_bounds(data: Dictionary, before_cells: Dictionary, through_cells: Dictionary, before_input: int, through_input: int, pulse: int) -> bool:
	var limits: Dictionary = data.legacy_limits
	if limits.is_empty():
		# A fresh model cannot claim sources from an earlier model epoch.
		return int(data.model_started_ms) == int(data.activation_ms) and before_input == 0
	if not Shape.keys(limits, ["at_ms", "input_energy", "cells"]) or not Shape.count(limits.at_ms, int(data.model_started_ms), int(data.model_started_ms)) or not Shape.count(limits.input_energy, before_input, through_input) or not limits.cells is Array:
		return false
	if int(limits.input_energy) % pulse != 0 or limits.cells.size() > through_cells.size():
		return false
	var old_cells: Dictionary = {}
	var previous: String = ""
	for key: Variant in limits.cells:
		if not key is String or key.is_empty() or (not previous.is_empty() and key <= previous) or not through_cells.has(key) or not data.cells.has(key) or int(data.cells[key].allocated_ms) != int(data.model_started_ms):
			return false
		old_cells[key] = true
		previous = key
	for key: String in before_cells:
		if not old_cells.has(key):
			return false
	# The converter already verified the old field. Later saves cannot identify
	# which same-ms sources preceded conversion; preserve only provable bounds.
	# These bounds cannot authorize extra cells or more old input than receipts.
	return (int(limits.input_energy) == 0) == old_cells.is_empty()


static func _sample(heat: SimLocalHeat, data: Dictionary, now: int) -> bool:
	if not Shape.count(data.last_sample_ms, int(data.activation_ms), now) or int(data.last_sample_ms) != int(data.activation_ms) and posmod(int(data.last_sample_ms), int(heat.definitions.sample_ms)) != 0:
		return false
	if not data.last_sample_mode is String or data.last_sample_mode not in ["absolute", "legacy_excess"]:
		return false
	if not Shape.count(data.last_sample_input, 0, int(data.input_energy)) or not Shape.count(data.last_sample_loss, 0, int(data.loss_energy)) or not Shape.count(data.last_sample_ambient_in, 0, int(data.ambient_in)) or not _can_add(int(data.last_sample_input), int(data.last_sample_ambient_in)):
		return false
	var sample_at: int = int(data.last_sample_ms)
	if sample_at == int(data.activation_ms) and (not data.last_sample_cells.is_empty() or int(data.last_sample_input) != 0 or int(data.last_sample_loss) != 0 or int(data.last_sample_ambient_in) != 0):
		return false
	var legacy: bool = data.last_sample_mode == "legacy_excess"
	var old_cells: Dictionary = {}
	if legacy:
		if data.legacy_limits.is_empty() or sample_at > int(data.model_started_ms) or int(data.last_sample_ambient_in) != 0 or int(data.last_sample_input) > int(data.legacy_limits.input_energy):
			return false
		for key: String in data.legacy_limits.cells:
			old_cells[key] = true
	elif sample_at < int(data.model_started_ms):
		return false
	var old_maximum: int = int(heat.definitions.max_cell_energy) - 13000 * int(heat.definitions.capacity_per_tenth)
	var sample_sum: int = 0
	var sampled_baselines: int = 0
	for key: Variant in data.last_sample_cells:
		if not key is String or not data.cells.has(key) or not Shape.count(data.last_sample_cells[key], 1 if legacy else 0, old_maximum if legacy else int(heat.definitions.max_cell_energy)):
			return false
		if legacy:
			if not old_cells.has(key):
				return false
		else:
			if int(data.cells[key].allocated_ms) > sample_at or not _can_add(sampled_baselines, int(data.cells[key].baseline_energy)):
				return false
			sampled_baselines += int(data.cells[key].baseline_energy)
		var energy: int = int(data.last_sample_cells[key])
		if not _can_add(sample_sum, energy):
			return false
		sample_sum += energy
	if not _can_add(sample_sum, int(data.last_sample_loss)) or sample_sum + int(data.last_sample_loss) != int(data.last_sample_input) + int(data.last_sample_ambient_in):
		return false
	if not legacy:
		if sampled_baselines > int(data.last_sample_ambient_in):
			return false
		for key: String in data.cells:
			# Same-ms source completion can occur after the already committed
			# sample. Earlier allocations must be represented even when Q is zero.
			if int(data.cells[key].allocated_ms) < sample_at and not data.last_sample_cells.has(key):
				return false
	var before_input: int = 0
	var through_input: int = 0
	for receipt: Dictionary in data.receipts.values():
		if int(receipt.at_ms) < sample_at:
			if not _can_add(before_input, int(receipt.amount)):
				return false
			before_input += int(receipt.amount)
		if int(receipt.at_ms) <= sample_at:
			if not _can_add(through_input, int(receipt.amount)):
				return false
			through_input += int(receipt.amount)
	return int(data.last_sample_input) >= before_input and int(data.last_sample_input) <= through_input and int(data.last_sample_input) % int(heat.definitions.pulse_energy) == 0


static func _can_add(total: int, amount: int) -> bool:
	return total >= 0 and amount >= 0 and amount <= MAX_INTEGER and total <= MAX_INTEGER - amount


static func _can_multiply(value: int, multiplier: int) -> bool:
	@warning_ignore("integer_division")
	var limit: int = MAX_INTEGER if multiplier == 0 else MAX_INTEGER / multiplier
	return value >= 0 and multiplier >= 0 and value <= limit


static func _accumulate_delta(deltas: Dictionary, key: String, amount: int) -> bool:
	var current: int = int(deltas.get(key, 0))
	if amount > 0 and current > MAX_INTEGER - amount or amount < 0 and current < -MAX_INTEGER - amount:
		return false
	deltas[key] = current + amount
	return true
