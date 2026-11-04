class_name SimThermalHistory
extends RefCounted
## Derive bounded historical source coverage from saved source records alone.
## This is evidence about where a source could have allocated a cell, not a
## retained heat balance, a lifecycle record, or permission to discard live Q.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const MAX_INTEGER: int = 9007199254740991
const SWITCH_KEYS: Array[String] = ["action", "actor", "object", "at_ms", "region", "container", "cell", "enabled"]


static func source_coverage(heat: SimLocalHeat, data: Dictionary) -> Dictionary:
	# Candidate validation elsewhere proves original source events, device
	# ownership, switch sequencing and balances. Here we only validate record
	# shape/time and derive coverage; do not inspect live cells, flows, Q,
	# geometry, a custom background, or either world's clock.
	if heat == null or not SimLocalHeat.valid_definitions(heat.definitions):
		return _failure("invalid_heat")
	if not Shape.count(data.get("activation_ms"), 0, MAX_INTEGER):
		return _failure("invalid_time")
	var activation: int = int(data.activation_ms)
	if not Shape.count(data.get("model_started_ms"), activation, MAX_INTEGER):
		return _failure("invalid_time")
	var model_start: int = int(data.model_started_ms)
	if not Shape.count(data.get("segment_started_ms"), model_start, MAX_INTEGER):
		return _failure("invalid_time")
	var segment: int = int(data.segment_started_ms)
	if not Shape.count(data.get("last_ms"), segment, MAX_INTEGER):
		return _failure("invalid_time")
	if not data.get("receipts") is Dictionary or not data.get("device_switches") is Dictionary:
		return _failure("invalid_sources")
	var allocations: Dictionary = {}
	var before_cells: Dictionary = {}
	var through_cells: Dictionary = {}
	var receipt_sum: int = 0
	var before_input: int = 0
	var through_input: int = 0
	var limit: int = int(heat.definitions.max_cells)
	for action: Variant in data.receipts:
		var receipt: Variant = data.receipts[action]
		if not action is String or not heat._valid_receipt(receipt, activation) or action != receipt.action or int(receipt.at_ms) > segment:
			return _failure("invalid_receipt")
		var amount: int = int(receipt.amount)
		if not _can_add(receipt_sum, amount):
			return _failure("sum_overflow")
		receipt_sum += amount
		var at_ms: int = int(receipt.at_ms)
		if at_ms < model_start:
			if not _can_add(before_input, amount):
				return _failure("sum_overflow")
			before_input += amount
		if at_ms <= model_start:
			if not _can_add(through_input, amount):
				return _failure("sum_overflow")
			through_input += amount
		var center := Vector2i(int(receipt.cell[0]), int(receipt.cell[1]))
		if not _include_patch(heat, center, at_ms, model_start, true, limit, allocations, before_cells, through_cells):
			return _failure("coverage_budget")
	for action: Variant in data.device_switches:
		var change: Variant = data.device_switches[action]
		if not _valid_switch(heat, action, change, model_start, segment):
			return _failure("invalid_switch")
		if bool(change.enabled):
			var center := Vector2i(int(change.cell[0]), int(change.cell[1]))
			if not _include_patch(heat, center, int(change.at_ms), model_start, false, limit, allocations, before_cells, through_cells):
				return _failure("coverage_budget")
	return {"supported": true, "allocations": allocations,
		"before_model_cells": before_cells, "through_model_cells": through_cells,
		"receipt_sum": receipt_sum, "before_input": before_input, "through_input": through_input}


