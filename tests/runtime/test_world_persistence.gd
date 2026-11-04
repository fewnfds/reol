extends RefCounted
## Exploration is saved memory; visibility is a projection of the restored body.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const LEGACY_PATH: String = "res://tests/fixtures/session_v1.json"
const V2_PATH: String = "res://tests/fixtures/session_v2.json"
const V3_PATH: String = "res://tests/fixtures/session_v3.json"
const V4_PATH: String = "res://tests/fixtures/session_v4.json"
const V5_PATH: String = "res://tests/fixtures/session_v5.json"
const V6_PATH: String = "res://tests/fixtures/session_v6.json"
const V7_PATH: String = "res://tests/fixtures/session_v7.json"
const V8_PATH: String = "res://tests/fixtures/session_v8.json"
const V9_PATH: String = "res://tests/fixtures/session_v9.json"
const V10_PATH: String = "res://tests/fixtures/session_v10.json"
const OVERLOAD_PATH: String = "res://tests/fixtures/overload_v10.json"


func run(runner: Object) -> void:
	_test_exploration_boundaries(runner)
	_test_joint_exploration_and_atomic_rejection(runner)
	_test_real_legacy_migration_and_fresh_scene(runner)
	_test_real_v2_identity_migration(runner)
	_test_real_v3_artifact_migration(runner)
	_test_real_completed_artifact_save(runner)
	_test_real_short_action_save(runner)
	_test_real_continuous_life_save(runner)
	_test_real_practice_save(runner)
	_test_real_avian_save(runner)
	_test_real_player_life_save(runner)
	_test_real_material_advice(runner)
	_test_real_overload(runner)


func _test_real_overload(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var original: String = FileAccess.get_file_as_string(OVERLOAD_PATH)
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(OVERLOAD_PATH)), OK, "actual strong-infusion fixture validates as an ongoing world action")
	runner.assert_eq(GameClock.elapsed_ms, 1567600, "actual overload retains its fractional start phase")
	runner.assert_eq(runtime.world_sim.artifacts.active.player.verb, "force", "actual saved intent is overload rather than ordinary recharge")
	runner.assert_eq(runtime._home.simulation.actors.player.qi, 11, "actual archive already contains its one infusion payment")
	GameClock.advance_msec(120000)
	runner.assert_eq(runtime.world_sim.artifacts.objects.hearth_stone.damage, 4, "actual weak seam fractures under the resumed action")
	runner.assert_eq(runtime.world_sim.artifacts.objects.hearth_stone.charge, 0, "actual fracture loses the same stored heat")
	runner.assert_eq(runtime._home.simulation.actors.player.qi, 11, "resume never charges the infusion again")
	runner.assert_eq(runtime._home.simulation.actors.player.stamina, 90, "actual aftermath retains backlash and the following half-second recovery")
	var expected: String = JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)
	main.free()
	main = packed.instantiate()
	runner.root.add_child(main)
	runtime = main._continuity
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(OVERLOAD_PATH)), OK, "fresh scene restores the same real overload fixture")
	GameClock.advance_msec(120000)
	runner.assert_true(JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true) == expected, "actual material failure and the rest of the world have the same fresh-scene future")
	runner.assert_eq(FileAccess.get_file_as_string(OVERLOAD_PATH), original, "actual overload source remains immutable")
	main.free()
	GameClock.restore_state(clock)


func _test_real_material_advice(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var original: String = FileAccess.get_file_as_string(V10_PATH)
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(V10_PATH)), OK, "actual v10 pending artisan check validates in generated terrain")
	runner.assert_eq(GameClock.elapsed_ms, 1027100, "actual check retains its fractional shared minute")
	runner.assert_eq(runtime.world_sim.artifacts.active.su_zhi.recipient, "player", "pending check retains the intended physical listener")
	runner.assert_true(not runtime.world_sim.artifacts.describe("player", "hearth_stone").method, "actual customer has not learned how to use the stone")
	GameClock.advance_msec(120000)
	var view: Dictionary = runtime.world_sim.artifacts.describe("player", "hearth_stone")
	runner.assert_true(str(view.line).contains("苏芷曾告诉你") and str(view.line).contains("细裂") and not view.method, "real completed check supplies material advice without free mastery")
	var expected: String = JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)
	main.free()
	main = packed.instantiate()
	runner.root.add_child(main)
	runtime = main._continuity
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(V10_PATH)), OK, "fresh scene restores the same actual artisan check")
	GameClock.advance_msec(120000)
	runner.assert_true(JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true) == expected, "actual NPC explanation, experiences and objects continue identically in a fresh scene")
	runner.assert_eq(FileAccess.get_file_as_string(V10_PATH), original, "actual v10 source remains unchanged")
	main.free()
	GameClock.restore_state(clock)


