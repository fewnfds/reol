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
const Duties = preload("res://scripts/sim/kernel/institution_duties.gd")
const Defs = preload("res://scripts/sim/kernel/agency_defs.gd")
const Selection = preload("res://scripts/sim/kernel/agency_selection.gd")
const Planner = preload("res://scripts/sim/kernel/agency_planner.gd")
const Social = preload("res://scripts/sim/kernel/agency_social.gd")
const STATE_FIELDS: Array = ["records", "next_goal", "catalog_signature"]
const GOAL_LIMIT: int = 16
const APPRAISAL_LIMIT: int = 24
const BUDGET_MS: int = 1000
var records: Dictionary = {}
var next_goal: int = 1
var catalog_signature: String = Defs.SIGNATURE
var decisions: int = 0
var decision_usec: int = 0
var prepare_usec: int = 0
var discarded_plans: int = 0
var _reserved_work: Dictionary = {} # Runtime query reservations, never saved facts.
var latest: Dictionary = {} # Diagnostic only, not restored as decision truth.

func record(world: RefCounted, actor: int) -> Dictionary:
	if not records.has(actor):
		var traits: Dictionary = {}
		for index: int in Defs.DISPOSITIONS.size():
			traits[Defs.DISPOSITIONS[index]] = 0.5 + float((actor * 37 + index * 71) % 101) / 100.0
		records[actor] = {"goals": {}, "intention": {}, "dispositions": traits, "appraisals": {}, "social_appraisals": {},
			"budget": {"window_ms": world.operation_time(), "work": 0, "cursor": 0, "goal_cursor": 0}, "explore_ms": 0, "explore_count": 0, "idle_attempts": 0, "borrowed_autonomy": false}
	return records[actor]

func add_goal(world: RefCounted, actor: int, definition: String, params: Dictionary = {}, source: int = 0) -> int:
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor) or not Defs.GOALS.has(definition) or not _params_valid(definition, params, world.objects.next_id): return 0
	if int(params.get("organization", 0)) > 0 and not world.institutions.organizations.has(params.organization): return 0
	if source < 0 or source >= world.objects.next_id: return 0
	if Defs.GOALS[definition].driver == "instruction" and params.target == actor: return 0
	if Defs.GOALS[definition].driver == "responsibility":
		var share: Dictionary = world.institutions.shares.get(int(params.share), {})
		if share.get("actor") != actor or share.get("matter") != params.matter or share.get("state") != "accepted": return 0
	if Defs.GOALS[definition].driver == "duty" and not world.institutions.Duties.views(world.institutions, actor).has(int(params.appointment)): return 0
	var entry: Dictionary = record(world, actor)
	for goal: Dictionary in entry.goals.values():
		if Defs.GOALS[definition].driver == "responsibility" and Defs.GOALS[goal.definition].driver == "responsibility" and goal.params.share == params.share and goal.state == "active": return int(goal.id)
		if Defs.GOALS[definition].driver == "duty" and Defs.GOALS[goal.definition].driver == "duty" and goal.params.appointment == params.appointment and goal.state == "active": return int(goal.id)
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

func seed_examples(world: RefCounted) -> void:
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
	add_goal(world, actor, "vitality")
	add_goal(world, actor, "qi_reserve")
	if Beings.has(person, "environment"): add_goal(world, actor, "recovery")
	if Beings.has(person, "work"): add_goal(world, actor, "custody")
	if Beings.has(person, "contact"):
		add_goal(world, actor, "reporting")
		add_goal(world, actor, "responses")
		for organization: int in world.institutions.permissions(actor): add_goal(world, actor, "organization_service", {"organization": organization})
	world.institutions.Departments.ensure(world.institutions)
	if world.institutions._work_departments.has(actor) or world.institutions._management_departments.has(actor): add_goal(world, actor, "department_work")
	reconcile_duties(world, actor)

func reconcile_duties(world: RefCounted, actor: int) -> bool:
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor): return true
	var duties: Dictionary = world.institutions.Duties.views(world.institutions, actor)
	var entry: Dictionary = record(world, actor)
	for goal: Dictionary in entry.goals.values():
		if goal.state == "active" and Defs.GOALS[goal.definition].driver == "duty" and not duties.has(int(goal.params.appointment)): _close_goal(world, actor, goal, false)
	for id: int in duties:
		if add_goal(world, actor, "role_duty", {"appointment": id}) == 0: return false
	return true

func think(world: RefCounted, id: int, at: int) -> void:
	if world.objects.records.get(id, {}).get("autonomous", false) and not world.decisions.records.get(id, {}).get("manual", false): world.decisions.wake(world, id, at, "life_ready")

