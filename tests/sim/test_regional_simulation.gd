extends RefCounted
## Continuous-world acceptance scenarios: time, resources, identity and knowledge.

const RegionWorld = preload("res://scripts/sim/regional_simulation.gd")


func run(runner: Object) -> void:
	_test_absent_villages_continue_living(runner)
	_test_cargo_exists_once_and_arrives_once(runner)
	_test_blocked_route_keeps_cargo_and_progress(runner)
	_test_full_destination_waits_without_losing_cargo(runner)
	_test_competing_routes_share_real_stock(runner)
	_test_earlier_cross_region_arrival_interrupts_batch(runner)
	_test_messages_do_not_make_distant_people_omniscient(runner)
	_test_switching_modes_preserves_unfinished_business(runner)
	_test_new_near_action_survives_immediate_departure(runner)
	_test_inflight_json_snapshot_continues(runner)
	_test_bad_snapshot_cannot_partly_replace_world(runner)
	_test_bounded_advancement_can_resume(runner)
	_test_coarse_execution_agrees_with_detailed_execution(runner)
	_test_one_actor_has_one_execution_owner(runner)
	_test_idempotent_sync(runner)


func _test_idempotent_sync(runner: Object) -> void:
	var world: RegionWorld = _make_world(runner)
	if world == null:
		return
	var sim: VillageSimulation = world.regions.home
	var calls: int = int(sim.simulation_work.quiet_batch_calls)
	for _read: int in 20:
		world.synchronize_region("home")
	runner.assert_eq(int(sim.simulation_work.quiet_batch_calls), calls, "already synchronized domains do not advance an empty region again")
	runner.assert_true(sim.submit_action("player", "rest"), "far command starts at the synchronized point")
	world.invalidate_region("home")
	runner.assert_true(world._dirty_region_boundaries.has("home"), "mutations retain a pending deadline refresh")
	world.advance_to_ms(50)
	runner.assert_true(not world._dirty_region_boundaries.has("home"), "scheduling consumes the refresh before advancing")


func _make_world(runner: Object, autonomous: bool = false, competing: bool = false, scarce_export: bool = true, managed_herbs: bool = true) -> RegionWorld:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "continuous-world fixture loads definitions")
		return null
	if not managed_herbs:
		# The legacy quiet-cost scenario measures stable resident batching,
		# independently of the explicitly minute-sampled plant process.
		content.land_resources.types.wild_herbs.erase("ecology")
	var settings: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/scenarios/world_continuity.json")
	)
	var instances: Dictionary = {}
	for region_id: String in ["home", "river"]:
		var village: VillageSimulation = _make_village(content, region_id, autonomous, managed_herbs)
		if village == null:
			runner.assert_true(false, "continuous-world village initializes")
			return null
		instances[region_id] = village
	if competing:
		var second: Dictionary = settings.routes.river_road.duplicate(true)
		second["courier"] = "river_courier_second"
		second["courier_name"] = "第二名运粮人"
		if not scarce_export:
			second["travel_minutes"] = 8
		settings.routes["river_road_second"] = second
		# Both requests can be considered together, but only one real batch exists.
		if scarce_export:
			instances.river.inventory.containers.store.grain = int(second.reserve_floor) + int(second.amount)
	var world := RegionWorld.new()
	if not world.initialize(settings, instances, content):
		runner.assert_true(false, "regional scheduler binds the two villages")
		return null
	world.set_active_region("")
	return world


