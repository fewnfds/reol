extends RefCounted
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const MAX_WAKE_MS: int = 3600000 # Shared sleeping calendar; tactical fields retain short bounds.
## Owner-side coordination; no per-agent Node or new world clock.
const Defs = preload("res://scripts/sim/kernel/decision_defs.gd")
const Actions = preload("res://scripts/sim/kernel/action_defs.gd")
const Costs = preload("res://scripts/sim/kernel/action_costs.gd")
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const State = preload("res://scripts/sim/kernel/state.gd")
const MinTimeQueue = preload("res://scripts/sim/execution/min_time_queue.gd")
const STATE_FIELDS: Array = ["records", "wakeups", "movement", "next_task", "catalog_signature"]
const RECORD_FIELDS: Array = ["policy", "params", "manual", "mode", "next_ms", "task", "rule_due", "hit_ms", "ready_ms", "repath_ms", "follow_ms", "last_goal", "last_reason", "life_dirty", "feedback"]
const FEEDBACK_LIMIT: int = 16
const FEEDBACK_LONG_MS: int = 5000
const FEEDBACK_SHORT_MS: int = 1500
const EVIDENCE_FIELDS: Array = ["revision"]
const LIFE_CHANGES: Array = ["department_work", "needs_changed", "request_review", "institution_review", "source_review", "goal_added", "disposition_changed", "condition_changed", "aptitudes_changed", "capabilities_changed"]
const LIFE_RETRIES: Array = ["life_ready", "life_result", "planning_budget", "retry_due", "method_due", "resume", "policy_bound"]
var records: Dictionary = {}
var wakeups: Dictionary = {} # actor -> {reason: due_ms}; independent owner timers.
var next_task: int = 1
var catalog_signature: String = Defs.SIGNATURE
var movement: Dictionary = {} # Held autonomous input; saved, unlike local keyboard state.
var trace: Array[Dictionary] = [] # Bounded, diagnostic only.
var latest: Dictionary = {}
var evaluations: int = 0
var work_usec: int = 0
var _submitting: int = 0
# Derived from saved timers. A held obligation needs one admission check on
# wake, cancellation or restore. Once queued, only a real stimulus is due here.
var _review_due := MinTimeQueue.new()
var _recover_admission: Dictionary[int, bool] = {}
var _tactical: Dictionary[int, bool] = {}
var _indexed: bool = false

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
	cancel_life(world, actor)
	var entry: Dictionary = _record(world, actor)
	_submitting = actor
	world.end_run(actor, world.operation_time(), "preempted", {}, false)
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
	if entry.manual: return
	var due: int = at + maxi(0, delay)
	if reason in ["life_result", "await_commitment"]: due = ((due + 49) / 50) * 50
	var timers: Dictionary = wakeups.get(actor, {})
	if reason == "life_result" and not in_combat(actor):
		for pending: String in timers.keys():
			if pending.begins_with("execution_"): timers.erase(pending)
	timers[reason] = mini(int(timers.get(reason, due)), due)
	wakeups[actor] = timers
	if _is_hold(reason): _recover_admission[actor] = true
	_sync_next(actor)
	# A future appointment is not a change to today's inputs.
	if due <= at and reason in LIFE_CHANGES: entry.life_dirty = true
	if due <= at and reason in LIFE_CHANGES and entry.task.get("purpose", "") == "clearance": entry.task["reconsider"] = true

static func _is_hold(reason: String) -> bool:
	return reason in ["life_pending", "exploration_observe"]

func _sync_next(actor: int) -> void:
	var next: int = -1
	var review: int = -1
	var timers: Dictionary = wakeups.get(actor, {})
	var recover: bool = _recover_admission.has(actor)
	for reason: String in timers:
		var due: int = timers[reason]
		if next < 0 or due < next: next = due
		if (recover or not _is_hold(reason)) and (review < 0 or due < review): review = due
	records[actor].next_ms = next
	if next < 0:
		wakeups.erase(actor)
		_recover_admission.erase(actor)
	if review >= 0: _review_due.set_time(str(actor), review)
	else: _review_due.erase(str(actor))
	if next >= 0 and in_combat(actor): _tactical[actor] = true
	else: _tactical.erase(actor)

