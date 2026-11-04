extends RefCounted
## Real session and standalone loads retain sparse terrain without changing
## bodies, ledgers or the common clock. The v45 example is a format-boundary
## construction, not a claim about an independently recorded old save.

const LEGACY: String = "res://tests/fixtures/session_v42_exchange.json"
const LEGACY_SHA: String = "e13c2616a25f482db2397b585417d027c2759172393c6929eb98a4713b676ebf"
const EDIT_CELL: Vector2i = Vector2i(50, 50)


func run(runner: Object) -> void:
	var previous_clock: Dictionary = GameClock.to_dict()
	var stem: String = "user://tests/terrain_snapshot_%d" % Time.get_ticks_usec()
	_test_joint_session(runner, stem + ".json", stem + ".bad.json")
	_test_standalone(runner, stem + ".single.json", stem + ".single.bad.json")
	for path: String in [stem + ".json", stem + ".bad.json", stem + ".single.json", stem + ".single.bad.json"]:
		_remove(path)
	GameClock.restore_state(previous_clock)
	print("SCENARIO terrain snapshot: draft and live edits, independent candidate, joint and standalone restart, format boundary and atomic invalid-load rejection")


func _test_joint_session(runner: Object, path: String, bad_path: String) -> void:
	_restart_clock()
	var descriptor: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/world_generation.json"))
	var base_map: WorldMapData = WorldMapData.from_descriptor(descriptor)
	if base_map == null or str(descriptor.get("generator", "")) != WorldMapData.FLAT_GENERATOR_ID:
		runner.assert_true(false, "terrain save test has a valid flat opening descriptor")
		return
	var base: int = base_map.get_terrain(EDIT_CELL)
	var changed: int = (base + 1) % 3
	var rows: Array = [[EDIT_CELL.x, EDIT_CELL.y, changed]]
	var first: Node = load("res://scenes/main.tscn").instantiate()
	if not first.configure_opening_map(descriptor, rows):
		runner.assert_true(false, "real main scene accepts an independent pre-tree terrain draft")
		first.free()
		return
	# Mutating the caller's draft after acceptance must not mutate the map.
	rows[0][2] = base
	rows.clear()
	runner.root.add_child(first)
	var runtime: WorldContinuityRuntime = first._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "edited flat draft assembles the real joint world")
		first.free()
		return
	var original_map: WorldMapData = runtime.world_sim.map_data
	var expected_rows: Array = [[EDIT_CELL.x, EDIT_CELL.y, changed]]
	runner.assert_true(first.world.map_data() == original_map, "game view borrows the joint world's one actual terrain")
	runner.assert_eq(original_map.get_terrain(EDIT_CELL), changed, "opening uses the accepted edit rather than the caller's later mutation")
	runner.assert_eq(original_map.terrain_overrides(), expected_rows, "the real opening owns the requested sparse delta")
	GameClock.advance_msec(1517)
	var write: Error = runtime.save_game(path)
	runner.assert_eq(write, OK, "ordinary joint saver writes the edited terrain and running world")
	if write != OK:
		first.free()
		return
	var read: Dictionary = SimSaveStore.load_file(path)
	if not bool(read.get("ok", false)) or not read.get("data") is Dictionary:
		runner.assert_true(false, "edited joint save can be read through the real store")
		first.free()
		return
	var saved: Dictionary = read.data
	var expected: String = _json(saved)
	var expected_nature: String = _json(original_map.natural_cell(EDIT_CELL))
	runner.assert_eq(int(saved.schema_version), SessionSaveSchema.VERSION, "current terrain archive uses the explicit current envelope")
	runner.assert_eq(_json(saved.world.terrain_overrides), _json(expected_rows), "joint archive contains the actual edited cell")
	runner.assert_eq(int(saved.clock.elapsed_ms), 1517, "terrain save carries the actual fractional shared time")
	runner.assert_true(_json(WorldSessionSnapshot.capture(runtime)) == expected, "disk save matches the entire live session at the commit boundary")
	var staged: Dictionary = WorldSessionSnapshot.stage(runtime, saved)
	runner.assert_true(not staged.is_empty(), "edited session stages on an independent candidate map")
	if not staged.is_empty():
		runner.assert_true(staged.map != original_map and staged.world.map_data == staged.map, "candidate map and regional owner are independent of the live map")
		runner.assert_eq(staged.map.terrain_overrides(), expected_rows, "candidate restores the real sparse delta before spatial validation")
		runner.assert_eq(staged.map.get_terrain(EDIT_CELL), changed, "candidate samples the saved edited terrain")
	# Reset the edited cell only after saving. Loading must replace this different
	# live map and clock with the independently validated saved values.
	var reset: Dictionary = original_map.apply_terrain_patch([[EDIT_CELL.x, EDIT_CELL.y, base]])
	runner.assert_true(bool(reset.ok) and reset.changed_cells.has(EDIT_CELL), "a later real terrain edit changes the current map after saving")
	runner.assert_true(original_map.terrain_overrides().is_empty(), "restoring the generated cell removes the live override")
	GameClock.advance_msec(307)
	var loaded: Error = runtime.load_game(path)
	runner.assert_eq(loaded, OK, "ordinary joint loader restores the saved edited map")
	if loaded == OK:
		_assert_joint_state(runner, first, saved, expected, expected_rows, expected_nature, "same-scene load")
		runner.assert_true(runtime.world_sim.map_data != original_map, "accepted load publishes a separate terrain authority")
	first.free()

	# Destroy the entire first scene and initialize a new one before loading.
	# This checks a fresh-scene restart; it is not an OS-process restart test.
	_restart_clock()
	var fresh: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(fresh)
	runtime = fresh._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "fresh normal scene initializes before restoring terrain")
		fresh.free()
		return
	var blank: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_true(blank.world.terrain_overrides.is_empty(), "fresh unedited opening starts with no sparse terrain")
	_assert_v45_boundary(runner, runtime, blank, bad_path)
	loaded = runtime.load_game(path)
	runner.assert_eq(loaded, OK, "fresh scene loads the edited session through the normal loader")
	if loaded == OK:
		_assert_joint_state(runner, fresh, saved, expected, expected_rows, expected_nature, "fresh-scene load")
		_assert_rejections(runner, runtime, saved, bad_path, expected_rows)
	fresh.free()


