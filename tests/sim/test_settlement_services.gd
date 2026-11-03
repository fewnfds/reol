extends RefCounted
## Acceptance checks for services provided by actual people and institutions.

const ContinuityFixture = preload("res://tests/sim/test_regional_simulation.gd")

var _fixtures: RefCounted = ContinuityFixture.new()


func run(runner: Object) -> void:
	_test_visitor_uses_local_food_and_bed(runner)
	_test_cancel_keeps_actual_custody(runner)
	_test_delivery_reporting_and_exchange(runner)
	_test_transport_blockage_cancellation_and_death(runner)
	_test_permissions_are_rechecked_at_execution(runner)
	_test_help_has_cost_and_actual_execution(runner)
	_test_unfinished_services_survive_json_load(runner)
	_test_institutional_service_snapshots_resume_once(runner)
	_test_coarse_service_execution_matches_fine(runner)
	_test_delivery_claim_reconciles_pending_reports(runner)
	_test_invalid_service_boundaries_leave_state_unchanged(runner)
	_test_cancelled_claims_do_not_reintroduce_dispatched_demand(runner)


func _make_world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _fixtures._make_world(runner)
	if world == null:
		return null
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/definitions/settlement_services.json"
	))
	if not world.configure_services(definitions):
		runner.assert_true(false, "settlement service definitions bind to the persistent world")
		return null
	world.services.set_navigation(Callable(_fixtures, "_path"))
	world.regions.home.inventory.containers["actor:player"]["coin"] = 8
	# Keep registrars present for service tests; their official role still matters.
	for simulation: VillageSimulation in world.regions.values():
		for office: Dictionary in simulation.institutions.institutions[simulation.config.institution.id].offices.values():
			if not str(office.holder).is_empty():
				simulation.set_actor_cell(office.holder, SimRouteTravel.cell(simulation.places.records.cell.duplicate()))
	return world


func _position(world: RegionalSimulation, region_id: String, place: String, offset: Vector2i = Vector2i.ZERO) -> void:
	var data: Array = world.regions[region_id].places[place].cell
	world.regions.home.set_actor_cell("player", SimRouteTravel.cell([int(data[0]) + offset.x, int(data[1]) + offset.y]))
	world.invalidate_region("home")


func _finish(world: RegionalSimulation, actor_id: String, runner: Object, budget: int = 1500) -> void:
	var stop: int = world.current_time + budget
	while world.services.active_jobs.has(actor_id) and world.current_time < stop:
		if not world.advance_to(world.current_time + 1):
			runner.assert_true(false, "service simulation can advance to its next world minute")
			break
	runner.assert_true(not world.services.active_jobs.has(actor_id), "service action reaches a terminal result")


func _ok(result: Dictionary) -> bool:
	return bool(result.get("ok", false))


func _total(world: RegionalSimulation, item: String) -> int:
	var quantity: int = 0
	for simulation: VillageSimulation in world.regions.values():
		for container: String in simulation.inventory.containers:
			quantity += simulation.inventory.quantity(container, item)
		for id: String in simulation.land_resources.sources:
			if simulation.land_resources.terms_for(id).item == item:
				quantity -= int(simulation.land_resources.sources[id].produced)
	for container: String in world.in_transit.containers:
		quantity += world.in_transit.quantity(container, item)
	if world.services != null:
		for container: String in world.services.escrow.containers:
			quantity += world.services.escrow.quantity(container, item)
	return quantity


func _state(world: RegionalSimulation) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true)), "", true, true)


