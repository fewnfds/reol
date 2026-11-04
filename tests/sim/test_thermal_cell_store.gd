extends RefCounted
## Exact Q representation tests; terrain and real heat integration are separate.

const Store = preload("res://scripts/sim/thermal_cell_store.gd")
const FIRST := Vector2i(100, 100)
const SECOND := Vector2i(120, 100)
const MAX_Q: int = 1000
# Six deliberately different values, specified independently of the store's
# orbit function: center, adjacent axes, diagonals, outer axes, sides, corners.
const OFFSETS: Array = [
	[50, 40, 30, 40, 50],
	[40, 20, 10, 20, 40],
	[30, 10, 0, 10, 30],
	[40, 20, 10, 20, 40],
	[50, 40, 30, 40, 50]]


func run(runner: Object) -> void:
	_projection_and_queries(runner)
	_symmetric_deltas(runner)
	_asymmetric_deltas(runner)
	_atomic_delta_rejection(runner)
	_compaction_refusals(runner)
	_two_patches(runner)
	_single_add_and_replacement(runner)
	_frozen_execution(runner)
	print("SCENARIO thermal cell store: unique orbit Q, exact projections, bounded atomic deltas, independent expansion and safe compaction")


func _frozen_execution(runner: Object) -> void:
	var expected: Dictionary = _rows(FIRST)
	var flows: Array = []
	for key: String in expected:
		flows.append({"from": "", "to": key, "rate": 3})
		flows.append({"from": key, "to": "", "rate": 2})
	var store: SimThermalCellStore = _single(expected, flows)
	runner.assert_true(store.frozen_ready(), "compressed slopes compile without a Q snapshot")
	runner.assert_eq(store.ambient_in_rate(), 75, "bath incoming retains all 25 original flows")
	runner.assert_eq(store.ambient_out_rate(), 50, "bath outgoing is not replaced by a net flow")
	var before: Dictionary = store.materialize()
	runner.assert_true(not store.can_advance(-1, MAX_Q) and not store.advance(100, MAX_Q), "negative time and old-state outflow overdraw are refused")
	runner.assert_eq(store.materialize(), before, "rejected frozen advance changes no Q or representation")
	runner.assert_true(store.frozen_ready(), "refused advance preserves its valid frozen plan")
	runner.assert_true(not store.apply_deltas({"100,100": -1001}, MAX_Q), "an invalid external mutation is refused")
	runner.assert_true(store.frozen_ready(), "refused external mutation preserves the accepted rates")
	runner.assert_true(store.advance(3, MAX_Q) and store.advance(4, MAX_Q), "frozen slopes support sequential subdivisions")
	for key: String in expected:
		expected[key].energy = int(expected[key].energy) + 7
	_check(runner, store, expected, 6, "seven milliseconds update each single-cell orbit Q exactly once")
	runner.assert_true(store.can_advance(0, MAX_Q), "zero elapsed time leaves the same plan usable")
	store.add_energy("100,100", 1)
	runner.assert_true(not store.frozen_ready(), "actual source mutation invalidates the previous slopes")


func _rows(center: Vector2i, base: int = 100) -> Dictionary:
	var rows: Dictionary = {}
	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			var point: Vector2i = center + Vector2i(x, y)
			rows[_key(point)] = {"cell": [point.x, point.y],
				"energy": base + int(OFFSETS[y + 2][x + 2]),
				"allocated_ms": 137, "baseline_energy": 80}
	return rows


func _key(point: Vector2i) -> String:
	return "%d,%d" % [point.x, point.y]


func _single(rows: Dictionary, flows: Array = []) -> SimThermalCellStore:
	var centers: Array[Vector2i] = [FIRST]
	var store := Store.new()
	store.replace_fine(rows.duplicate(true))
	store.compact(centers, flows, MAX_Q)
	return store


func _sum(rows: Dictionary) -> int:
	var result: int = 0
	for row: Dictionary in rows.values():
		result += int(row.energy)
	return result


