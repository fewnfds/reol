extends RefCounted
## Current lifecycle ownership and candidate checks; old roots remain read-only.

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
		runner.assert_true(false, "ordinary main initializes for lifecycle candidates")
	else:
		_opening_and_rejections(runner, runtime)
		_earlier_solar_archive(runner, runtime)
	main.free()
	GameClock.restore_state(saved_clock)
	print("SCENARIO object lifecycle boundary: current and standalone candidates, strict failures and immutable old archive rejection")


func _opening_and_rejections(runner: Object, runtime: WorldContinuityRuntime) -> void:
	var current: Dictionary = WorldSessionSnapshot.capture(runtime)
	var live: RegionalSimulation = runtime.world_sim
	var terrain: WorldMapData = live.map_data
	var stable: String = _json(current)
	runner.assert_eq(int(current.schema_version), SessionSaveSchema.VERSION, "ordinary opening writes the current root")
	runner.assert_eq(int(current.continuity.world.version), RegionalSimulation.SCHEMA_VERSION, "ordinary opening writes the current regional version")
	runner.assert_eq(_json(current.continuity.world.object_lifecycle), _json(SimObjectLifecycle.empty_state()), "ordinary opening starts with the original empty lifecycle")
	runner.assert_eq(_json(SessionSaveSchema.upgrade(current)), stable, "current root is accepted without migration")
	var candidate: Dictionary = WorldSessionSnapshot.stage(runtime, current)
	runner.assert_true(not candidate.is_empty(), "ordinary current root builds an independent candidate")
	if not candidate.is_empty():
		runner.assert_true(candidate.world != live, "current candidate does not reuse the active world")
	var standalone: Dictionary = current.duplicate(true)
	standalone.erase("continuity")
	standalone.assembly = ReolWorldAssemblyInputs.standalone(standalone.simulation.config)
	runner.assert_true(not standalone.assembly.is_empty(), "standalone input has an explicit independent assembly")
	runner.assert_eq(_json(SessionSaveSchema.upgrade(standalone)), _json(standalone), "current standalone root remains standalone without inventing a world")
	for version: int in [50, 51]:
		var previous: Dictionary = current.duplicate(true)
		previous.schema_version = version
		var input: String = _json(previous)
		runner.assert_true(SessionSaveSchema.upgrade(previous).is_empty() and WorldSessionSnapshot.stage(runtime, previous).is_empty(), "an old root label cannot route a current lifecycle through migration: %d" % version)
		runner.assert_eq(_json(previous), input, "refusing a mixed root leaves its input untouched: %d" % version)
	var ids: Array = current.continuity.world.artifacts.objects.keys()
	runner.assert_true(not ids.is_empty(), "ordinary opening contains a real unique item for location validation")
	for fault: String in ["missing_lifecycle", "damaged_content", "outside_player", "broken_object"]:
		if fault == "broken_object" and ids.is_empty():
			continue
		var bad: Dictionary = current.duplicate(true)
		match fault:
			"missing_lifecycle": bad.continuity.world.erase("object_lifecycle")
			"damaged_content": bad.content_bundle.documents[CLIMATE_PATH].regions.home.label = "corrupt archived content"
			"outside_player": bad.player.position = [-1.0, -1.0]
			"broken_object": bad.continuity.world.artifacts.objects[ids[0]].container = "ground:missing"
		var before: String = _json(bad)
		runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "current lifecycle candidate rejects " + fault)
		runner.assert_eq(_json(bad), before, "candidate validation does not repair " + fault)
		runner.assert_true(runtime.world_sim == live and live.map_data == terrain, "candidate failure retains live owners: " + fault)
		runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), stable, "candidate failure leaves the complete current session intact: " + fault)


func _earlier_solar_archive(runner: Object, runtime: WorldContinuityRuntime) -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(V49_PATH)
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	runner.assert_eq(FileAccess.get_sha256(V49_PATH), V49_SHA, "native root49 archive retains its recorded checksum")
	if bytes.is_empty() or not parsed is Dictionary:
		runner.assert_true(false, "native root49 archive is a readable dictionary")
		return
	var source: Dictionary = parsed
	var input: String = _json(source)
	var live: RegionalSimulation = runtime.world_sim
	var terrain: WorldMapData = live.map_data
	var before: String = _json(WorldSessionSnapshot.capture(runtime))
	runner.assert_eq(SessionSaveSchema.rejection_reason(source.get("schema_version")), SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT, "native root49 reports the retired environment")
	runner.assert_true(SessionSaveSchema.upgrade(source).is_empty() and WorldSessionSnapshot.stage(runtime, source).is_empty(), "native root49 does not import into the current lifecycle")
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(V49_PATH)), ERR_INVALID_DATA, "ordinary loader refuses the genuine root49 archive")
	runner.assert_true(runtime.world_sim == live and live.map_data == terrain, "old root refusal retains world and map owners")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, "old root refusal preserves the entire current session")
	runner.assert_eq(_json(source), input, "old root refusal does not mutate the source")
	runner.assert_eq(FileAccess.get_file_as_bytes(V49_PATH), bytes, "old root refusal preserves actual fixture bytes")
	runner.assert_eq(FileAccess.get_sha256(V49_PATH), V49_SHA, "native root49 checksum remains unchanged")


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
