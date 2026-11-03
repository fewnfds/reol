extends RefCounted
## Services use the same player, terrain route and world clock as ordinary travel.

const ContinuityFixture = preload("res://tests/runtime/test_world_continuity_runtime.gd")

var _fixtures: RefCounted = ContinuityFixture.new()


func run(runner: Object) -> void:
	_test_visitor_services_share_player_and_clock(runner)
	_test_service_snapshot_and_manual_cancel(runner)
	_test_labor_to_food_without_coins(runner)


func _arrive_river(fixture: Dictionary, runner: Object) -> bool:
	var runtime: WorldContinuityRuntime = fixture.continuity
	if not runtime.travel_to("river"):
		runner.assert_true(false, "service fixture can travel to river")
		return false
	var limit: int = GameClock.tick_index + 300
	while not runtime.player_journey.is_empty() and GameClock.tick_index < limit:
		GameClock.advance_ticks(1)
	runner.assert_eq(runtime.current_region, "river", "visitor reaches the region before requesting local services")
	return runtime.current_region == "river"


func _finish_service(runtime: WorldContinuityRuntime, runner: Object) -> void:
	var limit: int = GameClock.elapsed_ms + 120 * 600000
	while runtime.world_sim.services.owns_actor("player") and GameClock.tick_index < limit:
		GameClock.advance_ticks(1)
	runner.assert_true(not runtime.world_sim.services.owns_actor("player"), "runtime service completes or reports failure within its action budget")


func _finish_labor(runtime: WorldContinuityRuntime, runner: Object) -> void:
	var limit: int = GameClock.tick_index + 300
	while not runtime._home.simulation.actors.player.active.is_empty() and GameClock.tick_index < limit:
		GameClock.advance_ticks(1)
	runner.assert_true(runtime._home.simulation.actors.player.active.is_empty(), "native labor reaches an end without a second body or clock")


func _test_labor_to_food_without_coins(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var sim: VillageSimulation = fixture.home.simulation
	# Isolate the player's contribution from other residents' successful work.
	for id: String in sim.actors:
		sim.cancel_action(id, "scenario_setup")
		sim.actors[id].autonomous = false
	sim.inventory.containers["actor:player"]["coin"] = 0
	runtime.world_sim.invalidate_region("home")
	var initial_wood: int = sim.inventory.quantity("kitchen", "wood")
	runner.assert_true(bool(runtime.submit_service("work:deliver_wood").ok), "labor page starts a real native hauling action")
	var action_before: String = str(sim.actors.player.active.id)
	runner.assert_true(not bool(runtime.submit_service("work:cook").ok), "another work click cannot steal an occupied body")
	runner.assert_eq(str(sim.actors.player.active.id), action_before, "refused work preserves the original executor")
	runner.assert_true(not bool(runtime.submit_service("work:eat").ok), "native command namespace cannot bypass paid visitor services")
	runner.assert_true(runtime.service_adapter.panel._activity.text.contains("柴") or runtime.service_adapter.panel._activity.text.contains("库房"), "native work replaces stale service outcome in the activity view")
	GameClock.advance_ticks(4)
	var path: String = "user://tests/labor_loop_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "labor is saved through the same joint snapshot as visitor jobs")
	_finish_labor(runtime, runner)
	var expected: Variant = _normal(runtime.world_sim.to_dict())
	var finish_tick: int = GameClock.tick_index
	runner.assert_eq(runtime.load_game(path), OK, "unfinished native labor restores from joint snapshot")
	_finish_labor(runtime, runner)
	runner.assert_eq(GameClock.tick_index, finish_tick, "restored labor needs the same remaining shared time")
	runner.assert_true(_normal(runtime.world_sim.to_dict()) == expected, "restored labor produces identical resources, knowledge and receipts")
	sim = runtime._home.simulation
	runner.assert_eq(sim.inventory.quantity("kitchen", "wood"), initial_wood + 3, "wood is actually moved into the kitchen")
	runner.assert_eq(sim.institutions.balance("sect", "player"), 0, "unreported work is not yet formal contribution")
	runner.assert_eq(sim.actors.player.receipts.size(), 1, "completed labor leaves one evidence receipt")
	runner.assert_true(bool(runtime.submit_service("work:report").ok), "player walks to register the native work evidence")
	_finish_labor(runtime, runner)
	runner.assert_eq(sim.institutions.balance("sect", "player"), 2, "registration posts real institution credit once")
	runner.assert_true(sim.actors.player.receipts.is_empty(), "registered receipt cannot be reported again")
	runner.assert_true(bool(runtime.submit_service("redeem").ok), "labor credit can be exchanged for an actual stocked meal")
	_finish_service(runtime, runner)
	runner.assert_eq(sim.inventory.quantity("actor:player", "meal"), 1, "redemption puts the actual meal in the original inventory")
	runner.assert_eq(sim.institutions.balance("sect", "player"), 1, "meal redemption debits institution credit")
	var hunger: float = float(sim.actors.player.hunger)
	runner.assert_true(bool(runtime.submit_service("eat").ok), "a penniless laborer can eat their own redeemed meal")
	_finish_service(runtime, runner)
	runner.assert_eq(sim.inventory.quantity("actor:player", "meal"), 0, "eating consumes exactly one real carried meal")
	runner.assert_eq(sim.inventory.quantity("actor:player", "coin"), 0, "the labor-to-food path creates and spends no phantom money")
	runner.assert_true(float(sim.actors.player.hunger) > hunger, "eating changes the same body's need")
	print("SCENARIO livelihood: labor→evidence→registration→stocked meal→food with zero starting coins")
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	_fixtures._dispose(fixture)


func _normal(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true, true))


