class_name SimThermalFrozenGroups
extends RefCounted
## Exact integration plan for one already frozen, device-free transfer set.
## Original cell rows remain the sole owners of Q. A group retains their
## references, keys and separate rates, never a copied balance or a clock.
## The caller must recompile after changing membership, rates, sources,
## geometry or restored rows; grouped rows cannot be edited independently.

const MAX_INTEGER: int = 9007199254740991
const DEVICE_PREFIX: String = "@artifact/"

var _groups: Array[Dictionary] = []
var _cell_count: int = 0
var _ambient_in_rate: int = 0
var _ambient_out_rate: int = 0
var _total_rate: int = 0
var _max_q: int = 0
var _compiled: bool = false

var group_count: int:
	get: return _groups.size()
var cell_count: int:
	get: return _cell_count
var ambient_in_rate: int:
	get: return _ambient_in_rate
var ambient_out_rate: int:
	get: return _ambient_out_rate
var groups: Array[Dictionary]:
	get:
		# Detached diagnostics contain no Q and expose no writable original rows.
		var result: Array[Dictionary] = []
		for group: Dictionary in _groups:
			result.append({"cells": group.members.duplicate(), "in_rate": int(group.in_rate), "out_rate": int(group.out_rate)})
		return result


static func compile(cells: Dictionary, flows: Array, max_q: int) -> SimThermalFrozenGroups:
	if max_q < 0 or max_q > MAX_INTEGER:
		return null
	var row_buckets: Dictionary = {}
	for key: Variant in cells:
		if not key is String or str(key).is_empty() or str(key).begins_with(DEVICE_PREFIX):
			return null
		var row: Variant = cells[key]
		if not row is Dictionary or row.is_read_only() or not _integer(row.get("energy"), 0, max_q):
			return null
		# Equal dictionaries may be different original cells. Reject reference
		# aliases only; hashing narrows identity checks without owning any Q.
		var row_hash: int = hash(row)
		var bucket: Array = row_buckets.get(row_hash, [])
		for prior: Dictionary in bucket:
			if is_same(prior, row):
				return null
		bucket.append(row)
		row_buckets[row_hash] = bucket
	var seen: Dictionary = {}
	for raw: Variant in flows:
		if not _flow_shape(raw):
			return null
		var origin: String = raw.from
		var target: String = raw.to
		if origin == target or origin.begins_with(DEVICE_PREFIX) or target.begins_with(DEVICE_PREFIX):
			return null
		if (not origin.is_empty() and not cells.has(origin)) or (not target.is_empty() and not cells.has(target)):
			return null
		var destinations: Dictionary = seen.get(origin, {})
		if destinations.has(target):
			return null
		destinations[target] = true
		seen[origin] = destinations
	return _build(cells, flows, max_q)


static func compile_field(cells: Dictionary, flows: Array, max_q: int) -> SimThermalFrozenGroups:
	# Trusted entry for the thermal owner's original rows and generated flows,
	# or inputs already fully validated and normalized at their boundary.
	# The caller guarantees writable unaliased rows, nonempty String cell keys,
	# integral Q/rates in range, existing endpoints, unique directed edges and
	# no device endpoints. This entry is not an untrusted snapshot validator.
	if max_q < 0 or max_q > MAX_INTEGER:
		return null
	return _build(cells, flows, max_q)


static func _build(cells: Dictionary, flows: Array, max_q: int) -> SimThermalFrozenGroups:
	# Both entry points use exactly the same aggregation and grouping math.
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}
	var total_rate: int = 0
	var bath_in: int = 0
	var bath_out: int = 0
	for raw: Dictionary in flows:
		var origin: String = raw.from
		var target: String = raw.to
		var rate: int = int(raw.rate)
		if total_rate > MAX_INTEGER - rate:
			return null
		total_rate += rate
		# Every endpoint and bath subtotal is bounded by the checked total.
		if origin.is_empty():
			bath_in += rate
		else:
			outgoing[origin] = int(outgoing.get(origin, 0)) + rate
		if target.is_empty():
			bath_out += rate
		else:
			incoming[target] = int(incoming.get(target, 0)) + rate
	var plan := SimThermalFrozenGroups.new()
	var signatures: Dictionary = {}
	var keys: Array = cells.keys()
	keys.sort()
	for key: String in keys:
		var row: Dictionary = cells[key]
		var in_rate: int = int(incoming.get(key, 0))
		var out_rate: int = int(outgoing.get(key, 0))
		var signature: String = "%d/%d/%d" % [int(row.energy), in_rate, out_rate]
		if not signatures.has(signature):
			signatures[signature] = plan._groups.size()
			plan._groups.append({"rows": [], "members": PackedStringArray(), "in_rate": in_rate, "out_rate": out_rate})
		var group: Dictionary = plan._groups[int(signatures[signature])]
		group.rows.append(row)
		var members: PackedStringArray = group.members
		members.append(key)
		group.members = members
	plan._cell_count = keys.size()
	plan._ambient_in_rate = bath_in
	plan._ambient_out_rate = bath_out
	plan._total_rate = total_rate
	plan._max_q = max_q
	plan._compiled = true
	return plan


func can_settle(dt: int) -> bool:
	if not _compiled or dt < 0 or dt > MAX_INTEGER:
		return false
	# This kernel also bounds the sum of all transferred amounts, including
	# internal edges. Arbitrary individually valid but globally oversized
	# fields are outside this exact-integer contract.
	if not _product_fits(_total_rate, dt, MAX_INTEGER) or not _product_fits(_ambient_in_rate, dt, MAX_INTEGER) or not _product_fits(_ambient_out_rate, dt, MAX_INTEGER):
		return false
	for group: Dictionary in _groups:
		var energy: Variant = group.rows[0].get("energy")
		if not _integer(energy, 0, _max_q):
			return false
		var old_q: int = int(energy)
		if not _product_fits(int(group.out_rate), dt, old_q) or not _product_fits(int(group.in_rate), dt, _max_q - old_q):
			return false
	return true


func apply(dt: int) -> bool:
	# No original cell is written until every group and global amount fits.
	if not can_settle(dt):
		return false
	if dt == 0:
		return true
	for group: Dictionary in _groups:
		if int(group.in_rate) == int(group.out_rate):
			continue
		var energy: int = int(group.rows[0].energy) - int(group.out_rate) * dt + int(group.in_rate) * dt
		for row: Dictionary in group.rows:
			row.energy = energy
	return true


static func _product_fits(rate: int, dt: int, budget: int) -> bool:
	if rate == 0 or dt == 0:
		return true
	@warning_ignore("integer_division")
	var maximum_dt: int = budget / rate
	return dt <= maximum_dt


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	if value is int:
		return value >= minimum and value <= maximum
	if value is float:
		return is_finite(value) and value >= float(minimum) and value <= float(maximum) and floor(value) == value
	return false


static func _flow_shape(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 3 or not value.get("from") is String or not value.get("to") is String or not _integer(value.get("rate"), 1, MAX_INTEGER):
		return false
	for key: Variant in value:
		if not key is String or key not in ["from", "to", "rate"]:
			return false
	return true
