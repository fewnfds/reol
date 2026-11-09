extends RefCounted
## The real gathering page uses original private water, timed labor and sight.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


class ControlledFog extends FogOfWar:
	var source_visible: bool = true


	func is_cell_visible(_cell: Vector2i) -> bool:
		return source_visible


	func is_explored(_cell: Vector2i) -> bool:
		return true


func run(runner: Object) -> void:
	_test_actual_private_water_and_timed_care(runner)
	_test_observation_and_presentation_are_local_and_read_only(runner)
	_test_missing_action_and_original_body_control(runner)


func _quiet_fixture(runner: Object) -> Dictionary:
	var fixture: Dictionary = Fixtures.new()._fixture(runner)
	if fixture.is_empty():
		return fixture
	for region: String in fixture.continuity.world_sim.regions:
		var sim: VillageSimulation = fixture.continuity.world_sim.regions[region]
		for actor: String in sim.actors:
			sim.cancel_action(actor, "fixture_setup")
			sim.actors[actor].autonomous = false
		fixture.continuity.world_sim.invalidate_region(region)
	return fixture


func _care_button(panel: SettlementServicesPanel) -> Button:
	for button: Button in panel._local_buttons:
		if button.get_meta("service_action", "") == "work:irrigate_herb":
			return button
	return null


func _test_actual_private_water_and_timed_care(runner: Object) -> void:
	var fixture: Dictionary = _quiet_fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var sim: VillageSimulation = runtime.world_sim.regions.home
	var panel: SettlementServicesPanel = runtime.service_adapter.panel
	panel._select_page(5)
	panel.personal_gather.button_pressed = true
	var button: Button = _care_button(panel)
	runner.assert_true(button != null and not button.disabled, "original gathering page offers care without converting it into personal harvesting")
	if button == null:
		Fixtures.new()._dispose(fixture)
		return
	var before_source: String = JSON.stringify(sim.land_resources.to_dict(), "", true, true)
	button.pressed.emit()
	runner.assert_true(sim.actors.player.active.is_empty(), "a care click cannot use public well stock when the player carries no private water")
	runner.assert_eq(sim.inventory.quantity("actor:player", "water"), 0, "failed care creates no carried water")
	runner.assert_eq(JSON.stringify(sim.land_resources.to_dict(), "", true, true), before_source, "unfunded care cannot alter soil or mature herbs")
	runner.assert_true(not panel._notice.text.contains("功德堂"), "failed care does not suggest a public report reward")
	runner.assert_true(bool(runtime.start_home_work("keep_water").ok), "the same original actor can actually draw personal water from the finite spring")
	GameClock.advance_msec(650000)
	runner.assert_true(sim.actors.player.active.is_empty(), "personal water gathering completes its original travel and ten-minute labor")
	var carried_water: int = sim.inventory.quantity("actor:player", "water")
	runner.assert_eq(carried_water, 12, "real personal gathering puts the finite batch in the original bag")
	var plants: SimPlants = runtime.world_sim.plants
	var plant_id: String = str(sim.land_resources.sources.herb_slope.plant_id)
	var water_before: int = plants._water(plants.bodies[plant_id])
	var balance: int = sim.institutions.balance(str(sim.config.institution.id), "player")
	button.pressed.emit()
	runner.assert_eq(plants.active.get("player", {}).get("kind", ""), "water", "the original page routes delegated care to the common plant action")
	var cancelled_id: String = str(plants.active.get("player", {}).get("id", ""))
	runner.assert_eq(sim.inventory.quantity("actor:player", "water"), carried_water, "starting care reserves rather than immediately consuming the water")
	GameClock.advance_msec(1)
	runtime.service_adapter.submit("cancel")
	runner.assert_eq(sim.inventory.quantity("actor:player", "water"), carried_water, "cancelling original labor releases unspent private water")
	runner.assert_eq(plants._water(plants.bodies[plant_id]), water_before, "cancelled care adds no plant water")
	runner.assert_true(not sim.inventory.operations.has(cancelled_id + ":water"), "cancelled care leaves no completed water consumption")
	button.pressed.emit()
	runner.assert_eq(plants.active.get("player", {}).get("kind", ""), "water", "changing gathering mode never changes the care action's meaning")
	var action_id: String = str(plants.active.get("player", {}).get("id", ""))
	for _step: int in 100:
		if not plants.active.has("player"):
			break
		GameClock.advance_msec(maxi(1, plants.jobs.next_boundary_ms() - GameClock.elapsed_ms))
	runner.assert_true(not plants.active.has("player"), "care completes after its actual route and archived plant work duration")
	runner.assert_eq(sim.inventory.quantity("actor:player", "water"), carried_water - 1, "completed care consumes exactly one original private water")
	var receipt: Dictionary = plants.jobs.receipts.get(action_id, {})
	runner.assert_eq(receipt.get("result", {}).get("status", ""), "completed", "the common plant owner retains the original action receipt")
	runner.assert_true(plants._water(plants.bodies[plant_id]) > water_before, "actual private water reaches the same original plant")
	runner.assert_true(sim.inventory.operations.has(action_id + ":water"), "plant input references the original inventory consumption")
	runner.assert_eq(sim.institutions.balance(str(sim.config.institution.id), "player"), balance, "private care does not award public contribution")
	runner.assert_true(sim.actors.player.receipts.is_empty(), "care creates no reportable public-work receipt")
	runner.assert_true(panel._notice.text.contains("慢慢生长") and not panel._notice.text.contains("功德堂"), "completed care reports real tending without promising instant herbs or public rewards")
	var once: int = sim.inventory.quantity("actor:player", "water")
	GameClock.advance_msec(1)
	runner.assert_eq(sim.inventory.quantity("actor:player", "water"), once, "later presentation refresh cannot repeat completed irrigation")
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, WorldSessionSnapshot.capture(runtime)).is_empty(), "care reached through the existing page produces a loadable whole session")
	Fixtures.new()._dispose(fixture)