static func valid_legacy_limits(data: Dictionary, coverage: Dictionary, pulse: int) -> bool:
	# Preserve the original pre-conversion proof: same-millisecond pulse receipts
	# can lie on either side of conversion. Device enables may allocate cells at
	# that instant, but cannot enlarge the old pulse-only field's evidence.
	if not Shape.count(pulse, 1, MAX_INTEGER) or not Shape.count(data.get("activation_ms"), 0, MAX_INTEGER):
		return false
	var activation: int = int(data.activation_ms)
	if not Shape.count(data.get("model_started_ms"), activation, MAX_INTEGER) or not data.get("legacy_limits") is Dictionary:
		return false
	var model_start: int = int(data.model_started_ms)
	if coverage.get("supported") != true or not coverage.get("supported") is bool or not coverage.get("allocations") is Dictionary or not coverage.get("before_model_cells") is Dictionary or not coverage.get("through_model_cells") is Dictionary:
		return false
	if not Shape.count(coverage.get("before_input"), 0, MAX_INTEGER) or not Shape.count(coverage.get("through_input"), int(coverage.before_input), MAX_INTEGER) or not Shape.count(coverage.get("receipt_sum"), int(coverage.through_input), MAX_INTEGER):
		return false
	var allocations: Dictionary = coverage.allocations
	var before_cells: Dictionary = coverage.before_model_cells
	var through_cells: Dictionary = coverage.through_model_cells
	for key: Variant in through_cells:
		if not SimInventory._nonempty(key) or not through_cells[key] is bool or not through_cells[key] or not Shape.count(allocations.get(key), model_start, model_start):
			return false
	for key: Variant in before_cells:
		if not SimInventory._nonempty(key) or not before_cells[key] is bool or not before_cells[key] or not through_cells.has(key):
			return false
	var limits: Dictionary = data.legacy_limits
	var before_input: int = int(coverage.before_input)
	var through_input: int = int(coverage.through_input)
	if limits.is_empty():
		# A fresh model cannot claim sources from an earlier model epoch.
		return model_start == activation and before_input == 0
	if not Shape.keys(limits, ["at_ms", "input_energy", "cells"]) or not Shape.count(limits.at_ms, model_start, model_start) or not Shape.count(limits.input_energy, before_input, through_input) or not limits.cells is Array:
		return false
	if int(limits.input_energy) % pulse != 0 or limits.cells.size() > through_cells.size():
		return false
	var old_cells: Dictionary = {}
	var previous: String = ""
	for key: Variant in limits.cells:
		if not key is String or key.is_empty() or (not previous.is_empty() and key <= previous) or not through_cells.has(key) or not Shape.count(allocations.get(key), model_start, model_start):
			return false
		old_cells[key] = true
		previous = key
	for key: String in before_cells:
		if not old_cells.has(key):
			return false
	# The already-validated converter is the only evidence for exact old Q.
	# Same-ms sources cannot be ordered retrospectively by this projection.
	return (int(limits.input_energy) == 0) == old_cells.is_empty()


static func _valid_switch(heat: SimLocalHeat, action: Variant, change: Variant, model_start: int, segment: int) -> bool:
	return action is String and SimInventory._nonempty(action) and Shape.keys(change, SWITCH_KEYS) and action == change.action and SimInventory._nonempty(change.actor) and SimInventory._nonempty(change.object) and SimInventory._nonempty(change.region) and SimInventory._nonempty(change.container) and heat._cell_array(change.cell) and change.enabled is bool and Shape.count(change.at_ms, model_start, segment)


static func _include_patch(heat: SimLocalHeat, center: Vector2i, at_ms: int, model_start: int, pulse: bool, limit: int, allocations: Dictionary, before_cells: Dictionary, through_cells: Dictionary) -> bool:
	var allocated_at: int = maxi(model_start, at_ms)
	for point: Vector2i in heat._patch(center):
		var key: String = heat._key(point)
		if not allocations.has(key):
			if allocations.size() >= limit:
				return false
			allocations[key] = allocated_at
		else:
			allocations[key] = mini(int(allocations[key]), allocated_at)
		# Old conversion boundaries were defined by pulse receipts, not later
		# thermal-device records at the same millisecond.
		if pulse and at_ms < model_start:
			before_cells[key] = true
		if pulse and at_ms <= model_start:
			through_cells[key] = true
	return true


static func _can_add(total: int, amount: int) -> bool:
	return total >= 0 and amount >= 0 and amount <= MAX_INTEGER and total <= MAX_INTEGER - amount


static func _failure(reason: String) -> Dictionary:
	# No partial coverage, sums or cell evidence escapes on failure.
	return {"supported": false, "reason": reason}