func _test_real_player_life_save(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	runner.root.add_child(main)
	var source: String = FileAccess.get_file_as_string(V9_PATH)
	var runtime: WorldContinuityRuntime = main._continuity
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(V9_PATH)), OK, "real v9 bird-player flight restores against generated terrain")
	runner.assert_eq(GameClock.elapsed_ms, 20600, "real selected-life fixture retains fractional time")
	runner.assert_eq(runtime.avatar_subject, "subject:avian:moss_sparrow", "real selected-life fixture retains its actual subject")
	runner.assert_true(not main._avatar.opening.visible and not main.player.avatar_active, "load locks the opening and keeps the original human autonomous")
	runner.assert_eq(runtime.world_sim.avian_life.birds.moss_sparrow.active.purpose, "pickup", "real player-selected herb flight resumes in progress")
	GameClock.advance_msec(40000)
	runner.assert_eq(runtime.world_sim.avian_life.inventory.quantity("bird:moss_sparrow", "herb"), 1, "real flight leaves exactly one picked sprig in the selected beak")
	var expected: String = JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)
	main.free()
	main = packed.instantiate()
	runner.root.add_child(main)
	runtime = main._continuity
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(V9_PATH)), OK, "fresh scene also restores the real selected-life fixture")
	GameClock.advance_msec(40000)
	runner.assert_true(JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true) == expected, "real bird-player, old human and remote futures agree in a fresh scene")
	runner.assert_eq(FileAccess.get_file_as_string(V9_PATH), source, "real selected-life source remains immutable")
	main.free()
	GameClock.restore_state(clock)


func _test_exploration_boundaries(runner: Object) -> void:
	var world := Fixtures.FlatWorld.new()
	var fog := FogOfWar.new()
	fog.setup(world, Vector2i(10, 10))
	var before: Dictionary = fog.exploration_to_dict()
	runner.assert_true(FogOfWar.is_valid_exploration(before), "actual visible cells serialize as valid exploration")
	fog.set_focus(Vector2i(70, 70))
	fog.update_now()
	runner.assert_true(fog.is_explored(Vector2i(70, 70)), "a later visit creates real exploration")
	runner.assert_true(fog.restore_exploration(before, Vector2i(10, 10)), "saved exploration restores")
	runner.assert_true(not fog.is_explored(Vector2i(70, 70)), "later footprints are absent from an earlier save")
	runner.assert_true(fog.is_cell_visible(Vector2i(10, 10)), "current visibility is recomputed at restored focus")
	runner.assert_eq(fog.exploration_to_dict(), before, "repeated visibility updates do not expand saved memory")
	var size: int = ReolWorld.WORLD_SIZE * ReolWorld.WORLD_SIZE
	var boundary: Dictionary = {"encoding": FogOfWar.EXPLORATION_ENCODING, "runs": [[0, 1], [size - 1, 1]]}
	runner.assert_true(fog.restore_exploration(boundary, Vector2i(10, 10)), "first and last world cells are valid memories")
	runner.assert_true(fog.is_explored(Vector2i.ZERO) and fog.is_explored(Vector2i(511, 511)), "world boundary memory is retained")
	for runs: Variant in [
		[[0, 0]], [[-1, 2]], [[size, 1]], [[size - 1, 2]], [[1.5, 2]],
		[[0, 2], [1, 2]], [[0, 2], [2, 2]], [[4, 1], [0, 1]], [[0, 1, 2]], [[true, 1]], [[0, INF]], "bad",
	]:
		var invalid: Dictionary = {"encoding": FogOfWar.EXPLORATION_ENCODING, "runs": runs}
		var unchanged: Dictionary = fog.exploration_to_dict()
		runner.assert_true(not fog.restore_exploration(invalid, Vector2i(10, 10)), "malformed or noncanonical exploration is rejected: %s" % str(runs))
		runner.assert_eq(fog.exploration_to_dict(), unchanged, "failed exploration restore cannot clear live memory")
	fog.free()
	world.free()


