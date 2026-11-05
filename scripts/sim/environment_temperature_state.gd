class_name SimEnvironmentTemperatureState
extends RefCounted
## One owner for actual outdoor temperature at explicitly tracked cells.
## Each cell keeps one known target segment; reads do not change its anchor.
## This object holds no clock, source inventory, Q balance, or integral ledger.

const Response = preload("res://scripts/sim/environment_field_response.gd")
const VERSION: int = 1
const PLAN_VERSION: int = 1
const MIN_C: float = -273.15
const MAX_C: float = Response.MAX_ABS_VALUE
const MAX_TIME: int = Response.MAX_TIME
const MAX_AXIS: int = 4096
const MAX_CAPACITY: int = 4_194_304
const MAX_REVISION: int = 9_007_199_254_740_991

var _configured: bool = false
var _size := Vector2i.ZERO
var _capacity: int = 0
var _activation_ms: int = 0
var _last_change_ms: int = 0
var _revision: int = 0
var _cells: Dictionary[Vector2i, RefCounted] = {}
var _issued_plan := WeakRef.new()


func configure(size: Vector2i, capacity: int, activation_ms: int) -> bool:
	if _configured or not _valid_configuration(size, capacity, activation_ms):
		return false
	_size = size
	_capacity = capacity
	_activation_ms = activation_ms
	_last_change_ms = activation_ms
	_revision = 0
	_configured = true
	return true


func actual_at(cell: Vector2i, at_ms: int) -> Dictionary:
	if not _configured:
		return _failure("not_configured")
	if not _inside(cell, _size):
		return _failure("invalid_cell")
	if at_ms < _activation_ms or at_ms > MAX_TIME:
		return _failure("time_out_of_range")
	if not _cells.has(cell):
		return _failure("untracked")
	var response: RefCounted = _cells[cell]
	var anchor: Dictionary = response.to_dict()
	if at_ms < int(anchor.start_ms):
		return _failure("history_unavailable")
	if at_ms > int(anchor.until_ms):
		return _failure("target_boundary")
	var result: Dictionary = response.sample(at_ms, false)
	if not bool(result.get("ok", false)) or not _temperature(result.get("value")):
		return _failure("response_unavailable")
	return {"ok": true, "cell": cell, "at_ms": at_ms, "value_c": float(result.value)}


func prepare_targets(changes: Array[Dictionary], at_ms: int, budget: int) -> Dictionary:
	var checked: Dictionary = _prepare_targets(changes, at_ms, budget)
	if not bool(checked.get("ok", false)):
		return checked
	var proof := PreparedProof.new(checked.rows, at_ms)
	_issued_plan = weakref(proof)
	var plan: Dictionary = {"ok": true, "version": PLAN_VERSION, "owner": get_instance_id(),
		"revision": _revision, "proof": proof, "at_ms": at_ms, "rows": checked.rows}
	plan.make_read_only()
	return plan


func _prepare_targets(changes: Array[Dictionary], at_ms: int, budget: int) -> Dictionary:
	# Complete, canonical transaction plan. An untracked cell requires its real
	# climate initial_c; a tracked cell must not supply an initial override.
	if not _configured:
		return _failure("not_configured")
	if at_ms < _last_change_ms or at_ms > MAX_TIME:
		return _failure("time_out_of_range")
	if budget < 0 or budget > _capacity:
		return _failure("invalid_budget")
	if changes.is_empty():
		return _failure("empty_change")
	if changes.size() > budget:
		return _failure("pending")
	if _revision >= MAX_REVISION:
		return _failure("revision_exhausted")
	var seen: Dictionary[Vector2i, bool] = {}
	var rows: Array[Dictionary] = []
	var new_count: int = 0
	for change: Dictionary in changes:
		var has_initial: bool = change.has("initial_c")
		var fields: Array[String] = ["cell", "target_c", "target_per_ms", "until_ms", "tau_ms"]
		if has_initial:
			fields.append("initial_c")
		if not _keys(change, fields) or not change.cell is Vector2i:
			return _failure("change_shape")
		var cell: Vector2i = change.cell
		if not _inside(cell, _size) or seen.has(cell):
			return _failure("invalid_or_duplicate_cell")
		seen[cell] = true
		var tracked: bool = _cells.has(cell)
		if has_initial == tracked:
			return _failure("initial_mismatch")
		var initial: float
		if tracked:
			var previous: Dictionary = actual_at(cell, at_ms)
			if not bool(previous.get("ok", false)):
				return _failure(str(previous.get("reason", "response_unavailable")))
			initial = float(previous.value_c)
		else:
			if not _temperature(change.initial_c):
				return _failure("initial_out_of_range")
			initial = float(change.initial_c)
			new_count += 1
			if new_count > _capacity - _cells.size():
				return _failure("capacity")
		if not _temperature(change.target_c) or not _number(change.target_per_ms) or not _integer(change.until_ms, at_ms, MAX_TIME) or not _integer(change.tau_ms, 1, Response.MAX_TAU_MS):
			return _failure("target_invalid")
		var response := Response.new()
		if not response.configure(at_ms, int(change.until_ms), initial, float(change.target_c), float(change.target_per_ms), int(change.tau_ms)) or not _physical_response(response.to_dict()):
			return _failure("target_invalid")
		var state: Dictionary = response.to_dict()
		state.make_read_only()
		var row: Dictionary = {"cell": cell, "response": state}
		row.make_read_only()
		rows.append(row)
	rows.sort_custom(_row_before)
	rows.make_read_only()
	return {"ok": true, "rows": rows}


