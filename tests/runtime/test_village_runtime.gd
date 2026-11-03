extends RefCounted
## Runtime-adapter checks. Save/load coverage runs after the clock autoload is ready.


class FixtureMap extends WorldMapData:
	var open_cells: Dictionary[Vector2i, bool] = {}


	func terrain_is_walkable(cell: Vector2i) -> bool:
		return open_cells.has(cell)


	func get_elevation(_cell: Vector2i) -> int:
		return 0


	func independent_copy() -> WorldMapData:
		var result := FixtureMap.new()
		result.open_cells = open_cells.duplicate()
		return result


class FixtureWorld extends ReolWorld:
	var open_cells: Dictionary[Vector2i, bool]:
		get:
			return (map_data() as FixtureMap).open_cells


	func _init() -> void:
		bind_map_data(FixtureMap.new())


	func _ready() -> void:
		pass


func run_tests(runner: Object) -> void:
	_test_snapshot_validation(runner)
	_test_world_validation(runner)
	_test_initial_reachability(runner)
	_test_save_load(runner)


func _test_snapshot_validation(runner: Object) -> void:
	var fixture: Dictionary = _make_fixture()
	var runtime: VillageRuntime = fixture.runtime
	var snapshot: Dictionary = _snapshot(runtime)
	runner.call("assert_true", runtime._valid_snapshot(snapshot), "runtime accepts a coherent snapshot")
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(snapshot, "", true, true))
	runner.call("assert_true", runtime._valid_snapshot(decoded), "runtime accepts the JSON numeric round trip")
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid.clock.speed = 3.0
	runner.call("assert_true", not runtime._valid_snapshot(invalid), "runtime rejects unsupported clock speeds")
	invalid = snapshot.duplicate(true)
	invalid.clock.tick_index = 2.5
	runner.call("assert_true", not runtime._valid_snapshot(invalid), "runtime rejects fractional clock ticks")
	invalid = snapshot.duplicate(true)
	invalid.simulation.tick_index = 18
	runner.call("assert_true", not runtime._valid_snapshot(invalid), "runtime rejects different clock and simulation ticks")
	invalid = snapshot.duplicate(true)
	invalid.player.position[0] = NAN
	runner.call("assert_true", not runtime._valid_snapshot(invalid), "runtime rejects nonfinite player positions")
	invalid = snapshot.duplicate(true)
	invalid.player.position[0] += TileGrid.TILE_SIZE
	runner.call("assert_true", not runtime._valid_snapshot(invalid), "runtime rejects positions outside the saved cell")
	invalid = snapshot.duplicate(true)
	invalid.simulation.config.navigation_radius = 25
	runner.call("assert_true", not runtime._valid_snapshot(invalid), "runtime rejects a different simulation configuration")
	invalid = snapshot.duplicate(true)
	invalid.world_seed = -1
	runner.call("assert_true", not runtime._valid_snapshot(invalid), "runtime rejects a different generated world")
	invalid = snapshot.duplicate(true)
	invalid.simulation.actors.player.facing = [1.0, 0.0]
	runner.call("assert_true", not runtime._valid_snapshot(invalid), "runtime rejects two different headings for its one original player body")
	_dispose_fixture(fixture)


func _test_world_validation(runner: Object) -> void:
	var fixture: Dictionary = _make_fixture()
	var runtime: VillageRuntime = fixture.runtime
	var simulation := VillageSimulation.new()
	simulation.actors = {
		"player": {"definition_id": "player", "cell": [10, 10], "active": {}},
		"a_he": {"definition_id": "a_he", "cell": [12, 12], "active": {}},
	}
	simulation.places = {"kitchen": {"label": "灶房", "cell": [13, 12]}}
	runner.call("assert_true", runtime._matches_world(simulation), "runtime accepts actors placed in the saved world")
	simulation.actors.a_he.active = {
		"path": [[12, 13], [13, 13], [13, 12]], "destination": "kitchen", "phase": "travel",
	}
	runner.call("assert_true", runtime._matches_world(simulation), "runtime accepts a legal in-progress route")
	simulation.actors.a_he.active.path = [[12, 13]]
	runner.call("assert_true", not runtime._matches_world(simulation), "runtime rejects a route that ends away from its facility")
	simulation.actors.a_he.active.path = [[15, 15]]
	runner.call("assert_true", not runtime._matches_world(simulation), "runtime rejects routes that jump over cells")
	simulation.actors.a_he.active = {}
	var saved_actor: Dictionary = simulation.actors.a_he
	simulation.actors.erase("a_he")
	runner.call("assert_true", not runtime._matches_world(simulation), "runtime rejects a missing scene actor")
	simulation.actors.a_he = saved_actor
	simulation.places.kitchen.erase("label")
	runner.call("assert_true", not runtime._matches_world(simulation), "runtime rejects incomplete place presentation")
	_dispose_fixture(fixture)


