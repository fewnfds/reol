extends RefCounted
## Actual main-scene clue, route and unique-object continuation.


func run(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var helper: RefCounted = load("res://tests/runtime/helpers/field_replay.gd").new()
	var path: String = "user://tests/field_trip_%d.json" % Time.get_ticks_usec()
	var domain: RefCounted = runtime.world_sim.field_opportunities
	runner.assert_eq(domain.known_sites("player").size(), 0, "new player does not receive someone else's old clue")
	runner.assert_true(domain.destination("player", "broken_stele").is_empty(), "hidden POI cannot be used as a known destination")
	var before: String = _canonical(runtime)
	domain.known_sites("player")
	domain.nearby_visible_sites("player")
	domain.destination("player", "broken_stele")
	runner.assert_eq(_canonical(runtime), before, "site presentation queries cannot grant knowledge, spawn treasure or advance the world")
	runner.assert_true(not runtime.travel_to_site("broken_stele"), "unreceived clue cannot grant an invisible travel shortcut")
	runner.assert_eq(_canonical(runtime), before, "refused unknown-site travel preserves the complete joint session")
	var prepared: Dictionary = helper.prepare_trip(runtime, path)
	runner.assert_true(bool(prepared.get("ok", false)), "ordinary opening earns a real field clue and travel archive: " + str(prepared.get("error", "")))
	if bool(prepared.get("ok", false)):
		runner.assert_true(not runtime.player_journey.is_empty(), "actual save is partway through physical route")
		runner.assert_true(runtime.load_game(ProjectSettings.globalize_path(path)) == OK and helper._finish_trip(runtime), "actual in-flight source can arrive at its fractional-millisecond destination")
		runner.assert_true(not runtime.service_adapter.panel._activity.text.contains("正在前往"), "arrival immediately clears the old travel activity without waiting for a minute or a new action")
		var future: Dictionary = helper.replay_trip(runtime, "test_early_a", path)
		runner.assert_true(bool(future.get("ok", false)), "early arrival takes the same unique ring through original timed action: " + str(future.get("error", "")))
		if bool(future.get("ok", false)):
			var expected: String = _canonical(runtime)
			main.free()
			GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
			main = load("res://scenes/main.tscn").instantiate()
			runner.root.add_child(main)
			runtime = main._continuity
			future = helper.replay_trip(runtime, "test_early_b", path)
			runner.assert_true(bool(future.get("ok", false)), "fresh scene restores the same earned trip and physical take")
			runner.assert_eq(_canonical(runtime), expected, "independent full-session loaders reach byte-equivalent bodies, objects, memories, costs and continuing life")
			runner.assert_eq(runtime.world_sim.artifacts.objects.stele_drawing_ring.container, "actor:player", "only original ring remains in the player's actual custody")
			runner.assert_true(not runtime.world_sim.artifacts.describe("player", "stele_drawing_ring").method, "having an unusual ring does not grant its future ability")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".report.json"))
	main.free()
	GameClock.restore_state(saved_clock)


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime)))