func _test_visitor_uses_local_food_and_bed(runner: Object) -> void:
	var world: RegionalSimulation = _make_world(runner)
	if world == null:
		return
	var home: VillageSimulation = world.regions.home
	var remote: VillageSimulation = world.regions.river
	var identities: Array = remote.actors.keys()
	home.actors.player.hunger = 20.0
	home.actors.player.energy = 15.0
	_position(world, "river", "kitchen", Vector2i(2, 0))
	var meals: int = _total(world, "meal")
	var source_meals: int = remote.inventory.quantity("kitchen", "meal")
	var result: Dictionary = world.services.begin("player", "river", "eat")
	runner.assert_true(_ok(result), "visitor can request food in another settlement")
	runner.assert_true(world.services.owns_actor("player"), "one world executor owns the visiting player's action")
	runner.assert_true(not home.submit_action("player", "rest"), "local executor cannot start a second action owned by visitor services")
	runner.assert_eq(remote.inventory.quantity("kitchen", "meal"), source_meals, "requesting food does not teleport or consume it")
	var hunger: float = float(home.actors.player.hunger)
	world.advance_to(world.current_time + 1)
	runner.assert_true(float(home.actors.player.hunger) <= hunger, "food benefits wait for travel and eating time")
	_finish(world, "player", runner)
	runner.assert_eq(_total(world, "meal"), meals - 1, "visitor consumes one actual meal from local stock")
	runner.assert_true(float(home.actors.player.hunger) > hunger, "eating restores the same persistent player's hunger")
	runner.assert_eq(remote.actors.keys(), identities, "visiting never creates a duplicate player in the destination")
	var energy: float = float(home.actors.player.energy)
	runner.assert_true(_ok(world.services.begin("player", "river", "rest")), "visitor can request a local bed")
	_finish(world, "player", runner)
	runner.assert_true(float(home.actors.player.energy) > energy, "rest after a real journey restores the original player's energy")
	runner.assert_true(world.current_time >= 60, "food and lodging use world time")
	print("SCENARIO visitor: one player ate and rested at river over %d world minutes" % world.current_time)


func _test_cancel_keeps_actual_custody(runner: Object) -> void:
	var world: RegionalSimulation = _make_world(runner)
	if world == null:
		return
	_position(world, "river", "kitchen")
	var meals: int = _total(world, "meal")
	var begin: Dictionary = world.services.begin("player", "river", "eat")
	runner.assert_true(_ok(begin), "cancel fixture begins a real food service")
	var stop: int = world.current_time + 100
	while world.regions.home.inventory.quantity("actor:player", "meal") == 0 and world.services.owns_actor("player") and world.current_time < stop:
		world.advance_to(world.current_time + 1)
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "meal"), 1, "food is physically transferred into visitor custody before eating")
	world.services.cancel("player")
	world.services.cancel("player")
	runner.assert_eq(_total(world, "meal"), meals, "repeated cancellation cannot refund a second meal")
	runner.assert_true(not world.services.owns_actor("player"), "cancellation releases execution ownership")
	runner.assert_true(_ok(world.services.begin("player", "river", "eat")), "visitor can resume eating already carried food")
	_finish(world, "player", runner)
	runner.assert_eq(_total(world, "meal"), meals - 1, "resumed eating consumes the carried meal once")
	world.regions.river.inventory.containers.kitchen.meal = 0
	world.invalidate_region("river")
	var before_inventory: Dictionary = world.regions.home.inventory.to_dict()
	var before_remote: Dictionary = world.regions.river.inventory.to_dict()
	runner.assert_true(not _ok(world.services.begin("player", "river", "eat")), "missing food prevents an unfunded meal action")
	runner.assert_eq(world.regions.home.inventory.to_dict(), before_inventory, "failed food request cannot take fees or create reservations")
	runner.assert_eq(world.regions.river.inventory.to_dict(), before_remote, "failed food request cannot remove nonexistent stock")


