class_name SimThermalTransferBudget
extends RefCounted
## Deterministic, stateless limits for one frozen set of transfers.
## Nonempty endpoints have independent outgoing and incoming budgets from the
## old state; the empty endpoint is an unlimited external bath. Incoming heat
## never funds outgoing heat in the same segment, nor vice versa.

const MAX_INTEGER: int = 9007199254740991
const MAX_DURATION_MS: int = 60000


static func span(candidates: Variant, capacities: Variant, max_duration_ms: Variant) -> Dictionary:
	# Keep every original rate. If even one millisecond is unaffordable, the
	# caller must not apply this slope; cumulative ledger limits are separate.
	var prepared: Dictionary = _prepare(candidates, capacities, max_duration_ms)
	if not bool(prepared.ok):
		return prepared
	var budgets: Dictionary = prepared.budgets
	var outgoing: Dictionary = prepared.outgoing
	var incoming: Dictionary = prepared.incoming
	for node: String in outgoing:
		if int(outgoing[node]) > int(budgets[node]["out"]):
			return _failure("rate_exceeds_budget")
	for node: String in incoming:
		if int(incoming[node]) > int(budgets[node]["in"]):
			return _failure("rate_exceeds_budget")
	return {"ok": true, "duration_ms": _duration(int(prepared.horizon), budgets, outgoing, incoming)}


static func field_span(flows: Array, cells: Dictionary, max_cell_energy: int, horizon: int) -> int:
	# Fast path for the thermal domain's already validated cells and normalized
	# flows. Shape, unique edges and endpoint types are the caller's contract;
	# aggregate the same separate old-state budgets used by span(). Zero signals
	# an invalid bound, missing node, overflow or an unaffordable millisecond.
	if horizon < 1 or horizon > MAX_DURATION_MS or max_cell_energy < 1 or max_cell_energy > MAX_INTEGER:
		return 0
	var outgoing: Dictionary = {}
	var incoming: Dictionary = {}
	var total: int = 0
	for flow: Dictionary in flows:
		var origin: String = flow.from
		var target: String = flow.to
		var rate: int = int(flow.rate)
		if rate < 1 or rate > MAX_INTEGER or total > MAX_INTEGER - rate:
			return 0
		total += rate
		# Each endpoint subtotal is no greater than the checked global total.
		if not origin.is_empty():
			outgoing[origin] = int(outgoing.get(origin, 0)) + rate
		if not target.is_empty():
			incoming[target] = int(incoming.get(target, 0)) + rate
	var duration: int = horizon
	for node: String in outgoing:
		if not cells.has(node):
			return 0
		var energy: int = int(cells[node].energy)
		var rate: int = int(outgoing[node])
		if energy < 0 or energy > max_cell_energy or rate > energy:
			return 0
		@warning_ignore("integer_division")
		var limit: int = energy / rate
		duration = mini(duration, limit)
	for node: String in incoming:
		if not cells.has(node):
			return 0
		var energy: int = int(cells[node].energy)
		var rate: int = int(incoming[node])
		if energy < 0 or energy > max_cell_energy or rate > max_cell_energy - energy:
			return 0
		@warning_ignore("integer_division")
		var limit: int = (max_cell_energy - energy) / rate
		duration = mini(duration, limit)
	return duration


