extends RefCounted
## The current ordinary opening earns a real lesson before its paid practice.

const Replay = preload("res://tests/runtime/helpers/capability_replay.gd")
const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")


func run(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var path: String = _unused_path()
	if runtime == null or runtime.world_sim == null or path.is_empty():
		runner.assert_true(false, "current capability scene and an unused save path are available")
	else:
		# This fixture compares complete practice/save futures, not frame budgets.
		runtime.settlement_work_budget = 2147483647
		_exercise_current(runner, runtime, path)
	_remove(path)
	main.free()
	GameClock.restore_state(clock)
	LegacyRejection.run(runner, {"res://tests/fixtures/session_v35.json": "b0765c3a7147ce6789b6211fa4d1f222646a4086e2b47594fa8ab4d32e4dd37f"})
	print("SCENARIO capability practice: current personal teaching, paid walking, real save/restore and retired archive rejection")


func _exercise_current(runner: Object, runtime: WorldContinuityRuntime, path: String) -> void:
	var chosen: bool = runtime.avatar_adapter.choose("subject:player") if runtime.avatar_adapter.opening.visible else runtime.human_player_active()
	runner.assert_true(chosen, "ordinary opening chooses the original human life")
	if not chosen:
		return
	GameClock.set_paused(true)
	GameClock.cancel_wait()
	GameClock.set_speed(1.0)
	var response: Dictionary = runtime.capability_adapter.begin_practice()
	runner.assert_true(not bool(response.ok), "ordinary untrained human cannot buy mastery by opening the network")
	runner.assert_true(runtime.world_sim.capability_practice.active.is_empty(), "failed prerequisite starts no phantom body process")
	# Travel and face-to-face teaching use the same ordinary bounded route as the
	# real capability replay; no body, skill, cost or consent is inserted.
	var helper := Replay.new()
	var report: Dictionary = {"steps": []}
	var teacher: String = helper._find_teacher(runtime, report)
	runner.assert_true(not teacher.is_empty(), "an actual nearby teacher agrees and completes the original personal lesson: " + str(report))
	if teacher.is_empty():
		return
	var world: RegionalSimulation = runtime.world_sim
	runner.assert_true(world.conflicts.knows("player", "qi_guard"), "the actual completed lesson teaches the original guard")
	var before_qi: int = int(world.conflicts.body("player").qi)
	response = runtime.capability_adapter.begin_practice()
	runner.assert_true(bool(response.ok), "actually taught original body begins practice through the product entry: " + str(response))
	if not bool(response.ok):
		return
	var id: String = str(response.id)
	var job: Dictionary = world.capability_practice.active.player
	var done: int = int(job.complete_ms)
	var occupied: String = _json(WorldSessionSnapshot.capture(runtime))
	runner.assert_true(not runtime.travel_to("river"), "active practice refuses a second route for the same body")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), occupied, "rejected journey changes neither practice, body nor actual cost")
	runner.assert_eq(int(world.conflicts.body("player").qi), before_qi - int(job.qi_spent), "practice pays the original qi once")
	runner.assert_true(world.conflicts.barriers.is_empty(), "practice creates no protective barrier")
	_advance(runtime, int(job.started_ms) + 15000)
	runner.assert_true(not world.capability_practice.learned("player"), "actual intermediate steps do not grant mastery early")
	var saved: Error = runtime.save_game(path)
	runner.assert_eq(saved, OK, "ordinary saver captures actual in-progress training")
	if saved != OK:
		return
	var intermediate: String = _json(WorldSessionSnapshot.capture(runtime))
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, WorldSessionSnapshot.capture(runtime)).is_empty(), "independent candidate validates actual walking practice")
	_advance(runtime, done - 1)
	runner.assert_true(not world.capability_practice.learned("player"), "one millisecond before completion remains unlearned")
	_advance(runtime, done)
	runner.assert_true(world.capability_practice.learned("player"), "all actual paid stages complete before mobile use is learned")
	runner.assert_eq(world.capability_practice.learned_at("player"), done, "mastery records the actual completion instant")
	runner.assert_eq(world.capability_practice.records[id].status, "completed", "terminal record keeps the original process identity")
	var future: String = _json(WorldSessionSnapshot.capture(runtime))
	var loaded: Error = runtime.load_game(path)
	runner.assert_eq(loaded, OK, "ordinary loader restores the walking stage")
	if loaded != OK:
		return
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), intermediate, "mid-practice replacement preserves the entire current session")
	_advance(runtime, done)
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), future, "restored real practice reaches the same complete future without double spending")
	var broken: Dictionary = WorldSessionSnapshot.capture(runtime)
	broken.continuity.world.capability_practice.records.erase(id)
	runner.assert_true(WorldSessionSnapshot.stage(runtime, broken).is_empty(), "erasing payment and successful stages cannot leave an unexplained qi balance")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), future, "failed independent candidate preserves the complete live future")


func _advance(_runtime: WorldContinuityRuntime, target: int) -> void:
	GameClock.advance_msec(target - GameClock.elapsed_ms)
	for _attempt: int in 4096:
		if not GameClock.has_pending_advance():
			break
		GameClock._process(0.0)


func _unused_path() -> String:
	for attempt: int in 100:
		var path: String = "user://tests/capability_runtime_%d_%d.json" % [Time.get_ticks_usec(), attempt]
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


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
