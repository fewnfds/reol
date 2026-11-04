extends RefCounted
## Pure rule probes: the reference checks feasibility, not the allocator.

const Budget = preload("res://scripts/sim/thermal_transfer_budget.gd")
const HeatFixtures = preload("res://tests/sim/test_local_heat.gd")
const MAX_EXACT: int = 9007199254740991


func run(runner: Object) -> void:
	_examples(runner)
	_invalid_inputs(runner)
	_exact_large_ratio_and_json(runner)
	_small_exhaustive(runner)
	_field_span_equivalence(runner)
	_field_heat_continuity(runner)
	print("SCENARIO thermal transfer budget: immutable inputs, simultaneous source/sink limits, stable integer allocation, exact large ratios and split frozen segments")


func _examples(runner: Object) -> void:
	var empty: Dictionary = Budget.freeze([], {}, 60000)
	var empty_span: Dictionary = Budget.span([], {}, 60000)
	runner.assert_true(bool(empty.get("ok", false)), "an empty frozen set is valid")
	if bool(empty.get("ok", false)):
		runner.assert_eq(empty.flows, [], "an empty set creates no flow")
		runner.assert_eq(empty.duration_ms, 60000, "empty flow keeps the full supported maximum duration")
	runner.assert_true(bool(empty_span.get("ok", false)), "an empty original-rate span is valid")
	if bool(empty_span.get("ok", false)):
		runner.assert_eq(empty_span.duration_ms, 60000, "empty original-rate span keeps the full duration")

	var ordinary: Array = [
		{"from": "z", "to": "b", "rate": 3},
		{"from": "", "to": "z", "rate": 1},
		{"from": "z", "to": "a", "rate": 2}]
	var capacities: Dictionary = {"z": {"out": 20, "in": 7}, "a": {"out": 0, "in": 8}, "b": {"out": 0, "in": 12}}
	var ordinary_copy: Array = ordinary.duplicate(true)
	var capacities_copy: Dictionary = capacities.duplicate(true)
	var result: Dictionary = Budget.freeze(ordinary, capacities, 10)
	var span: Dictionary = Budget.span(ordinary, capacities, 10)
	runner.assert_true(bool(result.get("ok", false)) and bool(span.get("ok", false)), "unconstrained original rates freeze and span")
	if bool(result.get("ok", false)) and bool(span.get("ok", false)):
		runner.assert_eq(result.flows, ordinary, "rates that fit one millisecond keep their values and original order")
		runner.assert_eq(result.duration_ms, 4, "source depletion defines the frozen segment boundary")
		runner.assert_eq(span.duration_ms, 4, "original-rate span stops at the same source boundary")
	runner.assert_eq(ordinary, ordinary_copy, "freezing does not edit candidate edges")
	runner.assert_eq(capacities, capacities_copy, "freezing does not spend or edit capacities")

	var compete: Array = [
		{"from": "s", "to": "c", "rate": 2},
		{"from": "s", "to": "a", "rate": 5},
		{"from": "s", "to": "b", "rate": 3}]
	capacities = {"s": {"out": 6, "in": 0}, "a": {"out": 0, "in": 10},
		"b": {"out": 0, "in": 10}, "c": {"out": 0, "in": 10}}
	result = Budget.freeze(compete, capacities, 10)
	runner.assert_true(bool(result.get("ok", false)), "three transfers can share one limited source")
	if bool(result.get("ok", false)):
		runner.assert_eq(result.flows, [{"from": "s", "to": "c", "rate": 1},
			{"from": "s", "to": "a", "rate": 4}, {"from": "s", "to": "b", "rate": 1}],
			"integer remainder follows stable edge order while output retains input order")
		runner.assert_eq(result.duration_ms, 1, "a one-millisecond limited tail is frozen at the feasible rate")
	span = Budget.span(compete, capacities, 10)
	runner.assert_true(not bool(span.get("ok", false)) and span.has("reason"), "unmodified rates cannot span even one millisecond here")

	var opposing: Array = [{"from": "", "to": "x", "rate": 5}, {"from": "x", "to": "", "rate": 5}]
	result = Budget.freeze(opposing, {"x": {"out": 0, "in": 5}}, 10)
	runner.assert_true(bool(result.get("ok", false)), "an incoming transfer can proceed with no old outgoing energy")
	if bool(result.get("ok", false)):
		runner.assert_eq(result.flows, [{"from": "", "to": "x", "rate": 5}], "incoming energy cannot be borrowed by same-segment outgoing flow")
	result = Budget.freeze(opposing, {"x": {"out": 5, "in": 0}}, 10)
	runner.assert_true(bool(result.get("ok", false)), "an outgoing transfer can proceed with no old incoming capacity")
	if bool(result.get("ok", false)):
		runner.assert_eq(result.flows, [{"from": "x", "to": "", "rate": 5}], "outgoing energy cannot be borrowed as same-segment incoming capacity")
	result = Budget.freeze(opposing, {"x": {"out": 0, "in": 0}}, 10)
	runner.assert_true(bool(result.get("ok", false)), "zero old budgets give a valid empty frozen segment")
	if bool(result.get("ok", false)):
		runner.assert_eq(result.flows, [], "opposing rates do not cancel into a free transfer")
		runner.assert_eq(result.duration_ms, 10, "an empty feasible result keeps the requested segment")

	var two_sided: Array = [{"from": "s", "to": "a", "rate": 2}, {"from": "s", "to": "b", "rate": 2}, {"from": "t", "to": "a", "rate": 2}]
	capacities = {"s": {"out": 3, "in": 0}, "t": {"out": 2, "in": 0},
		"a": {"out": 0, "in": 1}, "b": {"out": 0, "in": 4}}
	result = Budget.freeze(two_sided, capacities, 5)
	runner.assert_true(bool(result.get("ok", false)), "two-sided contention admits a feasible integer allocation")
	if bool(result.get("ok", false)):
		runner.assert_eq(result.flows, [{"from": "s", "to": "a", "rate": 1}, {"from": "s", "to": "b", "rate": 2}],
			"stable greedy residual fills usable capacity after both endpoint grants")


