extends RefCounted
## Persistent personal goals and intentions. P5 owns tasks; hosts own all travel,
## goods and work. Planning never restores an expected inventory or work cursor.
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const Beings = preload("res://scripts/sim/kernel/being_defs.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const State = preload("res://scripts/sim/kernel/state.gd")
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
const Defs = preload("res://scripts/sim/kernel/agency_defs.gd")
const Planner = preload("res://scripts/sim/kernel/agency_planner.gd")
const STATE_FIELDS: Array = ["records", "next_goal", "catalog_signature"]
const GOAL_LIMIT: int = 16
const APPRAISAL_LIMIT: int = 24
const BUDGET_MS: int = 1000
var records: Dictionary = {}
var next_goal: int = 1
var catalog_signature: String = Defs.SIGNATURE
var decisions: int = 0
var decision_usec: int = 0
var latest: Dictionary = {} # Diagnostic only, not restored as decision truth.

func record(world: RefCounted, actor: int) -> Dictionary:
	if not records.has(actor):
		var traits: Dictionary = {}
		for index: int in Defs.DISPOSITIONS.size():
			traits[Defs.DISPOSITIONS[index]] = 0.5 + float((actor * 37 + index * 71) % 101) / 100.0
		records[actor] = {"goals": {}, "intention": {}, "dispositions": traits, "appraisals": {},
			"budget": {"window_ms": world.operation_time(), "work": 0, "cursor": 0, "goal_cursor": 0}, "explore_ms": 0, "explore_count": 0, "idle_attempts": 0, "borrowed_autonomy": false}
	return records[actor]

func add_goal(world: RefCounted, actor: int, definition: String, params: Dictionary = {}, source: int = 0) -> int:
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor) or not Defs.GOALS.has(definition) or not _params_valid(definition, params, world.objects.next_id): return 0
	if int(params.get("organization", 0)) > 0 and not world.institutions.organizations.has(params.organization): return 0
	if source < 0 or source >= world.objects.next_id: return 0
	if Defs.GOALS[definition].driver == "responsibility":
		var share: Dictionary = world.institutions.shares.get(int(params.share), {})
		if share.get("actor") != actor or share.get("matter") != params.matter or share.get("state") != "accepted": return 0
	var entry: Dictionary = record(world, actor)
	for goal: Dictionary in entry.goals.values():
		if Defs.GOALS[definition].driver == "responsibility" and Defs.GOALS[goal.definition].driver == "responsibility" and goal.params.share == params.share and goal.state == "active": return int(goal.id)
		if goal.definition == definition and goal.params == params and goal.source == source and goal.state == "active": return int(goal.id)
	if entry.goals.size() >= GOAL_LIMIT:
		var victim: int = 0
		for id: int in entry.goals:
			if entry.goals[id].state != "active" and (victim == 0 or id < victim): victim = id
		if victim == 0: return 0
		entry.goals.erase(victim)
		if entry.intention.get("goal", 0) == victim: entry.intention = {}
	var id: int = next_goal
	next_goal += 1
	entry.goals[id] = {"id": id, "definition": definition, "params": State.copy(params), "source": source,
		"created_ms": world.operation_time(), "state": "active", "closed_ms": -1, "progress": 0, "method": {}}
	if world.objects.records[actor].get("autonomous", false): world.decisions.wake(world, actor, world.operation_time(), "goal_added")
	return id

func set_dispositions(world: RefCounted, actor: int, changes: Dictionary) -> bool:
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor): return false
	for key: Variant in changes:
		if key not in Defs.DISPOSITIONS or not (changes[key] is float or changes[key] is int) or not is_finite(float(changes[key])) or float(changes[key]) < 0.0 or float(changes[key]) > 2.0: return false
	record(world, actor).dispositions.merge(changes, true)
	if world.objects.records[actor].get("autonomous", false): world.decisions.wake(world, actor, world.operation_time(), "disposition_changed")
	return true