func _assert_joint_state(runner: Object, main: Node, saved: Dictionary, expected: String, expected_rows: Array, expected_nature: String, label: String) -> void:
	var runtime: WorldContinuityRuntime = main._continuity
	var map: WorldMapData = runtime.world_sim.map_data
	runner.assert_true(main.world.map_data() == map, label + " reconnects the view to the accepted terrain authority")
	runner.assert_eq(map.terrain_overrides(), expected_rows, label + " restores the actual terrain delta")
	runner.assert_eq(map.get_terrain(EDIT_CELL), int(expected_rows[0][2]), label + " exposes the changed terrain to world queries")
	runner.assert_true(_json(map.natural_cell(EDIT_CELL)) == expected_nature, label + " derives the same natural cell from the saved terrain")
	runner.assert_true(_json(runtime.world_sim.regions.home.inventory.to_dict()) == _json(saved.simulation.inventory), label + " keeps the original inventory and ledger")
	runner.assert_true(_json(GameClock.to_dict()) == _json(saved.clock), label + " restores the exact shared clock")
	runner.assert_true(_json(WorldSessionSnapshot.capture(runtime)) == expected, label + " preserves the complete saved bodies, activity, ownership and world")


func _assert_v45_boundary(runner: Object, runtime: WorldContinuityRuntime, blank: Dictionary, bad_path: String) -> void:
	# Synthetic conversion retains the v45 -> v46 terrain boundary before the
	# later artifact-version migration; it is not a genuine historical archive.
	var source: Dictionary = blank.duplicate(true)
	source.schema_version = 45
	source.world.erase("terrain_overrides")
	_project_regional_38(source)
	var before: String = _json(source)
	var upgraded: Dictionary = SessionSaveSchema.upgrade(source)
	runner.assert_true(not upgraded.is_empty(), "synthetic v45 format without terrain delta upgrades")
	if not upgraded.is_empty():
		runner.assert_true(_json(upgraded) == _json(blank), "v45 upgrade restores the current terrain and artifact envelopes without changing saved facts")
		var write: Error = SimSaveStore.save_file(bad_path, source)
		runner.assert_eq(write, OK, "synthetic v45 envelope is written through the ordinary store")
		if write == OK:
			var loaded: Error = runtime.load_game(bad_path)
			runner.assert_eq(loaded, OK, "ordinary loader accepts the v45 empty-terrain format")
			if loaded == OK:
				runner.assert_true(_json(WorldSessionSnapshot.capture(runtime)) == _json(blank), "ordinary v45 load preserves the complete unchanged session")
	runner.assert_true(_json(source) == before, "format migration does not mutate its input")
	var v46: Dictionary = source.duplicate(true)
	v46.schema_version = 46
	v46.world["terrain_overrides"] = []
	var v46_upgraded: Dictionary = SessionSaveSchema.upgrade(v46)
	runner.assert_true(not v46_upgraded.is_empty() and _json(v46_upgraded) == _json(blank), "the explicit v46 terrain envelope also advances to the current session")
	var missing_v46_terrain: Dictionary = v46.duplicate(true)
	missing_v46_terrain.world.erase("terrain_overrides")
	runner.assert_true(SessionSaveSchema.upgrade(missing_v46_terrain).is_empty(), "v46 still requires its terrain field before later migrations")
	var forged: Dictionary = source.duplicate(true)
	forged.world["terrain_overrides"] = []
	_reject(runner, runtime, forged, bad_path, "v45 claiming even an empty future terrain field")


