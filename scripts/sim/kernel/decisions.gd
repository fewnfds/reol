extends RefCounted
## Owner-side coordination; no per-agent Node or new world clock.
const Defs = preload("res://scripts/sim/kernel/decision_defs.gd")
const Actions = preload("res://scripts/sim/kernel/action_defs.gd")
const Costs = preload("res://scripts/sim/kernel/action_costs.gd")
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const State = preload("res://scripts/sim/kernel/state.gd")
const STATE_FIELDS: Array = ["records", "wakeups", "movement", "next_task", "catalog_signature"]
const RECORD_FIELDS: Array = ["policy", "params", "manual", "mode", "next_ms", "task", "rule_due", "hit_ms", "ready_ms", "repath_ms", "follow_ms", "last_goal", "last_reason", "life_dirty", "feedback"]
const FEEDBACK_LIMIT: int = 16
const FEEDBACK_LONG_MS: int = 5000
const FEEDBACK_SHORT_MS: int = 1500
const EVIDENCE_FIELDS: Array = ["kind", "definition", "tile", "inventory_revision", "capacity", "stage"]
var records: Dictionary = {}
var wakeups: Dictionary = {} # Reliable owner facts awaiting the next safe preparation.
var next_task: int = 1
var catalog_signature: String = Defs.SIGNATURE
var movement: Dictionary = {} # Held autonomous input; saved, unlike local keyboard state.
var trace: Array[Dictionary] = [] # Bounded, diagnostic only.
var latest: Dictionary = {}
var evaluations: int = 0
var work_usec: int = 0
var _submitting: int = 0

func _record(world: RefCounted, actor: int) -> Dictionary:
	if not records.has(actor):
		var person: Dictionary = world.objects.records[actor]
		var policy: String = "resident" if person.get("autonomous", false) else "basic"
		records[actor] = {"policy": policy, "params": {}, "manual": false, "mode": "idle", "next_ms": -1,
			"task": {}, "rule_due": {}, "hit_ms": -1, "ready_ms": 0, "repath_ms": 0, "follow_ms": 0, "last_goal": Vector2(-1, -1), "last_reason": "idle", "life_dirty": false, "feedback": []}
	return records[actor]

func bind(world: RefCounted, actor: int, policy: String, parameters: Dictionary = {}) -> String:
	if not world.actor_slots.has(actor) or not Defs.POLICIES.has(policy) or not Defs.parameters_valid(parameters): return "invalid_policy"
	var spec: Dictionary = Defs.POLICIES[policy].merged(parameters, true)
	if spec.min > spec.max: return "invalid_distance_band"
	if not world.gate.check(world, actor, world.operation_time()).is_empty(): return "action_committed"
	var entry: Dictionary = _record(world, actor)
	_submitting = actor
	world.end_run(actor, world.operation_time(), "preempted")
	world.clear_navigation(actor)
	_submitting = 0
	movement.erase(actor)
	entry.policy = policy
	entry.params = parameters.duplicate(true)
	entry.rule_due.clear()
	entry.task.clear()
	wake(world, actor, world.operation_time(), "policy_bound")
	return "bound"

func policy(world: RefCounted, actor: int) -> Dictionary:
	var entry: Dictionary = _record(world, actor)
	return Defs.POLICIES[entry.policy] if entry.params.is_empty() else Defs.POLICIES[entry.policy].merged(entry.params, true)

func wake(world: RefCounted, actor: int, at: int, reason: String, delay: int = 0) -> void:
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor): return
	var entry: Dictionary = _record(world, actor)
	if reason == "needs_changed":
		if entry.manual or not _life_preemptible(world, actor): return
		entry.life_dirty = true
	var due: int = at + maxi(0, delay)
	if reason in ["life_result", "await_commitment"]: due = ((due + 49) / 50) * 50
	if reason == "life_result" and str(wakeups.get(actor, "")).begins_with("execution_") and not in_combat(actor):
		entry.next_ms = due
		wakeups[actor] = reason
		return
	if entry.next_ms < 0 or due < entry.next_ms:
		entry.next_ms = due
		wakeups[actor] = reason
	elif due == entry.next_ms and reason not in ["tactical_due", "life_result"]: wakeups[actor] = reason

func in_combat(actor: int) -> bool:
	return records.get(actor, {}).get("mode", "") in ["fight", "flee"]

