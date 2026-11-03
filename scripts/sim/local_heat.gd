class_name SimLocalHeat
extends RefCounted
## Sparse positive heat above the original outdoor background, not an absolute
## thermodynamic simulation. Fixed cells own energy; rooms own no second heat.
## Integer energy/ms fluxes freeze at global boundaries and real mutations.
## Calling settle at additional times never recomputes those fluxes or rounds
## an extra fractional transfer. Internal transfers cancel exactly; only the
## explicit outdoor bath may remove heat. sum(cells) + loss == input.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]
const MAX_INTEGER: int = 9007199254740991
var definitions: Dictionary = {}
var activation_ms: int = 0
var last_ms: int = 0
var segment_started_ms: int = 0
var cells: Dictionary = {}
var flows: Array[Dictionary] = []
var input_energy: int = 0
var loss_energy: int = 0
var receipts: Dictionary = {}
var last_sample_ms: int = 0
var last_sample_cells: Dictionary = {}
var last_sample_input: int = 0
var last_sample_loss: int = 0
var _owner: WeakRef
var _roofed: Callable
var _barrier: Callable
var _receipt_validator: Callable
var _expected_actions: Callable
var _geometry_dirty: bool = false
var world: RefCounted:
	get:
		return null if _owner == null else _owner.get_ref()


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


func bind_world(authority: RefCounted) -> void:
	# Rebind a validated candidate without resetting its saved process.
	_owner = weakref(authority)


func initialize(authority: RefCounted, rules: Dictionary) -> bool:
	if authority == null or not valid_definitions(rules) or not Shape.count(authority.get("elapsed_ms"), 0, SimInventory.MAX_COUNT):
		return false
	_owner = weakref(authority)
	definitions = rules.duplicate(true)
	_assign(empty_state(int(authority.get("elapsed_ms"))))
	return true


static func empty_state(at_ms: int) -> Dictionary:
	return {"version": 1, "rules_version": 1, "activation_ms": at_ms, "last_ms": at_ms,
		"segment_started_ms": at_ms, "cells": {}, "flows": [], "input_energy": 0,
		"loss_energy": 0, "receipts": {}, "last_sample_ms": at_ms,
		"last_sample_cells": {}, "last_sample_input": 0, "last_sample_loss": 0}


func set_geometry(roofed: Callable, barrier: Callable) -> void:
	_roofed = roofed
	_barrier = barrier
	_geometry_dirty = true


func set_source_validator(receipt_validator: Callable, expected_actions: Callable) -> void:
	_receipt_validator = receipt_validator
	_expected_actions = expected_actions


func before_topology_change(now: int) -> void:
	# Repeated hooks in a single demolition/collapse transaction are harmless.
	if not _geometry_dirty:
		settle_at_ms(now)
	elif now > last_ms:
		settle_at_ms(now)
	_geometry_dirty = true


func after_topology_change(now: int) -> void:
	if now != last_ms:
		return
	_freeze()


func refresh_geometry() -> void:
	_freeze()


func next_boundary_ms() -> int:
	# Integer quantization may leave nonzero energy below every transfer
	# threshold. Its future is constant until an actual source/layout event.
	if flows.is_empty():
		return SimInventory.MAX_COUNT
	return mini(SimInventory.MAX_COUNT, last_ms - posmod(last_ms, int(definitions.step_ms)) + int(definitions.step_ms))


func settle_at_ms(now: int) -> bool:
	if definitions.is_empty() or not Shape.count(now, last_ms, SimInventory.MAX_COUNT):
		return false
	if _geometry_dirty:
		_freeze()
	while last_ms < now:
		if flows.is_empty():
			# No per-step geometry queries or artificial loss of residual heat.
			# Keep the empty frozen segment anchored at the actual save time.
			last_ms = now
			segment_started_ms = now
			return true
		var boundary: int = next_boundary_ms()
		var target: int = mini(now, boundary)
		_integrate(target - last_ms)
		last_ms = target
		if target == boundary:
			_freeze()
	return true