func commit(plan: Variant) -> Dictionary:
	if not _configured:
		return _failure("not_configured")
	if not _keys(plan, ["ok", "version", "owner", "revision", "proof", "at_ms", "rows"]) or not plan.is_read_only() or not plan.ok is bool or not plan.ok or not plan.version is int or plan.version != PLAN_VERSION or not plan.owner is int or plan.owner != get_instance_id() or not plan.revision is int or plan.revision != _revision:
		return _failure("invalid_or_stale_plan")
	if not plan.at_ms is int or plan.at_ms < _last_change_ms or plan.at_ms > MAX_TIME or not plan.rows is Array or not plan.rows.is_read_only() or plan.rows.is_empty() or plan.rows.size() > _capacity or _revision >= MAX_REVISION:
		return _failure("invalid_or_stale_plan")
	if not plan.proof is PreparedProof or not is_same(_issued_plan.get_ref(), plan.proof) or not plan.proof.matches(plan.rows, int(plan.at_ms)):
		return _failure("invalid_or_stale_plan")
	# Rebuild a complete candidate, including normal preparation, rather than
	# trusting caller-owned plan data or a claimed initial value. This verifies
	# identity/revision, unique rows, time, capacity and old actual continuity.
	var changes: Array[Dictionary] = []
	var prior := Vector2i(-1, -1)
	for row: Variant in plan.rows:
		if not _keys(row, ["cell", "response"]) or not row.is_read_only() or not row.cell is Vector2i or not _inside(row.cell, _size) or not _after(row.cell, prior) or not row.response is Dictionary or not row.response.is_read_only():
			return _failure("invalid_or_stale_plan")
		var candidate := Response.new()
		if not candidate.restore(row.response):
			return _failure("invalid_or_stale_plan")
		var state: Dictionary = candidate.to_dict()
		if not _physical_response(state) or int(state.start_ms) != int(plan.at_ms):
			return _failure("invalid_or_stale_plan")
		var cell: Vector2i = row.cell
		var change: Dictionary = {"cell": cell, "target_c": float(state.target_value),
			"target_per_ms": float(state.target_per_ms), "until_ms": int(state.until_ms), "tau_ms": int(state.tau_ms)}
		if not _cells.has(cell):
			change["initial_c"] = float(state.initial_value)
		changes.append(change)
		prior = cell
	var checked: Dictionary = _prepare_targets(changes, int(plan.at_ms), changes.size())
	if not bool(checked.get("ok", false)) or not _same_rows(plan.rows, checked.rows):
		return _failure("invalid_or_stale_plan")
	var replacements: Dictionary[Vector2i, RefCounted] = {}
	for row: Dictionary in checked.rows:
		var candidate := Response.new()
		if not candidate.restore(row.response):
			return _failure("invalid_or_stale_plan")
		replacements[row.cell] = candidate
	# All parsing and validation has finished; publication cannot partially fail.
	for cell: Vector2i in replacements:
		_cells[cell] = replacements[cell]
	_last_change_ms = int(plan.at_ms)
	_revision += 1
	_issued_plan = WeakRef.new()
	return {"ok": true, "revision": _revision, "changed": replacements.size(), "at_ms": _last_change_ms}


func next_boundary_ms() -> int:
	if not _configured or _cells.is_empty():
		return -1
	var boundary: int = MAX_TIME
	for response: RefCounted in _cells.values():
		boundary = mini(boundary, int(response.to_dict().until_ms))
	return boundary


func snapshot() -> Dictionary:
	if not _configured:
		return {}
	var cells: Array[Vector2i] = []
	for cell: Vector2i in _cells:
		cells.append(cell)
	cells.sort_custom(_cell_before)
	var rows: Array[Dictionary] = []
	for cell: Vector2i in cells:
		rows.append({"cell": [cell.x, cell.y], "response": _cells[cell].to_dict()})
	return {"version": VERSION, "size": [_size.x, _size.y], "capacity": _capacity,
		"activation_ms": _activation_ms, "last_change_ms": _last_change_ms,
		"revision": _revision, "cells": rows}


