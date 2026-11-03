extends RefCounted
## End-to-end rules tests use open grid routes and fixed game-minute steps.

const Simulation = preload("res://scripts/sim/village_simulation.gd")
const ContentDB = preload("res://scripts/data/content_db.gd")
const Clock = preload("res://scripts/autoload/game_clock.gd")


func run(runner: Object) -> void:
	_test_haul_takes_time_and_conserves(runner)
	_test_cancel_never_copies_resources(runner)
	_test_knowledge_stays_with_witnesses(runner)
	_test_repeated_request_cannot_repeat_execution(runner)
	_test_reporting_creates_institutional_credit(runner)
	_test_inflight_snapshot_continues_and_rejects_damage(runner)
	_test_office_succession_preserves_memory_and_accounts(runner)
	_test_clock_speed_does_not_change_tick_outcome(runner)
	_test_three_autonomous_days_release_reservations(runner)
	_test_unreachable_action_releases_reservation(runner)
	_test_cancelled_last_meal_can_be_eaten(runner)
	_test_cancelled_recipe_reuses_carried_ingredients(runner)
	_test_recipe_overflow_preserves_inputs_and_valid_state(runner)
	_test_unneeded_deliveries_do_not_earn_contribution(runner)
	_test_promotion_requires_authority_and_recorded_credit(runner)


func _make_simulation(runner: Object, autonomous: bool = false) -> VillageSimulation:
	var content := ContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "village fixture content loads")
		return null
	var settings: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/scenarios/village.json")
	)
	if not autonomous:
		for profile: Dictionary in settings.actor_profiles.values():
			profile["autonomous"] = false
		settings["scenario"]["helpers"] = []
	var cells: Dictionary = {
		"player": [100, 100], "chen_shouzhuo": [102, 100], "a_he": [100, 101],
		"shi_tou": [101, 101], "su_zhi": [102, 101], "lao_zhou": [103, 101],
	}
	var locations: Dictionary = {}
	for definition: Dictionary in settings.place_defs:
		locations[definition.id] = {
			"label": definition.label,
			"cell": [100 + int(definition.offset[0]), 100 + int(definition.offset[1])],
		}
	var sim := Simulation.new()
	if not sim.initialize(content, settings, cells, locations):
		runner.assert_true(false, "village fixture initializes: %s" % str(sim.errors))
		return null
	sim.set_navigation(_manhattan_path)
	return sim


func _manhattan_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = [from_cell]
	var cursor: Vector2i = from_cell
	while cursor.x != to_cell.x:
		cursor.x += 1 if cursor.x < to_cell.x else -1
		result.append(cursor)
	while cursor.y != to_cell.y:
		cursor.y += 1 if cursor.y < to_cell.y else -1
		result.append(cursor)
	return result


func _finish_action(sim: VillageSimulation, actor: String, runner: Object) -> void:
	var limit: int = sim.tick_index + int(sim.config.action_timeout) + 2
	while not sim.actors[actor].active.is_empty() and sim.tick_index < limit:
		sim.step()
	runner.assert_true(sim.actors[actor].active.is_empty(), "action reaches a terminal state")


func _advance_to_work(sim: VillageSimulation, actor: String, runner: Object) -> void:
	var limit: int = sim.tick_index + int(sim.config.action_timeout) + 2
	while not sim.actors[actor].active.is_empty() and sim.tick_index < limit:
		if sim.actors[actor].active.phase == "work":
			return
		sim.step()
	runner.assert_true(false, "action reaches work phase before completion or timeout")


func _total_item(sim: VillageSimulation, item: String) -> int:
	var amount: int = 0
	for container: String in sim.inventory.containers:
		amount += sim.inventory.quantity(container, item)
	return amount


func _json_state(sim: VillageSimulation) -> String:
	# JSON decoding represents integer literals as floats; normalize both sides.
	var encoded: String = JSON.stringify(sim.to_dict(), "", true, true)
	return JSON.stringify(JSON.parse_string(encoded), "", true, true)


