class_name SimLocalHeat
extends RefCounted
## Fixed-reference nonnegative energy, frozen integer fluxes and explicit bath
## accounting. One physical field; rooms, recipients and views own no heat.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const Legacy = preload("res://scripts/persistence/legacy_heat_v1.gd")
const TransferBudget = preload("res://scripts/sim/thermal_transfer_budget.gd")
const FrozenGroups = preload("res://scripts/sim/thermal_frozen_groups.gd")
const CellStore = preload("res://scripts/sim/thermal_cell_store.gd")
const VERSION: int = 3
const DEVICE_PREFIX: String = "@artifact/"
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]
const MAX_INTEGER: int = 9007199254740991
const GROUP_MIN_CELLS: int = 64
var definitions: Dictionary = {}
var activation_ms: int = 0
var model_started_ms: int = 0
var last_ms: int = 0
var segment_started_ms: int = 0
var _cell_store := CellStore.new()
## Detached diagnostics only. Rules mutate the one cell store, never this view.
var cells: Dictionary:
	get:
		var projected: Dictionary = _cell_store.materialize().duplicate(true)
		for row: Dictionary in projected.values():
			row.make_read_only()
		projected.make_read_only()
		return projected
var flows: Array[Dictionary] = []
var input_energy: int = 0
var continuous_input: int = 0
var absorbed_energy: int = 0
var device_input: Dictionary = {}
var device_absorbed: Dictionary = {}
var device_switches: Dictionary = {}
var ambient_in: int = 0
var loss_energy: int = 0
var receipts: Dictionary = {}
var last_sample_ms: int = 0
var last_sample_cells: Dictionary = {}
var last_sample_input: int = 0
var last_sample_loss: int = 0
var last_sample_ambient_in: int = 0
var last_sample_continuous_input: int = 0
var last_sample_absorbed: int = 0
var last_sample_mode: String = "absolute"
var legacy_limits: Dictionary = {}
var _owner: WeakRef
var _roofed: Callable
var _barrier: Callable
var _reuse_conductance_within_pass: bool = false
var _receipt_validator: Callable
var _expected_actions: Callable
var _geometry_dirty: bool = false
var _background_query: Callable
var _background_boundary: Callable
var _frozen_boundary_ms: int = MAX_INTEGER
var _frozen_groups: SimThermalFrozenGroups
## Spatial eligibility only; no Q, clock or frozen slopes. Original mutation
## boundaries invalidate it before membership or geometry can change.
var _compression_sites: Array[Vector2i] = []
var _compression_sites_dirty: bool = true
## Derived once per accepted freeze/restore, never serialized or a Q balance.
var _emission_rates: Dictionary = {}
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
		"continuous_input": 0, "absorbed_energy": 0, "device_input": {}, "device_absorbed": {},
		"device_switches": {}, "segment_until_ms": MAX_INTEGER,
		"receipts": {}, "last_sample_ms": at_ms, "last_sample_cells": {},
		"last_sample_input": 0, "last_sample_loss": 0, "last_sample_ambient_in": 0,
		"last_sample_mode": "absolute", "legacy_limits": {},
		"last_sample_continuous_input": 0, "last_sample_absorbed": 0}


func set_background(query: Callable, boundary: Callable) -> void:
	_compression_sites_dirty = true
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


func set_geometry(roofed: Callable, barrier: Callable, reuse_within_pass: bool = false) -> void:
	_compression_sites_dirty = true
	# Opt-in promises that geometry stays stable during one synchronous pass.
	_roofed = roofed
	_barrier = barrier
	_reuse_conductance_within_pass = reuse_within_pass
	_geometry_dirty = true


func set_source_validator(receipt_validator: Callable, expected_actions: Callable) -> void:
	_receipt_validator = receipt_validator
	_expected_actions = expected_actions


func can_change_topology(now: int, changed_cells: Array[Vector2i]) -> bool:
	# Construction calls this before costs or structures change, at its already
	# settled physical instant. A query cannot consume time or dirty geometry.
	# The complete footprint includes collateral roof removal; future bounded
	# representations can refuse expansion here, before any original costs.
	if definitions.is_empty() or now != last_ms or changed_cells.is_empty():
		return false
	for cell: Vector2i in changed_cells:
		if not _valid_cell(cell):
			return false
	return can_settle_at_ms(now)


