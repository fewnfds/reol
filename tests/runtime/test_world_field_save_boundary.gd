extends RefCounted
## Ordinary loading never invents field history for a pre-field archive.

const LEGACY_FIXTURE: String = "res://tests/fixtures/session_v42_exchange.json"

var _factory_calls: int = 0


func run(runner: Object) -> void:
	_test_version_gate(runner)
	_test_ordinary_rejections(runner)


func _test_version_gate(runner: Object) -> void:
	runner.assert_eq(SessionSaveSchema.VERSION, 53, "new ordinary sessions declare root53")
	for version: int in range(1, SessionSaveSchema.VERSION):
		var source: Dictionary = {"schema_version": version, "sentinel": {"kept": true}}
		var original: String = _json(source)
		runner.assert_eq(SessionSaveSchema.rejection_reason(version), SessionSaveSchema.REJECTION_LEGACY_BUILDINGS if version == 52 else SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT, "older root is identified as legacy: %d" % version)
		runner.assert_true(not SessionSaveSchema.supports_version(version), "older root is not supported: %d" % version)
		runner.assert_true(SessionSaveSchema.upgrade(source, null, Callable(self, "_forbidden_factory")).is_empty(), "older root is not imported: %d" % version)
		runner.assert_true(WorldSessionSnapshot.stage(null, source).is_empty(), "older root is refused before consulting any active runtime: %d" % version)
		runner.assert_eq(_json(source), original, "refusing an old root leaves its input untouched: %d" % version)
	runner.assert_eq(_factory_calls, 0, "old-root refusal never calls a map factory")
	runner.assert_eq(SessionSaveSchema.rejection_reason(51.0), SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT, "JSON whole-number old version has the same reason")
	runner.assert_true(SessionSaveSchema.supports_version(53), "the current integer version is supported")
	runner.assert_true(SessionSaveSchema.supports_version(53.0), "the current JSON whole-number version is supported")
	for invalid: Variant in [null, false, "51", -1, 0, 1.5, 53.5, 54]:
		runner.assert_eq(SessionSaveSchema.rejection_reason(invalid), SessionSaveSchema.REJECTION_UNSUPPORTED_VERSION, "malformed or future version is not reported as a legacy environment: %s" % str(invalid))
		runner.assert_true(not SessionSaveSchema.supports_version(invalid), "malformed or future version is refused: %s" % str(invalid))
	var incomplete: Dictionary = {"schema_version": SessionSaveSchema.VERSION}
	runner.assert_true(SessionSaveSchema.upgrade(incomplete).is_empty(), "a current version label does not make an incomplete envelope valid")


func _test_ordinary_rejections(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary scene initializes for the version boundary")
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var live: RegionalSimulation = runtime.world_sim
	var live_map: WorldMapData = live.map_data
	var old_session := EnvironmentResponseSession.new()
	runner.assert_true(not old_session.configure(live, live._content.environment_sources, {}, Rect2i(0, 0, 16, 16)), "retired acceptance session cannot install a second actual field")
	runner.assert_true(not live.bind_environment_boundary_guard(old_session), "ordinary scheduler rejects the retired environment guard")
	runner.assert_true(not live.object_lifecycle.bind_environment_boundary_guard(old_session), "ordinary lifecycle rejects a guard that bypasses its field participant")
	var live_inventory: String = _json(live.regions.home.inventory.to_dict())
	var clock: String = _json(GameClock.to_dict())
	var player_cell: Vector2i = runtime.controlled_cell()
	var busy_path: String = "user://tests/field_busy_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(busy_path), OK, "accepted field boundary saves a real primary")
	runner.assert_eq(runtime.save_game(busy_path), OK, "accepted field boundary creates a real backup")
	var primary: String = FileAccess.get_file_as_string(busy_path)
	var backup: String = FileAccess.get_file_as_string(busy_path + ".bak")
	for kind: String in ["object_commit", "field_candidate"]:
		live.object_lifecycle._committing = kind == "object_commit"
		live.environment_fields._busy = kind == "field_candidate"
		runner.assert_true(WorldSessionSnapshot.capture(runtime).is_empty(), "unpublished world cannot become an envelope: " + kind)
		runner.assert_eq(runtime.save_game(busy_path), ERR_BUSY, "ordinary saver refuses unpublished world: " + kind)
		runner.assert_eq(FileAccess.get_file_as_string(busy_path), primary, "busy capture preserves primary: " + kind)
		runner.assert_eq(FileAccess.get_file_as_string(busy_path + ".bak"), backup, "busy capture preserves backup: " + kind)
		live.object_lifecycle._committing = false
		live.environment_fields._busy = false
	_remove_test_save(busy_path)
	var original_fixture: String = FileAccess.get_file_as_string(LEGACY_FIXTURE)
	runner.assert_true(not original_fixture.is_empty(), "a real legacy archive is available")
	if not original_fixture.is_empty():
		var result: Error = runtime.load_game(ProjectSettings.globalize_path(LEGACY_FIXTURE))
		runner.assert_eq(result, ERR_INVALID_DATA, "ordinary load rejects a real old environment archive")
		runner.assert_eq(runtime._notice, "旧环境格式不再支持，存档未改；请新开局。", "old archive displays the explicit version reason")
		_assert_live_unchanged(runner, runtime, live, live_map, live_inventory, clock, player_cell)
		runner.assert_eq(FileAccess.get_file_as_string(LEGACY_FIXTURE), original_fixture, "refusing the old archive does not change its file")
	var path: String = "user://tests/world_field_save_boundary_%d.json" % Time.get_ticks_usec()
	var written: Error = SimSaveStore.save_file(path, {"schema_version": SessionSaveSchema.VERSION})
	runner.assert_eq(written, OK, "a malformed current-version envelope is written as test data")
	if written == OK:
		var before: String = FileAccess.get_file_as_string(path)
		var result: Error = runtime.load_game(path)
		runner.assert_eq(result, ERR_INVALID_DATA, "ordinary load rejects a malformed current envelope")
		runner.assert_eq(runtime._notice, "近况里的时间、行动或账目不适用于当前世界。", "malformed current data keeps the normal validation error")
		_assert_live_unchanged(runner, runtime, live, live_map, live_inventory, clock, player_cell)
		runner.assert_eq(FileAccess.get_file_as_string(path), before, "refusing malformed current data does not change the file")
	_remove_test_save(path)
	main.free()
	GameClock.restore_state(saved_clock)


func _assert_live_unchanged(runner: Object, runtime: WorldContinuityRuntime, world: RegionalSimulation, terrain: WorldMapData, inventory: String, clock: String, player_cell: Vector2i) -> void:
	runner.assert_true(runtime.world_sim == world and runtime.world_sim.map_data == terrain, "failed loading preserves the live world and map owners")
	runner.assert_eq(_json(world.regions.home.inventory.to_dict()), inventory, "failed loading preserves the live inventory")
	runner.assert_eq(_json(GameClock.to_dict()), clock, "failed loading preserves the common clock")
	runner.assert_eq(runtime.controlled_cell(), player_cell, "failed loading preserves the player position")


func _forbidden_factory(_descriptor: Dictionary) -> WorldMapData:
	_factory_calls += 1
	return null


func _remove_test_save(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _json(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)