func _must_reject(runner: Object, flows: Array, capacities: Dictionary, duration: Variant, label: String) -> void:
	var frozen: Dictionary = Budget.freeze(flows, capacities, duration)
	var span: Dictionary = Budget.span(flows, capacities, duration)
	runner.assert_true(not bool(frozen.get("ok", false)) and frozen.get("reason") is String and not str(frozen.get("reason")).is_empty(), "freeze rejects " + label)
	runner.assert_true(not bool(span.get("ok", false)) and span.get("reason") is String and not str(span.get("reason")).is_empty(), "span rejects " + label)


func _invalid_inputs(runner: Object) -> void:
	var flows: Array = [{"from": "a", "to": "b", "rate": 1}]
	var capacities: Dictionary = {"a": {"out": 5, "in": 5}, "b": {"out": 5, "in": 5}}
	for bad: Variant in [0, -1, 1.5, true, "1", INF, -INF, NAN, MAX_EXACT + 1]:
		var candidate: Array = flows.duplicate(true)
		candidate[0].rate = bad
		_must_reject(runner, candidate, capacities, 1, "invalid rate " + str(bad))
	for bad: Variant in [-1, 1.5, true, "1", INF, -INF, NAN, MAX_EXACT + 1]:
		for side: String in ["out", "in"]:
			var candidate_caps: Dictionary = capacities.duplicate(true)
			candidate_caps.a[side] = bad
			_must_reject(runner, flows, candidate_caps, 1, "invalid " + side + " capacity " + str(bad))
	for bad: Variant in [0, -1, 1.5, true, "1", INF, -INF, NAN, 60001]:
		_must_reject(runner, flows, capacities, bad, "invalid maximum duration " + str(bad))

	var malformed: Array[Array] = [
		[{"from": "a", "to": "b", "rate": 1, "extra": 0}],
		[{"from": "a", "to": "b"}],
		[{"from": true, "to": "b", "rate": 1}],
		[{"from": "a", "to": 2, "rate": 1}],
		[{"from": "a", "to": "missing", "rate": 1}],
		[{"from": "missing", "to": "b", "rate": 1}],
		[{"from": "a", "to": "a", "rate": 1}],
		[{"from": "", "to": "", "rate": 1}],
		[{"from": "a", "to": "b", "rate": 1}, {"from": "a", "to": "b", "rate": 2}]]
	for candidate: Array in malformed:
		_must_reject(runner, candidate, capacities, 1, "malformed, missing, duplicate or self edge")
	var duplicated: Array = [{"from": "a", "to": "b", "rate": 1}, {"from": "a", "to": "b", "rate": 2}]
	var original_edges: Array = duplicated.duplicate(true)
	var original_caps: Dictionary = capacities.duplicate(true)
	_must_reject(runner, duplicated, capacities, 1, "duplicate edge without side effects")
	runner.assert_eq(duplicated, original_edges, "rejected candidates stay unchanged")
	runner.assert_eq(capacities, original_caps, "rejection does not modify any original capacity")
	var bad_caps: Dictionary = capacities.duplicate(true)
	bad_caps.a.extra = 1
	_must_reject(runner, flows, bad_caps, 1, "extra node capacity field")
	bad_caps = capacities.duplicate(true)
	bad_caps.a.erase("in")
	_must_reject(runner, flows, bad_caps, 1, "missing node capacity field")
	_must_reject(runner, [{"from": "a", "to": "b", "rate": MAX_EXACT}, {"from": "a", "to": "c", "rate": 1}],
		{"a": {"out": MAX_EXACT, "in": 0}, "b": {"out": 0, "in": MAX_EXACT}, "c": {"out": 0, "in": 1}}, 1, "outgoing aggregate beyond exact integer range")
	_must_reject(runner, [{"from": "a", "to": "c", "rate": MAX_EXACT}, {"from": "b", "to": "c", "rate": 1}],
		{"a": {"out": MAX_EXACT, "in": 0}, "b": {"out": 1, "in": 0}, "c": {"out": 0, "in": MAX_EXACT}}, 1, "incoming aggregate beyond exact integer range")

	var json_numbers: Dictionary = Budget.freeze([{"from": "", "to": "x", "rate": 2.0}], {"x": {"out": 0.0, "in": 10.0}}, 3.0)
	runner.assert_true(bool(json_numbers.get("ok", false)), "JSON-style floating-point integers are accepted")
	if bool(json_numbers.get("ok", false)):
		runner.assert_eq(json_numbers.flows, [{"from": "", "to": "x", "rate": 2}], "accepted JSON integers preserve their exact rate")
		runner.assert_eq(json_numbers.duration_ms, 3, "accepted JSON integer duration remains exact")


