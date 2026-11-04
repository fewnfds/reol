extends RefCounted
## The archived v1 law is checked without making it a running heat owner.

const LegacyHeat = preload("res://scripts/persistence/legacy_heat_v1.gd")
const HEAT_PATH: String = "res://data/definitions/local_heat.json"
const CELL := Vector2i(100, 100)
const AMOUNT: int = 180000000


class ArtifactLog extends RefCounted:
	var events: Array[Dictionary] = []
	var allowed: bool = true

	func has_capability(_id: String, capability: String) -> bool:
		return allowed and capability == "heat_storage"


class Authority extends RefCounted:
	var elapsed_ms: int = 0
	var artifacts := ArtifactLog.new()
	var roofed: bool = false
	var barriers: Dictionary = {}

	func roof(_cell: Vector2i) -> bool:
		return roofed

	func barrier(cell: Vector2i) -> String:
		return str(barriers.get("%d,%d" % [cell.x, cell.y], "open"))


func run(runner: Object) -> void:
	_archived_empty_field(runner)
	_frozen_segment_and_rejections(runner)
	_older_sample_and_same_time_source(runner)
	print("SCENARIO legacy heat v1: archived rules and field, original frozen geometry, exact source receipts, old sampled offsets and read-only projections")


func _legacy_rules() -> Dictionary:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/compatibility/content_db_v42.json"))
	return source.documents[HEAT_PATH].duplicate(true)


func _configure(authority: Authority, rules: Dictionary) -> RefCounted:
	var validator := LegacyHeat.new()
	if not validator.configure(authority, rules):
		return null
	validator.set_geometry(Callable(authority, "roof"), Callable(authority, "barrier"))
	return validator


func _archived_empty_field(runner: Object) -> void:
	# This is the unmodified original fixture and its recorded v42 rules, not
	# today's runtime definitions. No warmed events exist in this archive.
	var archive: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/session_v42_exchange.json"))
	var old_world: Dictionary = archive.continuity.world
	var original: Dictionary = old_world.local_heat
	var authority := Authority.new()
	authority.elapsed_ms = int(old_world.elapsed_ms)
	var validator: RefCounted = _configure(authority, _legacy_rules())
	runner.assert_true(validator != null, "the archived v1 content definitions configure the migration validator")
	if validator == null:
		return
	var before: String = _json(original)
	runner.assert_true(validator.restore(original), "the actual v42 archived heat field passes its original v1 checks")
	runner.assert_eq(_json(original), before, "validation does not modify the historical fixture")
	runner.assert_eq(_json(validator.to_dict()), before, "accepted JSON values preserve the complete old thermal state")
	runner.assert_eq(validator.project_tenths(CELL, authority.elapsed_ms), {"supported": true, "value": 0}, "an unallocated old cell projects the original zero offset")
	runner.assert_true(not validator.has_visible_offsets(false) and not validator.has_visible_offsets(true), "an empty archived field does not invent current or historical warmth")
	var bad_rules: Dictionary = _legacy_rules()
	bad_rules.conductance.open = int(bad_rules.coefficient_scale)
	runner.assert_true(not LegacyHeat.valid_definitions(bad_rules), "legacy coefficients cannot overdraw a frozen step")
	bad_rules = _legacy_rules()
	bad_rules.version = 2
	runner.assert_true(not LegacyHeat.valid_definitions(bad_rules), "a new rule version is never silently interpreted as v1")


