extends RefCounted
## Pure assembly records and retired-root rejection. No facts are regenerated.

const SOURCE: String = "res://tests/fixtures/session_v42_exchange.json"


func run(runner: Object) -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if not raw is Dictionary:
		runner.assert_true(false, "real v42 fixture is readable")
		return
	var source: Dictionary = raw
	_test_record(runner, source)
	_test_world_capture(runner, source)
	_test_retired_roots(runner, source)
	print("SCENARIO assembly inputs: exact JSON format, saved opening ownership and immutable retired-root rejection")


func _test_record(runner: Object, current: Dictionary) -> void:
	var recorded: Dictionary = current.continuity.world.duplicate(true)
	var centers: Dictionary = current.continuity.centers.duplicate(true)
	var original_seed: int = int(recorded.regions.home.config.seed)
	var original_center: int = int(centers.home[0])
	var value: Dictionary = ReolWorldAssemblyInputs.from_saved(recorded, centers)
	runner.assert_true(not value.is_empty(), "joint record is built from saved regional inputs")
	if value.is_empty():
		return
	runner.assert_true(ReolWorldAssemblyInputs.is_valid(value, true), "valid joint assembly is accepted")
	var encoded: String = _json(value)
	var decoded: Variant = JSON.parse_string(encoded)
	runner.assert_true(ReolWorldAssemblyInputs.is_valid(decoded, true), "whole-number coordinates survive a JSON round trip")
	runner.assert_eq(_json(decoded), encoded, "JSON round trip retains the complete assembly")
	recorded.regions.home.config.seed = original_seed + 1
	centers.home[0] = original_center + 1
	runner.assert_eq(int(value.region_configs.home.seed), original_seed, "captured opening configuration does not alias input")
	runner.assert_eq(int(value.centers.home[0]), original_center, "captured centers do not alias input")
	value.region_configs.home.seed = original_seed + 2
	runner.assert_eq(int(recorded.regions.home.config.seed), original_seed + 1, "editing an exported record does not edit its source")
	value = decoded

	var bad: Dictionary = value.duplicate(true)
	bad.erase("settings")
	_reject(runner, bad, "missing a required field")
	bad = value.duplicate(true)
	bad["other"] = 1
	_reject(runner, bad, "an undeclared field")
	bad = value.duplicate(true)
	bad.version = 1.5
	_reject(runner, bad, "a fractional version")
	bad = value.duplicate(true)
	bad.region_configs.home.navigation_budget = 0
	_reject(runner, bad, "an invalid simulation configuration")
	bad = value.duplicate(true)
	bad.region_configs[""] = bad.region_configs.home
	bad.region_configs.erase("home")
	_reject(runner, bad, "an empty region ID")
	bad = value.duplicate(true)
	bad.settings.regions.erase("river")
	_reject(runner, bad, "settings with a different region set")
	bad = value.duplicate(true)
	bad.centers.erase("river")
	_reject(runner, bad, "centers with a different region set")
	bad = value.duplicate(true)
	bad.settings.routes = []
	_reject(runner, bad, "settings with no route dictionary")
	bad = value.duplicate(true)
	bad.settings["not_json"] = Vector2i.ZERO
	_reject(runner, bad, "a non-JSON settings value")
	for cell: Variant in [[-1, 0], [0, -1], [WorldMapData.WORLD_SIZE, 0], [0, WorldMapData.WORLD_SIZE], [2.5, 0], [true, 0], [0], "0,0"]:
		bad = value.duplicate(true)
		bad.centers.home = cell
		_reject(runner, bad, "invalid center " + str(cell))
	# The format is not tied to the current two-place runtime.
	var arbitrary: Dictionary = value.duplicate(true)
	arbitrary.region_configs = {"north": value.region_configs.home.duplicate(true)}
	arbitrary.settings.regions = {"north": value.settings.regions.home.duplicate(true)}
	arbitrary.settings.routes = {}
	arbitrary.settings.active_region = "north"
	arbitrary.centers = {"north": [0, WorldMapData.WORLD_SIZE - 1]}
	runner.assert_true(ReolWorldAssemblyInputs.is_valid(arbitrary, true), "generic joint format allows non-home and non-river region IDs")
	var single: Dictionary = ReolWorldAssemblyInputs.standalone(value.region_configs.home)
	runner.assert_true(ReolWorldAssemblyInputs.is_valid(single, false), "standalone assembly has one home and no joint settings or centers")
	runner.assert_true(not ReolWorldAssemblyInputs.is_valid(single, true), "standalone input cannot masquerade as joint input")
	bad = single.duplicate(true)
	bad.centers.home = [0, 0]
	runner.assert_true(not ReolWorldAssemblyInputs.is_valid(bad, false), "standalone input rejects joint centers")