func initialize(world: RefCounted) -> void:
	for page: RefCounted in world.pages:
		for row: int in page.ids.size():
			var id: int = page.ids[row]
			if id == 1: continue
			world.objects.records[id]["autonomous"] = true
			world.adopt_work(id, 0)
			page.modes[row] = Units.Mode.REST
			page.due_ms[row] = 50 + (id % 20) * 50
			_ensure_goals(world, id)
			# Original ordinary-world labor is an explicit recurring purpose.
			if Beings.has(world.objects.records[id], "work"):
				add_goal(world, id, "delivery", {"item": "wood", "amount": 4, "repeat": true})
			if id % 20 == 2:
				world.objects.add(id, "grain", 4); world.objects.add(id, "water", 2)
				page.hunger[row] = 2800
			if id % 20 == 3: page.energy[row] = 2800

func _ensure_goals(world: RefCounted, actor: int) -> void:
	var person: Dictionary = world.objects.records[actor]
	if Beings.has(person, "metabolism"):
		add_goal(world, actor, "sustenance")
		add_goal(world, actor, "rested")
	if Beings.has(person, "environment"): add_goal(world, actor, "recovery")
	if Beings.has(person, "work"): add_goal(world, actor, "custody")

func think(world: RefCounted, id: int, at: int) -> void:
	if world.objects.records.get(id, {}).get("autonomous", false): world.decisions.wake(world, id, at, "life_ready")

func choose(world: RefCounted, id: int, at: int) -> void:
	var started: int = Time.get_ticks_usec()
	_think(world, id, at)
	decision_usec += Time.get_ticks_usec() - started

func _self_view(world: RefCounted, actor: int) -> Dictionary:
	var view: Dictionary = world.operation_actor(actor)
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	view["hunger"] = page.hunger[slot % 256]
	view["speed"] = page.move_speed[slot % 256]
	view["recovering"] = Growth.needs_rest(world.objects.records[actor]) and page.body_heat[slot % 256] >= 5.0 and page.body_heat[slot % 256] <= 40.0
	return view

func _utility(goal: Dictionary, entry: Dictionary, actor: Dictionary, at: int) -> Dictionary:
	var spec: Dictionary = Defs.GOALS[goal.definition]
	var value: float = 0.0
	var emergency: bool = false
	match spec.driver:
		"resource":
			if not actor.body_capabilities.get("metabolism", false): return {"value": 0.0, "emergency": false}
			var current: int = int(actor[spec.metric])
			value = pow(clampf(float(int(spec.comfort) - current) / int(spec.comfort), 0.0, 1.0), float(spec.exponent))
			emergency = current <= int(spec.emergency)
		"recovery": value = 0.65 if actor.recovering else 0.0
		"development": value = 0.0 if Growth.mastered(actor, goal.params.method) else 1.0
		"delivery", "operation": value = 1.0
		"responsibility": value = 1.0 if actor.get("responsibilities", {}).has(int(goal.params.share)) else 0.0
		"custody": value = 1.0 if not actor.returns.is_empty() else 0.0
	value *= float(spec.weight)
	if not spec.disposition.is_empty(): value *= float(entry.dispositions[spec.disposition])
	if value > 0.0: value += minf(0.08, float(at - int(goal.created_ms)) / 3000000.0)
	if emergency: value += 2.0
	return {"value": value, "emergency": emergency}

func should_preempt(world: RefCounted, actor: int, at: int) -> bool:
	if not records.has(actor): return true
	var entry: Dictionary = records[actor]
	var view: Dictionary = _self_view(world, actor)
	var current: Dictionary = entry.goals.get(entry.intention.get("goal", 0), {})
	var current_score: float = float(_utility(current, entry, view, at).value) if not current.is_empty() and current.state == "active" else 0.0
	if at - int(entry.budget.window_ms) >= BUDGET_MS:
		entry.budget.window_ms = at; entry.budget.work = 0
	var self_target: Dictionary = world.operation_target(actor)
	self_target.inventory = view.inventory.duplicate()
	var planner := Planner.new()
	var clues: Dictionary = world.knowledge.known(actor, at)
	planner.configure(view, self_target, clues, _blocked(world, actor, entry, at), world.combat.position(world, actor), at, entry.budget, _preference(entry, view, clues, at))
	for goal: Dictionary in entry.goals.values():
		if goal.state != "active": continue
		var score: Dictionary = _utility(goal, entry, view, at)
		if score.value <= current_score + 0.12 or (not score.emergency and score.value < 0.25): continue
		for approach: String in Defs.GOALS[goal.definition].approaches:
			var allowance: int = mini(16, Planner.WORK_LIMIT - 32 - int(entry.budget.work))
			if allowance <= 0: return false # Leave enough room to adopt a different method.
			for option: Dictionary in planner.candidates(goal, Defs.APPROACHES[approach], allowance):
				if option.step.kind != "wait": return true
	return false

