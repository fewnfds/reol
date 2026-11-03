extends RefCounted
## Genuine paid v41 in-flight histories continue through the ordinary loader.

const CASES: Dictionary = {
	"research": {
		"archive": "res://tests/fixtures/session_v41_research.json",
		"sha256": "bb08013411cdf841521107aeb3941636d117369004d1f7d3a9ee8b63d46c6fbc",
		"source_ms": 281500, "source_qi": 18, "verb": "use_research", "due_ms": 371500,
		"outcome_ms": 384000, "future_ms": 514250, "container": "actor:player",
	},
	"draw": {
		"archive": "res://tests/fixtures/session_v41_draw.json",
		"sha256": "a814606c6b8a9666267378ce7ad104fabbb3d1fbe7c2d340bec7ed3583e66143",
		"source_ms": 383000, "source_qi": 16, "verb": "draw", "due_ms": 384000,
		"outcome_ms": 384000, "future_ms": 514250, "container": "actor:player",
	},
	"cancel": {
		"archive": "res://tests/fixtures/session_v41_draw.json",
		"sha256": "a814606c6b8a9666267378ce7ad104fabbb3d1fbe7c2d340bec7ed3583e66143",
		"source_ms": 383000, "source_qi": 16, "verb": "draw", "due_ms": 384000,
		"outcome_ms": 383000, "future_ms": 513250, "container": "dorm",
	},
}
const RING: String = "stele_drawing_ring"
const SWORD: String = "training_sword"


func run(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		runner.assert_true(false, "ordinary main scene loads for genuine v41 continuity")
		GameClock.restore_state(saved_clock)
		return
	var main: Node = scene.instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary main initializes its original world for v41 continuity")
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var helper: RefCounted = load("res://tests/runtime/helpers/drawing_replay.gd").new()
	var first_futures: Dictionary = {}
	for kind: String in CASES:
		var spec: Dictionary = CASES[kind]
		var archive: String = str(spec.archive)
		for attempt: int in 2:
			runner.assert_eq(FileAccess.get_sha256(archive), str(spec.sha256), "immutable v41 source matches its recorded SHA before replay: " + kind)
			var loaded: Error = runtime.load_game(ProjectSettings.globalize_path(archive))
			runner.assert_eq(loaded, OK, "ordinary loader reads genuine in-flight v41 source: " + kind)
			if loaded != OK:
				runner.assert_eq(FileAccess.get_sha256(archive), str(spec.sha256), "refused load leaves the actual v41 source bytes intact: " + kind)
				continue
			_check_source(runner, runtime, spec, kind)
			var suffix: String = "continuity_%s_%d_%d" % [kind, attempt, Time.get_ticks_usec()]
			var reply: Dictionary
			if kind == "research":
				reply = helper.replay_research(runtime, suffix, archive)
			else:
				reply = helper.replay_draw(runtime, suffix, kind == "cancel", archive)
			runner.assert_true(bool(reply.get("ok", false)), "ordinary v41 replay reaches its real future: " + kind + " " + str(reply.get("error", "")))
			if bool(reply.get("ok", false)):
				_check_future(runner, runtime, reply, spec, kind, attempt, first_futures)
			runner.assert_eq(FileAccess.get_sha256(archive), str(spec.sha256), "ordinary replay leaves the actual v41 source bytes intact: " + kind)
	main.free()
	GameClock.restore_state(saved_clock)
	print("SCENARIO drawing continuity: genuine paid research and draw archives, two original-loader replays per completion or cancellation branch and byte-identical complete futures")


func _check_source(runner: Object, runtime: WorldContinuityRuntime, spec: Dictionary, kind: String) -> void:
	var world: RegionalSimulation = runtime.world_sim
	var job: Dictionary = world.artifacts.active.get("player", {})
	runner.assert_eq(GameClock.elapsed_ms, int(spec.source_ms), "source retains its exact in-flight instant: " + kind)
	runner.assert_eq(int(world.elapsed_ms), int(spec.source_ms), "source's regional clock agrees with the original clock: " + kind)
	runner.assert_eq(int(world.conflicts.body("player").qi), int(spec.source_qi), "source retains its already paid original qi: " + kind)
	runner.assert_eq(str(job.get("verb", "")), str(spec.verb), "source retains the original in-flight verb: " + kind)
	runner.assert_eq(int(job.get("due_ms", -1)), int(spec.due_ms), "source retains the actual original deadline: " + kind)
	runner.assert_eq(int(job.get("qi_spent", -1)), 2, "source records the committed two qi: " + kind)
	runner.assert_eq(world.artifacts.objects[RING].container, "actor:player", "source holds the original ring: " + kind)
	runner.assert_eq(world.artifacts.objects[SWORD].container, "dorm", "source keeps the original sword in its real loose slot: " + kind)
	runner.assert_eq(world.artifacts.learned_use("player", RING), kind != "research", "source retains only its actually completed use knowledge: " + kind)
	var source: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, source).is_empty(), "loaded in-flight world remains an independently valid candidate: " + kind)


