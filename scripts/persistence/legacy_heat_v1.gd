class_name LegacyHeatV1
extends RefCounted
## Read-only validation and projection of a version-1 heat archive.
## This is a migration input, never a running field or a second heat owner.
## The caller supplies the original candidate's geometry and source records.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]
const MAX_INTEGER: int = 9007199254740991
const STATE_KEYS: Array[String] = ["version", "rules_version", "activation_ms", "last_ms", "segment_started_ms", "cells", "flows", "input_energy", "loss_energy", "receipts", "last_sample_ms", "last_sample_cells", "last_sample_input", "last_sample_loss"]

var _definitions: Dictionary = {}
var _state: Dictionary = {}
var _owner: WeakRef
var _roofed: Callable
var _barrier: Callable
var _receipt_validator: Callable
var _expected_actions: Callable
var _world: RefCounted:
	get:
		return null if _owner == null else _owner.get_ref()

# The original domain validators may inspect these values. Return copies for
# dictionaries so none of them can mutate the accepted archive through a view.
var definitions: Dictionary:
	get:
		return _definitions.duplicate(true)
var cells: Dictionary:
	get:
		return _state.get("cells", {}).duplicate(true)
var last_sample_cells: Dictionary:
	get:
		return _state.get("last_sample_cells", {}).duplicate(true)
var activation_ms: int:
	get:
		return int(_state.get("activation_ms", 0))
var last_sample_ms: int:
	get:
		return int(_state.get("last_sample_ms", 0))
var input_energy: int:
	get:
		return int(_state.get("input_energy", 0))


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "step_ms", "sample_ms", "world_size", "capacity_per_tenth", "pulse_energy", "coefficient_scale", "conductance", "bath_loss", "source_radius", "max_cells", "max_cell_energy", "max_total_input"]) or data.version != 1:
		return false
	if not Shape.count(data.step_ms, 1, 60000) or not Shape.count(data.sample_ms, int(data.step_ms), 3600000) or int(data.sample_ms) % int(data.step_ms) != 0 or not Shape.count(data.world_size, 1, 100000):
		return false
	if not Shape.count(data.capacity_per_tenth, 1, 1000000000) or not Shape.count(data.coefficient_scale, 1, 1000000) or not Shape.count(data.source_radius, 0, 8) or not Shape.count(data.max_cells, 1, 8192):
		return false
	if not Shape.count(data.max_cell_energy, int(data.capacity_per_tenth), 1000000000000) or not Shape.count(data.max_total_input, int(data.max_cell_energy), MAX_INTEGER):
		return false
	if not Shape.count(data.pulse_energy, 1, int(data.max_cell_energy)):
		return false
	if not Shape.keys(data.conductance, ["open", "open_door", "wall", "closed_door"]) or not Shape.keys(data.bath_loss, ["roofed", "unroofed"]):
		return false
	var greatest_edge: int = 0
	var greatest_bath: int = 0
	for value: Variant in data.conductance.values():
		if not Shape.count(value, 0, int(data.coefficient_scale)):
			return false
		greatest_edge = maxi(greatest_edge, int(value))
	for value: Variant in data.bath_loss.values():
		if not Shape.count(value, 0, int(data.coefficient_scale)):
			return false
		greatest_bath = maxi(greatest_bath, int(value))
	# A full frozen step cannot move more energy out of a cell than it owns.
	return 4 * greatest_edge + greatest_bath <= int(data.coefficient_scale)


func configure(authority: RefCounted, rules: Dictionary) -> bool:
	if authority == null or not valid_definitions(rules) or not Shape.count(authority.get("elapsed_ms"), 0, SimInventory.MAX_COUNT):
		return false
	_owner = weakref(authority)
	_definitions = rules.duplicate(true)
	_state.clear()
	_roofed = Callable()
	_barrier = Callable()
	_receipt_validator = Callable()
	_expected_actions = Callable()
	return true


func bind_world(authority: RefCounted) -> void:
	# The regional candidate has completed all validation and is being adopted
	# by its independent restore shell. No heat state is recomputed or advanced.
	_owner = weakref(authority)


