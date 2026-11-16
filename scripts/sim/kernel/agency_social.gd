extends RefCounted
## Personal experience and request judgment over detached views. No World access.
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const Planner = preload("res://scripts/sim/kernel/agency_planner.gd")
const Matters = preload("res://scripts/sim/kernel/institution_matters.gd")
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const LIMIT: int = 24
const COUNT_LIMIT: int = 16
const PROBE_WORK: int = 16

static func experienced(accounts: Dictionary, peer: int, result: Dictionary, support: bool = false) -> void:
	var previous: Dictionary = accounts.get(peer, {})
	if int(previous.get("last_result", 0)) >= int(result.id): return
	accounts[peer] = {"exchanges": mini(COUNT_LIMIT, int(previous.get("exchanges", 0)) + 1),
		"support": mini(COUNT_LIMIT, int(previous.get("support", 0)) + (1 if support else 0)),
		"last_result": int(result.id), "at_ms": int(result.at_ms)}
	if accounts.size() > LIMIT:
		var victim: int = 0
		for person: int in accounts:
			var value: Dictionary = accounts[person]
			if victim == 0 or value.support < accounts[victim].support or (value.support == accounts[victim].support and value.last_result < accounts[victim].last_result): victim = person
		accounts.erase(victim)

static func judge(actor: Dictionary, own_target: Dictionary, known: Dictionary, request: Dictionary, experience: Dictionary, context: Dictionary, position: Vector2, budget: Dictionary, at: int) -> Dictionary:
	if int(budget.work) + PROBE_WORK + 1 > Planner.WORK_LIMIT: return _answer("wait", "planning_budget")
	budget.work += 1
	var terms: Dictionary = request.terms
	var required: String = "put" if terms.kind == "delivery" else str(terms.operation)
	var operation: Dictionary = Operations.OPERATIONS[required]
	for capability: String in operation.required_capabilities:
		if not actor.body_capabilities.get(capability, false): return _answer("refuse", "refused_capability")
	if not operation.required_method.is_empty() and not Growth.introduced(actor, operation.required_method): return _answer("refuse", "method_not_known")
	if not operation.required_ability.is_empty() and not actor.abilities.get(operation.required_ability, false): return _answer("refuse", "ability_not_mastered")
	if terms.organization > 0 and not actor.permissions.has(int(terms.organization)): return _answer("refuse", "not_organization_member")
	if not context.has_goal_room or actor.responsibilities.size() >= Matters.PERSON_LIMIT: return _answer("refuse", "refused_capacity")
	for responsibility: Dictionary in actor.responsibilities.values():
		if request.matter > 0 and responsibility.matter == request.matter: return _answer("refuse", "already_accepted")
	for target: int in [request.target] + terms.sources:
		if int(known.get(target, {}).get("tile", -1)) < 0: return _answer("refuse", "task_not_understood")
	if required == "construct" and known[int(request.target)].kind != "blueprint": return _answer("refuse", "task_already_done")
	# A promise may allow this narrow execution grant after acceptance. It never
	# grants organization-wide rights or writes a live permission during a probe.
	var projected: Dictionary = actor.duplicate(true)
	projected.admission_reason = ""
	var contract: Dictionary = terms.duplicate(true)
	contract.target = int(request.target)
	projected.scope_grants.append_array(Matters.terms_grants(contract, known))
	if terms.organization == 0: projected.task_access[int(request.target)] = [required]
	projected.responsibilities[-1] = {"kind": terms.kind, "operation": terms.operation, "target": request.target,
		"item": terms.item, "remaining": request.quota, "organization": terms.organization, "sources": terms.sources}
	var planner := Planner.new()
	planner.configure(projected, own_target, known, context.blocked, position, at, budget, {})
	var options: Array = planner.candidates({"definition": "matter_share", "params": {"share": -1}}, {"pattern": "responsibility"}, PROBE_WORK)
	if options.is_empty():
		if int(budget.work) >= planner.slice_limit: return _answer("wait", "planning_budget")
		return _answer("refuse", "no_known_method")
	# This is a personal estimate, not a proof of path reachability or total cost.
	var estimate: int = roundi(position.distance_to(Terrain.center(int(known[int(request.target)].tile))) / maxf(0.1, float(actor.speed)) * 1000)
	var labor: int = Growth.duration_ms(actor, operation, maxi(0, int(operation.duration_ms)))
	if terms.kind == "produce":
		var recipe: Dictionary = operation.recipe
		var batches: int = ceili(float(request.quota) / int(recipe.outputs[terms.item]))
		labor = batches * (Growth.duration_ms(actor, operation, int(recipe.work_ms)) + int(recipe.passive_ms) + int(recipe.finish_ms))
		var process: Dictionary = known[int(request.target)].get("process", {})
		if process.get("operation") == required:
			var first: int = maxi(0, int(process.get("ready_ms", at)) - at) + int(recipe.finish_ms) if process.get("stage") == "passive" else Growth.duration_ms(actor, operation, int(process.get("remaining_ms", recipe.work_ms))) + int(recipe.passive_ms) + int(recipe.finish_ms)
			labor = first + (batches - 1) * (Growth.duration_ms(actor, operation, int(recipe.work_ms)) + int(recipe.passive_ms) + int(recipe.finish_ms))
	estimate += labor
	if terms.deadline_ms > 0 and at + estimate > terms.deadline_ms: return _answer("refuse", "refused_deadline", estimate)
	var traits: Dictionary = context.dispositions
	var familiarity: float = minf(0.18, float(experience.get("exchanges", 0)) * 0.06)
	var support: float = minf(0.18, float(experience.get("support", 0)) * 0.06)
	# Sociability affects seeking contact elsewhere, never general obedience.
	var willingness: float = (0.46 if terms.organization > 0 else 0.30) + familiarity + support
	var burden: float = 0.20 * float(context.need) + 0.20 * float(context.duty) * float(traits.dutifulness)
	burden += 0.12 * float(context.personal) * float(traits.persistence) + 0.12 * actor.responsibilities.size()
	burden += minf(0.22, float(estimate) / 180000.0)
	var diagnosis: Dictionary = {"willingness": willingness, "burden": burden, "need": context.need, "estimate_ms": estimate}
	if context.emergency or actor.recovering:
		return _answer("refuse", "refused_need", estimate, diagnosis)
	var busy: bool = float(context.need) >= 0.25 or willingness - burden < 0.24
	if not busy: return _answer("accept", "accepted_share", estimate, diagnosis)
	var can_defer: bool = request.state == "pending" and context.autonomous and at + 10000 < request.expires_ms and (terms.deadline_ms == 0 or at + 10000 + estimate < terms.deadline_ms)
	if can_defer and (float(context.need) >= 0.25 or float(context.duty) >= 0.25): return _answer("defer", "deferred_need" if float(context.need) >= 0.25 else "deferred_busy", estimate, diagnosis)
	return _answer("refuse", "refused_need" if float(context.need) >= 0.25 else "refused_busy", estimate, diagnosis)

static func _answer(decision: String, reason: String, estimate: int = 0, diagnostic: Dictionary = {}) -> Dictionary:
	return {"decision": decision, "reason": reason, "estimate_ms": estimate, "diagnostic": diagnostic}
