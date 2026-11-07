extends RefCounted
## Content versions belong to a saved session; the player and NPC views are
## projections of the same candidate content, never a second source of truth.

const V42_PATH: String = "res://tests/fixtures/session_v42_exchange.json"
const V42_SHA: String = "e13c2616a25f482db2397b585417d027c2759172393c6929eb98a4713b676ebf"
const PAWNS_PATH: String = "res://data/definitions/pawns.json"
const SERVICES_PATH: String = "res://data/definitions/settlement_services.json"
const NATURE_PATH: String = "res://data/definitions/natural_environment.json"


func run(runner: Object) -> void:
	_test_bundle_ownership(runner)
	_test_real_session_and_legacy(runner)


func _test_bundle_ownership(runner: Object) -> void:
	var old := ReolContentDB.new()
	runner.assert_true(old.load_all(), "opening definitions load before content version isolation")
	if old.get_pawn(&"player") == null:
		runner.assert_true(false, "opening content provides the player's definition")
		return
	var old_max: int = old.get_pawn(&"player").max_stamina
	var original: Dictionary = old.content_bundle()
	var saved: String = _json(original)
	runner.assert_eq(int(original.version), ReolContentBundle.VERSION, "the ordinary frozen bundle records the current content format")
	runner.assert_true(original.documents.has(ReolContentDB.ENVIRONMENT_SOURCES_PATH), "the current bundle contains its environment source definitions")
	runner.assert_true(old.environment_sources != null and old.environment_sources.is_configured(), "the loaded content owns configured environment source definitions")
	if old.environment_sources != null and original.documents.has(ReolContentDB.ENVIRONMENT_SOURCES_PATH):
		runner.assert_eq(_json(old.environment_sources.to_dict()), _json(original.documents[ReolContentDB.ENVIRONMENT_SOURCES_PATH]), "the source definitions come from this bundle")
		runner.assert_eq(old.environment_sources.digest(), JSON.stringify(old.environment_sources.to_dict(), "", true).sha256_text(), "the loaded source profile records its own canonical digest")
	var legacy_documents: Dictionary = original.documents.duplicate(true)
	legacy_documents.erase(ReolContentDB.ENVIRONMENT_SOURCES_PATH)
	var legacy_bundle: Dictionary = ReolContentBundle.from_documents(legacy_documents, ReolContentBundle.LEGACY_VERSION)
	var legacy_content := ReolContentDB.new()
	runner.assert_true(legacy_content.load_bundle(legacy_bundle), "an isolated v1 definition bundle remains parseable under its original manifest")
	runner.assert_true(legacy_content.environment_sources == null, "a v1 definition bundle does not silently borrow field profiles from disk")
	var documents: Dictionary = original.documents.duplicate(true)
	runner.assert_true(_set_player_max(documents, old_max + 35), "test changes the existing player definition without adding an identity")
	var newer: Dictionary = ReolContentBundle.from_documents(documents)
	var candidate := ReolContentDB.new()
	runner.assert_true(candidate.load_bundle(newer), "an independent content database accepts the edited template version")
	if candidate.get_pawn(&"player") == null:
		runner.assert_true(false, "edited content still exposes the existing player")
		return
	runner.assert_eq(old.get_pawn(&"player").max_stamina, old_max, "editing the template copy leaves the prior database unchanged")
	runner.assert_eq(candidate.get_pawn(&"player").max_stamina, old_max + 35, "the new database uses the edited value for the same ID")
	runner.assert_true(str(original.digest) != str(newer.digest), "distinct definitions have distinct content digests")
	runner.assert_true(not old.load_bundle(newer), "a live database refuses replacement by another version")
	runner.assert_true(not old.load_all(), "a live database refuses an in-place disk reload")
	runner.assert_eq(old.get_pawn(&"player").max_stamina, old_max, "refused reloads preserve the original definition")
	runner.assert_eq(_json(old.content_bundle()), saved, "refused reloads preserve the original frozen documents")
	# Neither the input document nor the returned copy may alias the DB's stored
	# source. A later editor can work on either without altering this version.
	_set_player_max(documents, old_max + 70)
	_set_player_max(newer.documents, old_max + 90)
	var returned: Dictionary = candidate.content_bundle()
	_set_player_max(returned.documents, old_max + 110)
	runner.assert_eq(candidate.get_pawn(&"player").max_stamina, old_max + 35, "changing input and exported copies cannot change the accepted definition")
	runner.assert_eq(_player_max(candidate.content_bundle().documents), old_max + 35, "the accepted source remains an independent deep copy")
	var bad_documents: Dictionary = original.documents.duplicate(true)
	bad_documents.erase(PAWNS_PATH)
	var bad := ReolContentDB.new()
	runner.assert_true(not bad.load_bundle(ReolContentBundle.from_documents(bad_documents)), "missing documents do not fall back to the disk")
	bad_documents = original.documents.duplicate(true)
	bad_documents[_undeclared_path()] = {}
	bad = ReolContentDB.new()
	runner.assert_true(not bad.load_bundle(ReolContentBundle.from_documents(bad_documents)), "undeclared documents cannot silently alter the bundle")
	bad_documents = original.documents.duplicate(true)
	_set_player_max(bad_documents, 0)
	bad = ReolContentDB.new()
	runner.assert_true(not bad.load_bundle(ReolContentBundle.from_documents(bad_documents)), "a valid digest cannot make invalid pawn definitions acceptable")
	bad_documents = original.documents.duplicate(true)
	bad_documents.erase(ReolContentDB.ENVIRONMENT_SOURCES_PATH)
	bad = ReolContentDB.new()
	runner.assert_true(not bad.load_bundle(ReolContentBundle.from_documents(bad_documents)), "a current bundle cannot omit its environment source definitions")
	bad_documents = original.documents.duplicate(true)
	bad_documents[ReolContentDB.ENVIRONMENT_SOURCES_PATH].profiles.none.thermal_grade = 1
	var bad_source_bundle: Dictionary = ReolContentBundle.from_documents(bad_documents)
	runner.assert_true(ReolContentBundle.is_valid(bad_source_bundle, ReolContentDB.DOCUMENT_PATHS), "the malformed source example has a complete manifest and correctly recomputed digest")
	bad = ReolContentDB.new()
	runner.assert_true(not bad.load_bundle(bad_source_bundle), "a valid digest cannot make an invalid source profile acceptable")