func choose(world: RefCounted, id: int, at: int) -> void:
	# Explicit synchronous caller; production uses the same job through Deferred.
	var identity: String = world.deferred.key("life", id)
	if world.deferred.ready.has(identity) or world.deferred.jobs.has(identity): return
	var job: RefCounted = prepare_plan(world, id, at)
	if job == null: return
	job.run()
	complete_plan(world, id, job, at)

func schedule_reviews(world: RefCounted, actor: int, at: int) -> void:
	# Review deadlines depend on current private evidence and authorization.
	if not world.combat.alive(world, actor) or not world.objects.records[actor].get("autonomous", false) or world.decisions.records.get(actor, {}).get("manual", false): return
	var person: Dictionary = world.objects.records[actor]
	var channels: Dictionary = world.knowledge.records.get(actor, {}).get("channels", {})
	if not Growth.has_qi_method(person) and world.society._requests_by_actor.get(actor, []).is_empty() and world.institutions.Duties.views(world.institutions, actor).is_empty() and channels.is_empty(): return
	var view: Dictionary = world.institutions.access_view(world, actor)
	var inputs: Dictionary = world.knowledge.review_inputs(actor, at, _duty_targets(view.duties))
	view["id"] = actor
	view["methods"] = person.get("methods", {})
	view["qi"] = int(person.get("qi", 0))
	view["known_channels"] = channels
	view["requests"] = world.society.request_views(world, actor, world.operation_time())
	view["request_retries"] = _request_retries(record(world, actor))
	view["observations"] = inputs.observations
	world.decisions.retry_allowed(world, actor, "", 0, world.operation_time())
	var clues: Dictionary = inputs.clues
	var due: int = Planner.Contacts.next_due(view, at)
	for request: Dictionary in view.requests:
		var review: int = Planner.Contacts.due(request, actor, view.responsibilities)
		if review < 0 or review > at or int(request.get("peer_tile", -1)) < 0: continue
		var peer: int = request.issuer if request.recipient == actor else request.recipient
		var task: Dictionary = world.decisions.records.get(actor, {}).get("task", {})
		if task.get("operation") == "respond_request" and task.get("target") == peer and not task.get("binding", {}).is_empty() and task.binding == world.gate.current(actor): continue
		var retry: int = maxi(at + 1000, maxi(int(records[actor].appraisals.get("respond_request:%d" % (request.issuer if request.recipient == actor else request.recipient), {}).get("until_ms", 0)), int(view.request_retries.get(int(request.id), 0))))
		if due < 0 or retry < due: due = retry
	if due > at: world.decisions.wake(world, actor, at, "request_review", due - at)
	due = Planner.Institutions.next_due(view, clues, at)
	if due > at: world.decisions.wake(world, actor, at, "institution_review", due - at)
	due = Planner.source_review_due(view, clues, at)
	if due > at: world.decisions.wake(world, actor, at, "source_review", due - at)

func resource_changed(world: RefCounted, actor: int, metric: String, before: int, after: int, at: int) -> void:
	if before == after or metric not in ["qi", "hp", "energy"] or not world.actor_slots.has(actor) or not world.combat.alive(world, actor) or not world.objects.records[actor].get("autonomous", false) or world.decisions.records.get(actor, {}).get("manual", false): return
	# Self-commits already have a single result/after_action wake. Never plan
	# synchronously inside payment or treatment; external changes wake later.
	if world._finishing.has(actor) or world.instant_actor == actor: return
	if after > before and not world.gate.current(actor).is_empty(): return
	world.decisions.wake(world, actor, at, "needs_changed", 50)

func _request_retries(entry: Dictionary) -> Dictionary:
	var retries: Dictionary = {}
	for account: Dictionary in entry.appraisals.values():
		if account.has("request"): retries[int(account.request)] = int(account.until_ms)
	return retries

func _utility_view(world: RefCounted, actor: int) -> Dictionary:
	var view: Dictionary = world.operation_actor(actor)
	view["has_department_work"] = world.institutions.Workflow.has_work(world.institutions, world, actor)
	view["recovering"] = Growth.needs_rest(world.objects.records[actor]) and view.temperature >= 5.0 and view.temperature <= 40.0
	view["requests"] = world.society.request_views(world, actor, world.operation_time())
	world.decisions.retry_allowed(world, actor, "", 0, world.operation_time())
	return view

func _duty_targets(duties: Dictionary) -> Dictionary:
	var targets: Dictionary = {}
	for duty: Dictionary in duties.values():
		for target: int in Duties.targets(duty): targets[target] = true
	return targets

