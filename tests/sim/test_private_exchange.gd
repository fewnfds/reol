extends RefCounted
## Controlled rule probes: positions and policy are explicit test conditions.
## The ring itself always comes from the real timed take and original custody.

const Drawing = preload("res://tests/sim/test_artifact_drawing.gd")
const RING: String = "stele_drawing_ring"
const BUYER: String = "player"
const SELLER: String = "river_shi_tou"
var fixtures := Drawing.new()


func run(runner: Object) -> void:
	_timed_original_transfer(runner, SELLER)
	_timed_original_transfer(runner, "shi_tou")
	_cancel_and_stable_proposal(runner)
	_refused_proposal(runner)
	_preconditions_and_competition(runner)
	_invalidated_delivery(runner)
	_candidate_integrity(runner)
	print("SCENARIO private exchange: original same/cross-region cash and unique ring, timed revocable consent, stable refusal, competition, interruption and independent atomic restore")


func _world(runner: Object, seller: String = SELLER, accept: bool = true) -> RegionalSimulation:
	var world: RegionalSimulation = fixtures._world(runner)
	if world == null:
		return null
	# These controlled policy values let each branch assert a definite result;
	# ordinary unchanged opening acceptance is verified by the product replay.
	world.private_exchange.definitions.policy.accept_threshold = -10.0 if accept else 10.0
	world.private_exchange.definitions.policy.uncertainty_band = 0.0
	world._content.private_exchange = world.private_exchange.definitions.duplicate(true)
	fixtures._at_site(world, seller)
	if not fixtures._action(runner, world, seller, "take"):
		return null
	world.regions[world.private_exchange.home(seller)].cancel_action(seller, "controlled_fixture_idle")
	world.private_exchange.body(seller).autonomous = true
	world.private_exchange.body(seller).retry_ms = world.elapsed_ms + 60000
	fixtures._put(world, BUYER, SimRouteTravel.cell(world.private_exchange.body(seller).cell) + Vector2i(1, 0))
	return world


func _start(runner: Object, world: RegionalSimulation, seller: String = SELLER) -> String:
	var reply: Dictionary = world.private_exchange.request(BUYER, seller, RING)
	runner.assert_true(bool(reply.get("ok", false)), "actual present parties accept one explicit timed bargain: " + str(reply))
	return str(reply.get("id", "")) if bool(reply.get("ok", false)) else ""


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _coin(world: RegionalSimulation, actor: String) -> int:
	return world.regions[world.private_exchange.home(actor)].inventory.quantity("actor:" + actor, "coin")


func _total(world: RegionalSimulation) -> int:
	var count: int = 0
	for sim: VillageSimulation in world.regions.values():
		for container: String in sim.inventory.containers:
			count += sim.inventory.quantity(container, "coin")
	return count


