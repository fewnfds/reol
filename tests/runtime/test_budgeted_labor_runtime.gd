extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
var fixtures := Fixtures.new()


func run(runner: Object) -> void:
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	for sim: VillageSimulation in runtime.world_sim.regions.values():
		for actor: String in sim.actors:
			sim.cancel_action(actor, "fixture_setup")
			sim.actors[actor].autonomous = false
	var sim: VillageSimulation = runtime._home.simulation
	_position(fixture)
	sim.set_actor_cell("chen_shouzhuo", SimRouteTravel.cell(sim.places.kitchen.cell))
	sim.observe_current_surroundings("chen_shouzhuo")
	sim.set_actor_cell("chen_shouzhuo", SimRouteTravel.cell(sim.places.records.cell))
	runtime.world_sim.invalidate_region("home")
	var ui: InteractionRequestsRuntime = runtime.interaction_adapter
	ui.show_panel()
	runner.assert_eq(ui.objects_for("accept_labor").size(), runtime.world_sim.budgeted_labor.definitions.offers.size(), "same C tool boundary supplies public labor terms without secret budgets")
	runner.assert_eq(ui.submit("subject:chen_shouzhuo", "accept_labor", {"kind": "labor_offer", "id": "deliver_wood"}).status, "refused", "normal unfunded public account refuses a cash job")
	var coins: int = runtime.player_inventory().quantity("actor:player", "coin")
	runner.assert_true(ui.submit("subject:chen_shouzhuo", "trade", {"kind": "trade_offer", "id": "buy_meal"}, "spoken", {"lots": 1}).ok, "existing finite sale can actually earn public revenue")
	GameClock.advance_msec(180000)
	runner.assert_eq(runtime.player_inventory().quantity("records", "coin"), 2, "employer capital is actual money received for real food")
	_position(fixture)
	ui.show_panel()
	var accepted: Dictionary = ui.submit("subject:chen_shouzhuo", "accept_labor", {"kind": "labor_offer", "id": "deliver_wood"})
	runner.assert_true(accepted.ok, "player can use structured request to accept the needed public cash job")
	if not accepted.ok:
		fixtures._dispose(fixture)
		return
	var id: String = str(accepted.process.id)
	runner.assert_true(runtime._home._automatic_player_motion() and not sim.submit_action("player", "cook") and not runtime.world_sim.services.begin("player", "home", "rest").ok, "original native body owns paid labor; another executor cannot steal it and manual interruption stays available")
	runner.assert_eq(runtime.player_inventory().quantity(id, "coin"), 2, "real received public money is now the unique wage fund")
	GameClock.advance_msec(1234)
	var path: String = "user://tests/budgeted_labor_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "ordinary joint save captures paid native work in flight")
	GameClock.advance_msec(600000)
	var future: String = _canonical(runtime)
	runner.assert_eq(runtime.world_sim.budgeted_labor.contracts[id].status, "payable", "original native work produces actual pending acceptance")
	runner.assert_true(runtime.service_adapter.panel._labor_note.text.contains("待验") or runtime.service_adapter.panel._labor_note.text.contains("验收"), "wage page explains earned money still needs actual acceptance")
	runner.assert_eq(runtime.player_inventory().quantity("actor:player", "coin"), coins - 2, "finishing labor does not remotely collect the wage")
	runner.assert_true(runtime._home.simulation.actors.player.receipts.is_empty(), "cash labor gives no extra contribution receipt")
	runner.assert_eq(runtime.load_game(path), OK, "ordinary loader restores real paid labor and budget")
	ui.show_panel()
	runner.assert_eq(ui._receipt, accepted.process, "participant's pending promise reconstructs after replacing the scene state")
	GameClock.advance_msec(600000)
	runner.assert_eq(_canonical(runtime), future, "paid native work resumes exactly the same joint future")
	_position(fixture)
	ui.show_panel()
	var claim: Dictionary = ui.submit("subject:chen_shouzhuo", "claim_wage", {"kind": "labor_contract", "id": id})
	runner.assert_true(claim.ok and runtime.world_sim.services.owns_actor("player"), "C acceptance request starts the existing timed service body")
	GameClock.advance_msec(1001)
	var claim_path: String = "user://tests/budgeted_claim_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(claim_path), OK, "ordinary joint save also captures unfinished acceptance")
	GameClock.advance_msec(180000)
	future = _canonical(runtime)
	runner.assert_eq(runtime.world_sim.budgeted_labor.contracts[id].status, "paid", "actual acceptance moves wage into original bag")
	runner.assert_eq(runtime.player_inventory().quantity("actor:player", "coin"), coins, "worker earns back exactly the two previously circulated coins")
	runner.assert_eq(runtime.player_inventory().quantity(id, "coin"), 0, "the single fund is emptied once")
	runner.assert_eq(runtime.load_game(claim_path), OK, "claim-in-progress crosses normal candidate boundary")
	ui.show_panel()
	runner.assert_eq(ui._receipt, claim.process, "latest participant progress reconstructs the actual acceptance job")
	GameClock.advance_msec(180000)
	runner.assert_eq(_canonical(runtime), future, "acceptance restart cannot repeat wages or change any world ledger")
	runner.assert_true(ui._progress.text.contains("验收") and ui._progress.text.contains("2钱"), "same interaction reports concrete paid outcome")
	for saved: String in [path, claim_path]:
		for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
			if FileAccess.file_exists(saved + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(saved + suffix))
	fixtures._dispose(fixture)
	_old_archive(runner)
	_actual_archives(runner)
	print("SCENARIO wage UI: actual public sales fund original labor, C promise and timed acceptance share body/time, both mid-action saves reproduce identical future")


