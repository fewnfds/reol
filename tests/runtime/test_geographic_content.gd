extends RefCounted
## Geography is compiled only while creating an independent opening. Saved
## worlds retain their own actual climate curves and never consult a profile.

const Geographic = preload("res://scripts/data/geographic_content.gd")
const CLIMATE_PATH: String = "res://data/definitions/climate.json"
const GEOGRAPHY_PATH: String = "res://data/scenarios/world_geography.json"
const V49_PATH: String = "res://tests/fixtures/session_v49_thermal.json"
const V49_SHA: String = "a6ae26fad7fff13394ec1a7c9831d5a1fdd85c191222b31213c7f9de138bf8bd"
const FUTURE_STEP_MS: int = 62347


func run(runner: Object) -> void:
	_test_isolated_content(runner)
	_test_ordinary_openings_and_archives(runner)
	print("SCENARIO geographic content: isolated creation, two real openings, archived curves, current restart and genuine pre-geography archive rejection")


func _test_isolated_content(runner: Object) -> void:
	var source := ReolContentDB.new()
	var loaded: bool = source.load_all()
	runner.assert_true(loaded, "geographic creation starts with a valid original content database")
	if not loaded:
		return
	var bundle: Dictionary = source.content_bundle()
	var profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(GEOGRAPHY_PATH))
	runner.assert_true(profile is Dictionary, "the ordinary opening geography is an explicit profile")
	if not profile is Dictionary:
		return
	var original_bundle: String = _json(bundle)
	var original_profile: String = _json(profile)
	var candidate: ReolContentDB = Geographic.build(bundle, profile)
	runner.assert_true(candidate != null, "valid geography builds an independently validated content candidate")
	runner.assert_eq(_json(bundle), original_bundle, "compilation does not mutate the supplied bundle")
	runner.assert_eq(_json(profile), original_profile, "compilation does not mutate the supplied profile")
	runner.assert_eq(_json(source.content_bundle()), original_bundle, "compilation does not replace the original content database")
	if candidate == null:
		return
	var created: Dictionary = candidate.content_bundle()
	runner.assert_true(ReolContentBundle.is_valid(created, ReolContentDB.DOCUMENT_PATHS), "compiled actual curves receive a validated content digest")
	runner.assert_true(str(created.digest) != str(bundle.digest), "geographic climate has its own content version")
	runner.assert_eq(_json(created.documents[CLIMATE_PATH].solar), _json(profile.solar), "the candidate binds its supplied solar geography")
	runner.assert_true(_json(created.documents[CLIMATE_PATH].regions) != _json(bundle.documents[CLIMATE_PATH].regions), "compiled regional curves differ from the source template")
	for path: String in bundle.documents:
		if path != CLIMATE_PATH:
			runner.assert_eq(_json(created.documents[path]), _json(bundle.documents[path]), "geographic compilation preserves the unrelated original document: " + path)
	var frozen: String = _json(created)
	profile.solar.latitude_mdeg = -45000
	bundle.documents[CLIMATE_PATH].regions.home.base_tenths = -100
	created.documents[CLIMATE_PATH].regions.home.base_tenths = 100
	runner.assert_eq(_json(candidate.content_bundle()), frozen, "mutating input and exported copies cannot rewrite the accepted curves")
	runner.assert_eq(_json(source.content_bundle()), original_bundle, "mutating the caller's bundle cannot rewrite its source database")

	var fresh_bundle: Dictionary = source.content_bundle()
	var fresh_profile: Dictionary = JSON.parse_string(original_profile)
	for fault: String in ["missing_region", "latitude_out_of_range", "unexpected_field"]:
		var bad: Dictionary = fresh_profile.duplicate(true)
		match fault:
			"missing_region": bad.regions.erase("river")
			"latitude_out_of_range": bad.solar.latitude_mdeg = 90001
			"unexpected_field": bad["invented"] = 1
		var before: String = _json(bad)
		runner.assert_true(Geographic.build(fresh_bundle, bad) == null, "invalid geography is rejected: " + fault)
		runner.assert_eq(_json(bad), before, "rejected profile is not repaired in place: " + fault)
	var damaged: Dictionary = fresh_bundle.duplicate(true)
	damaged.documents[CLIMATE_PATH].regions.home.base_tenths = 0
	runner.assert_true(Geographic.build(damaged, fresh_profile) == null, "a changed bundle without a matching digest cannot be compiled")
	runner.assert_eq(_json(fresh_bundle), original_bundle, "failed compilation leaves the valid source bundle unchanged")
	runner.assert_true(Geographic.build(fresh_bundle, fresh_profile) != null, "a valid candidate still builds after rejected inputs")


