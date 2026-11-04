extends RefCounted
## Immutable root48 bytes were written by the real pre-device code. Import
## preserves that frozen field and every old fact before adding empty ledgers.

const ARCHIVE: String = "res://tests/fixtures/session_v48_thermal.json"
const FUTURE: String = "res://tests/fixtures/session_v48_thermal_future.json"
const SOURCE_SHA: String = "216999c8399e8fff4c345bf8ad5dd375fa58c19cc66bae4510f43b47df1715d3"
const FUTURE_SHA: String = "51f8dd3824f3e411ac4d95504d3b62963a5f3bbb9ea884a333eaeea44a363419"
const HEAT_PATH: String = "res://data/definitions/local_heat.json"
const ARTIFACTS_PATH: String = "res://data/definitions/artifacts.json"
const FUTURE_MS: int = 957520
const DEVICE_FIELDS: Array[String] = ["continuous_input", "absorbed_energy", "device_input", "device_absorbed", "device_switches", "last_sample_continuous_input", "last_sample_absorbed", "segment_until_ms"]
const SolarProjection = preload("res://tests/runtime/helpers/solar_legacy_projection.gd")


func run(runner: Object) -> void:
	var bytes: String = FileAccess.get_file_as_string(ARCHIVE)
	var future_bytes: String = FileAccess.get_file_as_string(FUTURE)
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SOURCE_SHA, "the genuine root48 in-segment archive retains its independently recorded bytes")
	runner.assert_eq(FileAccess.get_sha256(FUTURE), FUTURE_SHA, "the old code's uninterrupted future retains its independently recorded bytes")
	var source: Dictionary = JSON.parse_string(bytes)
	var old_future: Dictionary = JSON.parse_string(future_bytes)
	var before: String = _json(source)
	var future_before: String = _json(old_future)
	runner.assert_eq(int(source.schema_version), 48, "the real source retains its old root format")
	runner.assert_eq(int(source.continuity.world.version), 40, "the real source retains its old regional format")
	runner.assert_eq(int(source.continuity.world.local_heat.version), 2, "the real source retains its fixed-reference v2 field")
	runner.assert_eq(int(source.continuity.world.artifacts.version), 7, "the real source predates device artifact state")
	runner.assert_true(not source.continuity.world.local_heat.cells.is_empty() and not source.continuity.world.local_heat.flows.is_empty(), "migration uses a genuine active frozen field rather than an empty relabelled current state")
	var current: Dictionary = SessionSaveSchema.upgrade(source)
	var expected_future: Dictionary = SessionSaveSchema.upgrade(old_future)
	runner.assert_true(not current.is_empty() and not expected_future.is_empty(), "both real root48 snapshots pass old and current independent candidates")
	runner.assert_eq(_json(source), before, "successful saved-instant upgrade never repairs the supplied old dictionary")
	runner.assert_eq(_json(old_future), future_before, "successful old-future upgrade never modifies its original dictionary")
	if current.is_empty() or expected_future.is_empty():
		return
	_original_fields(runner, current, source)
	_original_fields(runner, expected_future, old_future)
	runner.assert_eq(int(current.continuity.world.local_heat.segment_until_ms), 910000, "v2 conversion retains the original frozen endpoint rather than extending the segment from the save instant")
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary main initializes before thermal device migration")
	else:
		_load_and_future(runner, runtime, current, expected_future, source)
	main.free()
	GameClock.restore_state(saved_clock)
	runner.assert_eq(FileAccess.get_file_as_string(ARCHIVE), bytes, "pure upgrades, ordinary loading and rejection never rewrite genuine root48 bytes")
	runner.assert_eq(FileAccess.get_file_as_string(FUTURE), future_bytes, "continuation never rewrites the old code's genuine future")
	print("SCENARIO thermal device migration: genuine root48 active field and old-code future, exact old facts and content, ordinary load continuation, strict mixed-format/device rejection and atomic live-state preservation")


