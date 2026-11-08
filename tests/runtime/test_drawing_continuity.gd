extends RefCounted
## Research and drawing use current real work and the ordinary joint loader.

const Replay = preload("res://tests/runtime/helpers/drawing_replay.gd")
const RING: String = "stele_drawing_ring"
const SWORD: String = "training_sword"


func run(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var research_path: String = "user://tests/drawing_research_current_%d.json" % Time.get_ticks_usec()
	var draw_path: String = "user://tests/drawing_current_%d.json" % Time.get_ticks_usec()
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary scene initializes for drawing continuation")
		_cleanup(main, research_path, draw_path, saved_clock)
		return
	# This fixture checks completed research/draw futures, not frame budgets.
	runtime.settlement_work_budget = 2147483647
	_reject_historical_archives(runner, runtime)
	var helper := Replay.new()
	var report: Dictionary = {"steps": []}
	var chose: bool = helper._choose(runtime)
	runner.assert_true(chose, "current ordinary opening chooses the original player")
	if not chose:
		_cleanup(main, research_path, draw_path, saved_clock)
		return
	var heard: bool = helper._ask(runtime, report)
	runner.assert_true(heard, "the player obtains a real face-to-face site clue")
	if not heard:
		_cleanup(main, research_path, draw_path, saved_clock)
		return
	var travelled: bool = runtime.travel_to_site("broken_stele") and helper._finish_trip(runtime)
	runner.assert_true(travelled, "the player actually reaches the personally known site")
	if not travelled:
		_cleanup(main, research_path, draw_path, saved_clock)
		return
	var domain: SimArtifacts = runtime.world_sim.artifacts
	var selected: bool = runtime.object_adapter.select_object(RING)
	runner.assert_true(selected, "the real ring is visible at the arrived player's location")
	if not selected:
		_cleanup(main, research_path, draw_path, saved_clock)
		return
	for verb: String in ["take", "study"]:
		var reply: Dictionary = runtime.object_adapter.submit(verb)
		var completed: bool = bool(reply.get("ok", false)) and helper._finish_artifact(runtime)
		runner.assert_true(completed, "the original ring action actually completes: " + verb + " " + str(reply))
		if not completed:
			_cleanup(main, research_path, draw_path, saved_clock)
			return
	runner.assert_eq(str(domain.objects[RING].container), "actor:player", "the one actual ring is held by the original player")
	runner.assert_true(not domain.learned_use("player", RING), "shape study does not grant the later use early")
	var qi_before: int = int(runtime.world_sim.conflicts.body("player").qi)
	var research: Dictionary = runtime.object_adapter.submit("use_research")
	runner.assert_true(bool(research.get("ok", false)), "ordinary paid research starts on the original ring: " + str(research))
	if not bool(research.get("ok", false)):
		_cleanup(main, research_path, draw_path, saved_clock)
		return
	var research_job: Dictionary = domain.active.player.duplicate(true)
	var paid_qi: int = int(runtime.world_sim.conflicts.body("player").qi)
	runner.assert_eq(paid_qi, qi_before - int(research_job.qi_spent), "research debits its one original committed cost")
	var advanced: bool = helper._advance(runtime, 30000)
	runner.assert_true(advanced and domain.active.has("player") and not domain.learned_use("player", RING), "research remains unfinished at its real checkpoint")
	if not advanced or not domain.active.has("player"):
		_cleanup(main, research_path, draw_path, saved_clock)
		return
	var saved: Error = runtime.save_game(research_path)
	runner.assert_eq(saved, OK, "the current in-flight research saves with the whole session")
	if saved != OK:
		_cleanup(main, research_path, draw_path, saved_clock)
		return
	var research_present: String = _snapshot(runtime)
	var due: int = int(research_job.due_ms)
	var reached: bool = helper._advance(runtime, due - GameClock.elapsed_ms)
	runner.assert_true(reached and domain.learned_use("player", RING), "the original research completes once at its deadline")
	if not reached:
		_cleanup(main, research_path, draw_path, saved_clock)
		return
	var research_future: String = _snapshot(runtime)
	var loaded: Error = runtime.load_game(research_path)
	runner.assert_eq(loaded, OK, "ordinary loader restores the same current research")
	if loaded != OK:
		_cleanup(main, research_path, draw_path, saved_clock)
		return
	runner.assert_eq(_snapshot(runtime), research_present, "research checkpoint restores every original session fact")
	runner.assert_eq(int(runtime.world_sim.conflicts.body("player").qi), paid_qi, "loading research cannot pay twice")
	reached = helper._advance(runtime, due - GameClock.elapsed_ms)
	runner.assert_true(reached, "restored research reaches the original deadline")
	if not reached:
		_cleanup(main, research_path, draw_path, saved_clock)
		return
	runner.assert_eq(_snapshot(runtime), research_future, "restored research reaches the same full world future")
	var positioned: bool = helper._to_drawing_position(runtime, report)
	runner.assert_true(positioned, "the player walks to a real visible position near the original sword")
	if not positioned or not runtime.object_adapter.select_object(RING):
		_cleanup(main, research_path, draw_path, saved_clock)
		return
	domain = runtime.world_sim.artifacts
	var target_before: Dictionary = domain.objects[SWORD].duplicate(true)
	qi_before = int(runtime.world_sim.conflicts.body("player").qi)
	var draw: Dictionary = runtime.object_adapter.submit_draw(SWORD)
	runner.assert_true(bool(draw.get("ok", false)), "ordinary command starts a real draw of the original sword: " + str(draw))
	if not bool(draw.get("ok", false)):
		_cleanup(main, research_path, draw_path, saved_clock)
		return
	var draw_job: Dictionary = domain.active.player.duplicate(true)
	paid_qi = int(runtime.world_sim.conflicts.body("player").qi)
	runner.assert_eq(paid_qi, qi_before - int(draw_job.qi_spent), "drawing spends its original qi once on acceptance")
	advanced = helper._advance(runtime, 1000)
	runner.assert_true(advanced and domain.active.has("player"), "the actual drawing action remains in flight at one second")
	if not advanced or not domain.active.has("player"):
		_cleanup(main, research_path, draw_path, saved_clock)
		return
	runner.assert_eq(domain.objects[SWORD], target_before, "the target stays in its original custody until completion")
	saved = runtime.save_game(draw_path)
	runner.assert_eq(saved, OK, "the actual partially completed draw saves normally")
	if saved != OK:
		_cleanup(main, research_path, draw_path, saved_clock)
		return
	var draw_present: String = _snapshot(runtime)
	due = int(draw_job.due_ms)
	reached = helper._advance(runtime, due - GameClock.elapsed_ms)
	runner.assert_true(reached, "drawing reaches its real completion boundary")
	runner.assert_eq(str(domain.objects[SWORD].container), "actor:player", "completion moves the same original sword once")
	var draw_future: String = _snapshot(runtime)
	loaded = runtime.load_game(draw_path)
	runner.assert_eq(loaded, OK, "ordinary loader restores the unfinished draw")
	if loaded != OK:
		_cleanup(main, research_path, draw_path, saved_clock)
		return
	domain = runtime.world_sim.artifacts
	runner.assert_eq(_snapshot(runtime), draw_present, "draw checkpoint restores the single action and original target")
	runner.assert_eq(int(runtime.world_sim.conflicts.body("player").qi), paid_qi, "restoring a paid draw does not debit again")
	reached = helper._advance(runtime, due - GameClock.elapsed_ms)
	runner.assert_true(reached, "restored drawing reaches the same deadline")
	runner.assert_eq(_snapshot(runtime), draw_future, "the restored draw reaches the identical complete future")
	loaded = runtime.load_game(draw_path)
	runner.assert_eq(loaded, OK, "the same actual checkpoint restores for the cancellation branch")
	if loaded == OK:
		runtime.stop_player_action()
		runner.assert_true(helper._advance(runtime, due - GameClock.elapsed_ms), "the original deadline passes after cancellation")
		runner.assert_eq(runtime.world_sim.artifacts.objects[SWORD], target_before, "a cancelled draw cannot move or duplicate the original target")
		runner.assert_eq(int(runtime.world_sim.conflicts.body("player").qi), paid_qi, "cancellation cannot refund the committed draw cost")
	_cleanup(main, research_path, draw_path, saved_clock)
	print("SCENARIO drawing continuity: current real site, paid research and draw checkpoints, identical future, cancellation and old-archive rejection")


func _reject_historical_archives(runner: Object, runtime: WorldContinuityRuntime) -> void:
	var archives: Array[Dictionary] = [
		{"path": "res://tests/fixtures/session_v41_research.json", "sha": "bb08013411cdf841521107aeb3941636d117369004d1f7d3a9ee8b63d46c6fbc"},
		{"path": "res://tests/fixtures/session_v41_draw.json", "sha": "a814606c6b8a9666267378ce7ad104fabbb3d1fbe7c2d340bec7ed3583e66143"},
	]
	var world: RegionalSimulation = runtime.world_sim
	var content: ReolContentDB = runtime._home._content
	var terrain: WorldMapData = world.map_data
	var before: String = _snapshot(runtime)
	var clock: String = _json(GameClock.to_dict())
	for entry: Dictionary in archives:
		var path: String = str(entry.path)
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		var raw: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		runner.assert_eq(FileAccess.get_sha256(path), str(entry.sha), "historical drawing archive retains its recorded digest")
		runner.assert_true(raw is Dictionary, "historical drawing archive remains readable")
		if not raw is Dictionary:
			continue
		var source: Dictionary = raw
		var input: String = _json(source)
		runner.assert_eq(int(source.schema_version), 41, "historical drawing archive retains its root version")
		runner.assert_eq(SessionSaveSchema.rejection_reason(source.schema_version), SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT, "historical drawing has the old-environment rejection")
		runner.assert_true(WorldSessionSnapshot.stage(runtime, source).is_empty(), "historical drawing cannot invent a current environment")
		runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(path)), ERR_INVALID_DATA, "ordinary loader refuses historical drawing")
		runner.assert_true(runtime.world_sim == world and runtime._home._content == content and runtime.world_sim.map_data == terrain, "historical refusal keeps the live world owners")
		runner.assert_eq(_json(GameClock.to_dict()), clock, "historical refusal keeps common time")
		runner.assert_eq(_snapshot(runtime), before, "historical refusal keeps the complete current session")
		runner.assert_eq(_json(source), input, "staging leaves the original source dictionary unchanged")
		runner.assert_eq(FileAccess.get_file_as_bytes(path), bytes, "historical refusal leaves original file bytes unchanged")


func _cleanup(main: Node, research_path: String, draw_path: String, saved_clock: Dictionary) -> void:
	for path: String in [research_path, draw_path]:
		for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	if is_instance_valid(main):
		main.free()
	GameClock.restore_state(saved_clock)


func _snapshot(runtime: WorldContinuityRuntime) -> String:
	return _json(WorldSessionSnapshot.capture(runtime))


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