func _project_regional_38(snapshot: Dictionary) -> void:
	# Only a temporary current snapshot is projected; genuine archives are read-only.
	var regional: Dictionary = snapshot.continuity.world
	regional.version = 38
	regional.artifacts.version = 6
	for event: Dictionary in regional.artifacts.events:
		if event.get("kind") == "warmed":
			event.erase("heat_amount")


func _assert_rejections(runner: Object, runtime: WorldContinuityRuntime, saved: Dictionary, path: String, rows: Array) -> void:
	var bad: Dictionary = saved.duplicate(true)
	bad.world.erase("terrain_overrides")
	_reject(runner, runtime, bad, path, "current root without its mandatory terrain field")
	bad = saved.duplicate(true)
	bad.world.terrain_overrides = [rows[0].duplicate(), rows[0].duplicate()]
	_reject(runner, runtime, bad, path, "duplicate terrain coordinates")
	bad = saved.duplicate(true)
	bad.world.terrain_overrides = [rows[0].duplicate(), [WorldMapData.WORLD_SIZE, 50, WorldMapData.TERRAIN_WATER]]
	_reject(runner, runtime, bad, path, "an out-of-bounds row after a valid row")
	bad = saved.duplicate(true)
	bad.world.terrain_overrides = [[50.5, 50, WorldMapData.TERRAIN_WATER]]
	_reject(runner, runtime, bad, path, "a fractional terrain coordinate")
	bad = saved.duplicate(true)
	bad.world.terrain_overrides = [[50, 50, 1.5]]
	_reject(runner, runtime, bad, path, "a fractional terrain type")
	bad = saved.duplicate(true)
	bad.world.terrain_overrides = [[50, 50, 99]]
	_reject(runner, runtime, bad, path, "an unknown terrain type")
	var player: Array = saved.player.cell
	bad = saved.duplicate(true)
	bad.world.terrain_overrides.append([int(player[0]), int(player[1]), WorldMapData.TERRAIN_WATER])
	runner.assert_true(SessionSaveSchema.is_valid_world(bad), "player-on-water case has a valid terrain envelope before spatial checks")
	_reject(runner, runtime, bad, path, "a valid delta that places the original player in water")
	var original: String = FileAccess.get_file_as_string(LEGACY)
	var raw: Variant = JSON.parse_string(original)
	if not raw is Dictionary:
		runner.assert_true(false, "genuine historical terrain fixture is readable")
		return
	var legacy: Dictionary = SessionSaveSchema.upgrade(raw)
	if legacy.is_empty():
		runner.assert_true(false, "genuine historical terrain fixture upgrades before corruption")
		return
	legacy.world.terrain_overrides = [[EDIT_CELL.x, EDIT_CELL.y, WorldMapData.TERRAIN_WATER]]
	_reject(runner, runtime, legacy, path, "a nonempty delta on the immutable legacy generator")
	runner.assert_eq(FileAccess.get_sha256(LEGACY), LEGACY_SHA, "historical source archive is never rewritten")
	runner.assert_true(FileAccess.get_file_as_string(LEGACY) == original, "all malformed candidates leave historical source bytes unchanged")


func _reject(runner: Object, runtime: WorldContinuityRuntime, bad: Dictionary, path: String, label: String) -> void:
	var world: RegionalSimulation = runtime.world_sim
	var map: WorldMapData = world.map_data
	var view: ReolWorld = runtime.home_runtime()._world
	var terrain: Array = map.terrain_overrides()
	var clock: String = _json(GameClock.to_dict())
	var before: String = _json(WorldSessionSnapshot.capture(runtime))
	runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), label + " fails independent candidate validation")
	var write: Error = SimSaveStore.save_file(path, bad)
	runner.assert_eq(write, OK, label + " is a readable, ordinary save file")
	if write != OK:
		return
	runner.assert_eq(runtime.load_game(path), ERR_INVALID_DATA, label + " is rejected by the real loader")
	runner.assert_true(runtime.world_sim == world and runtime.world_sim.map_data == map and view.map_data() == map, label + " does not replace the live world, terrain owner or view binding")
	runner.assert_eq(map.terrain_overrides(), terrain, label + " cannot partially alter live terrain")
	runner.assert_true(_json(GameClock.to_dict()) == clock, label + " leaves the common clock intact")
	runner.assert_true(_json(WorldSessionSnapshot.capture(runtime)) == before, label + " leaves all live bodies, inventory and state unchanged")


