class_name SimLocalHeat
extends RefCounted
## Fixed-reference nonnegative energy, frozen integer fluxes and explicit bath
## accounting. One physical field; rooms, recipients and views own no heat.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const Legacy = preload("res://scripts/persistence/legacy_heat_v1.gd")
const TransferBudget = preload("res://scripts/sim/thermal_transfer_budget.gd")
const VERSION: int = 2
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]
const MAX_INTEGER: int = 9007199254740991
var definitions: Dictionary = {}
var activation_ms: int = 0
var model_started_ms: int = 0
var last_ms: int = 0
var segment_started_ms: int = 0
var cells: Dictionary = {}
var flows: Array[Dictionary] = []
var input_energy: int = 0
var ambient_in: int = 0
var loss_energy: int = 0
var receipts: Dictionary = {}
var last_sample_ms: int = 0
var last_sample_cells: Dictionary = {}
var last_sample_input: int = 0
var last_sample_loss: int = 0
var last_sample_ambient_in: int = 0
var last_sample_mode: String = "absolute"
var legacy_limits: Dictionary = {}
var _owner: WeakRef
var _roofed: Callable
var _barrier: Callable
var _receipt_validator: Callable
var _expected_actions: Callable
var _geometry_dirty: bool = false
var _background_query: Callable
var _background_boundary: Callable
var _frozen_boundary_ms: int = MAX_INTEGER
var world: RefCounted:
	get:
		return null if _owner == null else _owner.get_ref()


static func upgrade_definitions_v1(old: Variant) -> Dictionary:
	if not Legacy.valid_definitions(old):
		return {}
	var next: Dictionary = old.duplicate(true)
	next.version = VERSION
	next["reference_tenths"] = -10000
	next["max_exchange_energy"] = MAX_INTEGER
	next.max_cell_energy = int(old.max_cell_energy) + 13000 * int(old.capacity_per_tenth)
	return next if valid_definitions(next) else {}