func can_deposit(cell: Vector2i, amount: int) -> bool:
	if definitions.is_empty() or not _valid_cell(cell) or not Shape.count(amount, 1, int(definitions.max_cell_energy)) or input_energy > int(definitions.max_total_input) - amount:
		return false
	var key: String = _key(cell)
	if int(cells.get(key, {}).get("energy", 0)) > int(definitions.max_cell_energy) - amount:
		return false
	var added: int = 0
	for point: Vector2i in _patch(cell):
		if not cells.has(_key(point)):
			added += 1
	return cells.size() + added <= int(definitions.max_cells)


func deposit(source_receipt: Dictionary) -> bool:
	if not _valid_receipt(source_receipt, activation_ms) or receipts.has(source_receipt.action) or int(source_receipt.at_ms) != int(world.get("elapsed_ms")) or int(source_receipt.at_ms) < last_ms:
		return false
	var point := Vector2i(int(source_receipt.cell[0]), int(source_receipt.cell[1]))
	# Reject source capacity before any resource transaction. Settling actual
	# elapsed time is independent of whether a source transaction succeeds.
	if not settle_at_ms(int(source_receipt.at_ms)) or not can_deposit(point, int(source_receipt.amount)):
		return false
	for cell: Vector2i in _patch(point):
		var key: String = _key(cell)
		if not cells.has(key):
			cells[key] = {"cell": [cell.x, cell.y], "energy": 0}
	cells[_key(point)].energy = int(cells[_key(point)].energy) + int(source_receipt.amount)
	input_energy += int(source_receipt.amount)
	receipts[str(source_receipt.action)] = _normalized_receipt(source_receipt)
	_freeze()
	return true


func local_tenths(cell: Vector2i, at_ms: int = -1) -> int:
	var now: int = int(world.get("elapsed_ms")) if at_ms < 0 else at_ms
	if not _valid_cell(cell) or not settle_at_ms(now):
		return 0
	return _tenths(int(cells.get(_key(cell), {}).get("energy", 0)))


func project_tenths(cell: Vector2i, at_ms: int) -> int:
	# Initiative may inspect its next decision before the world commits that
	# time. Project the already frozen law without committing a clock, sampling
	# geometry or changing any cache. -1 explicitly means unsupported history
	# or a future beyond the next real heat boundary, never zero heat.
	if definitions.is_empty() or not _valid_cell(cell) or not Shape.count(at_ms, 0, SimInventory.MAX_COUNT):
		return -1
	var key: String = _key(cell)
	var energy: int = int(cells.get(key, {}).get("energy", 0))
	if at_ms == last_ms:
		return _tenths(energy)
	if _geometry_dirty:
		# Initial empty heat remains empty under every possible geometry.
		return 0 if input_energy == loss_energy and at_ms >= last_ms else -1
	if at_ms < segment_started_ms or not flows.is_empty() and at_ms > next_boundary_ms():
		return -1
	if flows.is_empty():
		return _tenths(energy)
	var dt: int = at_ms - last_ms
	for flow: Dictionary in flows:
		if str(flow.from) == key:
			energy -= int(flow.rate) * dt
		elif str(flow.to) == key:
			energy += int(flow.rate) * dt
	return _tenths(energy) if energy >= 0 else -1


func mark_sample(now: int) -> bool:
	if definitions.is_empty() or now < activation_ms or posmod(now, int(definitions.sample_ms)) != 0 or now < last_sample_ms or not settle_at_ms(now):
		return false
	# Repeating a sample at the same timestamp must not replace history after
	# a later semantic event at that timestamp. Scheduler orders this once.
	if now == last_sample_ms:
		return true
	last_sample_ms = now
	last_sample_cells = {}
	for key: String in _sorted(cells):
		if int(cells[key].energy) > 0:
			last_sample_cells[key] = int(cells[key].energy)
	last_sample_input = input_energy
	last_sample_loss = loss_energy
	return true


func sample_tenths(cell: Vector2i, at_ms: int) -> int:
	if definitions.is_empty() or at_ms != last_sample_ms or not _valid_cell(cell):
		return 0
	return _tenths(int(last_sample_cells.get(_key(cell), 0)))