func _self_view(world: RefCounted, actor: int) -> Dictionary:
	var view: Dictionary = _utility_view(world, actor)
	view["work_offers"] = []
	view["work_shipment"] = State.copy(world.institutions.Logistics.current(world.institutions, actor))
	var slot: int = world.actor_slots[actor]
	view["speed"] = world.pages[slot / 256].move_speed[slot % 256]
	view["known_channels"] = State.copy(world.knowledge.records.get(actor, {}).get("channels", {}))
	view["contacts"] = world.society.Contacts.views(world.society, actor)
	var entry: Dictionary = record(world, actor)
	view["social_appraisals"] = State.copy(entry.social_appraisals)
	view["request_retries"] = _request_retries(entry)
	var at: int = world.operation_time()
	# Only duty, noticeboard, and qi-source reviews use observation timestamps.
	view["observations"] = world.knowledge.review_inputs(actor, at, _duty_targets(view.duties), false).observations
	view["operation_failures"] = {}
	for failure: Dictionary in world.decisions.records.get(actor, {}).get("feedback", []):
		if int(failure.until_ms) > at: view.operation_failures["%s:%d" % [failure.operation, failure.target]] = failure.reason
	return view

func _utility(goal: Dictionary, entry: Dictionary, actor: Dictionary, at: int) -> Dictionary:
	return Selection.utility(goal, entry, actor, at)

func evaluate_request(world: RefCounted, actor: int, request: Dictionary, at: int) -> Dictionary:
	# The caller supplies a delivered personal view, never objective remote state.
	_ensure_goals(world, actor)
	var entry: Dictionary = record(world, actor)
	if at - int(entry.budget.window_ms) >= BUDGET_MS:
		entry.budget.window_ms = at; entry.budget.work = 0
	var view: Dictionary = _self_view(world, actor)
	var context: Dictionary = {"need": 0.0, "duty": 0.0, "personal": 0.0, "emergency": false, "blocked": {},
		"has_goal_room": entry.goals.size() < GOAL_LIMIT or entry.goals.values().any(func(goal: Dictionary): return goal.state != "active"),
		"dispositions": entry.dispositions, "autonomous": world.objects.records[actor].get("autonomous", false)}
	for goal: Dictionary in entry.goals.values():
		if goal.state != "active": continue
		var score: Dictionary = _utility(goal, entry, view, at)
		var driver: String = Defs.GOALS[goal.definition].driver
		var category: String = "need" if Defs.is_need(Defs.GOALS[goal.definition]) else ("duty" if driver in ["responsibility", "duty", "custody", "reporting"] else "personal")
		if driver == "responses": continue # Responding to this same request is not another burden.
		context[category] = maxf(float(context[category]), float(score.value))
		context.emergency = context.emergency or bool(score.emergency)
	var slot: int = world.actor_slots[actor]
	var temperature: float = world.pages[slot / 256].body_heat[slot % 256]
	context.emergency = context.emergency or float(view.hp) / maxi(1, int(view.max_hp)) <= 0.3 or (view.body_capabilities.environment and (temperature < 5.0 or temperature > 40.0))
	for key: String in view.operation_failures:
		if view.operation_failures[key] in ["path_failed", "out_of_reach", "no_operation_place"]: context.blocked[key] = true
	for key: String in entry.appraisals:
		var failure: Dictionary = entry.appraisals[key]
		if failure.until_ms > at and failure.reason in ["path_failed", "out_of_reach", "no_operation_place"] and int(world.knowledge.evidence(actor, int(failure.target)).get("revision", 0)) == failure.revision: context.blocked[key] = true
	var own_target: Dictionary = world.operation_target(actor)
	own_target.inventory = view.inventory.duplicate()
	var social_budget: Dictionary = entry.budget.duplicate()
	if _reserved_work.get(actor, {}).get("window_ms", -1) == int(entry.budget.window_ms): social_budget.work += int(_reserved_work[actor].amount)
	var prior_work: int = int(social_budget.work)
	var result: Dictionary = Social.judge(view, own_target, world.knowledge.known(actor, at), request,
		entry.social_appraisals.get(int(request.issuer), {}), context, world.combat.position(world, actor), social_budget, at)
	entry.budget.work = mini(Planner.WORK_LIMIT, int(entry.budget.work) + int(social_budget.work) - prior_work)
	entry.budget.cursor = (int(entry.budget.cursor) + 17) % 128
	latest[actor] = {"at_ms": at, "request": int(request.id), "request_evaluation": State.copy(result), "work": int(entry.budget.work)}
	return result