func set_geometry(roofed: Callable, barrier: Callable) -> void:
	# The stored slope is valid only under the exact candidate geometry. Any
	# context change invalidates a previous acceptance instead of refreezing it.
	_roofed = roofed
	_barrier = barrier
	_state.clear()


func set_source_validator(receipt_validator: Callable, expected_actions: Callable) -> void:
	# Optional trusted adapters must refer to the same independently validated
	# candidate artifacts. With no adapters the original artifact owner is used.
	_receipt_validator = receipt_validator
	_expected_actions = expected_actions
	_state.clear()


func restore(data: Variant) -> bool:
	# The original geometry must be available, even when the saved patch is
	# empty. Falling back to an uncovered open layout would not prove that this
	# archive was validated against its independently restored construction.
	if _world == null or not _roofed.is_valid() or not _barrier.is_valid() or not _valid_state(data):
		return false
	_assign(data)
	return true


func to_dict() -> Dictionary:
	return _state.duplicate(true)


func current_tenths(cell: Vector2i) -> int:
	# Read the accepted save instant only. This is not an advancing query.
	if _state.is_empty() or not _valid_cell(cell):
		return 0
	return _tenths(int(_state.cells.get(_key(cell), {}).get("energy", 0)))


func sample_tenths(cell: Vector2i, at_ms: int) -> int:
	if _state.is_empty() or at_ms != int(_state.last_sample_ms) or not _valid_cell(cell):
		return 0
	return _tenths(int(_state.last_sample_cells.get(_key(cell), 0)))


func project_tenths(cell: Vector2i, at_ms: int) -> Dictionary:
	if _state.is_empty():
		return {"supported": false, "reason": "uninitialized"}
	if not _valid_cell(cell):
		return {"supported": false, "reason": "invalid_cell"}
	if not Shape.count(at_ms, 0, SimInventory.MAX_COUNT):
		return {"supported": false, "reason": "invalid_time"}
	var key: String = _key(cell)
	var energy: int = int(_state.cells.get(key, {}).get("energy", 0))
	var saved_at: int = int(_state.last_ms)
	if at_ms == saved_at:
		return {"supported": true, "value": _tenths(energy)}
	if at_ms < int(_state.segment_started_ms):
		return {"supported": false, "reason": "history_unavailable"}
	if not _state.flows.is_empty():
		var boundary: int = mini(SimInventory.MAX_COUNT, saved_at - posmod(saved_at, int(_definitions.step_ms)) + int(_definitions.step_ms))
		if at_ms > boundary:
			return {"supported": false, "reason": "beyond_boundary"}
		var dt: int = at_ms - saved_at
		for flow: Dictionary in _state.flows:
			if str(flow.from) == key:
				energy -= int(flow.rate) * dt
			elif str(flow.to) == key:
				energy += int(flow.rate) * dt
	return {"supported": true, "value": _tenths(energy)} if energy >= 0 else {"supported": false, "reason": "inconsistent_projection"}


func minimum_offset_tenths() -> int:
	return 0


func maximum_offset_tenths() -> int:
	if _definitions.is_empty():
		return 0
	@warning_ignore("integer_division")
	return int(_definitions.max_cell_energy) / int(_definitions.capacity_per_tenth)


func has_visible_offsets(historical: bool) -> bool:
	if _state.is_empty():
		return false
	var values: Dictionary = _state.last_sample_cells if historical else _state.cells
	for value: Variant in values.values():
		var energy: int = int(value) if historical else int(value.energy)
		if energy >= int(_definitions.capacity_per_tenth):
			return true
	return false


