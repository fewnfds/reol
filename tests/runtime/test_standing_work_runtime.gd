extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	for sim: VillageSimulation in world.regions.values():
		for actor: String in sim.actors:
			sim.cancel_action(actor, "fixture_setup")
			sim.actors[actor].autonomous = false
	var sim: VillageSimulation = world.regions.home
	fixture.player.spawn_at(SimRouteTravel.cell(sim.places.kitchen.cell))
	runtime.prepare_player_command()
	sim.set_actor_cell("shi_tou", fixture.player.cell)
	sim.actors.shi_tou.autonomous = true
	sim.inventory.containers.kitchen.wood = 1
	var ui: InteractionRequestsRuntime = runtime.interaction_adapter
	ui.show_panel()
	var options: Array[Dictionary] = ui.objects_for("watch_supply")
	runner.assert_true(options.size() == 2, "actual request UI offers public intentions near the referenced kitchen")
	var reply: Dictionary = ui.submit(world.embodiment.subject_for_actor("shi_tou"), "watch_supply", {"kind": "work_plan", "id": "kitchen_wood"})
	runner.assert_true(reply.ok and reply.process.domain == "standing_work", "actual structured UI submits a real cooperative agreement")
	if reply.ok:
		GameClock.advance_msec(1000)
		var path: String = "user://qa_standing_work_runtime_test.json"
		runner.assert_eq(runtime.save_game(path), OK, "full session saves original consent and actual NPC work")
		GameClock.advance_msec(1500000)
		var future: String = _canonical(runtime)
		runner.assert_true(runtime.world_sim.regions.home.inventory.quantity("kitchen", "wood") > 1, "cooperative NPC really feeds original kitchen stock")
		runner.assert_eq(runtime.load_game(path), OK, "normal session loader restores the same promise and current body action")
		ui.show_panel()
		runner.assert_true(ui._receipt == reply.process, "request receipt reconstructs from original personal agreement after load")
		GameClock.advance_msec(1500000)
		runner.assert_true(_canonical(runtime) == future, "same cooperative work and distant world resume identically")
		for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	_fixtures._dispose(fixture)
	_test_previous_archive(runner)
	_test_actual_archive(runner)
	print("SCENARIO standing work UI: shared request/visible plan, original NPC autonomy and joint continuation, empty genuine old agreement migration")


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _test_previous_archive(runner: Object) -> void:
	# Old archives lack causal field history; current behavior is tested above.
	load("res://tests/runtime/helpers/legacy_rejection_archive.gd").run(runner, {
		"res://tests/fixtures/session_v21.json": ""
	})


func _test_actual_archive(runner: Object) -> void:
	# Old archives lack causal field history; current behavior is tested above.
	load("res://tests/runtime/helpers/legacy_rejection_archive.gd").run(runner, {
		"res://tests/fixtures/session_v22.json": ""
	})
