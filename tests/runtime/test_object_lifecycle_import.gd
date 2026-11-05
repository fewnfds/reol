extends RefCounted
## The old-root path uses real ordinary opening data, with only the new domain
## and its version labels projected away. Genuine earlier archives stay intact.

const Solar = preload("res://scripts/persistence/solar_import.gd")
const SolarProjection = preload("res://tests/runtime/helpers/solar_legacy_projection.gd")
const V49_PATH: String = "res://tests/fixtures/session_v49_thermal.json"
const V49_SHA: String = "a6ae26fad7fff13394ec1a7c9831d5a1fdd85c191222b31213c7f9de138bf8bd"
const CLIMATE_PATH: String = "res://data/definitions/climate.json"


func run(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary main initializes for the lifecycle root migration")
	else:
		_opening_and_rejections(runner, runtime)
		_earlier_solar_archive(runner, runtime)
	main.free()
	GameClock.restore_state(saved_clock)
	print("SCENARIO object lifecycle import: current and previous root, isolated candidate, standalone, invalid references and immutable native solar archive")


func _opening_and_rejections(runner: Object, runtime: WorldContinuityRuntime) -> void:
	var current: Dictionary = WorldSessionSnapshot.capture(runtime)
	var original_world: RegionalSimulation = runtime.world_sim
	var stable: String = _json(current)
	runner.assert_eq(int(current.schema_version), 51, "ordinary opening writes the current root51")
	runner.assert_eq(int(current.continuity.world.version), 42, "ordinary opening writes regional42")
	runner.assert_eq(_json(current.continuity.world.object_lifecycle), _json(SimObjectLifecycle.empty_state()), "ordinary opening starts with the empty original lifecycle")
	var accepted_current: Dictionary = SessionSaveSchema.upgrade(current)
	runner.assert_eq(_json(accepted_current), stable, "current root is accepted without migration")
	var current_candidate: Dictionary = WorldSessionSnapshot.stage(runtime, current)
	runner.assert_true(not current_candidate.is_empty(), "ordinary current root builds an independent candidate")
	if not current_candidate.is_empty():
		runner.assert_true(current_candidate.world != original_world, "current candidate does not reuse the active world")
	var previous: Dictionary = SolarProjection.prior_lifecycle(current)
	runner.assert_true(not previous.is_empty(), "previous root differs only by its empty lifecycle field and version labels")
	if previous.is_empty():
		return
	var previous_before: String = _json(previous)
	var factory := Callable(runtime.home_runtime(), "create_candidate_map")
	var upgraded: Dictionary = SessionSaveSchema.upgrade(previous, null, factory)
	runner.assert_true(not upgraded.is_empty(), "the previous root and regional world upgrade")
	if not upgraded.is_empty():
		runner.assert_eq(_json(upgraded), stable, "upgrade retains all original saved facts and adds only the empty lifecycle")
		var candidate: Dictionary = WorldSessionSnapshot.stage(runtime, previous)
		runner.assert_true(not candidate.is_empty(), "ordinary staging accepts the previous root")
		if not candidate.is_empty():
			runner.assert_eq(_json(candidate.snapshot), stable, "staging uses the same upgraded envelope")
		upgraded.continuity.world.object_lifecycle.receipts["test_mutation"] = {}
		runner.assert_eq(_json(previous), previous_before, "mutating the returned upgraded value cannot mutate the input")
	runner.assert_eq(_json(previous), previous_before, "upgrading the old root never modifies its input")

	var standalone: Dictionary = previous.duplicate(true)
	standalone.erase("continuity")
	standalone.assembly = ReolWorldAssemblyInputs.standalone(standalone.simulation.config)
	runner.assert_true(not standalone.assembly.is_empty(), "standalone input has its explicit independent assembly")
	var standalone_before: String = _json(standalone)
	var standalone_current: Dictionary = SessionSaveSchema.upgrade(standalone, null, factory)
	runner.assert_true(not standalone_current.is_empty() and not standalone_current.has("continuity"), "previous standalone root upgrades without inventing a regional world")
	if not standalone_current.is_empty():
		runner.assert_eq(int(standalone_current.schema_version), 51, "standalone root reaches the same current version")
		var expected: Dictionary = standalone.duplicate(true)
		expected.schema_version = 51
		runner.assert_eq(_json(standalone_current), _json(expected), "standalone migration changes no village, player or time facts")
	runner.assert_eq(_json(standalone), standalone_before, "standalone upgrade leaves its input unchanged")

	var bad: Dictionary = current.duplicate(true)
	bad.continuity.world.erase("object_lifecycle")
	_reject_upgrade(runner, bad, factory, "current root missing its lifecycle")
	bad = previous.duplicate(true)
	bad.continuity.world["object_lifecycle"] = SimObjectLifecycle.empty_state()
	_reject_upgrade(runner, bad, factory, "old root with even an empty future lifecycle")
	bad = previous.duplicate(true)
	bad.content_bundle.documents[CLIMATE_PATH].regions.home.label = "corrupt archived content"
	_reject_upgrade(runner, bad, factory, "old root with a damaged content digest")
	bad = previous.duplicate(true)
	bad.player.position = [-1.0, -1.0]
	_reject_upgrade(runner, bad, factory, "old root with a player position outside its recorded map")
	var ids: Array = previous.continuity.world.artifacts.objects.keys()
	runner.assert_true(not ids.is_empty(), "ordinary opening contains a real unique item for reference validation")
	if not ids.is_empty():
		bad = previous.duplicate(true)
		bad.continuity.world.artifacts.objects[ids[0]].container = "ground:missing"
		_reject_upgrade(runner, bad, factory, "old root with a broken original object location")
		bad = current.duplicate(true)
		bad.continuity.world.artifacts.objects[ids[0]].container = "ground:missing"
		var before: String = _json(bad)
		runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "current root with a broken original object location cannot publish a candidate")
		runner.assert_eq(_json(bad), before, "failed current staging leaves its supplied input unchanged")
	runner.assert_true(runtime.world_sim == original_world, "success and failure of independent staging keep the live world owner")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), stable, "candidate checks preserve the complete live session and shared clock")


