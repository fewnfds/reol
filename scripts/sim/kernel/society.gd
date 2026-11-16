extends RefCounted
## Contact and participation. Institutions owns the accepted obligations.
## Learning, physical possessions, practiced skill and stored qi are distinct.

const State = preload("res://scripts/sim/kernel/state.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Beings = preload("res://scripts/sim/kernel/being_defs.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Query = preload("res://scripts/sim/kernel/operation_query.gd")
const Results = preload("res://scripts/sim/kernel/activity_results.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const Contacts = preload("res://scripts/sim/kernel/society_contacts.gd")
const Requests = preload("res://scripts/sim/kernel/society_requests.gd")
const STATE_FIELDS: Array = ["waits", "contacts", "requests", "next_request"]
var waits: Dictionary = {} # Partner participation belongs to this interaction host.
var contacts: Dictionary = {}
var requests: Dictionary = {}
var next_request: int = 1
var _contacts_by_actor: Dictionary = {}
var _requests_by_actor: Dictionary = {}
var _requests_by_key: Dictionary = {}
var _request_by_share: Dictionary = {}
var completed: Dictionary = {}

func in_contact(world: RefCounted, actor: int, other: int, now: int) -> bool:
	if actor == other or not world.actor_slots.has(actor) or not world.objects.records.has(other) or now != world.operation_time(): return false
	if not world.combat.alive(world, actor) or not Beings.has(world.objects.records[actor], "contact") or not Beings.has(world.objects.records[other], "contact"): return false
	if world.actor_slots.has(other) and not world.combat.alive(world, other): return false
	var slot: int = world.actor_slots[actor]
	return world.facilities.in_range(world, other, world.position_at(actor, now), world.pages[slot / 256].radii[slot % 256], "talk", world.pages[slot / 256].flight[slot % 256] > 0)

func deliver_request(world: RefCounted, actor: int, action: Dictionary, now: int) -> Dictionary:
	return Requests.deliver(self, world, actor, action, now)

func respond(world: RefCounted, actor: int, id: int, response: String, now: int, reason: String = "") -> Dictionary:
	return Requests.respond(self, world, actor, id, response, reason if not reason.is_empty() else ("request_deferred" if response == "defer" else "request_refused"), now)

func on_share_closed(world: RefCounted, share: Dictionary, fulfilled: bool) -> void:
	Requests.share_closed(self, share, fulfilled, world.operation_time())

func on_matter_closed(world: RefCounted, matter: int) -> void:
	Requests.matter_closed(self, matter, world.operation_time())

func on_actor_removed(actor: int, now: int) -> void:
	Requests.actor_removed(self, actor, now)

func valid(world: RefCounted) -> bool:
	# Gate owns the cross-host run checks; Society also rejects extra lock data.
	for value: Variant in waits.values():
		if not value is Dictionary or value.size() != 3: return false
	return Requests.valid(self, world) and Contacts.valid(self, world)


func initialize(world: RefCounted) -> void:
	if not world.actor_slots.has(2):
		return
	world.release(2)
	var page: RefCounted = world.pages[0]
	page.positions[1] = Vector2(177.5, 187.5)
	page.modes[1] = Units.Mode.IDLE
	var teacher: Dictionary = world.objects.records[2]
	teacher.autonomous = false
	teacher["name"] = "旅居修士"
	Growth.seed(teacher, "wood_breath", 0)
	Growth.seed(teacher, "cooking", 0)
	Growth.seed(teacher, "herbalism", 0)
	world.objects.add(2, "breath_manual", 1)
	world.objects.add(2, "meal", 4)
	world.knowledge.observe(world, 2, 0)


func available(world: RefCounted, actor: int, action: Dictionary) -> bool:
	return availability_reason(world, actor, action).is_empty()

func availability_reason(world: RefCounted, actor: int, action: Dictionary) -> String:
	var operation: Dictionary = Operations.OPERATIONS.get(action.get("operation_id", action.kind), {})
	if operation.is_empty() or not world.objects.records.has(action.target): return "invalid_target"
	var query: Dictionary = Query.evaluate(operation, world.operation_actor(actor), world.operation_target(action.target), {"help_target": int(action.get("task_target", 0))})
	return query.reason if not query.ready else contact_reason(world, action)

func contact_reason(world: RefCounted, action: Dictionary) -> String:
	var operation: Dictionary = Operations.OPERATIONS[action.get("operation_id", action.kind)]
	if operation.handler in ["talk", "trade", "request_help", "offer_matter", "learn"] and world.actor_slots.has(action.target):
		if not Beings.has(world.objects.records[action.target], "contact"): return "not_available_for_contact"
	return ""


func invite(world: RefCounted, actor: int, action: Dictionary) -> void:
	if not available(world, actor, action): return
	var target: int = action.target
	var handler: String = Operations.OPERATIONS.get(action.get("operation_id", action.kind), {}).get("handler", "")
	if target == 1 or target == actor or not world.actor_slots.has(target) or handler not in ["talk", "trade", "learn", "request_help", "offer_matter"]:
		return
	if world.decisions.records.get(target, {}).get("manual", false): return
	if waits.has(target): return # Another host owns this partner; invitation cannot steal it.
	var slot: int = world.actor_slots[target]
	var page: RefCounted = world.pages[slot / 256]
	if world.combat.controls.has(target) or (not world.objects.records[target].get("autonomous", false) and world.work_runs.has(target)) or not world.gate.check(world, target, world.operation_time()).is_empty() or world.actions.has(target) or world.decisions.in_combat(target) or world.combat.states.has(target) or page.health[slot % 256] < 30:
		return # A busy/unwilling partner need not stop; contact can fail normally.
	action["partner_waiting"] = true
	action["partner_resume"] = world.objects.records[target].get("autonomous", false)
	world.release(target)
	page.modes[slot % 256] = Units.Mode.IDLE
	waits[target] = {"actor": actor, "owner_run": action.run_id, "run_id": world.next_run}
	world.next_run += 1
	world.gate.bind(target, "partner", waits[target].run_id)


func interrupt(world: RefCounted, action: Dictionary, now: int) -> void:
	if not action.get("partner_waiting", false) or not world.actor_slots.has(action.target):
		return
	var wait: Dictionary = waits.get(action.target, {})
	if wait.is_empty() or wait.owner_run != action.get("run_id"): return
	if not world.gate.unbind(action.target, "partner", wait.run_id): return
	waits.erase(action.target)
	var slot: int = world.actor_slots[action.target]
	var page: RefCounted = world.pages[slot / 256]
	# Never overwrite a newer player command or a defensive combat response.
	if action.get("partner_resume", false) and world.objects.records[action.target].get("autonomous", false) and page.health[slot % 256] > 0 and page.modes[slot % 256] == Units.Mode.IDLE and not world.actions.has(action.target) and not world.decisions.in_combat(action.target):
		world.livelihood.after_action(world, action.target, now)

func participation_reason(world: RefCounted, actor: int, action: Dictionary, now: int) -> String:
	var handler: String = Operations.OPERATIONS[action.kind].handler
	if handler not in ["talk", "trade", "request_help", "offer_matter", "learn"]: return ""
	if not world.actor_slots.has(action.target): return ""
	if action.target == 1 or world.decisions.records.get(action.target, {}).get("manual", false):
		# Contact does not seize the player's input. Presence and actual capacity
		# to participate are rechecked at both start and commit.
		return "target_busy" if not world.gate.current(action.target).is_empty() or world.combat.controls.has(action.target) or world.combat.engagements.has(action.target) or not world.gate.check(world, action.target, now).is_empty() or world.decisions.in_combat(action.target) else ""
	var wait: Dictionary = waits.get(action.target, {})
	return "" if wait.get("actor") == actor and wait.get("owner_run") == action.run_id else "target_busy"

func participants(actor: int, action: Dictionary) -> Array:
	var handler: String = Operations.OPERATIONS[action.kind].handler
	return [actor, action.target] if handler in ["talk", "trade", "request_help", "offer_matter", "learn"] and action.target != actor else [actor]


func finish(world: RefCounted, actor: int, action: Dictionary, now: int) -> String:
	return commit(world, actor, action, now).reason

func commit(world: RefCounted, actor: int, action: Dictionary, now: int) -> Dictionary:
	var availability: String = availability_reason(world, actor, action)
	if not availability.is_empty(): return Results.refused(availability)
	var operation_id: String = action.get("operation_id", action.kind)
	var handler: String = Operations.OPERATIONS[operation_id].handler
	var capability_reason: String = Operations.capability_reason(world.objects.records[actor], operation_id)
	if not capability_reason.is_empty(): return Results.refused(capability_reason)
	var person: Dictionary = world.objects.records[actor]
	var other: Dictionary = world.objects.records[action.target]
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	var facts: Dictionary = {}
	if handler in ["talk", "trade", "learn"]:
		Contacts.acknowledge(self, world, actor, int(action.target), now)
	match handler:
		"talk":
			var shared: Dictionary = world.knowledge.share(world, action.target, actor, now)
			_count(action.kind)
			return Results.completed(shared, "contact_established" if shared.is_empty() else "shared_clue")
		"trade":
			var give: String = str(action.get("give_item", "potion"))
			var want: String = str(action.get("want_item", "breath_manual"))
			var given: int = int(action.get("give_amount", 1))
			var wanted: int = int(action.get("want_amount", 1))
			if not Items.valid(give) or not Items.valid(want) or given <= 0 or wanted <= 0:
				return Results.refused("invalid_offer")
			var value: Dictionary = {"wood": 1, "grain": 2, "water": 2, "meal": 5, "potion": 12, "breath_manual": 10}
			if given * int(value.get(give, 1)) < wanted * int(value.get(want, 1)):
				return Results.refused("refused_value")
			if world.actor_slots.has(action.target):
				var other_slot: int = world.actor_slots[action.target]
				var other_page: RefCounted = world.pages[other_slot / 256]
				if want == "potion" and other_page.health[other_slot % 256] < 60 and world.objects.amount(action.target, want, world.objects.Stock.right(action.target)) <= wanted:
					return Results.refused("refused_need")
			if not world.objects.exchange(actor, action.target, give, given, want, wanted, world.objects.Stock.right(actor), world.objects.Stock.right(action.target), true):
				return Results.refused("missing_items_or_capacity")
			world._sync_inventory(actor)
			if world.actor_slots.has(action.target):
				world._sync_inventory(action.target)
			facts = {"given": {give: given}, "received": {want: wanted}, "counterparty": action.target}
		"request_help", "offer_matter":
			var delivered: Dictionary = Requests.deliver(self, world, actor, action, now)
			if delivered.status != "completed": return delivered
			var id: int = int(delivered.facts.request)
			var response: Dictionary = judge_request(world, int(action.target), id, now)
			if response.get("reason") == "accepted_share": action["partner_resume"] = true
			if not response.is_empty(): response.facts["counterparty"] = int(action.target)
			_count(action.kind)
			return response if not response.is_empty() else delivered
		"learn", "study":
			var method: String = Operations.OPERATIONS[operation_id].learning_method
			var spec: Dictionary = Growth.Defs.METHODS[method]
			if handler == "learn" and not Growth.mastered(other, method):
				return Results.refused("teacher_does_not_know")
			if handler == "study" and int(world.institutions.readable(world, actor).get(spec.study_item, 0)) <= 0:
				return Results.refused("missing_book")
			if int(person.get("methods", {}).get(method, {}).get("understanding", 0)) >= int(spec.introduction_points): return Results.refused("already_understood")
			facts = Growth.advance(person, method, Operations.OPERATIONS[operation_id].learning_points, handler, action.target if handler == "learn" else 0, now, spec.study_item if handler == "study" else "")
			facts["teacher"] = action.target if handler == "learn" else 0
		"practice":
			var method: String = Operations.OPERATIONS[operation_id].learning_method
			var spec: Dictionary = Growth.Defs.METHODS[method]
			if not Growth.introduced(person, method):
				return Results.refused("method_not_known")
			if page.energy[row] < maxi(800, int(spec.energy_cost)) or page.hunger[row] < maxi(800, int(spec.satiety_cost)) or page.body_heat[row] < 0 or page.body_heat[row] > 50:
				return Results.refused("body_not_ready")
			var qi: int = int(other.get("qi", 0))
			if qi < int(spec.source_qi_cost):
				return Results.refused("insufficient_stored_qi")
			other["qi"] = qi - int(spec.source_qi_cost) # Stored source, not ambient influence.
			page.energy[row] -= int(spec.energy_cost)
			page.hunger[row] -= int(spec.satiety_cost)
			facts = Growth.advance(person, method, Operations.OPERATIONS[operation_id].learning_points, "practice", 0, now)
			facts.merge({"target_qi_spent": int(spec.source_qi_cost), "qi_gained": world.pools.gain(world, actor, "qi", int(spec.qi_gain), now),
				"energy_spent": int(spec.energy_cost), "hunger_spent": int(spec.satiety_cost)})
	_count(action.kind)
	return Results.completed(facts)

func judge_request(world: RefCounted, actor: int, id: int, now: int) -> Dictionary:
	if actor == 1 or world.decisions.records.get(actor, {}).get("manual", false): return {}
	var request: Dictionary = {}
	for view: Dictionary in Requests.views(self, actor, now):
		if view.id == id: request = view; break
	if request.is_empty() or request.recipient != actor or request.state not in ["pending", "deferred"]: return {}
	if request.state == "deferred" and now < request.review_ms: return {}
	if not in_contact(world, actor, int(request.issuer), now): return {}
	var judgment: Dictionary = world.livelihood.evaluate_request(world, actor, request, now)
	if judgment.decision == "wait":
		var budget: Dictionary = world.livelihood.record(world, actor).budget
		world.decisions.wake(world, actor, now, "request_review", maxi(50, int(budget.window_ms) + world.livelihood.BUDGET_MS - now))
		return {}
	var response: Dictionary = respond(world, actor, id, str(judgment.decision), now, str(judgment.reason))
	if response.reason == "accepted_share":
		if not waits.has(actor) and world.gate.current(actor).is_empty(): world.livelihood.after_action(world, actor, now)
	elif judgment.decision == "defer":
		world.decisions.wake(world, actor, now, "request_review", mini(now + Requests.DEFER_MS, int(request.expires_ms) - 1) - now)
	return response

func support_witnesses(world: RefCounted, result: Dictionary) -> Array:
	var witnesses: Array = []
	for id: int in _requests_by_actor.get(int(result.actor), []):
		var request: Dictionary = requests[id]
		if request.recipient != result.actor or request.state != "fulfilled" or request.target != result.target: continue
		var share: Dictionary = world.institutions.shares.get(int(request.share), {})
		if int(share.get("last_result_id", 0)) != result.id: continue
		var issuer: int = request.issuer
		if not world.actor_slots.has(issuer) or not world.combat.alive(world, issuer): continue
		world.sight.sync(world)
		if world.sight.observed_position(world, issuer, int(result.actor)) == null or world.sight.observed_position(world, issuer, int(result.target)) == null: continue
		witnesses.append({"actor": issuer, "peer": int(result.actor)})
	return witnesses

func _count(kind: String) -> void:
	completed[kind] = int(completed.get(kind, 0)) + 1