func _blocked(world: RefCounted, id: int, entry: Dictionary, at: int) -> Dictionary:
	var blocked: Dictionary = {}
	world.decisions.retry_allowed(world, id, "", 0, at)
	for failure: Dictionary in world.decisions.records[id].feedback: blocked["%s:%d" % [failure.operation, failure.target]] = true
	for experience: Dictionary in world.knowledge.records.get(id, {}).get("experiences", []):
		if experience.reason == "teacher_does_not_know" and not world.knowledge.can_attempt(id, experience.operation, experience.target, at): blocked["%s:%d" % [experience.operation, experience.target]] = true
	for key: String in entry.appraisals:
		var account: Dictionary = entry.appraisals[key]
		if account.until_ms > at and int(world.knowledge.evidence(id, account.target).get("revision", 0)) == account.revision: blocked[key] = true
	return blocked

func _refresh_goals(world: RefCounted, actor: int, entry: Dictionary, at: int) -> void:
	var person: Dictionary = world.objects.records[actor]
	for goal: Dictionary in entry.goals.values():
		if goal.state != "active": continue
		if Defs.GOALS[goal.definition].driver == "responsibility": continue # Institutions alone closes social obligations.
		var completed: bool = Defs.GOALS[goal.definition].driver == "development" and Growth.mastered(person, goal.params.method)
		var expired: bool = int(goal.params.get("expires_ms", at + 1)) <= at
		var fixed: int = int(goal.params.get("target", 0))
		if fixed > 0:
			var clue: Dictionary = world.knowledge.view(actor, fixed, at)
			if not clue.is_empty() and clue.kind != "actor" and clue.tile < 0 and int(world.knowledge.records.get(actor, {}).get("subjects", {}).get(fixed, {}).get("absent_ms", -1)) >= 0: expired = true
		if Defs.GOALS[goal.definition].driver == "operation" and goal.params.operation == "construct":
			var clue: Dictionary = world.knowledge.view(actor, int(goal.params.target), at)
			completed = not clue.is_empty() and clue.kind != "blueprint" and clue.tile >= 0
			expired = expired or (not clue.is_empty() and clue.tile < 0)
		if completed or expired:
			goal.state = "completed" if completed else "cancelled"
			goal.closed_ms = at
			if entry.intention.get("goal") == goal.id: entry.intention.task_id = 0