func _test_world_capture(runner: Object, current: Dictionary) -> void:
	var saved: Dictionary = current.continuity.world
	var world := RegionalSimulation.new()
	world.settings = saved.settings.duplicate(true)
	for id: String in saved.regions:
		var simulation := VillageSimulation.new()
		simulation.config = saved.regions[id].config.duplicate(true)
		world.regions[id] = simulation
		world._opening_configs[id] = simulation.config.duplicate(true)
	var initial_seed: int = int(world.opening_config("home").seed)
	(world.regions.home as VillageSimulation).config.seed = initial_seed + 10
	var centers: Dictionary = current.continuity.centers.duplicate(true)
	var captured: Dictionary = ReolWorldAssemblyInputs.from_world(world, centers)
	runner.assert_true(not captured.is_empty(), "live world exports a valid independent assembly record")
	if captured.is_empty():
		return
	runner.assert_eq(int(captured.region_configs.home.seed), initial_seed, "capture reads the original opening config rather than a later live mutation")
	var original_budget: int = int(captured.settings.event_budget)
	var original_center: int = int(captured.centers.home[0])
	world.settings.event_budget = original_budget + 1
	centers.home[0] = original_center + 1
	runner.assert_eq(int(captured.settings.event_budget), original_budget, "capture owns a deep copy of regional settings")
	runner.assert_eq(int(captured.centers.home[0]), original_center, "capture owns a deep copy of JSON centers")


func _test_retired_roots(runner: Object, source: Dictionary) -> void:
	var original: String = _json(source)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SOURCE)
	runner.assert_eq(int(source.get("schema_version", -1)), 42, "fixture is an actual root42 archive")
	runner.assert_eq(SessionSaveSchema.rejection_reason(source.get("schema_version")), SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT, "actual root42 identifies the retired environment")
	runner.assert_true(SessionSaveSchema.upgrade(source).is_empty(), "actual root42 cannot enter the current schema")
	runner.assert_true(WorldSessionSnapshot.stage(null, source).is_empty(), "actual root42 is refused before any runtime is consulted")
	var historical: Dictionary = source.duplicate(true)
	# Extract an independent record from saved inputs without treating it as a
	# migrated world. These changes are only a synthetic assembly-record probe.
	historical.continuity.world.regions.home.config.seed = int(historical.continuity.world.regions.home.config.seed) + 7
	historical.continuity.world.settings.event_budget = 8123
	historical.continuity.centers.home = [7, 9]
	var before: String = _json(historical)
	var assembly: Dictionary = ReolWorldAssemblyInputs.from_saved(historical.continuity.world, historical.continuity.centers)
	runner.assert_true(not assembly.is_empty(), "saved inputs can form an independent assembly record")
	if assembly.is_empty():
		return
	runner.assert_eq(int(assembly.region_configs.home.seed), int(historical.continuity.world.regions.home.config.seed), "assembly uses the saved region configuration")
	runner.assert_eq(int(assembly.settings.event_budget), 8123, "assembly uses the saved regional settings")
	runner.assert_eq(_json(assembly.centers), _json(historical.continuity.centers), "assembly uses the saved centers")
	runner.assert_eq(_json(historical), before, "building assembly does not mutate its source")
	# The real v42 and synthetic mixed envelopes all stop at the root boundary;
	# a separately valid assembly must not make their missing field history valid.
	for version: int in [42, 43, 47]:
		var candidate: Dictionary = historical.duplicate(true)
		candidate.schema_version = version
		candidate["assembly"] = assembly.duplicate(true)
		var input: String = _json(candidate)
		runner.assert_eq(SessionSaveSchema.rejection_reason(version), SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT, "retired root %d identifies its old environment" % version)
		runner.assert_true(SessionSaveSchema.upgrade(candidate).is_empty(), "retired root %d cannot import even with assembly" % version)
		runner.assert_true(WorldSessionSnapshot.stage(null, candidate).is_empty(), "retired root %d is refused before an active runtime is consulted" % version)
		runner.assert_eq(_json(candidate), input, "retired root %d candidate is not mutated" % version)
	var standalone: Dictionary = historical.duplicate(true)
	standalone.erase("continuity")
	var standalone_before: String = _json(standalone)
	runner.assert_true(SessionSaveSchema.upgrade(standalone).is_empty(), "retired standalone input cannot create a current world")
	runner.assert_true(WorldSessionSnapshot.stage(null, standalone).is_empty(), "retired standalone input is rejected before runtime access")
	runner.assert_eq(_json(standalone), standalone_before, "retired standalone input remains unchanged")
	runner.assert_eq(_json(source), original, "assembly probes preserve the genuine input dictionary")
	runner.assert_eq(FileAccess.get_file_as_bytes(SOURCE), bytes, "assembly probes preserve the actual fixture bytes")


func _reject(runner: Object, value: Dictionary, reason: String) -> void:
	runner.assert_true(not ReolWorldAssemblyInputs.is_valid(value, true), "joint assembly rejects " + reason)


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
