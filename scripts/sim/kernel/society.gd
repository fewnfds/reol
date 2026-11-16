extends RefCounted
## Contact outcomes and personal commitments, not a global relationship scan.
## Learning, physical possessions, practiced skill and stored qi are distinct.

const State = preload("res://scripts/sim/kernel/state.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Beings = preload("res://scripts/sim/kernel/being_defs.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Query = preload("res://scripts/sim/kernel/operation_query.gd")
const Results = preload("res://scripts/sim/kernel/activity_results.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const STATE_FIELDS: Array = ["waits"]
var waits: Dictionary = {} # Partner participation belongs to this interaction host.
var completed: Dictionary = {}


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
	world.objects.add(2, "breath_manual", 1)
	world.objects.add(2, "meal", 4)
	world.livelihood.observe(world, 2, 0)


func available(world: RefCounted, actor: int, action: Dictionary) -> bool:
	return availability_reason(world, actor, action).is_empty()

func availability_reason(world: RefCounted, actor: int, action: Dictionary) -> String:
	var operation: Dictionary = Operations.OPERATIONS.get(action.get("operation_id", action.kind), {})
	if operation.is_empty() or not world.objects.records.has(action.target): return "invalid_target"
	var query: Dictionary = Query.evaluate(operation, world.operation_actor(actor), world.operation_target(action.target), {"help_target": int(action.get("task_target", 0))})
	return query.reason if not query.ready else contact_reason(world, action)

func contact_reason(world: RefCounted, action: Dictionary) -> String:
	var operation: Dictionary = Operations.OPERATIONS[action.get("operation_id", action.kind)]
	if operation.handler in ["talk", "trade", "request_help", "learn"] and world.actor_slots.has(action.target):
		if not Beings.has(world.objects.records[action.target], "contact"): return "not_available_for_contact"
	return ""


func invite(world: RefCounted, actor: int, action: Dictionary) -> void:
	if not available(world, actor, action): return
	var target: int = action.target
	var handler: String = Operations.OPERATIONS.get(action.get("operation_id", action.kind), {}).get("handler", "")
	if target == 1 or target == actor or not world.actor_slots.has(target) or handler not in ["talk", "trade", "learn", "request_help"]:
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
	if handler not in ["talk", "trade", "request_help", "learn"]: return ""
	if not world.actor_slots.has(action.target): return ""
	if action.target == 1:
		# Contact does not seize the player's input. Presence and actual capacity
		# to participate are rechecked at both start and commit.
		return "target_busy" if not world.gate.current(1).is_empty() or world.combat.controls.has(1) or world.combat.engagements.has(1) or not world.gate.check(world, 1, now).is_empty() or world.decisions.in_combat(1) else ""
	var wait: Dictionary = waits.get(action.target, {})
	return "" if wait.get("actor") == actor and wait.get("owner_run") == action.run_id else "target_busy"

func participants(actor: int, action: Dictionary) -> Array:
	var handler: String = Operations.OPERATIONS[action.kind].handler
	return [actor, action.target] if handler in ["talk", "trade", "request_help", "learn"] and action.target != actor else [actor]


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
	match handler:
		"talk":
			if not person.has("known"):
				person["known"] = {}
			for subject: int in other.get("known", {}):
				var clue: Dictionary = other.known[subject]
				if not person.known.has(subject) or int(person.known[subject].seen_ms) < int(clue.seen_ms):
					var copy: Dictionary = State.copy(clue)
					copy["source"] = action.target
					copy["hops"] = int(clue.get("hops", 0)) + 1
					person.known[subject] = copy
					_count(action.kind)
					return Results.completed({"subject": subject, "source": action.target, "hops": copy.hops}, "shared_clue")
			return Results.refused("no_new_clue")
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
		"request_help":
			var target: int = int(action.get("task_target", 0))
			if not Beings.has(other, "work"): return Results.refused("refused_capability")
			if not world.actor_slots.has(action.target) or other.has("commitment") or world.decisions.records.get(action.target, {}).get("manual", false):
				return Results.refused("refused_busy_or_body")
			if world.objects.records.get(target, {}).get("kind", "") != "blueprint":
				return Results.refused("invalid_task")
			if not person.get("known", {}).has(target) and world.combat.position(world, actor).distance_to(world.combat.position(world, target)) > 24:
				return Results.refused("unknown_task")
			var other_slot: int = world.actor_slots[action.target]
			var other_page: RefCounted = world.pages[other_slot / 256]
			if Beings.has(other, "metabolism") and (other_page.hunger[other_slot % 256] < 3000 or other_page.energy[other_slot % 256] < 2500):
				return Results.refused("refused_need")
			other["commitment"] = {"kind": "construct", "target": target, "requester": actor, "expires_ms": now + 300000,
				"was_autonomous": other.get("autonomous", false)}
			world.livelihood.remember(world, action.target, target, now)
			other.autonomous = true
			facts = {"accepted_kind": "construct", "task_target": target, "expires_ms": now + 300000}
			action["partner_resume"] = true
			if not waits.has(action.target) and world.gate.current(action.target).is_empty() and world.gate.check(world, action.target, now).is_empty(): world.livelihood.after_action(world, action.target, now)
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


func _count(kind: String) -> void:
	completed[kind] = int(completed.get(kind, 0)) + 1