func _ensure_indexed() -> void:
	if _indexed: return
	_indexed = true
	_review_due.clear()
	_recover_admission.clear()
	_tactical.clear()
	for actor: int in wakeups.keys():
		var timers: Dictionary = wakeups[actor]
		if timers.has("life_pending") or timers.has("exploration_observe"): _recover_admission[actor] = true
		_sync_next(actor)

func _forget_schedule(actor: int) -> void:
	wakeups.erase(actor)
	_review_due.erase(str(actor))
	_tactical.erase(actor)
	_recover_admission.erase(actor)

func _take_due(actor: int, now: int) -> Array[String]:
	var result: Array[String] = []
	var timers: Dictionary = wakeups[actor]
	for reason: String in timers.keys():
		if _is_hold(reason) or int(timers[reason]) > now: continue
		result.append(reason)
		timers.erase(reason)
	_sync_next(actor)
	return result

func in_combat(actor: int) -> bool:
	return records.get(actor, {}).get("mode", "") in ["fight", "flee"]

func cancel_life(world: RefCounted, actor: int) -> void:
	# A proposal and its issued query allowance have one lifecycle. Switching
	# prerequisites must retire both before reporting the service item finished.
	world.deferred.cancel("life", actor)
	world.livelihood.cancel_plan(actor)
	if wakeups.get(actor, {}).has("life_pending"):
		_recover_admission[actor] = true
		_sync_next(actor)

func suspend(world: RefCounted, actor: int) -> void:
	cancel_life(world, actor)
	var entry: Dictionary = _record(world, actor)
	entry.manual = true
	entry.life_dirty = false
	entry.mode = "manual"
	entry.task.clear()
	entry.next_ms = -1
	_forget_schedule(actor)
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
	_forget_schedule(actor)
	movement.erase(actor)
	latest.erase(actor)

func released(actor: int) -> void:
	if not records.has(actor): return
	records[actor].task.clear()
	if _submitting != actor: records[actor].life_dirty = false
	records[actor].mode = "idle" if not records[actor].manual else "manual"
	if _submitting != actor:
		var timers: Dictionary = wakeups.get(actor, {})
		for reason: String in timers.keys():
			if reason in ["life_pending", "exploration_observe", "life_ready", "life_result", "goal_added", "resume", "policy_bound"] or reason.begins_with("execution_"): timers.erase(reason)
		_sync_next(actor)
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
			for key: String in ["purpose", "reconsider", "knowledge_revision"]: entry.task.erase(key)
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
	return world.knowledge.evidence(actor, target)

func _prune_feedback(world: RefCounted, actor: int, at: int) -> void:
	var failures: Array = records[actor].feedback
	for index: int in range(failures.size() - 1, -1, -1):
		var failure: Dictionary = failures[index]
		if at >= int(failure.until_ms) or ((not Operations.contact_operation(str(failure.operation)) or failure.reason in ["out_of_reach", "path_failed", "no_operation_place"]) and failure.evidence != _evidence(world, actor, failure.target)): failures.remove_at(index)

func retry_allowed(world: RefCounted, actor: int, operation: String, target: int, at: int) -> bool:
	if not world.knowledge.can_attempt(actor, operation, target, at): return false
	var entry: Dictionary = _record(world, actor)
	_prune_feedback(world, actor, at)
	for failure: Dictionary in entry.feedback:
		if failure.operation == operation and failure.target == target: return false
	return true