func _test_haul_takes_time_and_conserves(runner: Object) -> void:
	var sim: VillageSimulation = _make_simulation(runner)
	if sim == null:
		return
	var wood: int = _total_item(sim, "wood")
	var original_cell: Array = sim.actors.player.cell.duplicate()
	runner.assert_true(sim.submit_action("player", "deliver_wood"), "player can start hauling")
	runner.assert_eq(sim.inventory.quantity("kitchen", "wood"), 0, "start does not teleport goods")
	sim.advance_to_ms(50)
	runner.assert_eq(sim.actors.player.cell, original_cell, "fifty milliseconds cannot skip travel time")
	runner.assert_true(not sim.actors.player.active.is_empty(), "haul remains in progress")
	runner.assert_eq(_total_item(sim, "wood"), wood, "hauling reserves rather than copies wood")
	_finish_action(sim, "player", runner)
	runner.assert_eq(sim.inventory.quantity("kitchen", "wood"), 3, "arrival delivers actual wood")
	runner.assert_eq(_total_item(sim, "wood"), wood, "completed hauling preserves wood")
	runner.assert_true(sim.tick_index > int(sim.config.actions.deliver_wood.minutes), "travel costs time")
	runner.assert_eq(sim.inventory.reservations.size(), 0, "completed haul frees reservations")


func _test_cancel_never_copies_resources(runner: Object) -> void:
	var sim: VillageSimulation = _make_simulation(runner)
	if sim == null:
		return
	var wood: int = _total_item(sim, "wood")
	sim.submit_action("player", "deliver_wood")
	sim.cancel_action("player")
	runner.assert_eq(sim.inventory.reservations.size(), 0, "cancel before pickup frees stock")
	runner.assert_eq(_total_item(sim, "wood"), wood, "cancel before pickup creates nothing")
	sim.submit_action("player", "deliver_wood")
	var limit: int = sim.tick_index + int(sim.config.action_timeout)
	while sim.inventory.quantity("actor:player", "wood") == 0 and sim.tick_index < limit:
		sim.step()
	runner.assert_eq(sim.inventory.quantity("actor:player", "wood"), 3, "pickup moves goods into bag")
	sim.cancel_action("player")
	sim.cancel_action("player")
	runner.assert_eq(sim.inventory.quantity("actor:player", "wood"), 3, "cancel keeps carried goods")
	runner.assert_eq(_total_item(sim, "wood"), wood, "repeated cancel cannot refund duplicate goods")
	runner.assert_eq(sim.inventory.reservations.size(), 0, "cancel after pickup leaks no reservation")


func _test_knowledge_stays_with_witnesses(runner: Object) -> void:
	var sim: VillageSimulation = _make_simulation(runner)
	if sim == null:
		return
	sim.set_actor_cell("su_zhi", SimRouteTravel.cell([140, 140]))
	var event_id: String = sim.observe("test_exchange", "player", "a_he", {
		"item": "wood", "amount": 1, "private": {"reason": "hidden_motive"},
	})
	runner.assert_true(sim.social.knowledge.player.has(event_id), "participant knows event")
	runner.assert_true(sim.social.knowledge.shi_tou.has(event_id), "nearby witness sees exchange")
	runner.assert_true(not sim.social.knowledge.su_zhi.has(event_id), "distant actor is not omniscient")
	var known: Dictionary = sim.social.knowledge.shi_tou[event_id]
	runner.assert_true(not known.details.has("private"), "witness cannot see hidden motive")
	runner.assert_true(sim.social.learn("su_zhi", event_id, "shi_tou"), "informant can pass knowledge")
	runner.assert_eq(sim.social.knowledge.su_zhi[event_id].source, "shi_tou", "hearsay names source")
	runner.assert_true(not sim.social.knowledge.su_zhi[event_id].direct, "hearsay is not direct sight")