func _test_initial_reachability(runner: Object) -> void:
	var fixture: Dictionary = _make_fixture()
	var runtime: VillageRuntime = fixture.runtime
	var world: FixtureWorld = fixture.world
	var pawn: Pawn = fixture.pawn
	world.open_cells[Vector2i(5, 5)] = true
	pawn.cell = Vector2i(5, 5)
	runner.call("assert_true", runtime._ensure_initial_reachability(), "initial placement can recover an isolated spawn")
	runner.call("assert_true", pawn.cell != Vector2i(5, 5), "initial actor leaves the isolated patch")
	runner.call("assert_true", pawn.cell != runtime._player.cell, "initial correction preserves distinct actor cells")
	var path: Array[Vector2i] = VillageRuntime.find_grid_path(
		world, runtime._player.cell, pawn.cell, 24, 4096
	)
	runner.call("assert_true", not path.is_empty(), "corrected initial actor is reachable")
	_dispose_fixture(fixture)


func _test_save_load(runner: Object) -> void:
	var previous_clock: Dictionary = _clock_state()
	GameClock.restore_state({"tick_index": 37, "total_minutes": 517, "speed": 1.0, "paused": false})
	var content := ReolContentDB.new()
	runner.call("assert_true", content.load_all(), "runtime save fixture loads game definitions")
	var world := FixtureWorld.new()
	for x: int in range(10, 31):
		for y: int in range(10, 31):
			world.open_cells[Vector2i(x, y)] = true
	var player := PlayerCharacter.new()
	player.setup_state(PawnState.create(content.get_pawn(&"player"), content))
	player.spawn_at(Vector2i(20, 20))
	var pawns: Array[Pawn] = []
	var index: int = 0
	for id: StringName in content.pawns:
		if id == &"player":
			continue
		var pawn := Pawn.new()
		pawn.setup(content.get_pawn(id), content, world, Vector2i(21 + index, 20))
		pawns.append(pawn)
		index += 1
	var runtime := VillageRuntime.new()
	var ready: bool = runtime.setup(world, player, pawns, content)
	runner.call("assert_true", ready, "runtime initializes independently of the scene tree")
	if not ready:
		_dispose_live_fixture(runtime, world, player, pawns)
		GameClock.restore_state(previous_clock)
		return
	runner.call("assert_eq", runtime.simulation.tick_index, 37, "runtime aligns a late initialization with the game clock")
	runner.call("assert_true", runtime.simulation.submit_action("player", "deliver_wood"), "player begins a resource-backed journey")
	GameClock.advance_msec(400)
	runtime.simulation.cancel_action("player", "manual_fixture")
	player.motion.relocate(TileGrid.cell_to_world(player.cell) + Vector2(7.25, -6.5))
	player._project_motion()
	player.set_altitude(1)
	var expected_position: Vector2 = player.global_position
	var expected_simulation: Dictionary = runtime.simulation.to_dict()
	var expected_clock: Dictionary = _clock_state()
	var path: String = "user://tests/village_runtime_%d.json" % Time.get_ticks_usec()
	runner.call("assert_eq", runtime.save_game(path), OK, "runtime writes a coherent mid-journey save")
	GameClock.advance_ticks(11)
	player.spawn_at(Vector2i(20, 21))
	player.set_altitude(0)
	runner.call("assert_eq", runtime.load_game(path), OK, "runtime reloads the mid-journey save")
	runner.call("assert_eq", player.global_position, expected_position, "runtime restores the precise player position")
	runner.call("assert_eq", player.altitude, 1, "runtime restores the player height layer")
	runner.call("assert_eq", _json_normalized(runtime.simulation.to_dict()), _json_normalized(expected_simulation), "runtime restores resources, RNG, commitments, and action progress")
	runner.call("assert_eq", _clock_state(), expected_clock, "runtime restores clock state with simulation state")
	var loaded: Dictionary = SimSaveStore.load_file(path)
	if loaded.ok:
		var invalid_snapshot: Dictionary = loaded.data
		invalid_snapshot.clock.speed = 3.0
		runner.call("assert_eq", SimSaveStore.save_file(path, invalid_snapshot), OK, "invalid-clock fixture is valid JSON")
		var before_simulation: VillageSimulation = runtime.simulation
		var before_position: Vector2 = player.global_position
		var before_clock: Dictionary = _clock_state()
		runner.call("assert_true", runtime.load_game(path) != OK, "runtime refuses a malformed clock snapshot")
		runner.call("assert_true", runtime.simulation == before_simulation, "failed load leaves the live simulation intact")
		runner.call("assert_eq", player.global_position, before_position, "failed load leaves the current player position intact")
		runner.call("assert_eq", _clock_state(), before_clock, "failed load leaves the current clock intact")
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		var test_file: String = ProjectSettings.globalize_path(path + suffix)
		if FileAccess.file_exists(test_file):
			DirAccess.remove_absolute(test_file)
	_dispose_live_fixture(runtime, world, player, pawns)
	GameClock.restore_state(previous_clock)


