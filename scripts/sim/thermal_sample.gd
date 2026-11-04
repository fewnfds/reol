class_name SimThermalSample
extends RefCounted
## Validate the saved historical slice without reading current cells or flows.
## Coverage must come from SimThermalHistory.source_coverage. This is not a
## complete-world validator: original source authenticity and current Q remain
## the responsibility of SimThermalSchema and the independent world candidate.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const History = preload("res://scripts/sim/thermal_history.gd")
const MAX_INTEGER: int = 9007199254740991
const COUNTERS: Array[String] = ["input_energy", "loss_energy", "ambient_in", "continuous_input", "absorbed_energy"]
const SAMPLED_COUNTERS: Array[String] = ["last_sample_input", "last_sample_loss", "last_sample_ambient_in", "last_sample_continuous_input", "last_sample_absorbed"]


static func validate(heat: SimLocalHeat, data: Dictionary, coverage: Dictionary, baselines: Dictionary = {}) -> bool:
	# An optional baseline table is derived once by the full schema from climate
	# and source allocation time. It must never be copied from saved cell rows.
	if heat == null or not SimLocalHeat.valid_definitions(heat.definitions) or not History.valid_legacy_limits(data, coverage, int(heat.definitions.pulse_energy)):
		return false
	if not Shape.count(data.get("last_ms"), int(data.model_started_ms), MAX_INTEGER) or not data.get("last_sample_cells") is Dictionary or not data.get("receipts") is Dictionary or not data.get("device_switches") is Dictionary:
		return false
	if not Shape.count(data.get("last_sample_ms"), int(data.activation_ms), int(data.last_ms)) or int(data.last_sample_ms) != int(data.activation_ms) and posmod(int(data.last_sample_ms), int(heat.definitions.sample_ms)) != 0:
		return false
	if not data.get("last_sample_mode") is String or data.last_sample_mode not in ["absolute", "legacy_excess"]:
		return false
	for index: int in COUNTERS.size():
		if not Shape.count(data.get(COUNTERS[index]), 0, MAX_INTEGER) or not Shape.count(data.get(SAMPLED_COUNTERS[index]), 0, int(data[COUNTERS[index]])):
			return false
	if not _can_add(int(data.last_sample_input), int(data.last_sample_ambient_in)) or not _can_add(int(data.last_sample_input) + int(data.last_sample_ambient_in), int(data.last_sample_continuous_input)):
		return false
	var sample_at: int = int(data.last_sample_ms)
	if sample_at == int(data.activation_ms) and (not data.last_sample_cells.is_empty() or int(data.last_sample_input) != 0 or int(data.last_sample_loss) != 0 or int(data.last_sample_ambient_in) != 0 or int(data.last_sample_continuous_input) != 0 or int(data.last_sample_absorbed) != 0):
		return false
	var legacy: bool = data.last_sample_mode == "legacy_excess"
	var old_cells: Dictionary = {}
	if legacy:
		if data.legacy_limits.is_empty() or sample_at > int(data.model_started_ms) or int(data.last_sample_ambient_in) != 0 or int(data.last_sample_continuous_input) != 0 or int(data.last_sample_absorbed) != 0 or int(data.last_sample_input) > int(data.legacy_limits.input_energy):
			return false
		for key: String in data.legacy_limits.cells:
			old_cells[key] = true
	elif sample_at < int(data.model_started_ms):
		return false
	var allocations: Dictionary = coverage.allocations
	var old_maximum: int = int(heat.definitions.max_cell_energy) - 13000 * int(heat.definitions.capacity_per_tenth)
	var sample_sum: int = 0
	var sampled_baselines: int = 0
	for key: Variant in data.last_sample_cells:
		# Coverage keys are canonical in-bounds coordinates derived from patches.
		if not key is String or not allocations.has(key) or not Shape.count(data.last_sample_cells[key], 1 if legacy else 0, old_maximum if legacy else int(heat.definitions.max_cell_energy)):
			return false
		if legacy:
			if not old_cells.has(key):
				return false
		else:
			var allocated_at: int = int(allocations[key])
			if allocated_at > sample_at:
				return false
			var baseline: int
			if baselines.is_empty():
				var point := Vector2i(key.get_slice(",", 0).to_int(), key.get_slice(",", 1).to_int())
				baseline = heat._baseline(point, allocated_at)
			else:
				if not Shape.count(baselines.get(key), 0, int(heat.definitions.max_cell_energy)):
					return false
				baseline = int(baselines[key])
			if not Shape.count(baseline, 0, int(heat.definitions.max_cell_energy)) or not _can_add(sampled_baselines, baseline):
				return false
			sampled_baselines += baseline
		var energy: int = int(data.last_sample_cells[key])
		if not _can_add(sample_sum, energy):
			return false
		sample_sum += energy
	if not _can_add(sample_sum, int(data.last_sample_loss)) or not _can_add(sample_sum + int(data.last_sample_loss), int(data.last_sample_absorbed)) or sample_sum + int(data.last_sample_loss) + int(data.last_sample_absorbed) != int(data.last_sample_input) + int(data.last_sample_ambient_in) + int(data.last_sample_continuous_input):
		return false
	if not legacy:
		if sampled_baselines > int(data.last_sample_ambient_in):
			return false
		for key: String in allocations:
			# At the same ms a source can complete after a committed sample. Every
			# earlier allocation is mandatory, even when its sampled Q is zero.
			if int(allocations[key]) < sample_at and not data.last_sample_cells.has(key):
				return false
	var before_input: int = 0
	var through_input: int = 0
	for action: Variant in data.receipts:
		var receipt: Variant = data.receipts[action]
		if not action is String or not heat._valid_receipt(receipt, int(data.activation_ms)) or action != receipt.action:
			return false
		if int(receipt.at_ms) < sample_at:
			if not _can_add(before_input, int(receipt.amount)):
				return false
			before_input += int(receipt.amount)
		if int(receipt.at_ms) <= sample_at:
			if not _can_add(through_input, int(receipt.amount)):
				return false
			through_input += int(receipt.amount)
	if int(data.last_sample_input) < before_input or int(data.last_sample_input) > through_input or int(data.last_sample_input) % int(heat.definitions.pulse_energy) != 0:
		return false
	var source_before: bool = false
	var sink_before: bool = false
	for change: Dictionary in data.device_switches.values():
		if bool(change.enabled) and int(change.at_ms) < sample_at:
			var thermal: Variant = heat._device_definition(str(change.object)).get("thermal")
			if not thermal is Dictionary or thermal.get("mode") not in ["emit", "absorb"]:
				return false
			source_before = source_before or thermal.mode == "emit"
			sink_before = sink_before or thermal.mode == "absorb"
	return (source_before or int(data.last_sample_continuous_input) == 0) and (sink_before or int(data.last_sample_absorbed) == 0)


static func _can_add(total: int, amount: int) -> bool:
	return total >= 0 and amount >= 0 and amount <= MAX_INTEGER and total <= MAX_INTEGER - amount