func _check(runner: Object, store: SimThermalCellStore, expected: Dictionary, slots: int, label: String) -> void:
	runner.assert_eq(store.count(), expected.size(), label + " preserves the exact logical cell count")
	runner.assert_eq(store.slot_count(), slots, label + " has the expected number of owned Q slots")
	var projected: Dictionary = store.materialize()
	runner.assert_eq(projected, expected, label + " preserves every cell's Q and allocation metadata")
	runner.assert_eq(_sum(projected), _sum(expected), label + " preserves the full physical Q total")


func _projection_and_queries(runner: Object) -> void:
	var expected: Dictionary = _rows(FIRST)
	var store: SimThermalCellStore = _single(expected)
	_check(runner, store, expected, 6, "an isolated symmetric 5x5 patch")
	runner.assert_eq(store.fine.size(), 0, "all 25 original fine rows surrender ownership after compression")
	var representatives: Dictionary = {"100,100": 100, "101,100": 110, "101,101": 120,
		"102,100": 130, "102,101": 140, "102,102": 150}
	for key: String in representatives:
		runner.assert_eq(store.energy_at(key), representatives[key], "a distinct orbit has the expected single-cell Q at " + key)
	var keys: Array[String] = store.keys()
	keys.sort()
	var expected_keys: Array = expected.keys()
	expected_keys.sort()
	runner.assert_eq(keys, expected_keys, "keys enumerate all 25 physical coordinates exactly once")
	for key: String in expected:
		runner.assert_true(store.has(key), "the compressed field still has " + key)
		runner.assert_eq(store.row(key), expected[key], "one-row projection preserves every field at " + key)
		runner.assert_eq(store.energy_at(key), int(expected[key].energy), "direct Q lookup agrees with the original at " + key)
	runner.assert_true(not store.has("400,400"), "an unallocated coordinate remains absent")
	runner.assert_true(store.row("400,400").is_empty(), "a missing coordinate has no fabricated row")
	runner.assert_eq(store.energy_at("400,400", -37), -37, "a missing Q uses the caller's fallback")
	keys.clear()
	var one_row: Dictionary = store.row("101,100")
	one_row.energy = 999
	one_row.cell[0] = 999
	var projection: Dictionary = store.materialize()
	projection["101,100"].energy = 998
	projection["101,100"].cell[1] = 998
	_check(runner, store, expected, 6, "queries and edits to detached compressed projections")
	runner.assert_eq(store.keys().size(), 25, "editing the returned key array cannot change membership")
	store.expand_all()
	_check(runner, store, expected, 25, "explicit expansion of a compressed patch")
	store.expand_all()
	_check(runner, store, expected, 25, "repeated expansion")


func _symmetric_deltas(runner: Object) -> void:
	var expected: Dictionary = _rows(FIRST)
	var store: SimThermalCellStore = _single(expected)
	var original_total: int = _sum(expected)
	var changes: Dictionary = {}
	var added: int = 0
	for key: String in expected:
		@warning_ignore("integer_division")
		var delta: int = (int(expected[key].energy) - 100) / 10 - 2
		changes[key] = delta
		added += delta
		expected[key].energy = int(expected[key].energy) + delta
	runner.assert_true(store.apply_deltas(changes, MAX_Q), "equal per-member orbit deltas are accepted")
	_check(runner, store, expected, 6, "all six independently changed symmetric orbits")
	runner.assert_eq(_sum(store.materialize()) - original_total, added, "each physical member receives its delta once, without multiplying a stored Q")

	# Omitted members in other orbits are zero; the center has just one member.
	var sparse: Dictionary = _rows(FIRST)
	var sparse_store: SimThermalCellStore = _single(sparse)
	sparse["100,100"].energy = int(sparse["100,100"].energy) + 7
	runner.assert_true(sparse_store.apply_deltas({"100,100": 7}, MAX_Q), "a center-only delta may retain a compressed patch")
	_check(runner, sparse_store, sparse, 6, "omitted orbit members receiving zero")
	runner.assert_true(sparse_store.apply_deltas({"101,100": 0}, MAX_Q), "an explicitly zero partial orbit does not force expansion")
	_check(runner, sparse_store, sparse, 6, "a sparse zero delta")


