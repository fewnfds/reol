class_name SimThermalCellStore
extends RefCounted
## One owned Q per fine row or per symmetric orbit. A materialized dictionary
## is a transient projection, not an additional live field or save format.

const MAX_INTEGER: int = 9007199254740991
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]
const ORBIT_COUNTS: Array[int] = [1, 4, 4, 4, 8, 4]

## replace_fine and allocate transfer already-normalized, owned rows here.
var fine: Dictionary = {}
## Each patch owns six Qs; its per-orbit rates and the coordinate index are
## derived metadata, never a second field or persisted balance.
var _patches: Dictionary = {}
var _index: Dictionary = {}
var _frozen_valid: bool = false
## Each entry references its one original fine row and two derived rates.
var _fine_plan: Array[Dictionary] = []
var _bath_in_rate: int = 0
var _bath_out_rate: int = 0


func replace_fine(rows: Dictionary) -> void:
	_invalidate_frozen()
	fine = rows
	_patches.clear()
	_index.clear()


func count() -> int:
	return fine.size() + _patches.size() * 25


func slot_count() -> int:
	return fine.size() + _patches.size() * 6


func keys() -> Array[String]:
	# Membership is derived metadata, so enumerating coordinates needs no Q
	# projection and does not expand the compressed field.
	var result: Array[String] = []
	for key: String in fine:
		result.append(key)
	for key: String in _index:
		result.append(key)
	return result


func has(key: String) -> bool:
	return fine.has(key) or _index.has(key)


func row(key: String) -> Dictionary:
	# This internal fine reference follows the controlled-owner contract.
	# Public read-only interfaces must not expose it for external mutation.
	if fine.has(key):
		return fine[key]
	if not _index.has(key):
		return {}
	var patch: Dictionary = _patches[_index[key]]
	var center: Vector2i = patch.center
	var point: Vector2i = _point(key)
	return _row(point, int(patch.q[_orbit(point - center)]), int(patch.allocated_ms), int(patch.baseline_energy))


func energy_at(key: String, fallback: int = 0) -> int:
	if fine.has(key):
		return int(fine[key].energy)
	if not _index.has(key):
		return fallback
	var patch: Dictionary = _patches[_index[key]]
	return int(patch.q[_orbit(_point(key) - patch.center)])


func materialize() -> Dictionary:
	# Uncompressed callers may use the owned dictionary on their controlled
	# internal path. A compressed result is a detached, short-lived projection;
	# modifying it never updates the original compressed Q.
	if _patches.is_empty():
		return fine
	var result: Dictionary = fine.duplicate(true)
	for patch: Dictionary in _patches.values():
		var center: Vector2i = patch.center
		for y: int in range(-2, 3):
			for x: int in range(-2, 3):
				var offset := Vector2i(x, y)
				var point: Vector2i = center + offset
				result[_key(point)] = _row(point, int(patch.q[_orbit(offset)]), int(patch.allocated_ms), int(patch.baseline_energy))
	return result


func snapshot() -> Dictionary:
	# Exactly one detached row set for a caller that may edit or persist it.
	# materialize already owns its complete projection when patches exist.
	return fine.duplicate(true) if _patches.is_empty() else materialize()


func allocate(key: String, row: Dictionary) -> void:
	# The owner has already validated canonical coordinates and non-duplication.
	assert(not has(key), "A thermal cell must have only one allocation")
	if has(key):
		return
	_invalidate_frozen()
	fine[key] = row


func add_energy(key: String, amount: int) -> void:
	# The owner preflights capacity and the addition. A single-cell mutation
	# cannot leave the other orbit members sharing its new Q.
	assert(has(key), "The thermal cell must already be allocated")
	if not has(key):
		return
	_invalidate_frozen()
	if _index.has(key):
		_expand_patch(str(_index[key]))
	fine[key].energy = int(fine[key].energy) + amount


func expand_all() -> void:
	_invalidate_frozen()
	for patch_id: String in _patches.keys():
		_expand_patch(patch_id)