static func freeze(candidates: Variant, capacities: Variant, max_duration_ms: Variant) -> Dictionary:
	# When one millisecond of raw demand is too large, each endpoint first
	# grants proportional integer shares. Fractional leftovers go to edges in
	# stable (from, to) order. Each edge receives the smaller endpoint grant.
	# A second stable greedy pass spends any still-feasible budget. This is
	# conservative and makes progress but does not promise maximum throughput.
	var prepared: Dictionary = _prepare(candidates, capacities, max_duration_ms)
	if not bool(prepared.ok):
		return prepared
	var rows: Array[Dictionary] = prepared.rows
	var ordered: Array = rows.duplicate()
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.from) < str(right.from) or (left.from == right.from and str(left.to) < str(right.to)))
	var budgets: Dictionary = prepared.budgets
	var outgoing: Dictionary = prepared.outgoing
	var incoming: Dictionary = prepared.incoming
	var out_assigned: Dictionary = {}
	var in_assigned: Dictionary = {}
	for row: Dictionary in ordered:
		var origin: String = row.from
		var target: String = row.to
		var rate: int = int(row.rate)
		var out_grant: int = rate
		var in_grant: int = rate
		if not origin.is_empty():
			out_grant = _share(rate, int(budgets[origin]["out"]), int(outgoing[origin]))
			out_assigned[origin] = int(out_assigned.get(origin, 0)) + out_grant
		if not target.is_empty():
			in_grant = _share(rate, int(budgets[target]["in"]), int(incoming[target]))
			in_assigned[target] = int(in_assigned.get(target, 0)) + in_grant
		row["out_grant"] = out_grant
		row["in_grant"] = in_grant

	var out_remainder: Dictionary = {}
	var in_remainder: Dictionary = {}
	for node: String in outgoing:
		out_remainder[node] = mini(int(budgets[node]["out"]), int(outgoing[node])) - int(out_assigned.get(node, 0))
	for node: String in incoming:
		in_remainder[node] = mini(int(budgets[node]["in"]), int(incoming[node])) - int(in_assigned.get(node, 0))
	for row: Dictionary in ordered:
		var origin: String = row.from
		var target: String = row.to
		var rate: int = int(row.rate)
		if not origin.is_empty() and int(out_remainder[origin]) > 0 and int(row.out_grant) < rate:
			row.out_grant = int(row.out_grant) + 1
			out_remainder[origin] = int(out_remainder[origin]) - 1
		if not target.is_empty() and int(in_remainder[target]) > 0 and int(row.in_grant) < rate:
			row.in_grant = int(row.in_grant) + 1
			in_remainder[target] = int(in_remainder[target]) - 1

	var out_left: Dictionary = {}
	var in_left: Dictionary = {}
	for node: String in budgets:
		out_left[node] = int(budgets[node]["out"])
		in_left[node] = int(budgets[node]["in"])
	for row: Dictionary in ordered:
		var amount: int = mini(int(row.out_grant), int(row.in_grant))
		row["actual"] = amount
		if not str(row.from).is_empty():
			out_left[row.from] = int(out_left[row.from]) - amount
		if not str(row.to).is_empty():
			in_left[row.to] = int(in_left[row.to]) - amount
	for row: Dictionary in ordered:
		var origin: String = row.from
		var target: String = row.to
		var extra: int = int(row.rate) - int(row.actual)
		if not origin.is_empty():
			extra = mini(extra, int(out_left[origin]))
		if not target.is_empty():
			extra = mini(extra, int(in_left[target]))
		row.actual = int(row.actual) + extra
		if not origin.is_empty():
			out_left[origin] = int(out_left[origin]) - extra
		if not target.is_empty():
			in_left[target] = int(in_left[target]) - extra

	var used_out: Dictionary = {}
	var used_in: Dictionary = {}
	for node: String in outgoing:
		used_out[node] = int(budgets[node]["out"]) - int(out_left[node])
	for node: String in incoming:
		used_in[node] = int(budgets[node]["in"]) - int(in_left[node])
	var flows: Array[Dictionary] = []
	# rows retains input order even though ordered shares its dictionaries.
	for row: Dictionary in rows:
		if int(row.actual) > 0:
			flows.append({"from": str(row.from), "to": str(row.to), "rate": int(row.actual)})
	return {"ok": true, "flows": flows, "duration_ms": _duration(int(prepared.horizon), budgets, used_out, used_in)}


