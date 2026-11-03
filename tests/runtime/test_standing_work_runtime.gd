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
	var prior: Dictionary = GameClock.to_dict()
	var path: String = "res://tests/fixtures/session_v21.json"
	var original: String = FileAccess.get_file_as_string(path)
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var result: Error = runtime.load_game(ProjectSettings.globalize_path(path))
	runner.assert_eq(result, OK, "genuine v21 migrates without inventing cooperative social history")
	if result == OK:
		runner.assert_true(runtime.world_sim.standing_work.entries.is_empty(), "old residents acquire no fabricated promises")
		runner.assert_eq(runtime.player_inventory().quantity("actor:player", "wood"), 6, "new intention domain changes no old actual material")
		runner.assert_eq(runtime.player_inventory().entrusted("actor:player", "wood"), 3, "old actual return custody is preserved")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "genuine v21 source remains immutable")
	main.free()
	GameClock.restore_state(prior)


func _test_actual_archive(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var path: String = "res://tests/fixtures/session_v22.json"
	var original: String = FileAccess.get_file_as_string(path)
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var result: Error = runtime.load_game(ProjectSettings.globalize_path(path))
	runner.assert_eq(result, OK, "genuine v22 has a real accepted agreement while the player is away")
	if result == OK:
		var id: String = "standing:home:request_4"
		runner.assert_eq(runtime.current_region, "river", "genuine actor actually traveled away from the cooperating NPC")
		runner.assert_eq(runtime.world_sim.standing_work.describe("player", id).code, "unconfirmed", "genuine absent character cannot inspect remote progress")
		GameClock.advance_msec(1500000)
		var future: String = _canonical(runtime)
		runner.assert_eq(runtime.world_sim.regions.home.inventory.quantity("kitchen", "wood"), 6, "genuine absent companion actually delivers public wood")
		runner.assert_eq(runtime.world_sim.regions.home.institutions.balance("sect", "player"), 0, "genuine requester receives no work credit for another's effort")
		main.free()
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		main = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		runtime = main._continuity
		runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(path)), OK, "fresh actual scene recovers the genuine ongoing promise")
		GameClock.advance_msec(1500000)
		runner.assert_true(_canonical(runtime) == future, "genuine absent work and all original world state have one identical future")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "real v22 archive is never rewritten")
	main.free()
	GameClock.restore_state(prior)