func _timed_original_transfer(runner: Object, seller: String) -> void:
	var world: RegionalSimulation = _world(runner, seller)
	if world == null:
		return
	var buyer_coin: int = _coin(world, BUYER)
	var seller_coin: int = _coin(world, seller)
	var total: int = _total(world)
	var price: int = int(world.private_exchange.definitions.price)
	var id: String = _start(runner, world, seller)
	if id.is_empty():
		return
	var job: Dictionary = world.private_exchange.jobs[id]
	runner.assert_true(world.private_exchange.owns_actor(BUYER) and world.private_exchange.owns_actor(seller), "the one bargain owns both original bodies")
	runner.assert_true(world.artifacts.target_in_use(RING), "other artifact users see the same original ring lock")
	runner.assert_eq(_coin(world, BUYER), buyer_coin, "acceptance reserves but does not pay")
	runner.assert_eq(_coin(world, seller), seller_coin, "acceptance creates no seller money")
	runner.assert_eq(world.artifacts.objects[RING].container, "actor:" + seller, "agreement is not already possession")
	runner.assert_eq(world.private_exchange.body(BUYER).active, {}, "there is no duplicate village work behind the exchange")
	runner.assert_true(world.advance_to_ms(int(job.due_ms) - 1), "the last incomplete millisecond can be reached")
	runner.assert_eq(_coin(world, BUYER), buyer_coin, "money stays in the original buyer purse until completion")
	runner.assert_eq(world.artifacts.objects[RING].container, "actor:" + seller, "unique original ring remains with seller until completion")
	runner.assert_true(world.advance_to_ms(int(job.due_ms)), "the shared exact deadline commits the bargain")
	runner.assert_eq(job.status, "completed", "real delivery records one completed result")
	runner.assert_eq(_coin(world, BUYER), buyer_coin - price, "buyer pays the exact quoted original coins")
	runner.assert_eq(_coin(world, seller), seller_coin + price, "seller receives the same original coins")
	runner.assert_eq(_total(world), total, "same/cross-region transfer conserves all original cash")
	runner.assert_eq(world.artifacts.objects[RING].region, "home", "ring follows the original buyer registered container")
	runner.assert_eq(world.artifacts.objects[RING].container, "actor:player", "one physical ring reaches the original buyer")
	runner.assert_true(not world.private_exchange.owns_actor(BUYER) and not world.private_exchange.owns_actor(seller), "completion releases both original bodies")
	world.private_exchange.settle_at_ms(world.elapsed_ms)
	runner.assert_eq(_coin(world, BUYER), buyer_coin - price, "duplicate settlement cannot pay twice")
	runner.assert_true(world.field_opportunities.cross_valid(), "site observations still follow the actual custody chain")
	runner.assert_true(SimArtifacts.Schema.cross_valid(world.artifacts), "exchange source and artifact history agree in both directions")
	var candidate: RegionalSimulation = _world(runner, seller)
	if candidate != null:
		var saved: String = _json(world.to_dict())
		runner.assert_true(candidate.restore(JSON.parse_string(saved)), "completed original cash and custody restore as one candidate")
		runner.assert_eq(_json(candidate.to_dict()), saved, "restored transfer changes no original state")
	# A purchase grants custody, not the seller's private understanding.
	runner.assert_true(not world.artifacts.learned_use(BUYER, RING), "buying the ring does not grant another person's mastery")
	runner.assert_true(fixtures._action(runner, world, BUYER, "study"), "buyer can personally study the same transferred object")
	runner.assert_true(fixtures._action(runner, world, BUYER, "use_research"), "buyer can genuinely research its use after the handover")
	runner.assert_true(world.artifacts.learned_use(BUYER, RING), "only completed personal research grants use knowledge")
	runner.assert_true(SimArtifacts.Schema.cross_valid(world.artifacts), "later research has a valid original transfer predecessor")


