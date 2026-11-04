extends RefCounted
## Root49 climate migration validates its original world before adding solar.

const Thermal = preload("res://scripts/persistence/thermal_import.gd")
const SolarProjection = preload("res://tests/runtime/helpers/solar_legacy_projection.gd")
const CLIMATE_PATH: String = "res://data/definitions/climate.json"
const V49_PATH: String = "res://tests/fixtures/session_v49_thermal.json"
const V49_SHA: String = "a6ae26fad7fff13394ec1a7c9831d5a1fdd85c191222b31213c7f9de138bf8bd"
const V49_FUTURE_SHA: String = "e49076030565daf86dc5764769b0710dd627bcc8a7d4a3cc0a28ce2069410e95"
const V49_FUTURE_STEP_MS: int = 35000
const V48_PATH: String = "res://tests/fixtures/session_v48_thermal.json"
const V48_SHA: String = "216999c8399e8fff4c345bf8ad5dd375fa58c19cc66bae4510f43b47df1715d3"
const V42_PATH: String = "res://tests/fixtures/session_v42_exchange.json"


func run(runner: Object) -> void:
	_historical_inputs(runner)
	_live_device_and_rejections(runner)
	print("SCENARIO solar migration: old thermal and standalone inputs, active original device, exact climate and facts, mixed-format rejection and ordinary continuation")


func _historical_inputs(runner: Object) -> void:
	var original: String = FileAccess.get_file_as_string(V48_PATH)
	runner.assert_eq(FileAccess.get_sha256(V48_PATH), V48_SHA, "solar migration starts from the independently recorded root48 bytes")
	var source: Dictionary = JSON.parse_string(original)
	var source_before: String = _json(source)
	var prior: Dictionary = Thermal.convert_v2(source)
	runner.assert_true(not prior.is_empty(), "the genuine root48 first reaches the independently validated root49 thermal boundary")
	if prior.is_empty():
		return
	runner.assert_eq(int(prior.schema_version), 49, "thermal import retains its historical root49 boundary")
	runner.assert_eq(int(prior.content_bundle.documents[CLIMATE_PATH].version), 1, "the thermal boundary still binds its original v1 climate")
	var current: Dictionary = SessionSaveSchema.upgrade(prior)
	runner.assert_true(not current.is_empty(), "the root49 candidate gains the current solar climate after validation")
	if current.is_empty():
		return
	_assert_converted(runner, prior, current, "genuine active thermal field")
	runner.assert_eq(_json(SessionSaveSchema.upgrade(source)), _json(current), "ordinary root48 migration passes through the same validated root49 solar boundary")
	runner.assert_eq(_json(source), source_before, "thermal and solar conversion never mutate the original archive dictionary")
	runner.assert_eq(FileAccess.get_file_as_string(V48_PATH), original, "the genuine root48 fixture remains byte-for-byte unchanged")
	var mixed: Dictionary = source.duplicate(true)
	mixed.content_bundle.documents[CLIMATE_PATH] = current.content_bundle.documents[CLIMATE_PATH].duplicate(true)
	mixed.content_bundle = ReolContentBundle.from_documents(mixed.content_bundle.documents)
	var mixed_before: String = _json(mixed)
	runner.assert_true(Thermal.convert_v2(mixed).is_empty(), "old thermal input cannot bind a newer climate even with a rebuilt digest")
	runner.assert_true(SessionSaveSchema.upgrade(mixed).is_empty(), "ordinary old-root import rejects the same mixed thermal and climate versions")
	runner.assert_eq(_json(mixed), mixed_before, "rejecting mixed old thermal input does not alter the supplied archive")
	var missing_old_config: Dictionary = source.duplicate(true)
	missing_old_config.erase("continuity")
	missing_old_config.assembly = ReolWorldAssemblyInputs.standalone(source.assembly.region_configs.home)
	missing_old_config.simulation.erase("config")
	runner.assert_true(not missing_old_config.assembly.is_empty(), "malformed standalone probe keeps independently valid assembly inputs")
	runner.assert_true(SessionSaveSchema._valid_world_fields(missing_old_config, 48), "missing old config reaches the standalone thermal validation boundary")
	var missing_before: String = _json(missing_old_config)
	runner.assert_true(Thermal.convert_v2(missing_old_config).is_empty(), "old standalone thermal input without its village config is rejected safely")
	runner.assert_eq(_json(missing_old_config), missing_before, "rejecting the missing old config does not change its input")

	var legacy_content: ReolContentDB = ReolContentDB.legacy_v42()
	runner.assert_true(legacy_content != null, "fixed pre-bundle compatibility content remains available for old candidates")
	if legacy_content == null:
		return
	var v42: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(V42_PATH))
	var v47: Dictionary = SessionSaveSchema._upgrade(v42, legacy_content)
	var v49: Dictionary = {} if v47.is_empty() else Thermal.convert(v47)
	runner.assert_true(not v49.is_empty(), "the actual pre-bundle archive reaches root49 before solar is added")
	if not v49.is_empty():
		var from_v42: Dictionary = SessionSaveSchema.upgrade(v42)
		runner.assert_true(not from_v42.is_empty(), "pre-bundle migration also reaches the current solar contract")
		if not from_v42.is_empty():
			_assert_converted(runner, v49, from_v42, "pre-bundle source")

	var standalone: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/session_v5.json"))
	standalone.erase("continuity")
	var single_v47: Dictionary = SessionSaveSchema._upgrade(standalone, legacy_content)
	var single_v49: Dictionary = {} if single_v47.is_empty() else Thermal.convert(single_v47)
	runner.assert_true(not single_v49.is_empty(), "historical standalone migration retains its no-regional-world boundary")
	if not single_v49.is_empty():
		var missing_config: Dictionary = single_v49.duplicate(true)
		missing_config.simulation.erase("config")
		runner.assert_true(SessionSaveSchema._valid_world_fields(missing_config, 49), "missing config reaches the standalone solar validation boundary")
		runner.assert_true(SessionSaveSchema.upgrade(missing_config).is_empty(), "standalone root49 without its village config is rejected safely")
		var single_current: Dictionary = SessionSaveSchema.upgrade(single_v49)
		runner.assert_true(not single_current.is_empty() and not single_current.has("continuity"), "standalone solar conversion cannot invent regional state")
		if not single_current.is_empty():
			_assert_converted(runner, single_v49, single_current, "standalone source")
			runner.assert_eq(_json(SessionSaveSchema.upgrade(standalone)), _json(single_current), "ordinary standalone old-root migration uses the same solar conversion")


