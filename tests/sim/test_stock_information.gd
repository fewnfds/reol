extends RefCounted

const Fixtures = preload("res://tests/sim/test_village_simulation.gd")
var _fixtures: RefCounted = Fixtures.new()


func run(runner: Object) -> void:
	_test_statement_changes_belief_not_stock(runner)
	_test_order_restore_and_damage(runner)
	_test_distrusted_source_is_still_remembered(runner)


func _scenario(runner: Object) -> VillageSimulation:
	var sim: VillageSimulation = _fixtures._make_simulation(runner)
	if sim == null:
		return null
	sim.set_actor_cell("player", Vector2i(110, 100))
	sim.set_actor_cell("su_zhi", SimRouteTravel.cell([110, 101]))
	sim.set_actor_cell("shi_tou", SimRouteTravel.cell([111, 100]))
	runner.assert_true(sim.advance_to(26), "information scenario advances all original processes to the conversation time")
	var grain: int = sim.inventory.quantity("kitchen", "grain")
	sim.inventory.consume("fixture:grain_shortage", "kitchen", "grain", grain)
	return sim


func _test_statement_changes_belief_not_stock(runner: Object) -> void:
	var sim: VillageSimulation = _scenario(runner)
	if sim == null:
		return
	var unknown: Dictionary = sim.stock_understanding("su_zhi", "kitchen", "grain")
	runner.assert_true(not bool(unknown.known) and not unknown.has("amount"), "unknown stock is not represented as zero")
	var inventory: String = JSON.stringify(sim.inventory.to_dict(), "", true, true)
	var said: Dictionary = sim.tell_stock("player", "su_zhi", "kitchen", "grain", 6)
	runner.assert_true(bool(said.ok), "a person can make a false stock statement")
	var heard: Dictionary = sim.stock_understanding("su_zhi", "kitchen", "grain")
	runner.assert_true(bool(heard.known), "the addressed listener has an attributed belief")
	runner.assert_eq(heard.amount, 6, "a listener can expect supplies that do not actually exist")
	runner.assert_eq(heard.basis, "said", "testimony is distinguishable from personal observation")
	runner.assert_eq(heard.source, "player", "belief retains who supplied the claim")
	runner.assert_eq(JSON.stringify(sim.inventory.to_dict(), "", true, true), inventory, "a statement does not change physical warehouse quantities")
	runner.assert_true(not bool(sim.stock_understanding("chen_shouzhuo", "kitchen", "grain").known), "an uninformed third person does not receive private speech")
	runner.assert_true(not sim._needed("su_zhi", "deliver_grain"), "NPC work need is evaluated from their mistaken belief")
	sim._choose_routine("su_zhi")
	runner.assert_true(sim.actors.su_zhi.active.is_empty(), "misinformed NPC actually refrains from an apparently unnecessary delivery")
	var before: String = _state(sim)
	for _index in 10:
		sim.stock_understanding("su_zhi", "kitchen", "grain")
	runner.assert_eq(_state(sim), before, "repeated information queries do not teach, mutate memory or consume randomness")
	var repeated: Dictionary = sim.tell_stock("player", "su_zhi", "kitchen", "grain", 6)
	runner.assert_eq(repeated.event, said.event, "same repeated statement reuses its existing occurrence")
	runner.assert_eq(_state(sim), before, "repeated statement does not mint another event or change RNG")
	# A recent personal inspection leads a different listener to another judgment.
	sim.set_actor_cell("shi_tou", SimRouteTravel.cell(sim.places.kitchen.cell.duplicate()))
	sim._observe_stock("shi_tou")
	sim.set_actor_cell("shi_tou", SimRouteTravel.cell([111, 100]))
	runner.assert_true(bool(sim.tell_stock("player", "shi_tou", "kitchen", "grain", 6).ok), "the same report can be heard by a second observer")
	var inspected: Dictionary = sim.stock_understanding("shi_tou", "kitchen", "grain")
	runner.assert_eq(inspected.amount, 0, "recent direct inspection outweighs conflicting testimony")
	runner.assert_true(bool(inspected.conflicted), "conflicting accounts remain inspectable instead of overwriting history")
	runner.assert_true(bool(sim.ask_stock("a_he", "su_zhi", "kitchen", "grain").ok), "a misinformed NPC answers from what they believe")
	runner.assert_eq(sim.stock_understanding("a_he", "kitchen", "grain").amount, 6, "NPC answer transmits the false expectation rather than reading warehouse truth")
	sim.set_actor_cell("su_zhi", SimRouteTravel.cell(sim.places.kitchen.cell.duplicate()))
	sim._observe_stock("su_zhi")
	runner.assert_eq(sim.stock_understanding("su_zhi", "kitchen", "grain").amount, 0, "checking the actual kitchen corrects one's own expectation")
	runner.assert_true(sim._needed("su_zhi", "deliver_grain"), "corrected understanding changes the NPC's work choice")
	runner.assert_eq(sim.stock_understanding("a_he", "kitchen", "grain").amount, 6, "one person's correction does not telepathically update another")
	sim.set_actor_cell("su_zhi", SimRouteTravel.cell([110, 101]))
	runner.assert_true(sim.advance_to(147), "report expiry advances the original world rather than only its clock")
	runner.assert_true(not bool(sim.stock_understanding("su_zhi", "kitchen", "grain").known), "expired reports become uncertainty rather than permanent fact")
	sim._choose_routine("su_zhi")
	runner.assert_eq(sim.actors.su_zhi.active.get("action"), "check_kitchen", "uncertainty sends an autonomous worker to inspect instead of querying hidden stock")
	print("SCENARIO finite information: false report→different beliefs→different work→personal verification; no global correction")