func _test_joint_exploration_and_atomic_rejection(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var fog := FogOfWar.new()
	fog.setup(fixture.world, fixture.player.cell)
	fixture.home._fog = fog
	GameClock.advance_ticks(27)
	runtime.travel_to("river")
	GameClock.advance_msec(100)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var path: String = "user://tests/exploration_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(SimSaveStore.save_file(path, snapshot), OK, "joint snapshot with exploration writes through existing atomic store")
	fog.set_focus(Vector2i(85, 85))
	fog.update_now()
	GameClock.advance_ticks(20)
	runner.assert_eq(runtime.load_game(path), OK, "joint world and exploration load together")
	runner.assert_true(not fog.is_explored(Vector2i(85, 85)), "successful joint load removes future exploration")
	runner.assert_eq(fog.exploration_to_dict(), snapshot.world.exploration, "saved exploration is restored exactly")
	var invalids: Array[Dictionary] = []
	var bad: Dictionary = snapshot.duplicate(true)
	bad.world.generator_version = 99
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.world.seed += 1
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.world.exploration.runs = [[262143, 2]]
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.erase("world")
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.schema_version = 99
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.schema_version = 1
	bad.erase("content_bundle")
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.world.exploration = FogOfWar.empty_exploration()
	bad.clock.tick_index = -1
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.continuity.world.erase("embodiment")
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.continuity.world.embodiment.controls["body:player"].erase("motion")
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.schema_version = 2
	bad.erase("content_bundle")
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.continuity.world.erase("artifacts")
	invalids.append(bad)
	bad = snapshot.duplicate(true)
	bad.schema_version = 3
	bad.erase("content_bundle")
	invalids.append(bad)
	for invalid: Dictionary in invalids:
		var before: String = JSON.stringify(WorldSessionSnapshot.capture(runtime), "", true, true)
		runner.assert_eq(SimSaveStore.save_file(path, invalid), OK, "negative fixture remains structurally valid JSON")
		runner.assert_true(runtime.load_game(path) != OK, "incompatible or corrupt world/session data is rejected")
		runner.assert_eq(JSON.stringify(WorldSessionSnapshot.capture(runtime), "", true, true), before, "failed joint load preserves clock, actors, cargo and fog")
	_remove_test_save(path)
	fixture.home._fog = null
	fog.free()
	fixtures._dispose(fixture)


func _test_real_legacy_migration_and_fresh_scene(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var source_text: String = FileAccess.get_file_as_string(LEGACY_PATH)
	var legacy: Dictionary = JSON.parse_string(source_text)
	runner.assert_eq(legacy.schema_version, 1.0, "regression fixture is a genuine previous session format")
	var staged: Dictionary = WorldSessionSnapshot.stage(runtime, legacy)
	runner.assert_true(not staged.is_empty(), "real legacy main-scene snapshot migrates against actual generated terrain")
	if not staged.is_empty():
		runner.assert_eq(staged.snapshot.schema_version, SessionSaveSchema.VERSION, "explicit migration reaches the current schema")
		runner.assert_eq(staged.snapshot.world.exploration, FogOfWar.empty_exploration(), "legacy migration invents no historic footprints")
		runner.assert_eq(legacy.schema_version, 1.0, "migration does not modify the source object")
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(LEGACY_PATH)), OK, "normal read path accepts real old save without overwriting it")
	runner.assert_eq(GameClock.tick_index, 27, "old save resumes its committed minute")
	runner.assert_true(not runtime.player_journey.is_empty() and not runtime.world_sim.shipments.is_empty(), "old save retains both player journey and real cargo")
	runner.assert_true(not main.fog.is_explored(runtime.centers.home - Vector2i(8, 0)), "old format does not infer earlier footprints outside restored vision")
	var path: String = "user://tests/migrated_world_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "migrated world saves normally in current format")
	var expected_fog: Dictionary = main.fog.exploration_to_dict()
	GameClock.advance_ticks(100)
	var expected: String = _world_state(runtime)
	main.free()
	# A new scene reconstructs everything from definitions; no old fog/actor refs.
	main = packed.instantiate()
	runner.root.add_child(main)
	runtime = main._continuity
	runner.assert_eq(runtime.load_game(path), OK, "fresh scene restores migrated save")
	runner.assert_eq(main.fog.exploration_to_dict(), expected_fog, "fresh scene retains saved memory, not its own initial spawn vision")
	GameClock.advance_ticks(100)
	runner.assert_true(_world_state(runtime) == expected, "migrated save has identical continuation across a fresh scene")
	runner.assert_eq(FileAccess.get_file_as_string(LEGACY_PATH), source_text, "legacy source file is unchanged")
	print("SCENARIO world persistence: real v1→v2→v3→current, fresh-scene exploration and cargo continue identically")
	main.free()
	_remove_test_save(path)
	GameClock.restore_state(saved_clock)


