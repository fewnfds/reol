class_name SimThermalSchema
extends RefCounted
## Independent validation of the one fixed-reference field. No live assignment,
## clock settlement or reconstruction of unrecorded pre-conversion heat history.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const History = preload("res://scripts/sim/thermal_history.gd")
const Sample = preload("res://scripts/sim/thermal_sample.gd")
const MAX_INTEGER: int = 9007199254740991
const V2_KEYS: Array[String] = ["version", "rules_version", "activation_ms", "model_started_ms", "last_ms", "segment_started_ms",
	"cells", "flows", "input_energy", "ambient_in", "loss_energy", "receipts", "last_sample_ms", "last_sample_cells",
	"last_sample_input", "last_sample_loss", "last_sample_ambient_in", "last_sample_mode", "legacy_limits"]


static func validate(heat: SimLocalHeat, data: Variant) -> bool:
	return _validate(heat, data, {})


static func upgrade_v2(heat: SimLocalHeat, old: Variant) -> Dictionary:
	# Never repair the supplied historical value. Its exact old layout and
	# version must be recognized before the candidate receives new empty ledgers.
	if not Shape.keys(old, V2_KEYS) or not Shape.count(old.version, 2, 2) or not Shape.count(old.rules_version, 2, 2):
		return {}
	var candidate: Dictionary = old.duplicate(true)
	candidate.version = 3
	candidate.rules_version = 3
	candidate["continuous_input"] = 0
	candidate["absorbed_energy"] = 0
	candidate["device_input"] = {}
	candidate["device_absorbed"] = {}
	candidate["device_switches"] = {}
	candidate["last_sample_continuous_input"] = 0
	candidate["last_sample_absorbed"] = 0
	# Only the independently reconstructed frozen anchors determine this value.
	candidate["segment_until_ms"] = MAX_INTEGER
	var derived: Dictionary = {"derive": true}
	if not _validate(heat, candidate, derived) or not derived.has("boundary"):
		return {}
	candidate.segment_until_ms = int(derived.boundary)
	return candidate if validate(heat, candidate) else {}


static func _validate(heat: SimLocalHeat, data: Variant, derived: Dictionary) -> bool:
	if heat == null or heat.world == null or not SimLocalHeat.valid_definitions(heat.definitions):
		return false
	if not Shape.keys(data, SimLocalHeat.empty_state(0).keys()) or not Shape.count(data.version, 3, 3) or not Shape.count(data.rules_version, int(heat.definitions.version), int(heat.definitions.version)):
		return false
	var now_value: Variant = heat.world.get("elapsed_ms")
	if not Shape.count(now_value, 0, MAX_INTEGER):
		return false
	var now: int = int(now_value)
	if not Shape.count(data.activation_ms, 0, now) or not Shape.count(data.model_started_ms, int(data.activation_ms), now) or not Shape.count(data.segment_started_ms, int(data.model_started_ms), now) or not Shape.count(data.last_ms, now, now) or not Shape.count(data.segment_until_ms, int(data.segment_started_ms), MAX_INTEGER):
		return false
	for field: String in ["cells", "receipts", "last_sample_cells", "legacy_limits", "device_input", "device_absorbed", "device_switches"]:
		if not data[field] is Dictionary:
			return false
	var devices: Dictionary = heat._device_objects()
	if data.cells.size() > int(heat.definitions.max_cells) or not data.flows is Array or data.flows.size() > data.cells.size() * 6 + devices.size():
		return false
	if not Shape.count(data.input_energy, 0, int(heat.definitions.max_total_input)) or not Shape.count(data.ambient_in, 0, int(heat.definitions.max_exchange_energy)) or not Shape.count(data.loss_energy, 0, int(heat.definitions.max_exchange_energy)) or not Shape.count(data.continuous_input, 0, MAX_INTEGER) or not Shape.count(data.absorbed_energy, 0, MAX_INTEGER):
		return false
	if not _can_add(int(data.input_energy), int(data.ambient_in)) or not _can_add(int(data.input_energy) + int(data.ambient_in), int(data.continuous_input)):
		return false
	var total_input: int = int(data.input_energy) + int(data.ambient_in) + int(data.continuous_input)
	# Historical coverage is derived from sources, independently of the current
	# Q representation. It does not authenticate those sources or authorize
	# discarding cells: the complete candidate still proves both below.
	for action: Variant in data.receipts:
		var receipt: Variant = data.receipts[action]
		if not action is String or not heat._valid_receipt(receipt, int(data.activation_ms)) or action != receipt.action or int(receipt.at_ms) > int(data.segment_started_ms) or not heat._source_matches(receipt):
			return false
	if not _devices(heat, data, devices):
		return false
	var coverage: Dictionary = History.source_coverage(heat, data)
	if not bool(coverage.supported) or int(coverage.receipt_sum) != int(data.input_energy) or coverage.allocations.size() != data.cells.size() or not heat._all_sources_present(data.receipts, int(data.activation_ms), now):
		return false
	var allocations: Dictionary = coverage.allocations
	var sum_q: int = 0
	var baseline_sum: int = 0
	var baselines: Dictionary = {}
	for key: Variant in data.cells:
		var row: Variant = data.cells[key]
		if not key is String or not Shape.keys(row, ["cell", "energy", "allocated_ms", "baseline_energy"]) or not heat._cell_array(row.cell):
			return false
		var point := Vector2i(int(row.cell[0]), int(row.cell[1]))
		if key != heat._key(point) or not allocations.has(key) or not Shape.count(row.energy, 0, int(heat.definitions.max_cell_energy)) or not Shape.count(row.allocated_ms, int(allocations[key]), int(allocations[key])) or not Shape.count(row.baseline_energy, 0, int(heat.definitions.max_cell_energy)):
			return false
		# Compute once from original climate and source evidence, never use row
		# metadata as authority for historical sample validation.
		var baseline: int = heat._baseline(point, int(allocations[key]))
		if int(row.baseline_energy) != baseline:
			return false
		baselines[key] = baseline
		if not _can_add(sum_q, int(row.energy)) or not _can_add(baseline_sum, int(row.baseline_energy)):
			return false
		sum_q += int(row.energy)
		baseline_sum += int(row.baseline_energy)
	if not _can_add(sum_q, int(data.loss_energy)) or not _can_add(sum_q + int(data.loss_energy), int(data.absorbed_energy)) or sum_q + int(data.loss_energy) + int(data.absorbed_energy) != total_input or baseline_sum > int(data.ambient_in):
		return false

	if not History.valid_legacy_limits(data, coverage, int(heat.definitions.pulse_energy)):
		return false
	if not _frozen_segment(heat, data, now, baseline_sum, devices, derived):
		return false
	return Sample.validate(heat, data, coverage, baselines)