func _clock_state() -> Dictionary:
	return {
		"tick_index": GameClock.tick_index, "total_minutes": GameClock.total_minutes,
		"speed": GameClock.speed, "paused": GameClock.paused,
	}


func _json_normalized(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true, true))


func _dispose_live_fixture(
	runtime: VillageRuntime, world: FixtureWorld, player: PlayerCharacter, pawns: Array[Pawn]
) -> void:
	runtime.free()
	for pawn: Pawn in pawns:
		pawn.free()
	player.free()
	world.free()


func _make_fixture() -> Dictionary:
	var world := FixtureWorld.new()
	for x: int in range(10, 21):
		for y: int in range(10, 21):
			world.open_cells[Vector2i(x, y)] = true
	var player := PlayerCharacter.new()
	player.spawn_at(Vector2i(10, 10))
	var pawn := Pawn.new()
	pawn.pawn_id = &"a_he"
	pawn.cell = Vector2i(12, 12)
	var runtime := VillageRuntime.new()
	runtime._world = world
	runtime._player = player
	runtime._pawns["a_he"] = pawn
	runtime._config = {"navigation_radius": 24, "navigation_budget": 4096}
	runtime._places = {"kitchen": {"label": "灶房", "cell": [13, 12]}}
	return {"world": world, "player": player, "pawn": pawn, "runtime": runtime}


func _snapshot(runtime: VillageRuntime) -> Dictionary:
	var exact_position: Vector2 = TileGrid.cell_to_world(Vector2i(10, 10)) + Vector2(7.25, -6.5)
	return {
		"schema_version": VillageRuntime.SAVE_VERSION,
		"avatar_subject": "subject:player",
		"world_seed": ReolWorld.WORLD_SEED,
		"world": SessionSaveSchema.capture_world(null, Vector2i(10, 10)),
		"simulation": {
			"config": runtime._config.duplicate(true), "controlled_actor": "player", "tick_index": 17,
			"actors": {"player": {"facing": [0.0, 1.0]}},
		},
		"clock": {"tick_index": 17, "total_minutes": 497, "speed": 2.0, "paused": false,
			"elapsed_ms": 1020000, "frame_debt_ms": 0.0, "wait_target_ms": 0},
		"player": {
			"cell": [10, 10], "position": [exact_position.x, exact_position.y], "altitude": 1,
			"motion": SimLocalMotion.legacy_state(),
		},
	}


func _dispose_fixture(fixture: Dictionary) -> void:
	(fixture.runtime as VillageRuntime).free()
	(fixture.pawn as Pawn).free()
	(fixture.player as PlayerCharacter).free()
	(fixture.world as FixtureWorld).free()
