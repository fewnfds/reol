extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
var fixtures := Fixtures.new()


func run(runner: Object) -> void:
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var sim: VillageSimulation = runtime.world_sim.regions.home
	# Only arrange the test player's starting approach. NPCs retain their normal
	# bodies, autonomy, resources and decisions throughout this scenario.
	fixture.player.spawn_at(SimRouteTravel.cell(sim.actors.chen_shouzhuo.cell))
	runtime.prepare_player_command()
	var bought: Dictionary = runtime.interaction_adapter.submit("subject:chen_shouzhuo", "trade", {"kind": "trade_offer", "id": "buy_meal"}, "spoken", {"lots": 1})
	runner.assert_true(bought.ok, "real player purchase can fund public labor without injected cash or goods")
	if not bought.ok:
		fixtures._dispose(fixture)
		return
	GameClock.advance_msec(180000)
	var found: bool = false
	for step: int in 360:
		var id: String = runtime.world_sim.budgeted_labor.latest_for("shi_tou")
		if not id.is_empty() and runtime.world_sim.budgeted_labor.contracts[id].status == "working":
			found = true
			break
		GameClock.advance_msec(30000)
	runner.assert_true(found, "ordinary autonomous residents find and negotiate an actually funded job")
	if found:
		var path: String = "user://tests/autonomous_livelihood_%d.json" % Time.get_ticks_usec()
		runner.assert_eq(runtime.save_game(path), OK, "normal joint save includes original NPC labor and bounded personal search")
		GameClock.advance_msec(3600000)
		var future: String = _canonical(runtime)
		var id: String = runtime.world_sim.budgeted_labor.latest_for("shi_tou")
		runner.assert_eq(runtime.world_sim.budgeted_labor.contracts[id].status, "paid", "normal scene NPC proceeds from real delivery to real acceptance")
		runner.assert_eq(runtime.world_sim.regions.home.inventory.available("actor:shi_tou", "meal"), 1, "normal scene NPC spends original wages on a carried reserve")
		runner.assert_eq(runtime.player_inventory().quantity("actor:player", "coin"), 4, "NPC life cannot take money directly from the player's bag")
		runner.assert_eq(runtime.load_game(path), OK, "normal candidate loader restores the autonomous NPC mid-job")
		GameClock.advance_msec(3600000)
		runner.assert_eq(_canonical(runtime), future, "all autonomous residents, inventories and messages resume the identical joint future")
		for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	fixtures._dispose(fixture)
	_legacy(runner)
	_actual_archive(runner)
	print("SCENARIO ordinary autonomous livelihood: player sale funds public budget, unmodified residents seek/fulfil/claim/buy; joint save resumes without an NPC script override")


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _legacy(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var path: String = "res://tests/fixtures/conversation_v26.json"
	var before: String = FileAccess.get_file_as_string(path)
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(path)), OK, "genuine v26 migrates at the ordinary session boundary")
	runner.assert_true(runtime.world_sim.autonomous_livelihood.plans.is_empty(), "old worlds receive no invented historic motives or job seeking")
	runner.assert_true(runtime.world_sim.regions.home.config.actions.has("seek_records"), "migration adds only the future public visit rule")
	runner.assert_eq(GameClock.elapsed_ms, 1001, "migration preserves original fractional time")
	runner.assert_eq(FileAccess.get_file_as_string(path), before, "genuine conversation fixture is never rewritten")
	main.free()
	GameClock.restore_state(prior)


func _actual_archive(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var path: String = "res://tests/fixtures/session_v27.json"
	var original: String = FileAccess.get_file_as_string(path)
	var expected: String = ""
	for attempt: int in 2:
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var runtime: WorldContinuityRuntime = main._continuity
		var err: Error = runtime.load_game(ProjectSettings.globalize_path(path))
		runner.assert_eq(err, OK, "real clicked-and-departed v27 loads into an independent normal scene")
		if err != OK:
			main.free()
			continue
		runner.assert_eq(GameClock.elapsed_ms, 4050050, "real archive keeps the same fractional time")
		runner.assert_eq(runtime.current_region, "river", "player's actual departure remains saved while home labor continues")
		runner.assert_eq(runtime.world_sim.budgeted_labor.contracts["labor:1"].status, "working", "archive contains a genuine ongoing autonomous contract")
		GameClock.advance_msec(3600000)
		runner.assert_eq(runtime.world_sim.budgeted_labor.contracts["labor:1"].status, "paid", "real absent resident actually reaches acceptance and payment")
		runner.assert_eq(runtime.player_inventory().available("actor:shi_tou", "meal"), 1, "real absent resident uses the original income for portable food")
		if attempt == 0:
			expected = _canonical(runtime)
		else:
			runner.assert_eq(_canonical(runtime), expected, "real autonomous archive yields the same complete future in two new scenes")
		main.free()
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "real autonomous fixture remains immutable")
	GameClock.restore_state(prior)