func before_topology_change(now: int) -> bool:
	# Repeated hooks in a single demolition/collapse transaction are harmless.
	if not _geometry_dirty:
		if not settle_at_ms(now):
			return false
	elif now > last_ms:
		if not settle_at_ms(now):
			return false
	elif now < last_ms:
		return false
	_cell_store.expand_all()
	_frozen_groups = null
	_compression_sites_dirty = true
	_geometry_dirty = true
	return true


func after_topology_change(now: int) -> void:
	if now != last_ms:
		return
	_compression_sites_dirty = true
	_freeze()


func refresh_geometry() -> void:
	_compression_sites_dirty = true
	_freeze()


func _boundary_at(at_ms: int, state: Dictionary, active_flows: Array, object_state: Dictionary = {}) -> int:
	if state.is_empty() or at_ms == MAX_INTEGER:
		return MAX_INTEGER
	var context: Dictionary = {} if _background_boundary.is_valid() else _default_background_context()
	var by_region: Dictionary = {}
	var next: int = MAX_INTEGER
	if not active_flows.is_empty():
		var distance: int = int(definitions.step_ms) - posmod(at_ms, int(definitions.step_ms))
		var span: int = 0
		if _has_device_flows(active_flows):
			var supplied: Dictionary = _device_objects() if object_state.is_empty() else object_state
			var result: Dictionary = TransferBudget.span(active_flows, _transfer_capacities(state, supplied), distance)
			span = int(result.duration_ms) if bool(result.ok) else 0
		else:
			span = TransferBudget.field_span(active_flows, state, int(definitions.max_cell_energy), distance)
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


func device_emission_rates(at_ms: int) -> Dictionary:
	# Read-only current outgoing slopes; callers cannot settle or repair heat.
	if definitions.is_empty() or at_ms != last_ms or (_geometry_dirty and (_cell_store.count() != 0 or not flows.is_empty())) or (_cell_store.count() != 0 and _frozen_boundary_ms <= last_ms):
		return {"supported": false, "reason": "unsettled_heat"}
	return {"supported": true, "rates": _emission_rates}


func _rebuild_emission_rates() -> void:
	_emission_rates = {}
	for flow: Dictionary in flows:
		var id: String = _device_id(str(flow.from))
		if not id.is_empty():
			_emission_rates[id] = int(_emission_rates.get(id, 0)) + int(flow.rate)
	_emission_rates.make_read_only()


func _device_objects() -> Dictionary:
	var result: Dictionary = {}
	var artifacts: Variant = world.get("artifacts") if world != null else null
	if artifacts == null or not artifacts.get("objects") is Dictionary or not artifacts.get("definitions") is Dictionary:
		return result
	for id: String in artifacts.objects:
		var item: Dictionary = artifacts.objects[id]
		var rule: Dictionary = artifacts.definitions.types.get(item.definition, {})
		if rule.get("capabilities", []).has("thermal_exchange"):
			result[id] = item
	return result


func _device_definition(id: String) -> Dictionary:
	var artifacts: Variant = world.get("artifacts") if world != null else null
	if artifacts == null or not artifacts.get("objects") is Dictionary or not artifacts.objects.has(id):
		return {}
	return artifacts.definitions.types.get(artifacts.objects[id].definition, {})


static func _device_id(endpoint: String) -> String:
	return endpoint.trim_prefix(DEVICE_PREFIX) if endpoint.begins_with(DEVICE_PREFIX) else ""


static func _has_device_flows(active_flows: Array) -> bool:
	for flow: Dictionary in active_flows:
		if not _device_id(str(flow.from)).is_empty() or not _device_id(str(flow.to)).is_empty():
			return true
	return false