func restore(data: Variant) -> bool:
	# Construct every response in isolation; no field is assigned until all
	# structure, coordinates, response bounds, and shared times are validated.
	if not _keys(data, ["version", "size", "capacity", "activation_ms", "last_change_ms", "revision", "cells"]) or not _integer(data.version, VERSION, VERSION) or not data["size"] is Array or data["size"].size() != 2:
		return false
	if not _integer(data["size"][0], 1, MAX_AXIS) or not _integer(data["size"][1], 1, MAX_AXIS) or not _integer(data.capacity, 1, MAX_CAPACITY) or not _integer(data.activation_ms, 0, MAX_TIME) or not _integer(data.last_change_ms, int(data.activation_ms), MAX_TIME) or not _integer(data.revision, 0, MAX_REVISION):
		return false
	var next_size := Vector2i(int(data["size"][0]), int(data["size"][1]))
	var capacity: int = int(data.capacity)
	if not _valid_configuration(next_size, capacity, int(data.activation_ms)) or not data.cells is Array or data.cells.size() > capacity:
		return false
	var revision: int = int(data.revision)
	var activation: int = int(data.activation_ms)
	var last_change: int = int(data.last_change_ms)
	if revision == 0 and (not data.cells.is_empty() or last_change != activation) or revision > 0 and data.cells.is_empty():
		return false
	var candidate: Dictionary[Vector2i, RefCounted] = {}
	var prior := Vector2i(-1, -1)
	var newest: int = activation
	for row: Variant in data.cells:
		if not _keys(row, ["cell", "response"]) or not row.cell is Array or row.cell.size() != 2 or not _integer(row.cell[0], 0, next_size.x - 1) or not _integer(row.cell[1], 0, next_size.y - 1):
			return false
		var cell := Vector2i(int(row.cell[0]), int(row.cell[1]))
		if not _after(cell, prior):
			return false
		var response := Response.new()
		if not response.restore(row.response):
			return false
		var state: Dictionary = response.to_dict()
		if not _physical_response(state) or int(state.start_ms) < activation or int(state.start_ms) > last_change:
			return false
		newest = maxi(newest, int(state.start_ms))
		candidate[cell] = response
		prior = cell
	if newest != last_change:
		return false
	_size = next_size
	_capacity = capacity
	_activation_ms = activation
	_last_change_ms = last_change
	_revision = revision
	_cells = candidate
	_configured = true
	# A plan prepared before restore cannot become valid merely because a
	# snapshot restored the same numeric revision and coordinates.
	_issued_plan = WeakRef.new()
	return true


static func _valid_configuration(size: Vector2i, capacity: int, activation_ms: int) -> bool:
	return size.x >= 1 and size.x <= MAX_AXIS and size.y >= 1 and size.y <= MAX_AXIS and capacity >= 1 and capacity <= MAX_CAPACITY and capacity <= size.x * size.y and activation_ms >= 0 and activation_ms <= MAX_TIME


static func _physical_response(state: Dictionary) -> bool:
	if not _temperature(state.get("initial_value")) or not _temperature(state.get("target_value")):
		return false
	var endpoint: float = float(state.target_value) + float(state.target_per_ms) * float(int(state.until_ms) - int(state.start_ms))
	return _temperature(endpoint)


static func _temperature(value: Variant) -> bool:
	return _number(value) and float(value) >= MIN_C and float(value) <= MAX_C


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	if not _number(value):
		return false
	var number: float = float(value)
	return number >= float(minimum) and number <= float(maximum) and floor(number) == number


static func _keys(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func _inside(cell: Vector2i, size: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


static func _after(cell: Vector2i, previous: Vector2i) -> bool:
	return cell.y > previous.y or cell.y == previous.y and cell.x > previous.x


static func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or a.y == b.y and a.x < b.x


static func _row_before(a: Dictionary, b: Dictionary) -> bool:
	return _cell_before(a.cell, b.cell)


static func _same_rows(first: Array, second: Array) -> bool:
	if first.size() != second.size():
		return false
	for index: int in first.size():
		if first[index].cell != second[index].cell or first[index].response != second[index].response:
			return false
	return true


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


class PreparedProof:
	extends RefCounted
	var _rows: Array
	var _at_ms: int

	func _init(rows: Array, at_ms: int) -> void:
		_rows = rows
		_at_ms = at_ms

	func matches(rows: Array, at_ms: int) -> bool:
		return is_same(_rows, rows) and _at_ms == at_ms