static func _prepare(candidates: Variant, capacities: Variant, max_duration_ms: Variant) -> Dictionary:
	if not _integer(max_duration_ms, 1, MAX_DURATION_MS):
		return _failure("invalid_duration")
	if not candidates is Array or not capacities is Dictionary:
		return _failure("invalid_input")
	var budgets: Dictionary = {}
	for node: Variant in capacities:
		if not node is String or str(node).is_empty():
			return _failure("invalid_capacity")
		var capacity: Variant = capacities[node]
		if not _keys(capacity, ["out", "in"]) or not _integer(capacity["out"], 0, MAX_INTEGER) or not _integer(capacity["in"], 0, MAX_INTEGER):
			return _failure("invalid_capacity")
		budgets[node] = {"out": int(capacity["out"]), "in": int(capacity["in"])}

	var rows: Array[Dictionary] = []
	var outgoing: Dictionary = {}
	var incoming: Dictionary = {}
	var seen: Dictionary = {}
	var total: int = 0
	for raw: Variant in candidates:
		if not _keys(raw, ["from", "to", "rate"]) or not raw.from is String or not raw.to is String or not _integer(raw.rate, 1, MAX_INTEGER):
			return _failure("invalid_candidate")
		var origin: String = raw.from
		var target: String = raw.to
		if origin == target:
			return _failure("invalid_edge")
		if (not origin.is_empty() and not budgets.has(origin)) or (not target.is_empty() and not budgets.has(target)):
			return _failure("missing_capacity")
		var destinations: Dictionary = seen.get(origin, {})
		if destinations.has(target):
			return _failure("duplicate_edge")
		destinations[target] = true
		seen[origin] = destinations
		var rate: int = int(raw.rate)
		if total > MAX_INTEGER - rate:
			return _failure("sum_overflow")
		total += rate
		# Each endpoint subtotal is bounded by the already checked global total.
		if not origin.is_empty():
			outgoing[origin] = int(outgoing.get(origin, 0)) + rate
		if not target.is_empty():
			incoming[target] = int(incoming.get(target, 0)) + rate
		rows.append({"from": origin, "to": target, "rate": rate})
	return {"ok": true, "rows": rows, "budgets": budgets, "outgoing": outgoing,
		"incoming": incoming, "horizon": int(max_duration_ms)}


static func _duration(horizon: int, budgets: Dictionary, outgoing: Dictionary, incoming: Dictionary) -> int:
	var duration: int = horizon
	for node: String in outgoing:
		var rate: int = int(outgoing[node])
		if rate > 0:
			@warning_ignore("integer_division")
			var limit: int = int(budgets[node]["out"]) / rate
			duration = mini(duration, limit)
	for node: String in incoming:
		var rate: int = int(incoming[node])
		if rate > 0:
			@warning_ignore("integer_division")
			var limit: int = int(budgets[node]["in"]) / rate
			duration = mini(duration, limit)
	return duration


static func _share(rate: int, budget: int, total: int) -> int:
	if total <= budget:
		return rate
	if budget == 0:
		return 0
	return _mul_div_floor(rate, budget, total)


static func _mul_div_floor(value: int, multiplier: int, divisor: int) -> int:
	# Here value <= divisor and multiplier < divisor. Long multiplication keeps
	# the quotient and remainder separately; no intermediate exceeds the JSON
	# safe bound, even when value * multiplier would overflow a signed int64.
	var bit: int = 1
	while bit <= (multiplier >> 1):
		bit = bit << 1
	var quotient: int = 0
	var remainder: int = 0
	while bit > 0:
		quotient += quotient
		if remainder >= divisor - remainder:
			remainder -= divisor - remainder
			quotient += 1
		else:
			remainder += remainder
		if (multiplier & bit) != 0:
			if remainder >= divisor - value:
				remainder -= divisor - value
				quotient += 1
			else:
				remainder += value
		bit = bit >> 1
	return quotient


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	if value is int:
		return value >= minimum and value <= maximum
	if value is float:
		var number: float = float(value)
		return is_finite(number) and number >= float(minimum) and number <= float(maximum) and floor(number) == number
	return false


static func _keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size():
		return false
	for key: Variant in value:
		if not key is String or not expected.has(key):
			return false
	return true


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
