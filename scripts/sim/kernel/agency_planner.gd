extends RefCounted
## Bounded, one-step planning over detached self/known views. Only the caller's
## planning budget changes; hosts still own paths, reservations and actual work.
const Defs = preload("res://scripts/sim/kernel/agency_defs.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Query = preload("res://scripts/sim/kernel/operation_query.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
static var PLANTS: Dictionary = Operations.freeze(JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/plants.json")).types)
const WORK_LIMIT: int = 128
const DEPTH_LIMIT: int = 4
var actor: Dictionary
var self_target: Dictionary
var known: Dictionary
var blocked: Dictionary
var position: Vector2
var at_ms: int
var budget: Dictionary
var preferred: Dictionary
var slice_limit: int
var ordered_targets: Array = []
var source_scope: Array = []
var sources_restricted: bool = false

func configure(self_view: Dictionary, own_target: Dictionary, clues: Dictionary, refusals: Dictionary, point: Vector2, at: int, work_budget: Dictionary, intention: Dictionary) -> void:
	actor = self_view; self_target = own_target; known = clues; blocked = refusals
	position = point; at_ms = at; budget = work_budget; preferred = intention
	slice_limit = mini(WORK_LIMIT, int(budget.work) + 32)
	ordered_targets.clear()
	for target: Dictionary in known.values():
		if int(target.get("tile", -1)) >= 0: ordered_targets.append(target)
	ordered_targets.sort_custom(func(a: Dictionary, b: Dictionary):
		var left: float = _distance(a)
		var right: float = _distance(b)
		return left < right if not is_equal_approx(left, right) else a.id < b.id)
	if ordered_targets.size() > 4 and int(budget.cursor) % 2 == 1:
		var offset: int = int(budget.cursor) % ordered_targets.size()
		ordered_targets = ordered_targets.slice(offset) + ordered_targets.slice(0, offset)
	elif ordered_targets.size() > 32:
		var near: Array = ordered_targets.slice(0, 4)
		var rest: Array = ordered_targets.slice(4)
		var offset: int = int(budget.cursor) % rest.size()
		ordered_targets = near + rest.slice(offset) + rest.slice(0, offset)

func _spend() -> bool:
	if int(budget.work) >= slice_limit: return false
	budget.work += 1
	return true

func _denied(operation: String, target: int) -> bool:
	return blocked.has("%s:%d" % [operation, target])

func _distance(target: Dictionary) -> float:
	return 0.0 if target.id == actor.id else position.distance_to(Terrain.center(int(target.tile)))

func _step(operation: Dictionary, target: Dictionary, parameters: Dictionary = {}) -> Dictionary:
	var input: Dictionary = {"kind": operation.id, "target": int(target.id)}
	input.merge(parameters, true)
	var duration: int = maxi(0, int(operation.duration_ms))
	if not operation.recipe.is_empty():
		duration = int(target.get("process", {}).get("remaining_ms", operation.recipe.work_ms)) + int(operation.recipe.finish_ms)
	return {"kind": "execute", "input": input, "estimate_ms": duration + roundi(_distance(target) / maxf(0.1, float(actor.speed)) * 1000), "confidence": 1.0}

func _inspect(target: Dictionary, reason: String = "unknown_target_state") -> Dictionary:
	if int(target.get("tile", -1)) < 0 or _denied("inspect", int(target.id)): return {}
	return {"kind": "inspect", "input": {"target": int(target.id)}, "estimate_ms": roundi(_distance(target) / maxf(0.1, float(actor.speed)) * 1000), "confidence": 0.7, "reason": reason}

func _targets(source: String, goal: Dictionary) -> Array:
	if source == "self": return [self_target]
	if source == "goal":
		var id: int = int(goal.params.get("target", 0))
		return [self_target] if id == actor.id else ([known[id]] if known.has(id) and int(known[id].get("tile", -1)) >= 0 else [])
	return [self_target] + ordered_targets if source == "either" else ordered_targets

func candidates(goal: Dictionary, approach: Dictionary, allowance: int = 32) -> Array:
	slice_limit = mini(WORK_LIMIT, int(budget.work) + allowance)
	source_scope = []
	sources_restricted = false
	match approach.pattern:
		"responsibility":
			var terms: Dictionary = actor.get("responsibilities", {}).get(int(goal.params.share), {})
			if terms.is_empty(): return []
			var projected: Dictionary = project(goal, actor)
			source_scope = terms.sources.duplicate()
			sources_restricted = true
			if terms.kind == "delivery": return _delivery(projected, [])
			return _perform(projected, {"targets": "goal", "handler": "", "prerequisites": true}, [])
		"perform": return _perform(goal, approach, [])
		"produce": return _produce(goal, str(approach.product), [])
		"develop": return _develop(goal, str(goal.params.method), [])
		"deliver": return _delivery(goal, [])
		"return": return _returns(goal, [])
	return []

static func project(goal: Dictionary, view: Dictionary) -> Dictionary:
	if Defs.GOALS[goal.definition].driver != "responsibility": return goal
	var terms: Dictionary = view.get("responsibilities", {}).get(int(goal.params.share), {})
	if terms.is_empty(): return {"params": {}, "progress": 0}
	return {"params": {"operation": terms.operation, "target": terms.target, "item": terms.item, "amount": terms.remaining, "organization": terms.organization}, "progress": 0}

func _option(step: Dictionary, operation: String, target: int) -> Dictionary:
	if step.is_empty(): return {}
	return {"operation": operation, "anchor": target, "step": step}

func _perform(goal: Dictionary, approach: Dictionary, chain: Array) -> Array:
	var result: Array = []
	var required: String = str(goal.params.get("operation", "")) if approach.targets == "goal" else ""
	for target: Dictionary in _targets(approach.targets, goal):
		for id: String in Query.options(target):
			if not required.is_empty() and id != required: continue
			var operation: Dictionary = Operations.OPERATIONS[id]
			if required.is_empty() and operation.handler != approach.handler: continue
			var step: Dictionary = _resolve(operation, target, chain, bool(approach.prerequisites))
			if not step.is_empty(): result.append(_option(step, id, target.id))
			if int(budget.work) >= slice_limit: return result
	return result

func _resolve(operation: Dictionary, target: Dictionary, chain: Array, prerequisites: bool = true, context: Dictionary = {}) -> Dictionary:
	var key: String = "%s:%d" % [operation.id, target.id]
	if chain.size() >= DEPTH_LIMIT or key in chain or _denied(operation.id, target.id) or not _spend(): return {}
	var query: Dictionary = Query.evaluate(operation, actor, target, context)
	if not query.applicable: return {}
	if query.ready: return _step(operation, target, context)
	if query.reason == "unknown_target_state": return _inspect(target)
	if query.reason == "unattended_in_progress":
		return {"kind": "wait", "input": {"target": int(target.id)}, "until_ms": int(target.process.ready_ms), "estimate_ms": maxi(0, int(target.process.ready_ms) - at_ms), "confidence": 0.95}
	if not prerequisites: return {}
	var next: Array = chain + [key]
	if query.reason == "missing_book":
		return _acquire(str(Growth.Defs.METHODS[operation.learning_method].study_item), 1, -1, "study", next)
	if query.reason == "method_not_known":
		var options: Array = _develop({"params": {"method": operation.required_method}}, operation.required_method, next)
		return _best(options).get("step", {})
	if query.reason != "missing_items": return {}
	var inputs: Dictionary = operation.recipe.inputs if not operation.recipe.is_empty() else operation.required_items
	var purpose: String = Stock.input_purpose(operation)
	var organization: int = int(target.get("organization", 0))
	var bundle: Dictionary = _input_bundle(inputs, organization, purpose)
	var items: Array = inputs.keys(); items.sort()
	for item: String in items:
		var deficit: int = maxi(0, int(inputs[item]) - int(bundle.get(item, 0)))
		if deficit > 0:
			var step: Dictionary = _acquire(item, deficit, organization, purpose, next)
			if not step.is_empty(): step.estimate_ms += maxi(0, int(operation.recipe.get("work_ms", operation.duration_ms)))
			return step
	return {}

func _input_bundle(inputs: Dictionary, organization: int, purpose: String) -> Dictionary:
	var best: Dictionary = {}
	var score: float = -1.0
	for bundle: Dictionary in actor.bundles:
		if int(bundle.organization) != organization or (organization > 0 and bundle.purpose != purpose): continue
		var amount: float = 0.0
		for item: String in inputs: amount += minf(1.0, float(bundle.items.get(item, 0)) / int(inputs[item]))
		if amount > score: best = bundle.items; score = amount
	return best

func _acquire(item: String, count: int, organization: int, purpose: String, chain: Array, excluded: Array = []) -> Dictionary:
	var key: String = "item:%s:%d:%s" % [item, organization, purpose]
	if chain.size() >= DEPTH_LIMIT or key in chain: return {}
	var next: Array = chain + [key]
	if organization != 0:
		for bundle: Dictionary in actor.bundles:
			var wrong_origin: bool = purpose == "supply" and sources_restricted and int(bundle.get("origin", 0)) not in source_scope
			if int(bundle.organization) > 0 and (organization < 0 or bundle.organization == organization) and (bundle.purpose != purpose or wrong_origin) and int(bundle.items.get(item, 0)) > 0:
				if not excluded.is_empty() and _retains(bundle, item): return {}
				var origins: Variant = [int(bundle.origin)] if bundle.purpose == "supply" else null
				var deposited: Dictionary = _deposit(item, int(bundle.items[item]), int(bundle.organization), 0, next, bundle.purpose, origins)
				return deposited # No legal middle store: do not gather more unusable stock.
	var choices: Array = []
	for target: Dictionary in _targets("known", {}):
		if sources_restricted and target.id not in source_scope: continue
		if target.id in excluded: continue
		var target_org: int = int(target.get("organization", 0))
		if organization >= 0 and target_org != organization and not target.has("contents"): continue
		if not target.has("inventory"):
			if target.kind in ["chest", "pile", "source", "workbench", "plant"]:
				var inspect: Dictionary = _inspect(target)
				if not inspect.is_empty(): choices.append(_option(inspect, "", target.id))
			continue
		if int(target.inventory.get(item, 0)) <= 0: continue
		for id: String in Query.options(target):
			var operation: Dictionary = Operations.OPERATIONS[id]
			if operation.handler not in ["take", "collect_source", "gather", "harvest"]: continue
			var stock_org: int = _take_origin(target, item, organization, purpose) if operation.handler == "take" else target_org
			if operation.handler == "take" and stock_org < 0: continue
			if operation.handler != "take" and organization >= 0 and target_org != organization: continue
			# Harvest/gather must yield the wanted item; a source collection's
			# configured item is read from the same immutable facility catalog.
			if operation.handler == "collect_source" and Query.BUILDINGS.get(target.definition, {}).get("capabilities", {}).get("stock_source", {}).get("item", "") != item: continue
			if operation.handler == "harvest":
				var yields_item: bool = false
				for rule: Dictionary in operation.targets:
					if rule.target_item == item: yields_item = true
				if not yields_item: continue
			if operation.handler == "gather":
				var product: Dictionary = PLANTS.get(target.definition, {}).get("product", {})
				if product.get("item", "") != item: continue
			var context: Dictionary = {"item": item}
			if operation.handler == "take" and stock_org > 0: context.merge({"purpose": purpose, "source_organization": stock_org})
			if operation.handler in ["gather", "collect_source", "harvest"] and target_org > 0 and not purpose.is_empty(): context["purpose"] = purpose
			var step: Dictionary = _resolve(operation, target, next, false, context)
			if step.is_empty(): continue
			if operation.handler == "take":
				step.input["item"] = item
				step.input["amount"] = mini(count, Stock.known_quantity(actor, target, item, "take", stock_org))
				if stock_org > 0:
					step.input["purpose"] = purpose
					step.input["source_organization"] = stock_org
				step.confidence *= 0.98
			else:
				if operation.handler in ["gather", "collect_source"]: step.input["amount"] = count
				step.confidence *= 0.78 if target_org > 0 and purpose not in ["supply", "cultivate"] else 0.9
			choices.append(_option(step, id, target.id))
			if int(budget.work) >= slice_limit: return _best(choices).get("step", {})
	return _best(choices).get("step", {})

func _take_origin(target: Dictionary, item: String, organization: int, purpose: String) -> int:
	var origins: Array = [organization] if organization >= 0 else [0]
	if organization < 0:
		for group: Dictionary in target.get("contents", {}).get(item, []):
			if not origins.has(int(group.organization)): origins.append(int(group.organization))
		if not target.has("contents") and not origins.has(int(target.get("organization", 0))): origins.append(int(target.organization))
	for origin: int in origins:
		if origin > 0 and not Stock.permits_issue(actor, target, origin, purpose, item): continue
		if Stock.known_quantity(actor, target, item, "take", origin) > 0: return origin
	return -1

func _deposit(item: String, count: int, organization: int, destination: int, chain: Array, purpose: String = "", origins: Variant = null) -> Dictionary:
	var choices: Array = []
	for target: Dictionary in _targets("known", {}):
		if int(target.get("organization", 0)) != organization or (destination > 0 and target.id != destination): continue
		if destination == 0 and not Query.BUILDINGS.get(target.definition, {}).get("capabilities", {}).has("storage"): continue
		for id: String in Query.options(target):
			var operation: Dictionary = Operations.OPERATIONS[id]
			if operation.handler != "put": continue
			var step: Dictionary = _resolve(operation, target, chain, false, {"item": item, "purpose": purpose})
			if step.is_empty(): continue
			step.input.merge({"item": item, "amount": count}, true)
			if not purpose.is_empty(): step.input["purpose"] = purpose
			if origins != null: step.input["origins"] = origins.duplicate()
			choices.append(_option(step, id, target.id))
			if int(budget.work) >= slice_limit: return _best(choices).get("step", {})
	return _best(choices).get("step", {})

func _produce(goal: Dictionary, item: String, chain: Array) -> Array:
	var result: Array = []
	for target: Dictionary in _targets("known", goal):
		var process: Dictionary = target.get("process", {})
		# Helping somebody else's private pot can be a valid operation, but it
		# cannot be offered as a way to obtain food for oneself.
		if not process.is_empty() and int(process.get("output_owner", 0)) > 0 and int(process.output_owner) != int(actor.id): continue
		for id: String in Query.options(target):
			var operation: Dictionary = Operations.OPERATIONS[id]
			if operation.recipe.is_empty() or not operation.recipe.outputs.has(item): continue
			var step: Dictionary = _resolve(operation, target, chain)
			if not step.is_empty(): result.append(_option(step, id, target.id))
			if int(budget.work) >= slice_limit: return result
	return result

func _develop(goal: Dictionary, method: String, chain: Array) -> Array:
	var result: Array = []
	if not Growth.Defs.METHODS.has(method) or Growth.mastered(actor, method): return result
	var introduced: bool = Growth.introduced(actor, method)
	for target: Dictionary in _targets("either", goal):
		for id: String in Query.options(target):
			var operation: Dictionary = Operations.OPERATIONS[id]
			var practical: bool = operation.handler == "practice" or not operation.recipe.is_empty()
			if operation.learning_method != method or (introduced != practical): continue
			if not practical and operation.handler not in ["learn", "study"]: continue
			if practical and actor.get("body_capabilities", {}).get("metabolism", false):
				var spec: Dictionary = Growth.Defs.METHODS[method]
				if int(actor.energy) < maxi(800, int(spec.energy_cost)) or int(actor.hunger) < maxi(800, int(spec.satiety_cost)): continue
			var step: Dictionary = _resolve(operation, target, chain)
			if step.is_empty(): continue
			if operation.handler == "learn":
				step.confidence *= 1.0 if target.get("teaches", {}).has(method) else 0.65
				step["social"] = true
			elif operation.handler == "study": step["social"] = false
			result.append(_option(step, id, target.id))
			if int(budget.work) >= slice_limit: return result
	return result

func _delivery(goal: Dictionary, chain: Array) -> Array:
	var item: String = goal.params.item
	var remaining: int = maxi(0, int(goal.params.amount) - int(goal.progress))
	var organization: int = int(goal.params.get("organization", 0))
	var destination: int = int(goal.params.get("target", 0))
	if destination > 0:
		var place: Dictionary = known.get(destination, {})
		if int(place.get("tile", -1)) < 0 or _denied("put", destination) or not Stock.access_reason(actor, place, "put", {"item": item, "purpose": "supply"}).is_empty(): return []
		if not place.has("inventory"):
			var inspect: Dictionary = _inspect(place)
			return [_option(inspect, "put", destination)] if not inspect.is_empty() else []
		if int(place.get("capacity", -1)) >= 0 and int(place.inventory.values().reduce(func(a: int, b: int): return a + b, 0)) >= int(place.capacity): return []
	if preferred.get("retained", {}).has("%d::%s" % [organization, item]): return []
	var held: int = 0
	for bundle: Dictionary in actor.bundles:
		if int(bundle.organization) == organization and (organization == 0 or (bundle.purpose == "supply" and int(bundle.get("origin", 0)) != int(goal.params.get("target", 0)) and (source_scope.is_empty() or int(bundle.get("origin", 0)) in source_scope))): held += int(bundle.items.get(item, 0))
	if held > 0:
		var step: Dictionary = _deposit(item, mini(remaining, held), organization, int(goal.params.get("target", 0)), chain, "supply" if organization > 0 else "", source_scope if sources_restricted else null)
		return [_option(step, "put", int(step.input.target))] if not step.is_empty() else []
	# Never fulfil a supply purpose by withdrawing and redepositing its own
	# destination's stock. An unspecified destination means any legal store.
	var excluded: Array = []
	for target: Dictionary in known.values():
		if int(goal.params.get("target", 0)) > 0:
			if target.id == goal.params.target: excluded.append(target.id)
		elif Query.BUILDINGS.get(target.definition, {}).get("capabilities", {}).has("storage"): excluded.append(target.id)
	var step: Dictionary = _acquire(item, remaining, organization, "supply" if organization > 0 else "", chain, excluded)
	return [_option(step, "put", int(goal.params.get("target", 0)))] if not step.is_empty() else []

func _returns(goal: Dictionary, chain: Array) -> Array:
	var result: Array = []
	for bundle: Dictionary in actor.return_bundles:
		if int(bundle.entrust) <= 0: continue
		for item: String in bundle.items:
			if Stock.permits_purpose(actor, int(bundle.organization), bundle.purpose, item) and _retains(bundle, item): continue
			var origins: Variant = [int(bundle.origin)] if bundle.purpose == "supply" and int(bundle.get("origin", 0)) > 0 else null
			var step: Dictionary = _deposit(item, int(bundle.items[item]), int(bundle.organization), 0, chain, bundle.purpose, origins)
			if not step.is_empty(): result.append(_option(step, "put", int(step.input.target)))
	return result

func _retains(bundle: Dictionary, item: String) -> bool:
	var key: String = "%d:%s:%s" % [int(bundle.organization), bundle.purpose, item]
	return preferred.get("retained", {}).has(key) or (bundle.purpose == "supply" and preferred.get("retained", {}).has(key + ":%d" % int(bundle.get("origin", 0))))

static func _best(options: Array) -> Dictionary:
	var result: Dictionary = {}
	var score: float = -INF
	for option: Dictionary in options:
		var value: float = float(option.step.confidence) - minf(0.45, float(option.step.estimate_ms) / 120000.0)
		if value > score: result = option; score = value
	return result