func suspend(world: RefCounted, actor: int) -> void:
	var entry: Dictionary = _record(world, actor)
	world.objects.records[actor].erase("commitment")
	entry.manual = true
	entry.life_dirty = false
	entry.mode = "manual"
	entry.task.clear()
	entry.next_ms = -1
	wakeups.erase(actor)
	movement.erase(actor)
	world.combat.engagements.erase(actor)
	entry.last_reason = "manual_control"

func resume(world: RefCounted, actor: int, at: int) -> void:
	var entry: Dictionary = _record(world, actor)
	entry.manual = false
	entry.life_dirty = false
	entry.mode = "idle"
	wake(world, actor, at, "resume")

func forget(actor: int) -> void:
	records.erase(actor)
	wakeups.erase(actor)
	movement.erase(actor)
	latest.erase(actor)

func released(actor: int) -> void:
	if not records.has(actor): return
	records[actor].task.clear()
	records[actor].life_dirty = false
	records[actor].mode = "idle" if not records[actor].manual else "manual"
	records[actor].next_ms = -1
	wakeups.erase(actor)
	movement.erase(actor)

func track_host(world: RefCounted, actor: int, operation: String = "", target: int = 0, approach: bool = false) -> void:
	# Both an autonomous choice and a one-off order to an autonomous resident
	# can await the existing host. Manual control remains explicitly suspended.
	if not world.objects.records[actor].get("autonomous", false): return
	var entry: Dictionary = _record(world, actor)
	if entry.manual: return
	var binding: Dictionary = world.gate.current(actor)
	if binding.is_empty(): return
	if operation.is_empty() and binding.domain == "interaction":
		var action: Dictionary = world.actions.get(actor, {})
		operation = str(action.get("kind", ""))
		target = int(action.get("target", 0))
	if entry.task.get("binding", {}) == binding:
		if not operation.is_empty() and target > 0:
			entry.task["operation"] = operation
			entry.task["target"] = target
			entry.task["approach"] = approach
		return
	entry.mode = "life"
	entry.task = {"id": _id(), "kind": "host", "binding": binding, "result": "", "waiting": "running"}
	if not operation.is_empty() and target > 0:
		entry.task["operation"] = operation
		entry.task["target"] = target
		entry.task["approach"] = approach

func _evidence(world: RefCounted, actor: int, target: int) -> Dictionary:
	# Personal observations only. A remote world edit cannot invalidate a refusal.
	var clue: Dictionary = world.objects.records[actor].get("known", {}).get(target, {})
	var result: Dictionary = {}
	for field: String in EVIDENCE_FIELDS:
		if clue.has(field): result[field] = clue[field]
	return result

func _prune_feedback(world: RefCounted, actor: int, at: int) -> void:
	var failures: Array = records[actor].feedback
	for index: int in range(failures.size() - 1, -1, -1):
		var failure: Dictionary = failures[index]
		if at >= int(failure.until_ms) or failure.evidence != _evidence(world, actor, failure.target): failures.remove_at(index)

func retry_allowed(world: RefCounted, actor: int, operation: String, target: int, at: int) -> bool:
	var entry: Dictionary = _record(world, actor)
	_prune_feedback(world, actor, at)
	for failure: Dictionary in entry.feedback:
		if failure.operation == operation and failure.target == target: return false
	return true

func result(world: RefCounted, actor: int, operation: String, target: int, reason: String, at: int) -> void:
	if operation.is_empty() or target <= 0 or not world.actor_slots.has(actor) or not world.combat.alive(world, actor): return
	var entry: Dictionary = _record(world, actor)
	_prune_feedback(world, actor, at)
	var succeeded: bool = reason in ["completed", "transferred", "arrived"]
	if not succeeded and reason in ["accepted", "started", "buffered", "replaced", "preempted", "interrupted", "partner_left", "cancelled", "action_committed", "stunned", "recovery", "rooted", "intent_pending"]: return
	for index: int in range(entry.feedback.size() - 1, -1, -1):
		if entry.feedback[index].operation == operation and entry.feedback[index].target == target: entry.feedback.remove_at(index)
	if succeeded: return
	var span: int = FEEDBACK_LONG_MS if reason in ["path_failed", "no_operation_place", "out_of_reach", "target_gone", "invalid_target", "unavailable"] else FEEDBACK_SHORT_MS
	entry.feedback.append({"operation": operation, "target": target, "reason": reason, "at_ms": at, "until_ms": at + span, "evidence": _evidence(world, actor, target)})
	if entry.feedback.size() > FEEDBACK_LIMIT: entry.feedback.pop_front()

