extends RefCounted
## The first real main-scene observation must already respect opening walls.


func run(runner: Object) -> void:
	var previous_clock: Dictionary = GameClock.to_dict()
	for subject: String in ["subject:player", "subject:avian:moss_sparrow", "subject:soul:yan_heng"]:
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var runtime: WorldContinuityRuntime = main._continuity
		if runtime == null or runtime.world_sim == null or main._avatar == null:
			runner.assert_true(false, "ordinary main scene assembles for " + subject)
			main.free()
			continue
		runner.assert_true(main._avatar.opening.visible and GameClock.paused, "opening waits for a life selection: " + subject)
		runner.assert_true(main._village._fog == main.fog and main.fog._active, "village uses the initialized scene fog: " + subject)
		runner.assert_true(main.fog.is_cell_visible(main.player.cell), "actual opening observer sees its own cell: " + subject)
		if subject == "subject:player":
			_assert_initial_office_sight(main, runner)
			_assert_initial_pawn_views(main, runner)
		runner.assert_true(main._avatar.choose(subject), "opening selects the original life: " + subject)
		runner.assert_eq(runtime.avatar_subject, subject, "selected life is bound to the world: " + subject)
		runner.assert_true(not main._avatar.opening.visible and main.fog.is_cell_visible(runtime.controlled_cell()), "selected life has an initialized local view: " + subject)
		main._process(0.0)
		if subject == "subject:player":
			_assert_saved_exploration(main, runner)
		main.free()
	GameClock.restore_state(previous_clock)
	print("SCENARIO opening structure visibility: actual first observation, existing exploration and all three starting lives")


func _assert_initial_office_sight(main: Node, runner: Object) -> void:
	var home: VillageSimulation = main._continuity.world_sim.regions.home
	var office: Dictionary = home.places.records.workspace
	var eye: Vector2i = main.player.cell
	var archive: Vector2i = SimRouteTravel.cell(office.fixtures.archive.cell)
	var wall: Vector2i = eye + Vector2i(1, -1)
	# The standard seed supplies this short diagonal ray: the archive is two
	# steps away and the intervening cell belongs to the original office wall.
	runner.assert_eq(archive, eye + Vector2i(1, -2), "standard opening puts the archive behind the near office wall")
	runner.assert_true(SimWorkplaces.wall_at(home.places, wall), "the intervening cell is a real fixed office wall")
	runner.assert_true(main.world.is_sight_blocked(wall), "the assembled regional sight provider sees that wall")
	runner.assert_true(main.fog.is_cell_visible(wall), "the observer sees the near surface of the wall")
	# This independent view uses the same map, without a sight-obstacle provider.
	# It proves terrain alone would have exposed the archive in the old order.
	var terrain_view := ReolWorld.new()
	terrain_view.bind_map_data(main.world.map_data())
	var terrain_fog := FogOfWar.new()
	terrain_fog.setup(terrain_view, eye)
	runner.assert_true(terrain_fog.is_cell_visible(archive), "terrain alone permits the original opening ray to the archive")
	terrain_fog.free()
	terrain_view.free()
	runner.assert_eq(main.fog.get_state(archive), FogOfWar.STATE_HIDDEN, "unseen archive is not explored during initial scene assembly")
	main.fog.update_now()
	runner.assert_eq(main.fog.get_state(archive), FogOfWar.STATE_HIDDEN, "recomputing stationary sight does not leave false exploration")


func _assert_initial_pawn_views(main: Node, runner: Object) -> void:
	runner.assert_true(not main._pawns.is_empty(), "ordinary opening has its original named residents")
	for pawn: Pawn in main._pawns:
		var actor: Dictionary = main._village.simulation.actors[String(pawn.pawn_id)]
		var expected: bool = bool(actor.alive) and main.fog.is_cell_visible(pawn.cell)
		runner.assert_eq(pawn.visible, expected, "resident view is synchronized after the first observation: " + String(pawn.pawn_id))


func _assert_saved_exploration(main: Node, runner: Object) -> void:
	var runtime: WorldContinuityRuntime = main._continuity
	var archive: Vector2i = SimRouteTravel.cell(runtime.world_sim.regions.home.places.records.workspace.fixtures.archive.cell)
	var eye: Vector2i = main.player.cell
	var index: int = archive.y * ReolWorld.WORLD_SIZE + archive.x
	var remembered: Dictionary = {"encoding": FogOfWar.EXPLORATION_ENCODING, "runs": [[index, 1]]}
	runner.assert_true(main.fog.restore_exploration(remembered, eye), "existing exploration can include the now-occluded archive")
	runner.assert_eq(main.fog.get_state(archive), FogOfWar.STATE_EXPLORED, "genuine prior memory remains explored behind the wall")
	var path: String = "user://tests/opening_structure_visibility_%d.json" % Time.get_ticks_usec()
	var saved: Error = runtime.save_game(path)
	runner.assert_eq(saved, OK, "session saves prior exploration")
	if saved == OK:
		runner.assert_true(main.fog.restore_exploration(FogOfWar.empty_exploration(), eye), "test clears the live view before ordinary loading")
		runner.assert_eq(main.fog.get_state(archive), FogOfWar.STATE_HIDDEN, "control view is unexplored before loading")
		var loaded: Error = runtime.load_game(path)
		runner.assert_eq(loaded, OK, "ordinary loader accepts the session with prior exploration")
		if loaded == OK:
			runner.assert_eq(main.fog.get_state(archive), FogOfWar.STATE_EXPLORED, "loading preserves prior explored memory behind the wall")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
