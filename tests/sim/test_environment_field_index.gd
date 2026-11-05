extends RefCounted
## The index stores disposable source projections, not original items or time.

const Index = preload("res://scripts/sim/environment_field_index.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const CHANNELS: int = 7


func run(runner: Object) -> void:
	_maxima_and_stable_ties(runner)
	_projection_isolation(runner)
	_movement_and_reclamation(runner)
	_spatial_buckets(runner)
	_circle_at_map_edge(runner)
	_rejections_are_atomic(runner)
	_small_map_against_float_reference(runner)
	print("SCENARIO environment field index: independent channel maxima, deterministic ties, moved-source replacement, bounded buckets, circular edges and float-reference agreement")


func _source(id: String, cell: Vector2i, radius: int, channels: Variant) -> Dictionary:
	return {"id": id, "cell": cell, "radius": radius, "channels": channels}


func _maxima_and_stable_ties(runner: Object) -> void:
	var first: RefCounted = Index.new()
	var second: RefCounted = Index.new()
	runner.assert_true(first.configure(Vector2i(32, 32), 8) and second.configure(Vector2i(32, 32), 8), "both independent layouts configure")
	var rows: Array[Dictionary] = [
		_source("z", Vector2i(12, 12), 4, [9000, 0, 0, 0, 0, 0, 0]),
		_source("c", Vector2i(12, 12), 4, [0, 0, 0, 5500, 1200, 4000, 6000]),
		_source("b", Vector2i(12, 12), 4, [5000, 7000, 9000, 0, 0, 0, 10000]),
		_source("a", Vector2i(12, 12), 4, PackedInt64Array([9000, 0, 6000, 0, 900, 10000, 0])),
	]
	for row: Dictionary in rows:
		runner.assert_true(bool(first.set_source(row).ok), "the forward-order source projection is accepted")
	for index: int in range(rows.size() - 1, -1, -1):
		runner.assert_true(bool(second.set_source(rows[index]).ok), "the reverse-order source projection is accepted")
	var center: Dictionary = first.sample_base(Vector2i(12, 12))
	runner.assert_eq(center.channels, PackedInt64Array([9000, 7000, 9000, 5500, 1200, 10000, 10000]), "each of five elements and the two thermal sides independently takes its maximum, never a sum")
	runner.assert_eq(center.winners, ["a", "b", "b", "c", "c", "a", "b"], "ties use stable source IDs while different channels keep their own winners")
	runner.assert_true(int(center.channels[5]) == int(center.channels[6]) and int(center.channels[5]) > 0, "equal hot and cold strengths remain separately available before later cancellation")
	for point: Vector2i in [Vector2i(12, 12), Vector2i(13, 12), Vector2i(13, 13), Vector2i(15, 12), Vector2i(16, 12), Vector2i(0, 0)]:
		var forward: Dictionary = first.sample_base(point)
		var reverse: Dictionary = second.sample_base(point)
		runner.assert_eq(forward.channels, reverse.channels, "base values do not depend on source insertion order")
		runner.assert_eq(forward.winners, reverse.winners, "winner IDs do not depend on source insertion order")
	var empty: Dictionary = first.sample_base(Vector2i.ZERO)
	runner.assert_eq(empty.channels, PackedInt64Array([0, 0, 0, 0, 0, 0, 0]), "no nearby source yields no invented field")
	runner.assert_eq(empty.winners, ["", "", "", "", "", "", ""], "zero channels do not invent a winning source")


func _projection_isolation(runner: Object) -> void:
	var index: RefCounted = Index.new()
	runner.assert_true(index.configure(Vector2i(24, 24), 4), "the projection-isolation fixture configures")
	var input_channels: Array = [9000, 700, 0, 0, 0, 1000, 500]
	var projection: Dictionary = _source("source", Vector2i(6, 7), 3, input_channels)
	var created: Dictionary = index.set_source(projection)
	runner.assert_true(bool(created.ok) and bool(created.changed), "adding a projection changes the derived index")
	var before: Dictionary = index.sample_base(Vector2i(6, 7)).duplicate(true)
	var before_diagnostics: Dictionary = index.diagnostics().duplicate(true)
	input_channels[0] = 1
	projection["id"] = "unrelated"
	projection["cell"] = Vector2i(18, 18)
	projection["radius"] = 1
	runner.assert_eq(index.sample_base(Vector2i(6, 7)), before, "changing the caller's original projection cannot mutate the index")
	runner.assert_eq(index.diagnostics(), before_diagnostics, "changing caller-owned input cannot advance the index revision")
	var returned: Dictionary = index.sample_base(Vector2i(6, 7))
	var returned_channels: PackedInt64Array = returned.channels
	returned_channels[0] = 1
	returned["channels"] = returned_channels
	var returned_winners: Array = returned.winners
	returned_winners[0] = "forged"
	returned["revision"] = -1
	runner.assert_eq(index.sample_base(Vector2i(6, 7)), before, "changing returned channels, winners or revision cannot pollute later queries")
	var identical: Dictionary = index.set_source(_source("source", Vector2i(6, 7), 3, PackedInt64Array([9000, 700, 0, 0, 0, 1000, 500])))
	runner.assert_true(bool(identical.ok) and not bool(identical.changed), "the same ID and values normalize to an unchanged projection")
	runner.assert_eq(identical.revision, created.revision, "an unchanged projection does not advance revision")
	runner.assert_eq(identical.affected, Rect2i(), "an unchanged projection has no affected region")
	runner.assert_eq(index.diagnostics(), before_diagnostics, "an unchanged projection does not rebuild or duplicate its source")


func _movement_and_reclamation(runner: Object) -> void:
	var index: RefCounted = Index.new()
	runner.assert_true(index.configure(Vector2i(40, 16), 4), "the moving-source fixture configures")
	var top: Dictionary = _source("top", Vector2i(6, 8), 4, [10000, 0, 0, 0, 0, 0, 0])
	var backup: Dictionary = _source("backup", Vector2i(6, 8), 4, [7000, 0, 0, 0, 0, 0, 0])
	index.set_source(top)
	index.set_source(backup)
	var original: Dictionary = index.sample_base(Vector2i(6, 8))
	runner.assert_eq(original.channels[0], 10000, "the stronger local source wins before movement")
	runner.assert_eq(original.winners[0], "top", "the winning source keeps its original ID")
	top["cell"] = Vector2i(26, 8)
	var moved: Dictionary = index.set_source(top)
	runner.assert_true(bool(moved.ok) and bool(moved.changed), "moving the source updates its projection")
	runner.assert_eq(int(moved.revision), int(original.revision) + 1, "one move advances the index revision exactly once")
	var affected: Rect2i = moved.affected
	for point: Vector2i in [Vector2i(3, 8), Vector2i(9, 8), Vector2i(23, 8), Vector2i(29, 8)]:
		runner.assert_true(affected.has_point(point), "the invalidation region covers both old and new nonzero footprints")
	var old_place: Dictionary = index.sample_base(Vector2i(6, 8))
	var new_place: Dictionary = index.sample_base(Vector2i(26, 8))
	runner.assert_eq(old_place.channels[0], 7000, "the old footprint immediately exposes the next strongest source")
	runner.assert_eq(old_place.winners[0], "backup", "the old footprint selects the actual surviving source")
	runner.assert_eq(new_place.channels[0], 10000, "the moved source supplies its full peak at the new footprint")
	runner.assert_eq(new_place.winners[0], "top", "movement preserves the source ID")
	var shared_before: Dictionary = index.diagnostics().duplicate(true)
	index.remove_source("top")
	runner.assert_eq(index.diagnostics().kernel_values, shared_before.kernel_values, "removing one of two equal-radius sources retains their shared table")
	runner.assert_eq(index.sample_base(Vector2i(6, 8)).channels[0], 7000, "the remaining equal-radius source stays queryable after its peer is removed")

	var only: RefCounted = Index.new()
	var control: RefCounted = Index.new()
	runner.assert_true(only.configure(Vector2i(32, 16), 4) and control.configure(Vector2i(32, 16), 4), "independent radius-lifecycle fixtures configure")
	var one: Dictionary = _source("one", Vector2i(3, 3), 3, [8000, 0, 0, 0, 0, 0, 0])
	only.set_source(one)
	var before_move: Dictionary = only.diagnostics().duplicate(true)
	one["cell"] = Vector2i(22, 3)
	runner.assert_true(bool(only.set_source(one).ok), "the sole source can move without changing radius")
	var after_move: Dictionary = only.diagnostics()
	runner.assert_eq(after_move.kernel_values, before_move.kernel_values, "moving the sole source keeps its existing radius table alive")
	runner.assert_eq(after_move.max_radius, 3, "moving the sole source retains its active radius")
	runner.assert_eq(only.sample_base(Vector2i(22, 3)).channels[0], 8000, "the retained table works immediately at the new location")
	runner.assert_eq(only.sample_base(Vector2i(3, 3)).channels[0], 0, "moving the sole source clears its old location")
	one["radius"] = 5
	var resized: Dictionary = only.set_source(one)
	control.set_source(one)
	runner.assert_true(bool(resized.ok) and bool(resized.changed), "an existing source can change radius")
	runner.assert_eq(only.diagnostics().kernel_values, control.diagnostics().kernel_values, "changing the sole radius retires its old table")
	runner.assert_eq(only.diagnostics().max_radius, 5, "the active maximum radius follows the changed source")
	runner.assert_true(int(only.sample_base(Vector2i(25, 3)).channels[0]) > 0, "the larger footprint becomes queryable")
	only.set_source(_source("other", Vector2i(2, 10), 2, [0, 0, 0, 0, 0, 0, 2000]))
	var two_radii: int = int(only.diagnostics().kernel_values)
	runner.assert_true(two_radii > int(control.diagnostics().kernel_values), "different active radii retain their own bounded templates")
	var removed: Dictionary = only.remove_source("one")
	runner.assert_true(bool(removed.ok) and removed.affected.has_point(Vector2i(22, 3)), "removal invalidates the removed source's footprint")
	runner.assert_eq(only.sample_base(Vector2i(22, 3)).channels[0], 0, "removed source values disappear from queries")
	runner.assert_eq(only.diagnostics().max_radius, 2, "removing the widest source lowers the active maximum radius")
	runner.assert_true(int(only.diagnostics().kernel_values) < two_radii, "removing the final source at a radius reclaims its table")
	only.remove_source("other")
	var empty: Dictionary = only.diagnostics()
	runner.assert_eq(empty.source_count, 0, "removing all projections leaves no source")
	runner.assert_eq(empty.bucket_count, 0, "empty spatial buckets are reclaimed")
	runner.assert_eq(empty.kernel_values, 0, "all unused radius tables are reclaimed")
	runner.assert_eq(empty.max_radius, 0, "an empty index has no active radius")


func _spatial_buckets(runner: Object) -> void:
	var index: RefCounted = Index.new()
	runner.assert_true(index.configure(Vector2i(512, 512), 512), "the sparse large-map fixture configures")
	index.set_source(_source("local", Vector2i(8, 8), 2, [3000, 0, 0, 0, 0, 0, 0]))
	for y: int in range(20):
		for x: int in range(20):
			var id: String = "remote_%02d_%02d" % [x, y]
			var location: Vector2i = Vector2i(200 + x * 4, 200 + y * 4)
			index.set_source(_source(id, location, 2, [2000, 0, 0, 0, 0, 0, 0]))
	var diagnostics: Dictionary = index.diagnostics()
	var local: Dictionary = index.sample_base(Vector2i(8, 8))
	runner.assert_eq(diagnostics.source_count, 401, "the fixture actually contains many distant sources")
	runner.assert_eq(local.channels[0], 3000, "the local source retains its correct field in a populated world")
	runner.assert_eq(local.candidate_count, 1, "the query visits the local bucket rather than scanning hundreds of distant sources")
	runner.assert_true(int(local.candidate_count) < int(diagnostics.source_count), "query work does not scale with unrelated remote source count")
	index.set_source(_source("remote_00_00", Vector2i(9, 8), 2, [4000, 0, 0, 0, 0, 0, 0]))
	var after_move: Dictionary = index.sample_base(Vector2i(8, 8))
	runner.assert_eq(after_move.candidate_count, 2, "a moved source enters the queried bucket exactly once")
	runner.assert_eq(after_move.channels[0], 3000, "moving a weaker-at-distance source into the bucket cannot spuriously add its strength")
	index.remove_source("local")
	runner.assert_eq(index.sample_base(Vector2i(8, 8)).candidate_count, 1, "removing a local source removes it from bucket queries")


func _circle_at_map_edge(runner: Object) -> void:
	var index: RefCounted = Index.new()
	runner.assert_true(index.configure(Vector2i(8, 8), 2), "the clipped edge fixture configures")
	var created: Dictionary = index.set_source(_source("edge", Vector2i.ZERO, 5, [10000, 0, 0, 0, 0, 0, 0]))
	runner.assert_true(bool(created.ok), "a source at the map corner is valid")
	var affected: Rect2i = created.affected
	runner.assert_eq(affected.position, Vector2i.ZERO, "the affected rectangle is clipped to the map origin")
	runner.assert_true(affected.end.x <= 8 and affected.end.y <= 8 and affected.has_point(Vector2i(4, 0)) and affected.has_point(Vector2i(0, 4)), "the clipped region still covers every in-bounds influence direction")
	runner.assert_eq(index.sample_base(Vector2i.ZERO).channels[0], 10000, "the edge source retains its full peak")
	runner.assert_eq(index.sample_base(Vector2i(4, 0)).channels[0], 2000, "an axial cell four units from radius five has the expected remaining strength")
	runner.assert_true(int(index.sample_base(Vector2i(1, 1)).channels[0]) < int(index.sample_base(Vector2i(1, 0)).channels[0]), "diagonal distance exceeds one axial step")
	runner.assert_eq(index.sample_base(Vector2i(3, 4)).channels[0], 0, "a point exactly on the circular edge has zero influence")
	runner.assert_eq(index.sample_base(Vector2i(4, 4)).channels[0], 0, "a square-corner cell outside the circle receives no influence")
	var removed: Dictionary = index.remove_source("edge")
	runner.assert_eq(removed.affected, affected, "removing an edge source invalidates the same clipped footprint")
	var opposite: Dictionary = index.set_source(_source("opposite", Vector2i(7, 7), 5, [10000, 0, 0, 0, 0, 0, 0]))
	var opposite_affected: Rect2i = opposite.affected
	runner.assert_eq(opposite_affected.end, Vector2i(8, 8), "clipping also respects the opposite map edges")
	runner.assert_eq(index.sample_base(Vector2i(7, 7)).channels[0], 10000, "the opposite corner retains its peak")
	runner.assert_eq(index.sample_base(Vector2i(3, 7)).channels[0], 2000, "opposite-edge clipping preserves in-bounds falloff")
	runner.assert_eq(index.sample_base(Vector2i(3, 3)).channels[0], 0, "the opposite square corner remains outside the circular field")


func _rejections_are_atomic(runner: Object) -> void:
	var index: RefCounted = Index.new()
	var untouched: Dictionary = index.diagnostics().duplicate(true)
	var good: Dictionary = _source("a", Vector2i(2, 2), 3, [10, 20, 30, 40, 50, 60, 70])
	for rejected: Dictionary in [index.set_source(good), index.remove_source("a"), index.sample_base(Vector2i.ZERO)]:
		runner.assert_true(not bool(rejected.ok) and not str(rejected.get("reason", "")).is_empty(), "unconfigured operations fail explicitly")
	runner.assert_eq(index.diagnostics(), untouched, "unconfigured queries and mutations leave no derived state")
	for example: Array in [
		[Vector2i(0, 1), 1], [Vector2i(1, 0), 1], [Vector2i(-1, 1), 1],
		[Vector2i(Index.MAX_AXIS + 1, 1), 1], [Vector2i(1, Index.MAX_AXIS + 1), 1],
		[Vector2i(4, 4), 0], [Vector2i(4, 4), -1], [Vector2i(4, 4), Index.MAX_CAPACITY + 1],
	]:
		runner.assert_true(not index.configure(example[0], int(example[1])), "invalid size or capacity cannot configure the index")
		runner.assert_eq(index.diagnostics(), untouched, "a rejected configuration cannot partially change diagnostics")
	runner.assert_true(index.configure(Vector2i(8, 8), 1), "a valid configuration remains possible after rejection")
	runner.assert_true(bool(index.set_source(good).ok), "the valid existing source consumes the single slot")
	var before: Dictionary = index.diagnostics().duplicate(true)
	var before_query: Dictionary = index.sample_base(Vector2i(2, 2)).duplicate(true)
	runner.assert_true(not index.configure(Vector2i(16, 16), 2), "a configured index cannot be reconfigured behind existing projections")
	runner.assert_eq(index.diagnostics(), before, "reconfiguration rejection leaves the existing index unchanged")
	var faults: Array[Dictionary] = [
		{}, {"id": "a", "cell": Vector2i(2, 2), "radius": 3},
		_source("", Vector2i(2, 2), 3, good.channels),
		_source("x".repeat(129), Vector2i(2, 2), 3, good.channels),
		{"id": 1, "cell": Vector2i(2, 2), "radius": 3, "channels": good.channels},
		{"id": "a", "cell": Vector2(2, 2), "radius": 3, "channels": good.channels},
		_source("a", Vector2i(-1, 2), 3, good.channels),
		_source("a", Vector2i(8, 2), 3, good.channels),
		_source("a", Vector2i(2, 2), 0, good.channels),
		_source("a", Vector2i(2, 2), Rules.MAX_RADIUS + 1, good.channels),
		{"id": "a", "cell": Vector2i(2, 2), "radius": 3.0, "channels": good.channels},
		_source("a", Vector2i(2, 2), 3, [10, 20, 30, 40, 50, 60]),
		_source("a", Vector2i(2, 2), 3, PackedInt32Array([10, 20, 30, 40, 50, 60, 70])),
		_source("a", Vector2i(2, 2), 3, [10, 20, 30, 40, 50, 60, -1]),
		_source("a", Vector2i(2, 2), 3, [10, 20, 30, 40, 50, 60, Rules.MAX_GRADE_MILLI + 1]),
		_source("a", Vector2i(2, 2), 3, [10, 20, 30, 40, 50, 60, 1.0]),
		_source("a", Vector2i(2, 2), 3, [10, 20, 30, 40, 50, 60, true]),
		{"id": "a", "cell": Vector2i(2, 2), "radius": 3, "channels": good.channels, "quantity": 10000},
		_source("b", Vector2i(3, 3), 2, [10, 20, 30, 40, 50, 60, 70]),
	]
	for fault: Dictionary in faults:
		var rejected: Dictionary = index.set_source(fault)
		runner.assert_true(not bool(rejected.ok) and not str(rejected.get("reason", "")).is_empty(), "invalid shape, value or exhausted capacity rejects explicitly: " + str(fault))
		runner.assert_eq(index.diagnostics(), before, "a rejected source never changes derived state or revision")
		runner.assert_eq(index.sample_base(Vector2i(2, 2)), before_query, "a rejected source cannot damage the previous projection")
	for cell: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(8, 0), Vector2i(0, 8), Vector2i(-2147483648, 2147483647)]:
		var rejected: Dictionary = index.sample_base(cell)
		runner.assert_true(not bool(rejected.ok) and not str(rejected.get("reason", "")).is_empty(), "out-of-bounds queries fail without inventing a field")
		runner.assert_eq(index.diagnostics(), before, "a rejected query leaves the index unchanged")
	var missing: Dictionary = index.remove_source("missing")
	runner.assert_true(not bool(missing.ok), "removing an unknown source fails explicitly")
	runner.assert_eq(index.diagnostics(), before, "removing an unknown source cannot advance revision")
	var changed: Dictionary = index.set_source(_source("a", Vector2i(3, 3), 3, [11, 20, 30, 40, 50, 60, 70]))
	runner.assert_true(bool(changed.ok) and bool(changed.changed), "capacity limits new sources, not valid updates of the existing ID")