func social_outcome(world: RefCounted, result: Dictionary) -> void:
	if result.is_empty() or result.status != "completed": return
	_complete_operation_goals(int(result.actor), result, int(result.at_ms))
	var handler: String = Operations.OPERATIONS[result.operation].handler
	if handler in ["learn", "teach"] and int(result.facts.get("points_gained", 0)) > 0:
		_note_social(world, int(result.facts.learner), int(result.facts.teacher), result, true)
		_note_social(world, int(result.facts.teacher), int(result.facts.learner), result)
	elif handler in ["talk", "trade"] and result.target in result.participants:
		_note_social(world, int(result.actor), int(result.target), result)
		_note_social(world, int(result.target), int(result.actor), result)
	if handler in ["learn", "teach"] and result.facts.get("understood", false):
		var teacher: int = result.facts.teacher
		for goal: Dictionary in records.get(teacher, {}).get("goals", {}).values():
			if goal.state == "active" and Defs.GOALS[goal.definition].driver == "instruction" and goal.params.target == result.facts.learner and goal.params.method == result.facts.method:
				_close_goal(world, teacher, goal, true)
	# Only a physically witnessed, actually credited result is personal support.
	# A distant Share callback, a mere acceptance or a later finished building
	# does not identify a benefactor to an observer.
	for witness: Dictionary in world.society.support_witnesses(world, result):
		_note_social(world, int(witness.actor), int(witness.peer), result, true)

func _note_social(world: RefCounted, actor: int, peer: int, result: Dictionary, support: bool = false) -> void:
	if actor == peer or not world.actor_slots.has(actor) or not world.combat.alive(world, actor): return
	Social.experienced(record(world, actor).social_appraisals, peer, result, support)

func teaching_consent(world: RefCounted, actor: int, peer: int, method: String, teaching: bool, at: int, explicit: bool = false) -> String:
	# Only this person's private motives are read. No planner or remote scan is
	# run on behalf of the caller; consent is evaluated once, on actual arrival.
	_ensure_goals(world, actor)
	var entry: Dictionary = record(world, actor)
	var view: Dictionary = _self_view(world, actor)
	var need: float = 0.0
	var competing: float = 0.0
	var willing: float = (0.24 + 0.12 * float(entry.dispositions.sociability)) if teaching else 0.0
	var clues: Dictionary = world.knowledge.known(actor, at)
	for goal: Dictionary in entry.goals.values():
		if goal.state != "active": continue
		var spec: Dictionary = Defs.GOALS[goal.definition]
		var score: Dictionary = _utility(goal, entry, view, at)
		if spec.driver == "duty" and not Planner.Institutions.review_due(view, view.duties.get(int(goal.params.appointment), {}), at, clues): continue
		if Defs.is_need(spec):
			if score.emergency: return "refused_need"
			need = maxf(need, float(score.value))
		elif (not teaching and learning_method(goal, view) == method and not Growth.mastered(view, method)) or (teaching and spec.driver == "instruction" and goal.params.method == method and goal.params.target == peer):
			willing = maxf(willing, float(score.value))
		elif teaching and spec.driver == "responsibility":
			var terms: Dictionary = view.responsibilities.get(int(goal.params.share), {})
			var op: Dictionary = Operations.OPERATIONS.get(terms.get("operation", ""), {})
			if terms.get("target") == peer and op.get("handler") == "teach" and op.learning_method == method: willing = maxf(willing, float(score.value))
			else: competing = maxf(competing, float(score.value))
		elif spec.driver not in ["responses", "reporting", "service"]: competing = maxf(competing, float(score.value))
	if float(view.hp) / maxi(1, int(view.max_hp)) <= 0.3 or (view.body_capabilities.environment and (float(view.temperature) < 5.0 or float(view.temperature) > 40.0)): return "refused_need"
	if teaching and not Growth.mastered(view, method): return "teacher_does_not_know"
	if not teaching and int(view.methods.get(method, {}).get("understanding", 0)) >= int(Growth.Defs.METHODS[method].introduction_points): return "learner_already_understood"
	if explicit: return "" # Complementary commands already express a choice, not immunity to urgent needs.
	if need > willing + 0.05: return "refused_need"
	if willing <= 0.0 or competing > willing + 0.12: return "not_interested"
	return ""

static func learning_method(goal: Dictionary, actor: Dictionary) -> String:
	return Selection.learning_method(goal, actor)

