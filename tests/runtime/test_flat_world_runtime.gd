extends RefCounted
## Different seeded flat openings and unchanged historical terrain share one
## ordinary load path. Configuring a draft cannot alter a running world.

const LEGACY: String = "res://tests/fixtures/session_v42_exchange.json"
const LEGACY_SHA: String = "e13c2616a25f482db2397b585417d027c2759172393c6929eb98a4713b676ebf"


func run(runner: Object) -> void:
	var previous_clock: Dictionary = GameClock.to_dict()
	_restart_clock()
	var first: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(first)
	if first._continuity == null or first._continuity.world_sim == null:
		runner.assert_true(false, "ordinary flat world opening assembles")
		first.free()
		GameClock.restore_state(previous_clock)
		return
	var default_map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/world_generation.json"))
	var saved_a: Dictionary = WorldSessionSnapshot.capture(first._continuity)
	runner.assert_eq(saved_a.world.generator, "reol_flat_noise", "normal new game uses the explicit flat scenario")
	runner.assert_eq(int(saved_a.world_seed), int(default_map.seed), "new world records its actual scenario seed")
	_assert_flat(runner, first._continuity.world_sim.map_data, "A")
	first.free()
	_restart_clock()
	var second: Node = load("res://scenes/main.tscn").instantiate()
	var draft: Dictionary = WorldMapData.flat_descriptor(int(default_map.seed) + 17)
	var expected_seed: int = int(draft.seed)
	runner.assert_true(second.configure_opening_map(draft), "a pre-tree draft selects a different legitimate map")
	draft.seed += 99
	runner.root.add_child(second)
	var runtime: WorldContinuityRuntime = second._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "different seeded opening assembles real residents, places and wildlife")
		second.free()
		GameClock.restore_state(previous_clock)
		return
	var saved_b: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_eq(int(saved_b.world_seed), expected_seed, "draft mutation after acceptance cannot change the new map")
	runner.assert_true(int(saved_a.world_seed) != int(saved_b.world_seed), "A and B are genuinely different map seeds")
	_assert_flat(runner, runtime.world_sim.map_data, "B")
	var stable_b: String = _json(saved_b)
	runner.assert_true(not second.configure_opening_map(default_map), "creation input cannot replace an active map")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), stable_b, "refused reconfiguration leaves every world fact unchanged")
	var path: String = "user://tests/flat_world_%d.json" % Time.get_ticks_usec()
	if _load(runtime, path, saved_a, runner, "A after B"):
		runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), _json(saved_a), "different map A returns with all of its own facts")
		_assert_flat(runner, runtime.world_sim.map_data, "restored A")
	var legacy_raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LEGACY))
	var legacy_current: Dictionary = SessionSaveSchema.upgrade(legacy_raw)
	if _load(runtime, path, legacy_raw, runner, "genuine old v42 after flat A"):
		runner.assert_eq(runtime.world_sim.map_data.descriptor(), WorldMapData.legacy_descriptor(), "old save restores the exact old generator instead of today's default")
		var old_hills: int = 0
		for cell: Vector2i in [Vector2i(0, 0), Vector2i(128, 128), Vector2i(256, 256), Vector2i(384, 384), Vector2i(511, 511)]:
			old_hills += 1 if runtime.world_sim.map_data.get_elevation(cell) > 0 else 0
		runner.assert_true(old_hills > 0, "historical terrain still has its original height samples")
		runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), _json(legacy_current), "legacy migration changes only the explicit envelopes, not old histories")
	var legacy_content: ReolContentDB = ReolContentDB.legacy_v42()
	var legacy_v47: Dictionary = SessionSaveSchema._upgrade(legacy_raw, legacy_content) if legacy_content != null else {}
	runner.assert_true(not legacy_v47.is_empty(), "the real v1 thermal archive reaches the old v47 envelope")
	if legacy_v47.is_empty():
		_remove(path)
		second.free()
		GameClock.restore_state(previous_clock)
		return
	var v44: Dictionary = legacy_v47.duplicate(true)
	v44.schema_version = 44
	v44.world.erase("terrain_overrides")
	_project_regional_38(v44)
	runner.assert_eq(_json(SessionSaveSchema._upgrade(v44, null)), _json(legacy_v47), "v44 envelope preserves the old recorded map and physical state through v47")
	var upgraded: Dictionary = SessionSaveSchema.upgrade(v44)
	runner.assert_true(not upgraded.is_empty(), "a synthetic v44 envelope with the genuine legacy map explicitly upgrades")
	if not upgraded.is_empty():
		runner.assert_eq(_json(upgraded), _json(legacy_current), "v44 migration preserves its recorded map and all original facts")
	for older: int in [43, 44]:
		var forged: Dictionary = legacy_v47.duplicate(true)
		forged.schema_version = older
		forged.world = saved_a.world.duplicate(true)
		forged.world_seed = saved_a.world_seed
		forged.world.erase("terrain_overrides")
		_project_regional_38(forged)
		if older == 43:
			forged.erase("assembly")
		runner.assert_true(SessionSaveSchema._upgrade(forged, null).is_empty(), "new flat generator cannot masquerade as an older v%d envelope" % older)
	var before: String = _json(WorldSessionSnapshot.capture(runtime))
	var bad: Dictionary = saved_a.duplicate(true)
	bad.world.generator_version = 99
	runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "unknown map code version is rejected")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, "bad map descriptor leaves the current old world untouched")
	if _load(runtime, path, saved_b, runner, "B after historical world"):
		runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), stable_b, "flat B restores its real original world after an old hilly world")
	runner.assert_eq(FileAccess.get_sha256(LEGACY), LEGACY_SHA, "genuine legacy fixture remains byte-identical")
	_remove(path)
	second.free()
	GameClock.restore_state(previous_clock)
	print("SCENARIO flat world: two actual seeded openings, A/B/historical cross-loads, zero new height, preserved old hills, guarded creation input")


func _project_regional_38(snapshot: Dictionary) -> void:
	# Project only an old v47 envelope containing the genuine v1 field.
	var regional: Dictionary = snapshot.continuity.world
	regional.version = 38
	regional.artifacts.version = 6
	for event: Dictionary in regional.artifacts.events:
		if event.get("kind") == "warmed":
			event.erase("heat_amount")


func _assert_flat(runner: Object, terrain: WorldMapData, label: String) -> void:
	var flat: bool = true
	for x: int in range(0, 512, 16):
		for y: int in range(0, 512, 16):
			flat = flat and terrain.get_elevation(Vector2i(x, y)) == 0
	runner.assert_true(flat, label + " has no generated height on 1024 distributed samples")


func _load(runtime: WorldContinuityRuntime, path: String, snapshot: Dictionary, runner: Object, label: String) -> bool:
	runner.assert_eq(SimSaveStore.save_file(path, snapshot), OK, label + " archive writes")
	var result: Error = runtime.load_game(path)
	runner.assert_eq(result, OK, label + " loads through the normal runtime")
	return result == OK


func _restart_clock() -> void:
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})


func _remove(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