static func valid_definitions(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != VERSION or data.get("reference_tenths") != -10000 or not Shape.count(data.get("max_exchange_energy"), 1, MAX_INTEGER):
		return false
	var prior: Dictionary = data.duplicate(true)
	prior.erase("reference_tenths")
	prior.erase("max_exchange_energy")
	prior.version = 1
	if not Shape.count(data.get("capacity_per_tenth"), 1, 1000000000) or not Shape.count(data.get("max_cell_energy"), 13000 * int(data.capacity_per_tenth) + 1, 14000000000000):
		return false
	if not Shape.count(data.get("pulse_energy"), 1, int(data.max_cell_energy)) or not Shape.count(data.get("max_total_input"), int(data.pulse_energy), MAX_INTEGER):
		return false
	# Legacy validates the shared stable conductance/lattice and field list;
	# v2 source budgets are independent of the larger absolute-Q ceiling.
	prior.max_cell_energy = mini(int(data.max_cell_energy), 1000000000000)
	prior.pulse_energy = mini(int(data.pulse_energy), int(prior.max_cell_energy))
	prior.max_total_input = maxi(int(data.max_total_input), int(prior.max_cell_energy))
	return Legacy.valid_definitions(prior)


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
	return {"version": VERSION, "rules_version": VERSION, "activation_ms": at_ms,
		"model_started_ms": at_ms, "last_ms": at_ms, "segment_started_ms": at_ms,
		"cells": {}, "flows": [], "input_energy": 0, "ambient_in": 0, "loss_energy": 0,
		"receipts": {}, "last_sample_ms": at_ms, "last_sample_cells": {},
		"last_sample_input": 0, "last_sample_loss": 0, "last_sample_ambient_in": 0,
		"last_sample_mode": "absolute", "legacy_limits": {}}


func set_background(query: Callable, boundary: Callable) -> void:
	_background_query = query
	_background_boundary = boundary
	_geometry_dirty = true


func _background(cell: Vector2i, at_ms: int) -> int:
	if _background_query.is_valid():
		return int(_background_query.call(cell, at_ms))
	var content: ReolContentDB = world.get("_content")
	var weather: RefCounted = world.get("weather")
	var value: Dictionary = SimClimateRules.background_at(content.climate, weather.definitions, weather.epoch_ms, cell, at_ms)
	return int(value.temperature_tenths)


func _background_next(cell: Vector2i, at_ms: int) -> int:
	if _background_boundary.is_valid():
		return int(_background_boundary.call(cell, at_ms))
	var content: ReolContentDB = world.get("_content")
	var weather: RefCounted = world.get("weather")
	return SimClimateRules.next_background_boundary_ms(content.climate, weather.definitions, weather.epoch_ms, SimClimateRules.region_at(content.climate, cell), at_ms)


func _baseline(cell: Vector2i, at_ms: int) -> int:
	return (_background(cell, at_ms) - int(definitions.reference_tenths)) * int(definitions.capacity_per_tenth)


func _default_background_context() -> Dictionary:
	var content: ReolContentDB = world.get("_content")
	var weather: RefCounted = world.get("weather")
	return {"climate": content.climate, "weather": weather.definitions, "epoch_ms": weather.epoch_ms}


func _baseline_for_pass(cell: Vector2i, at_ms: int, context: Dictionary, by_region: Dictionary) -> int:
	# One pass has one explicit timestamp. Never reuse a value across freezes,
	# candidate anchors, worlds, or custom per-cell background providers.
	if context.is_empty():
		return _baseline(cell, at_ms)
	var region: String = SimClimateRules.region_at(context.climate, cell)
	if not by_region.has(region):
		var background: Dictionary = SimClimateRules.background_for_region(context.climate, context.weather, int(context.epoch_ms), region, at_ms)
		by_region[region] = (int(background.temperature_tenths) - int(definitions.reference_tenths)) * int(definitions.capacity_per_tenth)
	return int(by_region[region])


func _boundary_for_pass(cell: Vector2i, at_ms: int, context: Dictionary, by_region: Dictionary) -> int:
	if context.is_empty():
		return _background_next(cell, at_ms)
	var region: String = SimClimateRules.region_at(context.climate, cell)
	if not by_region.has(region):
		by_region[region] = SimClimateRules.next_background_boundary_ms(context.climate, context.weather, int(context.epoch_ms), region, at_ms)
	return int(by_region[region])


func _offset(energy: int, cell: Vector2i, at_ms: int) -> int:
	# Divide nonnegative Q first; negative integer division truncates toward zero.
	return int(definitions.reference_tenths) + _tenths(energy) - _background(cell, at_ms)


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


func _boundary_at(at_ms: int, state: Dictionary, active_flows: Array) -> int:
	if state.is_empty() or at_ms == MAX_INTEGER:
		return MAX_INTEGER
	var context: Dictionary = {} if _background_boundary.is_valid() else _default_background_context()
	var by_region: Dictionary = {}
	var next: int = MAX_INTEGER
	if not active_flows.is_empty():
		var distance: int = int(definitions.step_ms) - posmod(at_ms, int(definitions.step_ms))
		var span: int = TransferBudget.field_span(active_flows, state, int(definitions.max_cell_energy), distance)
		if span == 0:
			# A damaged/unsupported slope cannot borrow heat or free room from
			# another flow in this same segment. Leave time pending explicitly.
			return at_ms
		next = at_ms + mini(span, MAX_INTEGER - at_ms)
	for row: Dictionary in state.values():
		var point := Vector2i(int(row.cell[0]), int(row.cell[1]))
		next = mini(next, _boundary_for_pass(point, at_ms, context, by_region))
		for side: Vector2i in SIDES:
			if not state.has(_key(point + side)):
				next = mini(next, _boundary_for_pass(point + side, at_ms, context, by_region))
	return next


func next_boundary_ms() -> int:
	return _frozen_boundary_ms


func can_settle_at_ms(now: int) -> bool:
	# Preflight one frozen segment before the regional executor advances bodies.
	if definitions.is_empty() or not Shape.count(now, last_ms, MAX_INTEGER):
		return false
	if cells.is_empty():
		return true
	if _geometry_dirty or now > next_boundary_ms():
		return false
	var dt: int = now - last_ms
	var incoming: int = 0
	var outgoing: int = 0
	var deltas: Dictionary = {}
	for flow: Dictionary in flows:
		var amount: int = int(flow.rate) * dt
		if str(flow.from).is_empty():
			incoming += amount
		else:
			deltas[flow.from] = int(deltas.get(flow.from, 0)) - amount
		if str(flow.to).is_empty():
			outgoing += amount
		else:
			deltas[flow.to] = int(deltas.get(flow.to, 0)) + amount
	if incoming > int(definitions.max_exchange_energy) - ambient_in or incoming > MAX_INTEGER - input_energy - ambient_in or outgoing > int(definitions.max_exchange_energy) - loss_energy:
		return false
	for key: String in deltas:
		var value: int = int(cells[key].energy) + int(deltas[key])
		if value < 0 or value > int(definitions.max_cell_energy):
			return false
	return true


func settle_at_ms(now: int) -> bool:
	if definitions.is_empty() or not Shape.count(now, last_ms, MAX_INTEGER):
		return false
	if _geometry_dirty:
		_freeze()
	while last_ms < now:
		var boundary: int = next_boundary_ms()
		var target: int = mini(now, boundary)
		if target <= last_ms or not can_settle_at_ms(target):
			return false
		_integrate(target - last_ms)
		last_ms = target
		if target == boundary or cells.is_empty():
			_freeze()
		elif flows.is_empty():
			# No slope to reconstruct: anchor at the accepted instant without
			# sampling geometry or changing the next declared climate boundary.
			segment_started_ms = last_ms
	return true


func can_deposit(cell: Vector2i, amount: int) -> bool:
	if definitions.is_empty() or not _valid_cell(cell) or not Shape.count(amount, 1, int(definitions.pulse_energy)) or input_energy > int(definitions.max_total_input) - amount:
		return false
	var source_q: int = int(cells.get(_key(cell), {}).get("energy", _baseline(cell, last_ms)))
	if source_q > int(definitions.max_cell_energy) - amount:
		return false
	var added: int = 0
	var baseline_sum: int = 0
	for point: Vector2i in _patch(cell):
		if cells.has(_key(point)):
			continue
		var energy: int = _baseline(point, last_ms)
		if energy < 0 or energy > int(definitions.max_cell_energy) or baseline_sum > MAX_INTEGER - energy:
			return false
		baseline_sum += energy
		added += 1
	return cells.size() + added <= int(definitions.max_cells) and baseline_sum <= int(definitions.max_exchange_energy) - ambient_in and baseline_sum <= MAX_INTEGER - input_energy - ambient_in - amount


func deposit(source_receipt: Dictionary) -> bool:
	if not _valid_receipt(source_receipt, activation_ms) or receipts.has(source_receipt.action) or int(source_receipt.at_ms) != int(world.get("elapsed_ms")) or int(source_receipt.at_ms) < last_ms:
		return false
	var point := Vector2i(int(source_receipt.cell[0]), int(source_receipt.cell[1]))
	if not settle_at_ms(int(source_receipt.at_ms)) or not can_deposit(point, int(source_receipt.amount)):
		return false
	for cell: Vector2i in _patch(point):
		var key: String = _key(cell)
		if not cells.has(key):
			var energy: int = _baseline(cell, last_ms)
			cells[key] = {"cell": [cell.x, cell.y], "energy": energy, "allocated_ms": last_ms, "baseline_energy": energy}
			ambient_in += energy
	cells[_key(point)].energy = int(cells[_key(point)].energy) + int(source_receipt.amount)
	input_energy += int(source_receipt.amount)
	receipts[str(source_receipt.action)] = _normalized_receipt(source_receipt)
	_freeze()
	return true


func current_tenths(cell: Vector2i) -> int:
	return _offset(int(cells[_key(cell)].energy), cell, last_ms) if _valid_cell(cell) and cells.has(_key(cell)) else 0


func local_tenths(cell: Vector2i, at_ms: int = -1) -> int:
	var now: int = int(world.get("elapsed_ms")) if at_ms < 0 else at_ms
	if not _valid_cell(cell) or not settle_at_ms(now):
		return 0
	return current_tenths(cell)


func project_tenths(cell: Vector2i, at_ms: int) -> Dictionary:
	# Initiative may inspect its next decision before the world commits that
	# time. Project the already frozen law without committing a clock, sampling
	# geometry or changing any cache. Unsupported results contain no numeric
	# value: a future cold offset must never be confused with a failure sentinel.
	if definitions.is_empty():
		return {"supported": false, "reason": "uninitialized"}
	if not _valid_cell(cell):
		return {"supported": false, "reason": "invalid_cell"}
	if not Shape.count(at_ms, 0, SimInventory.MAX_COUNT):
		return {"supported": false, "reason": "invalid_time"}
	var key: String = _key(cell)
	var energy: int = int(cells.get(key, {}).get("energy", 0))
	if at_ms == last_ms:
		return {"supported": true, "value": current_tenths(cell)}
	if _geometry_dirty:
		# Initial empty heat remains empty under every possible geometry.
		return {"supported": true, "value": 0} if cells.is_empty() and at_ms >= last_ms else {"supported": false, "reason": "geometry_unresolved"}
	if at_ms < segment_started_ms:
		return {"supported": false, "reason": "history_unavailable"}
	if at_ms > next_boundary_ms():
		return {"supported": false, "reason": "beyond_boundary"}
	if not cells.has(key):
		return {"supported": true, "value": 0}
	var dt: int = at_ms - last_ms
	for flow: Dictionary in flows:
		if str(flow.from) == key:
			energy -= int(flow.rate) * dt
		elif str(flow.to) == key:
			energy += int(flow.rate) * dt
	return {"supported": true, "value": _offset(energy, cell, at_ms)} if energy >= 0 and energy <= int(definitions.max_cell_energy) else {"supported": false, "reason": "inconsistent_projection"}


func mark_sample(now: int) -> bool:
	if definitions.is_empty() or now < activation_ms or posmod(now, int(definitions.sample_ms)) != 0 or now < last_sample_ms or not settle_at_ms(now):
		return false
	# Repeating a sample at the same timestamp must not replace history after
	# a later semantic event at that timestamp. Scheduler orders this once.
	if now == last_sample_ms:
		return true
	last_sample_ms = now
	last_sample_mode = "absolute"
	last_sample_cells = {}
	for key: String in _sorted(cells):
		last_sample_cells[key] = int(cells[key].energy)
	last_sample_input = input_energy
	last_sample_loss = loss_energy
	last_sample_ambient_in = ambient_in
	return true


func sample_tenths(cell: Vector2i, at_ms: int) -> int:
	if definitions.is_empty() or at_ms != last_sample_ms or not _valid_cell(cell) or not last_sample_cells.has(_key(cell)):
		return 0
	var energy: int = int(last_sample_cells[_key(cell)])
	return _tenths(energy) if last_sample_mode == "legacy_excess" else _offset(energy, cell, at_ms)


func maximum_offset_tenths() -> int:
	return int(definitions.reference_tenths) + _tenths(int(definitions.max_cell_energy)) + 10000


func minimum_offset_tenths() -> int:
	return int(definitions.reference_tenths) - 10000


func has_visible_offsets(historical: bool = false) -> bool:
	var state: Dictionary = last_sample_cells if historical else cells
	for key: String in state:
		var point := Vector2i(int(cells[key].cell[0]), int(cells[key].cell[1]))
		if (sample_tenths(point, last_sample_ms) if historical else current_tenths(point)) != 0:
			return true
	return false


func to_dict() -> Dictionary:
	if _geometry_dirty:
		_freeze()
	return {"version": VERSION, "rules_version": VERSION, "activation_ms": activation_ms,
		"model_started_ms": model_started_ms, "last_ms": last_ms, "segment_started_ms": segment_started_ms,
		"cells": cells.duplicate(true), "flows": flows.duplicate(true), "input_energy": input_energy,
		"ambient_in": ambient_in, "loss_energy": loss_energy, "receipts": receipts.duplicate(true),
		"last_sample_ms": last_sample_ms, "last_sample_cells": last_sample_cells.duplicate(true),
		"last_sample_input": last_sample_input, "last_sample_loss": last_sample_loss,
		"last_sample_ambient_in": last_sample_ambient_in, "last_sample_mode": last_sample_mode,
		"legacy_limits": legacy_limits.duplicate(true)}


func _assign(data: Dictionary) -> void:
	for field: String in ["activation_ms", "model_started_ms", "last_ms", "segment_started_ms", "input_energy", "ambient_in", "loss_energy", "last_sample_ms", "last_sample_input", "last_sample_loss", "last_sample_ambient_in"]:
		set(field, int(data[field]))
	last_sample_mode = str(data.last_sample_mode)
	cells = data.cells.duplicate(true)
	for row: Dictionary in cells.values():
		for field: String in ["energy", "allocated_ms", "baseline_energy"]:
			row[field] = int(row[field])
		row.cell = [int(row.cell[0]), int(row.cell[1])]
	flows.clear()
	for flow: Dictionary in data.flows:
		flows.append({"from": str(flow.from), "to": str(flow.to), "rate": int(flow.rate)})
	receipts = {}
	for key: String in data.receipts:
		receipts[key] = _normalized_receipt(data.receipts[key])
	last_sample_cells = {}
	for key: String in data.last_sample_cells:
		last_sample_cells[key] = int(data.last_sample_cells[key])
	legacy_limits = data.legacy_limits.duplicate(true)
	_geometry_dirty = false
	_frozen_boundary_ms = _boundary_at(last_ms, cells, flows)


func restore(data: Variant) -> bool:
	if not SimThermalSchema.validate(self, data):
		return false
	_assign(data)
	return true


func import_v1(old: RefCounted, context: RefCounted) -> Dictionary:
	var checker := Legacy.new()
	if not checker.configure(context, old.definitions):
		return {}
	checker.set_geometry(context.construction.thermal_roofed, context.construction.thermal_barrier)
	if not checker.restore(old.to_dict()):
		return {}
	var prior: Dictionary = checker.to_dict()
	var result: Dictionary = empty_state(int(context.elapsed_ms))
	result.activation_ms = int(prior.activation_ms)
	result.input_energy = int(prior.input_energy)
	result.loss_energy = int(prior.loss_energy)
	result.receipts = prior.receipts.duplicate(true)
	result.last_sample_ms = int(prior.last_sample_ms)
	result.last_sample_mode = "legacy_excess"
	result.last_sample_cells = prior.last_sample_cells.duplicate(true)
	result.last_sample_input = int(prior.last_sample_input)
	result.last_sample_loss = int(prior.last_sample_loss)
	result.legacy_limits = {"at_ms": int(context.elapsed_ms), "input_energy": int(prior.input_energy), "cells": _sorted(prior.cells)}
	for key: String in prior.cells:
		var point := Vector2i(int(prior.cells[key].cell[0]), int(prior.cells[key].cell[1]))
		var base: int = _baseline(point, int(context.elapsed_ms))
		var energy: int = base + int(prior.cells[key].energy)
		if base < 0 or energy > int(definitions.max_cell_energy) or base > MAX_INTEGER - int(result.ambient_in) - int(result.input_energy):
			return {}
		result.ambient_in = int(result.ambient_in) + base
		result.cells[key] = {"cell": [point.x, point.y], "energy": energy, "allocated_ms": int(context.elapsed_ms), "baseline_energy": base}
	result.flows = _build_flows(result.cells, int(context.elapsed_ms))
	return result if SimThermalSchema.validate(self, result) else {}


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
	flows = _build_flows(cells, last_ms)
	segment_started_ms = last_ms
	_frozen_boundary_ms = _boundary_at(last_ms, cells, flows)
	_geometry_dirty = false


func _build_flows(state: Dictionary, at_ms: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# Default region curves are spatially constant within a region. Providers
	# injected for per-cell rules retain their original call sequence instead.
	var context: Dictionary = {} if state.is_empty() or _background_query.is_valid() else _default_background_context()
	var by_region: Dictionary = {}
	for key: String in _sorted(state):
		var row: Dictionary = state[key]
		var point := Vector2i(int(row.cell[0]), int(row.cell[1]))
		var exchange: Array[int] = [0, 0]
		var roof: bool = _roofed.is_valid() and bool(_roofed.call(point))
		_bath_rates(exchange, int(row.energy) - _baseline_for_pass(point, at_ms, context, by_region), int(definitions.bath_loss.roofed if roof else definitions.bath_loss.unroofed))
		for side: Vector2i in SIDES:
			var neighbor: Vector2i = point + side
			var adjacent: String = _key(neighbor)
			var coefficient: int = mini(_conductance(point), _conductance(neighbor))
			if not state.has(adjacent):
				_bath_rates(exchange, int(row.energy) - _baseline_for_pass(neighbor, at_ms, context, by_region), coefficient)
			elif key < adjacent:
				var difference: int = int(row.energy) - int(state[adjacent].energy)
				var rate: int = _rate(absi(difference), coefficient)
				if rate > 0:
					result.append({"from": key if difference > 0 else adjacent, "to": adjacent if difference > 0 else key, "rate": rate})
		if exchange[0] > 0:
			result.append({"from": "", "to": key, "rate": exchange[0]})
		if exchange[1] > 0:
			result.append({"from": key, "to": "", "rate": exchange[1]})
	return result


func _bath_rates(rates: Array[int], difference: int, coefficient: int) -> void:
	if difference != 0:
		rates[1 if difference > 0 else 0] += _rate(absi(difference), coefficient)


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
	var divisor: int = int(definitions.coefficient_scale) * int(definitions.step_ms)
	return (energy / divisor) * coefficient + (energy % divisor) * coefficient / divisor


func _integrate(dt: int) -> void:
	for flow: Dictionary in flows:
		var amount: int = int(flow.rate) * dt
		if str(flow.from).is_empty():
			ambient_in += amount
		else:
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
