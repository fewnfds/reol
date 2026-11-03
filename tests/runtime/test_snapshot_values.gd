extends RefCounted
## Persistence values preserve actual positions and reject unsupported state.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	_values_keep_transport_semantics(runner)
	_numeric_validation_keeps_boundaries(runner)
	_explicit_context_stages_independent_world(runner)


func _values_keep_transport_semantics(runner: Object) -> void:
	var input: Dictionary = {&"nested": [{&"name": &"source", &"position": [65.125, -2.75]}], &"limit": SimSaveStore.MAX_JSON_INTEGER}
	var converted: Dictionary = SnapshotValues.for_save(input)
	runner.assert_true(converted.keys()[0] is String, "save boundary converts StringName keys into JSON strings")
	runner.assert_true(converted.nested[0].name is String, "save boundary converts nested StringName values")
	runner.assert_eq(converted.nested[0].position, [65.125, -2.75], "save conversion preserves fractional spatial coordinates")
	runner.assert_eq(converted.limit, SimSaveStore.MAX_JSON_INTEGER, "save conversion preserves the largest supported integer")
	runner.assert_true(SimSaveStore._valid_json_value(converted), "converted supported values satisfy original JSON transport")
	converted.nested[0].position[0] = 9.5
	runner.assert_eq(input.nested[0].position[0], 65.125, "save projection does not mutate its original nested state")
	var restored: Dictionary = SnapshotValues.normalized(SnapshotValues.for_save(input))
	runner.assert_eq(int(restored.limit), SimSaveStore.MAX_JSON_INTEGER, "JSON normalization keeps all supported integer digits")
	runner.assert_eq(restored.nested[0].position, [65.125, -2.75], "normalization retains noninteger coordinates")
	runner.assert_eq(SnapshotValues.normalized({"count": 2}), SnapshotValues.normalized({"count": 2.0}), "definition comparison accepts integral JSON numeric representation")
	for unsupported: Variant in [Vector2(1.0, 2.0), INF, NAN, SimSaveStore.MAX_JSON_INTEGER + 1]:
		var projected: Dictionary = SnapshotValues.for_save({"unsupported": unsupported})
		runner.assert_true(not SimSaveStore._valid_json_value(projected), "save projection leaves unsupported input for transport rejection: " + str(typeof(unsupported)))
	runner.assert_eq(VillageRuntime._snapshot_json_value(input), SnapshotValues.for_save(input), "legacy save helper remains compatible with the pure boundary")
	runner.assert_eq(VillageRuntime._json_normalized({"count": 2}), SnapshotValues.normalized({"count": 2}), "legacy normalized helper preserves its old callers")


func _numeric_validation_keeps_boundaries(runner: Object) -> void:
	runner.assert_true(SnapshotValues.valid_integer(0.0, 0), "integral JSON floats remain valid elapsed values")
	runner.assert_true(not SnapshotValues.valid_integer(0, 1), "positive-only timestamp retains its minimum")
	for value: Variant in [true, null, "1", 1.5, INF, NAN]:
		runner.assert_true(not SnapshotValues.valid_integer(value, 0), "integer validation rejects noninteger or nonnumeric input: " + str(value))
	runner.assert_true(SnapshotValues.number_pair([5.125, -7.5]), "spatial positions allow fractional components")
	runner.assert_true(not SnapshotValues.number_pair([5.125, -7.5], true), "grid coordinates still reject fractional components")
	runner.assert_true(SnapshotValues.number_pair([5.0, -7.0], true), "integer grid coordinates accept decoded JSON numbers")
	for value: Variant in [[1], [1, 2, 3], [true, 2], [INF, 2], Vector2(1.0, 2.0)]:
		runner.assert_true(not SnapshotValues.number_pair(value), "pair validation rejects wrong shape or nonfinite component: " + str(value))


func _explicit_context_stages_independent_world(runner: Object) -> void:
	var support: RefCounted = Fixtures.new()
	var fixture: Dictionary = support._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var home: VillageRuntime = runtime.home_runtime()
	var context: Dictionary = home.snapshot_context()
	runner.assert_true(home == fixture.home and context.player == fixture.player, "explicit session context references the existing runtime and controlled body")
	runner.assert_true(context.content != null, "explicit session context supplies original content definitions")
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var before: String = SnapshotValues.canonical_json(snapshot)
	var staged: Dictionary = WorldSessionSnapshot.stage(runtime, snapshot)
	runner.assert_true(not staged.is_empty(), "session with explicit boundary stages as a valid independent candidate")
	if not staged.is_empty():
		runner.assert_true(staged.world != runtime.world_sim and staged.map != runtime.world_sim.map_data, "candidate boundary owns independent world and static map")
	runner.assert_eq(SnapshotValues.canonical_json(WorldSessionSnapshot.capture(runtime)), before, "candidate staging does not mutate live world or snapshot values")
	var damaged: Dictionary = snapshot.duplicate(true)
	damaged.simulation.inventory.containers["player"] = {}
	runner.assert_true(WorldSessionSnapshot.stage(runtime, damaged).is_empty(), "conflicting home mirror is rejected without rewriting one side")
	runner.assert_eq(SnapshotValues.canonical_json(WorldSessionSnapshot.capture(runtime)), before, "rejected mirrored state leaves the original session unchanged")
	support._dispose(fixture)