func _frozen_segment_and_rejections(runner: Object) -> void:
	var rules: Dictionary = _legacy_rules()
	rules.source_radius = 0
	var authority := Authority.new()
	authority.elapsed_ms = 61000
	var receipt: Dictionary = _receipt("warm:1", 60000)
	authority.artifacts.events.append(_event(receipt))
	# Original v1: a 60,000-ms sample occurs before the same-time source.
	# At its open, uncovered one-cell patch the old bath slope is 10,800/ms:
	# 3,600 from atmosphere and 1,800 through each of four outside edges.
	var candidate: Dictionary = {
		"version": 1, "rules_version": 1, "activation_ms": 0,
		"last_ms": 61000, "segment_started_ms": 60000,
		"cells": {"100,100": {"cell": [100, 100], "energy": 169200000}},
		"flows": [{"from": "100,100", "to": "", "rate": 10800}],
		"input_energy": AMOUNT, "loss_energy": 10800000,
		"receipts": {"warm:1": receipt}, "last_sample_ms": 60000,
		"last_sample_cells": {}, "last_sample_input": 0, "last_sample_loss": 0,
	}
	var without_geometry := LegacyHeat.new()
	runner.assert_true(without_geometry.configure(authority, rules), "legacy definitions can be checked before geometry is bound")
	runner.assert_true(not without_geometry.restore(candidate), "a missing construction candidate cannot silently default to open space")
	var validator: RefCounted = _configure(authority, rules)
	runner.assert_true(validator != null, "a bounded archived v1 definition can be configured")
	if validator == null:
		return
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(candidate))
	var untouched: String = _json(decoded)
	runner.assert_true(validator.restore(decoded), "the original nonempty v1 slope and matching warmed event validate")
	runner.assert_eq(_json(decoded), untouched, "normalizing accepted whole JSON numbers never edits the input")
	var saved: String = _json(validator.to_dict())
	runner.assert_eq(validator.project_tenths(CELL, 60000), {"supported": true, "value": 180}, "reverse projection reaches the stored original segment anchor")
	runner.assert_eq(validator.project_tenths(CELL, 61000), {"supported": true, "value": 169}, "current projection reads the saved source energy")
	runner.assert_eq(validator.current_tenths(CELL), 169, "the candidate environment reads the same accepted instant without settling time")
	runner.assert_eq(validator.project_tenths(CELL, 70000), {"supported": true, "value": 72}, "the old frozen slope is readable through its inclusive next boundary")
	var unsupported: Dictionary = validator.project_tenths(CELL, 70001)
	runner.assert_true(not bool(unsupported.supported) and unsupported.reason == "beyond_boundary" and not unsupported.has("value"), "an unknown future has a reason and never supplies a guessed offset")
	unsupported = validator.project_tenths(CELL, 59999)
	runner.assert_true(not bool(unsupported.supported) and unsupported.reason == "history_unavailable" and not unsupported.has("value"), "a prior segment cannot be reconstructed from the current slope")
	runner.assert_eq(validator.sample_tenths(CELL, 60000), 0, "the same-millisecond source does not rewrite the prior empty sample")
	runner.assert_true(validator.has_visible_offsets(false) and not validator.has_visible_offsets(true), "current warmth and the earlier sample stay distinct")
	runner.assert_eq(validator.maximum_offset_tenths(), 1000000, "the offset upper bound comes from the archived capacity and cell limit")
	runner.assert_eq(validator.minimum_offset_tenths(), 0, "an old v1 field has no negative offset")
	var exposed_cells: Dictionary = validator.cells
	exposed_cells["100,100"].energy = 0
	var exposed_rules: Dictionary = validator.definitions
	exposed_rules.capacity_per_tenth = 1
	var exposed_state: Dictionary = validator.to_dict()
	exposed_state.receipts.clear()
	runner.assert_eq(_json(validator.to_dict()), saved, "changing returned dictionaries cannot mutate the validated record")
	runner.assert_eq(int(validator.definitions.capacity_per_tenth), 1000000, "changing a returned rule view cannot change saved rules")
	for method: String in ["deposit", "advance_to_ms", "settle_at_ms", "mark_sample", "refresh_geometry"]:
		runner.assert_true(not validator.has_method(method), "the migration reader exposes no old running heat operation: " + method)

	var bad: Dictionary = candidate.duplicate(true)
	bad.cells["100,100"].energy += 1
	_reject(runner, validator, bad, saved, "forged energy breaks the original conserved total")
	bad = candidate.duplicate(true)
	bad.flows[0].rate += 1
	_reject(runner, validator, bad, saved, "a forged frozen slope cannot pass its reconstructed anchor")
	bad = candidate.duplicate(true)
	bad.receipts["warm:1"].amount += 1
	_reject(runner, validator, bad, saved, "a source amount must match the archived pulse and event")
	bad = candidate.duplicate(true)
	bad.receipts.clear()
	_reject(runner, validator, bad, saved, "a warmed source cannot lose its unique receipt")
	bad = candidate.duplicate(true)
	bad.cells["101,100"] = {"cell": [101, 100], "energy": 0}
	_reject(runner, validator, bad, saved, "an unrelated cold cell is not part of the original source patch")
	bad = candidate.duplicate(true)
	bad.last_sample_cells["100,100"] = 1
	_reject(runner, validator, bad, saved, "the previous sample must also conserve its own original ledger")
	authority.artifacts.events[0].heat_amount -= 1
	_reject(runner, validator, candidate, saved, "the original v7 warmed event must match its receipt amount")
	authority.artifacts.events[0].heat_amount = AMOUNT
	authority.artifacts.allowed = false
	_reject(runner, validator, candidate, saved, "a receipt must name an artifact with the actual heat capability")
	authority.artifacts.allowed = true
	authority.artifacts.events.append(_event(_receipt("warm:missing", 60000)))
	_reject(runner, validator, candidate, saved, "a real warmed event also requires the reverse receipt")
	authority.artifacts.events.pop_back()
	authority.roofed = true
	_reject(runner, validator, candidate, saved, "the actual roof changes the old frozen bath slope")
	authority.roofed = false
	authority.barriers["100,100"] = "wall"
	_reject(runner, validator, candidate, saved, "the actual wall changes the old frozen boundary slope")
	authority.barriers.clear()
	runner.assert_true(validator.restore(candidate), "the original candidate still validates after restoring its original context")
	validator.set_geometry(Callable(authority, "roof"), Callable(authority, "barrier"))
	runner.assert_true(validator.to_dict().is_empty(), "replacing a geometry context invalidates earlier validation rather than refreezing old heat")


