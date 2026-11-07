extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")
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
	# Current run() saves both the real labor and the in-progress wage claim.
	LegacyRejection.run(runner, {
		"res://tests/fixtures/session_v25.json": "f6cc8c84441c321b76154781a069ea7f999ef3f32fd8d8c7a56d7af3bfa5004e",
		"res://tests/fixtures/session_v26.json": "fb4e849222f1e738a5c9140012db5392ad74991c7986617cd2287fd1a167d360",
		"res://tests/fixtures/wage_claim_v26.json": "1ebf265690d16bea20290261292abbe20232b74d8f7a266e79a83fa731350c19",
	}, ["budgeted_labor"])
	print("SCENARIO wage UI: actual public sales fund original labor, C promise and timed acceptance share body/time, both mid-action saves reproduce identical future")


func _position(fixture: Dictionary) -> void:
	var runtime: WorldContinuityRuntime = fixture.continuity
	fixture.player.spawn_at(SimRouteTravel.cell(runtime._home.simulation.places.records.cell))
	runtime.prepare_player_command()


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)