func _test_real_v2_identity_migration(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var source_text: String = FileAccess.get_file_as_string(V2_PATH)
	var legacy: Dictionary = JSON.parse_string(source_text)
	runner.assert_eq(legacy.schema_version, 2.0, "second real fixture predates subject/carrier serialization")
	runner.assert_true(not legacy.continuity.world.has("embodiment"), "genuine old regional output had no identity registry")
	var staged: Dictionary = WorldSessionSnapshot.stage(runtime, legacy)
	runner.assert_true(not staged.is_empty(), "real v2 scene migrates against actual terrain, actions and knowledge")
	if not staged.is_empty():
		runner.assert_eq(staged.snapshot.world, legacy.world, "identity migration does not alter exploration or generator memory")
		for domain: String in ["social", "inventory", "institutions"]:
			var migrated_domain: Dictionary = staged.snapshot.simulation[domain].duplicate(true)
			if domain == "inventory":
				runner.assert_true(migrated_domain.custody.is_empty(), "genuine v2 has no unfinished public custody to invent")
				migrated_domain.erase("custody")
			runner.assert_eq(migrated_domain, legacy.simulation[domain], "migration retains actual personal memories/materials/institution: " + domain)
		var registry: SimEmbodiment = staged.world.embodiment
		runner.assert_eq(registry.residence_of(registry.subject_for_actor("player")), registry.carrier_for_source("village_actor", "player"), "old player is bound to its one original body")
		runner.assert_eq(registry.to_dict().subjects.size(), 12, "migration creates one subject per real existing resident")
		runner.assert_true(staged.world.actor_controls("player", "action"), "old player's existing actions remain authorized")
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(V2_PATH)), OK, "normal load path upgrades immutable v2 fixture")
	runner.assert_eq(GameClock.tick_index, 238, "knowledge playthrough resumes its actual minute")
	var belief: Dictionary = runtime._home.simulation.stock_understanding("player", "kitchen", "wood")
	runner.assert_true(bool(belief.known) and belief.basis == "said" and belief.source == "chen_shouzhuo", "old save keeps named stock testimony instead of regenerating knowledge")
	var path: String = "user://tests/identity_migration_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "migrated identity saves in current format")
	GameClock.advance_ticks(60)
	var expected: String = _world_state(runtime)
	main.free()
	main = packed.instantiate()
	runner.root.add_child(main)
	runtime = main._continuity
	runner.assert_eq(runtime.load_game(path), OK, "new scene restores migrated subject/body references")
	GameClock.advance_ticks(60)
	runner.assert_eq(_world_state(runtime), expected, "v2 migration has identical future after a full scene replacement")
	runner.assert_eq(FileAccess.get_file_as_string(V2_PATH), source_text, "real v2 fixture remains immutable")
	var bad: Dictionary = legacy.duplicate(true)
	bad.continuity.world["embodiment"] = {}
	runner.assert_true(SessionSaveSchema.upgrade(bad).is_empty(), "old format with a contradictory modern field is rejected")
	bad = legacy.duplicate(true)
	bad.continuity.world.version = 2
	runner.assert_true(SessionSaveSchema.upgrade(bad).is_empty(), "modern regional corruption is not silently treated as legacy")
	main.free()
	_remove_test_save(path)
	GameClock.restore_state(saved_clock)
	print("SCENARIO identity migration: real v2→current preserves named knowledge, exploration, one body/bag and identical continuation")


func _world_state(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(runtime.world_sim.to_dict(), "", true, true)), "", true, true)


