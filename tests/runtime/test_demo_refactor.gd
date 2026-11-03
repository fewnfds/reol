extends RefCounted
## Regression checks for the extracted session boundary and recovered UI intents.

const ContinuityFixture = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const SessionSnapshot = preload("res://scripts/runtime/world_session_snapshot.gd")

var _fixtures: RefCounted = ContinuityFixture.new()


func run(runner: Object) -> void:
	_test_snapshot_boundary(runner, "home")
	_test_snapshot_boundary(runner, "river")
	_test_selected_resident_help(runner)
	_test_remote_selection(runner)
	_test_service_result_notice(runner)
	_test_service_pages_route_intentions(runner)
	_test_local_information_intentions(runner)


func _arrive_river(fixture: Dictionary, runner: Object) -> bool:
	var runtime: WorldContinuityRuntime = fixture.continuity
	if not runtime.travel_to("river"):
		runner.assert_true(false, "refactor fixture has a connected visitor route")
		return false
	var stop: int = GameClock.tick_index + 300
	while not runtime.player_journey.is_empty() and GameClock.tick_index < stop:
		GameClock.advance_ticks(1)
	runner.assert_eq(runtime.current_region, "river", "visitor reaches river before the regression scenario")
	return runtime.current_region == "river"


func _test_snapshot_boundary(runner: Object, location: String) -> void:
	var fixture: Dictionary = _lazy_region_fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	if location == "river" and not _arrive_river(fixture, runner):
		_fixtures._dispose(fixture)
		return
	var far: String = "home" if location == "river" else "river"
	var quiet: VillageSimulation = runtime.world_sim.regions[far]
	# A quiet far region may legally lag the committed global time. Capture must
	# settle it before serializing the duplicate home/session representations.
	for actor_id: String in quiet.actors:
		quiet.cancel_action(actor_id, "fixture_quiet_interval")
		# The remote settlement's controlled resident is an autonomous NPC, unlike
		# the visitor player. Preserve that persisted controller invariant.
		if actor_id != quiet.controlled_actor:
			quiet.actors[actor_id].autonomous = false
		quiet.actors[actor_id].retry_ms = GameClock.elapsed_ms + 120 * 60000
	runtime.world_sim.invalidate_region(far)
	var limit: int = GameClock.tick_index + 20
	while quiet.tick_index == runtime.world_sim.current_time and GameClock.tick_index < limit:
		GameClock.advance_ticks(1)
	runner.assert_true(quiet.tick_index < runtime.world_sim.current_time, "%s snapshot fixture actually contains a lazy far region" % location)
	var snapshot: Dictionary = SessionSnapshot.capture(runtime)
	runner.assert_eq(int(snapshot.clock.tick_index), int(snapshot.continuity.world.current_time), "captured clock and regional commit time agree")
	for region: Dictionary in snapshot.continuity.world.regions.values():
		runner.assert_eq(int(region.tick_index), int(snapshot.clock.tick_index), "every serialized region reaches the same session boundary")
	runner.assert_eq(_normal(snapshot.simulation), _normal(snapshot.continuity.world.regions.home), "home snapshot and regional home are the same committed body and books")
	var before: String = _state(runtime)
	var staged: Dictionary = SessionSnapshot.stage(runtime, _normal(snapshot))
	runner.assert_true(not staged.is_empty(), "extracted session validator accepts a coherent %s snapshot" % location)
	runner.assert_true(_state(runtime) == before, "candidate validation does not mutate the live causal world")
	if not staged.is_empty():
		runner.assert_true(staged.world != runtime.world_sim and staged.world.regions.home != runtime.world_sim.regions.home, "staged restore owns independent world and actor containers")
	var path: String = "user://tests/demo_refactor_%s_%d.json" % [location, Time.get_ticks_usec()]
	runner.assert_eq(SimSaveStore.save_file(path, snapshot), OK, "captured session writes as an ordinary JSON snapshot")
	GameClock.advance_ticks(73)
	var expected: String = _state(runtime)
	var expected_position: Vector2 = fixture.player.global_position
	runner.assert_eq(runtime.load_game(path), OK, "extracted snapshot loads at %s" % location)
	runner.assert_true(_state(runtime) == before, "load restores the exact pre-continuation regional state")
	GameClock.advance_ticks(73)
	runner.assert_true(_state(runtime) == expected, "snapshot extraction preserves the same future facts, resources and RNG at %s" % location)
	runner.assert_eq(fixture.player.global_position, expected_position, "snapshot refactor preserves the same player position")
	_remove_test_save(path)
	_fixtures._dispose(fixture)