func _think(world: RefCounted, id: int, at: int) -> void:
	if not world.objects.records.get(id, {}).get("autonomous", false) or world.decisions.in_combat(id) or not world.gate.current(id).is_empty() or not world.gate.check(world, id, at).is_empty(): return
	decisions += 1
	_ensure_goals(world, id)
	var entry: Dictionary = record(world, id)
	if world.knowledge.record(id).due_ms <= at: world.knowledge.observe(world, id, at)
	_refresh_goals(world, id, entry, at)
	if not world.objects.records[id].get("autonomous", false): return
	if at - int(entry.budget.window_ms) >= BUDGET_MS:
		entry.budget.window_ms = at
		entry.budget.work = 0
	if int(entry.budget.work) >= Planner.WORK_LIMIT:
		world.decisions.wake(world, id, at, "planning_budget", maxi(1, int(entry.budget.window_ms) + BUDGET_MS - at)); return
	var actor: Dictionary = _self_view(world, id)
	var clues: Dictionary = world.knowledge.known(id, at)
	var self_target: Dictionary = world.operation_target(id)
	self_target.inventory = actor.inventory.duplicate()
	var blocked: Dictionary = _blocked(world, id, entry, at)
	var ordered: Array = []
	for goal: Dictionary in entry.goals.values():
		if goal.state == "active":
			var score: Dictionary = _utility(goal, entry, actor, at)
			if score.value > 0.01: ordered.append({"goal": goal, "utility": score})
	ordered.sort_custom(func(a: Dictionary, b: Dictionary): return a.utility.value > b.utility.value if not is_equal_approx(a.utility.value, b.utility.value) else a.goal.id < b.goal.id)
	var allowance: int = maxi(4, mini(32, Planner.WORK_LIMIT / maxi(1, ordered.reduce(func(sum: int, value: Dictionary): return sum + Defs.GOALS[value.goal.definition].approaches.size(), 0))))
	# Emergency needs are always sampled first. Other purposes rotate when a
	# large authored catalog consumes the query budget before every purpose fits.
	var urgent: Array = ordered.filter(func(value: Dictionary): return value.utility.emergency)
	var ordinary: Array = ordered.filter(func(value: Dictionary): return not value.utility.emergency)
	if not ordinary.is_empty():
		var offset: int = int(entry.budget.goal_cursor) % ordinary.size()
		ordinary = ordinary.slice(offset) + ordinary.slice(0, offset)
	ordered = urgent + ordinary
	var planner := Planner.new()
	var preference: Dictionary = _preference(entry, actor, clues, at)
	planner.configure(actor, self_target, clues, blocked, world.combat.position(world, id), at, entry.budget, preference)
	var best: Dictionary = {}
	var choices: Array = []
	var examined: int = 0
	for candidate: Dictionary in ordered:
		examined += 1
		for approach_id: String in Defs.GOALS[candidate.goal.definition].approaches:
			var approach: Dictionary = Defs.APPROACHES[approach_id]
			for option: Dictionary in planner.candidates(candidate.goal, approach, allowance):
				var score: float = float(candidate.utility.value) * (0.55 + 0.45 * float(option.step.confidence) * float(approach.confidence)) - minf(0.12, float(option.step.estimate_ms) / 200000.0)
				if option.step.get("social", false): score += 0.04 * (float(entry.dispositions.sociability) - 1.0)
				if entry.intention.get("goal") == candidate.goal.id and entry.intention.get("approach") == approach_id and entry.intention.get("anchor") == option.anchor and entry.intention.get("operation") == option.operation:
					score += 0.05 * float(entry.dispositions.persistence)
				var decision: Dictionary = {"goal": candidate.goal.id, "approach": approach_id, "anchor": option.anchor, "operation": option.operation,
					"score": score, "utility": candidate.utility.value, "emergency": candidate.utility.emergency, "step": option.step}
				if choices.size() < 12: choices.append(State.copy(decision))
				if best.is_empty() or score > float(best.score): best = decision
			if int(entry.budget.work) >= Planner.WORK_LIMIT: break
		if int(entry.budget.work) >= Planner.WORK_LIMIT: break
	entry.budget.cursor = (int(entry.budget.cursor) + 17) % 128
	if int(entry.budget.work) >= Planner.WORK_LIMIT and not ordinary.is_empty(): entry.budget.goal_cursor = (int(entry.budget.goal_cursor) + maxi(1, examined - urgent.size())) % GOAL_LIMIT
	latest[id] = {"at_ms": at, "choices": choices, "chosen": State.copy(best), "work": entry.budget.work}
	if best.is_empty():
		var retry_at: int = at + 10001
		for failure: Dictionary in world.decisions.records[id].feedback:
			if failure.until_ms > at: retry_at = mini(retry_at, int(failure.until_ms))
		for account: Dictionary in entry.appraisals.values():
			if account.until_ms > at: retry_at = mini(retry_at, int(account.until_ms))
		if retry_at <= at + 10000:
			world.decisions.wake(world, id, at, "retry_due", maxi(50, retry_at - at)); return
		_idle(world, id, at, not ordered.is_empty()); return
	entry.intention = {"goal": best.goal, "approach": best.approach, "anchor": best.anchor, "operation": best.operation,
		"selected_ms": at, "task_id": 0}
	entry.goals[best.goal].method = {"approach": best.approach, "operation": best.operation, "anchor": best.anchor, "selected_ms": at}
	var step: Dictionary = best.step
	if step.kind == "wait":
		world.decisions.wake(world, id, at, "method_due", maxi(100, mini(10000, int(step.until_ms) - at))); return
	var target: int = int(step.input.target)
	if step.kind == "inspect" or (target != id and not world.sight.sees(world.combat.position(world, id), int(clues.get(target, {}).get("tile", -1)), world.sight.range_for(world, id))):
		var tile: int = int(clues.get(target, {}).get("tile", -1))
		if tile >= 0: _walk_to_site(world, id, world.terrain.nearest_open(tile), at, str(step.input.get("kind", "inspect")), target)
		else: _idle(world, id, at, true)
	else:
		if target != id and not world.knowledge.refresh(world, id, target, at):
			after_action(world, id, at); return # A last-seen tile cannot track a departed person.
		var input: Dictionary = step.input.duplicate(true)
		input["autonomous"] = true
		var reason: String = world.execute_operation(id, input)
		if reason not in ["accepted", "completed"]: _rejected(world, id, input.kind, target, reason, at)
		elif reason == "completed":
			var goal: Dictionary = entry.goals[best.goal]
			if Defs.GOALS[goal.definition].driver == "operation" and goal.params.operation == input.kind and goal.params.target == target: goal.state = "completed"; goal.closed_ms = at
			after_action(world, id, at, target)
	entry.intention.task_id = int(world.decisions.records.get(id, {}).get("task", {}).get("id", 0)) if entry.goals[best.goal].state == "active" else 0

