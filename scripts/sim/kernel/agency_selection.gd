extends RefCounted
## One detached personal proposal. No World, host, reservation or goods writes.
## The identical core advances by approaches locally or runs on the engine pool.
const Defs = preload("res://scripts/sim/kernel/agency_defs.gd")
const Planner = preload("res://scripts/sim/kernel/agency_planner.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
var input: Dictionary
var result: Dictionary = {}
var work_usec: int = 0
var thread_id: int = 0
var _planner: RefCounted
var _ordered: Array = []
var _goal: int = 0
var _approach: int = 0
var _examined: int = 0
var _urgent: int = 0
var _ordinary: int = 0
var _allowance: int = 0
var _limit: int = 0
var _initial_work: int = 0
var _choices: Array = []
var _best: Dictionary = {}

func run() -> void:
	while not advance(): pass

func advance() -> bool:
	if not result.is_empty(): return true
	var began: int = Time.get_ticks_usec()
	thread_id = OS.get_thread_caller_id()
	if _planner == null:
		_prepare()
	elif _goal < _ordered.size() and int(input.entry.budget.work) < _limit:
		var candidate: Dictionary = _ordered[_goal]
		var approaches: Array = Defs.GOALS[candidate.goal.definition].approaches
		var approach_id: String = approaches[_approach]
		var approach: Dictionary = Defs.APPROACHES[approach_id]
		if _approach == 0: _examined += 1
		for option: Dictionary in _planner.candidates(candidate.goal, approach, mini(_allowance, _limit - int(input.entry.budget.work))):
			if not input.binding.is_empty() and option.step.kind == "wait": continue
			var score: float = float(candidate.utility.value) * (0.55 + 0.45 * float(option.step.confidence) * float(approach.confidence)) - minf(0.12, float(option.step.estimate_ms) / 200000.0)
			if option.step.get("social", false): score += 0.04 * (float(input.entry.dispositions.sociability) - 1.0)
			var intention: Dictionary = input.entry.intention
			if intention.get("goal") == candidate.goal.id and intention.get("approach") == approach_id and intention.get("anchor") == option.anchor and intention.get("operation") == option.operation:
				score += 0.05 * float(input.entry.dispositions.persistence)
			var choice: Dictionary = {"goal": candidate.goal.id, "approach": approach_id, "anchor": option.anchor, "operation": option.operation,
				"score": score, "utility": candidate.utility.value, "emergency": candidate.utility.emergency, "step": option.step}
			if _choices.size() < 12: _choices.append(choice.duplicate(true))
			if _best.is_empty() or score > float(_best.score): _best = choice
		_approach += 1
		if _approach >= approaches.size(): _goal += 1; _approach = 0
	if _goal >= _ordered.size() or int(input.entry.budget.work) >= _limit: _finish()
	work_usec += Time.get_ticks_usec() - began
	return not result.is_empty()

func _prepare() -> void:
	var entry: Dictionary = input.entry
	_initial_work = int(entry.budget.work)
	_limit = int(input.limit)
	var current: Dictionary = entry.goals.get(int(entry.intention.get("goal", 0)), {})
	var current_score: float = float(utility(current, entry, input.actor, input.at_ms).value) if not current.is_empty() and current.state == "active" and int(entry.intention.get("task_id", 0)) > 0 else 0.0
	for goal: Dictionary in entry.goals.values():
		if goal.state != "active": continue
		var score: Dictionary = utility(goal, entry, input.actor, input.at_ms)
		if score.value <= 0.0: continue
		if not input.binding.is_empty() and current_score > 0 and (score.value <= current_score + 0.12 or (not score.emergency and score.value < 0.25)): continue
		_ordered.append({"goal": goal, "utility": score})
	_ordered.sort_custom(func(a: Dictionary, b: Dictionary): return a.utility.value > b.utility.value if not is_equal_approx(a.utility.value, b.utility.value) else a.goal.id < b.goal.id)
	_allowance = maxi(4, mini(32, Planner.WORK_LIMIT / maxi(1, _ordered.reduce(func(sum: int, value: Dictionary): return sum + Defs.GOALS[value.goal.definition].approaches.size(), 0))))
	var urgent: Array = _ordered.filter(func(value: Dictionary): return value.utility.emergency)
	var replying: bool = Planner.Contacts.judgment_due(input.actor, input.at_ms)
	var protected: Array = _ordered.filter(func(value: Dictionary): return not value.utility.emergency and replying and Defs.GOALS[value.goal.definition].driver == "responses")
	var ordinary: Array = _ordered.filter(func(value: Dictionary): return not value.utility.emergency and value not in protected)
	if not ordinary.is_empty():
		var offset: int = int(entry.budget.goal_cursor) % ordinary.size()
		ordinary = ordinary.slice(offset) + ordinary.slice(0, offset)
	_urgent = urgent.size(); _ordinary = ordinary.size()
	_ordered = urgent + protected + ordinary
	_planner = Planner.new()
	_planner.configure(input.actor, input.self_target, input.clues, input.blocked, input.position, input.at_ms, entry.budget, preference(entry, input.actor, input.clues, input.at_ms))

func _finish() -> void:
	var searching: bool = false
	if _best.is_empty() and input.binding.is_empty():
		for candidate: Dictionary in _ordered:
			var driver: String = Defs.GOALS[candidate.goal.definition].driver
			if driver == "resource" and Defs.GOALS[candidate.goal.definition].metric in ["hp", "qi"]: continue
			if driver == "development" and Growth.introduced(input.actor, candidate.goal.params.method) and int(Growth.Defs.METHODS[candidate.goal.params.method].source_qi_cost) > 0 and input.clues.values().any(func(place: Dictionary): return int(place.get("tile", -1)) >= 0 and int(place.get("source_qi_band", -1)) >= 0): continue
			if driver not in ["duty", "service", "reporting", "responses", "department"]:
				var target: int = int(Planner.project(candidate.goal, input.actor).params.get("target", 0))
				if not Planner.known_dead(input.clues.get(target, {})): searching = true
			elif driver == "service" and not input.clues.values().any(func(value: Dictionary): return value.has("post_revision") and int(value.get("organization", 0)) == int(candidate.goal.params.organization)): searching = true
			elif driver == "duty":
				var policy: Dictionary = input.actor.duties[int(candidate.goal.params.appointment)]
				if Planner.Institutions.Duties.targets(policy).any(func(target: int): return not input.clues.has(target)): searching = true
	var hit_limit: bool = int(input.entry.budget.work) >= _limit
	result = {"best": _best, "choices": _choices, "searching": searching, "hit_limit": hit_limit,
		"used": int(input.entry.budget.work) - _initial_work, "goal_cursor_delta": maxi(1, _examined - _urgent) if hit_limit and _ordinary > 0 else 0}


static func utility(goal: Dictionary, entry: Dictionary, actor: Dictionary, at: int) -> Dictionary:
	var spec: Dictionary = Defs.GOALS[goal.definition]
	var value: float = 0.0
	var emergency: bool = false
	match spec.driver:
		"resource":
			if spec.metric in ["hunger", "energy"] and not actor.body_capabilities.get("metabolism", false): return {"value": 0.0, "emergency": false}
			if spec.metric == "qi" and not Growth.has_qi_method(actor): return {"value": 0.0, "emergency": false}
			if actor.body_capabilities.get("metabolism", false) and (int(actor.hunger) < int(spec.min_satiety) or int(actor.energy) < int(spec.min_energy)): return {"value": 0.0, "emergency": false}
			var current: int = Defs.resource_value(actor, str(spec.metric))
			value = pow(clampf(float(int(spec.comfort) - current) / int(spec.comfort), 0.0, 1.0), float(spec.exponent))
			emergency = int(spec.emergency) >= 0 and current <= int(spec.emergency)
		"recovery": value = 0.65 if actor.recovering else 0.0
		"development": value = 0.0 if Growth.mastered(actor, goal.params.method) else 1.0
		"delivery", "operation", "instruction": value = 1.0
		"responsibility": value = 1.0 if actor.get("responsibilities", {}).has(int(goal.params.share)) else 0.0
		"duty": value = 1.0 if actor.get("duties", {}).has(int(goal.params.appointment)) else 0.0
		"service": value = 1.0 if actor.get("permissions", {}).has(int(goal.params.organization)) and actor.get("responsibilities", {}).is_empty() else 0.0
		"reporting": value = 1.0 if not actor.get("reports", []).is_empty() else 0.0
		"responses":
			for request: Dictionary in actor.get("requests", []):
				var time: int = Planner.Contacts.due(request, int(actor.id), actor.get("responsibilities", {}))
				if time >= 0 and time <= at: value = maxf(value, 1.0 + minf(0.5, float(at - time) / 30000.0))
		"department": value = 1.0 if actor.get("has_department_work", not actor.get("work_offers", []).is_empty()) else 0.0
		"custody": value = 1.0 if not actor.returns.is_empty() else 0.0
	value *= float(spec.weight)
	if not spec.disposition.is_empty(): value *= float(entry.dispositions[spec.disposition])
	if value > 0.0: value += minf(0.08, float(at - int(goal.created_ms)) / 3000000.0)
	if emergency: value += 2.0
	return {"value": value, "emergency": emergency}

static func learning_method(goal: Dictionary, actor: Dictionary) -> String:
	var driver: String = Defs.GOALS[goal.definition].driver
	if driver in ["development", "instruction"]: return str(goal.params.method)
	var operation: String = str(actor.get("responsibilities", {}).get(int(goal.params.share), {}).get("operation", "")) if driver == "responsibility" else str(goal.params.get("operation", ""))
	var spec: Dictionary = Operations.OPERATIONS.get(operation, {})
	return str(spec.get("required_method", "")) if not str(spec.get("required_method", "")).is_empty() else str(spec.get("learning_method", ""))

static func preference(entry: Dictionary, actor: Dictionary, clues: Dictionary, at: int) -> Dictionary:
	var result: Dictionary = entry.intention.duplicate(true)
	result["retained"] = {}
	for goal: Dictionary in entry.goals.values():
		if goal.state == "active" and utility(goal, entry, actor, at).value > 0.0:
			result.retained.merge(retained(goal, goal.method, clues, actor))
	return result

static func retained(goal: Dictionary, choice: Dictionary, clues: Dictionary, actor: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if Defs.GOALS[goal.definition].driver == "duty":
		var policy: Dictionary = actor.get("duties", {}).get(int(goal.params.appointment), {})
		if policy.get("kind") == "cultivation": return Planner.Institutions.Cultivation.retained(policy, actor, clues)
	# Self-study is useful independently of a former teacher's last-seen site.
	var method: String = learning_method(goal, actor)
	if not method.is_empty() and not Growth.introduced(actor, method):
		var book: String = Growth.Defs.METHODS[method].study_item
		var organizations: Dictionary = {0: true}
		for clue: Dictionary in clues.values(): organizations[int(clue.get("organization", 0))] = true
		for bundle: Dictionary in actor.get("bundles", []): organizations[int(bundle.organization)] = true
		for organization: int in organizations: result["%d:study:%s" % [organization, book]] = true
	var projected: Dictionary = Planner.project(goal, actor)
	var operation_id: String = str(choice.get("operation", ""))
	if operation_id.is_empty(): operation_id = str(projected.params.get("operation", ""))
	var operation: Dictionary = Operations.OPERATIONS.get(operation_id, {})
	var target: int = int(choice.get("anchor", 0))
	if target <= 0: target = int(projected.params.get("target", 0))
	var anchor: Dictionary = clues.get(target, {})
	# Keep prerequisites while the known method remains usable, not after its
	# actual site is known to be gone. Missing one ingredient alone is temporary.
	if target == 0 or (target != actor.id and int(anchor.get("tile", -1)) < 0): return result
	if not operation.is_empty():
		var place: Dictionary = anchor.duplicate()
		if not operation.recipe.is_empty(): place["processing_purpose"] = str(operation.recipe.purpose)
		if not Stock.access_reason(actor, place, str(operation.handler)).is_empty(): return result
		var organization: int = int(anchor.get("organization", 0))
		var inputs: Dictionary = operation.recipe.inputs if not operation.recipe.is_empty() else operation.required_items
		var purpose: String = Stock.input_purpose(operation)
		for item: String in inputs: result["%d:%s:%s" % [organization, purpose, item]] = true
	if Defs.GOALS[goal.definition].driver == "delivery": result["%d:supply:%s" % [int(goal.params.get("organization", 0)), goal.params.item]] = true
	if Defs.GOALS[goal.definition].driver == "responsibility":
		var terms: Dictionary = actor.get("responsibilities", {}).get(int(goal.params.share), {})
		var place: Dictionary = clues.get(int(terms.get("target", 0)), {})
		if int(place.get("tile", -1)) < 0: return result
		if terms.get("kind") == "delivery":
			if not Stock.access_reason(actor, place, "put", {"item": terms.item, "purpose": "supply"}).is_empty() or (int(place.get("capacity", -1)) >= 0 and int(place.get("inventory", {}).values().reduce(func(a: int, b: int): return a + b, 0)) >= int(place.capacity)): return result
			for origin: int in terms.sources: result["%d:supply:%s:%d" % [int(terms.organization), terms.item, origin]] = true
		elif terms.get("kind") == "produce":
			var recipe: Dictionary = Operations.OPERATIONS[terms.operation].recipe
			for item: String in recipe.inputs: result["%d:%s:%s" % [int(terms.organization), recipe.purpose, item]] = true
	return result