func _original_fields(runner: Object, current: Dictionary, prior: Dictionary) -> void:
	runner.assert_eq(int(current.schema_version), SessionSaveSchema.VERSION, "the old root explicitly reaches the current format")
	runner.assert_eq(int(current.continuity.world.version), RegionalSimulation.SCHEMA_VERSION, "the old region explicitly reaches the current format")
	runner.assert_eq(int(current.continuity.world.artifacts.version), SimArtifacts.VERSION, "the original artifact envelope explicitly advances")
	var heat: Dictionary = current.continuity.world.local_heat
	var old_heat: Dictionary = prior.continuity.world.local_heat
	runner.assert_eq(int(heat.version), SimLocalHeat.VERSION, "the original heat field explicitly advances")
	for field: String in ["continuous_input", "absorbed_energy", "last_sample_continuous_input", "last_sample_absorbed"]:
		runner.assert_eq(int(heat[field]), 0, "old history has no invented continuous device amount: " + field)
	for field: String in ["device_input", "device_absorbed", "device_switches"]:
		runner.assert_eq(_json(heat[field]), "{}", "old history has no invented per-device stock or activation: " + field)
	var projected_heat: Dictionary = heat.duplicate(true)
	for field: String in DEVICE_FIELDS:
		projected_heat.erase(field)
	projected_heat.version = old_heat.version
	projected_heat.rules_version = old_heat.rules_version
	runner.assert_eq(_json(projected_heat), _json(old_heat), "every original physical cell, flow, receipt, ledger, model epoch and historical sample survives unchanged")
	var old_rules: Dictionary = prior.content_bundle.documents[HEAT_PATH]
	var projected_rules: Dictionary = current.content_bundle.documents[HEAT_PATH].duplicate(true)
	runner.assert_eq(int(projected_rules.version), SimLocalHeat.VERSION, "the bound old thermal definition advances explicitly")
	projected_rules.version = old_rules.version
	runner.assert_eq(_json(projected_rules), _json(old_rules), "definition conversion preserves every original thermal coefficient and limit")
	var old_docs: Dictionary = prior.content_bundle.documents.duplicate(true)
	var new_docs: Dictionary = current.content_bundle.documents.duplicate(true)
	old_docs.erase(HEAT_PATH)
	new_docs.erase(HEAT_PATH)
	new_docs[SolarProjection.CLIMATE_PATH] = SolarProjection.prior_climate(current)
	runner.assert_true(not new_docs[SolarProjection.CLIMATE_PATH].is_empty(), "the bound climate gains exactly the fixed solar migration defaults")
	runner.assert_eq(_json(new_docs), _json(old_docs), "all original nonthermal content values remain exact after projecting the fixed solar addition")
	runner.assert_true(not current.content_bundle.documents[ARTIFACTS_PATH].types.has("fire_stone") and not current.content_bundle.documents[ARTIFACTS_PATH].types.has("cold_stone"), "old content gains neither of the new device types from disk")
	runner.assert_true(ReolContentBundle.is_valid(current.content_bundle, ReolContentDB.DOCUMENT_PATHS), "the explicitly converted heat and climate definitions receive a valid digest")
	var projected: Dictionary = current.duplicate(true)
	projected.schema_version = prior.schema_version
	projected.content_bundle = prior.content_bundle.duplicate(true)
	projected.continuity.world.version = prior.continuity.world.version
	projected.continuity.world.artifacts.version = prior.continuity.world.artifacts.version
	projected.continuity.world.local_heat = projected_heat
	projected.continuity.world.environment = SolarProjection.prior_environment(current.continuity.world.environment, prior.continuity.world.environment, current)
	runner.assert_eq(_json(projected), _json(prior), "after the explicit new contract is projected away, every original session field is still present and equal")


func _load_and_future(runner: Object, runtime: WorldContinuityRuntime, current: Dictionary, expected_future: Dictionary, source: Dictionary) -> void:
	var error: Error = runtime.load_game(ProjectSettings.globalize_path(ARCHIVE))
	runner.assert_eq(error, OK, "the ordinary current loader accepts the genuine active root48 archive")
	if error != OK:
		return
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), _json(current), "ordinary loading publishes exactly the independently converted complete session")
	GameClock.advance_msec(FUTURE_MS - GameClock.elapsed_ms)
	runner.assert_eq(int(runtime.world_sim.elapsed_ms), FUTURE_MS, "ordinary advancement reaches the old uninterrupted future instant")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), _json(expected_future), "current continuation has the same complete world, bodies, original objects, clock and sampled history as the real old code's uninterrupted future")
	_rejections(runner, runtime, source, current)


func _rejections(runner: Object, runtime: WorldContinuityRuntime, source: Dictionary, current: Dictionary) -> void:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "device-smuggling probe loads an actual current type definition")
		return
	var path: String = "user://tests/thermal_device_migration_%d.json" % Time.get_ticks_usec()
	var before: String = _json(WorldSessionSnapshot.capture(runtime))
	var clock: Dictionary = GameClock.to_dict()
	var live: RegionalSimulation = runtime.world_sim
	for kind: String in ["missing_old_field", "new_heat_in_old_root", "mixed_artifact_version", "smuggled_device"]:
		var bad: Dictionary = source.duplicate(true)
		match kind:
			"missing_old_field": bad.continuity.world.local_heat.erase("last_sample_mode")
			"new_heat_in_old_root": bad.continuity.world.local_heat = current.continuity.world.local_heat.duplicate(true)
			"mixed_artifact_version": bad.continuity.world.artifacts.version = SimArtifacts.VERSION
			"smuggled_device":
				bad.content_bundle.documents[ARTIFACTS_PATH].types["fire_stone"] = content.artifacts.types.fire_stone.duplicate(true)
				bad.content_bundle = ReolContentBundle.from_documents(bad.content_bundle.documents)
				bad.continuity.world.artifacts.objects["smuggled_fire_stone"] = {"definition": "fire_stone", "region": "home", "container": "kitchen", "stored_q": int(content.artifacts.types.fire_stone.thermal.opening_q), "enabled": false}
		var input: String = _json(bad)
		runner.assert_true(SessionSaveSchema.upgrade(bad).is_empty(), "strict old candidate rejects corruption before conversion: " + kind)
		runner.assert_eq(_json(bad), input, "failed old upgrade never repairs the malformed dictionary: " + kind)
		runner.assert_eq(SimSaveStore.save_file(path, bad), OK, "write only a temporary malformed candidate: " + kind)
		runner.assert_eq(runtime.load_game(path), ERR_INVALID_DATA, "ordinary load rejects the malformed old or mixed candidate: " + kind)
		runner.assert_true(runtime.world_sim == live, "rejected old device migration keeps the live regional authority: " + kind)
		runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, "rejected old device migration preserves every live fact: " + kind)
		runner.assert_eq(_json(GameClock.to_dict()), _json(clock), "rejected old device migration preserves the original common clock: " + kind)
	_remove(path)


func _remove(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