func _earlier_solar_archive(runner: Object, runtime: WorldContinuityRuntime) -> void:
	var source_text: String = FileAccess.get_file_as_string(V49_PATH)
	runner.assert_eq(FileAccess.get_sha256(V49_PATH), V49_SHA, "native root49 archive retains its recorded checksum")
	var parsed: Variant = JSON.parse_string(source_text)
	if not parsed is Dictionary:
		runner.assert_true(false, "native root49 archive is a dictionary")
		return
	var source: Dictionary = parsed
	var before: String = _json(source)
	var factory := Callable(runtime.home_runtime(), "create_candidate_map")
	var solar_boundary: Dictionary = Solar.convert(source, factory)
	var current: Dictionary = SessionSaveSchema.upgrade(source, null, factory)
	runner.assert_true(not solar_boundary.is_empty() and not current.is_empty(), "native root49 reaches both solar root50 and current root51")
	if not solar_boundary.is_empty() and not current.is_empty():
		runner.assert_eq(int(solar_boundary.schema_version), 50, "solar importer retains its historical boundary")
		runner.assert_eq(int(current.schema_version), 51, "ordinary root49 entry continues through lifecycle migration")
		runner.assert_eq(_json(SolarProjection.prior_lifecycle(current)), _json(solar_boundary), "root49 to root51 preserves the proved solar result and adds only an empty lifecycle")
		runner.assert_eq(_json(SessionSaveSchema.upgrade(current)), _json(current), "migrated root is accepted by the current entry")
	runner.assert_eq(_json(source), before, "both migration paths leave the supplied root49 dictionary unchanged")
	runner.assert_eq(FileAccess.get_file_as_string(V49_PATH), source_text, "both migration paths leave the native archive bytes unchanged")
	runner.assert_eq(FileAccess.get_sha256(V49_PATH), V49_SHA, "native root49 checksum remains unchanged")


func _reject_upgrade(runner: Object, candidate: Dictionary, factory: Callable, label: String) -> void:
	var before: String = _json(candidate)
	runner.assert_true(SessionSaveSchema.upgrade(candidate, null, factory).is_empty(), label + " is rejected")
	runner.assert_eq(_json(candidate), before, label + " is not repaired in place")


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