func _test_delivery_reporting_and_exchange(runner: Object) -> void:
	var world: RegionalSimulation = _make_world(runner)
	if world == null:
		return
	_position(world, "river", "store", Vector2i(1, 0))
	var total: int = _total(world, "grain")
	var result: Dictionary = world.services.begin("player", "river", "haul_grain")
	runner.assert_true(_ok(result), "player can accept needed cross-settlement grain transport")
	var duplicate: Dictionary = world.services.begin("player", "river", "haul_grain")
	runner.assert_true(not _ok(duplicate) or duplicate.get("id") == result.get("id"), "repeated click cannot create a second active transport")
	var stop: int = world.current_time + 100
	while world.regions.home.inventory.quantity("actor:player", "grain") == 0 and world.services.owns_actor("player") and world.current_time < stop:
		world.advance_to(world.current_time + 1)
	runner.assert_true(world.regions.home.inventory.quantity("actor:player", "grain") > 0, "player physically picks up allocated grain")
	runner.assert_eq(_total(world, "grain"), total, "pickup preserves global grain ownership")
	runner.assert_eq(world.regions.home.institutions.balance("sect", "player"), 0, "acceptance and pickup do not mint institutional contribution")
	_finish(world, "player", runner)
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "grain"), 0, "successful delivery leaves grain in destination custody")
	runner.assert_eq(_total(world, "grain"), total, "delivery does not create or lose grain")
	runner.assert_true(not world.services.receipts.is_empty(), "needed actual delivery leaves reportable evidence")
	runner.assert_eq(world.regions.home.institutions.balance("sect", "player"), 0, "delivery evidence still requires authorized registration")
	var before_forgery: String = _state(world)
	var forged: Dictionary = JSON.parse_string(before_forgery)
	forged.services.receipts.values()[0].amount += 1
	runner.assert_true(not world.restore(forged), "a delivery receipt cannot claim more contribution than the real work terms")
	runner.assert_true(_state(world) == before_forgery, "forged receipt leaves the real delivered work and pending proof intact")
	runner.assert_true(_ok(world.services.report_work("player", "home")), "player can travel to a present registrar and report real evidence")
	_finish(world, "player", runner)
	var credit: int = world.regions.home.institutions.balance("sect", "player")
	runner.assert_eq(credit, int(world.services.definitions.hauling.credit), "authorized registration records exactly the promised institutional contribution")
	world.services.report_work("player", "home")
	_finish(world, "player", runner)
	runner.assert_eq(world.regions.home.institutions.balance("sect", "player"), credit, "reporting the same evidence twice cannot duplicate credit")
	var meals: int = _total(world, "meal")
	var carried: int = world.regions.home.inventory.quantity("actor:player", "meal")
	runner.assert_true(_ok(world.services.redeem("player", "home", "meal")), "recognized contribution can buy an actual stocked meal")
	_finish(world, "player", runner)
	runner.assert_eq(_total(world, "meal"), meals, "redemption transfers existing goods rather than producing them")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "meal"), carried + int(world.services.definitions.redemptions.meal.amount), "redemption places exactly the stocked offer in the real player bag")
	runner.assert_eq(world.regions.home.institutions.balance("sect", "player"), credit - int(world.services.definitions.redemptions.meal.cost), "redemption debits exactly the issuing institution's listed cost")
	var settled: String = _state(world)
	world.advance_to(world.current_time)
	runner.assert_true(_state(world) == settled, "reprocessing a committed service cannot pay again")
	print("SCENARIO institutional service: transport→proof→registration→%d credit→stocked redemption" % credit)


func _test_permissions_are_rechecked_at_execution(runner: Object) -> void:
	var world: RegionalSimulation = _make_world(runner)
	if world == null:
		return
	_position(world, "home", "records")
	var home: VillageSimulation = world.regions.home
	var unqualified: Dictionary = world.services.request_access("player", "home", "gate")
	runner.assert_true(not unqualified.is_empty(), "asking for passage returns an explicit institutional decision")
	_finish(world, "player", runner)
	runner.assert_true(not world.services.has_access("player", "home", "gate"), "politeness without eligibility grants no actual passage")
	runner.assert_true(not _ok(world.services.begin("player", "home", "collect_herb")), "without authorization a visitor cannot collect restricted stock")
	home.institutions.issue("fixture:service_credit", "sect", "chen_shouzhuo", "player", 4, "fixture:recognized_work")
	runner.assert_true(_ok(world.services.request_access("player", "home", "gate")), "eligible player can request a formal authorization")
	_finish(world, "player", runner)
	runner.assert_true(world.services.has_access("player", "home", "gate"), "qualified request requires an actual authorized decision")
	var herbs: int = home.inventory.quantity("actor:player", "herb")
	runner.assert_true(_ok(world.services.begin("player", "home", "collect_herb")), "authorized passage enables a concrete resource action")
	_finish(world, "player", runner)
	runner.assert_eq(home.inventory.quantity("actor:player", "herb"), herbs + 1, "authorized collection transfers actual protected goods")
	home.institutions.appoint("sect", "steward", "")
	runner.assert_true(not world.services.has_access("player", "home", "gate"), "revoked authority no longer grants effective passage")
	runner.assert_true(not _ok(world.services.begin("player", "home", "collect_herb")), "revoked passage blocks the protected action")
	home.institutions.appoint("sect", "steward", "chen_shouzhuo")
	var stock: int = home.inventory.quantity("kitchen", "meal")
	var credit: int = home.institutions.balance("sect", "player")
	runner.assert_true(_ok(world.services.redeem("player", "home", "meal")), "redemption can begin while an official has signing power")
	home.institutions.appoint("sect", "registrar", "")
	world.invalidate_region("home")
	_finish(world, "player", runner)
	runner.assert_eq(home.institutions.balance("sect", "player"), credit, "revoking the signer during processing prevents a debit")
	runner.assert_eq(home.inventory.quantity("kitchen", "meal"), stock, "revoked redemption transfers no stock")
	home.institutions.appoint("sect", "registrar", "chen_shouzhuo")
	home.inventory.containers.kitchen.meal = 0
	world.invalidate_region("home")
	world.services.redeem("player", "home", "meal")
	_finish(world, "player", runner)
	runner.assert_eq(home.institutions.balance("sect", "player"), credit, "out-of-stock redemption never debits contribution")