func _test_visitor_services_share_player_and_clock(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var player: PlayerCharacter = fixture.player
	var body: Dictionary = runtime.world_sim.regions.home.actors.player
	var travel: Dictionary = runtime.submit_service("eat")
	runner.assert_true(bool(travel.get("ok", false)), "services are available from the current settlement")
	runner.assert_true(not runtime.travel_to("river"), "new travel cannot steal execution from an active service")
	runtime.submit_service("cancel")
	if not _arrive_river(fixture, runner):
		_fixtures._dispose(fixture)
		return
	var region_actors: Array = runtime.world_sim.regions.river.actors.keys()
	body.hunger = 20.0
	body.energy = 15.0
	var old_position: Vector2i = player.cell
	var coins: int = runtime.world_sim.regions.home.inventory.quantity("actor:player", "coin")
	var result: Dictionary = runtime.submit_service("eat")
	runner.assert_true(bool(result.get("ok", false)), "runtime submits visitor eating to the current river facilities")
	runner.assert_eq(player.cell, old_position, "food button creates a route instead of instantly moving the player")
	runner.assert_true(not runtime.travel_to("home"), "travel input respects the active service owner")
	_finish_service(runtime, runner)
	runner.assert_true(float(body.hunger) > 20.0, "river food affects the original persistent player body")
	runner.assert_true(runtime.world_sim.regions.home.inventory.quantity("actor:player", "coin") < coins, "visitor food charges the player's actual purse")
	runner.assert_eq(runtime.world_sim.regions.river.actors.keys(), region_actors, "eating while visiting does not spawn another player")
	var food_position: Array = runtime.world_sim.regions.river.places.kitchen.cell
	runner.assert_eq(player.cell, Vector2i(int(food_position[0]), int(food_position[1])), "runtime view follows the service route all the way to the kitchen")
	var started: int = GameClock.tick_index
	runner.assert_true(bool(runtime.submit_service("rest").get("ok", false)), "river offers a real visitor rest action")
	_finish_service(runtime, runner)
	runner.assert_true(GameClock.tick_index - started >= 60, "local lodging consumes world time")
	runner.assert_true(float(body.energy) > 15.0, "local lodging restores the same player body")
	print("SCENARIO playable services: travelled to river, ate at kitchen and rested at local lodging")
	_fixtures._dispose(fixture)


func _test_service_snapshot_and_manual_cancel(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	if not _arrive_river(fixture, runner):
		_fixtures._dispose(fixture)
		return
	runner.assert_true(bool(runtime.submit_service("rest").get("ok", false)), "save fixture begins an owned visitor service")
	GameClock.advance_ticks(7)
	var path: String = "user://tests/settlement_service_%d.json" % Time.get_ticks_usec()
	var before: String = JSON.stringify(_normal(runtime.world_sim.to_dict()), "", true, true)
	var before_position: Vector2 = fixture.player.global_position
	runner.assert_eq(runtime.save_game(path), OK, "joint save retains the visitor service route and transaction")
	var valid_snapshot: Dictionary = SimSaveStore.load_file(path).data
	var double_owner: Dictionary = valid_snapshot.duplicate(true)
	var route: Array[Vector2i] = runtime._find_path(fixture.player.cell, runtime.centers.home)
	var encoded_route: Array = []
	for cell: Vector2i in route:
		if cell != fixture.player.cell:
			encoded_route.append([cell.x, cell.y])
	runner.assert_true(not encoded_route.is_empty(), "dual-owner fixture contains a separately legal player journey")
	double_owner.continuity.player_journey = {"destination": "home", "path": encoded_route, "remaining": int(fixture.home._config.move_minutes_per_cell)}
	runner.assert_eq(SimSaveStore.save_file(path, double_owner), OK, "dual-owner snapshot remains valid serialized data")
	runner.assert_true(runtime.load_game(path) != OK, "a visitor service and a second player travel executor cannot own the same saved actor")
	runner.assert_true(JSON.stringify(_normal(runtime.world_sim.to_dict()), "", true, true) == before, "rejecting dual execution preserves the current service and world")
	runner.assert_eq(SimSaveStore.save_file(path, valid_snapshot), OK, "valid service snapshot is retained for continuation checks")
	GameClock.advance_ticks(120)
	var continued: String = JSON.stringify(_normal(runtime.world_sim.to_dict()), "", true, true)
	var focus_updates: Array[Vector2] = []
	runtime.player_travel_advanced.connect(func(value: Vector2) -> void: focus_updates.append(value))
	runner.assert_eq(runtime.load_game(path), OK, "joint load restores the active visitor service")
	runner.assert_true(not focus_updates.is_empty() and focus_updates.back() == before_position, "loading away from spawn restores the camera focus to the saved player")
	runner.assert_true(JSON.stringify(_normal(runtime.world_sim.to_dict()), "", true, true) == before, "load restores original service progress, world state and pending effects")
	runner.assert_eq(fixture.player.global_position, before_position, "load restores the exact service travel position")
	GameClock.advance_ticks(120)
	runner.assert_true(JSON.stringify(_normal(runtime.world_sim.to_dict()), "", true, true) == continued, "loaded service continues identically with autonomous inhabitants")
	runtime.submit_service("rest")
	GameClock.advance_ticks(2)
	runtime.cancel_travel()
	fixture.home.cancel_player_action()
	runner.assert_true(not runtime.world_sim.services.owns_actor("player"), "manual movement cancellation releases service ownership")
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		var file: String = ProjectSettings.globalize_path(path + suffix)
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	print("SCENARIO service persistence: visitor work resumes after load and manual override cancels ownership")
	_fixtures._dispose(fixture)