func _make_village(content: ReolContentDB, region_id: String, autonomous: bool, managed_herbs: bool = true) -> VillageSimulation:
	var settings: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/scenarios/village.json")
	)
	if not managed_herbs:
		# A new fixture with the prior fixed source law cannot offer care for
		# an unenabled plant. This happens before original bodies are created.
		settings.actions.erase("irrigate_herb")
	var cells: Dictionary = {}
	var profiles: Dictionary = {}
	var index: int = 0
	var origin := Vector2i(100, 100) if region_id == "home" else Vector2i(150, 100)
	for definition_id: String in settings.actor_profiles:
		var actor_id: String = definition_id if region_id == "home" else region_id + "_" + definition_id
		var profile: Dictionary = settings.actor_profiles[definition_id].duplicate(true)
		profile["definition_id"] = definition_id
		profile["autonomous"] = autonomous and (definition_id != "player" or region_id == "river")
		profiles[actor_id] = profile
		cells[actor_id] = [origin.x + index % 3, origin.y + int(index / 3)]
		index += 1
	settings["actor_profiles"] = profiles
	settings["controlled_actor"] = "player" if region_id == "home" else "river_player"
	if not autonomous:
		settings.scenario.helpers = []
	if region_id == "river":
		settings["autonomous_controller"] = autonomous
		settings.scenario.requester = "river_" + str(settings.scenario.requester)
		var helpers: Array = []
		for helper: String in settings.scenario.helpers:
			helpers.append("river_" + helper)
		settings.scenario.helpers = helpers
		settings.institution.id = "river_sect"
		for office: Dictionary in settings.institution.offices.values():
			office.holder = "river_" + str(office.holder)
	settings.initial_stock.store.grain = 0 if region_id == "home" else 100
	var places: Dictionary = {}
	for definition: Dictionary in settings.place_defs:
		places[definition.id] = {
			"label": definition.label,
			"cell": [origin.x + int(definition.offset[0]), origin.y + int(definition.offset[1])],
		}
	var village := VillageSimulation.new()
	if not village.initialize(content, settings, cells, places):
		return null
	village.set_navigation(_path)
	return village


func _path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [from_cell]
	var cursor: Vector2i = from_cell
	while cursor.x != to_cell.x:
		cursor.x += 1 if cursor.x < to_cell.x else -1
		path.append(cursor)
	while cursor.y != to_cell.y:
		cursor.y += 1 if cursor.y < to_cell.y else -1
		path.append(cursor)
	return path


func _first_shipment(world: RegionWorld) -> Dictionary:
	var deadline: int = world.current_time + 300
	while world.shipments.is_empty() and world.current_time < deadline:
		world.advance_to(world.current_time + 1)
	return {} if world.shipments.is_empty() else world.shipments.values()[0]


func _total_grain(world: RegionWorld) -> int:
	var amount: int = 0
	for village: VillageSimulation in world.regions.values():
		for container: String in village.inventory.containers:
			amount += village.inventory.quantity(container, "grain")
		# Transportation conserves all goods after explicit natural production.
		for id: String in village.land_resources.sources:
			if village.land_resources.terms_for(id).item == "grain":
				amount -= int(village.land_resources.sources[id].produced)
	for container: String in world.in_transit.containers:
		amount += world.in_transit.quantity(container, "grain")
	return amount


func _state(world: RegionWorld) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true)), "", true, true)


func _test_absent_villages_continue_living(runner: Object) -> void:
	var world: RegionWorld = _make_world(runner, true)
	if world == null:
		return
	var remote: VillageSimulation = world.regions.river
	var before: Dictionary = remote.to_dict()
	runner.assert_true(world.advance_to(600), "two entirely absent villages advance ten game hours")
	world.synchronize_regions()
	runner.assert_eq(world.current_time, 600, "world reaches the requested shared time")
	runner.assert_eq(remote.tick_index, 600, "absent village time stays aligned")
	runner.assert_true(remote.social.events.size() > 5, "absent people perform observable work and exchanges")
	runner.assert_true(remote.inventory.quantity("store", "wood") < int(before.inventory.containers.store.wood), "absent supply work consumes real source stock")
	runner.assert_eq(remote.actors.keys(), before.actors.keys(), "offscreen life preserves the persistent cast")
	runner.assert_true(remote.actors.river_a_he != before.actors.river_a_he, "offscreen cook retains evolving bodily needs and plans")
	runner.assert_true(remote.errors.is_empty(), "absent daily life creates no rule errors")
	var restored: RegionWorld = _make_world(runner, true)
	if restored != null:
		runner.assert_true(restored.restore(JSON.parse_string(_state(world))), "autonomous distant population remains saveable after daily activity")
	print("SCENARIO absent life: %d minutes, %d remote facts, %d shipments" % [world.current_time, remote.social.events.size(), world.shipments.size()])