func to_dict() -> Dictionary:
	if _geometry_dirty:
		_freeze()
	return {"version": 1, "rules_version": int(definitions.version), "activation_ms": activation_ms,
		"last_ms": last_ms, "segment_started_ms": segment_started_ms, "cells": cells.duplicate(true),
		"flows": flows.duplicate(true), "input_energy": input_energy, "loss_energy": loss_energy,
		"receipts": receipts.duplicate(true), "last_sample_ms": last_sample_ms,
		"last_sample_cells": last_sample_cells.duplicate(true), "last_sample_input": last_sample_input,
		"last_sample_loss": last_sample_loss}


func restore(data: Variant) -> bool:
	if not _valid_state(data):
		return false
	_assign(data)
	return true


func _assign(data: Dictionary) -> void:
	activation_ms = int(data.activation_ms)
	last_ms = int(data.last_ms)
	segment_started_ms = int(data.segment_started_ms)
	cells = data.cells.duplicate(true)
	flows.clear()
	for flow: Dictionary in data.flows:
		flows.append({"from": str(flow.from), "to": str(flow.to), "rate": int(flow.rate)})
	for key: String in cells:
		cells[key].energy = int(cells[key].energy)
		cells[key].cell = [int(cells[key].cell[0]), int(cells[key].cell[1])]
	input_energy = int(data.input_energy)
	loss_energy = int(data.loss_energy)
	receipts = {}
	for action: String in data.receipts:
		receipts[action] = _normalized_receipt(data.receipts[action])
	last_sample_ms = int(data.last_sample_ms)
	last_sample_cells = {}
	for key: String in data.last_sample_cells:
		last_sample_cells[key] = int(data.last_sample_cells[key])
	last_sample_input = int(data.last_sample_input)
	last_sample_loss = int(data.last_sample_loss)
	_geometry_dirty = false


func _valid_state(data: Variant) -> bool:
	if definitions.is_empty() or not Shape.keys(data, empty_state(0).keys()) or data.version != 1 or data.rules_version != definitions.version:
		return false
	var now: int = int(world.get("elapsed_ms"))
	if not Shape.count(data.activation_ms, 0, now) or not Shape.count(data.last_ms, int(data.activation_ms), now) or int(data.last_ms) != now:
		return false
	if not Shape.count(data.segment_started_ms, int(data.activation_ms), now) or now - int(data.segment_started_ms) >= int(definitions.step_ms) or int(data.segment_started_ms) < now - posmod(now, int(definitions.step_ms)):
		return false
	if not data.cells is Dictionary or data.cells.size() > int(definitions.max_cells) or not data.flows is Array or not data.receipts is Dictionary or not data.last_sample_cells is Dictionary:
		return false
	if not Shape.count(data.input_energy, 0, int(definitions.max_total_input)) or not Shape.count(data.loss_energy, 0, int(data.input_energy)):
		return false
	var sum: int = 0
	for key: Variant in data.cells:
		var row: Variant = data.cells[key]
		if not key is String or not Shape.keys(row, ["cell", "energy"]) or not _cell_array(row.cell) or key != _key(Vector2i(int(row.cell[0]), int(row.cell[1]))) or not Shape.count(row.energy, 0, int(definitions.max_cell_energy)):
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
		if int(anchors[key].energy) < 0 or int(anchors[key].energy) > int(definitions.max_cell_energy) or int(outgoing.get(key, 0)) * int(definitions.step_ms) > int(anchors[key].energy):
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
	if not Shape.count(data.last_sample_ms, int(data.activation_ms), now) or int(data.last_sample_ms) != int(data.activation_ms) and posmod(int(data.last_sample_ms), int(definitions.sample_ms)) != 0:
		return false
	if not Shape.count(data.last_sample_input, 0, int(data.input_energy)) or not Shape.count(data.last_sample_loss, 0, int(data.loss_energy)):
		return false
	var sample_sum: int = 0
	for key: Variant in data.last_sample_cells:
		if not key is String or not data.cells.has(key) or not Shape.count(data.last_sample_cells[key], 1, int(definitions.max_cell_energy)):
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
	var authority: RefCounted = world
	var artifacts: Variant = authority.get("artifacts")
	if artifacts == null:
		return false
	for event: Dictionary in artifacts.events:
		if str(event.get("action", "")) == receipt.action:
			if artifacts.has_method("has_capability") and not bool(artifacts.has_capability(str(receipt.object), "heat_storage")):
				return false
			var source_cell: Variant = event.get("cell")
			var same_cell: bool = _cell_array(source_cell) and int(source_cell[0]) == int(receipt.cell[0]) and int(source_cell[1]) == int(receipt.cell[1])
			return event.get("kind") == "warmed" and event.get("actor") == receipt.actor and event.get("object") == receipt.object and event.get("at_ms") == receipt.at_ms and same_cell and (not event.has("heat_amount") or event.heat_amount == receipt.amount)
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
	var artifacts: Variant = world.get("artifacts")
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
	return Shape.keys(receipt, ["action", "actor", "object", "at_ms", "cell", "amount"]) and SimInventory._nonempty(receipt.action) and SimInventory._nonempty(receipt.actor) and SimInventory._nonempty(receipt.object) and Shape.count(receipt.at_ms, earliest, SimInventory.MAX_COUNT) and _cell_array(receipt.cell) and Shape.count(receipt.amount, 1, int(definitions.get("max_cell_energy", 0))) and receipt.amount == definitions.pulse_energy