func _lazy_region_fixture(runner: Object) -> Dictionary:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return fixture
	var runtime: WorldContinuityRuntime = fixture.continuity
	runner.assert_eq(runtime.world_sim.elapsed_ms, 0, "lazy-region performance fixture changes only its explicit opening rules")
	# This regression exercises a region with no continuously sampled plants.
	# E3's normal herb patches intentionally wake their region each minute;
	# keep that behavior in every ordinary fixture and all other tests here.
	var rules: Dictionary = fixture.home._content.land_resources.duplicate(true)
	rules.types.wild_herbs.erase("ecology")
	fixture.home._content.land_resources = rules
	fixture.home._config.actions.erase("irrigate_herb")
	for region: String in runtime.world_sim.regions:
		var sim: VillageSimulation = runtime.world_sim.regions[region]
		sim.config.actions.erase("irrigate_herb")
		runtime.world_sim.opening_config(region).actions.erase("irrigate_herb")
		sim.land_resources.definitions = rules
		for id: String in sim.land_resources.sources:
			var state: Dictionary = sim.land_resources.sources[id]
			var terms: Dictionary = sim.land_resources.terms_for(id)
			state.ecology = {}
			state.next_growth_ms = int(terms.regrow_ms)
		runner.assert_true(SimLandResources.valid_state(sim.land_resources.to_dict(), sim.config, sim.places, sim.inventory, 0, rules), "explicit unsampled-source fixture remains a valid opening: " + region)
		runner.assert_eq(sim.land_resources.next_ecology_sample_ms(), SimInventory.MAX_COUNT, "no managed plant schedules environmental wakeups in the lazy-region fixture: " + region)
		runtime.world_sim.invalidate_region(region)
	return fixture