func _test_standalone(runner: Object, path: String, bad_path: String) -> void:
	_restart_clock()
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "standalone terrain fixture loads actual content")
		return
	var descriptor: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/world_generation.json"))
	var map: WorldMapData = WorldMapData.from_descriptor(descriptor)
	if map == null:
		runner.assert_true(false, "standalone terrain fixture has a valid flat map")
		return
	var base: int = map.get_terrain(EDIT_CELL)
	var changed: int = (base + 1) % 3
	if not bool(map.apply_terrain_patch([[EDIT_CELL.x, EDIT_CELL.y, changed]]).ok):
		runner.assert_true(false, "standalone map accepts its far terrain edit")
		return
	var world := ReolWorld.new()
	world.bind_map_data(map)
	var player := PlayerCharacter.new()
	player.setup_state(PawnState.create(content.get_pawn(&"player"), content))
	var spawn: Vector2i = world.find_spawn_cell()
	player.spawn_at(spawn)
	var pawns: Array[Pawn] = []
	var index: int = 0
	for id: StringName in content.pawns:
		if id == &"player":
			continue
		var pawn := Pawn.new()
		pawn.setup(content.get_pawn(id), content, world, spawn + Vector2i(index + 1, 0))
		pawns.append(pawn)
		index += 1
	var home := VillageRuntime.new()
	if not home.setup(world, player, pawns, content):
		runner.assert_true(false, "standalone village initializes on the edited real flat map")
		_dispose_standalone(home, world, player, pawns)
		return
	GameClock.advance_msec(1207)
	var write: Error = home.save_game(path)
	runner.assert_eq(write, OK, "standalone saver writes its own edited terrain")
	if write != OK:
		_dispose_standalone(home, world, player, pawns)
		return
	var stored: Dictionary = SimSaveStore.load_file(path)
	if not bool(stored.get("ok", false)) or not stored.get("data") is Dictionary:
		runner.assert_true(false, "standalone terrain archive is readable")
		_dispose_standalone(home, world, player, pawns)
		return
	var saved: Dictionary = stored.data
	runner.assert_true(not saved.has("continuity"), "standalone save is not a copied joint session")
	runner.assert_eq(_json(saved.world.terrain_overrides), _json([[EDIT_CELL.x, EDIT_CELL.y, changed]]), "standalone archive owns its edited terrain")
	var reset: Dictionary = map.apply_terrain_patch([[EDIT_CELL.x, EDIT_CELL.y, base]])
	runner.assert_true(bool(reset.ok) and reset.changed_cells.has(EDIT_CELL), "standalone live map changes after save")
	GameClock.advance_msec(251)
	var loaded: Error = home.load_game(path)
	runner.assert_eq(loaded, OK, "standalone loader reconstructs the edited map")
	if loaded == OK:
		runner.assert_true(world.map_data() != map, "standalone accepted load publishes an independent map")
		runner.assert_eq(world.map_data().terrain_overrides(), [[EDIT_CELL.x, EDIT_CELL.y, changed]], "standalone load restores the real delta")
		runner.assert_true(_json(home.simulation.to_dict()) == _json(saved.simulation), "standalone load preserves the complete original bodies, inventory and commitments")
		runner.assert_true(_json(GameClock.to_dict()) == _json(saved.clock), "standalone load preserves the original fractional clock")
		var stable_map: WorldMapData = world.map_data()
		var stable_sim: VillageSimulation = home.simulation
		var stable_clock: String = _json(GameClock.to_dict())
		var bad: Dictionary = saved.duplicate(true)
		bad.world.terrain_overrides.append([EDIT_CELL.x, EDIT_CELL.y, changed])
		runner.assert_eq(SimSaveStore.save_file(bad_path, bad), OK, "invalid standalone delta is written as ordinary JSON")
		runner.assert_eq(home.load_game(bad_path), ERR_INVALID_DATA, "standalone loader rejects duplicate terrain coordinates")
		runner.assert_true(world.map_data() == stable_map and home.simulation == stable_sim, "failed standalone load preserves both active owners")
		runner.assert_true(_json(home.simulation.to_dict()) == _json(saved.simulation) and _json(GameClock.to_dict()) == stable_clock, "failed standalone load changes no original simulation or time")
	_dispose_standalone(home, world, player, pawns)


func _dispose_standalone(home: VillageRuntime, world: ReolWorld, player: PlayerCharacter, pawns: Array[Pawn]) -> void:
	home.free()
	for pawn: Pawn in pawns:
		pawn.free()
	player.free()
	world.free()


func _restart_clock() -> void:
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _remove(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		var target: String = ProjectSettings.globalize_path(path + suffix)
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)