func compact(centers: Array[Vector2i], flows: Array, max_q: int) -> void:
	# The owner supplies current climate, geometry, receipt and device eligibility
	# every segment. Retain an existing unique-Q patch only after checking that
	# eligibility, its current halo and every member's separate frozen rates.
	_invalidate_frozen()
	if max_q < 0 or max_q > MAX_INTEGER:
		expand_all()
		return
	var totals: Dictionary = _flow_totals(flows)
	if not bool(totals.ok):
		expand_all()
		return
	var eligible: Dictionary = {}
	for center: Vector2i in centers:
		eligible[_key(center)] = true
	for patch_id: String in _patches.keys():
		if not eligible.has(patch_id) or not _refresh_patch(patch_id, totals, max_q):
			_expand_patch(patch_id)
	for center: Vector2i in centers:
		if not _patches.has(_key(center)):
			_compact_patch(center, totals, max_q)
	if not _patches.is_empty():
		_compile_frozen(totals)


func frozen_ready() -> bool:
	return _frozen_valid and not _patches.is_empty()


func ambient_in_rate() -> int:
	return _bath_in_rate if frozen_ready() else 0


func ambient_out_rate() -> int:
	return _bath_out_rate if frozen_ready() else 0


func can_advance(dt: int, max_q: int) -> bool:
	# The heat owner also verifies segment time and cumulative bath ledgers.
	# Incoming and outgoing budgets each refer to the old Q, never their net.
	if not frozen_ready() or dt < 0 or dt > MAX_INTEGER or max_q < 0 or max_q > MAX_INTEGER:
		return false
	if not _product_fits(_bath_in_rate, dt, MAX_INTEGER) or not _product_fits(_bath_out_rate, dt, MAX_INTEGER):
		return false
	for entry: Dictionary in _fine_plan:
		var row: Dictionary = entry.row
		if not row.get("energy") is int:
			return false
		var energy: int = row.energy
		if not _cell_can_advance(energy, int(entry.incoming), int(entry.outgoing), dt, max_q):
			return false
	for patch: Dictionary in _patches.values():
		for orbit: int in range(6):
			if not _cell_can_advance(int(patch.q[orbit]), int(patch.in_rates[orbit]), int(patch.out_rates[orbit]), dt, max_q):
				return false
	return true


func advance(dt: int, max_q: int) -> bool:
	# A failed preflight leaves every original row and patch untouched. Rates
	# remain valid for later subdivisions of the same frozen segment.
	if not can_advance(dt, max_q):
		return false
	if dt == 0:
		return true
	for entry: Dictionary in _fine_plan:
		var row: Dictionary = entry.row
		row.energy = int(row.energy) - int(entry.outgoing) * dt + int(entry.incoming) * dt
	for patch: Dictionary in _patches.values():
		var values: Array = patch.q
		for orbit: int in range(6):
			values[orbit] = int(values[orbit]) - int(patch.out_rates[orbit]) * dt + int(patch.in_rates[orbit]) * dt
	return true


func apply_deltas(deltas: Dictionary, max_q: int) -> bool:
	# Preflight all keys and results before writing or expanding any patch.
	# Missing members mean a zero delta, not an implicit group-wide change.
	# Successful external writes invalidate the derived segment plan. Refusal
	# preserves both the accepted representation and its still-valid rates.
	if max_q < 0 or max_q > MAX_INTEGER:
		return false
	var plans: Dictionary = {}
	for key: Variant in deltas:
		if not key is String or not deltas[key] is int or not has(key):
			return false
		var old_q: int = energy_at(key)
		var delta: int = deltas[key]
		if old_q < 0 or old_q > max_q or delta < -old_q or delta > max_q - old_q:
			return false
		if not _index.has(key):
			continue
		var patch_id: String = _index[key]
		var patch: Dictionary = _patches[patch_id]
		var orbit: int = _orbit(_point(key) - patch.center)
		var patch_plan: Dictionary = plans.get(patch_id, {})
		var group: Dictionary = patch_plan.get(orbit, {"delta": delta, "count": 0, "equal": true})
		group.equal = bool(group.equal) and int(group.delta) == delta
		group.count = int(group.count) + 1
		patch_plan[orbit] = group
		plans[patch_id] = patch_plan

	_invalidate_frozen()
	for patch_id: String in plans:
		var patch_plan: Dictionary = plans[patch_id]
		var expand: bool = false
		for orbit: int in patch_plan:
			var group: Dictionary = patch_plan[orbit]
			if not bool(group.equal) or (int(group.delta) != 0 and int(group.count) != ORBIT_COUNTS[orbit]):
				expand = true
				break
		if expand:
			_expand_patch(patch_id)
			continue
		var patch: Dictionary = _patches[patch_id]
		var values: Array = patch.q
		for orbit: int in patch_plan:
			values[orbit] = int(values[orbit]) + int(patch_plan[orbit].delta)

	for key: String in deltas:
		if fine.has(key):
			fine[key].energy = int(fine[key].energy) + int(deltas[key])
	return true


