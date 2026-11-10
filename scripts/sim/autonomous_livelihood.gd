class_name SimAutonomousLivelihood
extends RefCounted
## A bounded personal purpose. Bodies, money, promises and attributed knowledge
## remain with their original authorities; this only remembers search/backoff.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const RESULTS: Array[String] = ["none", "searching", "unreachable", "no_contact", "declined", "working", "claiming", "buying", "returning", "waiting"]
var definitions: Dictionary = {}
var plans: Dictionary = {}
var _owner: WeakRef
var world: RefCounted:
	get:
		return _owner.get_ref()


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "actor_definitions", "desired_item", "desired_amount", "purchase_offer", "capability_claim", "conversation_topic", "backoff_ms", "search_actions", "visits"]) or data.version != 1 or not data.actor_definitions is Array or data.actor_definitions.is_empty() or not Shape.count(data.desired_amount, 1, 10) or not Shape.count(data.backoff_ms, 60000, 86400000) or not data.search_actions is Array or data.search_actions.is_empty() or not data.visits is Dictionary:
		return false
	for field: String in ["desired_item", "purchase_offer", "capability_claim", "conversation_topic"]:
		if not SimInventory._nonempty(data[field]):
			return false
	var seen: Dictionary = {}
	for id: Variant in data.actor_definitions:
		if not SimInventory._nonempty(id) or seen.has(id):
			return false
		seen[id] = true
	seen.clear()
	for id: Variant in data.search_actions:
		if not SimInventory._nonempty(id) or seen.has(id) or not data.visits.has(id):
			return false
		var action: Variant = data.visits[id]
		if not Shape.keys(action, ["label", "kind", "target", "minutes", "contribution"]) or not SimInventory._nonempty(action.label) or not SimInventory._nonempty(action.target) or action.kind != "visit" or not Shape.count(action.minutes, 1, 60) or action.contribution != 0:
			return false
		seen[id] = true
	return seen.size() == data.visits.size()


static func install(config: Variant, rules: Dictionary) -> bool:
	if not config is Dictionary or not config.get("actions") is Dictionary:
		return false
	for id: String in rules.visits:
		if config.actions.has(id) and not Shape.same_record(config.actions[id], rules.visits[id]):
			return false
	for id: String in rules.visits:
		config.actions[id] = rules.visits[id].duplicate(true)
	return true


func bind_world(authority: RefCounted) -> void:
	# Rebind a validated candidate without resetting its saved process.
	_owner = weakref(authority)


func initialize(authority: RefCounted, rules: Dictionary) -> bool:
	if authority == null or not valid_definitions(rules):
		return false
	_owner = weakref(authority)
	definitions = rules.duplicate(true)
	plans = {}
	for region: String in world.regions:
		var sim: VillageSimulation = world.regions[region]
		for actor: String in sim.actors:
			if rules.actor_definitions.has(sim.actor_state(actor).definition_id):
				plans[actor] = {"region": region, "retry_ms": world.elapsed_ms, "stop_index": 0, "search_count": 0, "last_ms": -1, "last_result": "none"}
	return true


func wants_decision(actor: String, at_ms: int) -> bool:
	if world.services == null or not plans.has(actor) or at_ms < int(plans[actor].retry_ms):
		return false
	var offer: Dictionary = world.services.definitions.trade.offers.get(definitions.purchase_offer, {})
	if offer.get("direction") != "buy" or offer.get("item") != definitions.desired_item:
		return false
	var sim: VillageSimulation = world.regions[plans[actor].region]
	if not sim.actor_is_autonomous(actor):
		return false
	var contract: Dictionary = _contract(actor)
	return not contract.is_empty() or sim.inventory.available("actor:" + actor, str(definitions.desired_item)) < int(definitions.desired_amount)


func consider() -> void:
	for actor: String in world._sorted_keys(plans):
		if not wants_decision(actor, world.elapsed_ms) or not world.autonomous_decision(actor):
			continue
		var sim: VillageSimulation = world.regions[plans[actor].region]
		if not world.standing_work.duty_for(actor, world.elapsed_ms).is_empty():
			continue
		if not _step(actor, sim):
			# A rejected personal plan falls back to the same original needs/duty
			# policy, without calling the initiative hook recursively.
			sim._choose_routine(actor, false)
		world.invalidate_region(str(plans[actor].region))


func _step(actor: String, sim: VillageSimulation) -> bool:
	var plan: Dictionary = plans[actor]
	plan.last_ms = world.elapsed_ms
	plan.retry_ms = world.elapsed_ms + int(sim.config.decision_interval) * 60000
	var contract: Dictionary = _contract(actor)
	if contract.get("status") == "paused":
		return _result(plan, world.budgeted_labor.resume(actor, str(contract.id)), "working")
	if contract.is_empty() and not SimEntrustedGoods.first_held(sim.inventory, actor).is_empty():
		return _result(plan, world.services.begin(actor, str(plan.region), "return_goods"), "returning")
	var speaker: String = _speaker(actor, sim)
	if speaker.is_empty():
		return _search(actor, sim, plan)
	plan.search_count = 0
	if contract.get("status") == "payable":
		return _result(plan, world.budgeted_labor.request_claim(actor, str(contract.id), speaker), "claiming")
	var offer: Dictionary = world.services.definitions.trade.offers[definitions.purchase_offer]
	var lots: int = ceili(float(int(definitions.desired_amount) - sim.inventory.available("actor:" + actor, str(definitions.desired_item))) / float(offer.amount))
	if sim.inventory.available("actor:" + actor, str(world.services.definitions.coin_item)) >= lots * int(offer.coins):
		return _result(plan, world.services._trade.authorize(actor, str(plan.region), speaker, str(definitions.purchase_offer), lots), "buying")
	for id: String in world._sorted_keys(world.budgeted_labor.definitions.offers):
		var response: Dictionary = world.budgeted_labor.accept_autonomous(actor, str(plan.region), speaker, id)
		if response.ok:
			return _result(plan, response, "working")
	return _result(plan, {"ok": false}, "declined")