func result(world: RefCounted, actor: int, operation: String, target: int, reason: String, at: int, status: String = "") -> void:
	if operation.is_empty() or target <= 0 or not world.actor_slots.has(actor) or not world.combat.alive(world, actor): return
	var entry: Dictionary = _record(world, actor)
	_prune_feedback(world, actor, at)
	var succeeded: bool = status == "completed" if not status.is_empty() else reason in ["completed", "transferred", "arrived"]
	if not succeeded and reason in ["accepted", "started", "buffered", "replaced", "preempted", "interrupted", "partner_left", "cancelled", "action_committed", "stunned", "recovery", "rooted", "intent_pending"]: return
	if reason in ["planning_budget", "response_not_due", "shipment_changed", "request_changed"]: return
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

func knowledge_changed(world: RefCounted, actor: int, at: int, reason: String) -> void:
	if not world.objects.records.get(actor, {}).get("autonomous", false) or not world.combat.alive(world, actor): return
	var entry: Dictionary = _record(world, actor)
	if entry.manual or in_combat(actor): return
	var search: bool = entry.task.get("binding", {}).get("domain") == "work" and not entry.task.has("operation")
	if world.gate.current(actor).is_empty() or search:
		wake(world, actor, at, reason, 50 + actor % 10 * 50)

func focus(world: RefCounted, actor: int, at: int) -> void:
	# Explicit host request (summon command/fixture), distinct from discovery.
	var entry: Dictionary = _record(world, actor)
	if entry.manual: return
	_enter(world, actor, entry, "fight", at)

func ended(world: RefCounted, actor: int, binding: Dictionary, at: int, reason: String, activity: Dictionary = {}) -> void:
	if not records.has(actor): return
	if not activity.is_empty(): result(world, actor, activity.operation, activity.target, activity.reason, at, activity.status)
	var entry: Dictionary = records[actor]
	var task: Dictionary = entry.task
	if task.get("binding", {}) == binding and not binding.is_empty():
		var clearance: bool = clearance_quiet(world, actor) and reason == "completed"
		world.livelihood.task_ended(actor, int(task.id))
		if activity.is_empty() and task.has("operation") and (reason != "completed" or not task.get("approach", false)):
			result(world, actor, task.operation, task.target, reason, at, str(activity.get("status", "")))
		task.binding = {}
		task.result = reason
		if task.get("kind") == "host" or (_submitting != actor and reason != "completed"): task.clear()
		if _submitting != actor and not clearance: wake(world, actor, at, "execution_" + reason)
	elif binding.get("domain") == "partner" and entry.life_dirty:
		wake(world, actor, at, "life_ready")

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
	cancel_life(world, actor)
	_submitting = actor
	world.end_run(actor, now, "preempted", {}, false)
	world.clear_navigation(actor)
	_submitting = 0
	entry.mode = mode
	entry.task.clear()
	entry.ready_ms = now + int(policy(world, actor).reaction_ms)
	entry.repath_ms = 0
	return true

func next_boundary(now: int, end: int) -> int:
	_ensure_indexed()
	for actor: int in _tactical:
		if not in_combat(actor): continue
		for reason: String in wakeups[actor]:
			if reason not in ["tactical_due", "hurt", "contact", "contact_ended", "buffer_expired", "await_commitment"] and not reason.begins_with("execution_"): continue
			var due: int = wakeups[actor][reason]
			if due > now: end = mini(end, due)
	return end

