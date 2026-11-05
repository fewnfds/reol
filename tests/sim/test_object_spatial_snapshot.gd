extends RefCounted
## An explicitly captured set of detached reference geometry; never a world owner.

const Snapshot = preload("res://scripts/sim/object_spatial_snapshot.gd")


func run(runner: Object) -> void:
	_test_geometry_and_layers(runner)
	_test_reference_identity_and_atomic_rejection(runner)
	_test_query_budget_and_bounds(runner)
	_test_detached_results_and_lifecycle(runner)
	print("SCENARIO object spatial snapshot: exact cells, bounded queries, immutable captured references and explicit non-live scope")


func _test_geometry_and_layers(runner: Object) -> void:
	var snapshot := Snapshot.new(16, 32)
	var walls: Dictionary = {"kind": "workplace", "region": "west", "part": "walls"}
	var ring: Array[Vector2i] = [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(4, 3), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(2, 2)]
	runner.assert_true(bool(snapshot.append(walls, ring, "ground", "placed").ok), "a non-rectangular structure is accepted")
	runner.assert_true(bool(snapshot.append({"kind": "construction", "id": "roof"}, [Vector2i(2, 2)], "roof", "placed").ok), "a roof may share ground geometry")
	runner.assert_true(bool(snapshot.append({"kind": "artifact", "id": "held"}, [Vector2i(2, 2)], "container", "contained").ok), "a carried item keeps a distinct containment relation")
	runner.assert_true(bool(snapshot.append({"kind": "actor", "id": "person"}, [Vector2i(15, 15), Vector2i(16, 15)], "ground", "body").ok), "one body footprint crosses bucket boundaries")
	runner.assert_eq(snapshot.stats().entries, 12, "a repeated cell is indexed once")
	runner.assert_true(bool(snapshot.seal(1234).ok), "captured reference set seals")
	var hollow: Dictionary = snapshot.query(Rect2i(3, 3, 1, 1), "ground")
	runner.assert_true(bool(hollow.ok) and hollow.complete and hollow.references.is_empty(), "the center of a wall ring is not a wall")
	var outside: Dictionary = snapshot.query(Rect2i(2, 2, 1, 1), "ground")
	runner.assert_eq(outside.references, [walls], "ground geometry excludes roof and held objects")
	var contained: Dictionary = snapshot.query(Rect2i(2, 2, 1, 1), "container", "contained")
	runner.assert_eq(contained.references, [{"kind": "artifact", "id": "held"}], "contained is queryable without becoming a ground item")
	var cross: Dictionary = snapshot.query(Rect2i(15, 15, 2, 1))
	runner.assert_eq(cross.references.size(), 1, "one multi-cell object is returned once across buckets")
	runner.assert_eq(cross.references[0], {"kind": "actor", "id": "person"}, "cross-bucket geometry retains original reference")
	runner.assert_true(cross.scope == "captured_references" and not cross.live and cross.world_time_ms == 1234, "query identifies captured, non-live scope and time")


func _test_reference_identity_and_atomic_rejection(runner: Object) -> void:
	var snapshot := Snapshot.new(2, 3)
	var a: Dictionary = {"kind": "resource", "region": "west", "id": "tree"}
	var b: Dictionary = {"id": "tree", "region": "west", "kind": "resource"}
	runner.assert_true(bool(snapshot.append(a, [Vector2i(2, 2)], "ground", "resource").ok), "first reference is accepted")
	runner.assert_eq(snapshot.append(b, [Vector2i(5, 5)], "ground", "resource").reason, "duplicate_reference", "dictionary key order cannot duplicate one identity")
	runner.assert_eq(snapshot.append({"kind": "resource", "id": "invalid"}, [Vector2i(5, 5), Vector2i(-1, 0)], "ground", "resource").reason, "invalid_cell", "an invalid later cell rejects the whole insertion")
	runner.assert_eq(snapshot.append({"kind": "resource", "id": "huge"}, [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)], "ground", "resource").reason, "entry_capacity", "entry capacity rejects the whole insertion")
	runner.assert_eq(snapshot.stats().objects, 1, "rejected insertions add no object")
	runner.assert_eq(snapshot.stats().entries, 1, "rejected insertions add no cell")
	runner.assert_true(bool(snapshot.append({"kind": "resource", "id": "other"}, [Vector2i(5, 5)], "ground", "resource").ok), "valid insertion still succeeds after rejected attempts")
	runner.assert_eq(snapshot.append({"kind": "resource", "id": "overflow"}, [Vector2i(6, 5)], "ground", "resource").reason, "object_capacity", "object capacity is enforced")
	runner.assert_eq(snapshot.append({"kind": "resource", "id": 17}, [Vector2i(0, 0)], "ground", "resource").reason, "invalid_reference", "only detached flat-string identities are accepted")
	runner.assert_eq(snapshot.append({"kind": "resource", "id": "x"}, [Vector2i(8192, 0)], "ground", "resource").reason, "object_capacity", "capacity check has stable order before cell inspection")
	runner.assert_true(bool(snapshot.seal(8).ok), "rejected insertions leave a sealable snapshot")
	runner.assert_eq(snapshot.query(Rect2i(5, 5, 1, 1)).references, [{"kind": "resource", "id": "other"}], "failed insertions cannot leave ghost entries")