func _test_cargo_exists_once_and_arrives_once(runner: Object) -> void:
	var world: RegionWorld = _make_world(runner)
	if world == null:
		return
	var total: int = _total_grain(world)
	var original_source: int = world.regions.river.inventory.quantity("store", "grain")
	var shipment: Dictionary = _first_shipment(world)
	runner.assert_true(not shipment.is_empty(), "actual shortage produces a shipment without player input")
	if shipment.is_empty():
		return
	var amount: int = int(shipment.amount)
	runner.assert_eq(world.regions.river.inventory.quantity("store", "grain"), original_source - amount, "loaded grain leaves the source village")
	runner.assert_eq(world.regions.home.inventory.quantity("store", "grain"), 0, "destination cannot use grain before arrival")
	runner.assert_eq(world.in_transit.quantity(shipment.container, "grain"), amount, "grain has an actual in-transit container")
	runner.assert_eq(_total_grain(world), total, "departure conserves all grain")
	world.advance_to(world.current_time + int(world.settings.routes.river_road.travel_minutes))
	runner.assert_eq(shipment.status, "delivered", "a timed journey reaches the other settlement")
	runner.assert_eq(world.regions.home.inventory.quantity("store", "grain"), amount, "arrival commits one delivery")
	runner.assert_eq(world.in_transit.quantity(shipment.container, "grain"), 0, "arrived cargo is no longer in transit")
	var operations: int = world.operations.size()
	world.advance_to(world.current_time)
	world.set_active_region("home")
	world.set_active_region("river")
	runner.assert_eq(world.regions.home.inventory.quantity("store", "grain"), amount, "repeated settlement and entering regions cannot repeat delivery")
	runner.assert_eq(world.operations.size(), operations, "repeated current-time settlement creates no second operation")
	runner.assert_eq(_total_grain(world), total, "arrival conserves all grain")
	print("SCENARIO transport: %d grain, departure %d, arrival %d, total %d" % [amount, shipment.departed_at, shipment.delivered_at, total])


func _test_blocked_route_keeps_cargo_and_progress(runner: Object) -> void:
	var world: RegionWorld = _make_world(runner)
	if world == null:
		return
	var shipment: Dictionary = _first_shipment(world)
	if shipment.is_empty():
		runner.assert_true(false, "blocked-route fixture has a journey")
		return
	world.advance_to(world.current_time + 9)
	var courier_id: String = str(world.settings.routes.river_road.courier)
	var courier: Dictionary = world.couriers[courier_id]
	var progress: int = int(courier.progress)
	var total: int = _total_grain(world)
	runner.assert_true(world.set_route_blocked("river_road", true), "road can be blocked midway")
	world.advance_to(world.current_time + 80)
	runner.assert_eq(courier.progress, progress, "blocked traveller keeps the same route progress")
	runner.assert_eq(shipment.status, "blocked", "unavailable road prevents planned arrival")
	runner.assert_eq(world.regions.home.inventory.quantity("store", "grain"), 0, "blocked cargo is not credited to its destination")
	runner.assert_eq(_total_grain(world), total, "waiting on a road neither copies nor refunds cargo")
	world.set_route_blocked("river_road", false)
	world.advance_to(world.current_time + int(world.settings.routes.river_road.travel_minutes) - progress)
	runner.assert_eq(shipment.status, "delivered", "reopening the road resumes the unfinished journey")
	runner.assert_eq(_total_grain(world), total, "resumed arrival still conserves grain")
	print("SCENARIO road interruption: held at %d minutes, cargo retained, then delivered" % progress)


func _test_competing_routes_share_real_stock(runner: Object) -> void:
	var world: RegionWorld = _make_world(runner, false, true)
	if world == null:
		return
	var total: int = _total_grain(world)
	world.advance_to(45)
	var loaded: int = 0
	for shipment: Dictionary in world.shipments.values():
		loaded += int(shipment.amount)
	var route: Dictionary = world.settings.routes.river_road
	runner.assert_eq(loaded, int(route.amount), "two couriers cannot both allocate the last exportable batch")
	runner.assert_true(world.regions.river.inventory.quantity("store", "grain") >= int(route.reserve_floor), "supplier keeps its required local reserve")
	runner.assert_eq(_total_grain(world), total, "competing requests preserve global stock")