func _assign(data: Dictionary) -> void:
	# JSON may decode integral numbers as floats. Normalize the validated copy,
	# leaving both the raw input and any previously accepted candidate untouched.
	var accepted: Dictionary = data.duplicate(true)
	for field: String in ["version", "rules_version", "activation_ms", "last_ms", "segment_started_ms", "input_energy", "loss_energy", "last_sample_ms", "last_sample_input", "last_sample_loss"]:
		accepted[field] = int(accepted[field])
	for key: String in accepted.cells:
		var row: Dictionary = accepted.cells[key]
		row.cell = [int(row.cell[0]), int(row.cell[1])]
		row.energy = int(row.energy)
	for index: int in range(accepted.flows.size()):
		var flow: Dictionary = accepted.flows[index]
		accepted.flows[index] = {"from": str(flow.from), "to": str(flow.to), "rate": int(flow.rate)}
	for action: String in accepted.receipts:
		accepted.receipts[action] = _normalized_receipt(accepted.receipts[action])
	for key: String in accepted.last_sample_cells:
		accepted.last_sample_cells[key] = int(accepted.last_sample_cells[key])
	_state = accepted


func _valid_state(data: Variant) -> bool:
	if _definitions.is_empty() or not Shape.keys(data, STATE_KEYS) or data.version != 1 or data.rules_version != _definitions.version:
		return false
	var now: int = int(_world.get("elapsed_ms"))
	if not Shape.count(data.activation_ms, 0, now) or not Shape.count(data.last_ms, int(data.activation_ms), now) or int(data.last_ms) != now:
		return false
	if not Shape.count(data.segment_started_ms, int(data.activation_ms), now) or now - int(data.segment_started_ms) >= int(_definitions.step_ms) or int(data.segment_started_ms) < now - posmod(now, int(_definitions.step_ms)):
		return false
	if not data.cells is Dictionary or data.cells.size() > int(_definitions.max_cells) or not data.flows is Array or not data.receipts is Dictionary or not data.last_sample_cells is Dictionary:
		return false
	if not Shape.count(data.input_energy, 0, int(_definitions.max_total_input)) or not Shape.count(data.loss_energy, 0, int(data.input_energy)):
		return false
	var sum: int = 0
	for key: Variant in data.cells:
		var row: Variant = data.cells[key]
		if not key is String or not Shape.keys(row, ["cell", "energy"]) or not _cell_array(row.cell) or key != _key(Vector2i(int(row.cell[0]), int(row.cell[1]))) or not Shape.count(row.energy, 0, int(_definitions.max_cell_energy)):
			return false
		sum += int(row.energy)
	if sum + int(data.loss_energy) != int(data.input_energy) or data.flows.size() > data.cells.size() * 5:
		return false
	var anchors: Dictionary = data.cells.duplicate(true)
	var edges: Dictionary = {}
	var outgoing: Dictionary = {}
	var dt: int = now - int(data.segment_started_ms)
	var bath_rate: int = 0
	for raw: Variant in data.flows:
		if not Shape.keys(raw, ["from", "to", "rate"]) or not raw.from is String or not raw.to is String or not data.cells.has(raw.from) or not Shape.count(raw.rate, 1, _maximum_rate()) or raw.from == raw.to:
			return false
		if not str(raw.to).is_empty() and not data.cells.has(raw.to):
			return false
		var edge: String = str(raw.from) + ">" + str(raw.to)
		if edges.has(edge):
			return false
		edges[edge] = true
		outgoing[raw.from] = int(outgoing.get(raw.from, 0)) + int(raw.rate)
		anchors[raw.from].energy = int(anchors[raw.from].energy) + int(raw.rate) * dt
		if str(raw.to).is_empty():
			bath_rate += int(raw.rate)
		else:
			var from: Array = data.cells[raw.from].cell
			var to: Array = data.cells[raw.to].cell
			if absi(int(from[0]) - int(to[0])) + absi(int(from[1]) - int(to[1])) != 1:
				return false
			anchors[raw.to].energy = int(anchors[raw.to].energy) - int(raw.rate) * dt
	if int(data.loss_energy) < bath_rate * dt:
		return false
	for key: String in anchors:
		if int(anchors[key].energy) < 0 or int(anchors[key].energy) > int(_definitions.max_cell_energy) or int(outgoing.get(key, 0)) * int(_definitions.step_ms) > int(anchors[key].energy):
			return false
	# Validate the stored frozen slope against its reconstructed anchor and
	# the actual restored geometry, rather than trusting a forged fast leak.
	var expected_flows: Array[Dictionary] = _build_flows(anchors)
	if expected_flows.size() != data.flows.size():
		return false
	for index: int in range(expected_flows.size()):
		if not Shape.same_record(data.flows[index], expected_flows[index]):
			return false
	var receipt_sum: int = 0
	var expected_cells: Dictionary = {}
	for action: Variant in data.receipts:
		var receipt: Variant = data.receipts[action]
		if not action is String or not _valid_receipt(receipt, int(data.activation_ms)) or action != receipt.action or int(receipt.at_ms) > now or not data.cells.has(_key(Vector2i(int(receipt.cell[0]), int(receipt.cell[1])))) or not _source_matches(receipt):
			return false
		if int(receipt.amount) > int(_definitions.max_total_input) - receipt_sum:
			return false
		receipt_sum += int(receipt.amount)
		# Successful sources are the only allocator and allocate their whole
		# finite patch; existing cells are never reclaimed in this version.
		# Reject ghost zero-energy cells and missing cold boundary cells alike.
		for point: Vector2i in _patch(Vector2i(int(receipt.cell[0]), int(receipt.cell[1]))):
			var key: String = _key(point)
			if not data.cells.has(key):
				return false
			expected_cells[key] = true
	if expected_cells.size() != data.cells.size():
		return false
	if receipt_sum != int(data.input_energy) or not _all_sources_present(data.receipts, int(data.activation_ms), now):
		return false
	if not Shape.count(data.last_sample_ms, int(data.activation_ms), now) or int(data.last_sample_ms) != int(data.activation_ms) and posmod(int(data.last_sample_ms), int(_definitions.sample_ms)) != 0:
		return false
	if not Shape.count(data.last_sample_input, 0, int(data.input_energy)) or not Shape.count(data.last_sample_loss, 0, int(data.loss_energy)):
		return false
	var sample_sum: int = 0
	for key: Variant in data.last_sample_cells:
		if not key is String or not data.cells.has(key) or not Shape.count(data.last_sample_cells[key], 1, int(_definitions.max_cell_energy)):
			return false
		sample_sum += int(data.last_sample_cells[key])
	if sample_sum + int(data.last_sample_loss) != int(data.last_sample_input):
		return false
	if int(data.last_sample_ms) == int(data.activation_ms) and (not data.last_sample_cells.is_empty() or int(data.last_sample_input) != 0 or int(data.last_sample_loss) != 0):
		return false
	return true