func _asymmetric_deltas(runner: Object) -> void:
	var expected: Dictionary = _rows(FIRST)
	var store: SimThermalCellStore = _single(expected)
	expected["101,100"].energy = int(expected["101,100"].energy) + 3
	runner.assert_true(store.apply_deltas({"101,100": 3}, MAX_Q), "one member can receive a nonzero delta while its omitted peers receive zero")
	_check(runner, store, expected, 25, "a partial nonzero orbit")
	runner.assert_true(is_same(store.row("101,100"), store.fine["101,100"]), "an expanded internal row is the single owned fine row")

	var unequal: Dictionary = _rows(FIRST)
	var unequal_store: SimThermalCellStore = _single(unequal)
	var deltas: Dictionary = {"100,99": 1, "100,101": 1, "99,100": 2, "101,100": 1}
	for key: String in deltas:
		unequal[key].energy = int(unequal[key].energy) + int(deltas[key])
	runner.assert_true(unequal_store.apply_deltas(deltas, MAX_Q), "unequal deltas within a complete orbit can be applied safely")
	_check(runner, unequal_store, unequal, 25, "a complete but asymmetric orbit")


func _atomic_delta_rejection(runner: Object) -> void:
	var cases: Array[Dictionary] = [
		{"label": "missing key", "deltas": {"101,100": 1, "400,400": 1}},
		{"label": "noninteger delta", "deltas": {"101,100": 1, "100,100": 1.5}},
		{"label": "negative Q", "deltas": {"101,100": 1, "100,100": -101}},
		{"label": "Q over the maximum", "deltas": {"101,100": 1, "100,100": 901}}]
	for probe: Dictionary in cases:
		var expected: Dictionary = _rows(FIRST)
		var store: SimThermalCellStore = _single(expected)
		runner.assert_true(not store.apply_deltas(probe.deltas, MAX_Q), "the store rejects " + str(probe.label))
		_check(runner, store, expected, 6, "atomic rejection of " + str(probe.label))


func _compaction_refusals(runner: Object) -> void:
	var incomplete: Dictionary = _rows(FIRST)
	incomplete.erase("98,98")
	_check(runner, _single(incomplete), incomplete, 24, "an incomplete candidate patch")
	var rows: Dictionary = _rows(FIRST)
	rows["103,100"] = {"cell": [103, 100], "energy": 160, "allocated_ms": 137, "baseline_energy": 80}
	_check(runner, _single(rows), rows, 26, "a patch with an allocated four-neighbor halo")

	# Both overlapping candidates use the same constant Q and metadata. It is
	# their actual occupied halo, not an accidentally unequal orbit, that fails.
	var overlap: Dictionary = _rows(FIRST)
	var second: Vector2i = FIRST + Vector2i(4, 0)
	var overlapping_rows: Dictionary = _rows(second)
	for row: Dictionary in overlap.values():
		row.energy = 120
	for row: Dictionary in overlapping_rows.values():
		row.energy = 120
	overlap.merge(overlapping_rows)
	var centers: Array[Vector2i] = [FIRST, second]
	var combined := Store.new()
	combined.replace_fine(overlap.duplicate(true))
	combined.compact(centers, [], MAX_Q)
	_check(runner, combined, overlap, 45, "two overlapping, individually symmetric candidate patches")

	var unequal: Dictionary = _rows(FIRST)
	unequal["101,100"].energy = int(unequal["101,100"].energy) + 1
	_check(runner, _single(unequal), unequal, 25, "unequal Q within one orbit")
	var allocation: Dictionary = _rows(FIRST)
	allocation["101,100"].allocated_ms = 138
	_check(runner, _single(allocation), allocation, 25, "unequal allocation times")
	var baseline: Dictionary = _rows(FIRST)
	baseline["101,100"].baseline_energy = 81
	_check(runner, _single(baseline), baseline, 25, "unequal original background allocations")

	var ordinary: Dictionary = _rows(FIRST)
	var neutral_but_asymmetric: Array = [
		{"from": "", "to": "101,100", "rate": 7},
		{"from": "101,100", "to": "", "rate": 7}]
	_check(runner, _single(ordinary, neutral_but_asymmetric), ordinary, 25, "equal net but unequal separate incoming and outgoing rates")
	var balanced: Array = []
	for key: String in ordinary:
		balanced.append({"from": "", "to": key, "rate": 3})
		balanced.append({"from": key, "to": "", "rate": 2})
	_check(runner, _single(ordinary, balanced), ordinary, 6, "matching separate incoming and outgoing rates")
	var unknown: Array = [{"from": "400,400", "to": "101,100", "rate": 1}]
	_check(runner, _single(ordinary, unknown), ordinary, 25, "an unknown endpoint touching a candidate")
	var device: Array = [{"from": "@artifact/source", "to": "101,100", "rate": 1}]
	_check(runner, _single(ordinary, device), ordinary, 25, "a device endpoint touching a candidate")