func clearance_quiet(world: RefCounted, actor: int) -> bool:
	var task: Dictionary = records.get(actor, {}).get("task", {})
	return task.get("purpose", "") == "clearance" and not task.get("reconsider", false) and int(task.get("knowledge_revision", -1)) == int(world.knowledge.records.get(actor, {}).get("next_revision", 1))

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
	_ensure_indexed()
	# An actor that becomes due after this collection enters the next
	# preparation. Already due actors still read current timers and facts.
	var ready: PackedInt64Array = []
	var key: String = _review_due.first_through(now)
	while not key.is_empty():
		ready.append(int(key))
		_review_due.erase(key)
		key = _review_due.first_through(now)
	for actor: int in ready:
		if not wakeups.has(actor): continue
		if not world.combat.alive(world, actor): forget(actor); continue
		var entry: Dictionary = records[actor]
		var timers: Dictionary = wakeups[actor]
		if _recover_admission.erase(actor):
			if timers.has("life_pending"):
				var identity: String = world.deferred.key("life", actor)
				if not world.deferred.ready.has(identity) and not world.deferred.jobs.has(identity):
					if not world.gate.current(actor).is_empty() and _life_preemptible(world, actor): entry.life_dirty = true
					world.deferred.request("life", actor, int(timers.life_pending), 0 if entry.life_dirty else 1)
			if timers.has("exploration_observe"): world.deferred.request("observe", actor, int(timers.exploration_observe), 1)
		var reasons: Array[String] = _take_due(actor, now)
		if reasons.is_empty(): continue
		# A real changed input may justify a new self-contained plan before the
		# scan finishes. Ordinary retries cannot bypass their own prerequisite.
		if reasons.any(func(cause: String): return cause in LIFE_CHANGES) and wakeups.has(actor):
			wakeups[actor].erase("exploration_observe")
			_sync_next(actor)
		var reason: String = reasons.back()
		if entry.task.get("purpose", "") == "clearance" and reasons.any(func(cause: String): return cause not in ["space_needed", "life_pending"]): entry.task.reconsider = true
		for cause: String in reasons:
			if cause in LIFE_CHANGES or cause in LIFE_RETRIES:
				entry.life_dirty = true
				if entry.task.get("purpose", "") == "clearance": entry.task["reconsider"] = true
			elif cause in ["knowledge_observed", "knowledge_delivered"] and entry.task.get("binding", {}).get("domain") == "work" and not entry.task.has("operation"):
				entry.life_dirty = true # New evidence can end an uncommitted search.
		if world.deferred.jobs.has(world.deferred.key("life", actor)) and reasons.any(func(cause: String): return cause != "life_pending"): entry.life_dirty = true
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
			if not world.gate.current(actor).is_empty() and not _life_preemptible(world, actor):
				entry.life_dirty = true # Host completion will resume the owed review.
				continue
			if wakeups.get(actor, {}).has("exploration_observe") and world.gate.current(actor).is_empty():
				continue
			if reasons.size() == 1 and reason == "space_needed" and not entry.life_dirty:
				preload("res://scripts/sim/kernel/service_positions.gd").step_aside(world, actor, now)
				entry.last_reason = reason
				continue
			if not world.gate.check(world, actor, now).is_empty():
				wake(world, actor, now, "await_commitment", 100); continue
			if world.gate.current(actor).is_empty() or (entry.life_dirty and _life_preemptible(world, actor)):
				# A durable marker reconstructs this transient request after a save.
				# The world can advance while the proposal is queued/in flight.
				wake(world, actor, now, "life_pending")
				world.deferred.request("life", actor, now, 0 if entry.life_dirty else 1)
		else:
			entry.life_dirty = false
			if entry.mode != "follow": entry.mode = "idle"
			entry.task.clear()
			world.society.review_due(world, actor, now)
		entry.last_reason = reason
		# Independent future timers survive earlier wakes; no broad review on
		# every tactical/execution notification just to reconstruct a calendar.
	work_usec += Time.get_ticks_usec() - started_at

func _clear_pending(actor: int) -> void:
	if not records.has(actor): return
	if wakeups.has(actor): wakeups[actor].erase("life_pending")
	_sync_next(actor)