func _test_real_session_and_legacy(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary scene initializes for content migration")
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var path: String = "user://tests/content_bundle_%d.json" % Time.get_ticks_usec()
	var first: Dictionary = WorldSessionSnapshot.capture(runtime)
	var base_max: int = runtime._home._content.get_pawn(&"player").max_stamina
	var original_json: String = _json(first)
	var live_map: WorldMapData = runtime.world_sim.map_data
	var sample_cell: Vector2i = runtime.controlled_cell()
	var before_nature: Dictionary = live_map.natural_cell(sample_cell)
	var surface_id: String = str(before_nature.surface_id)
	var base_label: String = str(live_map.natural_surface_definitions()[surface_id].label)
	var base_metal: int = live_map.natural_affinity(sample_cell, "metal")
	var changed_label: String = base_label + "·乙"
	var changed_element: int = 0 if base_metal > 50 else 100
	var documents: Dictionary = first.content_bundle.documents.duplicate(true)
	runner.assert_true(_set_player_max(documents, base_max + 35), "a second template changes the same player ID")
	var base_travel: int = int(runtime.world_sim.services.definitions.move_minutes_per_cell)
	documents[SERVICES_PATH].move_minutes_per_cell = base_travel + 1
	documents[NATURE_PATH].surfaces[surface_id].label = changed_label
	documents[NATURE_PATH].surfaces[surface_id].elements[0] = changed_element
	var second: Dictionary = first.duplicate(true)
	second.content_bundle = ReolContentBundle.from_documents(documents)
	# This opening has no service job in flight; the recorded service's own
	# definition must agree with its new bundle, just as it would in a new world.
	second.continuity.world.services.definitions.move_minutes_per_cell = base_travel + 1
	var live_world: RegionalSimulation = runtime.world_sim
	var live_content: ReolContentDB = runtime._home._content
	var live_clock: String = _json(GameClock.to_dict())
	var observations: Array[Dictionary] = []
	var changed_metal: int = -1
	runtime._home.content_replaced.connect(func(emitted: ReolContentDB) -> void:
		# The callback acts like a different system observing the publication.
		# Capturing here catches a signal sent before clock/map/world replacement.
		var context: Dictionary = runtime._home.snapshot_context()
		var captured: Dictionary = WorldSessionSnapshot.capture(runtime)
		var observed_map: WorldMapData = runtime.world_sim.map_data
		observations.append({
			"context_content": context.content == emitted,
			"world_content": runtime.world_sim._content == emitted,
			"main_content": main._content == emitted,
			"home_simulation": runtime._home.simulation == runtime.world_sim.regions.home,
			"view_map": runtime._home._world.map_data() == observed_map,
			"clock_ms": GameClock.elapsed_ms,
			"world_ms": runtime.world_sim.elapsed_ms,
			"captured": captured,
			"label": str(observed_map.natural_surface_definitions()[surface_id].label),
			"metal": observed_map.natural_affinity(sample_cell, "metal"),
		})
	)
	var staged: Dictionary = WorldSessionSnapshot.stage(runtime, second)
	runner.assert_true(not staged.is_empty(), "the edited content builds a validated independent session candidate")
	if not staged.is_empty():
		runner.assert_true(staged.content != live_content, "staging owns a separate content database")
		runner.assert_eq(staged.content.get_pawn(&"player").max_stamina, base_max + 35, "candidate simulation uses the requested content version")
		runner.assert_eq(int(staged.world.services.definitions.move_minutes_per_cell), base_travel + 1, "candidate services use their archived definition, not the live world's definition")
		var candidate_map: WorldMapData = staged.map
		runner.assert_eq(str(candidate_map.natural_surface_definitions()[surface_id].label), changed_label, "candidate map uses the archived surface label")
		changed_metal = candidate_map.natural_affinity(sample_cell, "metal")
		runner.assert_true(changed_metal != base_metal, "candidate map uses the archived five-phase surface value")
	runner.assert_true(runtime.world_sim == live_world and runtime._home._content == live_content and runtime.world_sim.map_data == live_map, "staging does not replace live world, content, or map")
	runner.assert_eq(_json(live_map.natural_cell(sample_cell)), _json(before_nature), "candidate nature rules do not change the live map or its cached cell")
	runner.assert_eq(observations.size(), 0, "staging publishes no content-replaced signal")
	runner.assert_eq(_json(GameClock.to_dict()), live_clock, "staging does not change the shared clock")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), original_json, "staging preserves all original session facts")
	GameClock.advance_msec(2500)
	runner.assert_true(GameClock.elapsed_ms != int(second.clock.elapsed_ms), "content publication must restore a different saved instant")
	runner.assert_eq(SimSaveStore.save_file(path, second), OK, "write independent new-version session")
	var loaded: Error = runtime.load_game(path)
	runner.assert_eq(loaded, OK, "ordinary loading commits the validated new-version session")
	if loaded == OK:
		runner.assert_eq(runtime._home._content.get_pawn(&"player").max_stamina, base_max + 35, "loaded simulation owns the new definition")
		runner.assert_eq(int(runtime.world_sim.services.definitions.move_minutes_per_cell), base_travel + 1, "loaded services retain the same new definition")
		runner.assert_eq(str(runtime.world_sim.map_data.natural_surface_definitions()[surface_id].label), changed_label, "loaded map keeps the new surface definition")
		runner.assert_true(runtime.world_sim.map_data.natural_affinity(sample_cell, "metal") != base_metal, "loaded map computes the new five-phase affinity")
		runner.assert_eq(observations.size(), 1, "accepted load publishes one content-replaced event")
		if observations.size() == 1:
			_assert_observation(observations[0], second, changed_label, changed_metal, runner, "new version publication")
		runner.assert_true(runtime.world_sim._content == runtime._home._content, "simulation and home reference the same committed content")
		runner.assert_true(main._content == runtime._home._content, "main and simulation reference the same committed content")
		runner.assert_eq(main.player.state.max_stamina(), base_max + 35, "player's visible state immediately uses the saved definition")
		GameClock.advance_msec(5000)
		runner.assert_eq(int(runtime._home.simulation.actors.player.stamina), base_max + 35, "actual recovery observes the new maximum after time advances")
		runner.assert_eq(main.player.state.max_stamina(), base_max + 35, "view continues to use the committed maximum")
	# The original archive keeps version A even after B has been committed.
	runner.assert_eq(SimSaveStore.save_file(path, first), OK, "write original-version session")
	loaded = runtime.load_game(path)
	runner.assert_eq(loaded, OK, "ordinary loader restores the earlier definition for the same ID")
	if loaded == OK:
		runner.assert_eq(runtime._home._content.get_pawn(&"player").max_stamina, base_max, "original session restores its original maximum")
		runner.assert_eq(int(runtime.world_sim.services.definitions.move_minutes_per_cell), base_travel, "original session restores its original service policy")
		runner.assert_eq(str(runtime.world_sim.map_data.natural_surface_definitions()[surface_id].label), base_label, "original session restores its original surface label")
		runner.assert_eq(runtime.world_sim.map_data.natural_affinity(sample_cell, "metal"), base_metal, "original session restores its original five-phase affinity")
		runner.assert_eq(observations.size(), 2, "restoring the first version publishes one more event")
		if observations.size() == 2:
			_assert_observation(observations[1], first, base_label, base_metal, runner, "original version publication")
		runner.assert_eq(main.player.state.max_stamina(), base_max, "visible state returns to the original maximum")
		GameClock.advance_msec(5000)
		runner.assert_eq(int(runtime._home.simulation.actors.player.stamina), base_max, "actual recovery still respects the original maximum")
		var before: Dictionary = WorldSessionSnapshot.capture(runtime)
		var bad: Dictionary = before.duplicate(true)
		bad.erase("content_bundle")
		_reject(runtime, bad, path, runner, "current root without its content bundle")
		bad = before.duplicate(true)
		_set_player_max(bad.content_bundle.documents, base_max + 1)
		_reject(runtime, bad, path, runner, "document changed without its digest")
		bad = before.duplicate(true)
		bad.content_bundle.documents.erase(PAWNS_PATH)
		bad.content_bundle = ReolContentBundle.from_documents(bad.content_bundle.documents)
		_reject(runtime, bad, path, runner, "missing document with a recomputed digest")
		bad = before.duplicate(true)
		bad.content_bundle.documents[_undeclared_path()] = {}
		bad.content_bundle = ReolContentBundle.from_documents(bad.content_bundle.documents)
		_reject(runtime, bad, path, runner, "additional document with a recomputed digest")
		bad = before.duplicate(true)
		_set_player_max(bad.content_bundle.documents, 0)
		bad.content_bundle = ReolContentBundle.from_documents(bad.content_bundle.documents)
		_reject(runtime, bad, path, runner, "invalid definition with a recomputed digest")
		bad = before.duplicate(true)
		var v1_documents: Dictionary = bad.content_bundle.documents.duplicate(true)
		v1_documents.erase(ReolContentDB.ENVIRONMENT_SOURCES_PATH)
		bad.content_bundle = ReolContentBundle.from_documents(v1_documents, ReolContentBundle.LEGACY_VERSION)
		_reject(runtime, bad, path, runner, "current session paired with a v1 bundle lacking field definitions")
		runner.assert_eq(observations.size(), 2, "rejected content candidates publish no replacement event")
	var legacy_text: String = FileAccess.get_file_as_string(V42_PATH)
	var legacy_bytes: PackedByteArray = FileAccess.get_file_as_bytes(V42_PATH)
	var legacy: Dictionary = JSON.parse_string(legacy_text)
	runner.assert_eq(FileAccess.get_sha256(V42_PATH), V42_SHA, "the independently recorded real v42 archive retains its original bytes")
	runner.assert_eq(int(legacy.schema_version), 42, "legacy archive retains its original root version")
	runner.assert_eq(SessionSaveSchema.rejection_reason(legacy.schema_version), SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT, "v42 reports the explicit old-environment rejection")
	var contaminated: Dictionary = legacy.duplicate(true)
	contaminated["content_bundle"] = first.content_bundle.duplicate(true)
	_reject(runtime, contaminated, path, runner, "a legacy root remains unsupported when given a modern content bundle")
	var old_world: RegionalSimulation = runtime.world_sim
	var old_content: ReolContentDB = runtime._home._content
	var old_map: WorldMapData = old_world.map_data
	var old_clock: String = _json(GameClock.to_dict())
	var before_legacy: String = _json(WorldSessionSnapshot.capture(runtime))
	var original_legacy: String = _json(legacy)
	var observation_count: int = observations.size()
	runner.assert_true(SessionSaveSchema.upgrade(legacy).is_empty(), "the v42 field history is not invented by an upgrade")
	runner.assert_true(WorldSessionSnapshot.stage(runtime, legacy).is_empty(), "the actual v42 archive is rejected before publication")
	loaded = runtime.load_game(ProjectSettings.globalize_path(V42_PATH))
	runner.assert_eq(loaded, ERR_INVALID_DATA, "ordinary loader rejects the actual v42 in-flight archive")
	runner.assert_eq(runtime._notice, "旧环境格式不再支持，存档未改；请新开局。", "ordinary loading explains why the old archive cannot be opened")
	runner.assert_true(runtime.world_sim == old_world and runtime._home._content == old_content and runtime.world_sim.map_data == old_map, "rejecting v42 leaves the world, content and map owners untouched")
	runner.assert_eq(_json(GameClock.to_dict()), old_clock, "rejecting v42 leaves the shared clock unchanged")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before_legacy, "rejecting v42 preserves the complete current session")
	runner.assert_eq(_json(legacy), original_legacy, "rejection does not repair or mutate the v42 candidate")
	runner.assert_eq(observations.size(), observation_count, "rejecting v42 publishes no content-replaced signal")
	runner.assert_eq(FileAccess.get_file_as_bytes(V42_PATH), legacy_bytes, "validation and rejection never rewrite the real legacy archive")
	runner.assert_eq(FileAccess.get_sha256(V42_PATH), V42_SHA, "the v42 archive still has its independently recorded digest")
	_remove(path)
	main.free()
	GameClock.restore_state(saved_clock)
	print("SCENARIO content versions: isolated same-ID templates, real load and recovery, atomic malformed-bundle rejection, immutable real v42 rejection")