func _blocked(world: RefCounted, id: int, entry: Dictionary, at: int) -> Dictionary:
	var blocked: Dictionary = {}
	world.decisions.retry_allowed(world, id, "", 0, at)
	for failure: Dictionary in world.decisions.records[id].feedback: blocked["%s:%d" % [failure.operation, failure.target]] = true
	for experience: Dictionary in world.knowledge.records.get(id, {}).get("experiences", []):
		if experience.reason == "teacher_does_not_know" and not world.knowledge.can_attempt(id, experience.operation, experience.target, at): blocked["%s:%d" % [experience.operation, experience.target]] = true
	for key: String in entry.appraisals:
		var account: Dictionary = entry.appraisals[key]
		if account.has("request"): continue # Waiting for this reply is not a failure to contact the person.
		if account.until_ms > at and ((Operations.contact_operation(str(account.operation)) and account.reason not in ["out_of_reach", "path_failed", "no_operation_place"]) or int(world.knowledge.evidence(id, account.target).get("revision", 0)) == account.revision): blocked[key] = true
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
			if clue.get("kind") == "actor" and int(clue.get("hp", 1)) <= 0: expired = true
			if not clue.is_empty() and clue.kind != "actor" and clue.tile < 0 and int(world.knowledge.records.get(actor, {}).get("subjects", {}).get(fixed, {}).get("absent_ms", -1)) >= 0: expired = true
		if Defs.GOALS[goal.definition].driver == "operation" and goal.params.operation == "construct":
			var clue: Dictionary = world.knowledge.view(actor, int(goal.params.target), at)
			completed = not clue.is_empty() and clue.kind != "blueprint" and clue.tile >= 0
			expired = expired or (not clue.is_empty() and clue.tile < 0)
		if completed or expired:
			goal.state = "completed" if completed else "cancelled"
			goal.closed_ms = at
			if entry.intention.get("goal") == goal.id: entry.intention.task_id = 0

func can_plan(world: RefCounted, id: int, at: int, check_gate: bool = true) -> bool:
	return world.actor_slots.has(id) and world.combat.alive(world, id) and world.objects.records[id].get("autonomous", false) and not world.decisions.records.get(id, {}).get("manual", false) and not world.decisions.in_combat(id) and not world.combat.engagements.has(id) and (not check_gate or world.gate.check(world, id, at).is_empty())

func cancel_plan(actor: int) -> void:
	# Aborting forfeits this allocation in its original window. Otherwise repeated
	# cancel/restart could issue unlimited queries while old workers still finish.
	var hold: Dictionary = _reserved_work.get(actor, {})
	var entry: Dictionary = records.get(actor, {})
	if not hold.is_empty() and not entry.is_empty() and int(entry.budget.window_ms) == int(hold.window_ms):
		entry.budget.work = mini(Planner.WORK_LIMIT, int(entry.budget.work) + int(hold.amount))
	_reserved_work.erase(actor)

func prepare_plan(world: RefCounted, id: int, at: int) -> RefCounted:
	if _reserved_work.has(id): return null # One detached proposal per person.
	if not can_plan(world, id, at): return null
	if not world.gate.current(id).is_empty() and not world.decisions._life_preemptible(world, id): return null
	var began: int = Time.get_ticks_usec()
	_ensure_goals(world, id)
	var entry: Dictionary = record(world, id)
	_refresh_goals(world, id, entry, at)
	if not can_plan(world, id, at): return null
	if at - int(entry.budget.window_ms) >= BUDGET_MS:
		entry.budget.window_ms = at; entry.budget.work = 0
	var actor: Dictionary = State.copy(_self_view(world, id))
	actor.work_offers = world.institutions.Workflow.personal(world.institutions, world, id)
	var limit: int = Planner.WORK_LIMIT - (17 if Planner.Contacts.judgment_due(actor, at) else 0)
	if int(entry.budget.work) >= limit:
		world.decisions.wake(world, id, at, "planning_budget", maxi(1, int(entry.budget.window_ms) + BUDGET_MS - at))
		return null
	var clues: Dictionary = world.knowledge.planning_clues(id, at)
	var self_target: Dictionary = State.copy(world.operation_target(id))
	self_target.inventory = actor.inventory.duplicate()
	var retry: int = at + 10001
	for failure: Dictionary in world.decisions.records[id].feedback:
		if failure.until_ms > at: retry = mini(retry, int(failure.until_ms))
	for account: Dictionary in entry.appraisals.values():
		if account.until_ms > at: retry = mini(retry, int(account.until_ms))
	var job := Selection.new()
	job.input = {"actor": actor, "clues": clues, "self_target": self_target, "blocked": _blocked(world, id, entry, at),
		"entry": {"goals": State.copy(entry.goals), "dispositions": entry.dispositions.duplicate(), "intention": State.copy(entry.intention), "budget": entry.budget.duplicate()},
		"position": world.combat.position(world, id), "at_ms": at, "binding": world.gate.current(id), "limit": limit, "retry_at": retry,
		"reserved": limit - int(entry.budget.work), "initial_work": int(entry.budget.work)}
	# Reserve queries outside saved facts. Intervening social judgments see the
	# hold; loading discards it and reconstructs the durable pending request.
	_reserved_work[id] = {"window_ms": int(entry.budget.window_ms), "amount": limit - int(entry.budget.work)}
	decisions += 1
	prepare_usec += Time.get_ticks_usec() - began
	return job