func _cancel_and_stable_proposal(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var total: int = _total(world)
	var buyer_coin: int = _coin(world, BUYER)
	var id: String = _start(runner, world)
	if id.is_empty():
		return
	var proposal: String = str(world.private_exchange.jobs[id].proposal)
	var prior: String = _json(world.services.social.requests)
	var original_consent: String = str(world.private_exchange.jobs[id].consent)
	world.private_exchange.cancel(BUYER, "player_cancelled")
	runner.assert_eq(world.private_exchange.jobs[id].status, "cancelled", "buyer can stop before delivery")
	runner.assert_eq(_coin(world, BUYER), buyer_coin, "cancel pays no money")
	runner.assert_eq(_total(world), total, "cancel conserves original cash")
	runner.assert_eq(world.artifacts.objects[RING].container, "actor:" + SELLER, "cancel leaves original ring with seller")
	runner.assert_true(not world.artifacts.target_in_use(RING), "cancel releases the shared object lock")
	var next_id: String = _start(runner, world)
	if next_id.is_empty():
		return
	runner.assert_true(next_id != id, "another present request needs fresh process consent")
	runner.assert_eq(str(world.private_exchange.jobs[next_id].proposal), proposal, "same deal reuses its stable proposal")
	runner.assert_eq(_json(world.services.social.requests), prior, "repeating accepted terms does not reroll or rewrite the original decision")
	runner.assert_true(world.private_exchange.jobs[next_id].consent != original_consent, "another handover records fresh present consent")
	world.private_exchange.cancel(SELLER, "seller_withdrew")
	var denied: Dictionary = world.private_exchange.request(BUYER, SELLER, RING)
	runner.assert_true(not bool(denied.get("ok", false)), "seller's withdrawal cannot be bypassed with old acceptance")


func _refused_proposal(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, SELLER, false)
	if world == null:
		return
	var first: Dictionary = world.private_exchange.request(BUYER, SELLER, RING)
	runner.assert_eq(first.get("code"), "refused", "controlled unwilling seller may reject an affordable bargain")
	var stable: String = _json(world.services.social.to_dict())
	world.private_exchange.body(SELLER).energy -= 0.1
	var again: Dictionary = world.private_exchange.request(BUYER, SELLER, RING)
	runner.assert_eq(again.get("code"), "refused", "unrelated energy drift does not reset the refused deal")
	runner.assert_eq(_json(world.services.social.to_dict()), stable, "repeat refusal consumes no second random decision")
	runner.assert_true(world.private_exchange.jobs.is_empty(), "refusal creates no body process")
	runner.assert_eq(world.artifacts.objects[RING].container, "actor:" + SELLER, "refusal leaves the ring with its owner")


func _preconditions_and_competition(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var ledger: SimInventory = world.regions.home.inventory
	var price: int = int(world.private_exchange.definitions.price)
	var coins: int = _coin(world, BUYER)
	runner.assert_true(ledger.reserve("test:other", "actor:player", "coin", coins, BUYER), "another real reservation can occupy the purse first")
	runner.assert_true(not world.private_exchange.request(BUYER, SELLER, RING).ok, "a competing reservation is not spendable cash")
	ledger.release("test:other")
	var original: Vector2i = SimRouteTravel.cell(world.private_exchange.body(BUYER).cell)
	fixtures._put(world, BUYER, original + Vector2i(30, 0))
	runner.assert_true(world.private_exchange.offered_objects(BUYER, SELLER).is_empty(), "distant held ring is not exposed as a proposal object")
	runner.assert_true(not world.private_exchange.request(BUYER, SELLER, RING).ok, "a proposal cannot reach a distant person")
	fixtures._put(world, BUYER, original)
	var seller_ledger: SimInventory = world.regions.river.inventory
	seller_ledger.containers["actor:" + SELLER]["coin"] = SimInventory.MAX_COUNT
	runner.assert_true(not world.private_exchange.request(BUYER, SELLER, RING).ok, "full seller purse cannot accept even a willing delivery")
	seller_ledger.containers["actor:" + SELLER].erase("coin")
	ledger.containers["actor:player"]["coin"] = price - 1
	runner.assert_true(not world.private_exchange.request(BUYER, SELLER, RING).ok, "insufficient original balance cannot start a bargain")
	ledger.containers["actor:player"]["coin"] = coins
	var id: String = _start(runner, world)
	if id.is_empty():
		return
	fixtures._put(world, "shi_tou", original)
	runner.assert_true(not world.private_exchange.request("shi_tou", SELLER, RING).ok, "two buyers cannot share one seller or ring")
	runner.assert_true(not world.artifacts.begin(SELLER, "study", RING).ok, "the original owner cannot use a ring during its reserved handover")
	world.private_exchange.cancel(BUYER)


func _invalidated_delivery(runner: Object) -> void:
	for fault: String in ["move", "control", "missing_reservation", "full_purse"]:
		var world: RegionalSimulation = _world(runner)
		if world == null:
			continue
		var before: int = _coin(world, BUYER)
		var id: String = _start(runner, world)
		if id.is_empty():
			continue
		var job: Dictionary = world.private_exchange.jobs[id]
		match fault:
			"move": fixtures._put(world, SELLER, SimRouteTravel.cell(world.private_exchange.body(SELLER).cell) + Vector2i(1, 0))
			"control": world.private_exchange.body(SELLER).alive = false
			"missing_reservation": world.regions.home.inventory.release(str(job.reservation))
			"full_purse": world.regions.river.inventory.containers["actor:" + SELLER]["coin"] = SimInventory.MAX_COUNT
		world.private_exchange.settle_at_ms(world.elapsed_ms)
		runner.assert_true(job.status != "active" and job.status != "completed", "changed real condition stops delivery: " + fault)
		runner.assert_eq(_coin(world, BUYER), before, "failed delivery cannot partially charge: " + fault)
		runner.assert_eq(world.artifacts.objects[RING].container, "actor:" + SELLER, "failed delivery cannot partially transfer ring: " + fault)
		runner.assert_true(not world.artifacts.target_in_use(RING), "failed delivery releases ring: " + fault)


func _candidate_integrity(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var id: String = _start(runner, world)
	if id.is_empty():
		return
	var saved: Dictionary = world.to_dict()
	var candidate: RegionalSimulation = _world(runner)
	if candidate == null:
		return
	runner.assert_true(candidate.restore(JSON.parse_string(_json(saved))), "independent candidate restores ongoing body and original coin reservation")
	runner.assert_eq(_json(candidate.to_dict()), _json(saved), "inflight JSON restore preserves every world fact")
	for fault: String in ["missing_domain", "missing_consent", "wrong_object", "wrong_price", "missing_reservation", "wrong_position", "duplicate_job", "wrong_source"]:
		var bad: Dictionary = saved.duplicate(true)
		match fault:
			"missing_domain": bad.erase("private_exchange")
			"missing_consent": bad.private_exchange.jobs[id].erase("consent")
			"wrong_object": bad.private_exchange.jobs[id].object = "training_sword"
			"wrong_price": bad.private_exchange.proposals[str(bad.private_exchange.jobs[id].proposal)].price += 1
			"missing_reservation": bad.regions.home.inventory.reservations.erase(str(saved.private_exchange.jobs[id].reservation))
			"wrong_position": bad.private_exchange.jobs[id].buyer_position[0] += 0.25
			"duplicate_job": bad.private_exchange.jobs["forged"] = bad.private_exchange.jobs[id].duplicate(true)
			"wrong_source": bad.private_exchange.jobs[id].source_event = "artifact:event:99999"
		var stable: String = _json(candidate.to_dict())
		runner.assert_true(not candidate.restore(bad), "candidate rejects broken exchange cause: " + fault)
		runner.assert_eq(_json(candidate.to_dict()), stable, "bad candidate cannot replace live state: " + fault)
	runner.assert_true(candidate.advance_to_ms(int(saved.private_exchange.jobs[id].due_ms)), "genuine inflight candidate completes through the original deadline")
	var completed: Dictionary = candidate.to_dict()
	for fault: String in ["missing_transfer", "missing_artifact_half", "forged_recipient", "reused_action"]:
		var bad: Dictionary = completed.duplicate(true)
		match fault:
			"missing_transfer": bad.private_exchange.transfers.erase(str(bad.private_exchange.jobs[id].receipt))
			"missing_artifact_half": bad.artifacts.events = bad.artifacts.events.filter(func(row: Dictionary) -> bool: return row.get("exchange", "") != id)
			"forged_recipient":
				for event: Dictionary in bad.artifacts.events:
					if event.get("exchange", "") == id: event.recipient = SELLER
			"reused_action": bad.private_exchange.jobs[id].artifact_action = "artifact:action:1"
		var stable: String = _json(candidate.to_dict())
		runner.assert_true(not candidate.restore(bad), "completed cause cannot lose or forge half the handover: " + fault)
		runner.assert_eq(_json(candidate.to_dict()), stable, "invalid completed cause leaves all live history unchanged: " + fault)
