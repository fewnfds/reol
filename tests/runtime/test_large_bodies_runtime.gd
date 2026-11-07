extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")


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
	# Current body movement, food provenance, departure and resume are above.
	LegacyRejection.run(runner, {
		"res://tests/fixtures/session_v23.json": "e5fe71942196c137ac8791cb4968d06d6de31c3449b122b1771b90dff9d002c8",
		"res://tests/fixtures/session_v24.json": "41f974342957ceecff2d9331bd5f9619c61a5b3269d1a44a6b290f2e4e49c6db",
	}, ["large_bodies"])
	print("SCENARIO scale runtime: visible shared requests, body-aware old paths, actual food, away motion and old-archive rejection")


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)