func _test_transport_blockage_cancellation_and_death(runner: Object) -> void:
	var world: RegionalSimulation = _make_world(runner)
	if world == null:
		return
	_position(world, "river", "store")
	var grain: int = _total(world, "grain")
	runner.assert_true(_ok(world.services.begin("player", "river", "haul_grain")), "interruption fixture starts needed transport")
	var stop: int = world.current_time + 100
	while world.regions.home.inventory.quantity("actor:player", "grain") == 0 and world.services.owns_actor("player") and world.current_time < stop:
		world.advance_to(world.current_time + 1)
	var cargo: int = world.regions.home.inventory.quantity("actor:player", "grain")
	runner.assert_true(cargo > 0, "interrupted player actually carries the source goods")
	world.set_route_blocked("river_road", true)
	var position: Array = world.regions.home.actors.player.cell.duplicate()
	world.advance_to(world.current_time + 30)
	runner.assert_eq(world.regions.home.actors.player.cell, position, "closed cross-region route stops service travel")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "grain"), cargo, "closed route retains player cargo in custody")
	var blocked_status: Dictionary = world.services.status("player")
	runner.assert_eq(blocked_status.stage, "delivery", "service observation distinguishes delivery from source pickup")
	runner.assert_true(str(blocked_status.line).contains("受阻"), "service observation keeps the actual blocked-road explanation")
	world.services.cancel("player")
	world.services.cancel("player")
	var cancelled_status: Dictionary = world.services.status("player")
	runner.assert_true(not cancelled_status.busy and cancelled_status.status == "cancelled" and str(cancelled_status.line).contains("中断"), "terminal service result remains available after its execution owner is released")
	var restored: RegionalSimulation = _make_world(runner)
	if restored != null:
		runner.assert_true(restored.restore(JSON.parse_string(_state(world))), "cancelled service state and correction report restore together")
		runner.assert_eq(restored.services.status("player"), cancelled_status, "derived latest-service observation rebuilds identically after load")
	runner.assert_eq(_total(world, "grain"), grain, "cancelling a blocked journey cannot refund duplicate cargo")
	runner.assert_true(world.services.receipts.is_empty(), "cancelled transport creates no completed-work evidence")
	world.set_route_blocked("river_road", false)
	runner.assert_true(_ok(world.services.begin("player", "river", "rest")), "living player can begin another activity")
	world.regions.home.remove_actor("player")
	world.invalidate_region("home")
	world.advance_to(world.current_time + 100)
	runner.assert_true(not world.services.owns_actor("player"), "dead or departed actor cannot keep executing a service")
	runner.assert_eq(_total(world, "grain"), grain, "departure leaves real cargo rather than erasing or refunding it")