func _test_real_v3_artifact_migration(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var source_text: String = FileAccess.get_file_as_string(V3_PATH)
	var source: Dictionary = JSON.parse_string(source_text)
	runner.assert_eq(source.schema_version, 3.0, "third fixture was actually saved before the artifact domain existed")
	runner.assert_true(not source.continuity.world.has("artifacts"), "real previous output has no invented object history")
	var staged: Dictionary = WorldSessionSnapshot.stage(runtime, source)
	runner.assert_true(not staged.is_empty(), "real subject/control snapshot migrates into current session")
	if not staged.is_empty():
		runner.assert_true(staged.world.artifacts.objects.is_empty() and staged.world.artifacts.events.is_empty(), "migration preserves old world history rather than spawning retroactive objects/knowledge")
		runner.assert_eq(staged.snapshot.continuity.world.embodiment, source.continuity.world.embodiment, "artifact migration preserves exact old control state")
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(V3_PATH)), OK, "normal v3 loading succeeds")
	runner.assert_true(runtime.world_sim.artifacts.objects.is_empty(), "loading replaces temporary scene opening objects with saved history")
	runner.assert_eq(FileAccess.get_file_as_string(V3_PATH), source_text, "real v3 fixture remains unchanged")
	main.free()
	GameClock.restore_state(clock)


func _test_real_avian_save(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var source: String = FileAccess.get_file_as_string(V8_PATH)
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(V8_PATH)), OK, "actual v8 nonhuman cargo save restores through the full terrain validator")
	runner.assert_eq(GameClock.elapsed_ms, 2576650, "real bird archive retains the exact return flight moment")
	runner.assert_eq(runtime.world_sim.avian_life.inventory.quantity("bird:moss_sparrow", "herb"), 1, "actual bird retains the one held sprig")
	runner.assert_eq(runtime._home.simulation.inventory.quantity("garden", "herb"), 12, "carried herb has not already reached the garden")
	GameClock.advance_msec(10000)
	runner.assert_eq(runtime._home.simulation.inventory.quantity("garden", "herb"), 13, "real restored bird commits one material delivery")
	var expected: String = JSON.stringify(WorldSessionSnapshot.capture(runtime), "", true, true)
	main.free()
	main = packed.instantiate()
	runner.root.add_child(main)
	runtime = main._continuity
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(V8_PATH)), OK, "fresh scene restores the same real bird without reseeding its habitat")
	GameClock.advance_msec(10000)
	runner.assert_eq(JSON.stringify(WorldSessionSnapshot.capture(runtime), "", true, true), expected, "nonhuman cargo, personal memories and all other domains have the same fresh-scene future")
	runner.assert_eq(FileAccess.get_file_as_string(V8_PATH), source, "actual avian fixture remains immutable")
	main.free()
	GameClock.restore_state(clock)


func _remove_test_save(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _test_real_completed_artifact_save(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var source_text: String = FileAccess.get_file_as_string(V4_PATH)
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(V4_PATH)), OK, "actual completed/registered artifact playthrough restores through all validators")
	runner.assert_eq(GameClock.tick_index, 88, "actual artifact fixture resumes its committed minute")
	runner.assert_eq(runtime.world_sim.artifacts.objects.hearth_stone.charge, 4, "stored heat remains consumed after successful load")
	runner.assert_true(bool(runtime.world_sim.artifacts.describe("player", "hearth_stone").method), "personal investigation remains learned")
	runner.assert_eq(runtime._home.simulation.institutions.balance(str(runtime._home.simulation.config.institution.id), "player"), 2, "institution remembers registered alternative cooking evidence")
	runner.assert_eq(runtime._home.simulation.actors.player.receipts.size(), 0, "registered receipt is not recreated as unpaid")
	GameClock.advance_ticks(30)
	var expected: String = _world_state(runtime)
	main.free()
	main = packed.instantiate()
	runner.root.add_child(main)
	runtime = main._continuity
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(V4_PATH)), OK, "fresh scene loads completed artifact, materials and institution together")
	GameClock.advance_ticks(30)
	runner.assert_true(_world_state(runtime) == expected, "completed real artifact save continues identically across a fresh scene")
	runner.assert_eq(FileAccess.get_file_as_string(V4_PATH), source_text, "actual completed fixture is never rewritten by the reader")
	main.free()
	GameClock.restore_state(clock)


