class_name SimThermalSchema
extends RefCounted
## Independent validation of the one fixed-reference field. No live assignment,
## clock settlement or reconstruction of unrecorded pre-conversion heat history.

const Shape = preload("res://scripts/sim/avian_schema.gd")
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
	if not _can_add(sum_q, int(data.loss_energy)) or not _can_add(sum_q + int(data.loss_energy), int(data.absorbed_energy)) or sum_q + int(data.loss_energy) + int(data.absorbed_energy) != total_input or baseline_sum > int(data.ambient_in):
		return false

	var expected_cells: Dictionary = {}
	var before_model_cells: Dictionary = {}
	var through_model_cells: Dictionary = {}
	var receipt_sum: int = 0
	var before_model_input: int = 0
	var through_model_input: int = 0
	for action: Variant in data.receipts:
		var receipt: Variant = data.receipts[action]
		if not action is String or not heat._valid_receipt(receipt, int(data.activation_ms)) or action != receipt.action or int(receipt.at_ms) > int(data.segment_started_ms) or not heat._source_matches(receipt):
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
	if not _devices(heat, data, devices, expected_cells) or receipt_sum != int(data.input_energy) or expected_cells.size() != data.cells.size() or not heat._all_sources_present(data.receipts, int(data.activation_ms), now):
		return false
	for key: String in expected_cells:
		var expected_allocation: int = maxi(int(data.model_started_ms), int(expected_cells[key]))
		if int(data.cells[key].allocated_ms) != expected_allocation:
			return false
	if not _legacy_bounds(data, before_model_cells, through_model_cells, before_model_input, through_model_input, int(heat.definitions.pulse_energy)):
		return false
	if not _frozen_segment(heat, data, now, baseline_sum, devices, derived):
		return false
	return _sample(heat, data, now)


static func _devices(heat: SimLocalHeat, data: Dictionary, devices: Dictionary, expected_cells: Dictionary) -> bool:
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
			var center := Vector2i(int(change.cell[0]), int(change.cell[1]))
			for point: Vector2i in heat._patch(center):
				var key: String = heat._key(point)
				if not data.cells.has(key):
					return false
				expected_cells[key] = mini(int(expected_cells.get(key, MAX_INTEGER)), int(change.at_ms))
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
	if not Shape.count(data.last_sample_input, 0, int(data.input_energy)) or not Shape.count(data.last_sample_loss, 0, int(data.loss_energy)) or not Shape.count(data.last_sample_ambient_in, 0, int(data.ambient_in)) or not Shape.count(data.last_sample_continuous_input, 0, int(data.continuous_input)) or not Shape.count(data.last_sample_absorbed, 0, int(data.absorbed_energy)) or not _can_add(int(data.last_sample_input), int(data.last_sample_ambient_in)) or not _can_add(int(data.last_sample_input) + int(data.last_sample_ambient_in), int(data.last_sample_continuous_input)):
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
	if not _can_add(sample_sum, int(data.last_sample_loss)) or not _can_add(sample_sum + int(data.last_sample_loss), int(data.last_sample_absorbed)) or sample_sum + int(data.last_sample_loss) + int(data.last_sample_absorbed) != int(data.last_sample_input) + int(data.last_sample_ambient_in) + int(data.last_sample_continuous_input):
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
	if int(data.last_sample_input) < before_input or int(data.last_sample_input) > through_input or int(data.last_sample_input) % int(heat.definitions.pulse_energy) != 0:
		return false
	var source_before: bool = false
	var sink_before: bool = false
	for change: Dictionary in data.device_switches.values():
		if bool(change.enabled) and int(change.at_ms) < sample_at:
			var thermal: Dictionary = heat._device_definition(str(change.object)).thermal
			source_before = source_before or thermal.mode == "emit"
			sink_before = sink_before or thermal.mode == "absorb"
	return (source_before or int(data.last_sample_continuous_input) == 0) and (sink_before or int(data.last_sample_absorbed) == 0)


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