func complete_plan(world: RefCounted, id: int, job: RefCounted, at: int) -> void:
	var began: int = Time.get_ticks_usec()
	var entry: Dictionary = records.get(id, {})
	if entry.is_empty(): return
	var packet: Dictionary = job.input
	var result: Dictionary = job.result
	_reserved_work.erase(id)
	if int(entry.budget.window_ms) == int(packet.entry.budget.window_ms):
		entry.budget.work = mini(Planner.WORK_LIMIT, int(entry.budget.work) + int(result.used))
	if not can_plan(world, id, at): discarded_plans += 1; return
	var current: Dictionary = world.gate.current(id)
	if current != packet.binding:
		discarded_plans += 1
		think(world, id, at)
		schedule_reviews(world, id, at)
		return
	if not current.is_empty() and not world.decisions._life_preemptible(world, id): discarded_plans += 1; return
	_refresh_goals(world, id, entry, at)
	entry.budget.cursor = (int(entry.budget.cursor) + 17) % 128
	entry.budget.goal_cursor = (int(entry.budget.goal_cursor) + int(result.goal_cursor_delta)) % GOAL_LIMIT
	var best: Dictionary = result.best
	latest[id] = {"at_ms": at, "sampled_ms": packet.at_ms, "choices": result.choices, "chosen": best.duplicate(true), "work": entry.budget.work}
	if best.is_empty():
		if result.hit_limit:
			world.decisions.wake(world, id, at, "planning_budget", maxi(1, int(entry.budget.window_ms) + BUDGET_MS - at))
		elif current.is_empty():
			if int(packet.retry_at) <= int(packet.at_ms) + 10000:
				world.decisions.wake(world, id, at, "retry_due", maxi(50, int(packet.retry_at) - at))
			else: _idle(world, id, at, bool(result.searching))
	else:
		var goal: Dictionary = entry.goals.get(int(best.goal), {})
		if goal.is_empty() or goal.state != "active" or goal.params != packet.entry.goals[best.goal].params:
			discarded_plans += 1
			think(world, id, at)
		else:
			var view: Dictionary = _utility_view(world, id)
			var score: Dictionary = _utility(goal, entry, view, at)
			var previous: Dictionary = entry.goals.get(int(entry.intention.get("goal", 0)), {})
			var previous_score: float = float(_utility(previous, entry, view, at).value) if not previous.is_empty() and previous.state == "active" and int(entry.intention.get("task_id", 0)) > 0 else 0.0
			if score.value <= 0 or (not current.is_empty() and previous_score > 0 and (score.value <= previous_score + 0.12 or (not score.emergency and score.value < 0.25))):
				discarded_plans += 1
				if current.is_empty(): think(world, id, at)
			else: _adopt_choice(world, id, best, at)
	schedule_reviews(world, id, at)
	decision_usec += Time.get_ticks_usec() - began

