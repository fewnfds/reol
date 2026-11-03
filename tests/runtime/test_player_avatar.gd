extends RefCounted
## One selected life, shared physical rules and an atomic continued perspective.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	_test_manual_life(runner)
	_test_opening_and_persistence(runner)
	print("SCENARIO player life: one opening body, manual flight/food/cargo, autonomous former human and persisted finite perspective")


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _test_manual_life(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	var runtime: WorldContinuityRuntime = fixture.continuity
	var domain: SimAvianLife = runtime.world_sim.avian_life
	runner.assert_true(not runtime.select_starting_avatar("subject:avian:moss_sparrow"), "no opening adapter means no free runtime body switch")
	runtime._opening_selection_available = true
	runner.assert_true(not runtime.select_starting_avatar("subject:missing"), "invalid opening identity leaves selection available")
	runner.assert_true(runtime.select_starting_avatar("subject:avian:moss_sparrow"), "opening selects an existing physical sparrow")
	runner.assert_true(not runtime.select_starting_avatar("subject:player"), "opening identity can be chosen only once")
	runner.assert_true(fixture.home.simulation.actors.player.autonomous and not domain.birds.moss_sparrow.autonomous, "former human becomes autonomous while the one original bird is manual")
	runner.assert_true(not runtime.travel_to("river") and not runtime.start_home_work("deliver_wood").ok, "bird cannot order the former human's route or work")
	runner.assert_true(not runtime.service_adapter.submit("eat").ok and not runtime.object_adapter.submit("look").ok, "bird cannot consume human services or use the former human's artifact knowledge")
	fixture.home.simulation.actors.player.energy = 25.0
	var start: Vector2 = SimAvianLife.point(domain.birds.moss_sparrow)
	runner.assert_true(domain.command_flight("moss_sparrow", Vector2.RIGHT), "bird's own controller starts bounded flight")
	var action_id: String = domain.birds.moss_sparrow.active.id
	GameClock.advance_msec(100)
	runner.assert_true(SimAvianLife.point(domain.birds.moss_sparrow).x > start.x, "flight advances on the same millisecond clock")
	runner.assert_true(domain.command_flight("moss_sparrow", Vector2.RIGHT), "holding a direction preserves its segment")
	runner.assert_eq(domain.birds.moss_sparrow.active.id, action_id, "sampling a held direction does not restart progress")
	runner.assert_true(domain.command_flight("moss_sparrow", Vector2.DOWN), "changed intent turns from current physical position")
	GameClock.advance_msec(100)
	domain.command_flight("moss_sparrow", Vector2.ZERO)
	var stopped: Array = domain.birds.moss_sparrow.position.duplicate()
	GameClock.advance_msec(1000)
	runner.assert_eq(domain.birds.moss_sparrow.position, stopped, "releasing manual movement stops its remaining segment")
	runner.assert_true(not fixture.home.simulation.actors.player.active.is_empty(), "former player now makes autonomous life decisions")
	domain.set_landing_check(func(_cell: Vector2i) -> bool: return false)
	runner.assert_true(not domain.command_land("moss_sparrow").ok, "flight does not make blocked ground a valid landing")
	domain.set_landing_check(fixture.world.is_walkable)
	domain.birds.moss_sparrow.energy = SimAvianLife.SCALE
	runner.assert_true(not domain.command_flight("moss_sparrow", Vector2.UP), "exhausted wings cannot begin another flight")
	runner.assert_true(not domain.command_activity("moss_sparrow", "forage").ok, "a remembered food route cannot bypass exhausted wings")
	runner.assert_true(domain.command_activity("moss_sparrow", "rest").ok, "low-energy bird has a legal ground recovery option away from its nest")
	GameClock.advance_msec(60000)
	runner.assert_true(int(domain.birds.moss_sparrow.energy) > SimAvianLife.SCALE, "ground recovery restores this body rather than a copied resource")
	domain.cancel("moss_sparrow")
	var seeds: int = domain.inventory.quantity("home:seeds", "seed")
	runner.assert_true(domain.command_activity("moss_sparrow", "forage").ok, "manual bird chooses a personally known source of food")
	GameClock.advance_msec(20000)
	runner.assert_eq(domain.inventory.quantity("home:seeds", "seed"), seeds - 1, "eating consumes an actual finite seed")
	var herbs: int = fixture.home.simulation.inventory.quantity("garden", "herb")
	runner.assert_true(domain.command_activity("moss_sparrow", "pickup").ok, "manual bird enters the same real crevice as the autonomous birds")
	GameClock.advance_msec(20000)
	runner.assert_eq(domain.inventory.quantity("bird:moss_sparrow", "herb"), 1, "picked sprig remains in its one beak")
	runner.assert_true(domain.birds.moss_sparrow.active.is_empty(), "manual pickup does not automatically make the player's next choice")
	runner.assert_true(not domain.command_activity("moss_sparrow", "pickup").ok, "beak capacity prevents another sprig")
	runner.assert_true(domain.command_activity("moss_sparrow", "drop").ok, "real carried sprig can be given to the original village garden")
	GameClock.advance_msec(20000)
	runner.assert_eq(fixture.home.simulation.inventory.quantity("garden", "herb"), herbs + 1, "manual delivery changes shared human stock")
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, JSON.parse_string(_canonical(runtime))).is_empty(), "manual actions and transfer provenance validate across JSON")
	runner.assert_true(domain.command_activity("moss_sparrow", "pickup").ok, "a second independent trip takes another real sprig")
	GameClock.advance_msec(20000)
	var far: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(domain.sites["river:garden"].cell))
	for _step: int in 100:
		if SimAvianLife.point(domain.birds.moss_sparrow).distance_to(far) < 40.0:
			break
		domain.command_flight("moss_sparrow", far - SimAvianLife.point(domain.birds.moss_sparrow))
		GameClock.advance_msec(100)
	domain.command_flight("moss_sparrow", Vector2.ZERO)
	var far_stock: int = runtime.world_sim.regions.river.inventory.quantity("garden", "herb")
	runner.assert_true(domain.birds.moss_sparrow.known_sites.has("river:garden"), "flying to a different habitat produces personal observations there")
	runner.assert_true(domain.command_activity("moss_sparrow", "drop").ok, "carried home sprig can be put into the nearest personally known far garden")
	GameClock.advance_msec(10000)
	runner.assert_eq(runtime.world_sim.regions.river.inventory.quantity("garden", "herb"), far_stock + 1, "delivery follows actual target region rather than birthplace")
	runner.assert_eq(domain.birds.moss_sparrow.region, "home", "visiting another habitat does not replace the bird's origin identity")
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, JSON.parse_string(_canonical(runtime))).is_empty(), "cross-habitat physical provenance and identity are saveable together")
	domain.command_flight("moss_sparrow", Vector2.RIGHT)
	GameClock.advance_msec(50)
	stopped = domain.birds.moss_sparrow.position.duplicate()
	runtime.world_sim.embodiment.release_control(SimAvianLife.subject_id("moss_sparrow"), SimAvianLife.carrier_id("moss_sparrow"), "motion")
	GameClock.advance_msec(100)
	runner.assert_eq(domain.birds.moss_sparrow.position, stopped, "control loss prevents displacement at the following interval")
	runner.assert_true(domain.birds.moss_sparrow.active.is_empty(), "control loss settles the manual action")
	fixtures._dispose(fixture)


