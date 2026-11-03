extends RefCounted
## Original paid body and teaching acquire the new use through a real process.


func run(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var path: String = "user://tests/capability_runtime_%d.json" % Time.get_ticks_usec()
	var response: Dictionary = runtime.capability_adapter.begin_practice()
	runner.assert_true(not bool(response.ok), "ordinary untrained human cannot buy mastery by opening the network")
	runner.assert_true(runtime.world_sim.capability_practice.active.is_empty(), "failed prerequisite starts no phantom body process")
	var error: Error = runtime.load_game(ProjectSettings.globalize_path("res://tests/fixtures/session_v35.json"))
	runner.assert_eq(error, OK, "normal loader restores actual original lesson and paid preparation")
	if error == OK:
		runtime.conflict_adapter.yield_player()
		_advance(runtime, GameClock.elapsed_ms + 5000)
		var world: RegionalSimulation = runtime.world_sim
		var before_qi: int = int(world.conflicts.body("player").qi)
		response = runtime.capability_adapter.begin_practice()
		runner.assert_true(bool(response.ok), "actually taught original body begins a future practice through the product entry: " + str(response))
		if bool(response.ok):
			var id: String = str(response.id)
			var job: Dictionary = world.capability_practice.active.player
			var done: int = int(job.complete_ms)
			var occupied: String = _json(WorldSessionSnapshot.capture(runtime))
			runner.assert_true(not runtime.travel_to("river"), "active practice refuses a second route for the same original body")
			runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), occupied, "rejected journey changes neither practice, body nor its actual cost")
			runner.assert_eq(int(world.conflicts.body("player").qi), before_qi - int(job.qi_spent), "practice pays from original qi once")
			runner.assert_true(world.conflicts.barriers.is_empty(), "practice does not invent a protective barrier")
			_advance(runtime, int(job.started_ms) + 15000)
			runner.assert_true(not world.capability_practice.learned("player"), "actual intermediate steps do not grant mastery early")
			runner.assert_eq(runtime.save_game(path), OK, "ordinary saver captures actual in-progress training")
			var intermediate: String = _json(WorldSessionSnapshot.capture(runtime))
			runner.assert_true(not WorldSessionSnapshot.stage(runtime, WorldSessionSnapshot.capture(runtime)).is_empty(), "independent candidate validates actual walking practice")
			_advance(runtime, done - 1)
			runner.assert_true(not world.capability_practice.learned("player"), "one millisecond before true completion remains unlearned")
			_advance(runtime, done)
			runner.assert_true(world.capability_practice.learned("player"), "all real paid stages complete before mobile use is learned")
			runner.assert_eq(world.capability_practice.learned_at("player"), done, "mastery has the actual completion instant")
			runner.assert_eq(world.capability_practice.records[id].status, "completed", "terminal record keeps the original process identity")
			var future: String = _json(WorldSessionSnapshot.capture(runtime))
			_write("res://logs/capability_runtime_expected.json", future)
			runner.assert_eq(runtime.load_game(path), OK, "ordinary loader restores the walking stage")
			runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), intermediate, "mid-practice replacement preserves the entire real session")
			_advance(runtime, done)
			_write("res://logs/capability_runtime_resumed.json", _json(WorldSessionSnapshot.capture(runtime)))
			runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), future, "restored real practice produces the same complete future without double spending")
			var current: Dictionary = WorldSessionSnapshot.capture(runtime)
			var broken: Dictionary = current.duplicate(true)
			broken.continuity.world.capability_practice.records.erase(id)
			runner.assert_true(WorldSessionSnapshot.stage(runtime, broken).is_empty(), "erasing payment and successful stages cannot leave an unexplained qi balance")
			runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), future, "failed independent candidate preserves the complete live future")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.free()
	GameClock.restore_state(clock)


func _advance(runtime: WorldContinuityRuntime, target: int) -> void:
	GameClock.advance_msec(target - GameClock.elapsed_ms)
	if runtime.world_sim.elapsed_ms < target:
		runtime.advance_to_ms(target)


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(value)