func _test_full_destination_waits_without_losing_cargo(runner: Object) -> void:
	var world: RegionWorld = _make_world(runner)
	var restored: RegionWorld = _make_world(runner)
	if world == null or restored == null:
		return
	var shipment: Dictionary = _first_shipment(world)
	if shipment.is_empty():
		runner.assert_true(false, "full-destination fixture contains a real shipment")
		return
	world.regions.home.inventory.containers.store.grain = SimInventory.MAX_COUNT
	world.invalidate_region("home")
	world.advance_to(world.current_time + int(world.settings.routes.river_road.travel_minutes))
	var courier: Dictionary = world.couriers.river_courier
	runner.assert_eq(courier.phase, "waiting_delivery", "courier waits to unload when the destination is full")
	runner.assert_eq(world.in_transit.quantity(shipment.container, "grain"), int(shipment.amount), "full storage keeps goods in the courier's custody")
	var energy: float = float(courier.energy)
	world.advance_to(world.current_time + 30)
	runner.assert_eq(courier.energy, energy, "waiting to unload does not pretend the courier keeps travelling")
	runner.assert_true(restored.restore(JSON.parse_string(_state(world))), "waiting unload state survives a JSON snapshot")
	world.regions.home.inventory.containers.store.grain -= int(shipment.amount)
	world.invalidate_region("home")
	world.advance_to(world.current_time + int(world.settings.routes.river_road.assessment_minutes))
	runner.assert_eq(shipment.status, "delivered", "available storage lets the same waiting cargo unload")
	runner.assert_eq(world.in_transit.quantity(shipment.container, "grain"), 0, "successful retry empties the one cargo container")


func _test_earlier_cross_region_arrival_interrupts_batch(runner: Object) -> void:
	var world: RegionWorld = _make_world(runner, false, true, false)
	if world == null:
		return
	var first: Dictionary = _first_shipment(world)
	if first.is_empty():
		runner.assert_true(false, "different-duration routes have dispatched real cargo")
		return
	var departure: int = world.current_time
	world.advance_to(departure + 9)
	var early: Dictionary = {}
	var late: Dictionary = {}
	for shipment: Dictionary in world.shipments.values():
		if shipment.route == "river_road_second":
			early = shipment
		elif shipment.route == "river_road":
			late = shipment
	runner.assert_true(not early.is_empty() and not late.is_empty(), "both independent routes have real allocated cargo")
	if early.is_empty() or late.is_empty():
		return
	runner.assert_eq(early.status, "delivered", "earlier arrival is applied before a distant batch can pass it")
	runner.assert_eq(late.status, "outbound", "later route is still unfinished at the earlier causal boundary")
	runner.assert_eq(world.regions.home.inventory.quantity("store", "grain"), int(early.amount), "destination sees only cargo that has actually arrived")
	world.advance_to(departure + int(world.settings.routes.river_road.travel_minutes))
	var delivered: int = 0
	for shipment: Dictionary in world.shipments.values():
		if shipment.status == "delivered":
			delivered += int(shipment.amount)
	runner.assert_eq(world.regions.home.inventory.quantity("store", "grain"), delivered, "later arrivals preserve each earlier committed delivery")


func _test_switching_modes_preserves_unfinished_business(runner: Object) -> void:
	var world: RegionWorld = _make_world(runner)
	if world == null:
		return
	var remote: VillageSimulation = world.regions.river
	var actor_id: String = "river_lao_zhou"
	runner.assert_true(remote.submit_action(actor_id, "rest"), "remote person begins a persistent rest action")
	world.invalidate_region("river")
	world.advance_to(15)
	world.synchronize_region("river")
	var before: String = JSON.stringify(remote.to_dict(), "", true, true)
	var cargo: Dictionary = world.shipments.duplicate(true)
	for index: int in range(12):
		world.set_active_region("river")
		world.set_active_region("home")
		world.set_active_region("")
	runner.assert_true(world.regions.river == remote, "entering and leaving preserves the same simulation owner")
	runner.assert_eq(JSON.stringify(remote.to_dict(), "", true, true), before, "precision changes preserve identity, needs, memories and action progress")
	runner.assert_eq(world.shipments, cargo, "precision changes preserve unsettled transport")
	runner.assert_true(not remote.actors[actor_id].active.is_empty(), "returning can encounter work still in progress")
	remote.cancel_action(actor_id, "visitor_intervened")
	world.invalidate_region("river")
	world.advance_to(20)
	runner.assert_true(remote.actors[actor_id].active.is_empty(), "visitor intervention affects future work after reentry")