func _life_preemptible(world: RefCounted, actor: int) -> bool:
	if not world.objects.records[actor].get("autonomous", false): return false
	if world.gate.current(actor).get("domain", "") == "partner": return false
	return not world.actions.has(actor) or bool(world.actions[actor].get("autonomous", false))

func notice(world: RefCounted, actor: int, at: int, hit: bool = false) -> void:
	var entry: Dictionary = _record(world, actor)
	if hit: entry.hit_ms = at
	wake(world, actor, at, "hurt" if hit else "contact")

func focus(world: RefCounted, actor: int, at: int) -> void:
	# Explicit host request (summon command/fixture), distinct from discovery.
	var entry: Dictionary = _record(world, actor)
	if entry.manual: return
	_enter(world, actor, entry, "fight", at)

func ended(world: RefCounted, actor: int, binding: Dictionary, at: int, reason: String) -> void:
	if not records.has(actor): return
	var entry: Dictionary = records[actor]
	var task: Dictionary = entry.task
	if task.get("binding", {}) == binding and not binding.is_empty():
		if task.has("operation") and (reason != "completed" or not task.get("approach", false)):
			result(world, actor, task.operation, task.target, reason, at)
		task.binding = {}
		task.result = reason
		if task.get("kind") == "host" or (_submitting != actor and reason != "completed"): task.clear()
		if _submitting != actor: wake(world, actor, at, "execution_" + reason)

func started(actor: int, button: String, activation: int) -> void:
	var task: Dictionary = records.get(actor, {}).get("task", {})
	if task.get("waiting", "") == "buffered" and task.get("button", "") == button:
		task.binding = {"domain": "combat", "run_id": activation}
		task.waiting = "running"

func buffer_ended(world: RefCounted, actor: int, button: String, at: int) -> void:
	var task: Dictionary = records.get(actor, {}).get("task", {})
	if task.get("waiting", "") != "buffered" or task.get("button", "") != button: return
	task.clear()
	wake(world, actor, at, "buffer_expired")

func interrupted(actor: int) -> void:
	var task: Dictionary = records.get(actor, {}).get("task", {})
	if task.get("kind", "") == "sequence": task.clear()

func contact_ended(world: RefCounted, actor: int, at: int) -> void:
	movement.erase(actor)
	if not records.has(actor): return
	var entry: Dictionary = records[actor]
	if in_combat(actor):
		entry.mode = "idle"
		entry.task.clear()
		world.combat.resumed += 1
	wake(world, actor, at, "contact_ended")

func _enter(world: RefCounted, actor: int, entry: Dictionary, mode: String, now: int) -> bool:
	if entry.mode == mode: return true
	if not world.gate.check(world, actor, now).is_empty(): return false
	_submitting = actor
	world.end_run(actor, now, "preempted")
	world.clear_navigation(actor)
	_submitting = 0
	entry.mode = mode
	entry.task.clear()
	entry.ready_ms = now + int(policy(world, actor).reaction_ms)
	entry.repath_ms = 0
	return true

func next_boundary(now: int, end: int) -> int:
	for actor: int in wakeups:
		var due: int = records[actor].next_ms
		if due > now: end = mini(end, due)
	return end

func follow(world: RefCounted, actor: int, home: Vector2, now: int) -> void:
	var entry: Dictionary = _record(world, actor)
	if entry.manual or now < int(entry.follow_ms): return
	entry.follow_ms = now + 300
	var origin: Vector2 = world.combat.position(world, actor)
	if origin.distance_to(home) > 10:
		world.combat.finish(world, actor, now)
		world.objects.records[actor]["threat_scan_after"] = now + 1000
	if in_combat(actor) or world.combat.engagements.has(actor) or world.combat.states.has(actor) or not world.gate.check(world, actor, now).is_empty() or world.effects.has_kind(actor, "root", now): return
	entry.mode = "follow"
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	if origin.distance_to(home) <= 2.5:
		if page.modes[row] == Units.Mode.COMBAT_MOVE: world.clear_navigation(actor); page.modes[row] = Units.Mode.IDLE
		return
	var point: Vector2 = world.terrain.project_point(home, page.radii[row], page.flight[row] > 0)
	if point.x >= 0 and (page.modes[row] != Units.Mode.COMBAT_MOVE or page.targets[row].distance_to(point) > 1): page.move_to(row, point, Units.Mode.COMBAT_MOVE)