static func _devices(heat: SimLocalHeat, data: Dictionary, devices: Dictionary) -> bool:
	# These are references to the candidate's original artifacts, never a second
	# set of balances. Artifact schema also validates each definition and event.
	var definitions: Dictionary = {}
	for id: Variant in devices:
		var item: Variant = devices[id]
		if not SimInventory._nonempty(id) or not Shape.keys(item, ["definition", "region", "container", "stored_q", "enabled"]) or not item.enabled is bool:
			return false
		var definition: Dictionary = heat._device_definition(str(id))
		var thermal: Variant = definition.get("thermal")
		if not Shape.keys(thermal, ["mode", "rate_q_per_ms", "capacity_q", "opening_q"]) or thermal.mode not in ["emit", "absorb"] or not Shape.count(thermal.rate_q_per_ms, 1, MAX_INTEGER) or not Shape.count(thermal.capacity_q, 1, MAX_INTEGER) or not Shape.count(thermal.opening_q, 0, int(thermal.capacity_q)) or not Shape.count(item.stored_q, 0, int(thermal.capacity_q)):
			return false
		definitions[id] = thermal

	var input_sum: int = 0
	var absorbed_sum: int = 0
	for id: Variant in data.device_input:
		if not id is String or not devices.has(id) or not Shape.count(data.device_input[id], 0, MAX_INTEGER) or not _can_add(input_sum, int(data.device_input[id])):
			return false
		input_sum += int(data.device_input[id])
	for id: Variant in data.device_absorbed:
		if not id is String or not devices.has(id) or not Shape.count(data.device_absorbed[id], 0, MAX_INTEGER) or not _can_add(absorbed_sum, int(data.device_absorbed[id])):
			return false
		absorbed_sum += int(data.device_absorbed[id])
	if input_sum != int(data.continuous_input) or absorbed_sum != int(data.absorbed_energy):
		return false
	for id: String in devices:
		var emitted: int = int(data.device_input.get(id, 0))
		var absorbed: int = int(data.device_absorbed.get(id, 0))
		var thermal: Dictionary = definitions[id]
		var opening: int = int(thermal.opening_q)
		if thermal.mode == "emit":
			if absorbed != 0 or emitted > opening or int(devices[id].stored_q) != opening - emitted:
				return false
		else:
			if emitted != 0 or absorbed > int(thermal.capacity_q) - opening or int(devices[id].stored_q) != opening + absorbed:
				return false

	var switches: Dictionary = data.device_switches
	var authority: Variant = heat.world.get("artifacts")
	var events: Variant = [] if authority == null else authority.get("events")
	if not events is Array:
		return false
	var seen: Dictionary = {}
	var latest: Dictionary = {}
	var last_at: Dictionary = {}
	var had_elapsed_enable: Dictionary = {}
	for event: Variant in events:
		if not event is Dictionary or event.get("kind") not in ["enabled", "disabled"]:
			continue
		var action: Variant = event.get("action")
		if not SimInventory._nonempty(action) or seen.has(action) or not switches.has(action):
			return false
		var change: Variant = switches[action]
		if not Shape.keys(change, ["action", "actor", "object", "at_ms", "region", "container", "cell", "enabled"]) or action != change.action or not SimInventory._nonempty(change.actor) or not change.object is String or not devices.has(change.object) or not SimInventory._nonempty(change.region) or not SimInventory._nonempty(change.container) or not heat._cell_array(change.cell) or not change.enabled is bool or not Shape.count(change.at_ms, int(data.model_started_ms), int(data.segment_started_ms)):
			return false
		var enabled: bool = event.kind == "enabled"
		if change.enabled != enabled or event.get("verb") != ("enable" if enabled else "disable") or event.get("actor") != change.actor or event.get("object") != change.object or not Shape.count(event.get("at_ms"), 0, MAX_INTEGER) or int(event.at_ms) != int(change.at_ms) or event.get("effect_region") != change.region or event.get("device_container") != change.container or not _same_cell(heat, event.get("cell"), change.cell):
			return false
		var id: String = str(change.object)
		var previous: Dictionary = latest.get(id, {})
		if (bool(previous.get("enabled", false)) == enabled) or (last_at.has(id) and int(change.at_ms) < int(last_at[id])):
			return false
		if not _place_at(heat, str(change.region), str(change.container), change.cell):
			return false
		if not enabled and (previous.get("region") != change.region or previous.get("container") != change.container or not _same_cell(heat, previous.get("cell"), change.cell)):
			return false
		if enabled:
			if int(change.at_ms) < int(data.last_ms):
				had_elapsed_enable[id] = true
		seen[action] = true
		latest[id] = change
		last_at[id] = int(change.at_ms)
	if seen.size() != switches.size():
		return false
	for id: String in devices:
		var item: Dictionary = devices[id]
		var change: Dictionary = latest.get(id, {})
		if bool(item.enabled) != bool(change.get("enabled", false)):
			return false
		if bool(item.enabled) and (change.get("region") != item.region or change.get("container") != item.container or not _place_at(heat, str(item.region), str(item.container), change.cell)):
			return false
		if (int(data.device_input.get(id, 0)) > 0 or int(data.device_absorbed.get(id, 0)) > 0) and not had_elapsed_enable.has(id):
			return false
	return true