func _test_repeated_request_cannot_repeat_execution(runner: Object) -> void:
	var sim: VillageSimulation = _make_simulation(runner)
	if sim == null:
		return
	# Ensure the example is a stable willing helper rather than a random outcome.
	sim.config.social_policy.bias = 1.0
	sim.config.social_policy.uncertainty_band = 0.0
	# The requester is close enough to ask, but cannot witness distant delivery.
	# Thus the original request context remains unchanged when it is retried.
	sim.set_actor_cell("a_he", SimRouteTravel.cell([113, 101]))
	var original: Array = sim.actors.shi_tou.cell.duplicate()
	var energy: float = sim.actors.shi_tou.energy
	var hunger: float = sim.actors.shi_tou.hunger
	var accepted: Dictionary = sim.request_help("a_he", "shi_tou")
	runner.assert_eq(accepted.status, "accepted", "willing helper accepts request")
	_finish_action(sim, "shi_tou", runner)
	var delivered: int = sim.inventory.quantity("kitchen", "wood")
	var action_count: int = sim.inventory.operations.size()
	# Restore the same visible situation; the same agreement must remain settled.
	sim.set_actor_cell("shi_tou", SimRouteTravel.cell(original))
	sim.actors.shi_tou.energy = energy
	sim.actors.shi_tou.hunger = hunger
	var repeated: Dictionary = sim.request_help("a_he", "shi_tou")
	runner.assert_eq(repeated.id, accepted.id, "unchanged request keeps the same decision id")
	runner.assert_true(sim.actors.shi_tou.active.is_empty(), "cached request cannot restart execution")
	for index: int in range(20):
		sim.step()
	runner.assert_eq(sim.inventory.quantity("kitchen", "wood"), delivered, "repeat delivers no extra wood")
	runner.assert_eq(sim.inventory.operations.size(), action_count, "repeat creates no extra transfers")


func _test_reporting_creates_institutional_credit(runner: Object) -> void:
	var sim: VillageSimulation = _make_simulation(runner)
	if sim == null:
		return
	sim.submit_action("player", "deliver_wood")
	_finish_action(sim, "player", runner)
	runner.assert_eq(sim.institutions.balance("sect", "player"), 0, "finished work awaits registration")
	runner.assert_true(not sim.actors.player.has("contribution"), "contribution is not an actor property")
	runner.assert_true(not sim.actors.player.receipts.is_empty(), "work leaves a reportable receipt")
	sim.set_actor_cell("player", SimRouteTravel.cell(sim.actors.chen_shouzhuo.cell.duplicate()))
	runner.assert_true(sim.report_work("player"), "nearby registrar accepts work evidence")
	runner.assert_eq(sim.institutions.balance("sect", "player"), 2, "registrar records institutional credit")
	runner.assert_eq(sim.actors.player.receipts.size(), 0, "registered receipt is settled")
	sim.report_work("player")
	runner.assert_eq(sim.institutions.balance("sect", "player"), 2, "repeated report cannot mint credit")


func _test_inflight_snapshot_continues_and_rejects_damage(runner: Object) -> void:
	var sim: VillageSimulation = _make_simulation(runner)
	var restored: VillageSimulation = _make_simulation(runner)
	if sim == null or restored == null:
		return
	sim.submit_action("player", "deliver_wood")
	sim.advance_to_ms(100)
	var snapshot: Dictionary = JSON.parse_string(_json_state(sim))
	runner.assert_true(restored.restore(snapshot), "active route and reservation restore")
	var limit: int = sim.tick_index + int(sim.config.action_timeout) + 2
	while not sim.actors.player.active.is_empty() and sim.tick_index < limit:
		sim.step()
		restored.step()
	runner.assert_true(sim.actors.player.active.is_empty(), "original inflight action terminates")
	runner.assert_true(restored.actors.player.active.is_empty(), "loaded inflight action terminates")
	runner.assert_eq(_json_state(restored), _json_state(sim), "inflight load continues identically")
	var before: String = _json_state(restored)
	var damaged: Dictionary = restored.to_dict()
	damaged.actors.player.hunger = -1
	runner.assert_true(not restored.restore(damaged), "invalid actor needs reject whole snapshot")
	runner.assert_eq(_json_state(restored), before, "failed load leaves running world unchanged")
	damaged = snapshot.duplicate(true)
	damaged.inventory.reservations.clear()
	runner.assert_true(not restored.restore(damaged), "orphan active reservation is rejected")
	runner.assert_eq(_json_state(restored), before, "bad active action cannot partly load")