func prepare(world: RefCounted, now: int) -> void:
	var started_at: int = Time.get_ticks_usec()
	for actor: int in wakeups.keys():
		var entry: Dictionary = records[actor]
		if not world.combat.alive(world, actor): forget(actor); continue
		if entry.next_ms < 0: wakeups.erase(actor); continue
		if now < int(entry.next_ms): continue
		entry.next_ms = -1
		var reason: String = str(wakeups.get(actor, "due"))
		wakeups.erase(actor)
		if entry.manual:
			entry.life_dirty = false
			continue
		evaluations += 1
		var spec: Dictionary = policy(world, actor)
		var contact: Dictionary = world.combat.engagements.get(actor, {})
		if not contact.is_empty():
			var slot: int = world.actor_slots[actor]
			var page: RefCounted = world.pages[slot / 256]
			var health: float = float(page.health[slot % 256]) / page.max_health[slot % 256]
			var response: String = "flee" if health < float(spec.flee_health) else str(spec.response)
			# Once fleeing, recover a margin before selecting fight again.
			if entry.mode == "flee" and health < float(spec.flee_health) + 0.1: response = "flee"
			if response == "ignore":
				if in_combat(actor): world.combat.finish(world, actor, now)
				else: world.combat.engagements.erase(actor)
				movement.erase(actor)
				world.objects.records[actor]["threat_scan_after"] = now + 2000
			elif not _enter(world, actor, entry, response, now):
				wake(world, actor, now, "await_commitment", int(spec.think_ms)); continue
		if in_combat(actor) and world.combat.engagements.has(actor):
			_combat(world, actor, entry, spec, now)
			if in_combat(actor): wake(world, actor, now, "tactical_due", int(spec.think_ms))
		elif world.objects.records[actor].get("autonomous", false):
			if not world.gate.check(world, actor, now).is_empty():
				wake(world, actor, now, "await_commitment", 100); continue
			if entry.life_dirty:
				entry.life_dirty = false
				if _life_preemptible(world, actor):
					_submitting = actor
					world.end_run(actor, now, "preempted")
					world.clear_navigation(actor)
					_submitting = 0
			if world.gate.current(actor).is_empty():
				entry.mode = "life"
				world.livelihood.choose(world, actor, now)
				entry.mode = "life" if world.objects.records[actor].get("autonomous", false) else "idle"
				track_host(world, actor)
				_record_trace(actor, now, entry, -1, "life_selected")
		else:
			entry.life_dirty = false
			if entry.mode != "follow": entry.mode = "idle"
			entry.task.clear()
		entry.last_reason = reason
	work_usec += Time.get_ticks_usec() - started_at

func _id() -> int:
	var result: int = next_task
	next_task += 1
	return result

func _ready(world: RefCounted, actor: int, button: String, now: int) -> bool:
	return _ready_reason(world, actor, button, now).is_empty()

func _ready_reason(world: RefCounted, actor: int, button: String, now: int) -> String:
	var combat: RefCounted = world.combat
	var kind: String = combat.ability(world, actor, button, now)
	if not Actions.ACTIONS.has(kind): return "unbound_slot"
	var def: Dictionary = Actions.ACTIONS[kind]
	if now < int(combat.cooldowns.get(actor, {}).get(def.cd_group, 0)): return "cooldown"
	if now < int(combat.status.get(actor, {}).get("stun_until", 0)): return "stunned"
	if not combat.states.has(actor) and now < int(combat.status.get(actor, {}).get("ready_ms", 0)): return "recovery"
	if world.effects.has_kind(actor, "root", now) and def.delivery.kind in ["evade", "blink"]: return "rooted"
	if def.delivery.kind == "entity":
		var refusal: String = world.entities.readiness(actor, kind)
		if not refusal.is_empty(): return refusal
	if def.delivery.kind == "implement":
		var refusal: String = world.implements.readiness(actor, kind)
		if not refusal.is_empty(): return refusal
	var cost: String = Costs.check(world, actor, Costs.from_action(def))
	if not cost.is_empty(): return cost
	if combat.states.has(actor) and now < Actions.cancel_ms(combat.states[actor], button): return "action_committed"
	return "intent_pending" if combat.intents.has(actor) else ""