func _transfer_capacities(state: Dictionary, objects: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in state:
		var energy: int = int(state[key].energy)
		result[key] = {"out": energy, "in": int(definitions.max_cell_energy) - energy}
	for id: String in objects:
		var item: Dictionary = objects[id]
		if not bool(item.enabled):
			continue
		var thermal: Dictionary = _device_definition(id).thermal
		result[DEVICE_PREFIX + id] = {"out": int(item.stored_q) if thermal.mode == "emit" else 0,
			"in": int(thermal.capacity_q) - int(item.stored_q) if thermal.mode == "absorb" else 0}
	return result


func _device_cell(item: Dictionary) -> Vector2i:
	var regions: Variant = world.get("regions") if world != null else null
	if not regions is Dictionary or not regions.has(item.region):
		return Vector2i(-1, -1)
	var places: Dictionary = regions[item.region].places
	if not places.has(item.container):
		return Vector2i(-1, -1)
	return Vector2i(int(places[item.container].cell[0]), int(places[item.container].cell[1]))


func _logged_enabled(id: String) -> bool:
	var latest: int = -1
	var enabled: bool = false
	for receipt: Dictionary in device_switches.values():
		if receipt.object == id and int(receipt.at_ms) > latest:
			latest = int(receipt.at_ms)
			enabled = bool(receipt.enabled)
	return enabled


func _switch_plan(id: String, enabled: bool) -> Dictionary:
	var now: int = int(world.get("elapsed_ms"))
	var objects: Dictionary = _device_objects()
	if definitions.is_empty() or last_ms != now or _geometry_dirty or not objects.has(id) or _logged_enabled(id) == enabled:
		return {"ok": false}
	var item: Dictionary = objects[id]
	var point: Vector2i = _device_cell(item)
	if not _valid_cell(point):
		return {"ok": false}
	var planned: Dictionary = _cell_store.materialize().duplicate(true)
	var baseline_sum: int = 0
	if enabled:
		for cell: Vector2i in _patch(point):
			var key: String = _key(cell)
			if planned.has(key):
				continue
			var energy: int = _baseline(cell, now)
			if energy < 0 or energy > int(definitions.max_cell_energy) or baseline_sum > MAX_INTEGER - energy:
				return {"ok": false}
			baseline_sum += energy
			planned[key] = {"cell": [cell.x, cell.y], "energy": energy, "allocated_ms": now, "baseline_energy": energy}
	if planned.size() > int(definitions.max_cells) or baseline_sum > int(definitions.max_exchange_energy) - ambient_in or baseline_sum > MAX_INTEGER - input_energy - continuous_input - ambient_in:
		return {"ok": false}
	var proposed: Dictionary = objects.duplicate(true)
	proposed[id].enabled = enabled
	var flow_plan: Dictionary = _flow_plan(planned, now, proposed)
	if not bool(flow_plan.ok):
		return {"ok": false}
	return {"ok": true, "cells": planned, "ambient": baseline_sum}


func can_switch_device(id: String, enabled: bool) -> bool:
	return world != null and bool(_switch_plan(id, enabled).ok)


func switch_device(receipt: Dictionary) -> bool:
	if not Shape.keys(receipt, ["action", "actor", "object", "at_ms", "region", "container", "cell", "enabled"]) or not receipt.enabled is bool or not SimInventory._nonempty(receipt.action) or not SimInventory._nonempty(receipt.actor) or not SimInventory._nonempty(receipt.object) or not receipt.region is String or not receipt.container is String or not _cell_array(receipt.cell) or receipt.at_ms != last_ms or device_switches.has(receipt.action):
		return false
	var objects: Dictionary = _device_objects()
	if not objects.has(receipt.object):
		return false
	var item: Dictionary = objects[receipt.object]
	if bool(item.enabled) != bool(receipt.enabled) or item.region != receipt.region or item.container != receipt.container or _device_cell(item) != Vector2i(int(receipt.cell[0]), int(receipt.cell[1])):
		return false
	var plan: Dictionary = _switch_plan(str(receipt.object), bool(receipt.enabled))
	if not bool(plan.ok):
		return false
	# Artifact caller has set its proposed enabled flag and will immediately
	# append the original action record; no callbacks occur in this commit.
	_compression_sites_dirty = true
	_cell_store.replace_fine(plan.cells)
	ambient_in += int(plan.ambient)
	device_switches[str(receipt.action)] = {"action": str(receipt.action), "actor": str(receipt.actor),
		"object": str(receipt.object), "at_ms": int(receipt.at_ms), "region": str(receipt.region), "container": str(receipt.container),
		"cell": [int(receipt.cell[0]), int(receipt.cell[1])], "enabled": bool(receipt.enabled)}
	_freeze()
	return true


func can_settle_at_ms(now: int) -> bool:
	# Preflight one frozen segment before the regional executor advances bodies.
	if definitions.is_empty() or not Shape.count(now, last_ms, MAX_INTEGER):
		return false
	if _cell_store.count() == 0:
		return true
	if _geometry_dirty or now > next_boundary_ms():
		return false
	var dt: int = now - last_ms
	if _cell_store.frozen_ready():
		if not _cell_store.can_advance(dt, int(definitions.max_cell_energy)):
			return false
		return _ledger_can_accept(_cell_store.ambient_in_rate() * dt, _cell_store.ambient_out_rate() * dt, 0, 0)
	if _frozen_groups != null and _frozen_groups.can_settle(dt):
		return _ledger_can_accept(int(_frozen_groups.ambient_in_rate) * dt,
			int(_frozen_groups.ambient_out_rate) * dt, 0, 0)
	var incoming: int = 0
	var outgoing: int = 0
	var emitted: int = 0
	var absorbed: int = 0
	var deltas: Dictionary = {}
	var device_deltas: Dictionary = {}
	for flow: Dictionary in flows:
		@warning_ignore("integer_division")
		var maximum_rate: int = MAX_INTEGER if dt == 0 else MAX_INTEGER / dt
		if int(flow.rate) > maximum_rate:
			return false
		var amount: int = int(flow.rate) * dt
		if str(flow.from).is_empty():
			if incoming > MAX_INTEGER - amount:
				return false
			incoming += amount
		elif not _device_id(str(flow.from)).is_empty():
			var id: String = _device_id(str(flow.from))
			if emitted > MAX_INTEGER - amount:
				return false
			emitted += amount
			device_deltas[id] = int(device_deltas.get(id, 0)) - amount
		else:
			deltas[flow.from] = int(deltas.get(flow.from, 0)) - amount
		if str(flow.to).is_empty():
			if outgoing > MAX_INTEGER - amount:
				return false
			outgoing += amount
		elif not _device_id(str(flow.to)).is_empty():
			var id: String = _device_id(str(flow.to))
			if absorbed > MAX_INTEGER - amount:
				return false
			absorbed += amount
			device_deltas[id] = int(device_deltas.get(id, 0)) + amount
		else:
			deltas[flow.to] = int(deltas.get(flow.to, 0)) + amount
	if not _ledger_can_accept(incoming, outgoing, emitted, absorbed):
		return false
	var objects: Dictionary = _device_objects() if not device_deltas.is_empty() else {}
	for id: String in device_deltas:
		if not objects.has(id) or not bool(objects[id].enabled):
			return false
		var value: int = int(objects[id].stored_q) + int(device_deltas[id])
		if value < 0 or value > int(_device_definition(id).thermal.capacity_q):
			return false
	for key: String in deltas:
		var value: int = _cell_store.energy_at(key) + int(deltas[key])
		if value < 0 or value > int(definitions.max_cell_energy):
			return false
	return true


func _ledger_can_accept(incoming: int, outgoing: int, emitted: int, absorbed: int) -> bool:
	# Both arithmetic paths retain the same cumulative source/bath limits.
	return not (emitted > int(definitions.max_total_input) - input_energy - continuous_input or incoming > int(definitions.max_exchange_energy) - ambient_in or emitted > MAX_INTEGER - input_energy - continuous_input - ambient_in or incoming > MAX_INTEGER - input_energy - continuous_input - ambient_in - emitted or outgoing > int(definitions.max_exchange_energy) - loss_energy or absorbed > MAX_INTEGER - absorbed_energy)


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
		if not _integrate(target - last_ms):
			return false
		last_ms = target
		if target == boundary or _cell_store.count() == 0:
			_freeze()
		elif flows.is_empty():
			# No slope to reconstruct: anchor at the accepted instant without
			# sampling geometry or changing the next declared climate boundary.
			segment_started_ms = last_ms
	return true


func can_deposit(cell: Vector2i, amount: int) -> bool:
	if definitions.is_empty() or not _valid_cell(cell) or not Shape.count(amount, 1, int(definitions.pulse_energy)) or input_energy + continuous_input > int(definitions.max_total_input) - amount:
		return false
	var source_q: int = _cell_store.energy_at(_key(cell)) if _cell_store.has(_key(cell)) else _baseline(cell, last_ms)
	if source_q > int(definitions.max_cell_energy) - amount:
		return false
	var added: int = 0
	var baseline_sum: int = 0
	for point: Vector2i in _patch(cell):
		if _cell_store.has(_key(point)):
			continue
		var energy: int = _baseline(point, last_ms)
		if energy < 0 or energy > int(definitions.max_cell_energy) or baseline_sum > MAX_INTEGER - energy:
			return false
		baseline_sum += energy
		added += 1
	return _cell_store.count() + added <= int(definitions.max_cells) and baseline_sum <= int(definitions.max_exchange_energy) - ambient_in and baseline_sum <= MAX_INTEGER - input_energy - continuous_input - ambient_in - amount


func deposit(source_receipt: Dictionary) -> bool:
	if not _valid_receipt(source_receipt, activation_ms) or receipts.has(source_receipt.action) or int(source_receipt.at_ms) != int(world.get("elapsed_ms")) or int(source_receipt.at_ms) < last_ms:
		return false
	var point := Vector2i(int(source_receipt.cell[0]), int(source_receipt.cell[1]))
	if not settle_at_ms(int(source_receipt.at_ms)) or not can_deposit(point, int(source_receipt.amount)):
		return false
	_compression_sites_dirty = true
	for cell: Vector2i in _patch(point):
		var key: String = _key(cell)
		if not _cell_store.has(key):
			var energy: int = _baseline(cell, last_ms)
			_cell_store.allocate(key, {"cell": [cell.x, cell.y], "energy": energy, "allocated_ms": last_ms, "baseline_energy": energy})
			ambient_in += energy
	_cell_store.add_energy(_key(point), int(source_receipt.amount))
	input_energy += int(source_receipt.amount)
	receipts[str(source_receipt.action)] = _normalized_receipt(source_receipt)
	_freeze()
	return true


func current_tenths(cell: Vector2i) -> int:
	return _offset(_cell_store.energy_at(_key(cell)), cell, last_ms) if has_cell(cell) else 0


func has_cell(cell: Vector2i) -> bool:
	return _valid_cell(cell) and _cell_store.has(_key(cell))


func cell_count() -> int:
	return _cell_store.count()


func cell_keys() -> Array[String]:
	return _cell_store.keys()


func cell_row(key: String) -> Dictionary:
	return _cell_store.row(key).duplicate(true)


func storage_summary() -> Dictionary:
	return {"logical_cells": _cell_store.count(), "q_slots": _cell_store.slot_count()}


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
	var energy: int = _cell_store.energy_at(key)
	if at_ms == last_ms:
		return {"supported": true, "value": current_tenths(cell)}
	if _geometry_dirty:
		# Initial empty heat remains empty under every possible geometry.
		return {"supported": true, "value": 0} if _cell_store.count() == 0 and at_ms >= last_ms else {"supported": false, "reason": "geometry_unresolved"}
	if at_ms < segment_started_ms:
		return {"supported": false, "reason": "history_unavailable"}
	if at_ms > next_boundary_ms():
		return {"supported": false, "reason": "beyond_boundary"}
	if not _cell_store.has(key):
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
	var keys: Array[String] = _cell_store.keys()
	keys.sort()
	for key: String in keys:
		last_sample_cells[key] = _cell_store.energy_at(key)
	last_sample_input = input_energy
	last_sample_loss = loss_energy
	last_sample_ambient_in = ambient_in
	last_sample_continuous_input = continuous_input
	last_sample_absorbed = absorbed_energy
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
	var keys: Array = last_sample_cells.keys() if historical else _cell_store.keys()
	for key: String in keys:
		# Historical keys were validated against canonical source coverage. A
		# saved observation must not borrow current allocation metadata.
		var point := Vector2i(key.get_slice(",", 0).to_int(), key.get_slice(",", 1).to_int())
		if (sample_tenths(point, last_sample_ms) if historical else current_tenths(point)) != 0:
			return true
	return false


func to_dict() -> Dictionary:
	if _geometry_dirty:
		_freeze()
	return {"version": VERSION, "rules_version": VERSION, "activation_ms": activation_ms,
		"model_started_ms": model_started_ms, "last_ms": last_ms, "segment_started_ms": segment_started_ms,
		"cells": _cell_store.materialize().duplicate(true), "flows": flows.duplicate(true), "input_energy": input_energy,
		"ambient_in": ambient_in, "loss_energy": loss_energy, "receipts": receipts.duplicate(true),
		"continuous_input": continuous_input, "absorbed_energy": absorbed_energy,
		"device_input": device_input.duplicate(true), "device_absorbed": device_absorbed.duplicate(true),
		"device_switches": device_switches.duplicate(true), "segment_until_ms": _frozen_boundary_ms,
		"last_sample_ms": last_sample_ms, "last_sample_cells": last_sample_cells.duplicate(true),
		"last_sample_input": last_sample_input, "last_sample_loss": last_sample_loss,
		"last_sample_ambient_in": last_sample_ambient_in, "last_sample_mode": last_sample_mode,
		"legacy_limits": legacy_limits.duplicate(true),
		"last_sample_continuous_input": last_sample_continuous_input, "last_sample_absorbed": last_sample_absorbed}


func _assign(data: Dictionary) -> void:
	_compression_sites_dirty = true
	for field: String in ["activation_ms", "model_started_ms", "last_ms", "segment_started_ms", "input_energy", "continuous_input", "absorbed_energy", "ambient_in", "loss_energy", "last_sample_ms", "last_sample_input", "last_sample_loss", "last_sample_ambient_in", "last_sample_continuous_input", "last_sample_absorbed"]:
		set(field, int(data[field]))
	last_sample_mode = str(data.last_sample_mode)
	var restored_cells: Dictionary = data.cells.duplicate(true)
	for row: Dictionary in restored_cells.values():
		for field: String in ["energy", "allocated_ms", "baseline_energy"]:
			row[field] = int(row[field])
		row.cell = [int(row.cell[0]), int(row.cell[1])]
	_cell_store.replace_fine(restored_cells)
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
	device_input = {}
	device_absorbed = {}
	for id: String in data.device_input:
		device_input[id] = int(data.device_input[id])
	for id: String in data.device_absorbed:
		device_absorbed[id] = int(data.device_absorbed[id])
	device_switches = data.device_switches.duplicate(true)
	_geometry_dirty = false
	_frozen_boundary_ms = int(data.segment_until_ms)
	_compile_cell_store(_cell_store.materialize())
	_rebuild_frozen_groups()
	_rebuild_emission_rates()


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
	result.segment_until_ms = _boundary_at(int(context.elapsed_ms), result.cells, result.flows)
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
	_frozen_groups = null
	var state: Dictionary = _cell_store.materialize()
	var plan: Dictionary = _flow_plan(state, last_ms)
	flows = plan.flows if bool(plan.ok) else []
	segment_started_ms = last_ms
	_frozen_boundary_ms = _boundary_at(last_ms, state, flows) if bool(plan.ok) else last_ms
	_geometry_dirty = false
	_rebuild_emission_rates()
	if bool(plan.ok):
		_compile_cell_store(state)
		_rebuild_frozen_groups()
	else:
		_frozen_groups = null


func _compile_cell_store(state: Dictionary) -> void:
	# Compression is an exact running representation, not a change to the
	# frozen clock, transfer law, source evidence or expanded v3 save format.
	var centers: Array[Vector2i] = []
	if int(definitions.source_radius) == 2 and _reuse_conductance_within_pass and not _background_query.is_valid() and not _background_boundary.is_valid():
		var device_enabled: bool = false
		for item: Dictionary in _device_objects().values():
			device_enabled = device_enabled or bool(item.enabled)
		if not device_enabled:
			if _compression_sites_dirty:
				_compression_sites = []
				var seen: Dictionary = {}
				var climate: Dictionary = world.get("_content").climate
				for receipt: Dictionary in receipts.values():
					var center := Vector2i(int(receipt.cell[0]), int(receipt.cell[1]))
					var key: String = _key(center)
					if seen.has(key):
						continue
					seen[key] = true
					if _compression_site(center, state, climate):
						_compression_sites.append(center)
				_compression_sites_dirty = false
			centers = _compression_sites
	_cell_store.compact(centers, flows, int(definitions.max_cell_energy))


func _compression_site(center: Vector2i, state: Dictionary, climate: Dictionary) -> bool:
	if not _valid_cell(center - Vector2i(3, 3)) or not _valid_cell(center + Vector2i(3, 3)):
		return false
	var region: String = SimClimateRules.region_at(climate, center)
	# A cheap membership pass rejects overlapping historical source patches
	# before asking original construction geometry about a viable candidate.
	for y: int in range(-3, 4):
		for x: int in range(-3, 4):
			var point: Vector2i = center + Vector2i(x, y)
			var inside: bool = absi(x) <= 2 and absi(y) <= 2
			if inside != state.has(_key(point)):
				return false
	for y: int in range(-3, 4):
		for x: int in range(-3, 4):
			var point: Vector2i = center + Vector2i(x, y)
			if SimClimateRules.region_at(climate, point) != region or bool(_roofed.call(point)):
				return false
			var barrier: Variant = _barrier.call(point)
			if barrier is bool:
				if barrier:
					return false
			elif barrier is String:
				if barrier not in ["open", "open_door"]:
					return false
			else:
				return false
	return true


func _rebuild_frozen_groups() -> void:
	# A derived index of this exact frozen segment, never a Q balance or clock.
	# Every source/topology change and restore rebuilds it from original rows.
	_frozen_groups = null
	# The former group kernel mutates original fine rows. A detached expanded
	# projection must never become its authority or retain a second live Q.
	if _cell_store.slot_count() != _cell_store.count():
		return
	var state: Dictionary = _cell_store.fine
	if state.size() < GROUP_MIN_CELLS:
		return
	# Q is part of every signature. Require fourfold potential reduction before
	# graph compilation; the complete in/out signature can split these buckets.
	var energies: Dictionary = {}
	@warning_ignore("integer_division")
	var distinct_limit: int = state.size() / 4
	for key: String in state:
		var row: Dictionary = state[key]
		energies[int(row.energy)] = true
		if energies.size() > distinct_limit:
			return
	if _has_device_flows(flows):
		return
	# These original rows/edges were generated here or normalized only after
	# full candidate validation. External inputs use the strict compile API.
	var grouped: SimThermalFrozenGroups = FrozenGroups.compile_field(state, flows, int(definitions.max_cell_energy))
	if grouped != null and int(grouped.group_count) * 2 <= state.size():
		_frozen_groups = grouped


func _build_flows(state: Dictionary, at_ms: int, object_state: Dictionary = {}) -> Array[Dictionary]:
	var plan: Dictionary = _flow_plan(state, at_ms, object_state)
	var result: Array[Dictionary] = []
	if bool(plan.ok):
		result.assign(plan.flows)
	return result


func _flow_plan(state: Dictionary, at_ms: int, object_state: Dictionary = {}) -> Dictionary:
	var objects: Dictionary = _device_objects() if object_state.is_empty() else object_state
	var raw: Array[Dictionary] = _candidate_flows(state, at_ms)
	var any_device: bool = false
	for id: String in _sorted(objects):
		var item: Dictionary = objects[id]
		if not bool(item.enabled):
			continue
		any_device = true
		var point: Vector2i = _device_cell(item)
		var key: String = _key(point)
		if not _valid_cell(point) or not state.has(key):
			return {"ok": false, "reason": "missing_device_cell"}
		var thermal: Dictionary = _device_definition(id).thermal
		var endpoint: String = DEVICE_PREFIX + id
		raw.append({"from": endpoint if thermal.mode == "emit" else key,
			"to": key if thermal.mode == "emit" else endpoint, "rate": int(thermal.rate_q_per_ms)})
	if not any_device:
		return {"ok": true, "flows": raw}
	return TransferBudget.freeze(raw, _transfer_capacities(state, objects), int(definitions.step_ms))


func _candidate_flows(state: Dictionary, at_ms: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# Default region curves are spatially constant within a region. Providers
	# injected for per-cell rules retain their original call sequence instead.
	var context: Dictionary = {} if state.is_empty() or _background_query.is_valid() else _default_background_context()
	var by_region: Dictionary = {}
	# A custom background query can change geometry between side queries.
	# Cache only for this pass; candidates, later freezes and rebindings share none.
	var reuse_conductance: bool = _reuse_conductance_within_pass and not _background_query.is_valid()
	var conductance_by_cell: Dictionary[Vector2i, int] = {}
	for key: String in _sorted(state):
		var row: Dictionary = state[key]
		var point := Vector2i(int(row.cell[0]), int(row.cell[1]))
		var exchange: Array[int] = [0, 0]
		var roof: bool = _roofed.is_valid() and bool(_roofed.call(point))
		_bath_rates(exchange, int(row.energy) - _baseline_for_pass(point, at_ms, context, by_region), int(definitions.bath_loss.roofed if roof else definitions.bath_loss.unroofed))
		for side: Vector2i in SIDES:
			var neighbor: Vector2i = point + side
			var adjacent: String = _key(neighbor)
			var coefficient: int
			if reuse_conductance:
				if not conductance_by_cell.has(point):
					conductance_by_cell[point] = _conductance(point)
				if not conductance_by_cell.has(neighbor):
					conductance_by_cell[neighbor] = _conductance(neighbor)
				coefficient = mini(conductance_by_cell[point], conductance_by_cell[neighbor])
			else:
				coefficient = mini(_conductance(point), _conductance(neighbor))
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


func _integrate(dt: int) -> bool:
	if _cell_store.frozen_ready():
		if not _cell_store.advance(dt, int(definitions.max_cell_energy)):
			return false
		ambient_in += _cell_store.ambient_in_rate() * dt
		loss_energy += _cell_store.ambient_out_rate() * dt
		return true
	if _frozen_groups != null and _frozen_groups.can_settle(dt):
		if not _frozen_groups.apply(dt):
			return false
		ambient_in += int(_frozen_groups.ambient_in_rate) * dt
		loss_energy += int(_frozen_groups.ambient_out_rate) * dt
		return true
	var compressed: bool = _cell_store.slot_count() != _cell_store.count()
	if compressed:
		var deltas: Dictionary = {}
		for flow: Dictionary in flows:
			var amount: int = int(flow.rate) * dt
			if not str(flow.from).is_empty() and _device_id(str(flow.from)).is_empty():
				deltas[flow.from] = int(deltas.get(flow.from, 0)) - amount
			if not str(flow.to).is_empty() and _device_id(str(flow.to)).is_empty():
				deltas[flow.to] = int(deltas.get(flow.to, 0)) + amount
		if not _cell_store.apply_deltas(deltas, int(definitions.max_cell_energy)):
			return false
	var objects: Dictionary = _device_objects() if _has_device_flows(flows) else {}
	for flow: Dictionary in flows:
		var amount: int = int(flow.rate) * dt
		if str(flow.from).is_empty():
			ambient_in += amount
		elif not _device_id(str(flow.from)).is_empty():
			var id: String = _device_id(str(flow.from))
			objects[id].stored_q = int(objects[id].stored_q) - amount
			continuous_input += amount
			device_input[id] = int(device_input.get(id, 0)) + amount
		elif not compressed:
			_cell_store.fine[flow.from].energy = int(_cell_store.fine[flow.from].energy) - amount
		if str(flow.to).is_empty():
			loss_energy += amount
		elif not _device_id(str(flow.to)).is_empty():
			var id: String = _device_id(str(flow.to))
			objects[id].stored_q = int(objects[id].stored_q) + amount
			absorbed_energy += amount
			device_absorbed[id] = int(device_absorbed.get(id, 0)) + amount
		elif not compressed:
			_cell_store.fine[flow.to].energy = int(_cell_store.fine[flow.to].energy) + amount
	return true


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