static func _normalized_receipt(receipt: Dictionary) -> Dictionary:
	return {"action": str(receipt.action), "actor": str(receipt.actor), "object": str(receipt.object), "at_ms": int(receipt.at_ms), "cell": [int(receipt.cell[0]), int(receipt.cell[1])], "amount": int(receipt.amount)}


func _freeze() -> void:
	flows = _build_flows(cells)
	segment_started_ms = last_ms
	_geometry_dirty = false


func _build_flows(state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key: String in _sorted(state):
		var row: Dictionary = state[key]
		var point := Vector2i(int(row.cell[0]), int(row.cell[1]))
		var bath: int = _rate(int(row.energy), int(definitions.bath_loss.roofed) if _roofed.is_valid() and bool(_roofed.call(point)) else int(definitions.bath_loss.unroofed))
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
	return int(definitions.conductance.get(kind, definitions.conductance.wall))


# Truncate the frozen energy/ms slope deliberately. Sub-rate energy stays in
# the original cell rather than moving through a rounded-up transfer.
func _rate(energy: int, coefficient: int) -> int:
	@warning_ignore("integer_division")
	return energy * coefficient / (int(definitions.coefficient_scale) * int(definitions.step_ms))


func _integrate(dt: int) -> void:
	for flow: Dictionary in flows:
		var amount: int = int(flow.rate) * dt
		cells[flow.from].energy = int(cells[flow.from].energy) - amount
		if str(flow.to).is_empty():
			loss_energy += amount
		else:
			cells[flow.to].energy = int(cells[flow.to].energy) + amount


func _patch(center: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var radius: int = int(definitions.source_radius)
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			var point := Vector2i(x, y)
			if _valid_cell(point):
				result.append(point)
	return result


func _valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < int(definitions.world_size) and cell.y < int(definitions.world_size)


func _cell_array(value: Variant) -> bool:
	return value is Array and value.size() == 2 and Shape.count(value[0], 0, int(definitions.world_size) - 1) and Shape.count(value[1], 0, int(definitions.world_size) - 1)


# Only complete tenths are observable; retain all fractional heat in its cell.
func _tenths(energy: int) -> int:
	@warning_ignore("integer_division")
	return energy / int(definitions.capacity_per_tenth)


# The safe outflow bound counts only complete energy units per millisecond.
func _maximum_rate() -> int:
	@warning_ignore("integer_division")
	return int(definitions.max_cell_energy) / int(definitions.step_ms)


static func _key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func _sorted(data: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: String in data:
		result.append(key)
	result.sort()
	return result