func _test_messages_do_not_make_distant_people_omniscient(runner: Object) -> void:
	var world: RegionWorld = _make_world(runner)
	if world == null:
		return
	world.advance_to(1)
	runner.assert_true(world.shipments.is_empty(), "supplier cannot dispatch before receiving the shortage report")
	runner.assert_true(world.known_event_lines("river").is_empty(), "sending a request does not immediately inform the far village")
	var shipment: Dictionary = _first_shipment(world)
	if shipment.is_empty():
		runner.assert_true(false, "delivered report produces a shipment")
		return
	var departure: int = world.current_time
	var delay: int = int(world.settings.routes.river_road.message_minutes)
	runner.assert_true(not world.known_event_lines("river").is_empty(), "source knows its actual departure")
	runner.assert_true(world.known_event_lines("home").is_empty(), "far destination cannot instantly know that a courier left")
	world.advance_to(departure + delay - 1)
	runner.assert_true(world.known_event_lines("home").is_empty(), "departure news remains unavailable until its channel delay")
	world.advance_to(departure + delay)
	runner.assert_true(not world.known_event_lines("home").is_empty(), "departure news becomes available only after arrival of the message")
	runner.assert_eq(world.regions.home.inventory.quantity("store", "grain"), 0, "learning about a shipment does not deliver its cargo")
	print("SCENARIO information: dispatch %d, destination hears %d, grain still in transit" % [departure, departure + delay])


func _test_new_near_action_survives_immediate_departure(runner: Object) -> void:
	var world: RegionWorld = _make_world(runner)
	var expected: RegionWorld = _make_world(runner)
	if world == null or expected == null:
		return
	world.set_active_region("home")
	expected.set_active_region("home")
	runner.assert_true(world.regions.home.submit_action("player", "rest"), "nearby player starts a new action at a commit point")
	expected.regions.home.submit_action("player", "rest")
	world.set_active_region("")
	world.advance_to(100)
	expected.advance_to(100)
	world.synchronize_region("home")
	runner.assert_eq(world.regions.home.actors.player, expected.regions.home.actors.player, "leaving immediately after a command retains its new execution boundary")


func _test_inflight_json_snapshot_continues(runner: Object) -> void:
	var original: RegionWorld = _make_world(runner)
	var restored: RegionWorld = _make_world(runner)
	if original == null or restored == null:
		return
	var shipment: Dictionary = _first_shipment(original)
	if shipment.is_empty():
		runner.assert_true(false, "save fixture has in-transit cargo")
		return
	original.advance_to(original.current_time + 11)
	original.set_route_blocked("river_road", true)
	original.advance_to(original.current_time + 17)
	var snapshot: Dictionary = JSON.parse_string(_state(original))
	runner.assert_true(restored.restore(snapshot), "JSON round trip restores blocked cargo and pending messages")
	runner.assert_true(_state(restored) == _state(original), "load retains complete committed and uncommitted state")
	original.set_route_blocked("river_road", false)
	restored.set_route_blocked("river_road", false)
	var target: int = original.current_time + 160
	original.advance_to(target)
	restored.advance_to(target)
	runner.assert_true(_state(restored) == _state(original), "saved unfinished world resumes with identical causal outcomes")
	print("SCENARIO save/resume: blocked mid-trip JSON snapshot resumes identically through minute %d" % target)


func _test_bad_snapshot_cannot_partly_replace_world(runner: Object) -> void:
	var world: RegionWorld = _make_world(runner)
	if world == null:
		return
	_first_shipment(world)
	var before: String = _state(world)
	var damaged: Dictionary = JSON.parse_string(before)
	damaged.current_time = -1
	runner.assert_true(not world.restore(damaged), "negative world time is rejected")
	runner.assert_true(_state(world) == before, "bad world snapshot does not replace regions or transport")
	damaged = JSON.parse_string(before)
	damaged.regions.river.actors.river_a_he.hunger = -1
	runner.assert_true(not world.restore(damaged), "invalid remote character rejects whole save")
	runner.assert_true(_state(world) == before, "failed remote validation leaves the living world unchanged")
	damaged = JSON.parse_string(before)
	if not damaged.shipments.is_empty():
		damaged.shipments.values()[0].amount = -1
		runner.assert_true(not world.restore(damaged), "invalid cargo rejects whole save")
		runner.assert_true(_state(world) == before, "failed cargo validation leaves original pending delivery intact")