func _test_office_succession_preserves_memory_and_accounts(runner: Object) -> void:
	var sim: VillageSimulation = _make_simulation(runner)
	if sim == null:
		return
	var event_id: String = sim.observe("help", "chen_shouzhuo", "player", {"task": "inspect"})
	sim.social.remember_outcome("player", "chen_shouzhuo", "fulfilled", event_id)
	var memory: Dictionary = sim.social.relation("player", "chen_shouzhuo")
	sim.institutions.issue("test_credit", "sect", "chen_shouzhuo", "player", 4, event_id)
	runner.assert_true(sim.grant_access("chen_shouzhuo", "player", "gate"), "authorized office grants access")
	runner.assert_true(sim.institutions.appoint("sect", "registrar", "su_zhi"), "office changes holder")
	runner.assert_eq(sim.institutions.balance("sect", "player"), 4, "new registrar inherits existing account")
	runner.assert_eq(
		sim.social.relation("player", "chen_shouzhuo"), memory, "office change preserves private history"
	)
	runner.assert_true(
		not sim.institutions.has_permission("sect", "chen_shouzhuo", "record"), "old holder loses signing power"
	)
	runner.assert_true(sim.has_access("player", "gate"), "office change does not silently revoke access")


func _test_clock_speed_does_not_change_tick_outcome(runner: Object) -> void:
	var slow: VillageSimulation = _make_simulation(runner)
	var fast: VillageSimulation = _make_simulation(runner)
	if slow == null or fast == null:
		return
	slow.submit_action("player", "deliver_wood")
	fast.submit_action("player", "deliver_wood")
	var slow_clock := Clock.new()
	var fast_clock := Clock.new()
	slow_clock.tick.connect(func(_tick: int) -> void: slow.step())
	fast_clock.tick.connect(func(_tick: int) -> void: fast.step())
	fast_clock.set_speed(4.0)
	for frame: int in range(120):
		slow_clock._process(0.125)
	for frame: int in range(30):
		fast_clock._process(0.125)
	runner.assert_eq(fast_clock.tick_index, slow_clock.tick_index, "4x needs one quarter real duration")
	runner.assert_eq(_json_state(fast), _json_state(slow), "equal tick input yields equal simulation state")
	slow_clock.free()
	fast_clock.free()


func _test_three_autonomous_days_release_reservations(runner: Object) -> void:
	var sim: VillageSimulation = _make_simulation(runner, true)
	if sim == null:
		return
	for minute: int in range(3 * 1440):
		sim.step()
	runner.assert_eq(sim.tick_index, 4320, "autonomous village advances three game days")
	runner.assert_true(sim.errors.is_empty(), "autonomous world records no simulation error")
	runner.assert_true(sim.social.events.size() > 6, "autonomous actors complete meaningful activity")
	for id: String in sim.actors:
		sim.actors[id].autonomous = false
		sim.cancel_action(id)
	runner.assert_eq(sim.inventory.reservations.size(), 0, "ending actions frees every reservation")
	for container: String in sim.inventory.containers:
		for item: String in sim.inventory.containers[container]:
			runner.assert_true(sim.inventory.quantity(container, item) >= 0, "three-day inventory stays nonnegative")
	var restored: VillageSimulation = _make_simulation(runner)
	if restored != null:
		runner.assert_true(restored.restore(sim.to_dict()), "long-running village remains valid for saving")