func service(world: RefCounted, actor: int, now: int) -> bool:
	var identity: String = world.deferred.key("life", actor)
	if not records.has(actor) or not world.livelihood.can_plan(world, actor, now, false):
		# A contact may arrive after prepare() and cancel an owed review before
		# the policy chooses to ignore it. Keep the debt while control is autonomous.
		if records.has(actor) and not records[actor].manual and world.objects.records.get(actor, {}).get("autonomous", false) and world.combat.alive(world, actor):
			records[actor].life_dirty = true
		cancel_life(world, actor)
		_clear_pending(actor)
		return true
	var entry: Dictionary = records[actor]
	if not world.gate.check(world, actor, now).is_empty():
		# A temporary stun/commitment does not revoke the durable request.
		wake(world, actor, now, "await_commitment", 100)
		return false
	if wakeups.get(actor, {}).has("exploration_observe") and world.gate.current(actor).is_empty():
		cancel_life(world, actor)
		world.deferred.request("observe", actor, now, 0)
		# Observation owns the dependency and wakes life when done. Keeping this
		# older blocked item at the queue head would starve its own prerequisite.
		_clear_pending(actor)
		return true
	if world.deferred.jobs.has(identity):
		var job: RefCounted = world.deferred.poll(identity)
		if job == null: return false
		_clear_pending(actor)
		world.livelihood.complete_plan(world, actor, job, now)
		if entry.life_dirty: wake(world, actor, now, "life_ready")
		entry.mode = "life" if not world.gate.current(actor).is_empty() else "idle"
		track_host(world, actor)
		_record_trace(actor, now, entry, -1, "life_selected")
		return true
	if not world.gate.current(actor).is_empty() and (not entry.life_dirty or not _life_preemptible(world, actor)):
		if not _life_preemptible(world, actor): entry.life_dirty = true
		_clear_pending(actor)
		return true
	if world.deferred.retiring(identity) or not world.deferred.capacity(world.requested_workers): return false
	var job: RefCounted = world.livelihood.prepare_plan(world, actor, now)
	if job == null:
		_clear_pending(actor)
		return true
	# Only the coordinator consumes events. End-of-step events may not yet have
	# passed prepare(); never erase them just because a proposal starts now.
	entry.life_dirty = false
	wake(world, actor, now, "life_pending")
	world.deferred.start(identity, job, world.requested_workers)
	return false

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
			if not fact is int or fact < 1 or fact > 999999999999: return false
		var key: String = "%s:%d" % [failure.operation, failure.target]
		if seen.has(key): return false
		seen[key] = true
	return true

func valid(world: RefCounted) -> bool:
	if catalog_signature != Defs.SIGNATURE or not Defs.ERRORS.is_empty() or next_task < 1: return false
	# Current v32 single-reason saves are read once into the richer calendar.
	# Keep every new timer in saves; projecting only the nearest would lose causes.
	for actor: Variant in wakeups:
		if not actor is int or not records.get(actor) is Dictionary: return false
		if wakeups[actor] is String:
			wakeups[actor] = {wakeups[actor]: records[actor].get("next_ms", -1)}
		var timers: Variant = wakeups[actor]
		if not timers is Dictionary or timers.is_empty() or timers.size() > 64: return false
		var nearest: int = -1
		for reason: Variant in timers:
			if not reason is String or not reason.is_valid_identifier() or reason.length() > 80: return false
			var due: Variant = timers[reason]
			if not due is int or due < 0 or due > world.elapsed_ms + MAX_WAKE_MS: return false
			if nearest < 0 or due < nearest: nearest = due
		if records[actor].get("next_ms") != nearest: return false
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
			if not entry.get(field) is int or entry[field] < (-1 if field in ["next_ms", "hit_ms"] else 0) or entry[field] > world.elapsed_ms + (MAX_WAKE_MS if field == "next_ms" else 10000): return false
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
		if task.has("purpose"):
			if task.kind != "host" or not task.purpose is String or task.purpose != "clearance" or task.binding.get("domain") != "work": return false
			if task.has("operation") or task.has("target") or task.has("approach"): return false
			if not task.get("reconsider") is bool or not task.get("knowledge_revision") is int or task.knowledge_revision < 1: return false
			var slot: int = world.actor_slots[actor]
			if world.pages[slot / 256].modes[slot % 256] != Units.Mode.EXPLORE: return false
			fields.append_array(["purpose", "reconsider", "knowledge_revision"])
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
	for actor: Variant in movement:
		if not actor is int or not records.has(actor) or not in_combat(actor) or not movement[actor] is Vector2 or not movement[actor].is_finite() or movement[actor].length() > 1.001: return false
	return true