func _check_future(runner: Object, runtime: WorldContinuityRuntime, reply: Dictionary, spec: Dictionary, kind: String, attempt: int, first_futures: Dictionary) -> void:
	runner.assert_true(bool(reply.get("ordinary_commands", false)), "future uses original commands: " + kind)
	runner.assert_true(bool(reply.get("candidate_valid", false)), "replay independently validates its complete future: " + kind)
	runner.assert_eq(int(reply.get("ms", -1)), int(spec.future_ms), "future reaches its exact original instant: " + kind)
	runner.assert_eq(GameClock.elapsed_ms, int(spec.future_ms), "future remains on the shared clock: " + kind)
	runner.assert_eq(int(reply.get("qi", -1)), 16, "future retains both genuine committed qi costs: " + kind)
	runner.assert_eq(int(runtime.world_sim.conflicts.body("player").qi), 16, "the original body has the same actual qi balance: " + kind)
	var target: Dictionary = reply.get("target", {})
	runner.assert_eq(target, {"definition": "wooden_sword", "region": "home", "container": str(spec.container)}, "future keeps the same original sword in the expected custody: " + kind)
	runner.assert_eq(runtime.world_sim.artifacts.objects[SWORD], target, "reported target is the actual original object: " + kind)
	runner.assert_eq(runtime.world_sim.artifacts.objects[RING].container, "actor:player", "future still retains the original ring: " + kind)
	var outcome: Dictionary = {}
	for step: Dictionary in reply.get("steps", []):
		if step.get("kind") == "same_original_target":
			outcome = step
	runner.assert_true(not outcome.is_empty(), "replay records the actual target outcome before travel: " + kind)
	if not outcome.is_empty():
		runner.assert_eq(int(outcome.at_ms), int(spec.outcome_ms), "completion or cancellation occurred at its actual instant: " + kind)
		runner.assert_eq(str(outcome.container), str(spec.container), "completion or cancellation preserves the right custody: " + kind)
	var path: String = str(reply.get("full_snapshot", ""))
	var exists: bool = not path.is_empty() and FileAccess.file_exists(path)
	runner.assert_true(exists, "replay writes the full joint future to an actual file: " + kind)
	if not exists:
		return
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	runner.assert_true(not bytes.is_empty(), "actual future file is nonempty: " + kind)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	runner.assert_true(parsed is Dictionary, "actual future file contains a complete JSON snapshot: " + kind)
	if parsed is Dictionary:
		var snapshot: Dictionary = parsed
		runner.assert_true(not WorldSessionSnapshot.stage(runtime, snapshot).is_empty(), "saved future itself passes candidate validation: " + kind)
		runner.assert_true(_json(snapshot) == _json(WorldSessionSnapshot.capture(runtime)), "saved future agrees with the entire original live session: " + kind)
	if attempt == 0:
		first_futures[kind] = bytes
	else:
		runner.assert_true(first_futures.has(kind), "first same-source replay produced a complete future: " + kind)
		if first_futures.has(kind):
			runner.assert_true(bytes == first_futures[kind], "two same-source ordinary replays produce byte-identical complete futures: " + kind)


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