func _source_matches(receipt: Dictionary) -> bool:
	if _receipt_validator.is_valid():
		return bool(_receipt_validator.call(receipt))
	var authority: RefCounted = _world
	var artifacts: Variant = authority.get("artifacts")
	if artifacts == null:
		return false
	for event: Dictionary in artifacts.events:
		if str(event.get("action", "")) == receipt.action:
			if artifacts.has_method("has_capability") and not bool(artifacts.has_capability(str(receipt.object), "heat_storage")):
				return false
			var source_cell: Variant = event.get("cell")
			var same_cell: bool = _cell_array(source_cell) and int(source_cell[0]) == int(receipt.cell[0]) and int(source_cell[1]) == int(receipt.cell[1])
			return event.get("kind") == "warmed" and event.get("actor") == receipt.actor and event.get("object") == receipt.object and event.get("at_ms") == receipt.at_ms and same_cell and event.get("heat_amount") == receipt.amount
	return false


func _all_sources_present(candidate: Dictionary, activation: int, now: int) -> bool:
	if _expected_actions.is_valid():
		var expected: Variant = _expected_actions.call()
		if not expected is Array or expected.size() != candidate.size():
			return false
		var provided_actions: Dictionary = {}
		for action: Variant in expected:
			if not action is String or not candidate.has(action) or provided_actions.has(action):
				return false
			provided_actions[action] = true
		return true
	var artifacts: Variant = _world.get("artifacts")
	if artifacts == null:
		return candidate.is_empty()
	var recorded_actions: Dictionary = {}
	for event: Dictionary in artifacts.events:
		if event.get("kind") == "warmed" and int(event.get("at_ms", -1)) >= activation and int(event.get("at_ms", -1)) <= now:
			if artifacts.has_method("has_capability") and not bool(artifacts.has_capability(str(event.get("object", "")), "heat_storage")):
				return false
			var action: String = str(event.get("action", ""))
			if not candidate.has(action) or recorded_actions.has(action):
				return false
			recorded_actions[action] = true
	return recorded_actions.size() == candidate.size()