func _test_opening_and_persistence(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	runner.assert_true(main._avatar.opening.visible and GameClock.paused, "new game offers its opening before time starts")
	runner.assert_true(main._avatar.choose("subject:avian:moss_sparrow"), "opening UI binds the real sparrow life")
	runner.assert_true(not main.player.avatar_active and not main._avatar.opening.visible, "former human no longer samples player intent")
	runner.assert_true(not main.hud._pawn_panel.visible and not runtime._panel.visible, "bird view has no hidden human identity or resources panel")
	runner.assert_eq(main.fog._observer_radius, int(runtime.world_sim.avian_life.rules().observation_cells), "bird perspective derives its own observation radius")
	var unknown: Vector2i = runtime.controlled_cell() + Vector2i(8, 0)
	runner.assert_true(not main.fog.is_explored(unknown), "opening clears initial human-sized explored vision")
	Input.action_press("move_right")
	GameClock.advance_msec(100)
	runner.assert_eq(runtime.world_sim.avian_life.birds.moss_sparrow.active.purpose, "explore", "actual input adapter submits bird flight")
	main.hud.refresh_body()
	runner.assert_true(not main.hud._pawn_panel.visible, "human body refresh cannot reopen its panel over the bird view")
	Input.action_release("move_right")
	GameClock.advance_msec(50)
	runner.assert_true(runtime.world_sim.avian_life.birds.moss_sparrow.active.is_empty(), "input release stops exploration without cancelling other activities")
	runner.assert_true(main._avatar.submit("pickup").ok, "real perspective submits a physical pickup journey")
	GameClock.advance_msec(100)
	var path: String = "user://tests/player_avatar_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "selected life and unfinished action enter the existing session save")
	var snapshot: Dictionary = SimSaveStore.load_file(path).data
	runner.assert_eq(snapshot.avatar_subject, SimAvianLife.subject_id("moss_sparrow"), "session records identity separately from body state")
	GameClock.advance_msec(30000)
	var expected: String = _canonical(runtime)
	runner.assert_eq(runtime.load_game(path), OK, "ordinary load restores bird perspective and unfinished action")
	runner.assert_true(not runtime._opening_selection_available and not main._avatar.choose("subject:player"), "loading cannot reopen a free body choice")
	runner.assert_true(not main.fog.is_explored(unknown), "load does not temporarily reveal human-sized vision")
	GameClock.advance_msec(30000)
	runner.assert_true(_canonical(runtime) == expected, "joint bird, former-human and remote futures match after a normal JSON load")
	var bad: Dictionary = snapshot.duplicate(true)
	bad.avatar_subject = "subject:missing"
	var before: String = _canonical(runtime)
	runner.assert_eq(SimSaveStore.save_file(path, bad), OK, "bad identity fixture remains valid JSON")
	runner.assert_true(runtime.load_game(path) != OK, "unresolvable player identity is rejected")
	runner.assert_eq(_canonical(runtime), before, "bad identity cannot partly replace body, world or perspective")
	bad = snapshot.duplicate(true)
	bad.avatar_subject = "subject:player"
	runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "changing only the player subject cannot hide a second manual body")
	bad = snapshot.duplicate(true)
	bad.erase("avatar_subject")
	runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "modern save missing identity is not silently migrated")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	main.free()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	runner.root.add_child(main)
	runner.assert_true(main._avatar.choose("subject:player"), "human opening remains selectable in a fresh world")
	runner.assert_true(main.player.avatar_active and main.hud._pawn_panel.visible and not main._avatar._bird_status.visible, "human choice retains its original presentation and input binding")
	runner.assert_true(not WorldSessionSnapshot.stage(main._continuity, WorldSessionSnapshot.capture(main._continuity)).is_empty(), "human opening still saves as one manual life")
	main.free()
	GameClock.restore_state(saved_clock)
