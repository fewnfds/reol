extends RefCounted
## A direct per-flow old-budget oracle checks the grouped arithmetic.

const Groups = preload("res://scripts/sim/thermal_frozen_groups.gd")
const MAX_EXACT: int = 9007199254740991


func run(runner: Object) -> void:
	_groups_and_original_rows(runner)
	_small_exhaustive(runner)
	_random_order_and_arithmetic(runner)
	_slicing(runner)
	_extremes_and_json(runner)
	_invalid_inputs(runner)
	print("SCENARIO thermal frozen groups: strict and trusted-field original-row integration, distinct incoming/outgoing budgets, independent exhaustive and seeded per-flow oracle, stable grouping, split intervals, JSON integers, exact limits and strict-input atomic rejection")


func _cells(energies: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var index: int = 0
	for key: String in energies:
		result[key] = {"energy": energies[key], "cell": [index, 0], "metadata": {"label": key}}
		index += 1
	return result


func _groups_and_original_rows(runner: Object) -> void:
	var cells: Dictionary = _cells({"z": 9, "d": 5, "c": 5, "b": 5, "a": 5})
	var flows: Array = [{"from": "", "to": "d", "rate": 1}, {"from": "", "to": "b", "rate": 1},
		{"from": "c", "to": "", "rate": 1}, {"from": "", "to": "c", "rate": 2}]
	var original: Dictionary = cells.duplicate(true)
	var retained_b: Dictionary = cells.b
	var plan: SimThermalFrozenGroups = Groups.compile(cells, flows, 10)
	runner.assert_true(plan != null, "ordinary original cells and bath flows compile")
	if plan == null:
		return
	runner.assert_eq(cells, original, "compilation does not normalize or spend original Q")
	runner.assert_eq(plan.cell_count, 5, "the plan retains every original cell including quiet ones")
	runner.assert_eq(plan.group_count, 4, "same net rate does not merge distinct incoming and outgoing budgets")
	runner.assert_eq(plan.ambient_in_rate, 4, "inbound bath rate is the actual sum of incoming edges")
	runner.assert_eq(plan.ambient_out_rate, 1, "outbound bath rate remains separate")
	var expected: Array = [
		{"cells": PackedStringArray(["a"]), "in_rate": 0, "out_rate": 0},
		{"cells": PackedStringArray(["b", "d"]), "in_rate": 1, "out_rate": 0},
		{"cells": PackedStringArray(["c"]), "in_rate": 2, "out_rate": 1},
		{"cells": PackedStringArray(["z"]), "in_rate": 0, "out_rate": 0}]
	runner.assert_eq(plan.groups, expected, "groups and members use deterministic first-member key order")
	var detached: Array[Dictionary] = plan.groups
	detached[1].in_rate = MAX_EXACT
	var detached_members: PackedStringArray = detached[1].cells
	detached_members.append("invented")
	detached[1].cells = detached_members
	runner.assert_eq(plan.groups, expected, "diagnostic grouping exposes neither original rows nor writable internal metadata")
	runner.assert_true(plan.apply(1), "a feasible grouped millisecond applies")
	runner.assert_true(is_same(cells.b, retained_b) and int(retained_b.energy) == 6, "integration writes the retained original row rather than a copied Q owner")
	runner.assert_eq(cells.a, original.a, "the quiet original cell remains unchanged")
	runner.assert_eq(cells.b.metadata, original.b.metadata, "integration preserves all nonenergy metadata")
	runner.assert_eq(int(cells.c.energy), 6, "different gross rates retain the same independently computed net result")
	var field_cells: Dictionary = original.duplicate(true)
	var field_b: Dictionary = field_cells.b
	var field: SimThermalFrozenGroups = Groups.compile_field(field_cells, flows, 10)
	runner.assert_true(field != null, "already validated original field rows compile through the trusted entry")
	if field != null:
		runner.assert_eq(field.groups, expected, "strict and trusted entries export the same groups and separate rates")
		runner.assert_true(field.apply(1), "the trusted plan integrates the same feasible interval")
		runner.assert_true(is_same(field_cells.b, field_b) and int(field_b.energy) == 6, "the trusted entry also writes the original referenced row")
		runner.assert_eq(field_cells, cells, "both compile entries produce the same complete cell results")
	var before: Dictionary = cells.duplicate(true)
	runner.assert_true(not plan.apply(3), "one later group with insufficient old headroom rejects the entire operation")
	runner.assert_eq(cells, before, "a failed late group cannot leave earlier groups partly changed")
	var uncompiled := Groups.new()
	runner.assert_true(not uncompiled.can_settle(0) and not uncompiled.apply(0), "only a validated compile result is an integration plan")


func _oracle(initial: Dictionary, flows: Array, ceiling: int, dt: int) -> Dictionary:
	# Charge each edge against two distinct old-state purses, then integrate
	# that edge on a private result. This has no grouping or aggregate rates.
	if dt < 0 or dt > MAX_EXACT:
		return {"ok": false}
	var remaining_q: Dictionary = {}
	var remaining_room: Dictionary = {}
	for key: String in initial:
		remaining_q[key] = int(initial[key].energy)
		remaining_room[key] = ceiling - int(initial[key].energy)
	var result: Dictionary = initial.duplicate(true)
	var total_amount: int = 0
	for flow: Dictionary in flows:
		var rate: int = int(flow.rate)
		@warning_ignore("integer_division")
		var limit: int = MAX_EXACT / rate
		if dt > limit:
			return {"ok": false}
		var amount: int = rate * dt
		if total_amount > MAX_EXACT - amount:
			return {"ok": false}
		total_amount += amount
		var origin: String = flow.from
		var target: String = flow.to
		if not origin.is_empty():
			if amount > int(remaining_q[origin]):
				return {"ok": false}
			remaining_q[origin] = int(remaining_q[origin]) - amount
			result[origin].energy = int(result[origin].energy) - amount
		if not target.is_empty():
			if amount > int(remaining_room[target]):
				return {"ok": false}
			remaining_room[target] = int(remaining_room[target]) - amount
			result[target].energy = int(result[target].energy) + amount
	return {"ok": true, "cells": result}


func _case_error(initial: Dictionary, flows: Array, ceiling: int, dt: int) -> String:
	var actual: Dictionary = initial.duplicate(true)
	var before: Dictionary = actual.duplicate(true)
	var flow_copy: Array = flows.duplicate(true)
	var plan: SimThermalFrozenGroups = Groups.compile(actual, flows, ceiling)
	if plan == null:
		return "valid graph did not compile"
	if actual != before or flows != flow_copy:
		return "compile changed its input"
	var expected: Dictionary = _oracle(initial, flows, ceiling, dt)
	if plan.can_settle(dt) != bool(expected.ok):
		return "group preflight differs from direct per-flow old budgets"
	if actual != before:
		return "preflight changed original rows"
	if plan.apply(dt) != bool(expected.ok):
		return "group application differs from direct per-flow feasibility"
	if actual != (expected.cells if bool(expected.ok) else before):
		return "original Q or atomic failure differs from the per-flow result"
	if flows != flow_copy:
		return "integration changed the frozen flows"
	# The fast entry receives the normalized numerical representation promised
	# by its caller, including when the strict side tests JSON integral floats.
	var field_cells: Dictionary = before.duplicate(true)
	for row: Dictionary in field_cells.values():
		row.energy = int(row.energy)
	var field_before: Dictionary = field_cells.duplicate(true)
	var field_flows: Array = flows.duplicate(true)
	for flow: Dictionary in field_flows:
		flow.rate = int(flow.rate)
	var field_flow_copy: Array = field_flows.duplicate(true)
	var field: SimThermalFrozenGroups = Groups.compile_field(field_cells, field_flows, ceiling)
	if field == null:
		return "valid normalized graph did not compile through the trusted entry"
	if field_cells != field_before or field_flows != field_flow_copy:
		return "trusted compile changed its original input"
	if field.groups != plan.groups or field.cell_count != plan.cell_count or field.ambient_in_rate != plan.ambient_in_rate or field.ambient_out_rate != plan.ambient_out_rate:
		return "strict and trusted grouping, cell count or bath rates differ"
	if field.can_settle(dt) != bool(expected.ok):
		return "trusted preflight differs from direct per-flow old budgets"
	if field_cells != field_before:
		return "trusted preflight changed original rows"
	if field.apply(dt) != bool(expected.ok):
		return "trusted application differs from direct per-flow feasibility"
	var field_expected: Dictionary = (expected.cells if bool(expected.ok) else before).duplicate(true)
	for row: Dictionary in field_expected.values():
		row.energy = int(row.energy)
	if field_cells != field_expected:
		return "trusted original Q or atomic failure differs from the per-flow result"
	for key: String in actual:
		if int(field_cells[key].energy) != int(actual[key].energy):
			return "strict and trusted original Q results differ"
	if field_flows != field_flow_copy:
		return "trusted integration changed the frozen flows"
	return ""


func _small_exhaustive(runner: Object) -> void:
	var checked: int = 0
	for ceiling: int in range(4):
		for a_q: int in range(ceiling + 1):
			for b_q: int in range(ceiling + 1):
				var initial: Dictionary = _cells({"a": a_q, "b": b_q})
				for inbound: int in range(3):
					for outbound: int in range(3):
						for across: int in range(3):
							var flows: Array = []
							if inbound > 0:
								flows.append({"from": "", "to": "a", "rate": inbound})
							if outbound > 0:
								flows.append({"from": "a", "to": "", "rate": outbound})
							if across > 0:
								flows.append({"from": "a", "to": "b", "rate": across})
							for dt: int in range(5):
								var error: String = _case_error(initial, flows, ceiling, dt)
								if not error.is_empty():
									runner.assert_true(false, "small exhaustive grouped oracle: %s Q=%s ceiling=%d rates=%s dt=%d" % [error, [a_q, b_q], ceiling, [inbound, outbound, across], dt])
									return
								checked += 1
	runner.assert_eq(checked, 4050, "strict and trusted entries match the independent oracle for all small old-budget and duration combinations")


func _random_order_and_arithmetic(runner: Object) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261108
	var endpoints: Array[String] = ["", "a", "b", "c", "d"]
	for case_index: int in range(96):
		var ceiling: int = rng.randi_range(1, 31)
		var initial: Dictionary = _cells({"a": rng.randi_range(0, ceiling), "b": rng.randi_range(0, ceiling),
			"c": rng.randi_range(0, ceiling), "d": rng.randi_range(0, ceiling)})
		var flows: Array = []
		for origin: String in endpoints:
			for target: String in endpoints:
				if origin != target and rng.randi_range(0, 4) == 0:
					flows.append({"from": origin, "to": target, "rate": rng.randi_range(1, 4)})
		for dt: int in range(7):
			var error: String = _case_error(initial, flows, ceiling, dt)
			if not error.is_empty():
				runner.assert_true(false, "seeded grouped oracle case %d dt %d: %s" % [case_index, dt, error])
				return
		var ordered: SimThermalFrozenGroups = Groups.compile(initial, flows, ceiling)
		var reversed_cells: Dictionary = {}
		var keys: Array = initial.keys()
		keys.reverse()
		for key: String in keys:
			reversed_cells[key] = initial[key].duplicate(true)
		var reversed_flows: Array = flows.duplicate(true)
		reversed_flows.reverse()
		var reversed: SimThermalFrozenGroups = Groups.compile(reversed_cells, reversed_flows, ceiling)
		var ordered_field: SimThermalFrozenGroups = Groups.compile_field(initial, flows, ceiling)
		var reversed_field: SimThermalFrozenGroups = Groups.compile_field(reversed_cells, reversed_flows, ceiling)
		if ordered == null or reversed == null or ordered_field == null or reversed_field == null:
			runner.assert_true(false, "seeded valid graphs compile under either insertion order")
			return
		runner.assert_eq(ordered.groups, reversed.groups, "cell insertion and edge order do not change exact grouping")
		runner.assert_eq(ordered_field.groups, ordered.groups, "the trusted entry retains strict grouping under the original order")
		runner.assert_eq(reversed_field.groups, ordered.groups, "the trusted entry retains strict grouping under reversed cell and edge order")


func _slicing(runner: Object) -> void:
	var initial: Dictionary = _cells({"a": 20, "b": 10, "c": 20, "d": 10})
	var flows: Array = [{"from": "a", "to": "b", "rate": 2}, {"from": "c", "to": "d", "rate": 2},
		{"from": "", "to": "b", "rate": 1}, {"from": "", "to": "d", "rate": 1}]
	var expected: Dictionary = _oracle(initial, flows, 40, 7)
	for durations: Array in [[7], [1, 2, 4], [0, 3, 0, 1, 3]]:
		var cells: Dictionary = initial.duplicate(true)
		var plan: SimThermalFrozenGroups = Groups.compile(cells, flows, 40)
		if plan == null:
			runner.assert_true(false, "the original grouped frozen interval compiles")
			return
		runner.assert_eq(plan.group_count, 2, "matching original balances and gross rates provide a real two-group reduction")
		for dt: int in durations:
			runner.assert_true(plan.apply(dt), "every slice fits the actual remaining original budgets")
		runner.assert_eq(cells, expected.cells, "whole and distinct slicing schedules retain the same exact original rows")
	var cells: Dictionary = initial.duplicate(true)
	var plan: SimThermalFrozenGroups = Groups.compile(cells, flows, 40)
	if plan == null:
		return
	runner.assert_true(plan.apply(3), "the first frozen portion integrates")
	# JSON restore creates fresh row owners and therefore requires compilation.
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(cells, "", true, true))
	var restored: SimThermalFrozenGroups = Groups.compile(decoded, flows, 40)
	runner.assert_true(restored != null, "fresh JSON rows compile a separate plan")
	if restored != null:
		runner.assert_true(plan.apply(4) and restored.apply(4), "both original and freshly compiled owners finish the remaining portion")
		runner.assert_eq(SnapshotValues.normalized(decoded), SnapshotValues.normalized(cells), "no plan-owned Q or clock is required for exact JSON continuation, including complete JSON-normalized metadata")