func _adopt_choice(world: RefCounted, id: int, best: Dictionary, at: int) -> void:
	var entry: Dictionary = records[id]
	var before: Dictionary = entry.intention
	var binding: Dictionary = world.gate.current(id)
	var step: Dictionary = best.step
	if not binding.is_empty() and step.kind == "wait": return
	entry.intention = {"goal": best.goal, "approach": best.approach, "anchor": best.anchor, "operation": best.operation, "selected_ms": at, "task_id": 0}
	if step.kind == "wait":
		world.decisions.wake(world, id, at, "method_due", maxi(100, mini(10000, int(step.until_ms) - at)))
		return
	var target: int = int(step.input.target)
	var clue: Dictionary = world.knowledge.view(id, target, at)
	var accepted: bool = false
	world.decisions._submitting = id
	if step.has("work_offer"):
		var reason: String = world.institutions.Workflow.adopt(world.institutions, world, id, step.work_offer)
		accepted = reason in ["accepted", "completed"]
		if reason == "completed": after_action(world, id, at, target)
		elif not accepted: _rejected(world, id, str(step.input.kind), target, reason, at)
	elif step.kind == "inspect" or (target != id and not world.sight.sees(world.combat.position(world, id), int(clue.get("tile", -1)), world.sight.range_for(world, id))):
		var tile: int = int(clue.get("tile", -1))
		if tile >= 0:
			_walk_to_site(world, id, world.terrain.nearest_open(tile), at, str(step.input.get("kind", "inspect")), target)
			accepted = world.gate.current(id) != binding and not world.gate.current(id).is_empty()
		elif binding.is_empty(): _idle(world, id, at, true)
	else:
		if target != id and not world.knowledge.refresh(world, id, target, at):
			after_action(world, id, at)
		else:
			var input: Dictionary = step.input.duplicate(true)
			input["autonomous"] = true
			# Hosts validate current resources/authority/station BEFORE replacing the
			# current host. A rejected stale proposal must not cancel useful work.
			var reason: String = world.execute_operation(id, input)
			accepted = reason in ["accepted", "completed"]
			if not accepted: _rejected(world, id, input.kind, target, reason, at)
			elif reason == "completed":
				if not binding.is_empty() and world.gate.matches(id, binding):
					world.end_run(id, at, "preempted", {}, false)
					world.clear_navigation(id)
				var goal: Dictionary = entry.goals[best.goal]
				if Defs.GOALS[goal.definition].driver == "operation" and goal.params.operation == input.kind and goal.params.target == target: goal.state = "completed"; goal.closed_ms = at
				after_action(world, id, at, target)
	world.decisions._submitting = 0
	if accepted:
		entry.goals[best.goal].method = {"approach": best.approach, "operation": best.operation, "anchor": best.anchor, "selected_ms": at}
		entry.intention.task_id = int(world.decisions.records.get(id, {}).get("task", {}).get("id", 0)) if entry.goals[best.goal].state == "active" else 0
	else: entry.intention = before

func _preference(entry: Dictionary, actor: Dictionary, clues: Dictionary, at: int) -> Dictionary:
	return Selection.preference(entry, actor, clues, at)

func _retained(goal: Dictionary, choice: Dictionary, clues: Dictionary, actor: Dictionary) -> Dictionary:
	return Selection.retained(goal, choice, clues, actor)

func share_closed(world: RefCounted, share: Dictionary, completed: bool) -> void:
	var entry: Dictionary = records.get(int(share.actor), {})
	if entry.is_empty(): return
	for goal: Dictionary in entry.goals.values():
		if Defs.GOALS[goal.definition].driver != "responsibility" or goal.params.share != share.id or goal.state != "active": continue
		_close_goal(world, int(share.actor), goal, completed)
	reconcile_autonomy(world, int(share.actor))

func _close_goal(world: RefCounted, actor: int, goal: Dictionary, completed: bool) -> void:
	var entry: Dictionary = records[actor]
	goal.state = "completed" if completed else "cancelled"
	goal.closed_ms = world.operation_time()
	if entry.intention.get("goal") != goal.id: return
	var task: Dictionary = world.decisions.records.get(actor, {}).get("task", {})
	var binding: Dictionary = world.gate.current(actor)
	if entry.intention.task_id > 0 and task.get("id") == entry.intention.task_id and not binding.is_empty() and task.get("binding", {}) == binding and world._finishing.get(actor) != binding.run_id:
		world.end_run(actor, world.operation_time(), "cancelled")
		world.clear_navigation(actor)
	entry.intention.task_id = 0

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
	if searching and int(world.knowledge.record(id).due_ms) <= at:
		# An empty proposal is not evidence that this location has nothing useful.
		# Finish the already due look before committing to blind exploration.
		world.decisions.wake(world, id, at, "exploration_observe")
		world.knowledge.admit(world, id, int(world.knowledge.records[id].due_ms), 0)
		return
	entry.idle_attempts = mini(6, int(entry.idle_attempts) + 1) if searching else 0
	if preload("res://scripts/sim/kernel/service_positions.gd").step_aside(world, id, at, not searching): return
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
	elif target == 0 and (preload("res://scripts/sim/kernel/service_positions.gd").is_service_cell(world, point) or not preload("res://scripts/sim/kernel/service_positions.gd").occupants(world, point, page.radii[row], id).is_empty()):
		world.decisions.wake(world, id, at, "life_result", 1000)
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