func _live_device_and_rejections(runner: Object) -> void:
	var original: String = FileAccess.get_file_as_string(V49_PATH)
	var hash: String = FileAccess.get_sha256(V49_PATH)
	runner.assert_eq(hash, V49_SHA, "the native root49 checkpoint retains its independently recorded bytes")
	var parsed: Variant = JSON.parse_string(original)
	runner.assert_true(parsed is Dictionary, "the native root49 checkpoint is an archive dictionary")
	if hash != V49_SHA or not parsed is Dictionary:
		return
	var prior: Dictionary = parsed
	var prior_before: String = _json(prior)
	runner.assert_eq(int(prior.clock.elapsed_ms), 120173, "native checkpoint retains its original fractional clock")
	runner.assert_true(bool(prior.continuity.world.artifacts.objects.fire_stone.enabled), "native checkpoint retains its enabled original device")
	runner.assert_eq(int(prior.continuity.world.artifacts.objects.fire_stone.stored_q), 179827000, "native checkpoint retains the original device balance")
	runner.assert_eq(int(prior.continuity.world.local_heat.continuous_input), 173000, "native checkpoint retains the actual transferred heat")
	var current: Dictionary = SessionSaveSchema.upgrade(prior)
	runner.assert_true(not current.is_empty(), "genuine root49 with an enabled original device passes independent old and current candidates")
	runner.assert_eq(FileAccess.get_file_as_string(V49_PATH), original, "attempted conversion never rewrites the native root49 archive")
	if current.is_empty():
		return
	_assert_converted(runner, prior, current, "genuine active device")
	runner.assert_eq(_json(prior), prior_before, "successful solar migration leaves its original candidate untouched")
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary main initializes before native solar migration")
	else:
		_load_native_and_future(runner, runtime, prior, current)
	main.free()
	GameClock.restore_state(saved_clock)
	runner.assert_eq(FileAccess.get_file_as_string(V49_PATH), original, "conversion, rejection and restart never rewrite the native root49 archive")
	runner.assert_eq(FileAccess.get_sha256(V49_PATH), V49_SHA, "the native root49 archive retains its recorded hash after all operations")


func _load_native_and_future(runner: Object, runtime: WorldContinuityRuntime, prior: Dictionary, current: Dictionary) -> void:
	var loaded: Error = runtime.load_game(ProjectSettings.globalize_path(V49_PATH))
	runner.assert_eq(loaded, OK, "ordinary loader accepts the genuine native root49 archive")
	if loaded != OK:
		return
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), _json(current), "ordinary loading publishes exactly the independently converted complete session")
	var path: String = "user://tests/solar_migration_%d.json" % Time.get_ticks_usec()
	_rejections(runner, runtime, prior, current, path)
	var saved: Error = runtime.save_game(path)
	runner.assert_eq(saved, OK, "ordinary saving writes a current-format checkpoint to a temporary user path")
	if saved == OK:
		runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), _json(current), "current checkpoint retains the complete migrated session")
		GameClock.advance_msec(V49_FUTURE_STEP_MS)
		var future: Dictionary = WorldSessionSnapshot.capture(runtime)
		runner.assert_eq(int(GameClock.elapsed_ms), 155173, "the native checkpoint advances by the recorded 35000 ms")
		runner.assert_eq(int(runtime.world_sim.elapsed_ms), 155173, "the physical world reaches the same committed instant as the clock")
		runner.assert_eq(int(future.continuity.world.artifacts.objects.fire_stone.stored_q), 144827000, "the original enabled device reaches the recorded future balance")
		runner.assert_eq(int(future.continuity.world.local_heat.device_input.fire_stone), 35173000, "the heat ledger records exactly the original device's continued transfer")
		# Projection only compares with an independently captured pre-solar future;
		# no old input is constructed from the current state for migration.
		runner.assert_eq(_json(_prior_climate(future)).sha256_text(), V49_FUTURE_SHA, "every original future fact matches the native old-code digest after projecting the fixed solar addition")
		loaded = runtime.load_game(path)
		runner.assert_eq(loaded, OK, "ordinary loader accepts the saved current-format checkpoint")
		if loaded == OK:
			runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), _json(current), "current-format restart restores the same complete migrated checkpoint")
			GameClock.advance_msec(V49_FUTURE_STEP_MS)
			runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), _json(future), "current-format restart reaches the same complete future")
	_clean(path)


