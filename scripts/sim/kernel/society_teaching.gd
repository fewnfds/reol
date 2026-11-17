extends RefCounted
## Rules for the original interaction host. No separate lesson state or clock.
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const JOIN_MS: int = 5000
const RETRY_MS: int = 250

static func applies(operation: Dictionary) -> bool:
	return operation.get("handler", "") in ["learn", "teach"]

static func roles(actor: int, action: Dictionary) -> Dictionary:
	var operation: Dictionary = Operations.OPERATIONS[action.kind]
	return {"teacher": actor if operation.handler == "teach" else int(action.target),
		"learner": int(action.target) if operation.handler == "teach" else actor, "method": operation.learning_method}

static func complement(actor: int, action: Dictionary, other: Dictionary) -> bool:
	if other.is_empty() or other.get("target") != actor or other.has("started_ms"): return false
	var left: Dictionary = Operations.OPERATIONS[action.kind]
	var right: Dictionary = Operations.OPERATIONS.get(other.get("kind", ""), {})
	return applies(right) and left.handler != right.handler and left.learning_method == right.learning_method

static func prepare(owner: RefCounted, world: RefCounted, actor: int, action: Dictionary, at: int) -> String:
	var pair: Dictionary = roles(actor, action)
	var target: int = action.target
	if world.reservations.get(target, actor) != actor: return "target_busy"
	if not world.actor_slots.has(target): return "" if Growth.mastered(world.objects.records[target], pair.method) else "teacher_does_not_know"
	if action.get("partner_waiting", false): return owner.participation_reason(world, actor, action, at)
	var other: Dictionary = world.actions.get(target, {})
	var matching: bool = complement(actor, action, other)
	var manual: bool = target == 1 or world.decisions.records.get(target, {}).get("manual", false)
	var self_manual: bool = actor == 1 or world.decisions.records.get(actor, {}).get("manual", false)
	if manual and (not matching or not self_manual or (actor != 1 and (target == 1 or actor > target))):
		# Explicit player participation is adopted by the player's own host. An
		# unattended player is never enrolled by a nearby NPC's command.
		return "awaiting_participant"
	if not matching and other.get("target") == actor and other.get("waiting", false): return "not_interested"
	if not matching and (not other.is_empty() or owner.waits.has(target)): return "target_busy"
	if not world.gate.check(world, target, at).is_empty() or world.combat.controls.has(target) or world.decisions.in_combat(target) or world.combat.engagements.has(target): return "target_busy"
	if not matching:
		var slot: int = world.actor_slots[target]
		var mode: int = world.pages[slot / 256].modes[slot % 256]
		var task: Dictionary = world.decisions.records.get(target, {}).get("task", {})
		var entry: Dictionary = world.livelihood.records.get(target, {})
		var goal: Dictionary = entry.get("goals", {}).get(entry.get("intention", {}).get("goal", 0), {})
		var searching: bool = mode == world.Units.Mode.EXPLORE and world.objects.records[target].get("autonomous", false) and (task.get("operation", "").is_empty() or (not goal.is_empty() and world.livelihood.learning_method(goal, world.operation_actor(target)) == pair.method))
		if not world.gate.current(target).is_empty() and mode != world.Units.Mode.REST and not searching: return "target_busy"
	var consent: String = world.livelihood.teaching_consent(world, target, int(pair.learner if pair.teacher == target else pair.teacher), pair.method, pair.teacher == target, at, matching)
	if not consent.is_empty(): return consent
	if matching:
		world.end_run(target, at, "joined_activity", {}, false)
		world.clear_navigation(target)
	owner.hold_partner(world, actor, action, target)
	return ""

static func result(world: RefCounted, actor: int, action: Dictionary, at: int, already: bool = false) -> Dictionary:
	var pair: Dictionary = roles(actor, action)
	var facts: Dictionary
	if already:
		facts = {"method": pair.method, "channel": "understanding", "points_gained": 0, "understanding": int(Growth.Defs.METHODS[pair.method].introduction_points)}
	else:
		facts = Growth.advance(world.objects.records[pair.learner], pair.method, int(Operations.OPERATIONS[action.kind].learning_points), "learn", pair.teacher, at)
	facts.merge({"teacher": pair.teacher, "learner": pair.learner, "understood": int(facts.understanding) >= int(Growth.Defs.METHODS[pair.method].introduction_points)})
	return world.ActivityResults.completed(facts, "learner_already_understood" if already else "completed")

static func join_valid(action: Dictionary, elapsed: int) -> bool:
	if not action.has("join_until_ms"): return not action.has("join_reason") and not (applies(Operations.OPERATIONS.get(action.get("kind", ""), {})) and not action.has("started_ms") and (action.get("waiting", false) or action.get("partner_waiting", false)))
	return applies(Operations.OPERATIONS.get(action.get("kind", ""), {})) and not action.has("started_ms") and action.get("waiting", false) and action.get("participants", []).size() == 1 and not action.get("partner_waiting", false) and not action.has("partner_free") and action.join_until_ms is int and action.join_until_ms >= elapsed and action.join_until_ms <= elapsed + JOIN_MS and action.get("join_reason") in ["awaiting_participant", "target_busy"]