func _appraise(world: RefCounted, actor: int, operation: String, target: int, status: String, reason: String, at: int, request: int = 0) -> void:
	if not records.has(actor) or operation.is_empty() or target <= 0: return
	var accounts: Dictionary = records[actor].appraisals
	var key: String = "%s:%d" % [operation, target]
	if operation == "respond_request" and request > 0:
		var scoped: String = key + ":%d" % request
		if status == "completed" and reason != "awaiting_response": accounts.erase(scoped)
		if reason == "awaiting_response": key = scoped
	if status == "completed" and reason != "awaiting_response": accounts.erase(key); return
	if reason in ["planning_budget", "response_not_due", "shipment_changed", "request_changed"]: return
	if reason in ["preempted", "interrupted", "partner_left", "cancelled", "replaced", "joined_activity", "action_committed", "actor_dead", "actor_removed"]: return
	var previous: Dictionary = accounts.get(key, {})
	var failures: int = mini(6, int(previous.get("failures", 0)) + 1)
	accounts[key] = {"operation": operation, "target": target, "reason": reason, "failures": failures, "at_ms": at,
		"until_ms": at + mini(60000, 1500 * (1 << (failures - 1))), "revision": int(world.knowledge.evidence(actor, target).get("revision", 0))}
	if reason == "awaiting_response" and operation == "respond_request" and request > 0: accounts[key]["request"] = request
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
	_appraise(world, actor, result.operation, int(result.target), result.status, result.reason, at, int(result.facts.get("request", 0)))
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

func _complete_operation_goals(actor: int, result: Dictionary, at: int) -> void:
	# Actual completion, including an instant self-operation, can satisfy an
	# explicit purpose while another need selected the identical operation.
	if result.reason == "process_waiting": return
	for goal: Dictionary in records.get(actor, {}).get("goals", {}).values():
		if goal.state == "active" and Defs.GOALS[goal.definition].driver == "operation" and goal.params.operation == result.operation and goal.params.target == result.target:
			goal.state = "completed"; goal.closed_ms = at

func after_action(world: RefCounted, id: int, at: int, target: int = 0) -> void:
	if not world.actor_slots.has(id) or not world.combat.alive(world, id) or not world.objects.records[id].get("autonomous", false) or world.decisions.records.get(id, {}).get("manual", false): return
	if target > 0: world.knowledge.refresh(world, id, target, at)
	world.decisions.wake(world, id, at, "life_result", 500 + (id % 10) * 50)

func forget(actor: int) -> void:
	_reserved_work.erase(actor)
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

func protected_targets(world: RefCounted, actor: int, subjects: Dictionary = {}) -> Dictionary:
	if subjects.is_empty(): subjects = world.knowledge.records.get(actor, {}).get("subjects", {})
	var result: Dictionary = world.institutions.Access.known_personal_places(world.institutions, actor, subjects)
	for request: Dictionary in world.society.Requests.views(world.society, actor, world.operation_time()):
		if request.state in ["pending", "deferred", "accepted"]:
			for target: int in [int(request.target)] + request.terms.sources: result[target] = true
	var entry: Dictionary = records.get(actor, {})
	if entry.get("goals", {}).get(entry.get("intention", {}).get("goal", 0), {}).get("state") == "active": result[int(entry.intention.anchor)] = true
	for goal: Dictionary in entry.get("goals", {}).values():
		if goal.state == "active" and goal.params.get("target", 0) > 0: result[int(goal.params.target)] = true
	for terms: Dictionary in world.institutions.Matters.views(world.institutions, world, actor).values():
		for target: int in [int(terms.target)] + terms.sources: result[target] = true
	for duty: Dictionary in world.institutions.Duties.views(world.institutions, actor).values():
		for target: int in world.institutions.Duties.targets(duty): result[target] = true
		for site: int in duty.get("sites", []):
			var occupant: int = int(subjects.get(site, {}).get("view", {}).get("occupant", 0))
			if occupant > 0: result[occupant] = true
	for bundle: Dictionary in world.institutions.return_bundles(world, actor):
		if bundle.purpose == "supply" and int(bundle.get("origin", 0)) > 0: result[int(bundle.origin)] = true
	return result

static func _params_valid(definition: String, params: Dictionary, next_id: int) -> bool:
	var permitted: Array = []
	match Defs.GOALS[definition].driver:
		"duty":
			permitted = ["appointment"]
			if params.size() != 1 or not params.get("appointment") is int or params.appointment < 1: return false
		"service":
			permitted = ["organization"]
			if params.size() != 1 or not params.get("organization") is int or params.organization < 1: return false
		"responsibility":
			permitted = ["matter", "share"]
			if params.size() != 2 or not params.get("matter") is int or params.matter < 1 or not params.get("share") is int or params.share < 1: return false
		"development":
			permitted = ["method"]
			if not params.get("method") is String or not Growth.Defs.METHODS.has(params.method): return false
		"instruction":
			permitted = ["method", "target"]
			if params.size() != 2 or not params.get("method") is String or not Growth.Defs.METHODS.has(params.method) or not params.get("target") is int or params.target <= 0: return false
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