func _combat(world: RefCounted, actor: int, entry: Dictionary, spec: Dictionary, now: int) -> void:
	var combat: RefCounted = world.combat
	if entry.task.get("kind", "") == "sequence" and now >= int(entry.task.deadline_ms): entry.task.clear()
	var contact: Dictionary = combat.engagements[actor]
	var origin: Vector2 = combat.position(world, actor)
	var observed: Variant = world.sight.observed_position(world, actor, contact.target) if contact.target > 0 else null
	if observed != null:
		if not combat.alive(world, contact.target): combat.finish(world, actor, now); return
		contact.last_seen_pos = observed
		contact.last_seen_ms = now
		contact.search_tile = -1
	elif contact.last_seen_ms >= 0 and (now - int(contact.last_seen_ms) >= combat.CONTACT_MEMORY_MS or origin.distance_to(contact.last_seen_pos) < 0.5 or (contact.search_tile >= 0 and origin.distance_to(Terrain.center(contact.search_tile)) < 0.4)):
		combat.finish(world, actor, now); return
	var goal: Vector2 = contact.last_seen_pos if contact.target > 0 else contact.destination
	if goal.x < 0: return
	var direction: Vector2 = origin.direction_to(goal)
	var distance: float = origin.distance_to(goal)
	var clear: bool = Terrain.blocking_fraction(world.terrain.blocked, origin, goal) < 0
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	page.aims[slot % 256] = direction if not direction.is_zero_approx() else page.aims[slot % 256]
	if combat.states.has(actor):
		var state: Dictionary = combat.states[actor]
		if observed != null and now < int(state.started_ms) + int(Actions.ACTIONS[state.kind].get("lock", 0)) and not direction.is_zero_approx():
			state.direction = Vector2(state.direction).rotated(clampf(Vector2(state.direction).angle_to(direction), -0.20, 0.20))
	if entry.mode == "flee":
		if distance > 9.0 or (observed == null and now - int(contact.last_seen_ms) > 1500): combat.finish(world, actor, now); return
		var escape: Vector2 = _retreat_point(world, actor, direction)
		if escape.x < 0:
			_steer(world, actor, Vector2.ZERO)
			_record_trace(actor, now, entry, -1, "no_escape_route")
		else: _move(world, actor, entry, escape, now, false)
		return
	if observed == null or not clear:
		# Abandon future steps; an already admitted strike keeps its own commitment.
		if entry.task.get("kind", "") == "sequence": entry.task.clear()
		_move(world, actor, entry, goal, now, observed == null)
		return
	var desired_min: float = spec.min
	var desired_max: float = spec.max if spec.max > 0 else float(combat.profile(world, actor).range) * 0.85
	if desired_min > 0 and distance < desired_min:
		var retreat: Vector2 = _retreat_point(world, actor, direction)
		_steer(world, actor, origin.direction_to(retreat) if retreat.x >= 0 else Vector2.ZERO)
	elif distance > desired_max + 0.4:
		_move(world, actor, entry, goal - direction * desired_max, now, false)
	else: _steer(world, actor, Vector2.ZERO)
	if now < int(entry.ready_ms): return
	if entry.task.get("kind", "") == "sequence":
		_sequence(world, actor, entry, spec, goal, now); return
	var ready: Dictionary = {}
	var rejects: Dictionary = {}
	for button: String in ["primary", "skill", "skill2", "skill3", "step"]:
		var refusal: String = _ready_reason(world, actor, button, now)
		ready[button] = refusal.is_empty()
		if not refusal.is_empty(): rejects[button] = refusal
	var observation: Dictionary = {"visible": true, "clear": clear, "distance": distance, "range": combat.profile(world, actor).range,
		"health": float(page.health[slot % 256]) / page.max_health[slot % 256], "hit_ms": entry.hit_ms}
	var intent: Dictionary = Defs.EVALUATORS[spec.evaluator].choose(observation, spec, ready, entry.rule_due, now)
	latest[actor] = {"rule": intent.rule, "action": intent.action, "rejected": rejects, "at_ms": now}
	match str(intent.action):
		"cast":
			var result: String = _cast(world, actor, entry, str(intent.button), goal, spec, now)
			if result == "started": entry.rule_due[intent.rule] = now + int(intent.interval)
			_record_trace(actor, now, entry, intent.rule, result)
		"sequence":
			var button: String = str(intent.sequence[0])
			var result: String = _cast(world, actor, entry, button, goal, spec, now)
			if result in ["started", "buffered"]:
				entry.task = {"id": _id(), "kind": "sequence", "steps": intent.sequence.duplicate(), "index": 0,
					"binding": entry.task.binding, "waiting": entry.task.waiting, "button": button, "result": "", "deadline_ms": now + 6000}
				entry.rule_due[intent.rule] = now + int(intent.interval)
			else: entry.rule_due[intent.rule] = now + 300 # Failed start yields to other rules.
			_record_trace(actor, now, entry, intent.rule, "sequence" if result in ["started", "buffered"] else result)
		"approach":
			if distance > desired_max: _move(world, actor, entry, goal - direction * desired_max, now, false)
		"wait": _steer(world, actor, Vector2.ZERO)

