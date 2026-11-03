extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var domain: SimLargeBodies = runtime.world_sim.large_bodies
	runner.assert_eq(domain.bodies.size(), 1, "normal main adapter assembles an actual large source")
	var id: String = "hill_beast"
	var at: Vector2i = domain.body_cell(id)
	runner.assert_true(not fixture.world.is_walkable(at) and runtime.world_sim.construction.occupied(at), "original human navigation and construction respect the beast footprint")
	var side: Vector2i = at + Vector2i(0, 2)
	fixture.player.spawn_at(side)
	runner.assert_true(runtime.large_body_adapter.select_at(runtime.large_body_adapter.display_point(id)), "pointing at visible beast enters the existing C request panel")
	runner.assert_eq(runtime.interaction_adapter.receiver_choice.get_selected_metadata(), SimLargeBodies.subject_id(id), "click selects actual beast subject")
	runner.assert_eq(runtime.interaction_adapter.verb_choice.get_selected_metadata(), "offer_food", "context uses the shared object/action/medium vocabulary")
	fixture.home.simulation.inventory.containers["actor:player"].meal = 2
	var answer: Dictionary = runtime.interaction_adapter.submit(SimLargeBodies.subject_id(id), "offer_food", {"kind": "provisions", "id": "meal"}, "spoken")
	runner.assert_eq(answer.status, "not_understood", "spoken command does not become universal animal communication")
	answer = runtime.interaction_adapter.submit(SimLargeBodies.subject_id(id), "offer_food", {"kind": "provisions", "id": "meal"}, "gesture")
	runner.assert_true(answer.ok, "shared C request hands actual food across body boundary")
	runner.assert_eq(fixture.home.simulation.inventory.quantity("actor:player", "meal"), 1, "one original bag pays for actual edge feeding")
	GameClock.advance_msec(15400)
	runner.assert_true(not domain.bodies[id].step.is_empty(), "normal clock leaves a genuine step in flight")
	var path: String = "user://tests/large_body_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "joint saver captures the physical mid-step")
	var captured: Dictionary = WorldSessionSnapshot.capture(runtime)
	var bad: Dictionary = captured.duplicate(true)
	bad.continuity.world.large_bodies.bodies[id].position[1] += 6
	runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "joint staging rejects wrong interpolated multi-cell position")
	runner.assert_true(runtime.travel_to("river"), "player may leave the roaming beast behind")
	GameClock.advance_msec(180000)
	var future: String = _canonical(runtime)
	runner.assert_eq(runtime.load_game(path), OK, "ordinary load restores movement and original food provenance")
	runner.assert_true(runtime.travel_to("river"), "same departure remains available after load")
	GameClock.advance_msec(180000)
	runner.assert_eq(_canonical(runtime), future, "same departure and away duration yield identical joint future")
	for suffix: String in ["", ".bak"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	fixtures._dispose(fixture)
	_old_archive(runner)
	_actual_archive(runner)
	print("SCENARIO scale runtime: visible shared requests, body-aware old paths, actual food, away motion and honest legacy migration")


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _old_archive(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var old_path: String = "res://tests/fixtures/session_v23.json"
	var original: String = FileAccess.get_file_as_string(old_path)
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(old_path)), OK, "genuine v23 record handover migrates without manufacturing past beasts")
	runner.assert_true(runtime.world_sim.large_bodies.bodies.is_empty(), "v23 migration explicitly adds an empty scale domain")
	runner.assert_eq(FileAccess.get_file_as_string(old_path), original, "real v23 fixture remains byte-for-byte intact")
	main.free()
	GameClock.restore_state(prior)


func _actual_archive(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var path: String = "res://tests/fixtures/session_v24.json"
	var original: String = FileAccess.get_file_as_string(path)
	var future: String = ""
	for attempt: int in 2:
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var runtime: WorldContinuityRuntime = main._continuity
		runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(path)), OK, "genuine v24 restores actual food provenance and physical large step")
		runner.assert_eq(GameClock.elapsed_ms, 199400, "genuine archive retains its fractional step time")
		runner.assert_eq(runtime.world_sim.large_bodies.bodies.hill_beast.step.started_ms, 199000, "restored movement was already underway before save")
		runner.assert_eq(runtime.world_sim.large_bodies.events.size(), 1, "real UI gift remains one historical operation")
		runner.assert_eq(runtime.player_inventory().quantity("actor:player", "meal"), 0, "actual purchased food is already consumed exactly once")
		runner.assert_true(runtime.travel_to("river"), "genuine player can leave along an actual region route")
		GameClock.advance_msec(180000)
		runner.assert_eq(runtime.current_region, "river", "original human reaches the second settlement")
		runner.assert_true(not runtime.large_body_adapter.is_visible_body("hill_beast"), "far body does not enter the visible receiver list")
		if attempt == 0:
			future = _canonical(runtime)
		else:
			runner.assert_eq(_canonical(runtime), future, "genuine scale archive resumes the same absent world across complete scene replacement")
		main.free()
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "genuine v24 archive is never regenerated by a test")
	GameClock.restore_state(prior)