func _test_ordinary_openings_and_archives(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	var source := ReolContentDB.new()
	if not source.load_all():
		runner.assert_true(false, "real geography openings can load original content")
		return
	var profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(GEOGRAPHY_PATH))
	if not profile is Dictionary:
		runner.assert_true(false, "real geography openings have a valid default profile")
		return
	var expected_default: ReolContentDB = Geographic.build(source.content_bundle(), profile)
	if expected_default == null:
		runner.assert_true(false, "the default geographic profile compiles for the real opening")
		return
	var path: String = "user://tests/geographic_content_%d.json" % Time.get_ticks_usec()
	_reset_clock()
	var preflight: Node = load("res://scenes/main.tscn").instantiate()
	runner.assert_true(preflight.configure_opening_content(expected_default.content_bundle()), "an independently compiled bundle can configure a new Main")
	runner.assert_true(not preflight.configure_opening_content(source.content_bundle()), "content cannot be configured twice before opening")
	runner.assert_true(not preflight.configure_opening_geography(profile), "a geography profile cannot replace already configured content")
	preflight.free()
	var first: Node = load("res://scenes/main.tscn").instantiate()
	var invalid: Dictionary = profile.duplicate(true)
	invalid.solar.latitude_mdeg = 90001
	runner.assert_true(not first.configure_opening_geography(invalid), "invalid profile is rejected before an opening enters the tree")
	var wrong_clock: Dictionary = source.content_bundle()
	wrong_clock.documents[CLIMATE_PATH].calendar.start_minutes = 481
	wrong_clock = ReolContentBundle.from_documents(wrong_clock.documents)
	runner.assert_true(not first.configure_opening_content(wrong_clock), "opening rejects content whose calendar disagrees with the original clock")
	runner.root.add_child(first)
	var first_runtime: WorldContinuityRuntime = first._continuity
	if first_runtime == null or first_runtime.world_sim == null:
		runner.assert_true(false, "default Main enters a real running world after rejected configurations")
		first.free()
		GameClock.restore_state(saved_clock)
		_remove(path)
		return
	var default_content: Dictionary = expected_default.content_bundle()
	runner.assert_eq(_json(first._content.content_bundle()), _json(default_content), "ordinary Main compiles the configured default geography")
	runner.assert_eq(_json(first_runtime.world_sim.environment.definitions), _json(default_content.documents[CLIMATE_PATH]), "real environment uses those exact default curves")
	runner.assert_true(not first.configure_opening_geography(profile), "a running Main cannot replace its geography")
	runner.assert_true(not first.configure_opening_content(source.content_bundle()), "a running Main cannot replace its content")
	var checkpoint: String = _json(WorldSessionSnapshot.capture(first_runtime))
	var saved: Error = first_runtime.save_game(path)
	runner.assert_eq(saved, OK, "the real default opening saves its compiled climate")
	var expected_future: String = ""
	if saved == OK:
		GameClock.advance_msec(FUTURE_STEP_MS)
		runner.assert_eq(first_runtime.world_sim.elapsed_ms, FUTURE_STEP_MS, "the first world advances its original physical clock")
		expected_future = _json(WorldSessionSnapshot.capture(first_runtime))
	first.free()

	_reset_clock()
	var second: Node = load("res://scenes/main.tscn").instantiate()
	runner.assert_true(not second.configure_opening_geography(invalid), "a rejected profile does not consume the custom opening")
	var custom: Dictionary = profile.duplicate(true)
	custom.solar.latitude_mdeg = -60000
	var expected_custom: ReolContentDB = Geographic.build(source.content_bundle(), custom)
	runner.assert_true(expected_custom != null, "the second opening has an independently valid southern geography")
	var configured: bool = second.configure_opening_geography(custom)
	runner.assert_true(configured, "a valid profile can be configured after rejection")
	if configured:
		runner.assert_true(not second.configure_opening_geography(profile), "a second geography configuration is rejected")
		runner.assert_true(not second.configure_opening_content(source.content_bundle()), "content cannot replace an already configured geography")
		var pending: String = _json(second._opening_content.content_bundle())
		custom.solar.latitude_mdeg = 90000
		runner.assert_eq(_json(second._opening_content.content_bundle()), pending, "the configured opening is isolated from later profile edits")
	runner.root.add_child(second)
	var runtime: WorldContinuityRuntime = second._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "custom Main starts a real world")
		second.free()
		GameClock.restore_state(saved_clock)
		_remove(path)
		return
	if expected_custom != null and configured:
		var custom_bundle: Dictionary = expected_custom.content_bundle()
		runner.assert_eq(_json(second._content.content_bundle()), _json(custom_bundle), "the second real world uses its custom compiled curves")
		runner.assert_true(str(custom_bundle.digest) != str(default_content.digest), "the two real openings have different climate content versions")
		runner.assert_true(_json(custom_bundle.documents[CLIMATE_PATH].regions) != _json(default_content.documents[CLIMATE_PATH].regions), "different latitudes produce different actual temperature curves")
	runner.assert_true(not second.configure_opening_geography(profile), "the second running Main also rejects replacement")
	if saved == OK:
		var restored: Error = runtime.load_game(path)
		runner.assert_eq(restored, OK, "the custom world loads the first world's ordinary saved checkpoint")
		if restored == OK:
			runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), checkpoint, "load restores the complete original checkpoint without recompiling it")
			runner.assert_eq(_json(runtime.world_sim.environment.definitions), _json(default_content.documents[CLIMATE_PATH]), "the archive curves, not the second opening profile, own temperature")
			runner.assert_eq(_json(second._content.content_bundle()), _json(default_content), "Main is rebound to the restored content version")
			GameClock.advance_msec(FUTURE_STEP_MS)
			runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), expected_future, "loading into a differently configured Main produces the same complete future")
	_test_legacy_archive(runner, runtime)
	second.free()
	GameClock.restore_state(saved_clock)
	_remove(path)


