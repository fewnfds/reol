extends RefCounted
## Product route from a current ordinary opening; no invented body or resources.


func run(runner: Object) -> void:
	var previous_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var helper: RefCounted = load("res://tests/runtime/helpers/drawing_replay.gd").new()
	var research_path: String = _unused_path("research")
	var draw_path: String = _unused_path("draw")
	if runtime == null or runtime.world_sim == null or research_path.is_empty() or draw_path.is_empty():
		runner.assert_true(false, "current drawing scene and unused save paths are available")
	else:
		# This case checks complete drawing futures, not per-frame budgets.
		runtime.settlement_work_budget = 2147483647
		_exercise_current(runner, runtime, helper, research_path, draw_path)
	_remove(research_path)
	_remove(draw_path)
	main.free()
	GameClock.restore_state(previous_clock)
	print("SCENARIO product drawing: current real clue, travel, paid research, target selection, seconds UI and full continuation")


func _prepare_research(runner: Object, runtime: WorldContinuityRuntime, helper: RefCounted) -> bool:
	var report: Dictionary = {"steps": []}
	var chose: bool = helper._choose(runtime)
	runner.assert_true(chose, "current ordinary opening chooses the original player")
	if not chose:
		return false
	var heard: bool = helper._ask(runtime, report)
	runner.assert_true(heard, "the actual player hears the site clue in person")
	if not heard:
		return false
	var travelled: bool = runtime.travel_to_site("broken_stele") and helper._finish_trip(runtime)
	runner.assert_true(travelled, "the original player travels to the known site")
	if not travelled or not runtime.object_adapter.select_object(helper.RING):
		return false
	for verb: String in ["take", "study"]:
		var reply: Dictionary = runtime.object_adapter.submit(verb)
		var finished: bool = bool(reply.get("ok", false)) and helper._finish_artifact(runtime)
		runner.assert_true(finished, "the real ring action completes: " + verb)
		if not finished:
			return false
	var player: PlayerCharacter = runtime.home_runtime()._player
	var point: Vector2 = player.motion.position + Vector2(7.25, -3.5)
	# Controlled within-cell point; the real action must not snap the body.
	player.motion.position = point
	player.motion.velocity = Vector2(10.0, 0.0)
	player._project_motion()
	var started: Dictionary = runtime.object_adapter.submit("use_research")
	runner.assert_true(bool(started.get("ok", false)), "research starts from the actual continuous body point")
	if not bool(started.get("ok", false)):
		return false
	runner.assert_eq(player.motion.position, point, "research preserves the continuous point at start")
	runner.assert_true(player.motion.velocity.is_zero_approx(), "starting research clears the body's residual velocity")
	var advanced: bool = helper._advance(runtime, 30000)
	runner.assert_true(advanced and runtime.world_sim.artifacts.active.has("player"), "paid research reaches a real in-flight checkpoint")
	return advanced and runtime.world_sim.artifacts.active.has("player")