func _two_patches(runner: Object) -> void:
	var expected: Dictionary = _rows(FIRST)
	expected.merge(_rows(SECOND, 300))
	var centers: Array[Vector2i] = [FIRST, SECOND]
	var store := Store.new()
	store.replace_fine(expected.duplicate(true))
	store.compact(centers, [], MAX_Q)
	_check(runner, store, expected, 12, "two independent symmetric patches")
	expected["101,100"].energy = int(expected["101,100"].energy) + 3
	expected["120,100"].energy = int(expected["120,100"].energy) + 5
	runner.assert_true(store.apply_deltas({"101,100": 3, "120,100": 5}, MAX_Q), "one transaction can update an asymmetric first patch and a symmetric second patch")
	_check(runner, store, expected, 31, "only the affected first patch expands")
	runner.assert_true(store.fine.has("101,100") and not store.fine.has("120,100"), "the updated second patch retains compressed ownership")


func _single_add_and_replacement(runner: Object) -> void:
	var expected: Dictionary = _rows(FIRST)
	var store: SimThermalCellStore = _single(expected)
	var original_total: int = _sum(expected)
	store.add_energy("100,100", 9)
	expected["100,100"].energy = int(expected["100,100"].energy) + 9
	_check(runner, store, expected, 25, "a single-cell addition")
	runner.assert_eq(_sum(store.materialize()), original_total + 9, "the center addition neither multiplies heat nor alters other cells")

	# Replace a live compressed block, not just an already expanded field.
	store = _single(_rows(FIRST))
	var fresh: Dictionary = _rows(SECOND, 300)
	store.replace_fine(fresh.duplicate(true))
	_check(runner, store, fresh, 25, "replacement of all original owned rows")
	runner.assert_true(not store.has("100,100") and store.row("100,100").is_empty(), "replacement clears the old patch and its coordinate index")
	runner.assert_eq(store.energy_at("100,100", -7), -7, "old compressed Q cannot be queried after replacement")
	var centers: Array[Vector2i] = [SECOND]
	store.compact(centers, [], MAX_Q)
	_check(runner, store, fresh, 6, "the replacement field recompacts independently")
	var extra: Dictionary = {"cell": [400, 400], "energy": 222, "allocated_ms": 137, "baseline_energy": 80}
	store.allocate("400,400", extra)
	fresh["400,400"] = extra.duplicate(true)
	_check(runner, store, fresh, 7, "an independent fine allocation alongside a compressed patch")
	runner.assert_true(is_same(store.row("400,400"), extra), "owned fine allocation keeps its single original row")