func _test_unreachable_action_releases_reservation(runner: Object) -> void:
	var sim: VillageSimulation = _make_simulation(runner)
	if sim == null:
		return
	sim.set_navigation(func(_from: Vector2i, _to: Vector2i) -> Array[Vector2i]:
		var no_path: Array[Vector2i] = []
		return no_path
	)
	var before: Dictionary = sim.inventory.to_dict()
	runner.assert_true(not sim.submit_action("player", "deliver_wood"), "unreachable job cannot start")
	runner.assert_true(sim.actors.player.active.is_empty(), "failed route creates no active job")
	runner.assert_eq(sim.inventory.to_dict(), before, "failed route releases stock without moving it")


func _test_cancelled_last_meal_can_be_eaten(runner: Object) -> void:
	var sim: VillageSimulation = _make_simulation(runner)
	if sim == null:
		return
	var meals: int = sim.inventory.quantity("kitchen", "meal")
	sim.inventory.consume("fixture:leave_last_meal", "kitchen", "meal", meals - 1)
	sim.set_actor_cell("player", SimRouteTravel.cell(sim.places.kitchen.cell.duplicate()))
	runner.assert_true(sim.submit_action("player", "eat"), "start eating the last kitchen meal")
	_advance_to_work(sim, "player", runner)
	runner.assert_eq(sim.inventory.quantity("kitchen", "meal"), 0, "last meal has left the kitchen")
	runner.assert_eq(sim.inventory.quantity("actor:player", "meal"), 1, "meal is actually in bag")
	sim.cancel_action("player")
	runner.assert_true(sim.submit_action("player", "eat"), "cancelled meal can be eaten from bag")
	runner.assert_eq(sim.inventory.reservations.size(), 0, "bag meal needs no kitchen reservation")
	var hunger: float = sim.actors.player.hunger
	_finish_action(sim, "player", runner)
	runner.assert_eq(_total_item(sim, "meal"), 0, "resumed eating consumes the one real meal")
	runner.assert_true(float(sim.actors.player.hunger) > hunger, "resumed eating restores hunger")


func _test_cancelled_recipe_reuses_carried_ingredients(runner: Object) -> void:
	var sim: VillageSimulation = _make_simulation(runner)
	if sim == null:
		return
	sim.inventory.transfer("fixture:cooking_wood", "store", "kitchen", "wood", 1)
	sim.set_actor_cell("player", SimRouteTravel.cell(sim.places.kitchen.cell.duplicate()))
	runner.assert_true(sim.submit_action("player", "cook"), "recipe reserves initial ingredients")
	_advance_to_work(sim, "player", runner)
	var kitchen: Dictionary = sim.inventory.containers["kitchen"].duplicate(true)
	var carried: Dictionary = sim.inventory.containers["actor:player"].duplicate(true)
	for item: String in sim.config.actions.cook.inputs:
		runner.assert_eq(
			sim.inventory.quantity("actor:player", item),
			int(sim.config.actions.cook.inputs[item]), "recipe ingredients move into bag"
		)
	sim.cancel_action("player")
	runner.assert_true(sim.submit_action("player", "cook"), "cancelled recipe uses existing bag inputs")
	runner.assert_eq(sim.inventory.reservations.size(), 0, "carried recipe needs no extra stock")
	_advance_to_work(sim, "player", runner)
	runner.assert_eq(sim.inventory.containers["kitchen"], kitchen, "resume does not take more ingredients")
	runner.assert_eq(sim.inventory.containers["actor:player"], carried, "resume keeps one ingredient batch")
	_finish_action(sim, "player", runner)
	for item: String in sim.config.actions.cook.inputs:
		runner.assert_eq(sim.inventory.quantity("actor:player", item), 0, "recipe consumes carried batch once")
	runner.assert_eq(
		sim.inventory.quantity("kitchen", "meal"), int(kitchen.meal) + 6,
		"resumed recipe produces exactly one batch"
	)