func _cast(world: RefCounted, actor: int, entry: Dictionary, button: String, goal: Vector2, spec: Dictionary, now: int) -> String:
	var direction: Vector2 = world.combat.position(world, actor).direction_to(goal)
	var move: Vector2 = movement.get(actor, Vector2.ZERO)
	if button == "step":
		var origin: Vector2 = world.combat.position(world, actor)
		var retreat: Vector2 = _retreat_point(world, actor, direction) if spec.min > 0 else goal
		if retreat.x < 0: return "target_blocked"
		move = origin.direction_to(retreat)
	_submitting = actor
	var target: int = int(world.combat.engagements.get(actor, {}).get("target", 0))
	var result: String = world.combat.request(world, actor, button, direction, move, now, goal, target)
	_submitting = 0
	# A legal cancel has already ended the previous host and cleared its task.
	# Only create the replacement after the executor actually admits it.
	if result in ["started", "buffered"] and entry.task.is_empty():
		entry.task = {"id": _id(), "kind": "host", "binding": {}, "result": "", "waiting": ""}
	if result == "started":
		entry.task["binding"] = world.gate.current(actor)
		entry.task["button"] = button
		entry.task["result"] = ""
		entry.task["waiting"] = "running"
	elif result == "buffered":
		entry.task["binding"] = {}
		entry.task["result"] = ""
		entry.task["waiting"] = "buffered"
		entry.task["button"] = button
	else: entry.ready_ms = now + 100
	return result

func _sequence(world: RefCounted, actor: int, entry: Dictionary, spec: Dictionary, goal: Vector2, now: int) -> void:
	var task: Dictionary = entry.task
	if now >= int(task.deadline_ms): task.clear(); return
	if task.waiting == "buffered": return
	if not task.binding.is_empty():
		# A confirmed legal cancel may advance the combination before natural end.
		# The executor still decides whether the replacement can actually start.
		var following: int = int(task.index) + 1
		if task.binding.domain != "combat" or following >= task.steps.size(): return
		var next_button: String = task.steps[following]
		if _ready(world, actor, next_button, now):
			var result: String = _cast(world, actor, entry, next_button, goal, spec, now)
			if result in ["started", "buffered"]: task.index = following
		return
	if task.waiting == "running":
		if task.result != "completed": task.clear(); return
		task.index += 1
		task.waiting = ""
	if task.index >= task.steps.size(): task.clear(); return
	var button: String = task.steps[task.index]
	var refusal: String = _ready_reason(world, actor, button, now)
	if not refusal.is_empty() and refusal not in ["action_committed", "stunned", "recovery", "rooted", "intent_pending"]:
		task.clear()
		_record_trace(actor, now, entry, -1, refusal)
	elif refusal.is_empty():
		var result: String = _cast(world, actor, entry, button, goal, spec, now)
		if result not in ["started", "buffered"]: task.clear()

func _steer(world: RefCounted, actor: int, direction: Vector2) -> void:
	movement[actor] = direction.limit_length(1.0)
	if world.combat.states.has(actor): return
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	world.clear_navigation(actor)
	page.modes[slot % 256] = Units.Mode.IDLE if direction.is_zero_approx() else Units.Mode.DIRECT