func _assert_observation(observation: Dictionary, expected: Dictionary, expected_label: String, expected_metal: int, runner: Object, label: String) -> void:
	for key: String in ["context_content", "world_content", "main_content", "home_simulation", "view_map"]:
		runner.assert_true(bool(observation[key]), label + " exposes a fully rebound owner: " + key)
	var captured: Dictionary = observation.captured
	runner.assert_eq(int(observation.clock_ms), int(expected.clock.elapsed_ms), label + " exposes the saved clock rather than the previous clock")
	runner.assert_eq(int(observation.world_ms), int(expected.continuity.world.elapsed_ms), label + " exposes the saved regional time")
	runner.assert_eq(int(captured.clock.elapsed_ms), int(expected.clock.elapsed_ms), label + " can capture a coherent shared clock")
	runner.assert_eq(int(captured.continuity.world.elapsed_ms), int(expected.continuity.world.elapsed_ms), label + " can capture the matching regional time")
	runner.assert_eq(int(captured.simulation.actors.player.stamina), int(expected.simulation.actors.player.stamina), label + " captures the saved body state")
	runner.assert_eq(str(captured.content_bundle.digest), str(expected.content_bundle.digest), label + " can capture the published content version")
	runner.assert_eq(str(observation.label), expected_label, label + " exposes the corresponding map definition")
	runner.assert_eq(int(observation.metal), expected_metal, label + " exposes the corresponding five-phase affinity")