func _test_help_has_cost_and_actual_execution(runner: Object) -> void:
	var world: RegionalSimulation = _make_world(runner)
	var busy_world: RegionalSimulation = _make_world(runner)
	if world == null or busy_world == null:
		return
	_fixtures._first_shipment(busy_world)
	_position(busy_world, "river", "store")
	var busy: Dictionary = busy_world.services.ask_help("player", "river_courier", "river_road", 2)
	runner.assert_eq(busy.get("status"), "refused", "an existing transport commitment can make a healthy courier refuse")
	var courier: Dictionary = world.couriers.river_courier
	_position(world, "river", "store")
	courier.energy = 5.0
	var before: int = _total(world, "coin")
	var refusal: Dictionary = world.services.ask_help("player", "river_courier", "river_road", 2)
	runner.assert_eq(refusal.get("status"), "refused", "exhausted helper can refuse a paid request")
	runner.assert_eq(_total(world, "coin"), before, "refusal does not invent or destroy payment")
	courier.energy = 100.0
	var agreement: Dictionary = world.services.ask_help("player", "river_courier", "river_road", 2)
	runner.assert_eq(agreement.get("status"), "accepted", "idle capable helper can accept adequate concrete terms")
	if agreement.get("status") != "accepted":
		return
	var promise: Dictionary = world.services.help_requests[agreement.id]
	runner.assert_true(not str(promise.shipment).is_empty() and world.shipments.has(promise.shipment), "accepted agreement names its own actual dispatched shipment")
	runner.assert_eq(world.services.escrow.quantity(promise.escrow, "coin"), 2, "accepted payment is held in a real escrow container")
	runner.assert_eq(_total(world, "coin"), before, "acceptance moves a real payment into escrow without creating currency")
	var repeated: Dictionary = world.services.ask_help("player", "river_courier", "river_road", 2)
	runner.assert_true(repeated.get("id") == agreement.get("id"), "unchanged accepted terms retain the same agreement")
	var money_after_accept: int = world.regions.home.inventory.quantity("actor:player", "coin")
	world.services.ask_help("player", "river_courier", "river_road", 2)
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "coin"), money_after_accept, "repeating a request does not escrow payment again")
	var restored: RegionalSimulation = _make_world(runner)
	if restored != null:
		runner.assert_true(restored.restore(JSON.parse_string(_state(world))), "an unpaid promise and escrow survive JSON save/load")
	world.set_active_region("")
	world.advance_to(world.current_time + 400)
	if restored != null:
		restored.set_active_region("")
		restored.advance_to(world.current_time)
		runner.assert_true(_state(restored) == _state(world), "saved unpaid cooperation delivers and settles payment identically")
	runner.assert_eq(world.shipments[promise.shipment].status, "delivered", "the agreement's own cargo arrives while the player is absent")
	runner.assert_eq(promise.execution, "fulfilled", "the paid promise settles only after its own delivery")
	runner.assert_eq(world.services.escrow.quantity(promise.escrow, "coin"), 0, "fulfillment releases the original escrow payment")
	runner.assert_eq(world.services.escrow.quantity(promise.wallet, "coin"), 2, "the helper is paid exactly the agreed existing coins")
	runner.assert_eq(_total(world, "coin"), before, "delivery pays existing escrow coins instead of generating money")
	var settled: String = _state(world)
	var forged_wallet: Dictionary = JSON.parse_string(settled)
	forged_wallet.services.escrow.containers[promise.wallet]["coin"] += 1
	runner.assert_true(not world.restore(forged_wallet), "courier wallet currency must be backed by the exact completed payment")
	runner.assert_true(_state(world) == settled, "an unbacked courier payment cannot corrupt the live cooperation state")
	var paid_once: int = world.regions.home.inventory.quantity("actor:player", "coin")
	world.services.ask_help("player", "river_courier", "river_road", 2)
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "coin"), paid_once, "replaying completed cooperation cannot collect another payment")
	print("SCENARIO cooperation: tired helper refused; changed terms/resources accepted and transported real grain")


func _test_unfinished_services_survive_json_load(runner: Object) -> void:
	var world: RegionalSimulation = _make_world(runner)
	var restored: RegionalSimulation = _make_world(runner)
	if world == null or restored == null:
		return
	_position(world, "river", "store")
	world.services.begin("player", "river", "haul_grain")
	world.advance_to(2)
	var encoded: String = _state(world)
	runner.assert_true(restored.restore(JSON.parse_string(encoded)), "mid-service JSON snapshot restores all execution references")
	runner.assert_true(not restored.regions.home.submit_action("player", "rest"), "loading a service also restores its single execution owner")
	var lost_cargo: Dictionary = JSON.parse_string(encoded)
	lost_cargo.regions.home.inventory.containers["actor:player"]["grain"] = 0
	var coherent: String = _state(restored)
	runner.assert_true(not restored.restore(lost_cargo), "active transport with missing real cargo rejects the entire save")
	runner.assert_true(_state(restored) == coherent, "missing service cargo cannot corrupt the live saved journey")
	world.advance_to(300)
	restored.advance_to(300)
	runner.assert_true(_state(restored) == _state(world), "unfinished cross-region service continues identically after JSON load")
	var before: String = _state(restored)
	var damaged: Dictionary = JSON.parse_string(before)
	if damaged.has("services") and not damaged.services.active_jobs.is_empty():
		damaged.services.active_jobs.player = "missing:job"
	else:
		damaged.services.active_jobs["missing:actor"] = "missing:job"
	runner.assert_true(not restored.restore(damaged), "broken service job references reject the entire world snapshot")
	runner.assert_true(_state(restored) == before, "bad service snapshot cannot partly replace regional state")