func _test_recipe_overflow_preserves_inputs_and_valid_state(runner: Object) -> void:
	var sim: VillageSimulation = _make_simulation(runner)
	if sim == null:
		return
	sim.inventory.transfer("fixture:overflow_wood", "store", "kitchen", "wood", 1)
	sim.set_actor_cell("player", SimRouteTravel.cell(sim.places.kitchen.cell.duplicate()))
	runner.assert_true(sim.submit_action("player", "cook"), "overflow test begins a real recipe")
	_advance_to_work(sim, "player", runner)
	# Simulate a full output container before this work batch commits.
	sim.inventory.containers["kitchen"]["meal"] = SimInventory.MAX_COUNT
	var carried: Dictionary = sim.inventory.containers["actor:player"].duplicate(true)
	_finish_action(sim, "player", runner)
	runner.assert_eq(
		sim.inventory.quantity("kitchen", "meal"), SimInventory.MAX_COUNT,
		"full output container cannot overflow"
	)
	runner.assert_eq(
		sim.inventory.containers["actor:player"], carried,
		"failed output preflight consumes no carried ingredients"
	)
	runner.assert_eq(sim.actors.player.receipts.size(), 0, "failed recipe earns no contribution receipt")
	runner.assert_eq(sim.inventory.reservations.size(), 0, "failed batch releases reservations")
	var restored: VillageSimulation = _make_simulation(runner)
	if restored != null:
		runner.assert_true(restored.restore(sim.to_dict()), "overflow rejection leaves a restorable world")


func _test_unneeded_deliveries_do_not_earn_contribution(runner: Object) -> void:
	var sim: VillageSimulation = _make_simulation(runner)
	if sim == null:
		return
	var original_wood: int = _total_item(sim, "wood")
	for delivery: int in range(2):
		runner.assert_true(sim.submit_action("player", "deliver_wood"), "needed wood delivery starts")
		_finish_action(sim, "player", runner)
	runner.assert_eq(sim.inventory.quantity("kitchen", "wood"), 6, "legitimate deliveries satisfy demand")
	runner.assert_true(sim.report_work("player"), "registrar accepts needed work")
	var credit: int = sim.institutions.balance("sect", "player")
	runner.assert_eq(credit, 4, "needed work receives its advertised contribution")
	for delivery: int in range(2):
		runner.assert_true(sim.submit_action("player", "deliver_wood"), "extra delivery remains a real action")
		_finish_action(sim, "player", runner)
		runner.assert_eq(sim.actors.player.receipts.size(), 0, "unneeded delivery creates no credit receipt")
		sim.report_work("player")
		runner.assert_eq(sim.institutions.balance("sect", "player"), credit, "extra reports cannot farm credit")
	runner.assert_eq(_total_item(sim, "wood"), original_wood, "extra hauling still conserves resources")


func _test_promotion_requires_authority_and_recorded_credit(runner: Object) -> void:
	var sim: VillageSimulation = _make_simulation(runner)
	if sim == null:
		return
	runner.assert_true(
		not sim.approve_promotion("chen_shouzhuo", "player", "outer_disciple"),
		"authorized issuer still needs recorded contribution"
	)
	var threshold: int = 100
	runner.assert_true(
		sim.institutions.issue(
			"fixture:promotion_credit", "sect", "chen_shouzhuo", "player", threshold,
			"fixture:recognized_work"
		), "promotion fixture records institutional entitlement"
	)
	runner.assert_true(
		not sim.approve_promotion("shi_tou", "player", "outer_disciple"),
		"friend without authorization cannot approve promotion"
	)
	runner.assert_eq(sim.actors.player.rank_id, "servant", "unauthorized promotion keeps old rank")
	runner.assert_true(
		sim.approve_promotion("chen_shouzhuo", "player", "outer_disciple"),
		"authorized issuer can recognize eligible promotion"
	)
	runner.assert_eq(sim.actors.player.rank_id, "outer_disciple", "recognized promotion changes rank")
	runner.assert_true(
		not sim.approve_promotion("chen_shouzhuo", "player", "outer_disciple"),
		"same promotion cannot be applied twice"
	)