func _contract(actor: String) -> Dictionary:
	var id: String = world.budgeted_labor.latest_for(actor)
	var note: Dictionary = world.budgeted_labor.contracts.get(id, {})
	return note if note.get("status") in ["working", "paused", "payable"] else {}


func _speaker(actor: String, sim: VillageSimulation) -> String:
	# Current physical proximity is perceptible; hidden posts and distant
	# coordinates never choose whom to seek. Old testimony may now be wrong.
	var visible: Array[String] = []
	var radius: float = minf(float(sim.config.observation_radius), float(world._content.interaction_requests.communication_cells))
	for other: String in world._sorted_keys(sim.actors):
		if other != actor and sim.actor_state(other).alive and sim._distance(actor, other) <= radius:
			visible.append(other)
	for other: String in visible:
		if _claims_payment(sim, actor, other):
			return other
	for other: String in visible:
		var last: int = -1
		for request: Dictionary in sim.social.requests.values():
			if request.task == SimCapabilityConversation.TASK and request.requester == actor and request.responder == other:
				last = maxi(last, int(request.tick) * 60000)
		if last >= 0 and world.elapsed_ms - last < int(definitions.backoff_ms):
			continue
		SimCapabilityConversation.ask_autonomous(world, actor, other, str(definitions.conversation_topic))
		return other if _claims_payment(sim, actor, other) else ""
	return ""


func _claims_payment(sim: VillageSimulation, listener: String, speaker: String) -> bool:
	var latest: Dictionary = {}
	# Event order survives JSON key sorting, including multiple statements in
	# one coarse minute. Read only the listener's own version of those events.
	for event: Dictionary in sim.social.events:
		var known: Dictionary = sim.social.knowledge[listener].get(event.id, {})
		if known.get("kind") == SimCapabilityConversation.KIND and known.actor == speaker and known.target == listener:
			latest = known
	return not latest.is_empty() and latest.details.get("claims", []).has(definitions.capability_claim)


func _search(actor: String, sim: VillageSimulation, plan: Dictionary) -> bool:
	if int(plan.search_count) >= definitions.search_actions.size():
		plan.search_count = 0
		return _result(plan, {"ok": false}, "no_contact")
	var action: String = str(definitions.search_actions[int(plan.stop_index)])
	plan.stop_index = (int(plan.stop_index) + 1) % definitions.search_actions.size()
	plan.search_count = int(plan.search_count) + 1
	if not sim.submit_action(actor, action):
		return _result(plan, {"ok": false}, "unreachable")
	plan.last_result = "searching"
	return true


func _result(plan: Dictionary, response: Dictionary, success: String) -> bool:
	var ok: bool = bool(response.ok)
	plan.last_result = success if ok else ("waiting" if success in ["working", "claiming", "buying"] else success)
	if not ok:
		plan.retry_ms = world.elapsed_ms + int(definitions.backoff_ms)
	return ok


static func empty_state() -> Dictionary:
	return {"version": 1, "plans": {}}


func to_dict() -> Dictionary:
	return {"version": 1, "plans": plans.duplicate(true)}


func restore(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "plans"]) or data.version != 1 or not data.plans is Dictionary:
		return false
	for actor: Variant in data.plans:
		var plan: Variant = data.plans[actor]
		if not actor is String or not Shape.keys(plan, ["region", "retry_ms", "stop_index", "search_count", "last_ms", "last_result"]) or not plan.region is String or not world.regions.has(plan.region):
			return false
		var sim: VillageSimulation = world.regions[plan.region]
		if not sim.has_actor(actor) or not definitions.actor_definitions.has(sim.actor_state(actor).definition_id) or not Shape.count(plan.retry_ms, 0, SimInventory.MAX_COUNT) or not Shape.count(plan.stop_index, 0, definitions.search_actions.size() - 1) or not Shape.count(plan.search_count, 0, definitions.search_actions.size()) or not Shape.count(plan.last_ms, -1, world.elapsed_ms) or plan.last_result not in RESULTS:
			return false
		if (int(plan.last_ms) == -1) != (plan.last_result == "none") or int(plan.retry_ms) < int(plan.last_ms):
			return false
		if int(plan.last_ms) == -1 and (int(plan.retry_ms) > world.elapsed_ms or int(plan.stop_index) != 0 or int(plan.search_count) != 0):
			return false
		if int(plan.last_ms) >= 0 and int(plan.retry_ms) - int(plan.last_ms) > maxi(int(definitions.backoff_ms), int(sim.config.decision_interval) * 60000):
			return false
		for id: String in definitions.visits:
			if not Shape.same_record(sim.config.actions.get(id), definitions.visits[id]):
				return false
	plans = data.plans.duplicate(true)
	return true