func _compact_patch(center: Vector2i, totals: Dictionary, max_q: int) -> void:
	var values: Array[int] = [-1, -1, -1, -1, -1, -1]
	var incoming: Array[int] = [-1, -1, -1, -1, -1, -1]
	var outgoing: Array[int] = [-1, -1, -1, -1, -1, -1]
	var allocated_ms: int = -1
	var baseline: int = -1
	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			var offset := Vector2i(x, y)
			var point: Vector2i = center + offset
			var key: String = _key(point)
			var row: Variant = fine.get(key)
			if not _valid_row(row, point, max_q):
				return
			if allocated_ms < 0:
				allocated_ms = int(row.allocated_ms)
				baseline = int(row.baseline_energy)
			elif int(row.allocated_ms) != allocated_ms or int(row.baseline_energy) != baseline:
				return
			var orbit: int = _orbit(offset)
			var energy: int = int(row.energy)
			var in_rate: int = int(totals.incoming.get(key, 0))
			var out_rate: int = int(totals.outgoing.get(key, 0))
			if values[orbit] < 0:
				values[orbit] = energy
				incoming[orbit] = in_rate
				outgoing[orbit] = out_rate
			elif values[orbit] != energy or incoming[orbit] != in_rate or outgoing[orbit] != out_rate:
				return
			for side: Vector2i in SIDES:
				var neighbor: Vector2i = offset + side
				if (absi(neighbor.x) > 2 or absi(neighbor.y) > 2) and has(_key(center + neighbor)):
					return

	var patch_id: String = _key(center)
	_patches[patch_id] = {"center": center, "allocated_ms": allocated_ms,
		"baseline_energy": baseline, "q": values, "in_rates": incoming, "out_rates": outgoing}
	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			var key: String = _key(center + Vector2i(x, y))
			fine.erase(key)
			_index[key] = patch_id


func _refresh_patch(patch_id: String, totals: Dictionary, max_q: int) -> bool:
	var patch: Dictionary = _patches[patch_id]
	var center: Vector2i = patch.center
	# Q remains owned by the patch; do not expand 25 rows to check it.
	for energy: Variant in patch.q:
		if not energy is int or energy < 0 or energy > max_q:
			return false
	# A smaller new maximum must not retain metadata the original fine-row
	# admission would have rejected.
	if int(patch.baseline_energy) > max_q:
		return false
	for offset: int in range(-2, 3):
		if has(_key(center + Vector2i(offset, -3))) or has(_key(center + Vector2i(offset, 3))) or has(_key(center + Vector2i(-3, offset))) or has(_key(center + Vector2i(3, offset))):
			return false
	var incoming: Array[int] = [-1, -1, -1, -1, -1, -1]
	var outgoing: Array[int] = [-1, -1, -1, -1, -1, -1]
	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			var offset := Vector2i(x, y)
			var key: String = _key(center + offset)
			var orbit: int = _orbit(offset)
			var in_rate: int = int(totals.incoming.get(key, 0))
			var out_rate: int = int(totals.outgoing.get(key, 0))
			if incoming[orbit] < 0:
				incoming[orbit] = in_rate
				outgoing[orbit] = out_rate
			elif incoming[orbit] != in_rate or outgoing[orbit] != out_rate:
				return false
	patch.in_rates = incoming
	patch.out_rates = outgoing
	return true