func _retreat_point(world: RefCounted, actor: int, toward: Vector2) -> Vector2:
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	var origin: Vector2 = page.positions[slot % 256]
	# Bounded local geometry, never queries an unseen opponent's state.
	for angle: float in [0.0, 0.65, -0.65, 1.3, -1.3]:
		var point: Vector2 = origin - toward.rotated(angle) * 2.0
		if world.terrain.segment_clear(origin, point, page.radii[slot % 256], page.flight[slot % 256] > 0): return point
	return Vector2(-1, -1)

func _move(world: RefCounted, actor: int, entry: Dictionary, point: Vector2, now: int, search: bool) -> void:
	movement.erase(actor)
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	if not world.combat.states.has(actor) and page.modes[row] == Units.Mode.DIRECT:
		page.direct_velocities[row] = Vector2.ZERO
		page.modes[row] = Units.Mode.IDLE
	if world.combat.states.has(actor) or now < int(entry.repath_ms): return
	if not world.gate.check(world, actor, now).is_empty() or world.effects.has_kind(actor, "root", now): return
	var projected: Vector2 = world.terrain.project_point(point, page.radii[row], page.flight[row] > 0)
	if projected.x < 0: world.combat.blocked(world, actor, now); return
	if search: world.combat.engagements[actor].search_tile = Terrain.index(Vector2i(projected))
	if projected.distance_squared_to(entry.last_goal) >= 0.0625 or page.modes[row] != Units.Mode.COMBAT_MOVE:
		page.move_to(row, projected, Units.Mode.COMBAT_MOVE)
		entry.last_goal = projected
		world.combat.repaths += 1
	entry.repath_ms = now + 300

func _record_trace(actor: int, now: int, entry: Dictionary, rule: int, result: String) -> void:
	var previous: Dictionary = trace.back() if not trace.is_empty() else {}
	if previous.get("actor") == actor and previous.get("rule") == rule and previous.get("result") == result: return
	trace.append({"actor": actor, "at_ms": now, "policy": entry.policy, "mode": entry.mode, "rule": rule, "result": result})
	if trace.size() > 64: trace.pop_front()

func describe(actor: int) -> Dictionary:
	var result: Dictionary = State.copy(records.get(actor, {}))
	result["choice"] = State.copy(latest.get(actor, {}))
	return result

func _feedback_valid(world: RefCounted, value: Variant) -> bool:
	if not value is Array or value.size() > FEEDBACK_LIMIT: return false
	var seen: Dictionary = {}
	for failure: Variant in value:
		if not failure is Dictionary or failure.size() != 6: return false
		for field: Variant in failure:
			if field not in ["operation", "target", "reason", "at_ms", "until_ms", "evidence"]: return false
		if not failure.get("operation") is String or not failure.operation.is_valid_identifier() or failure.operation.length() > 64: return false
		if not failure.get("target") is int or failure.target <= 0 or failure.target >= world.objects.next_id: return false
		if not failure.get("reason") is String or not failure.reason.is_valid_identifier() or failure.reason.length() > 80: return false
		if not failure.get("at_ms") is int or failure.at_ms < 0 or failure.at_ms > world.elapsed_ms: return false
		if not failure.get("until_ms") is int or failure.until_ms - failure.at_ms not in [FEEDBACK_LONG_MS, FEEDBACK_SHORT_MS]: return false
		if not failure.get("evidence") is Dictionary: return false
		for field: Variant in failure.evidence:
			if field not in EVIDENCE_FIELDS: return false
			var fact: Variant = failure.evidence[field]
			if field in ["kind", "definition"]:
				if not fact is String or fact.length() > 128: return false
			elif not fact is int or fact < -1 or fact > 2147483647: return false
		var key: String = "%s:%d" % [failure.operation, failure.target]
		if seen.has(key): return false
		seen[key] = true
	return true