func _older_sample_and_same_time_source(runner: Object) -> void:
	var rules: Dictionary = _legacy_rules()
	rules.source_radius = 0
	for side: String in rules.conductance:
		rules.conductance[side] = 0
	rules.bath_loss.roofed = 0
	rules.bath_loss.unroofed = 0
	var authority := Authority.new()
	authority.elapsed_ms = 61000
	var first: Dictionary = _receipt("warm:1", 0)
	var second: Dictionary = _receipt("warm:2", 60000)
	authority.artifacts.events.append(_event(first))
	authority.artifacts.events.append(_event(second))
	var candidate: Dictionary = {
		"version": 1, "rules_version": 1, "activation_ms": 0,
		"last_ms": 61000, "segment_started_ms": 61000,
		"cells": {"100,100": {"cell": [100, 100], "energy": 360000000}},
		"flows": [], "input_energy": 360000000, "loss_energy": 0,
		"receipts": {"warm:1": first, "warm:2": second}, "last_sample_ms": 60000,
		"last_sample_cells": {"100,100": AMOUNT}, "last_sample_input": AMOUNT, "last_sample_loss": 0,
	}
	var validator: RefCounted = _configure(authority, rules)
	if validator == null:
		runner.assert_true(false, "the insulating legacy fixture has valid definitions")
		return
	runner.assert_true(validator.restore(candidate), "two old receipts and the earlier pre-source sample validate together")
	runner.assert_eq(validator.sample_tenths(CELL, 60000), 180, "historical projection preserves the earlier observed offset")
	runner.assert_eq(validator.sample_tenths(CELL, 59999), 0, "an unavailable old sample is never filled from current heat")
	runner.assert_eq(validator.project_tenths(CELL, 61000), {"supported": true, "value": 360}, "the later source affects the real current field")
	runner.assert_true(validator.has_visible_offsets(true), "the nonzero historical sample remains independently visible")
	var saved: String = _json(validator.to_dict())
	var bad: Dictionary = candidate.duplicate(true)
	bad.last_sample_cells["100,100"] += 1
	_reject(runner, validator, bad, saved, "an altered historical offset is not repriced from current energy")
	bad = candidate.duplicate(true)
	bad.last_sample_cells["101,100"] = 1
	_reject(runner, validator, bad, saved, "a historical sample cannot name a cell outside the original allocated patch")


func _receipt(action: String, at_ms: int) -> Dictionary:
	return {"action": action, "actor": "player", "object": "warm_stone", "at_ms": at_ms, "cell": [CELL.x, CELL.y], "amount": AMOUNT}


func _event(receipt: Dictionary) -> Dictionary:
	return {"kind": "warmed", "action": receipt.action, "actor": receipt.actor, "object": receipt.object, "at_ms": receipt.at_ms, "cell": receipt.cell.duplicate(), "heat_amount": receipt.amount}


func _reject(runner: Object, validator: RefCounted, bad: Dictionary, saved: String, label: String) -> void:
	runner.assert_true(not validator.restore(bad), label)
	runner.assert_eq(_json(validator.to_dict()), saved, "rejected v1 candidate leaves the previous accepted copy unchanged")


func _json(value: Dictionary) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