func _extremes_and_json(runner: Object) -> void:
	var empty: SimThermalFrozenGroups = Groups.compile({}, [], 0)
	runner.assert_true(empty != null and empty.can_settle(MAX_EXACT) and empty.apply(MAX_EXACT), "zero-rate empty fields accept the full safe integer duration")
	var empty_field: SimThermalFrozenGroups = Groups.compile_field({}, [], 0)
	runner.assert_true(empty_field != null and empty_field.can_settle(MAX_EXACT) and empty_field.apply(MAX_EXACT), "the trusted empty field retains the same full safe integer duration")
	var quiet: Dictionary = _cells({"a": MAX_EXACT})
	var quiet_plan: SimThermalFrozenGroups = Groups.compile(quiet, [], MAX_EXACT)
	runner.assert_true(quiet_plan != null and quiet_plan.apply(MAX_EXACT), "a zero-rate original balance needs no artificial 60000ms limit")
	runner.assert_eq(int(quiet.a.energy), MAX_EXACT, "the largest quiet Q stays exact")
	runner.assert_true(_case_error(_cells({"a": MAX_EXACT}), [], MAX_EXACT, MAX_EXACT).is_empty(), "both entries preserve a maximum-duration quiet original balance")
	var leaving: Array = [{"from": "a", "to": "", "rate": MAX_EXACT}]
	var entering: Array = [{"from": "", "to": "a", "rate": MAX_EXACT}]
	for dt: int in [0, 1, 2, MAX_EXACT, MAX_EXACT + 1, -1]:
		var source_error: String = _case_error(_cells({"a": MAX_EXACT}), leaving, MAX_EXACT, dt)
		var sink_error: String = _case_error(_cells({"a": 0}), entering, MAX_EXACT, dt)
		runner.assert_true(source_error.is_empty() and sink_error.is_empty(), "largest source/sink products preflight before any overflow: dt=%d %s %s" % [dt, source_error, sink_error])
	var largest_total: Array = [{"from": "", "to": "a", "rate": MAX_EXACT - 1}, {"from": "", "to": "b", "rate": 1}]
	runner.assert_true(_case_error(_cells({"a": 0, "b": 0}), largest_total, MAX_EXACT, 1).is_empty(), "the largest exact sum of transferred amounts remains feasible")
	@warning_ignore("integer_division")
	var half: int = MAX_EXACT / 2
	var globally_oversized: Array = [{"from": "a", "to": "b", "rate": half}, {"from": "c", "to": "d", "rate": half}]
	var oversized_cells: Dictionary = _cells({"a": MAX_EXACT, "b": 0, "c": MAX_EXACT, "d": 0})
	var oversized: SimThermalFrozenGroups = Groups.compile(oversized_cells, globally_oversized, MAX_EXACT)
	runner.assert_true(oversized != null, "individually legal cells can compile below the total-rate bound")
	if oversized != null:
		var before: Dictionary = oversized_cells.duplicate(true)
		runner.assert_true(not oversized.can_settle(2) and not oversized.apply(2), "the kernel's explicit total-amount bound rejects a globally oversized field even when each endpoint fits")
		runner.assert_eq(oversized_cells, before, "global amount overflow changes no original cell")
	var json: Dictionary = JSON.parse_string('{"cells":{"a":{"energy":8.0,"note":"original"},"b":{"energy":2.0}},"flows":[{"from":"a","to":"b","rate":2.0}]}')
	runner.assert_true(json.cells.a.energy is float and json.flows[0].rate is float, "JSON fixture really exercises integral float values")
	runner.assert_true(_case_error(json.cells, json.flows, 10, 3).is_empty(), "JSON integral floats retain exact per-flow arithmetic")


