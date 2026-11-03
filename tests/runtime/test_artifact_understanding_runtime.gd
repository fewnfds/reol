extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	var runtime: WorldContinuityRuntime = fixture.continuity
	var domain: SimArtifacts = runtime.world_sim.artifacts
	var at: Vector2i = domain.object_cell("hearth_stone")
	fixture.player.spawn_at(at)
	for id: String in ["su_zhi", "chen_shouzhuo"]:
		fixture.home.simulation.set_actor_cell(id, at)
		fixture.home.simulation.actors[id].autonomous = false
	runtime.prepare_player_command()
	var adapter: WorldObjectsRuntime = runtime.object_adapter
	runner.assert_true(adapter.select_object("hearth_stone"), "real inspector opens on its original shared object")
	fixture.home._selected_actor = "su_zhi"
	runner.assert_true(adapter.submit("ask_examine").ok, "selected nearby artisan commits a real NPC inspection through UI intent")
	runner.assert_true(adapter.panel._activity.text.contains("同门正在辨看"), "pending advice displays the other person's actual committed activity")
	GameClock.advance_msec(447)
	var path: String = "user://tests/material_advice_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "pending NPC check and designated recipient save together")
	GameClock.advance_msec(120000)
	var expected: String = _canonical(runtime)
	var view: Dictionary = runtime.world_sim.artifacts.describe("player", "hearth_stone")
	runner.assert_true(str(view.line).contains("苏芷曾告诉你") and not view.method, "UI refresh receives an attributed result without copying mastery")
	runner.assert_true(adapter.panel._description.text.contains("细裂"), "completed fractional-minute inspection refreshes the visible object description")
	runner.assert_true(adapter.panel._notice.text.contains("苏芷："), "heard result replaces the obsolete started-action notice")
	runner.assert_eq(runtime.load_game(path), OK, "ordinary runtime load restores an ongoing NPC check")
	GameClock.advance_msec(120000)
	runner.assert_true(_canonical(runtime) == expected, "normal read path resumes NPC timing, knowledge and physical state identically")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	fixtures._dispose(fixture)
	print("SCENARIO material advice UI: selected person performs a real timed check; normal JSON resumes its private source and heard result")


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)