func _exercise_current(runner: Object, runtime: WorldContinuityRuntime, helper: RefCounted, research_path: String, draw_path: String) -> void:
	if not _prepare_research(runner, runtime, helper):
		return
	var world: RegionalSimulation = runtime.world_sim
	runner.assert_true(not world.artifacts.learned_use("player", helper.RING), "incomplete paid research cannot grant use early")
	_check_stationary_candidate(runner, runtime, "use_research")
	var saved: Error = runtime.save_game(research_path)
	runner.assert_eq(saved, OK, "ordinary saver captures current in-flight research")
	if saved != OK:
		return
	var due: int = int(world.artifacts.active.player.due_ms)
	var reached: bool = helper._advance(runtime, due - GameClock.elapsed_ms)
	runner.assert_true(reached and world.artifacts.learned_use("player", helper.RING), "research reaches its original deadline and personal mastery")
	if not reached:
		return
	var research_future: String = _json(WorldSessionSnapshot.capture(runtime))
	var loaded: Error = runtime.load_game(research_path)
	runner.assert_eq(loaded, OK, "ordinary loader restores current legal stopped research")
	if loaded != OK:
		return
	runner.assert_true(helper._advance(runtime, due - GameClock.elapsed_ms), "restored research reaches the same original deadline")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), research_future, "legal stopped research resumes to the same complete future")
	world = runtime.world_sim
	var projected: Dictionary = SimCapabilityQueries.project(world, "player")
	for node: Dictionary in projected.nodes:
		if node.id == "drawing_ring":
			runner.assert_true(node.state == "learned" and not node.sources.is_empty(), "personal capability cites the original completed research")
	var report: Dictionary = {"steps": []}
	var positioned: bool = helper._to_drawing_position(runtime, report)
	runner.assert_true(positioned, "the player actually returns and walks to a visible drawing position")
	if not positioned or not runtime.object_adapter.select_object(helper.RING):
		return
	var drawing: Dictionary = runtime.object_adapter.submit_draw("training_sword")
	runner.assert_true(bool(drawing.get("ok", false)), "ordinary command starts the original paid draw")
	if not bool(drawing.get("ok", false)) or not helper._advance(runtime, 1000):
		return
	world = runtime.world_sim
	runner.assert_true(world.artifacts.objects.training_sword.container == "dorm", "incomplete draw keeps the original sword in its genuine slot")
	runtime.service_adapter.refresh()
	var activity: String = runtime.service_adapter.panel._phase.text
	runner.assert_true(activity.contains("1 秒") and not activity.contains("0 分钟"), "the actual mid-draw activity shows seconds")
	runner.assert_true(not runtime.travel_to("river"), "ongoing draw prevents a second journey on the same body")
	_check_stationary_candidate(runner, runtime, "draw")
	var before: String = _json(WorldSessionSnapshot.capture(runtime))
	var airborne: Dictionary = WorldSessionSnapshot.capture(runtime)
	airborne.player.altitude = 1
	runner.assert_true(WorldSessionSnapshot.stage(runtime, airborne).is_empty(), "candidate refuses unsupported airborne casting")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, "bad height preserves the complete live process")
	var choices: Array[Dictionary] = runtime.object_adapter.draw_targets()
	runtime.object_adapter.refresh()
	runtime.capability_adapter.show_panel()
	runtime.capability_adapter.refresh()
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, "view rebuilding and target choices do not generate knowledge, time or money")
	runner.assert_true(not choices.is_empty(), "the visible original target remains available while the process owns it")
	runtime.capability_adapter.panel.hide()
	runtime.object_adapter.select_object(helper.RING)
	runner.assert_true(runtime.object_adapter.panel._activity.text.contains("秒"), "the two-second operation is described in seconds")
	saved = runtime.save_game(draw_path)
	runner.assert_eq(saved, OK, "ordinary saver captures the real in-flight draw")
	if saved != OK:
		return
	var paid_qi: int = int(world.conflicts.body("player").qi)
	due = int(world.artifacts.active.player.due_ms)
	runner.assert_true(helper._advance(runtime, due - GameClock.elapsed_ms), "draw reaches its real completion")
	runner.assert_true(world.artifacts.objects.training_sword.container == "actor:player", "the original sword enters the original body custody")
	runner.assert_eq(int(world.conflicts.body("player").qi), paid_qi, "completion does not charge the original qi again")
	var future: String = _json(WorldSessionSnapshot.capture(runtime))
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, WorldSessionSnapshot.capture(runtime)).is_empty(), "complete draw stages independently")
	loaded = runtime.load_game(draw_path)
	runner.assert_eq(loaded, OK, "ordinary loader restores the paid current draw")
	if loaded != OK:
		return
	runner.assert_true(helper._advance(runtime, due - GameClock.elapsed_ms), "restored draw reaches the original deadline")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), future, "original paid draw resumes to the same complete future once")


func _unused_path(label: String) -> String:
	for attempt: int in 100:
		var path: String = "user://tests/drawing_runtime_%s_%d_%d.json" % [label, Time.get_ticks_usec(), attempt]
		var occupied: bool = false
		for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
			if FileAccess.file_exists(path + suffix):
				occupied = true
				break
		if not occupied:
			return path
	return ""


func _remove(path: String) -> void:
	if path.is_empty():
		return
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


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
