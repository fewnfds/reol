extends RefCounted
## The player never asks for an opportunity; another person pursues it anyway.


func run(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	# Compare completed absent-NPC futures; frame-budget continuation is tested
	# by the shared clock owner. Apply the same host policy after scene restart.
	runtime.settlement_work_budget = 2147483647
	var helper: RefCounted = load("res://tests/runtime/helpers/field_replay.gd").new()
	var path: String = "user://tests/field_absence_%d.json" % Time.get_ticks_usec()
	var prepared: Dictionary = helper.prepare_npc(runtime, path)
	runner.assert_true(bool(prepared.get("ok", false)), "untouched ordinary NPC chooses a real expedition while player only waits: " + str(prepared.get("error", "")))
	if bool(prepared.get("ok", false)):
		runner.assert_true(runtime.world_sim.field_opportunities.known_sites("player").is_empty(), "NPC departure never grants player the NPC's clue")
		runner.assert_true(not runtime.world_sim.field_opportunities.route_projection("river_shi_tou").is_empty(), "actual archive is inside NPC original continuous route")
		var first: Dictionary = helper.replay_npc(runtime, "test_absence_a", path)
		runner.assert_true(bool(first.get("ok", false)), "same NPC takes original ring before player asks and later visits: " + str(first.get("error", "")))
		if bool(first.get("ok", false)):
			var expected: String = _canonical(runtime)
			main.free()
			GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
			main = load("res://scenes/main.tscn").instantiate()
			runner.root.add_child(main)
			runtime = main._continuity
			runtime.settlement_work_budget = 2147483647
			var second: Dictionary = helper.replay_npc(runtime, "test_absence_b", path)
			runner.assert_true(bool(second.get("ok", false)), "fresh main restores actual NPC route and same later visit")
			runner.assert_eq(_canonical(runtime), expected, "NPC absence, later learned clue and current empty site have identical complete futures after independent loaders")
			runner.assert_eq(runtime.world_sim.artifacts.objects.stele_drawing_ring.container, "actor:river_shi_tou", "late player cannot respawn or silently confiscate the actual carried original")
			runner.assert_true(not runtime.object_adapter.select_object("stele_drawing_ring"), "empty-site player cannot inspect remote holder through notes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".report.json"))
	main.free()
	GameClock.restore_state(saved_clock)


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime)))