func _test_selected_resident_help(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var home: VillageRuntime = fixture.home
	var sim: VillageSimulation = home.simulation
	runner.assert_true(not bool(runtime.selected_interaction().enabled), "player selection does not pretend to be an NPC help target")
	home.select_actor("shi_tou")
	runner.assert_true(bool(runtime.selected_interaction().enabled), "a visible selected local resident exposes the recovered help intention")
	sim.cancel_action("shi_tou", "fixture_available_helper")
	sim.actors.shi_tou.autonomous = false
	sim.actors.shi_tou.energy = 100.0
	sim.set_actor_cell("shi_tou", SimRouteTravel.cell([80, 80]))
	runtime.world_sim.invalidate_region("home")
	var refused: Dictionary = runtime.request_selected_help()
	runner.assert_eq(refused.get("reason"), "out_of_range", "selected help routes through real social proximity checks")
	runner.assert_true(sim.actors.shi_tou.active.is_empty(), "a rejected help request creates no fake work")
	sim.set_actor_cell("shi_tou", SimRouteTravel.cell(sim.actors.player.cell.duplicate()))
	var task: String = str(sim.config.scenario.task)
	var source: String = str(sim.config.actions[task].source)
	var item: String = str(sim.config.actions[task].item)
	var source_before: int = sim.inventory.quantity(source, item)
	var accepted: Dictionary = runtime.request_selected_help()
	runner.assert_eq(accepted.get("status"), "accepted", "available nearby helper weighs and accepts the real hauling request")
	runner.assert_true(not sim.actors.shi_tou.active.is_empty(), "accepted selection help starts the existing NPC executor")
	if not sim.actors.shi_tou.active.is_empty():
		runner.assert_eq(sim.actors.shi_tou.active.action, task, "help starts the configured work rather than an unrelated action")
		runner.assert_eq(sim.actors.shi_tou.active.request_id, accepted.get("id"), "NPC execution retains the exact social promise ID")
	runner.assert_eq(sim.inventory.quantity(source, item), source_before, "asking for help reserves work without teleporting source stock")
	_fixtures._dispose(fixture)


func _test_remote_selection(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	if not _arrive_river(fixture, runner):
		_fixtures._dispose(fixture)
		return
	var selected: Array[Pawn] = []
	runtime.resident_selected.connect(func(pawn: Pawn) -> void: selected.append(pawn))
	var resident: Pawn = runtime._remote_views.river_lao_zhou
	# Isolate the target from legitimate crowded work sites: this test verifies
	# selection routing, rather than imposing an unimplemented overlap policy.
	for other: Pawn in runtime._remote_views.values():
		other.visible = other == resident
	runner.assert_true(runtime.select_remote_at(resident.selection_center()), "clicking a nearby river resident selects the existing instance")
	runner.assert_eq(selected.size(), 1, "one click emits exactly one resident selection intention")
	if not selected.is_empty():
		runner.assert_true(selected[0] == resident, "selection sends the original river Pawn to the main HUD route")
		runner.assert_eq(selected[0].pawn_id, &"river_lao_zhou", "selection retains the stable foreign resident ID")
		runner.assert_eq(selected[0].display_name_override, str(runtime.settings.runtime.remote_names.river_lao_zhou), "HUD selection receives the river instance name instead of its reused home definition name")
	runner.assert_true(resident.selected, "selected river resident visibly owns selection")
	runtime.clear_remote_selection()
	runner.assert_true(not resident.selected and runtime._selected_remote.is_empty(), "returning to player selection clears the remote highlight and target")
	runner.assert_true(not runtime.select_remote_at(fixture.player.selection_center()), "a nearby resident does not steal a click closer to the player")
	_fixtures._dispose(fixture)


func _test_service_result_notice(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var started: Dictionary = runtime.submit_service("eat")
	runner.assert_true(bool(started.get("ok", false)), "notice fixture starts a real timed service")
	var limit: int = GameClock.tick_index + 200
	while runtime.world_sim.services.owns_actor("player") and GameClock.tick_index < limit:
		GameClock.advance_ticks(1)
	var status: Dictionary = runtime.world_sim.services.status("player")
	runner.assert_eq(status.get("status"), "completed", "notice fixture physically finishes eating")
	var actual_notice: String = runtime.service_adapter.panel._notice.text
	runner.assert_eq(actual_notice, str(status.get("outcome")), "completed service displays its actual outcome instead of the stale started message")
	runner.assert_true(actual_notice != str(started.get("line")), "completion replaces the original acknowledgement")
	var path: String = "user://tests/demo_service_restart_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "save at the completed service facility")
	runner.assert_eq(runtime.load_game(path), OK, "load while standing at that same facility")
	var coins: int = runtime.player_inventory().quantity("actor:player", "coin")
	var again: Dictionary = runtime.submit_service("eat")
	runner.assert_true(bool(again.get("ok", false)), "JSON float coordinates and integer view coordinates name the same service cell")
	GameClock.advance_ticks(20)
	runner.assert_eq(runtime.world_sim.services.status("player").get("status"), "completed", "a new service can finish at a loaded facility without walking away first")
	runner.assert_eq(runtime.player_inventory().quantity("actor:player", "coin"), coins - int(runtime.world_sim.services.definitions.visitor.eat.fee), "restarted service charges exactly one real meal")
	_remove_test_save(path)
	var rejected: Dictionary = runtime.submit_service("missing_demo_action")
	runner.assert_true(not bool(rejected.get("ok", false)), "a later invalid intention is rejected by the rules")
	runtime.service_adapter.refresh()
	runner.assert_eq(runtime.service_adapter.panel._notice.text, str(rejected.get("line")), "refresh does not overwrite a newer refusal with an old completed service")
	_fixtures._dispose(fixture)


func _test_service_pages_route_intentions(runner: Object) -> void:
	var panel := SettlementServicesPanel.new()
	var actions: Array[String] = []
	panel.service_requested.connect(func(action_id: String) -> void: actions.append(action_id))
	runner.assert_true(panel._pages[0].visible and not panel._pages[1].visible and not panel._pages[2].visible, "service menu opens to one focused life page")
	panel._tabs[1].pressed.emit()
	var report: Button
	for button: Button in panel._local_buttons:
		if button.get_meta("service_action") == "report":
			report = button
	runner.assert_true(panel._pages[1].visible and not panel._pages[0].visible, "changing pages exposes work and credential intentions")
	if report != null:
		report.pressed.emit()
	runner.assert_eq(actions, ["report"], "grouped menu emits the original service API intention exactly once")
	panel._tabs[3].pressed.emit()
	var work: Button
	for button: Button in panel._local_buttons:
		if button.get_meta("service_action") == "work:deliver_wood":
			work = button
	runner.assert_true(panel._pages[3].visible and not panel._pages[1].visible, "labor has its own visible page")
	if work != null:
		work.pressed.emit()
		runner.assert_eq(actions, ["report", "work:deliver_wood"], "labor emits one explicit native work intention")
		panel.set_home_work_available(false)
		runner.assert_true(work.disabled, "home-only labor is disabled while away")
	panel.free()


func _test_local_information_intentions(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var home: VillageRuntime = fixture.home
	fixture.player.spawn_at(Vector2i(38, 30))
	# The start-of-game inspection really happened; let it age while the player
	# stays away, rather than erasing genuine knowledge to manufacture the test.
	GameClock.advance_ticks(121)
	home.select_actor("chen_shouzhuo")
	var panel: SettlementServicesPanel = runtime.service_adapter.panel
	panel._tabs[4].pressed.emit()
	runner.assert_true(panel._pages[4].visible, "conversation page is a real reachable control")
	runner.assert_true(not bool(home.simulation.stock_understanding("player", "kitchen", "wood").known), "player has no direct vision of the distant kitchen in the runtime scenario")
	for button: Button in panel._local_buttons:
		if button.get_meta("service_action") == "talk:ask":
			button.pressed.emit()
	var understanding: Dictionary = home.simulation.stock_understanding("player", "kitchen", "wood")
	runner.assert_true(bool(understanding.known), "asking through the actual button obtains an attributed report")
	runner.assert_eq(understanding.source, "chen_shouzhuo", "the runtime preserves the informant instead of exposing raw stock")
	runner.assert_eq(understanding.basis, "said", "player information display distinguishes hearing from seeing")
	runner.assert_true(panel._details.text.contains("陈守拙说"), "visible summary names the source of this belief")
	var path: String = "user://tests/local_information_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "new information is included in the ordinary joint snapshot")
	var stock: Dictionary = home.simulation.inventory.containers.kitchen.duplicate(true)
	runner.assert_true(bool(runtime.submit_service("talk:supplied").ok), "player can make a claim independently of actual stock")
	runner.assert_eq(home.simulation.inventory.containers.kitchen, stock, "runtime speech cannot mint supplies")
	GameClock.advance_ticks(15)
	runner.assert_eq(runtime.load_game(path), OK, "joint load restores the previous information boundary")
	runner.assert_eq(home.simulation.stock_understanding("player", "kitchen", "wood"), understanding, "informant and expectation survive restoration exactly")
	panel.set_home_work_available(false)
	for button: Button in panel._local_buttons:
		if str(button.get_meta("service_action", "")).begins_with("talk:"):
			runner.assert_true(button.disabled, "home conversation controls are disabled while away")
	_remove_test_save(path)
	_fixtures._dispose(fixture)


func _normal(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true, true))


func _state(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(_normal(runtime.world_sim.to_dict()), "", true, true)


func _remove_test_save(path: String) -> void:
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		var target: String = ProjectSettings.globalize_path(path + suffix)
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)