func _test_real_short_action_save(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var source: String = FileAccess.get_file_as_string(V5_PATH)
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(V5_PATH)), OK, "actual Shift input fixture restores an in-flight short action")
	runner.assert_eq(GameClock.elapsed_ms, 2800, "real archive restores fractional world minute")
	runner.assert_eq(main.player.global_position, Vector2(16416, 16446), "real archive restores partially travelled body")
	runner.assert_eq(runtime._home.simulation.actors.player.stamina, 92, "real archive retains one exertion cost")
	runner.assert_true(main.hud._pawn_resources.text.contains("92/100"), "restored body resources refresh the visible HUD before another minute")
	GameClock.advance_msec(400)
	# Deterministic 1ms travel accumulates under 0.1px of float32 quantization
	# at this world coordinate. Original time, source position and cost stay exact.
	runner.assert_true(main.player.global_position.distance_to(Vector2(16416, 16536)) < 0.1, "real pending action completes only its remaining ninety pixels within subpixel precision")
	runner.assert_true(main.player.motion.action.is_empty(), "real action clears after recovery")
	runner.assert_eq(runtime._home.simulation.actors.player.stamina, 92, "real restored action does not repay or spend again")
	var expected: String = JSON.stringify(WorldSessionSnapshot.capture(runtime), "", true, true)
	main.free()
	main = packed.instantiate()
	runner.root.add_child(main)
	runtime = main._continuity
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(V5_PATH)), OK, "fresh process-style scene restores the same fine-time save")
	GameClock.advance_msec(400)
	runner.assert_eq(JSON.stringify(WorldSessionSnapshot.capture(runtime), "", true, true), expected, "fresh scene has identical body/time/world after short action")
	runner.assert_eq(FileAccess.get_file_as_string(V5_PATH), source, "actual in-flight source fixture is immutable")
	main.free()
	GameClock.restore_state(clock)


func _test_real_continuous_life_save(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var source: String = FileAccess.get_file_as_string(V6_PATH)
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(V6_PATH)), OK, "actual shared-time native/visitor archive validates in the real terrain")
	runner.assert_eq(GameClock.elapsed_ms, 15100, "real shared-life archive retains its fractional minute")
	runner.assert_eq(main.player.motion.position, Vector2(16439.970703125, 16416), "real shared-life route restores between cell centers")
	runner.assert_true(not runtime.player_journey.is_empty(), "real journey remains in progress after loading")
	GameClock.advance_msec(1000)
	var expected: String = JSON.stringify(WorldSessionSnapshot.capture(runtime), "", true, true)
	main.free()
	main = packed.instantiate()
	runner.root.add_child(main)
	runtime = main._continuity
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(V6_PATH)), OK, "fresh scene restores the real millisecond NPC and automatic route archive")
	GameClock.advance_msec(1000)
	runner.assert_eq(JSON.stringify(WorldSessionSnapshot.capture(runtime), "", true, true), expected, "actual continuous life and route have identical fresh-scene continuation")
	runner.assert_eq(FileAccess.get_file_as_string(V6_PATH), source, "shared-life source remains immutable")
	main.free()
	GameClock.restore_state(clock)


func _test_real_practice_save(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var source: String = FileAccess.get_file_as_string(V7_PATH)
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(V7_PATH)), OK, "actual practice save restores through the real terrain and full joint validator")
	runner.assert_true(runtime.world_sim.avian_life.birds.is_empty() and runtime.world_sim.avian_life.sites.is_empty(), "true v7 history gains no invented birds or plants during migration")
	runner.assert_eq(GameClock.elapsed_ms, 9100, "actual practice archive retains the precise preparation time")
	runner.assert_eq(runtime._home.simulation.actors.player.stamina, 76, "archive retains earlier strain and one accepted palm cost")
	runner.assert_eq(runtime.world_sim.sparring.phase("player", GameClock.elapsed_ms), "prepare", "archive restores a palm still preparing")
	GameClock.advance_msec(150)
	runner.assert_eq(runtime._home.simulation.actors.shi_tou.stamina, 121, "real saved palm contacts the nearby NPC exactly once")
	GameClock.advance_msec(750)
	var expected: String = JSON.stringify(WorldSessionSnapshot.capture(runtime), "", true, true)
	main.free()
	main = packed.instantiate()
	runner.root.add_child(main)
	runtime = main._continuity
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(V7_PATH)), OK, "fresh scene restores the same real practice without reseeding life")
	GameClock.advance_msec(900)
	runner.assert_eq(JSON.stringify(WorldSessionSnapshot.capture(runtime), "", true, true), expected, "actual practice world/positions/resources have identical fresh-scene continuation")
	runner.assert_eq(FileAccess.get_file_as_string(V7_PATH), source, "actual practice archive remains immutable")
	main.free()
	GameClock.restore_state(clock)