func _rejections(runner: Object, runtime: WorldContinuityRuntime, prior: Dictionary, current: Dictionary, path: String) -> void:
	var stable: String = _json(WorldSessionSnapshot.capture(runtime))
	var owner: RegionalSimulation = runtime.world_sim
	for fault: String in ["bad_digest", "old_has_solar", "old_has_modern_climate", "old_rules_version", "old_heat_ledger", "current_old_climate", "current_missing_solar", "current_invalid_vernal_day", "current_rules_version"]:
		var bad: Dictionary = current.duplicate(true) if fault.begins_with("current_") else prior.duplicate(true)
		var rebuild: bool = false
		match fault:
			"bad_digest": bad.content_bundle.documents[CLIMATE_PATH].regions.home.label = "damaged digest"
			"old_has_solar":
				bad.content_bundle.documents[CLIMATE_PATH]["solar"] = SimSolarRules.migration_defaults()
				rebuild = true
			"old_has_modern_climate":
				bad.content_bundle.documents[CLIMATE_PATH] = current.content_bundle.documents[CLIMATE_PATH].duplicate(true)
				rebuild = true
			"old_rules_version": bad.continuity.world.environment.rules_version = 2
			"old_heat_ledger": bad.continuity.world.local_heat.continuous_input = -1
			"current_old_climate":
				bad.content_bundle.documents[CLIMATE_PATH] = prior.content_bundle.documents[CLIMATE_PATH].duplicate(true)
				rebuild = true
			"current_missing_solar":
				bad.content_bundle.documents[CLIMATE_PATH].erase("solar")
				rebuild = true
			"current_invalid_vernal_day":
				bad.content_bundle.documents[CLIMATE_PATH].solar.vernal_day = SimWorldCalendar.days_per_year(bad.content_bundle.documents[CLIMATE_PATH].calendar)
				rebuild = true
			"current_rules_version": bad.continuity.world.environment.rules_version = 1
		if rebuild:
			bad.content_bundle = ReolContentBundle.from_documents(bad.content_bundle.documents)
		var before: String = _json(bad)
		runner.assert_true(SessionSaveSchema.upgrade(bad, null, Callable(runtime.home_runtime(), "create_candidate_map")).is_empty(), "mixed or damaged solar input is rejected: " + fault)
		runner.assert_eq(_json(bad), before, "rejected solar input is not repaired in place: " + fault)
		runner.assert_eq(SimSaveStore.save_file(path, bad), OK, "write a temporary malformed solar candidate: " + fault)
		runner.assert_eq(runtime.load_game(path), ERR_INVALID_DATA, "ordinary loader refuses malformed solar candidate: " + fault)
		runner.assert_true(runtime.world_sim == owner, "rejected candidate keeps the original live authority: " + fault)
		runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), stable, "rejected candidate preserves original clock, device and heat: " + fault)


func _prior_climate(current: Dictionary) -> Dictionary:
	var climate: Dictionary = SolarProjection.prior_climate(current)
	if current.get("schema_version") != 50 or climate.is_empty():
		return {}
	var prior: Dictionary = current.duplicate(true)
	prior.schema_version = 49
	prior.content_bundle.documents[CLIMATE_PATH] = climate
	prior.content_bundle = ReolContentBundle.from_documents(prior.content_bundle.documents)
	if prior.has("continuity"):
		if prior.continuity.world.environment.get("version") != 3 or prior.continuity.world.environment.get("rules_version") != 2:
			return {}
		prior.continuity.world.environment.rules_version = 1
	return prior


func _assert_converted(runner: Object, prior: Dictionary, current: Dictionary, label: String) -> void:
	runner.assert_eq(int(current.schema_version), 50, label + " reaches root50")
	runner.assert_eq(int(current.content_bundle.documents[CLIMATE_PATH].version), 2, label + " binds climate v2")
	runner.assert_eq(_json(current.content_bundle.documents[CLIMATE_PATH].solar), _json(SolarProjection.IMPORT_SOLAR), label + " uses the independently fixed import defaults")
	if current.has("continuity"):
		runner.assert_eq(int(current.continuity.world.environment.rules_version), 2, label + " binds the sampled environment to climate v2")
	runner.assert_eq(_json(_prior_climate(current)), _json(prior), label + " retains every original session value after projecting only solar and its rule version")


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _clean(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