func _test_observation_and_presentation_are_local_and_read_only(runner: Object) -> void:
	var fixture: Dictionary = _quiet_fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var home: VillageRuntime = fixture.home
	var sim: VillageSimulation = home.simulation
	var garden: Vector2i = SimRouteTravel.cell(sim.places.garden.cell)
	sim.set_actor_cell("player", garden)
	fixture.player.spawn_at(garden)
	var fog := ControlledFog.new()
	home._fog = fog
	var before: String = JSON.stringify(sim.land_resources.to_dict(), "", true, true)
	var inventory_before: String = JSON.stringify(sim.inventory.to_dict(), "", true, true)
	var phase: String = str(runtime.world_sim.plants.observation(str(sim.land_resources.sources.herb_slope.plant_id)).phase)
	runner.assert_eq(home.herb_phase_for(sim, "garden"), phase, "nearby currently visible garden draws the source's qualitative plant phase")
	runtime.service_adapter.refresh()
	var panel: SettlementServicesPanel = runtime.service_adapter.panel
	runner.assert_true(panel._resource_note.text.contains("可采"), "the existing gathering page gives nearby observable herb information")
	fog.source_visible = false
	runner.assert_eq(home.herb_phase_for(sim, "garden"), "unknown", "exploration alone cannot expose the living plant state through fog")
	runtime.service_adapter.refresh()
	runner.assert_eq(panel._resource_note.text, "药丛近况须走近查看。", "an occluded source supplies no fresh local soil description")
	fog.source_visible = true
	sim.set_actor_cell("player", garden + Vector2i(20, 0))
	fixture.player.spawn_at(garden + Vector2i(20, 0))
	runner.assert_eq(home.herb_phase_for(sim, "garden"), "unknown", "current sight without original observation distance cannot inspect soil")
	runtime.service_adapter.refresh()
	runner.assert_true(not _care_button(panel).disabled, "remote soil truth is not revealed by disabling the care button")
	var river: VillageSimulation = runtime.world_sim.regions.river
	var river_garden: Vector2i = SimRouteTravel.cell(river.places.garden.cell)
	sim.set_actor_cell("player", river_garden)
	fixture.player.spawn_at(river_garden)
	runner.assert_eq(home.herb_phase_for(river, "garden"), str(runtime.world_sim.plants.observation(str(river.land_resources.sources.herb_slope.plant_id)).phase), "river plants use the same visible-source projection without creating another player")
	runner.assert_eq(JSON.stringify(sim.land_resources.to_dict(), "", true, true), before, "description and map projection do not advance the plant process")
	runner.assert_eq(JSON.stringify(sim.inventory.to_dict(), "", true, true), inventory_before, "reading local plant information changes no original inventory")
	home._fog = null
	fog.free()
	Fixtures.new()._dispose(fixture)


func _test_missing_action_and_original_body_control(runner: Object) -> void:
	var fixture: Dictionary = _quiet_fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var sim: VillageSimulation = fixture.home.simulation
	var panel: SettlementServicesPanel = runtime.service_adapter.panel
	var without_care: Dictionary = sim.config.duplicate(true)
	without_care.actions.erase("irrigate_herb")
	panel.set_resource_work(without_care, sim.land_resources)
	runner.assert_true(_care_button(panel).disabled, "a historical configuration without care cannot expose an actionable new button")
	runner.assert_true(bool(runtime.start_home_work("keep_water").ok), "body-control scenario first obtains real private water through the original action")
	GameClock.advance_msec(650000)
	runner.assert_eq(sim.inventory.quantity("actor:player", "water"), 12, "the control refusal is tested with sufficient genuine carried water")
	runner.assert_true(runtime.world_sim.plants.bodies.has(sim.land_resources.sources.herb_slope.plant_id), "the control refusal targets the actual delegated original plant")
	var carrier: String = runtime.world_sim.embodiment.carrier_for_source("village_actor", "player")
	var subject: String = runtime.world_sim.embodiment.subject_for_actor("player")
	runner.assert_true(runtime.world_sim.embodiment.release_control(subject, carrier, "action"), "fixture releases the original body's action channel")
	runner.assert_true(not bool(runtime.start_home_work("irrigate_herb").ok), "runtime care respects original body control rather than acting through the UI")
	runner.assert_true(sim.actors.player.active.is_empty(), "refused body control starts no second hidden action")
	runner.assert_true(runtime.world_sim.embodiment.grant_control(subject, carrier, "action"), "original body control can be restored without recreating the actor")
	Fixtures.new()._dispose(fixture)