func _test_bounded_advancement_can_resume(runner: Object) -> void:
	var bounded: RegionWorld = _make_world(runner)
	var unlimited: RegionWorld = _make_world(runner)
	if bounded == null or unlimited == null:
		return
	var complete: bool = bounded.advance_to(240, 1)
	runner.assert_true(not complete, "small work budget yields before the full world interval")
	runner.assert_true(bounded.current_time < 240, "yield does not claim unprocessed time")
	var attempts: int = 0
	while not complete and attempts < 2000:
		complete = bounded.advance_to(240, 1)
		attempts += 1
	runner.assert_true(complete, "retained pending world time can finish over later calls")
	unlimited.advance_to(240)
	runner.assert_true(_state(bounded) == _state(unlimited), "budget boundaries do not lose events or change outcomes")


func _test_coarse_execution_agrees_with_detailed_execution(runner: Object) -> void:
	# Keep this original sparse-cost assertion about stable residents. Other
	# regional acceptance cases retain the real managed ecology by default.
	var coarse: RegionWorld = _make_world(runner, false, false, true, false)
	var detailed: RegionWorld = _make_world(runner, false, false, true, false)
	if coarse == null or detailed == null:
		return
	for world: RegionWorld in [coarse, detailed]:
		for sim: VillageSimulation in world.regions.values():
			runner.assert_true(sim.land_resources.sources.herb_slope.ecology.is_empty() and not sim.config.actions.has("irrigate_herb"), "quiet-cost dependencies have no enabled plant process or care action")
	coarse.advance_to(240)
	for minute: int in range(1, 241):
		detailed.set_active_region("home")
		detailed.advance_to(minute)
		# The other region remains remotely advanced in both runs.
	coarse.synchronize_regions()
	detailed.synchronize_regions()
	var coarse_home: VillageSimulation = coarse.regions.home
	var detailed_home: VillageSimulation = detailed.regions.home
	runner.assert_eq(_total_grain(coarse), _total_grain(detailed), "coarse and detailed travel conserve the same goods")
	runner.assert_eq(coarse_home.inventory.to_dict(), detailed_home.inventory.to_dict(), "coarse and detailed delivery agree at an equal world time")
	runner.assert_eq(coarse_home.actors, detailed_home.actors, "quiet coarse and detailed need updates agree")
	runner.assert_eq(coarse.shipments, detailed.shipments, "cross-region arrival ordering is unchanged by presentation precision")
	runner.assert_true(int(coarse_home.simulation_work.batched_minutes) > 120, "quiet absent village batches most stable minutes")
	runner.assert_true(int(coarse_home.simulation_work.quiet_batch_calls) < int(detailed_home.simulation_work.quiet_batch_calls), "coarse execution avoids detailed per-minute work")
	var near_remote: VillageSimulation = detailed.regions.river
	runner.assert_true(int(near_remote.simulation_work.step_count) + int(near_remote.simulation_work.quiet_batch_calls) < 100, "a nearby settlement does not force quiet far residents to update every minute")
	print("SCENARIO cost: quiet remote %d detailed steps + %d batched minutes; near %d steps" % [coarse_home.simulation_work.step_count, coarse_home.simulation_work.batched_minutes, detailed_home.simulation_work.step_count])


func _test_one_actor_has_one_execution_owner(runner: Object) -> void:
	var world: RegionWorld = _make_world(runner)
	if world == null:
		return
	var invalid := RegionWorld.new()
	runner.assert_true(not invalid.initialize(world.settings, {
		"home": world.regions.home, "river": world.regions.home,
	}), "one simulation instance cannot be executed as two settlements")
	var content := ReolContentDB.new()
	content.load_all()
	var other_home: VillageSimulation = _make_village(content, "home", false)
	runner.assert_true(not invalid.initialize(world.settings, {
		"home": world.regions.home, "river": other_home,
	}), "different settlements cannot own duplicate persistent character identities")
