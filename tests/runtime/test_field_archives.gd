extends RefCounted
## Immutable ordinary GUI archives: physical travel, take and absent NPC route.

const SOURCES: Dictionary = {
	"trip": ["session_v40.json", "383717fbed1a214a2e0d3e38ae4ff495a4d9b33666ff245fdb75e0900649a8b1"],
	"take": ["session_v40_take.json", "8a97fabf282c80a69cd718496a92889dfd30aa97be0ca728c4b17f2d065d4d02"],
	"npc": ["session_v40_npc.json", "27186018991b78ee1201e2d1286e16af206c72d7d3e9289cdf328fc40acbf7c0"],
}


func run(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	var expected: Dictionary = {}
	for attempt: int in 2:
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var runtime: WorldContinuityRuntime = main._continuity
		var helper: RefCounted = load("res://tests/runtime/helpers/field_replay.gd").new()
		for kind: String in SOURCES:
			var path: String = "res://tests/fixtures/" + str(SOURCES[kind][0])
			runner.assert_eq(FileAccess.get_sha256(path), str(SOURCES[kind][1]), "genuine field source preserves original bytes before replay: " + kind)
			var suffix: String = "archive_%s_%d" % [kind, attempt]
			var reply: Dictionary
			match kind:
				"trip": reply = helper.replay_trip(runtime, suffix, path)
				"take": reply = helper.replay_take(runtime, suffix, path)
				_: reply = helper.replay_npc(runtime, suffix, path)
			runner.assert_true(bool(reply.get("ok", false)), "actual field source reaches ordinary valid future: " + kind + " " + str(reply.get("error", "")))
			if bool(reply.get("ok", false)):
				var future: String = SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime)))
				if attempt == 0: expected[kind] = future
				else: runner.assert_eq(future, str(expected.get(kind, "")), "independent ordinary loaders preserve complete actual field future: " + kind)
			runner.assert_eq(FileAccess.get_sha256(path), str(SOURCES[kind][1]), "replaying does not rewrite genuine source: " + kind)
		main.free()
	GameClock.restore_state(clock)