func _test_order_restore_and_damage(runner: Object) -> void:
	var sim: VillageSimulation = _scenario(runner)
	if sim == null:
		return
	sim.tell_stock("player", "su_zhi", "kitchen", "grain", 6)
	sim.tell_stock("player", "su_zhi", "kitchen", "grain", 0)
	for _index in 7:
		sim.social.record("conversation", "player", "su_zhi", {}, [], sim.tick_index)
	var last: Dictionary = sim.tell_stock("player", "su_zhi", "kitchen", "grain", 6)
	runner.assert_eq(last.event, "event_10", "changed testimony creates a new occurrence after intervening correction")
	runner.assert_eq(sim.stock_understanding("su_zhi", "kitchen", "grain").amount, 6, "same-tick evidence uses stable numeric event order")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(sim.to_dict(), "", true, true))
	var loaded: VillageSimulation = _scenario(runner)
	runner.assert_true(loaded.restore(saved), "existing snapshot stores statements and sources without inventing a second ledger")
	runner.assert_eq(loaded.stock_understanding("su_zhi", "kitchen", "grain").amount, 6, "JSON key sorting cannot change which same-tick report is newer")
	var source_state: String = _state(loaded)
	var bad: Dictionary = saved.duplicate(true)
	for event: Dictionary in bad.social.events:
		if event.id == "event_10":
			event.details.participants.amount = -1
	for observer: String in ["player", "su_zhi"]:
		bad.social.knowledge[observer]["event_10"].details.amount = -1
	var social_only := SimSocialMemory.new()
	runner.assert_true(social_only.restore(bad.social), "generic event provenance can validly describe a negative spoken number")
	runner.assert_true(not loaded.restore(bad), "stock-claim semantics reject an invalid supported quantity")
	runner.assert_eq(_state(loaded), source_state, "semantically invalid claim cannot partly replace a live world")
	bad = saved.duplicate(true)
	bad.social.knowledge.su_zhi["event_10"].source = "chen_shouzhuo"
	bad.social.knowledge.su_zhi["event_10"].direct = false
	runner.assert_true(not loaded.restore(bad), "invented informant with no source knowledge is rejected")
	runner.assert_eq(_state(loaded), source_state, "forged provenance preserves live state")
	for _index in 160:
		sim.step()
	runner.assert_true(loaded.advance_to(sim.tick_index), "restored finite knowledge can use distant quiet-interval scheduling")
	runner.assert_eq(_state(loaded), _state(sim), "fine and batched continuation agree after information ages out")


func _test_distrusted_source_is_still_remembered(runner: Object) -> void:
	var sim: VillageSimulation = _scenario(runner)
	if sim == null:
		return
	var statement: Dictionary = sim.tell_stock("player", "su_zhi", "kitchen", "grain", 6)
	for _index in 4:
		var event: String = sim.social.record("promise_broken", "player", "su_zhi", {}, [], sim.tick_index)
		runner.assert_true(sim.social.remember_outcome("su_zhi", "player", "broke_promise", event), "personal experience can reduce trust in the speaker")
	var belief: Dictionary = sim.stock_understanding("su_zhi", "kitchen", "grain")
	runner.assert_true(not bool(belief.known), "a distrusted source is not adopted as sufficient knowledge")
	runner.assert_true(sim.social.knowledge.su_zhi.has(statement.event), "disbelieving a source does not erase the occurrence of their statement")
	runner.assert_eq(belief.accounts.size(), 1, "rejected testimony remains attributed for later inspection")
	var restored: VillageSimulation = _scenario(runner)
	runner.assert_true(restored.restore(JSON.parse_string(JSON.stringify(sim.to_dict()))), "trust history and rejected testimony restore together")
	runner.assert_true(not bool(restored.stock_understanding("su_zhi", "kitchen", "grain").known), "reload cannot turn distrusted testimony into fact")


func _state(sim: VillageSimulation) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(sim.to_dict(), "", true, true)), "", true, true)