func _test_query_budget_and_bounds(runner: Object) -> void:
	var snapshot := Snapshot.new(8, 16)
	runner.assert_true(bool(snapshot.append({"kind": "a", "id": "1"}, [Vector2i(0, 0), Vector2i(1, 0)], "ground", "placed").ok), "budget fixture first geometry")
	runner.assert_true(bool(snapshot.append({"kind": "a", "id": "2"}, [Vector2i(2, 0)], "ground", "placed").ok), "budget fixture second geometry")
	runner.assert_eq(snapshot.query(Rect2i(0, 0, 1, 1)).reason, "unsealed", "cannot query a partial capture")
	runner.assert_eq(snapshot.seal(-1).reason, "invalid_time", "negative capture times are rejected")
	runner.assert_true(bool(snapshot.seal(10).ok), "valid capture time is accepted")
	var bounded: Dictionary = snapshot.query(Rect2i(0, 0, 3, 1), "", "", 2)
	runner.assert_true(not bounded.ok and not bounded.complete and bounded.reason == "budget_exhausted", "budget exhaustion cannot be read as an empty complete result")
	runner.assert_true(not bounded.has("references") and bounded.work_used <= 2, "budget failure publishes no partial references and respects the limit")
	var complete: Dictionary = snapshot.query(Rect2i(0, 0, 3, 1), "", "", 10)
	runner.assert_true(complete.ok and complete.complete and complete.references.size() == 2, "adequate budget returns each matching reference once")
	runner.assert_eq(snapshot.query(Rect2i(0, 0, 1, 1), "", "", 0).reason, "invalid_budget", "zero work budget is invalid")
	runner.assert_eq(snapshot.query(Rect2i(-1, 0, 1, 1)).reason, "invalid_area", "negative coordinates cannot wrap")
	runner.assert_eq(snapshot.query(Rect2i(8191, 8191, 2, 1)).reason, "invalid_area", "query must stay within map-axis limit")
	runner.assert_eq(snapshot.query(Rect2i(0, 0, 0, 1)).reason, "invalid_area", "empty area is explicit failure")
	runner.assert_eq(snapshot.query(Rect2i(0, 0, 1, 1), "unknown").reason, "invalid_layer", "unknown geometry layers are not silently ignored")


func _test_detached_results_and_lifecycle(runner: Object) -> void:
	var invalid := Snapshot.new(0, 1)
	runner.assert_eq(invalid.append({"kind": "actor", "id": "p"}, [Vector2i.ZERO], "ground", "body").reason, "invalid_limits", "invalid constructor limits reject insertions")
	runner.assert_eq(invalid.seal(1).reason, "invalid_limits", "invalid constructor limits cannot seal")
	var snapshot := Snapshot.new(2, 2)
	var ref: Dictionary = {"kind": "actor", "id": "p"}
	var cells: Array[Vector2i] = [Vector2i(8, 8)]
	runner.assert_true(bool(snapshot.append(ref, cells, "ground", "body").ok), "insert copies identity and cell value")
	ref.id = "changed"
	cells[0] = Vector2i(9, 9)
	runner.assert_true(bool(snapshot.seal(42).ok), "snapshot seals once")
	runner.assert_eq(snapshot.seal(43).reason, "sealed", "time cannot be rewritten")
	runner.assert_eq(snapshot.append({"kind": "actor", "id": "other"}, [Vector2i.ZERO], "ground", "body").reason, "sealed", "sealed geometry cannot change")
	var first: Dictionary = snapshot.query(Rect2i(8, 8, 1, 1))
	runner.assert_eq(first.references, [{"kind": "actor", "id": "p"}], "source mutation cannot rewrite captured reference or geometry")
	first.references[0].id = "tampered"
	first.references.clear()
	var second: Dictionary = snapshot.query(Rect2i(8, 8, 1, 1))
	runner.assert_eq(second.references, [{"kind": "actor", "id": "p"}], "query output cannot rewrite the snapshot")
	runner.assert_true(snapshot.query(Rect2i(9, 9, 1, 1)).references.is_empty(), "changed caller cells do not move the captured object")