func _position(fixture: Dictionary) -> void:
	var runtime: WorldContinuityRuntime = fixture.continuity
	fixture.player.spawn_at(SimRouteTravel.cell(runtime._home.simulation.places.records.cell))
	runtime.prepare_player_command()


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _old_archive(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var path: String = "res://tests/fixtures/session_v25.json"
	var original: String = FileAccess.get_file_as_string(path)
	var old: Dictionary = JSON.parse_string(original)
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(path)), OK, "genuine private-production v25 migrates through ordinary loader")
	runner.assert_true(runtime.world_sim.budgeted_labor.contracts.is_empty(), "migration invents no historical wage promise")
	runner.assert_eq(runtime.player_inventory().quantity("records", "coin"), old.simulation.inventory.containers.records.get("coin", 0), "migration does not invent capital for the employer")
	runner.assert_eq(runtime.world_sim.personal_production.active.player.id, "production_job:2", "existing production keeps original body and unfinished effort")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "genuine v25 archive remains byte-for-byte unchanged")
	main.free()
	GameClock.restore_state(prior)


func _actual_archives(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	for file: String in ["session_v26.json", "wage_claim_v26.json"]:
		var path: String = "res://tests/fixtures/" + file
		var original: String = FileAccess.get_file_as_string(path)
		var expected: String = ""
		for attempt: int in 2:
			GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
			var main: Node = load("res://scenes/main.tscn").instantiate()
			runner.root.add_child(main)
			var runtime: WorldContinuityRuntime = main._continuity
			var loaded: Error = runtime.load_game(ProjectSettings.globalize_path(path))
			runner.assert_eq(loaded, OK, "genuine clicked wage scene loads normally: " + file)
			if loaded != OK:
				main.free()
				continue
			var note: Dictionary = runtime.world_sim.budgeted_labor.contracts["labor:1"]
			var cook: Dictionary = runtime._home.simulation.actors.a_he
			var own_study: Dictionary = runtime.world_sim.artifacts.active.get("a_he", {})
			runner.assert_true(bool(cook.autonomous) or bool(own_study.get("previous_autonomous", false)), "genuine wage archive retains autonomous life including the cook's own underway investigation")
			runner.assert_eq(runtime.player_inventory().quantity("actor:player", "coin"), 4, "actual sale funded two public coins without injecting capital")
			runner.assert_eq(runtime.player_inventory().quantity("labor:1", "coin"), 2, "archive contains the same actual dedicated fund")
			if file == "session_v26.json":
				runner.assert_eq(GameClock.elapsed_ms, 183551, "real archive preserves fractional resumed delivery time")
				runner.assert_eq(runtime._home.simulation.actors.player.active.id, "action:8", "same original body resumes the second delivery attempt")
				runner.assert_eq(note.attempts.size(), 2, "normal stop and resumption retain their separate attempts")
				runner.assert_eq(runtime.player_inventory().entrusted("actor:player", "wood"), 3, "real in-flight public wood stays entrusted")
				GameClock.advance_msec(500000)
				runner.assert_eq(note.status, "payable", "genuine restarted delivery earns only a pending wage")
				runner.assert_eq(note.attempts.back().ended_ms, 485050, "original interrupted trip needs the same actual remaining labor")
			else:
				runner.assert_eq(GameClock.elapsed_ms, 684552, "genuine claim preserves fractional original shared time")
				runner.assert_eq(runtime.world_sim.services.active_jobs.player, "service:job:4", "genuine acceptance resumes the original timed service")
				GameClock.advance_msec(180000)
				runner.assert_eq(note.status, "paid", "genuine claim transfers real held money once")
				runner.assert_eq(note.terminal_ms, 804841, "accepted original appointment pays at the same millisecond")
				runner.assert_eq(runtime.player_inventory().quantity("actor:player", "coin"), 6, "earned coins enter the original human bag")
				runner.assert_eq(runtime.player_inventory().quantity("labor:1", "coin"), 0, "actual escrow is empty after payment")
			runner.assert_true(runtime._home.simulation.actors.player.receipts.is_empty(), "real paid delivery never produces duplicate public credit")
			runner.assert_eq(runtime._home.simulation.institutions.balance("sect", "player"), 0, "actual official contribution remains zero")
			if attempt == 0:
				expected = _canonical(runtime)
			else:
				runner.assert_eq(_canonical(runtime), expected, "genuine archive gives identical entire future after scene replacement: " + file)
			main.free()
		runner.assert_eq(FileAccess.get_file_as_string(path), original, "tests never generate or rewrite the genuine clicked archive: " + file)
	GameClock.restore_state(prior)
