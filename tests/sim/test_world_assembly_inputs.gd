extends RefCounted
## Pure assembly records and root migration. No saved facts are regenerated.

const SOURCE: String = "res://tests/fixtures/session_v42_exchange.json"


func run(runner: Object) -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if not raw is Dictionary:
		runner.assert_true(false, "real v42 fixture is readable")
		return
	var source: Dictionary = raw
	var legacy_content: ReolContentDB = ReolContentDB.legacy_v42()
	if legacy_content == null:
		runner.assert_true(false, "v42 compatibility content is available")
		return
	var current: Dictionary = source.duplicate(true)
	current.schema_version = 43
	current["content_bundle"] = legacy_content.content_bundle()
	_test_record(runner, current)
	_test_world_capture(runner, current)
	_test_root_migration(runner, source, current)
	print("SCENARIO assembly inputs: exact JSON format, saved opening ownership, immutable v42/v43 migration")


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


func _test_root_migration(runner: Object, source: Dictionary, current: Dictionary) -> void:
	var historical: Dictionary = current.duplicate(true)
	# These valid values differ from today's opening and must be taken from the
	# archive itself. None of them are world events or resource transactions.
	historical.continuity.world.regions.home.config.seed = int(historical.continuity.world.regions.home.config.seed) + 7
	historical.continuity.world.settings.event_budget = 8123
	historical.continuity.centers.home = [7, 9]
	var before: String = _json(historical)
	var migrated: Dictionary = SessionSaveSchema.upgrade(historical)
	runner.assert_true(not migrated.is_empty(), "a modern v43 with its own content bundle migrates")
	if migrated.is_empty():
		return
	runner.assert_eq(int(migrated.schema_version), SessionSaveSchema.VERSION, "v43 migrates through the assembly boundary to the current root")
	runner.assert_eq(int(migrated.assembly.region_configs.home.seed), int(historical.continuity.world.regions.home.config.seed), "migration uses the saved region configuration")
	runner.assert_eq(int(migrated.assembly.settings.event_budget), 8123, "migration uses the saved regional settings")
	runner.assert_eq(_json(migrated.assembly.centers), _json(historical.continuity.centers), "migration uses the saved centers")
	runner.assert_eq(_json(migrated.content_bundle), _json(historical.content_bundle), "migration keeps the exact archived content bundle")
	runner.assert_eq(_json(historical), before, "v43 migration does not mutate its source")
	var reconstructed: Dictionary = migrated.duplicate(true)
	reconstructed.erase("assembly")
	reconstructed.world.erase("terrain_overrides")
	reconstructed.schema_version = 43
	runner.assert_eq(_json(reconstructed), before, "migration adds no world history or resource state")
	var bad: Dictionary = migrated.duplicate(true)
	bad.erase("assembly")
	runner.assert_true(not SessionSaveSchema.is_valid_world(bad) and SessionSaveSchema.upgrade(bad).is_empty(), "v44 without assembly is rejected")
	bad = historical.duplicate(true)
	bad["assembly"] = migrated.assembly.duplicate(true)
	runner.assert_true(SessionSaveSchema.upgrade(bad).is_empty(), "v43 cannot smuggle a v44 assembly")
	bad = historical.duplicate(true)
	bad.erase("content_bundle")
	runner.assert_true(SessionSaveSchema.upgrade(bad).is_empty(), "v43 without its content bundle cannot use legacy fallback")
	bad = source.duplicate(true)
	bad["assembly"] = migrated.assembly.duplicate(true)
	runner.assert_true(SessionSaveSchema.upgrade(bad).is_empty(), "v42 cannot smuggle a v44 assembly")
	var from_42: Dictionary = SessionSaveSchema.upgrade(source)
	runner.assert_true(not from_42.is_empty(), "real v42 explicitly traverses v43 and v44")
	if not from_42.is_empty():
		runner.assert_eq(int(from_42.schema_version), SessionSaveSchema.VERSION, "v42 reaches current root version")
		runner.assert_eq(_json(from_42.assembly.region_configs.home), _json(source.continuity.world.regions.home.config), "v42 region input is not replaced with today's opening")
	var standalone: Dictionary = current.duplicate(true)
	standalone.erase("continuity")
	var upgraded_single: Dictionary = SessionSaveSchema.upgrade(standalone)
	runner.assert_true(not upgraded_single.is_empty(), "standalone v43 is migrated without creating a joint world")
	if not upgraded_single.is_empty():
		runner.assert_true(ReolWorldAssemblyInputs.is_valid(upgraded_single.assembly, false), "standalone v44 contains only home configuration")
		runner.assert_eq(_json(upgraded_single.assembly.region_configs.home), _json(standalone.simulation.config), "standalone migration uses its saved simulation config")


func _reject(runner: Object, value: Dictionary, reason: String) -> void:
	runner.assert_true(not ReolWorldAssemblyInputs.is_valid(value, true), "joint assembly rejects " + reason)


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