func _exact_large_ratio_and_json(runner: Object) -> void:
	# The two products below are about 10^31. A binary64 proportional
	# calculation rounds the second floor up by one, changing the winner.
	var flows: Array = [{"from": "s", "to": "a", "rate": 3000000002469134},
		{"from": "s", "to": "b", "rate": 6007199252271857}]
	var capacities: Dictionary = {"s": {"out": 4000000001578246, "in": 0},
		"a": {"out": 0, "in": MAX_EXACT}, "b": {"out": 0, "in": MAX_EXACT}}
	var round_trip: Variant = JSON.parse_string(JSON.stringify({"flows": flows, "capacities": capacities, "duration": 10}))
	runner.assert_true(round_trip is Dictionary, "extreme values survive actual JSON parsing")
	if not round_trip is Dictionary:
		return
	var result: Dictionary = Budget.freeze(round_trip.flows, round_trip.capacities, round_trip.duration)
	runner.assert_true(bool(result.get("ok", false)), "large JSON-safe inputs can be frozen without overflow")
	if bool(result.get("ok", false)):
		runner.assert_eq(result.flows, [{"from": "s", "to": "a", "rate": 1332267631172366},
			{"from": "s", "to": "b", "rate": 2667732370405880}],
			"large products use exact integer floors and the stable remainder edge")
		runner.assert_eq(result.duration_ms, 1, "the large source reaches its exact boundary after one millisecond")
	var reversed: Array = round_trip.flows.duplicate(true)
	reversed.reverse()
	var reversed_result: Dictionary = Budget.freeze(reversed, round_trip.capacities, round_trip.duration)
	runner.assert_true(bool(reversed_result.get("ok", false)), "large reversed input is also accepted")
	if bool(result.get("ok", false)) and bool(reversed_result.get("ok", false)):
		runner.assert_eq(_flow_map(reversed_result.flows), _flow_map(result.flows), "large integer allocation is independent of candidate order")
		runner.assert_eq(reversed_result.flows.size(), 2, "large reversed output retains both original edges")
		if not reversed_result.flows.is_empty():
			runner.assert_eq(reversed_result.flows[0].to, "b", "large reversed output retains its own input order")