func _test_legacy_archive(runner: Object, runtime: WorldContinuityRuntime) -> void:
	var original: PackedByteArray = FileAccess.get_file_as_bytes(V49_PATH)
	var parsed: Variant = JSON.parse_string(original.get_string_from_utf8())
	runner.assert_eq(FileAccess.get_sha256(V49_PATH), V49_SHA, "the genuine pre-geography archive retains its recorded hash")
	if original.is_empty() or not parsed is Dictionary:
		runner.assert_true(false, "the genuine pre-geography archive is readable")
		return
	var source: Dictionary = parsed
	var input: String = _json(source)
	var live: RegionalSimulation = runtime.world_sim
	var terrain: WorldMapData = live.map_data
	var before: String = _json(WorldSessionSnapshot.capture(runtime))
	runner.assert_eq(SessionSaveSchema.rejection_reason(source.get("schema_version")), SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT, "the old climate archive reports the retired environment")
	runner.assert_true(SessionSaveSchema.upgrade(source).is_empty() and WorldSessionSnapshot.stage(runtime, source).is_empty(), "old geography cannot be staged into a current world")
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(V49_PATH)), ERR_INVALID_DATA, "the ordinary loader rejects the genuine old climate archive")
	runner.assert_true(runtime.world_sim == live and live.map_data == terrain, "rejection retains the current world and map")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, "rejection preserves the entire current climate session")
	runner.assert_eq(_json(source), input, "the old input dictionary remains unchanged")
	runner.assert_eq(FileAccess.get_file_as_bytes(V49_PATH), original, "the historical fixture bytes remain unchanged")
	runner.assert_eq(FileAccess.get_sha256(V49_PATH), V49_SHA, "the historical fixture hash remains unchanged")


func _reset_clock() -> void:
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})


func _remove(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