func _valid_receipt(receipt: Variant, earliest: int = 0) -> bool:
	return Shape.keys(receipt, ["action", "actor", "object", "at_ms", "cell", "amount"]) and SimInventory._nonempty(receipt.action) and SimInventory._nonempty(receipt.actor) and SimInventory._nonempty(receipt.object) and Shape.count(receipt.at_ms, earliest, SimInventory.MAX_COUNT) and _cell_array(receipt.cell) and Shape.count(receipt.amount, 1, int(_definitions.get("max_cell_energy", 0))) and receipt.amount == _definitions.pulse_energy


static func _normalized_receipt(receipt: Dictionary) -> Dictionary:
	return {"action": str(receipt.action), "actor": str(receipt.actor), "object": str(receipt.object), "at_ms": int(receipt.at_ms), "cell": [int(receipt.cell[0]), int(receipt.cell[1])], "amount": int(receipt.amount)}


func _build_flows(state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key: String in _sorted(state):
		var row: Dictionary = state[key]
		var point := Vector2i(int(row.cell[0]), int(row.cell[1]))
		var bath: int = _rate(int(row.energy), int(_definitions.bath_loss.roofed) if _roofed.is_valid() and bool(_roofed.call(point)) else int(_definitions.bath_loss.unroofed))
		for side: Vector2i in SIDES:
			var neighbor: Vector2i = point + side
			var adjacent: String = _key(neighbor)
			var coefficient: int = mini(_conductance(point), _conductance(neighbor))
			if not state.has(adjacent):
				# A declared finite patch exchanges with the original outside
				# background here. No hidden neighboring reservoir is invented.
				bath += _rate(int(row.energy), coefficient)
			elif key < adjacent:
				var difference: int = int(row.energy) - int(state[adjacent].energy)
				var rate: int = _rate(absi(difference), coefficient)
				if rate > 0:
					result.append({"from": key if difference > 0 else adjacent, "to": adjacent if difference > 0 else key, "rate": rate})
		if bath > 0:
			result.append({"from": key, "to": "", "rate": bath})
	return result


func _conductance(point: Vector2i) -> int:
	var kind: String = "open"
	if _barrier.is_valid() and _valid_cell(point):
		var value: Variant = _barrier.call(point)
		kind = ("wall" if value else "open") if value is bool else str(value)
	return int(_definitions.conductance.get(kind, _definitions.conductance.wall))


# Truncate the frozen energy/ms slope deliberately. Sub-rate energy stays in
# the original cell rather than moving through a rounded-up transfer.
func _rate(energy: int, coefficient: int) -> int:
	@warning_ignore("integer_division")
	return energy * coefficient / (int(_definitions.coefficient_scale) * int(_definitions.step_ms))


func _patch(center: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var radius: int = int(_definitions.source_radius)
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			var point := Vector2i(x, y)
			if _valid_cell(point):
				result.append(point)
	return result


func _valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < int(_definitions.world_size) and cell.y < int(_definitions.world_size)


func _cell_array(value: Variant) -> bool:
	return value is Array and value.size() == 2 and Shape.count(value[0], 0, int(_definitions.world_size) - 1) and Shape.count(value[1], 0, int(_definitions.world_size) - 1)


# Only complete tenths are observable; retain all fractional heat in its cell.
func _tenths(energy: int) -> int:
	@warning_ignore("integer_division")
	return energy / int(_definitions.capacity_per_tenth)


# The safe outflow bound counts only complete energy units per millisecond.
func _maximum_rate() -> int:
	@warning_ignore("integer_division")
	return int(_definitions.max_cell_energy) / int(_definitions.step_ms)


static func _key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func _sorted(data: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: String in data:
		result.append(key)
	result.sort()
	return result