func _preference(entry: Dictionary, actor: Dictionary, clues: Dictionary, at: int) -> Dictionary:
	var result: Dictionary = entry.intention.duplicate(true)
	result["retained"] = {}
	for goal: Dictionary in entry.goals.values():
		if goal.state == "active" and not goal.method.is_empty() and _utility(goal, entry, actor, at).value > 0.01:
			result.retained.merge(_retained(goal, goal.method, clues, actor))
	return result

func _retained(goal: Dictionary, choice: Dictionary, clues: Dictionary, actor: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var operation: Dictionary = Operations.OPERATIONS.get(choice.operation, {})
	var anchor: Dictionary = clues.get(choice.anchor, {})
	# Keep prerequisites while the known method remains usable, not after its
	# actual site is known to be gone. Missing one ingredient alone is temporary.
	if choice.anchor != actor.id and int(anchor.get("tile", -1)) < 0: return result
	if not operation.is_empty():
		var organization: int = int(clues.get(choice.anchor, {}).get("organization", 0))
		var inputs: Dictionary = operation.recipe.inputs if not operation.recipe.is_empty() else operation.required_items
		var purpose: String = Stock.input_purpose(operation)
		for item: String in inputs: result["%d:%s:%s" % [organization, purpose, item]] = true
	var method: String = str(goal.params.method) if Defs.GOALS[goal.definition].driver == "development" else str(operation.get("required_method", ""))
	if not method.is_empty():
		var book: String = Growth.Defs.METHODS[method].study_item
		var organizations: Dictionary = {0: true}
		for clue: Dictionary in clues.values(): organizations[int(clue.get("organization", 0))] = true
		for organization: int in organizations: result["%d:study:%s" % [organization, book]] = true
	if Defs.GOALS[goal.definition].driver == "delivery": result["%d:supply:%s" % [int(goal.params.get("organization", 0)), goal.params.item]] = true
	if Defs.GOALS[goal.definition].driver == "responsibility":
		var terms: Dictionary = actor.get("responsibilities", {}).get(int(goal.params.share), {})
		if terms.get("kind") == "delivery":
			if not Stock.access_reason(actor, anchor, "put", {"item": terms.item, "purpose": "supply"}).is_empty() or (int(anchor.get("capacity", -1)) >= 0 and int(anchor.get("inventory", {}).values().reduce(func(a: int, b: int): return a + b, 0)) >= int(anchor.capacity)): return result
			for origin: int in terms.sources: result["%d:supply:%s:%d" % [int(terms.organization), terms.item, origin]] = true
	return result

func share_closed(world: RefCounted, share: Dictionary, completed: bool) -> void:
	var entry: Dictionary = records.get(int(share.actor), {})
	if entry.is_empty(): return
	for goal: Dictionary in entry.goals.values():
		if Defs.GOALS[goal.definition].driver != "responsibility" or goal.params.share != share.id or goal.state != "active": continue
		goal.state = "completed" if completed else "cancelled"
		goal.closed_ms = world.operation_time()
		if entry.intention.get("goal") == goal.id:
			var task: Dictionary = world.decisions.records.get(int(share.actor), {}).get("task", {})
			var binding: Dictionary = world.gate.current(int(share.actor))
			if entry.intention.task_id > 0 and task.get("id") == entry.intention.task_id and not binding.is_empty() and task.get("binding", {}) == binding and world._finishing.get(int(share.actor)) != binding.run_id:
				world.end_run(int(share.actor), world.operation_time(), "cancelled")
				world.clear_navigation(int(share.actor))
			entry.intention.task_id = 0
	reconcile_autonomy(world, int(share.actor))

func reconcile_autonomy(world: RefCounted, actor: int) -> void:
	var entry: Dictionary = records.get(actor, {})
	if entry.get("borrowed_autonomy", false) and world.objects.records.has(actor) and (not Beings.has(world.objects.records[actor], "work") or world.institutions.Matters.shares_for(world.institutions, actor).is_empty()):
		world.objects.records[actor].autonomous = false
		entry.borrowed_autonomy = false
		var binding: Dictionary = world.gate.current(actor)
		var decision: Dictionary = world.decisions.records.get(actor, {})
		if world.actor_slots.has(actor) and not decision.get("manual", false) and binding.get("domain") == "work" and decision.get("task", {}).get("binding", {}) == binding:
			var slot: int = world.actor_slots[actor]
			if world.pages[slot / 256].modes[slot % 256] == Units.Mode.EXPLORE:
				world.end_run(actor, world.operation_time(), "cancelled")
				world.clear_navigation(actor)

func task_ended(actor: int, task_id: int) -> void:
	var intention: Dictionary = records.get(actor, {}).get("intention", {})
	if not intention.is_empty() and intention.task_id == task_id: intention.task_id = 0

func _idle(world: RefCounted, id: int, at: int, searching: bool) -> void:
	var entry: Dictionary = records[id]
	entry.idle_attempts = mini(6, int(entry.idle_attempts) + 1) if searching else 0
	var delay: int = mini(10000, 1000 * (1 << int(entry.idle_attempts)))
	if searching and at >= int(entry.explore_ms) and (Beings.has(world.objects.records[id], "work") or Beings.has(world.objects.records[id], "metabolism")):
		var angle: float = deg_to_rad(float((id * 97 + int(entry.explore_count) * 137) % 360))
		var point: Vector2i = Vector2i(world.combat.position(world, id) + Vector2.from_angle(angle) * (8.0 + int(entry.explore_count) % 7))
		entry.explore_count += 1
		entry.explore_ms = at + mini(60000, 5000 * (1 << int(entry.idle_attempts)))
		_walk_to_site(world, id, world.terrain.nearest_open(Terrain.index(point.clamp(Vector2i.ONE, Vector2i.ONE * (Terrain.SIZE - 2)))), at)
	elif searching: world.decisions.wake(world, id, at, "life_result", delay)
	# Satisfied people need no aimless one-second life polling. The shared need
	# thresholds, new knowledge, conditions and new goals already wake P5.

func _walk_to_site(world: RefCounted, id: int, tile: int, at: int, operation: String = "", target: int = 0) -> void:
	var slot: int = world.actor_slots[id]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	var point: Vector2 = world.terrain.project_point(Terrain.center(tile), page.radii[row], page.flight[row] > 0)
	if point.x < 0: _rejected(world, id, operation, target, "no_operation_place", at)
	elif world.adopt_motion(id, at):
		page.move_to(row, point, Units.Mode.EXPLORE)
		world.decisions.track_host(world, id, operation, target, true)
	else: after_action(world, id, at)

func _rejected(world: RefCounted, id: int, operation: String, target: int, reason: String, at: int) -> void:
	if target > 0:
		if Operations.OPERATIONS.has(operation): world.knowledge.outcome(world, id, operation, target, "refused", reason, at)
		_appraise(world, id, operation, target, "refused", reason, at)
	world.decisions.result(world, id, operation, target, reason, at)
	after_action(world, id, at)

func _appraise(world: RefCounted, actor: int, operation: String, target: int, status: String, reason: String, at: int) -> void:
	if not records.has(actor) or operation.is_empty() or target <= 0: return
	var accounts: Dictionary = records[actor].appraisals
	var key: String = "%s:%d" % [operation, target]
	if status == "completed": accounts.erase(key); return
	if reason in ["preempted", "interrupted", "partner_left", "cancelled", "replaced", "action_committed", "actor_dead", "actor_removed"]: return
	var previous: Dictionary = accounts.get(key, {})
	var failures: int = mini(6, int(previous.get("failures", 0)) + 1)
	accounts[key] = {"operation": operation, "target": target, "reason": reason, "failures": failures, "at_ms": at,
		"until_ms": at + mini(60000, 1500 * (1 << (failures - 1))), "revision": int(world.knowledge.evidence(actor, target).get("revision", 0))}
	if accounts.size() > APPRAISAL_LIMIT:
		var oldest: String = str(accounts.keys()[0])
		for item: String in accounts:
			if int(accounts[item].at_ms) < int(accounts[oldest].at_ms): oldest = item
		accounts.erase(oldest)

func outcome(world: RefCounted, actor: int, binding: Dictionary, result: Dictionary, at: int, reason: String) -> void:
	if not records.has(actor): return
	var task: Dictionary = world.decisions.records.get(actor, {}).get("task", {})
	if result.is_empty():
		if task.get("binding", {}) == binding and task.has("operation") and reason != "completed": _appraise(world, actor, task.operation, int(task.target), "interrupted", reason, at)
		return
	_appraise(world, actor, result.operation, int(result.target), result.status, result.reason, at)
	var entry: Dictionary = records[actor]
	if result.status == "completed": entry.idle_attempts = 0
	var intention: Dictionary = entry.intention
	if intention.is_empty() or int(intention.task_id) <= 0 or task.get("id") != intention.task_id or task.get("binding", {}) != binding: return
	var goal: Dictionary = entry.goals.get(intention.goal, {})
	if goal.is_empty() or goal.state != "active" or result.status != "completed": return
	if Defs.GOALS[goal.definition].driver == "delivery" and result.operation == "put" and result.facts.get("item") == goal.params.item and int(result.facts.get("source", 0)) == actor:
		var destination: int = int(result.facts.get("destination", 0))
		if int(goal.params.get("target", 0)) > 0 and destination != int(goal.params.target): return
		if int(world.objects.records.get(destination, {}).get("organization", 0)) != int(goal.params.get("organization", 0)): return
		var fulfilled: int = int(result.facts.get("amount", 0))
		if int(goal.params.get("organization", 0)) > 0:
			fulfilled = 0
			for line: Dictionary in result.facts.get("deliveries", []):
				if line.organization == goal.params.organization and line.origin != destination: fulfilled += int(line.amount)
		goal.progress = mini(int(goal.params.amount), int(goal.progress) + maxi(0, fulfilled))
		if goal.progress >= goal.params.amount:
			if goal.params.get("repeat", false): goal.progress = 0
			else: goal.state = "completed"; goal.closed_ms = at
	if Defs.GOALS[goal.definition].driver == "operation" and result.operation == goal.params.operation and result.target == goal.params.target and result.reason != "process_waiting":
		goal.state = "completed"; goal.closed_ms = at

func after_action(world: RefCounted, id: int, at: int, target: int = 0) -> void:
	if not world.actor_slots.has(id) or not world.combat.alive(world, id) or not world.objects.records[id].get("autonomous", false): return
	if target > 0: world.knowledge.refresh(world, id, target, at)
	world.decisions.wake(world, id, at, "life_result", 500 + (id % 10) * 50)

func forget(actor: int) -> void:
	records.erase(actor); latest.erase(actor)

func arrived(world: RefCounted, actor: int, at: int) -> void:
	world.sight.sync(world)
	var task: Dictionary = world.decisions.records.get(actor, {}).get("task", {})
	if not task.get("approach", false): return
	var target: int = int(task.get("target", 0))
	var tile: int = int(world.knowledge.view(actor, target, at).get("tile", -1))
	if target > 0 and tile >= 0 and world.knowledge.refresh(world, actor, target, at, true): return
	if tile >= 0 and not world.sight.sees(world.combat.position(world, actor), tile, world.sight.range_for(world, actor)):
		_appraise(world, actor, str(task.get("operation", "inspect")), target, "failed", "not_observed", at)
		world.decisions.result(world, actor, str(task.get("operation", "inspect")), target, "not_observed", at)
	elif tile >= 0: world.knowledge.refresh(world, actor, target, at)

func protects(world: RefCounted, actor: int, target: int) -> bool:
	var entry: Dictionary = records.get(actor, {})
	if entry.get("intention", {}).get("anchor", 0) == target and entry.get("goals", {}).get(entry.intention.get("goal", 0), {}).get("state") == "active": return true
	for goal: Dictionary in entry.get("goals", {}).values():
		if goal.state == "active" and goal.params.get("target", 0) == target: return true
	for terms: Dictionary in world.institutions.Matters.views(world.institutions, world, actor).values():
		if terms.target == target or target in terms.sources: return true
	return false

static func _params_valid(definition: String, params: Dictionary, next_id: int) -> bool:
	var permitted: Array = []
	match Defs.GOALS[definition].driver:
		"responsibility":
			permitted = ["matter", "share"]
			if params.size() != 2 or not params.get("matter") is int or params.matter < 1 or not params.get("share") is int or params.share < 1: return false
		"development":
			permitted = ["method"]
			if not params.get("method") is String or not Growth.Defs.METHODS.has(params.method): return false
		"delivery":
			permitted = ["item", "amount", "target", "organization", "repeat"]
			if not params.get("item") is String or not preload("res://scripts/sim/kernel/items.gd").valid(params.item) or not params.get("amount") is int or params.amount < 1 or params.amount > 10000: return false
		"operation":
			permitted = ["operation", "target", "expires_ms"]
			if not params.get("operation") is String or not Operations.OPERATIONS.has(params.operation) or not params.get("target") is int or params.target <= 0: return false
	for key: Variant in params:
		if key not in permitted: return false
		if key in ["target", "organization"] and (not params[key] is int or params[key] < 0 or (key == "target" and params[key] >= next_id)): return false
		if key == "expires_ms" and (not params[key] is int or params[key] < 0): return false
		if key == "repeat" and not params[key] is bool: return false
	return true

func describe(actor: int) -> Dictionary:
	var entry: Dictionary = records.get(actor, {})
	if entry.is_empty(): return {}
	var goals: Array = []
	for goal: Dictionary in entry.goals.values(): goals.append({"id": goal.id, "title": Defs.GOALS[goal.definition].title, "state": goal.state, "progress": goal.progress, "params": State.copy(goal.params)})
	return {"goals": goals, "intention": State.copy(entry.intention), "dispositions": State.copy(entry.dispositions), "evaluation": State.copy(latest.get(actor, {}))}

func valid(world: RefCounted) -> bool:
	return preload("res://scripts/sim/kernel/agency_state.gd").valid(self, world)
