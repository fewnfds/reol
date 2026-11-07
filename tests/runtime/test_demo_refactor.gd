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
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	if location == "river" and not _arrive_river(fixture, runner):
		_fixtures._dispose(fixture)
		return
	var far: String = "home" if location == "river" else "river"
	var live_world: RegionalSimulation = runtime.world_sim
	var quiet: VillageSimulation = live_world.regions[far]
	var start_ms: int = GameClock.elapsed_ms
	# A far region may have already been synchronized by a normal environmental
	# or object boundary. Capture must serialize both regions at the committed
	# instant regardless, without advancing the shared clock to do so.
	GameClock.advance_msec(1234)
	var committed_ms: int = GameClock.elapsed_ms
	var clock_before: Dictionary = GameClock.to_dict()
	runner.assert_eq(committed_ms, start_ms + 1234, "%s fixture advances a real subminute interval" % location)
	runner.assert_true(not GameClock.has_pending_advance(), "%s fixture reaches a completed clock boundary" % location)
	runner.assert_eq(live_world.elapsed_ms, committed_ms, "%s world and clock share the committed millisecond" % location)
	runner.assert_eq(live_world.target_ms, committed_ms, "%s world has no uncommitted time at capture" % location)
	runner.assert_true(quiet.elapsed_ms <= committed_ms, "%s far region never leads the shared clock" % location)
	runner.assert_eq(runtime.current_region, location, "%s remains the active runtime region" % location)
	runner.assert_eq(live_world.active_region, location, "%s remains the active simulation region" % location)
	var snapshot: Dictionary = SessionSnapshot.capture(runtime)
	runner.assert_true(not snapshot.is_empty(), "%s session capture succeeds" % location)
	if snapshot.is_empty():
		_fixtures._dispose(fixture)
		return
	runner.assert_eq(GameClock.to_dict(), clock_before, "%s capture does not advance or alter the shared clock" % location)
	runner.assert_eq(live_world.elapsed_ms, committed_ms, "%s capture does not advance world time" % location)
	runner.assert_eq(live_world.target_ms, committed_ms, "%s capture does not add world time debt" % location)
	runner.assert_eq(quiet.elapsed_ms, committed_ms, "%s capture synchronizes the live far region" % location)
	runner.assert_eq(_normal(snapshot.clock), _normal(clock_before), "%s serialized clock is the original commit point" % location)
	runner.assert_eq(int(snapshot.continuity.world.elapsed_ms), committed_ms, "%s serialized world keeps the original commit point" % location)
	runner.assert_eq(int(snapshot.continuity.world.target_ms), committed_ms, "%s serialized world has no added time debt" % location)
	runner.assert_eq(snapshot.continuity.world.active_region, location, "%s serialized world preserves the active region" % location)
	runner.assert_eq(int(snapshot.clock.tick_index), int(snapshot.continuity.world.current_time), "captured clock and regional commit time agree")
	for region_id: String in snapshot.continuity.world.regions:
		var region: Dictionary = snapshot.continuity.world.regions[region_id]
		runner.assert_eq(int(region.elapsed_ms), committed_ms, "%s serialized %s reaches the exact session boundary" % [location, region_id])
		runner.assert_eq(int(region.tick_index), int(snapshot.clock.tick_index), "every serialized region reaches the same session minute")
		runner.assert_eq(_normal(region), _normal(live_world.regions[region_id].to_dict()), "%s serialized %s preserves its live body and books" % [location, region_id])
	runner.assert_eq(_normal(snapshot.simulation), _normal(snapshot.continuity.world.regions.home), "home snapshot and regional home are the same committed body and books")
	var before: String = _state(runtime)
	var before_position: Vector2 = fixture.player.global_position
	var live_map: WorldMapData = live_world.map_data
	var staged: Dictionary = SessionSnapshot.stage(runtime, _normal(snapshot))
	runner.assert_true(not staged.is_empty(), "extracted session validator accepts a coherent %s snapshot" % location)
	runner.assert_true(_state(runtime) == before, "candidate validation does not mutate the live causal world")
	runner.assert_eq(GameClock.to_dict(), clock_before, "candidate validation does not alter the shared clock")
	runner.assert_true(runtime.world_sim == live_world and runtime.world_sim.map_data == live_map and runtime.world_sim.regions[far] == quiet, "candidate validation keeps the live world, map and far-region owners")
	if not staged.is_empty():
		runner.assert_true(staged.world != live_world and staged.world.regions.home != live_world.regions.home and staged.world.regions[far] != quiet and staged.map != live_map, "staged restore owns an independent world, map and region containers")
	var path: String = "user://tests/demo_refactor_%s_%d.json" % [location, Time.get_ticks_usec()]
	var saved: Error = runtime.save_game(path)
	runner.assert_eq(saved, OK, "ordinary save writes the captured %s session" % location)
	if saved != OK:
		_remove_test_save(path)
		_fixtures._dispose(fixture)
		return
	runner.assert_eq(GameClock.to_dict(), clock_before, "ordinary save does not advance the shared clock")
	runner.assert_true(_state(runtime) == before, "ordinary save keeps the committed world state")
	GameClock.advance_ticks(73)
	runner.assert_eq(GameClock.elapsed_ms, committed_ms + 73 * 60000, "original continuation commits all 73 requested minutes")
	runner.assert_true(not GameClock.has_pending_advance(), "original continuation leaves no uncommitted time")
	var expected: String = _state(runtime)
	var expected_clock: Dictionary = GameClock.to_dict()
	var expected_position: Vector2 = fixture.player.global_position
	runner.assert_eq(runtime.load_game(path), OK, "extracted snapshot loads at %s" % location)
	runner.assert_true(_state(runtime) == before, "load restores the exact pre-continuation regional state")
	runner.assert_eq(GameClock.to_dict(), clock_before, "load restores the original shared clock")
	runner.assert_eq(runtime.current_region, location, "load restores the active runtime region")
	runner.assert_eq(runtime.world_sim.active_region, location, "load restores the active simulation region")
	runner.assert_eq(fixture.player.global_position, before_position, "load restores the saved player position")
	GameClock.advance_ticks(73)
	runner.assert_true(not GameClock.has_pending_advance(), "restored continuation leaves no uncommitted time")
	runner.assert_true(_state(runtime) == expected, "snapshot extraction preserves the same future facts, resources and RNG at %s" % location)
	runner.assert_eq(GameClock.to_dict(), expected_clock, "snapshot extraction preserves the same future shared clock")
	runner.assert_eq(fixture.player.global_position, expected_position, "snapshot refactor preserves the same player position")
	_remove_test_save(path)
	_fixtures._dispose(fixture)


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