func _reject(runner: Object, cells: Dictionary, flows: Array, ceiling: int, label: String) -> void:
	# var_to_str also preserves nonfinite fault samples for an immutable-input
	# comparison; numerical NaN equality would otherwise be a false failure.
	var before: String = var_to_str({"cells": cells, "flows": flows})
	runner.assert_true(Groups.compile(cells, flows, ceiling) == null, "group compilation rejects " + label)
	runner.assert_eq(var_to_str({"cells": cells, "flows": flows}), before, "rejecting " + label + " changes neither original rows nor flows")


func _invalid_inputs(runner: Object) -> void:
	var good: Dictionary = _cells({"a": 5, "b": 5})
	var edge: Dictionary = {"from": "a", "to": "b", "rate": 1}
	for ceiling: int in [-1, MAX_EXACT + 1]:
		_reject(runner, good, [edge], ceiling, "an out-of-range ceiling")
	for invalid: Variant in [null, [], "row", {}, {"energy": -1}, {"energy": 11}, {"energy": 1.5},
		{"energy": INF}, {"energy": NAN}, {"energy": true}, {"energy": "5"}]:
		_reject(runner, {"a": invalid}, [], 10, "an invalid original row " + str(invalid))
	for invalid_key: Variant in ["", "@artifact/device", 1, StringName("a")]:
		var cells: Dictionary = {}
		cells[invalid_key] = {"energy": 5}
		_reject(runner, cells, [], 10, "an invalid cell key " + str(invalid_key))
	var readonly: Dictionary = {"energy": 5}
	readonly.make_read_only()
	_reject(runner, {"a": readonly}, [], 10, "a read-only original Q row")
	var aliased: Dictionary = {"energy": 5}
	_reject(runner, {"a": aliased, "b": aliased}, [], 10, "two cell keys sharing one physical Q row")
	# Structurally equal but independently owned rows remain valid originals.
	runner.assert_true(Groups.compile({"a": {"energy": 5}, "b": {"energy": 5}}, [], 10) != null, "equal separate row values are not mistaken for aliases")
	for invalid: Variant in [null, [], "flow", {}, {"from": "a", "to": "b"},
		{"from": 1, "to": "b", "rate": 1}, {"from": "a", "to": "b", "rate": 1, "extra": 0}]:
		_reject(runner, good, [invalid], 10, "an invalid flow shape " + str(invalid))
	for rate: Variant in [0, -1, MAX_EXACT + 1, 0.5, INF, NAN, true, "1"]:
		_reject(runner, good, [{"from": "a", "to": "b", "rate": rate}], 10, "an invalid integer rate " + str(rate))
	for endpoints: Array in [["a", "a"], ["", ""], ["a", "missing"], ["missing", "b"],
		["@artifact/device", "a"], ["a", "@artifact/device"]]:
		_reject(runner, good, [{"from": endpoints[0], "to": endpoints[1], "rate": 1}], 10, "an invalid or device endpoint " + str(endpoints))
	_reject(runner, good, [edge, edge.duplicate(true)], 10, "a duplicate directed edge")
	_reject(runner, good, [{"from": "a", "to": "", "rate": MAX_EXACT}, {"from": "b", "to": "", "rate": 1}], MAX_EXACT, "a total rate above the exact bound")
	for original_q: int in [0, 10]:
		var cells: Dictionary = _cells({"a": original_q})
		var opposing: Array = [{"from": "", "to": "a", "rate": 1}, {"from": "a", "to": "", "rate": 1}]
		var plan: SimThermalFrozenGroups = Groups.compile(cells, opposing, 10)
		if plan == null:
			runner.assert_true(false, "opposing gross rates are a valid compiled graph")
			return
		var before: Dictionary = cells.duplicate(true)
		runner.assert_true(not plan.can_settle(1) and not plan.apply(1), "zero net flow cannot borrow incoming Q or outgoing free capacity")
		runner.assert_eq(cells, before, "failed gross-budget checking changes no original Q")