func _small_map_against_float_reference(runner: Object) -> void:
	var index: RefCounted = Index.new()
	var map_size := Vector2i(19, 15)
	runner.assert_true(index.configure(map_size, 32), "the independent small-map reference fixture configures")
	var random := RandomNumberGenerator.new()
	random.seed = 24681357
	var rows: Array[Dictionary] = []
	for source_index: int in range(24):
		var channel_values: Array[int] = []
		for channel: int in CHANNELS:
			# At most 1,000,000 milli-strength keeps millionth-weight rounding
			# within one milli-strength of the independently rounded real value.
			var strength: int = random.randi_range(0, 1000000)
			channel_values.append(0 if random.randi_range(0, 4) == 0 else strength)
		var location := Vector2i(random.randi_range(0, map_size.x - 1), random.randi_range(0, map_size.y - 1))
		var row: Dictionary = _source("r_%02d" % source_index, location, 1 + source_index % 8, channel_values)
		rows.append(row)
		runner.assert_true(bool(index.set_source(row).ok), "every fixed-seed mixed-radius reference source is accepted")
	for y: int in map_size.y:
		for x: int in map_size.x:
			var cell := Vector2i(x, y)
			var reference: Dictionary = _float_reference(rows, cell)
			var actual: Dictionary = index.sample_base(cell)
			var expected: PackedFloat64Array = reference.maxima
			var candidates: Dictionary = reference.contributions
			for channel: int in CHANNELS:
				var value: int = int(actual.channels[channel])
				var rounded_reference: int = roundi(expected[channel])
				runner.assert_true(absi(value - rounded_reference) <= 1, "small-map value agrees within one milli-strength at %s channel %d" % [cell, channel])
				var winner: String = str(actual.winners[channel])
				if value == 0:
					runner.assert_eq(winner, "", "zero-valued fields have no source winner")
				else:
					runner.assert_true(candidates.has(winner), "a nonzero winner refers to a real projection")
					if candidates.has(winner):
						var winner_values: PackedFloat64Array = candidates[winner]
						runner.assert_true(expected[channel] - winner_values[channel] <= 2.00001, "the selected winner is within the combined rounding bound of the real maximum")


func _float_reference(rows: Array[Dictionary], cell: Vector2i) -> Dictionary:
	# Deliberately calculate the Euclidean real-valued field directly. This is
	# independent of the integer kernel lookup and the source index's buckets.
	var maxima := PackedFloat64Array()
	maxima.resize(CHANNELS)
	var contributions: Dictionary = {}
	for row: Dictionary in rows:
		var source_cell: Vector2i = row.cell
		var dx: float = float(cell.x - source_cell.x)
		var dy: float = float(cell.y - source_cell.y)
		var distance: float = sqrt(dx * dx + dy * dy)
		var factor: float = maxf(0.0, 1.0 - distance / float(row.radius))
		var values := PackedFloat64Array()
		values.resize(CHANNELS)
		for channel: int in CHANNELS:
			values[channel] = float(row.channels[channel]) * factor
			maxima[channel] = maxf(maxima[channel], values[channel])
		contributions[row.id] = values
	return {"maxima": maxima, "contributions": contributions}