func _test_coarse_service_execution_matches_fine(runner: Object) -> void:
	var coarse: RegionalSimulation = _make_world(runner)
	var fine: RegionalSimulation = _make_world(runner)
	if coarse == null or fine == null:
		return
	_position(coarse, "river", "kitchen", Vector2i(2, 0))
	_position(fine, "river", "kitchen", Vector2i(2, 0))
	coarse.services.begin("player", "river", "eat")
	fine.services.begin("player", "river", "eat")
	coarse.advance_to(120)
	for minute: int in range(1, 121):
		fine.advance_to(minute)
	runner.assert_true(_state(coarse) == _state(fine), "service travel, consumption and world outcomes agree across advancement granularity")


func _assert_pending_service_roundtrip(world: RegionalSimulation, kind: String, runner: Object) -> void:
	world.advance_to(world.current_time + 2)
	runner.assert_true(world.services.owns_actor("player"), "%s snapshot is taken while the institutional job is unfinished" % kind)
	var saved: String = _state(world)
	var restored: RegionalSimulation = _make_world(runner)
	if restored == null:
		return
	runner.assert_true(restored.restore(JSON.parse_string(saved)), "%s job quote, evidence and execution restore from JSON" % kind)
	runner.assert_true(_state(restored) == saved, "%s load retains the complete pending institutional transaction" % kind)
	_finish(world, "player", runner)
	restored.advance_to(world.current_time)
	runner.assert_true(_state(restored) == _state(world), "%s resumes to identical institutional balances, stock and records" % kind)
	var balance: int = restored.regions.home.institutions.balance("sect", "player")
	var meals: int = restored.regions.home.inventory.quantity("actor:player", "meal")
	restored.advance_to(restored.current_time)
	runner.assert_eq(restored.regions.home.institutions.balance("sect", "player"), balance, "%s repeated settlement does not repeat a posting" % kind)
	runner.assert_eq(restored.regions.home.inventory.quantity("actor:player", "meal"), meals, "%s repeated settlement does not repeat delivery" % kind)


func _test_institutional_service_snapshots_resume_once(runner: Object) -> void:
	var world: RegionalSimulation = _make_world(runner)
	if world == null:
		return
	_position(world, "river", "store")
	runner.assert_true(_ok(world.services.begin("player", "river", "haul_grain")), "institutional snapshot fixture starts a resource-backed delivery")
	_finish(world, "player", runner)
	runner.assert_true(_ok(world.services.report_work("player", "home")), "reporting starts an actual pending registrar transaction")
	_assert_pending_service_roundtrip(world, "report", runner)
	var promised: int = int(world.services.definitions.hauling.credit)
	runner.assert_eq(world.regions.home.institutions.balance("sect", "player"), promised, "resumed reporting posts exactly one work award")
	runner.assert_true(_ok(world.services.redeem("player", "home", "meal")), "redemption starts a pending stock and debit transaction")
	_assert_pending_service_roundtrip(world, "redeem", runner)
	runner.assert_eq(world.regions.home.institutions.balance("sect", "player"), promised - int(world.services.definitions.redemptions.meal.cost), "resumed redemption makes exactly one matching debit")
	runner.assert_true(_ok(world.services.request_access("player", "home", "gate")), "access starts a pending eligibility and authorization transaction")
	_assert_pending_service_roundtrip(world, "access", runner)
	runner.assert_true(world.services.has_access("player", "home", "gate"), "resumed access transaction produces effective passage")
	print("SCENARIO institutional persistence: report, redemption and permission each resume once from unfinished JSON snapshots")