static func _place_at(heat: SimLocalHeat, region: String, container: String, cell: Array) -> bool:
	var regions: Variant = heat.world.get("regions")
	if not regions is Dictionary or not regions.has(region):
		return false
	var places: Variant = regions[region].get("places")
	return places is Dictionary and places.has(container) and places[container] is Dictionary and _same_cell(heat, places[container].get("cell"), cell)


static func _same_cell(heat: SimLocalHeat, left: Variant, right: Variant) -> bool:
	# JSON roundtrips represent exact integer coordinates as floats. Compare
	# values only after validating each coordinate, never raw Array element types.
	return heat._cell_array(left) and heat._cell_array(right) and int(left[0]) == int(right[0]) and int(left[1]) == int(right[1])


static func _frozen_segment(heat: SimLocalHeat, data: Dictionary, now: int, baseline_sum: int, devices: Dictionary, derived: Dictionary) -> bool:
	if not data.cells.is_empty() and (not heat._roofed.is_valid() or not heat._barrier.is_valid()):
		return false
	var segment: int = int(data.segment_started_ms)
	var dt: int = now - segment
	if not data.flows.is_empty() and dt > int(heat.definitions.step_ms):
		return false
	var anchors: Dictionary = data.cells.duplicate(true)
	var object_anchors: Dictionary = devices.duplicate(true)
	var reverse_deltas: Dictionary = {}
	var seen_edges: Dictionary = {}
	var bath_in: int = 0
	var bath_out: int = 0
	var device_in: int = 0
	var device_out: int = 0
	for flow: Variant in data.flows:
		if not Shape.keys(flow, ["from", "to", "rate"]) or not flow.from is String or not flow.to is String or not Shape.count(flow.rate, 1, MAX_INTEGER) or flow.from == flow.to:
			return false
		var origin: String = str(flow.from)
		var target: String = str(flow.to)
		var source_device: String = heat._device_id(origin)
		var target_device: String = heat._device_id(target)
		if not source_device.is_empty() and not target_device.is_empty():
			return false
		if not origin.is_empty() and source_device.is_empty() and not data.cells.has(origin) or not target.is_empty() and target_device.is_empty() and not data.cells.has(target):
			return false
		if not source_device.is_empty() or not target_device.is_empty():
			var id: String = source_device if not source_device.is_empty() else target_device
			if not devices.has(id) or not bool(devices[id].enabled) or origin.is_empty() or target.is_empty():
				return false
			var thermal: Dictionary = heat._device_definition(id).get("thermal", {})
			if thermal.is_empty() or int(flow.rate) > int(thermal.rate_q_per_ms) or thermal.mode != ("emit" if not source_device.is_empty() else "absorb"):
				return false
		else:
			if int(flow.rate) > heat._maximum_rate():
				return false
		var destinations: Dictionary = seen_edges.get(origin, {})
		if destinations.has(target):
			return false
		destinations[target] = true
		seen_edges[origin] = destinations
		if not origin.is_empty() and not target.is_empty() and source_device.is_empty() and target_device.is_empty():
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
		elif not source_device.is_empty():
			var emitting_item: Dictionary = object_anchors[source_device]
			var emit_rule: Dictionary = heat._device_definition(source_device).thermal
			if amount > int(data.device_input.get(source_device, 0)) or amount > int(emit_rule.capacity_q) - int(emitting_item.stored_q) or not _can_add(device_in, amount):
				return false
			emitting_item.stored_q = int(emitting_item.stored_q) + amount
			device_in += amount
		elif not _accumulate_delta(reverse_deltas, origin, amount):
			return false
		if target.is_empty():
			if not _can_add(bath_out, amount):
				return false
			bath_out += amount
		elif not target_device.is_empty():
			var absorbing_item: Dictionary = object_anchors[target_device]
			if amount > int(data.device_absorbed.get(target_device, 0)) or amount > int(absorbing_item.stored_q) or not _can_add(device_out, amount):
				return false
			absorbing_item.stored_q = int(absorbing_item.stored_q) - amount
			device_out += amount
		elif not _accumulate_delta(reverse_deltas, target, -amount):
			return false
	if bath_in > int(data.ambient_in) or bath_out > int(data.loss_energy) or device_in > int(data.continuous_input) or device_out > int(data.absorbed_energy):
		return false
	var anchor_ambient: int = int(data.ambient_in) - bath_in
	var anchor_loss: int = int(data.loss_energy) - bath_out
	var anchor_continuous: int = int(data.continuous_input) - device_in
	var anchor_absorbed: int = int(data.absorbed_energy) - device_out
	if anchor_ambient < baseline_sum or not _can_add(int(data.input_energy), anchor_ambient) or not _can_add(int(data.input_energy) + anchor_ambient, anchor_continuous):
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
	if not _can_add(anchor_sum, anchor_loss) or not _can_add(anchor_sum + anchor_loss, anchor_absorbed) or anchor_sum + anchor_loss + anchor_absorbed != int(data.input_energy) + anchor_ambient + anchor_continuous:
		return false
	var plan: Dictionary = heat._flow_plan(anchors, segment, object_anchors)
	if not bool(plan.get("ok", false)) or not plan.get("flows") is Array:
		return false
	var expected: Array = plan.flows
	if expected.size() != data.flows.size():
		return false
	for index: int in expected.size():
		if not Shape.same_record(data.flows[index], expected[index]):
			return false
	var boundary: int = heat._boundary_at(segment, anchors, expected, object_anchors)
	if not Shape.count(boundary, segment, MAX_INTEGER) or segment < MAX_INTEGER and boundary <= segment:
		return false
	if bool(derived.get("derive", false)):
		derived["boundary"] = boundary
	elif int(data.segment_until_ms) != boundary:
		return false
	return now <= boundary


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
