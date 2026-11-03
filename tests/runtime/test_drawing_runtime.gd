extends RefCounted
## Product route from a genuine older save; no invented body or resources.


func run(runner: Object) -> void:
	var previous_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var helper: RefCounted = load("res://tests/runtime/helpers/drawing_replay.gd").new()
	_check_research_preserves_position(runner, runtime, helper)
	var research: Dictionary = helper.prepare_research(runtime)
	runner.assert_true(bool(research.get("ok", false)), "ordinary old take -> actual outer study -> paid research in progress: " + str(research))
	if bool(research.get("ok", false)):
		var world: RegionalSimulation = runtime.world_sim
		runner.assert_true(not world.artifacts.learned_use("player", helper.RING), "original incomplete paid research cannot grant use early")
		_check_stationary_candidate(runner, runtime, "use_research")
		var due: int = int(world.artifacts.active.player.due_ms)
		runner.assert_true(helper._advance(runtime, due - GameClock.elapsed_ms), "legal stopped research reaches its original deadline")
		runner.assert_true(world.artifacts.learned_use("player", helper.RING), "product research completion has genuine personal mastery")
		var research_future: String = _json(WorldSessionSnapshot.capture(runtime))
		runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(helper.RESEARCH_ARCHIVE)), OK, "original loader restores the legal stopped research")
		runner.assert_true(helper._advance(runtime, due - GameClock.elapsed_ms), "restored research reaches the same original deadline")
		runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), research_future, "legal stopped research resumes to the same full future")
		world = runtime.world_sim
		var projected: Dictionary = SimCapabilityQueries.project(world, "player")
		for node: Dictionary in projected.nodes:
			if node.id == "drawing_ring":
				runner.assert_true(node.state == "learned" and not node.sources.is_empty(), "eighth personal category cites original completed research")
		var drawing: Dictionary = helper.prepare_draw(runtime)
		runner.assert_true(bool(drawing.get("ok", false)), "ordinary original return, short walk and selected target reach real draw middle: " + str(drawing))
		if bool(drawing.get("ok", false)):
			world = runtime.world_sim
			var ring: String = helper.RING
			runner.assert_true(world.artifacts.objects.training_sword.container == "dorm", "short draw starts with original target still in its genuine slot")
			runtime.service_adapter.refresh()
			var shared_activity: String = runtime.service_adapter.panel._phase.text
			runner.assert_true(shared_activity.contains("1 秒") and not shared_activity.contains("0 分钟"), "the actual mid-draw shared activity shows one second, not zero minutes")
			runner.assert_true(not runtime.travel_to("river"), "ongoing original draw prevents simultaneous original-body journey")
			_check_stationary_candidate(runner, runtime, "draw")
			var before: String = _json(WorldSessionSnapshot.capture(runtime))
			var airborne: Dictionary = WorldSessionSnapshot.capture(runtime)
			airborne.player.altitude = 1
			runner.assert_true(WorldSessionSnapshot.stage(runtime, airborne).is_empty(), "candidate refuses unsupported airborne casting instead of assuming same height")
			runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, "bad-height candidate preserves the entire live process")
			var choices: Array[Dictionary] = runtime.object_adapter.draw_targets()
			runtime.object_adapter.refresh()
			runtime.capability_adapter.show_panel()
			runtime.capability_adapter.refresh()
			runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, "view rebuild and target choices do not generate knowledge, time or money")
			runner.assert_true(not choices.is_empty(), "same currently visible target remains available while original process owns it")
			runtime.capability_adapter.panel.hide()
			runtime.object_adapter.select_object(ring)
			runner.assert_true(runtime.object_adapter.panel._activity.text.contains("秒"), "two-second operation is described in seconds")
			var source_qi: int = int(world.conflicts.body("player").qi)
			due = int(world.artifacts.active.player.due_ms)
			helper._advance(runtime, due - GameClock.elapsed_ms)
			runner.assert_true(world.artifacts.objects.training_sword.container == "actor:player", "original selected sword enters actual original body custody")
			runner.assert_eq(int(world.conflicts.body("player").qi), source_qi, "completion does not pay the same original qi twice")
			var future: String = _json(WorldSessionSnapshot.capture(runtime))
			runner.assert_true(not WorldSessionSnapshot.stage(runtime, WorldSessionSnapshot.capture(runtime)).is_empty(), "complete original draw world stages independently")
			runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(helper.DRAW_ARCHIVE)), OK, "original loader restores real paid draw middle")
			helper._advance(runtime, due - GameClock.elapsed_ms)
			runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), future, "original paid draw resumes to identical full future once")
	main.free()
	GameClock.restore_state(previous_clock)
	print("SCENARIO product drawing: genuine earlier take, actual research and short walk, original target selection, sourced capability, seconds UI and full paid continuation")


func _check_research_preserves_position(runner: Object, runtime: WorldContinuityRuntime, helper: RefCounted) -> void:
	if runtime.load_game(ProjectSettings.globalize_path(helper.V40_TAKE)) != OK:
		runner.assert_true(false, "continuous research probe loads the genuine earlier take")
		return
	GameClock.set_paused(true)
	if not helper._finish_artifact(runtime) or not runtime.object_adapter.select_object(helper.RING) or not runtime.object_adapter.submit("study").ok or not helper._finish_artifact(runtime):
		runner.assert_true(false, "continuous research probe completes real ring take and shape study")
		return
	var player: PlayerCharacter = runtime.home_runtime()._player
	var before: Vector2 = player.motion.position + Vector2(7.25, -3.5)
	# Controlled within-cell test position: the same original body keeps a
	# continuous point rather than moving to the grid centre on submission.
	player.motion.position = before
	player.motion.velocity = Vector2(10.0, 0.0)
	player._project_motion()
	var reply: Dictionary = runtime.object_adapter.submit("use_research")
	runner.assert_true(bool(reply.ok), "research starts from the controlled continuous body position")
	if bool(reply.ok):
		runner.assert_eq(player.motion.position, before, "research preserves the original continuous position at start")
		runner.assert_true(player.motion.velocity.is_zero_approx(), "starting research clears the original body's residual velocity")


func _check_stationary_candidate(runner: Object, runtime: WorldContinuityRuntime, verb: String) -> void:
	var good: Dictionary = WorldSessionSnapshot.capture(runtime)
	var before: String = _json(good)
	runner.assert_eq(str(good.continuity.world.artifacts.active.player.verb), verb, verb + " candidate comes from its real in-flight process")
	runner.assert_eq(good.player.motion.velocity, [0.0, 0.0], verb + " real body is stopped during the process")
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, good).is_empty(), verb + " accepts its actual zero-speed candidate")
	runner.assert_eq(_json(good), before, verb + " valid candidate staging leaves its input untouched")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, verb + " valid candidate staging leaves the live process untouched")
	for speed: float in [10.0, 0.000001]:
		var moving: Dictionary = good.duplicate(true)
		moving.player.motion.velocity = [speed, 0.0]
		var moving_before: String = _json(moving)
		runner.assert_true(WorldSessionSnapshot.stage(runtime, moving).is_empty(), verb + " rejects in-flight speed %s" % speed)
		runner.assert_eq(_json(moving), moving_before, verb + " rejection leaves the supplied candidate untouched")
		runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, verb + " rejection leaves the live process untouched")


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