func valid(world: RefCounted) -> bool:
	if catalog_signature != Defs.SIGNATURE or not Defs.ERRORS.is_empty() or next_task < 1: return false
	var ids: Dictionary = {}
	for actor: Variant in records:
		var entry: Variant = records[actor]
		if not actor is int or not world.actor_slots.has(actor) or not world.combat.alive(world, actor) or not entry is Dictionary: return false
		if entry.size() != RECORD_FIELDS.size(): return false
		for key: Variant in entry:
			if key not in RECORD_FIELDS: return false
		if not entry.get("policy") is String or not Defs.POLICIES.has(entry.policy) or not entry.get("params") is Dictionary or not Defs.parameters_valid(entry.params): return false
		var spec: Dictionary = Defs.POLICIES[entry.policy].merged(entry.params, true)
		if spec.min > spec.max: return false
		if not entry.get("manual") is bool or entry.get("mode") not in ["idle", "manual", "life", "fight", "flee", "follow"]: return false
		if not entry.get("life_dirty") is bool: return false
		if not _feedback_valid(world, entry.get("feedback")): return false
		if entry.manual != (entry.mode == "manual"): return false
		if in_combat(actor) and not world.combat.engagements.has(actor): return false
		for field: String in ["next_ms", "hit_ms", "ready_ms", "repath_ms", "follow_ms"]:
			if not entry.get(field) is int or entry[field] < (-1 if field in ["next_ms", "hit_ms"] else 0) or entry[field] > world.elapsed_ms + 10000: return false
		if entry.hit_ms > world.elapsed_ms or not entry.get("last_reason") is String or not entry.get("last_goal") is Vector2 or not entry.last_goal.is_finite(): return false
		if entry.last_goal != Vector2(-1, -1) and (entry.last_goal.x < 0 or entry.last_goal.y < 0 or entry.last_goal.x >= Terrain.SIZE or entry.last_goal.y >= Terrain.SIZE): return false
		if (entry.next_ms >= 0) != wakeups.has(actor): return false
		if not entry.get("rule_due") is Dictionary or not entry.get("task") is Dictionary: return false
		for index: Variant in entry.rule_due:
			if not index is int or index < 0 or index >= spec.rules.size() or not entry.rule_due[index] is int or entry.rule_due[index] < 0 or entry.rule_due[index] > world.elapsed_ms + 10000: return false
		var task: Dictionary = entry.task
		if task.is_empty(): continue
		if not task.get("id") is int or task.id < 1 or task.id >= next_task or ids.has(task.id): return false
		ids[task.id] = true
		if task.get("kind") not in ["host", "sequence"] or not task.get("binding") is Dictionary or not task.get("result") is String or task.get("waiting") not in ["", "running", "buffered"]: return false
		if not task.binding.is_empty() and not world.gate.matches(actor, task.binding): return false
		var fields: Array = ["id", "kind", "binding", "result", "waiting", "button"] if task.kind == "host" else ["id", "kind", "binding", "result", "waiting", "button", "steps", "index", "deadline_ms"]
		if task.has("operation") or task.has("target") or task.has("approach"):
			if task.kind != "host" or not task.get("operation") is String or not task.operation.is_valid_identifier() or task.operation.length() > 64: return false
			if not task.get("target") is int or task.target <= 0 or task.target >= world.objects.next_id or not task.get("approach") is bool: return false
			if task.binding.get("domain", "") == "interaction":
				var action: Dictionary = world.actions.get(actor, {})
				if task.target != action.get("target") or task.operation != action.get("kind") or task.approach: return false
			fields.append_array(["operation", "target", "approach"])
		for key: Variant in task:
			if key not in fields: return false
		if task.waiting == "buffered":
			if not task.binding.is_empty() or task.get("button", "") != world.combat.intents.get(actor, {}).get("button", ""): return false
		elif task.kind == "host" and (task.waiting != "running" or task.binding.is_empty()): return false
		if task.waiting == "running" and task.binding.is_empty() and task.result != "completed": return false
		if task.kind == "sequence":
			if not task.get("steps") is Array or task.steps.is_empty() or task.steps.size() > 8 or not task.get("index") is int or task.index < 0 or task.index >= task.steps.size(): return false
			if not task.get("deadline_ms") is int or task.deadline_ms < 0 or task.deadline_ms > world.elapsed_ms + 6000 or not task.get("button") is String: return false
			for button: Variant in task.steps:
				if button not in ["primary", "skill", "skill2", "skill3", "step"]: return false
	for actor: Variant in wakeups:
		if not actor is int or not records.has(actor) or not wakeups[actor] is String: return false
	for actor: Variant in movement:
		if not actor is int or not records.has(actor) or not in_combat(actor) or not movement[actor] is Vector2 or not movement[actor].is_finite() or movement[actor].length() > 1.001: return false
	return true