func _reject(runtime: WorldContinuityRuntime, candidate: Dictionary, path: String, runner: Object, label: String) -> void:
	var old_world: RegionalSimulation = runtime.world_sim
	var old_content: ReolContentDB = runtime._home._content
	var old_map: WorldMapData = old_world.map_data
	var old_clock: String = _json(GameClock.to_dict())
	var before: String = _json(WorldSessionSnapshot.capture(runtime))
	var original_input: String = _json(candidate)
	runner.assert_true(WorldSessionSnapshot.stage(runtime, candidate).is_empty(), label + " is rejected during independent staging")
	runner.assert_eq(SimSaveStore.save_file(path, candidate), OK, label + " can be represented as an untrusted save")
	runner.assert_eq(runtime.load_game(path), ERR_INVALID_DATA, label + " is rejected by the ordinary loader")
	runner.assert_true(runtime.world_sim == old_world and runtime._home._content == old_content and runtime.world_sim.map_data == old_map, label + " leaves all live owners in place")
	runner.assert_eq(_json(GameClock.to_dict()), old_clock, label + " leaves the shared clock unchanged")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, label + " leaves all session facts unchanged")
	runner.assert_eq(_json(candidate), original_input, label + " is not repaired or mutated")


func _set_player_max(documents: Dictionary, value: int) -> bool:
	var pawns: Variant = documents.get(PAWNS_PATH)
	if not pawns is Dictionary or not pawns.get("pawns") is Array:
		return false
	for pawn: Variant in pawns.pawns:
		if pawn is Dictionary and pawn.get("id") == "player":
			pawn.max_stamina = value
			return true
	return false


func _player_max(documents: Dictionary) -> int:
	for pawn: Dictionary in documents[PAWNS_PATH].pawns:
		if pawn.get("id") == "player":
			return int(pawn.max_stamina)
	return -1


func _undeclared_path() -> String:
	# This is deliberately unresolvable; construct it so the repository's
	# static resource-reference checker does not interpret it as a required file.
	return "res://" + "data/definitions/not_declared.json"


func _remove(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
