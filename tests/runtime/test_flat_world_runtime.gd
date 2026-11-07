extends RefCounted
## Different seeded flat openings share one ordinary load path. Retired old
## archives are rejected without replacing the current world or their bytes.

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
	_assert_retired_archive(runner, runtime)
	var before: String = _json(WorldSessionSnapshot.capture(runtime))
	var bad: Dictionary = saved_a.duplicate(true)
	bad.world.generator_version = 99
	runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "unknown map code version is rejected")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, "bad map descriptor leaves the current world untouched")
	if _load(runtime, path, saved_b, runner, "B after rejected historical archive"):
		runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), stable_b, "flat B restores its real original world after a rejected old archive")
	runner.assert_eq(FileAccess.get_sha256(LEGACY), LEGACY_SHA, "genuine legacy fixture remains byte-identical")
	_remove(path)
	second.free()
	GameClock.restore_state(previous_clock)
	print("SCENARIO flat world: two actual seeded openings, A/B cross-loads, old archive rejection, zero new height and guarded creation input")


func _assert_retired_archive(runner: Object, runtime: WorldContinuityRuntime) -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(LEGACY)
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	runner.assert_eq(FileAccess.get_sha256(LEGACY), LEGACY_SHA, "genuine legacy fixture retains its recorded hash")
	if bytes.is_empty() or not parsed is Dictionary:
		runner.assert_true(false, "genuine legacy archive is readable")
		return
	var source: Dictionary = parsed
	var source_before: String = _json(source)
	var world: RegionalSimulation = runtime.world_sim
	var map: WorldMapData = world.map_data
	var before: String = _json(WorldSessionSnapshot.capture(runtime))
	runner.assert_eq(SessionSaveSchema.rejection_reason(source.get("schema_version")), SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT, "the genuine old archive reports its retired environment")
	runner.assert_true(SessionSaveSchema.upgrade(source).is_empty(), "genuine old archive does not enter the current schema")
	runner.assert_true(WorldSessionSnapshot.stage(runtime, source).is_empty(), "genuine old archive cannot stage a current world")
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(LEGACY)), ERR_INVALID_DATA, "ordinary loading refuses the genuine old archive")
	runner.assert_true(runtime.world_sim == world and world.map_data == map, "old archive rejection retains the current world and map")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, "old archive rejection preserves the complete live session")
	runner.assert_eq(_json(source), source_before, "old archive rejection leaves its input unchanged")
	runner.assert_eq(FileAccess.get_file_as_bytes(LEGACY), bytes, "old archive rejection preserves the actual fixture bytes")
	runner.assert_eq(FileAccess.get_sha256(LEGACY), LEGACY_SHA, "old archive retains its original hash after rejection")


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