func _flow_totals(flows: Array) -> Dictionary:
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}
	var seen: Dictionary = {}
	var total: int = 0
	var bath_in: int = 0
	var bath_out: int = 0
	for flow: Variant in flows:
		if not flow is Dictionary or flow.size() != 3 or not flow.get("from") is String or not flow.get("to") is String or not flow.get("rate") is int:
			return {"ok": false}
		var origin: String = flow.from
		var target: String = flow.to
		var rate: int = flow.rate
		# Unknown/device endpoints are not eligible, including remote ones.
		if origin == target or rate <= 0 or rate > MAX_INTEGER or total > MAX_INTEGER - rate or (not origin.is_empty() and not has(origin)) or (not target.is_empty() and not has(target)):
			return {"ok": false}
		var destinations: Dictionary = seen.get(origin, {})
		if destinations.has(target):
			return {"ok": false}
		destinations[target] = true
		seen[origin] = destinations
		total += rate
		if origin.is_empty():
			bath_in += rate
		else:
			outgoing[origin] = int(outgoing.get(origin, 0)) + rate
		if target.is_empty():
			bath_out += rate
		else:
			incoming[target] = int(incoming.get(target, 0)) + rate
	return {"ok": true, "incoming": incoming, "outgoing": outgoing,
		"bath_in": bath_in, "bath_out": bath_out}


func _compile_frozen(totals: Dictionary) -> void:
	_fine_plan.clear()
	for key: String in fine:
		_fine_plan.append({"row": fine[key], "incoming": int(totals.incoming.get(key, 0)),
			"outgoing": int(totals.outgoing.get(key, 0))})
	_bath_in_rate = int(totals.bath_in)
	_bath_out_rate = int(totals.bath_out)
	_frozen_valid = true


func _invalidate_frozen() -> void:
	_frozen_valid = false
	_fine_plan.clear()
	_bath_in_rate = 0
	_bath_out_rate = 0


static func _cell_can_advance(energy: int, incoming: int, outgoing: int, dt: int, max_q: int) -> bool:
	return energy >= 0 and energy <= max_q and _product_fits(outgoing, dt, energy) and _product_fits(incoming, dt, max_q - energy)


static func _product_fits(rate: int, dt: int, budget: int) -> bool:
	if rate == 0 or dt == 0:
		return true
	@warning_ignore("integer_division")
	return dt <= budget / rate


func _expand_patch(patch_id: String) -> void:
	var patch: Dictionary = _patches[patch_id]
	var center: Vector2i = patch.center
	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			var offset := Vector2i(x, y)
			var point: Vector2i = center + offset
			var key: String = _key(point)
			fine[key] = _row(point, int(patch.q[_orbit(offset)]), int(patch.allocated_ms), int(patch.baseline_energy))
			_index.erase(key)
	_patches.erase(patch_id)


static func _valid_row(row: Variant, point: Vector2i, max_q: int) -> bool:
	if not row is Dictionary or row.size() != 4 or not row.get("cell") is Array or row.cell.size() != 2 or not row.cell[0] is int or not row.cell[1] is int or not row.get("energy") is int or not row.get("allocated_ms") is int or not row.get("baseline_energy") is int:
		return false
	return int(row.cell[0]) == point.x and int(row.cell[1]) == point.y and int(row.energy) >= 0 and int(row.energy) <= max_q and int(row.allocated_ms) >= 0 and int(row.allocated_ms) <= MAX_INTEGER and int(row.baseline_energy) >= 0 and int(row.baseline_energy) <= max_q


static func _orbit(offset: Vector2i) -> int:
	var a: int = mini(absi(offset.x), absi(offset.y))
	var b: int = maxi(absi(offset.x), absi(offset.y))
	if a == 0:
		return 0 if b == 0 else (1 if b == 1 else 3)
	if a == 1:
		return 2 if b == 1 else 4
	return 5


static func _key(point: Vector2i) -> String:
	return "%d,%d" % [point.x, point.y]


static func _point(key: String) -> Vector2i:
	return Vector2i(key.get_slice(",", 0).to_int(), key.get_slice(",", 1).to_int())


static func _row(point: Vector2i, energy: int, allocated_ms: int, baseline: int) -> Dictionary:
	return {"cell": [point.x, point.y], "energy": energy,
		"allocated_ms": allocated_ms, "baseline_energy": baseline}
