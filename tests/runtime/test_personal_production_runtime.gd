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
	var inventory: SimInventory = runtime.player_inventory()
	inventory.containers["actor:player"].merge({"wood": 1, "herb": 2}, true)
	var panel: SettlementServicesPanel = runtime.service_adapter.panel
	panel._submit("production:new:dry_herbs")
	var domain: SimPersonalProduction = runtime.world_sim.personal_production
	runner.assert_true(domain.owns_actor("player"), "normal production page reserves ingredients and starts the real body")
	if not domain.owns_actor("player"):
		fixtures._dispose(fixture)
		return
	var id: String = str(domain.active.player.batch)
	runner.assert_true(not runtime.travel_to("river") and not fixture.home._player_can_act() and fixture.home._automatic_player_motion(), "travel/short actions and native projection respect original body ownership")
	GameClock.advance_msec(1234)
	var path: String = "user://tests/personal_production_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "normal joint save captures underway materials and fractional route")
	GameClock.advance_msec(480000)
	var future: String = _canonical(runtime)
	runner.assert_eq(runtime.player_inventory().quantity(id, "dried_herb"), 2, "completed product stays at its physical worksite")
	runner.assert_true(panel.batch_choice.item_count == 1 and panel._batch_note.text.contains("现场"), "production page explains that finished goods still need handling")
	runner.assert_eq(runtime.load_game(path), OK, "normal loader reconstructs the original active production route")
	GameClock.advance_msec(480000)
	runner.assert_eq(_canonical(runtime), future, "ordinary session file resumes the identical entire world")
	domain = runtime.world_sim.personal_production
	runner.assert_true(runtime.travel_to("river"), "finished work frees the human to leave the goods behind")
	GameClock.advance_msec(120000)
	runner.assert_eq(runtime.current_region, "river", "owner can actually leave before collecting")
	panel._submit("production:collect")
	runner.assert_true(domain.owns_actor("player"), "same selected batch orders a real return journey across settlements")
	runner.assert_eq(runtime.player_inventory().quantity("actor:player", "dried_herb"), 0, "remote pickup button provides no remote goods")
	GameClock.advance_msec(1000)
	runtime.stop_player_action()
	runner.assert_true(not domain.owns_actor("player") and domain.batches[id].state == "ready", "manual stop keeps the finished batch at its original site")
	panel._submit("production:collect")
	GameClock.advance_msec(180000)
	runner.assert_eq(runtime.player_inventory().quantity("actor:player", "dried_herb"), 2, "actual return and handling put original output into the one bag")
	runner.assert_eq(domain.batches[id].state, "collected", "finished pickup remains terminal")
	# Working snapshot validation checks the adapter's short-action/motion as
	# well as the domain-owned route and the original inventory.
	runtime.player_inventory().containers["actor:player"].merge({"wood": 1, "herb": 2}, true)
	panel._submit("production:new:dry_herbs")
	GameClock.advance_msec(1000)
	var state: Dictionary = WorldSessionSnapshot.capture(runtime)
	var before: String = _canonical(runtime)
	var bad: Dictionary = state.duplicate(true)
	bad.player.motion.velocity = [1.0, 0.0]
	runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "joint candidate rejects simultaneous free velocity and process travel")
	runner.assert_eq(_canonical(runtime), before, "bad joint candidate cannot partly replace the body or its batch")
	panel.batch_choice.select(1)
	panel.batch_selected.emit()
	var deadline: int = int(domain.active.player.due_ms)
	GameClock.advance_msec(deadline - GameClock.elapsed_ms - 1)
	runner.assert_true(panel._collect_batch.disabled, "unfinished production keeps collection unavailable")
	GameClock.advance_msec(2)
	runner.assert_true(not panel._collect_batch.disabled and panel._batch_note.text.contains("现场"), "fractional completion refreshes collection without waiting for a minute notification")
	runtime.stop_player_action()
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	fixtures._dispose(fixture)
	_old_archive(runner)
	_actual_archive(runner)
	print("SCENARIO production UI: one page/body/bag, physical distant pickup, normal joint persistence and explicit empty v24 migration")


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _old_archive(runner: Object) -> void:
	# Old archives lack causal field history; current behavior is tested above.
	load("res://tests/runtime/helpers/legacy_rejection_archive.gd").run(runner, {
		"res://tests/fixtures/session_v24.json": ""
	})


func _actual_archive(runner: Object) -> void:
	# Old archives lack causal field history; current behavior is tested above.
	load("res://tests/runtime/helpers/legacy_rejection_archive.gd").run(runner, {
		"res://tests/fixtures/session_v25.json": ""
	})