func _test_delivery_claim_reconciles_pending_reports(runner: Object) -> void:
	var world: RegionalSimulation = _make_world(runner)
	if world == null:
		return
	var route: Dictionary = world.settings.routes.river_road
	var amount: int = int(world.services.definitions.hauling.amount)
	world.regions.home.inventory.containers.store.grain = int(route.stock_below) - amount
	world.invalidate_region("home")
	runner.assert_eq(world.delivery_need("river_road"), amount, "delivery assessment starts with exactly one work-sized shortage")
	world.request_delivery("river_road")
	_position(world, "river", "store")
	runner.assert_true(_ok(world.services.begin("player", "river", "haul_grain")), "player can claim shortage after the original request letter was sent")
	runner.assert_eq(world.delivery_need("river_road"), 0, "a concrete accepted contract covers its exact destination demand")
	world.set_route_blocked("river_road", true)
	world.advance_to(int(route.message_minutes))
	runner.assert_true(world.shipments.is_empty(), "an older in-flight report cannot dispatch duplicate cargo for a newly claimed shortage")
	world.services.cancel("player")
	world.set_route_blocked("river_road", false)
	runner.assert_eq(world.delivery_need("river_road"), amount, "cancellation releases only the unfinished delivery commitment")
	var correction_at: int = world.current_time + int(route.message_minutes)
	world.advance_to(correction_at - 1)
	runner.assert_true(world.shipments.is_empty(), "source does not learn cancellation before a correction report reaches it")
	world.advance_to(correction_at)
	runner.assert_eq(world.shipments.size(), 1, "a delivered correction lets an available courier resume the released work")
	var shipment: Dictionary = world.shipments.values()[0]
	runner.assert_eq(int(shipment.amount), amount, "automatic replacement supplies only the original unmet shortage")


func _test_invalid_service_boundaries_leave_state_unchanged(runner: Object) -> void:
	var world: RegionalSimulation = _make_world(runner)
	if world == null:
		return
	var services: RefCounted = world.services
	var before: String = _state(world)
	runner.assert_true(not services.transfer("bad-region", "missing", "store", "home", "actor:player", "grain", 1), "unknown transfer source is rejected without a dictionary access error")
	runner.assert_true(not services.transfer("bad-destination", "home", "store", "missing", "store", "grain", 1), "unknown transfer destination is rejected")
	runner.assert_true(not services.transfer("", "river", "store", "home", "actor:player", "grain", 1), "cross-settlement transfer requires a real operation identity")
	runner.assert_true(not services.transfer("bad-item", "river", "store", "home", "actor:player", "", 1), "cross-settlement transfer requires an item identity")
	runner.assert_eq(services.issuer("missing", "player", "record"), "", "unknown office region has no valid issuer")
	runner.assert_eq(services.issuer("home", "missing", "record"), "", "unknown actor cannot obtain an office issuer")
	runner.assert_true(_state(world) == before, "invalid external requests cannot partially change world inventory, records or time")


func _test_cancelled_claims_do_not_reintroduce_dispatched_demand(runner: Object) -> void:
	var world: RegionalSimulation = _make_world(runner)
	if world == null:
		return
	var route: Dictionary = world.settings.routes.river_road
	var amount: int = int(world.services.definitions.hauling.amount)
	# Two small promises are cancelled before their correction letters arrive.
	# The first letter causes a real dispatch before the second letter reaches
	# the supplier, whose own shipment must not be allocated for a second time.
	route.travel_minutes = 3
	route.assessment_minutes = 300
	world.regions.home.inventory.containers.store.grain = int(route.stock_below) - 2 * amount
	world.invalidate_region("home")
	_position(world, "river", "store")
	var second_actor: String = "river_player"
	world.regions.river.set_actor_cell(second_actor, SimRouteTravel.cell(world.regions.river.places.store.cell.duplicate()))
	runner.assert_true(_ok(world.services.begin("player", "river", "haul_grain")), "first actor claims one part of the shared shortage")
	runner.assert_true(_ok(world.services.begin(second_actor, "river", "haul_grain")), "second actor can claim the remaining distinct part")
	runner.assert_eq(world.delivery_need("river_road"), 0, "multiple promises cover exactly the two accepted shares")
	world.advance_to(1)
	world.services.cancel("player")
	world.advance_to(2)
	world.services.cancel(second_actor)
	runner.assert_eq(world.delivery_need("river_road"), 2 * amount, "both cancellations release only their uncompleted shares")
	world.advance_to(40)
	var delivered: int = 0
	for shipment: Dictionary in world.shipments.values():
		delivered += int(shipment.amount)
	runner.assert_eq(delivered, 2 * amount, "late correction reports cannot reintroduce cargo already dispatched for the same shortage")
	runner.assert_eq(world.regions.home.inventory.quantity("store", "grain"), int(route.stock_below), "automatic replacements stop at the original target stock")