func _edge_id(row: Dictionary) -> String:
	return str(row.from) + "|" + str(row.to)


func _flow_map(flows: Array) -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in flows:
		result[_edge_id(row)] = int(row.rate)
	return result


func _totals(flows: Array, nodes: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for node: String in nodes:
		result[node] = {"out": 0, "in": 0}
	for row: Dictionary in flows:
		if not str(row.from).is_empty():
			result[row.from].out += int(row.rate)
		if not str(row.to).is_empty():
			result[row.to].in += int(row.rate)
	return result


func _slow_duration(flows: Array, capacities: Dictionary, maximum: int) -> int:
	# Each step checks physical old budgets independently; no allocation logic.
	var totals: Dictionary = _totals(flows, capacities)
	var duration: int = 0
	for tick: int in range(1, maximum + 1):
		var fits: bool = true
		for node: String in capacities:
			if int(totals[node].out) * tick > int(capacities[node].out) or int(totals[node].in) * tick > int(capacities[node].in):
				fits = false
				break
		if not fits:
			break
		duration = tick
	return duration


func _audit_flows(candidates: Array, capacities: Dictionary, result: Dictionary, maximum: int) -> String:
	if not bool(result.get("ok", false)) or not result.get("flows") is Array:
		return "valid inputs were not frozen"
	var output: Array = result.flows
	var candidate_map: Dictionary = {}
	var candidate_order: Dictionary = {}
	var feasible: bool = false
	for index: int in candidates.size():
		var edge: Dictionary = candidates[index]
		var id: String = _edge_id(edge)
		candidate_map[id] = int(edge.rate)
		candidate_order[id] = index
		var source_ok: bool = str(edge.from).is_empty() or int(capacities[edge.from].out) > 0
		var target_ok: bool = str(edge.to).is_empty() or int(capacities[edge.to].in) > 0
		feasible = feasible or (source_ok and target_ok)
	var last_index: int = -1
	for raw: Variant in output:
		if not raw is Dictionary or raw.size() != 3 or not raw.has("from") or not raw.has("to") or not raw.has("rate"):
			return "output edge shape changed"
		if not (raw.rate is int or raw.rate is float) or not is_finite(float(raw.rate)):
			return "output rate is not a finite number"
		var id: String = _edge_id(raw)
		if not candidate_map.has(id) or int(raw.rate) < 1 or int(raw.rate) > int(candidate_map[id]) or raw.rate != int(raw.rate):
			return "output invented an edge or changed its rate outside the candidate"
		if int(candidate_order[id]) <= last_index:
			return "output did not preserve relative input order"
		last_index = int(candidate_order[id])
	if feasible and output.is_empty():
		return "a feasible one-unit edge made no progress"
	var duration: int = _slow_duration(output, capacities, maximum)
	if duration < 1 or result.get("duration_ms") != duration:
		return "frozen duration or simultaneous endpoint budgets are wrong"
	return ""


func _split_amounts(flows: Array, durations: Array) -> Dictionary:
	var amounts: Dictionary = {}
	for duration: int in durations:
		for row: Dictionary in flows:
			var id: String = _edge_id(row)
			amounts[id] = int(amounts.get(id, 0)) + int(row.rate) * duration
	return amounts


func _check_case(candidates: Array, capacities: Dictionary, maximum: int) -> String:
	var original_edges: Array = candidates.duplicate(true)
	var original_caps: Dictionary = capacities.duplicate(true)
	var result: Dictionary = Budget.freeze(candidates, capacities, maximum)
	var error: String = _audit_flows(candidates, capacities, result, maximum)
	if not error.is_empty():
		return error
	var reversed: Array = candidates.duplicate(true)
	reversed.reverse()
	var reversed_before: Array = reversed.duplicate(true)
	var other: Dictionary = Budget.freeze(reversed, capacities, maximum)
	error = _audit_flows(reversed, capacities, other, maximum)
	if not error.is_empty():
		return "reversed: " + error
	if _flow_map(result.flows) != _flow_map(other.flows) or result.duration_ms != other.duration_ms:
		return "input order changed the selected rates or boundary"
	var span: Dictionary = Budget.span(candidates, capacities, maximum)
	var expected_span: int = _slow_duration(candidates, capacities, maximum)
	if expected_span == 0:
		if bool(span.get("ok", false)) or not span.has("reason"):
			return "span accepted an impossible original-rate millisecond"
	elif not bool(span.get("ok", false)) or span.get("duration_ms") != expected_span:
		return "span changed original rates or chose the wrong boundary"
	if candidates != original_edges or reversed != reversed_before or capacities != original_caps:
		return "a pure budget operation mutated its inputs"
	var duration: int = int(result.duration_ms)
	if duration > 1:
		var first: int = 1
		var rest: int = duration - first
		var remaining: Dictionary = capacities.duplicate(true)
		var totals: Dictionary = _totals(result.flows, capacities)
		for node: String in remaining:
			remaining[node].out = int(remaining[node].out) - int(totals[node].out) * first
			remaining[node].in = int(remaining[node].in) - int(totals[node].in) * first
		var continued: Dictionary = Budget.span(result.flows, remaining, rest)
		if not bool(continued.get("ok", false)) or continued.get("duration_ms") != rest:
			return "the frozen rates cannot continue through their own split boundary"
		if _split_amounts(result.flows, [duration]) != _split_amounts(result.flows, [first, rest]):
			return "frozen edge amounts depend on the integration split"
	return ""


func _small_exhaustive(runner: Object) -> void:
	# Three independent directions model outside heat, a same-cell sink and a
	# transfer to another cell. Incoming and outgoing limits remain distinct.
	for incoming: int in range(1, 4):
		for outgoing: int in range(1, 4):
			for across: int in range(1, 4):
				for x_in: int in range(5):
					for x_out: int in range(5):
						for y_in: int in range(5):
							var candidates: Array = [{"from": "", "to": "x", "rate": incoming},
								{"from": "x", "to": "", "rate": outgoing}, {"from": "x", "to": "y", "rate": across}]
							var capacities: Dictionary = {"x": {"out": x_out, "in": x_in}, "y": {"out": 0, "in": y_in}}
							var error: String = _check_case(candidates, capacities, 4)
							var label: String = "small independent budget/ordering/split oracle"
							if not error.is_empty():
								label += ": %s rates=%s caps=%s" % [error, str([incoming, outgoing, across]), str([x_in, x_out, y_in])]
							runner.assert_true(error.is_empty(), label)


func _field_capacities(cells: Dictionary, ceiling: int) -> Dictionary:
	var result: Dictionary = {}
	for node: String in cells:
		var energy: int = int(cells[node].energy)
		result[node] = {"out": energy, "in": ceiling - energy}
	return result


func _field_equivalence_error(flows: Array, cells: Dictionary, ceiling: int, horizon: int) -> String:
	var original_flows: Array = flows.duplicate(true)
	var original_cells: Dictionary = cells.duplicate(true)
	var capacities: Dictionary = _field_capacities(cells, ceiling)
	var expected: int = _slow_duration(flows, capacities, horizon)
	var generic: Dictionary = Budget.span(flows, capacities, horizon)
	var generic_duration: int = int(generic.duration_ms) if bool(generic.get("ok", false)) else 0
	var fast: int = Budget.field_span(flows, cells, ceiling, horizon)
	if fast != expected or generic_duration != expected:
		return "fast=%d generic=%d independent=%d" % [fast, generic_duration, expected]
	if flows != original_flows or cells != original_cells:
		return "field or generic span changed its original flows or cell energy"
	return ""


func _field_span_equivalence(runner: Object) -> void:
	# The independent oracle charges Q and free room separately at each
	# millisecond. Unaffordable one-millisecond slopes must return zero.
	for ceiling: int in range(1, 5):
		for x_energy: int in range(ceiling + 1):
			var single: Dictionary = {"x": {"energy": x_energy, "cell": [1, 1]}}
			for incoming: int in range(1, 4):
				for outgoing: int in range(1, 4):
					var inbound: Dictionary = {"from": "", "to": "x", "rate": incoming}
					var outbound: Dictionary = {"from": "x", "to": "", "rate": outgoing}
					for single_flows: Array in [[inbound], [outbound], [inbound, outbound]]:
						var error: String = _field_equivalence_error(single_flows, single, ceiling, 4)
						var label: String = "single-cell field/generic/slow span"
						if not error.is_empty():
							label += ": %s Q=%d ceiling=%d flows=%s" % [error, x_energy, ceiling, str(single_flows)]
						runner.assert_true(error.is_empty(), label)
			for y_energy: int in range(ceiling + 1):
				var pair: Dictionary = {"x": {"energy": x_energy, "cell": [1, 1]}, "y": {"energy": y_energy, "cell": [2, 1]}}
				for first: int in range(1, 4):
					for second: int in range(1, 4):
						for third: int in range(1, 4):
							var graphs: Array[Array] = [
								[{"from": "", "to": "x", "rate": first}, {"from": "x", "to": "", "rate": second}, {"from": "x", "to": "y", "rate": third}],
								[{"from": "x", "to": "y", "rate": first}, {"from": "y", "to": "x", "rate": second}, {"from": "", "to": "x", "rate": third}]]
							for flows: Array in graphs:
								var error: String = _field_equivalence_error(flows, pair, ceiling, 4)
								var label: String = "two-cell field/generic/slow span"
								if not error.is_empty():
									label += ": %s Q=%s ceiling=%d flows=%s" % [error, str([x_energy, y_energy]), ceiling, str(flows)]
								runner.assert_true(error.is_empty(), label)

	runner.assert_eq(Budget.field_span([], {}, MAX_EXACT, 60000), 60000, "empty field flow accepts the full 60000ms horizon")
	var full: Dictionary = {"x": {"energy": 60000}}
	var empty: Dictionary = {"x": {"energy": 0}}
	var leaving: Array = [{"from": "x", "to": "", "rate": 1}]
	var arriving: Array = [{"from": "", "to": "x", "rate": 1}]
	runner.assert_eq(Budget.field_span(leaving, full, 60000, 60000), 60000, "one unit/ms can spend the entire 60000ms horizon")
	runner.assert_eq(Budget.field_span(arriving, empty, 60000, 60000), 60000, "one unit/ms can fill the entire 60000ms horizon")
	runner.assert_eq(Budget.field_span(leaving, empty, 60000, 60000), 0, "empty Q cannot fund an outgoing millisecond")
	runner.assert_eq(Budget.field_span(arriving, full, 60000, 60000), 0, "a full cell cannot accept an incoming millisecond")
	runner.assert_eq(Budget.field_span(leaving, {}, 60000, 1), 0, "missing outgoing cell rejects the slope")
	runner.assert_eq(Budget.field_span(arriving, {}, 60000, 1), 0, "missing incoming cell rejects the slope")
	runner.assert_true(not bool(Budget.span(leaving, {}, 1).get("ok", false)), "generic span also rejects the missing cell")
	runner.assert_eq(Budget.field_span(leaving, full, 60000, 0), 0, "zero horizon is rejected")
	runner.assert_eq(Budget.field_span(leaving, full, 60000, 60001), 0, "horizon above the supported maximum is rejected")
	runner.assert_eq(Budget.field_span([], {}, 0, 1), 0, "zero cell ceiling is rejected")
	runner.assert_eq(Budget.field_span([], {}, MAX_EXACT + 1, 1), 0, "cell ceiling beyond JSON-exact range is rejected")
	runner.assert_eq(Budget.field_span(leaving, {"x": {"energy": -1}}, 1, 1), 0, "negative original energy is rejected")
	runner.assert_eq(Budget.field_span(leaving, {"x": {"energy": 2}}, 1, 1), 0, "original energy above its ceiling is rejected")
	var largest: Array = [{"from": "x", "to": "", "rate": MAX_EXACT}]
	var largest_cells: Dictionary = {"x": {"energy": MAX_EXACT}}
	var largest_copy: Array = largest.duplicate(true)
	var largest_cells_copy: Dictionary = largest_cells.duplicate(true)
	runner.assert_eq(Budget.field_span(largest, largest_cells, MAX_EXACT, 60000), 1, "maximum exact Q and rate allow exactly one millisecond")
	runner.assert_eq(Budget.field_span([{"from": "", "to": "x", "rate": MAX_EXACT}], {"x": {"energy": 0}}, MAX_EXACT, 60000), 1, "maximum exact inbound headroom allows exactly one millisecond")
	runner.assert_eq(Budget.field_span([{"from": "x", "to": "", "rate": MAX_EXACT + 1}], largest_cells, MAX_EXACT, 1), 0, "rate beyond the exact integer limit is rejected")
	runner.assert_eq(Budget.field_span([{"from": "x", "to": "", "rate": MAX_EXACT}, {"from": "y", "to": "", "rate": 1}],
		{"x": {"energy": MAX_EXACT}, "y": {"energy": 1}}, MAX_EXACT, 1), 0, "global rate aggregate above the exact limit is rejected")
	runner.assert_true(not bool(Budget.span([{"from": "x", "to": "", "rate": MAX_EXACT}, {"from": "y", "to": "", "rate": 1}],
		{"x": {"out": MAX_EXACT, "in": 0}, "y": {"out": 1, "in": MAX_EXACT - 1}}, 1).get("ok", false)), "generic span rejects the same global aggregate")
	runner.assert_eq(largest, largest_copy, "large field span leaves original rates untouched")
	runner.assert_eq(largest_cells, largest_cells_copy, "large field span leaves original energy untouched")


func _field_heat_continuity(runner: Object) -> void:
	var fixture := HeatFixtures.new()
	var current: Dictionary = fixture._make()
	runner.assert_true(bool(current.configured), "real finite heat fixture initializes")
	if not bool(current.configured):
		return
	var climate_changes: Array[Dictionary] = [{"at_ms": 5500, "west": 3}]
	current.world.background_schedule = climate_changes
	fixture._advance(current, 137)
	runner.assert_true(fixture._deposit(current, "warm:field-span"), "a real completed impulse creates its original heat receipt")
	if current.heat.flows.is_empty():
		runner.assert_true(false, "real impulse must create nonempty original thermal flows")
		return
	var ceiling: int = int(current.heat.definitions.max_cell_energy)
	var step: int = int(current.heat.definitions.step_ms)
	var distance: int = step - posmod(137, step)
	var generic: Dictionary = Budget.span(current.heat.flows, _field_capacities(current.heat.cells, ceiling), distance)
	runner.assert_true(bool(generic.get("ok", false)), "real frozen heat rates fit the original physical cell budgets")
	if not bool(generic.get("ok", false)):
		return
	runner.assert_eq(int(generic.duration_ms), distance, "initial real heat rates fit to the original step boundary")
	var expected: int = mini(137 + int(generic.duration_ms), 5500)
	runner.assert_eq(current.heat._boundary_at(137, current.heat.cells, current.heat.flows), expected, "real fast boundary agrees with generic rates and the earlier climate boundary")
	runner.assert_eq(current.heat.next_boundary_ms(), 5500, "the deposited live field schedules the actual climate change")
	fixture._advance(current, 5500)
	runner.assert_eq(current.heat.last_ms, 5500, "the actual field reaches and settles the climate boundary")
	distance = step - posmod(5500, step)
	generic = Budget.span(current.heat.flows, _field_capacities(current.heat.cells, ceiling), distance)
	runner.assert_true(bool(generic.get("ok", false)), "post-climate real rates still fit their physical budgets")
	if not bool(generic.get("ok", false)):
		return
	runner.assert_eq(int(generic.duration_ms), distance, "post-climate real rates fit to the next original step")
	runner.assert_eq(current.heat._boundary_at(5500, current.heat.cells, current.heat.flows), 5500 + distance, "real fast boundary returns the original step after the climate change")
	runner.assert_eq(current.heat.next_boundary_ms(), 10000, "the live field retains the ordinary aligned step")
	fixture._advance(current, 5731)
	runner.assert_eq(current.heat.last_ms, 5731, "the real field can stop inside its frozen segment")
	var saved: String = fixture._json(current.heat)
	var resumed: Dictionary = fixture._make({}, 5731)
	resumed.world.background_schedule = current.world.background_schedule.duplicate(true)
	resumed.world.artifacts.events = current.world.artifacts.events.duplicate(true)
	var restored: bool = resumed.heat.restore(JSON.parse_string(saved))
	runner.assert_true(restored, "an independent heat authority accepts the actual in-flight JSON and original receipt")
	if not restored:
		return
	runner.assert_eq(fixture._json(resumed.heat), saved, "independent JSON restore preserves the complete heat state")
	for at_ms: int in [9999, 10000, 17031]:
		fixture._advance(current, at_ms)
		fixture._advance(resumed, at_ms, true)
		runner.assert_eq(current.heat.last_ms, at_ms, "original field advances through the requested future")
		runner.assert_eq(resumed.heat.last_ms, at_ms, "restored field advances through the same future")
		runner.assert_eq(fixture._json(resumed.heat), fixture._json(current.heat), "restored and original complete heat futures match across different partitions")
