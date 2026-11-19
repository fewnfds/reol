extends RefCounted
## Pure queries consume detached personal observations. Never accept a World.
const Defs = preload("res://scripts/sim/kernel/operation_defs.gd")
const Costs = preload("res://scripts/sim/kernel/action_costs.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
const Production = preload("res://scripts/sim/kernel/production.gd")
const Cultivation = preload("res://scripts/sim/kernel/cultivation.gd")
const Construction = preload("res://scripts/sim/kernel/construction_defs.gd")
static var BUILDINGS: Dictionary = Construction.DEFINITIONS
static var PLANTS: Dictionary = preload("res://scripts/sim/kernel/nature_defs.gd").DEFINITIONS

static func evaluate(operation: Dictionary, actor: Dictionary, target: Dictionary, context: Dictionary = {}, buildings: Dictionary = {}) -> Dictionary:
	if buildings.is_empty(): buildings = BUILDINGS
	if actor.get("id", 0) == target.get("id", -1) and target.get("kind") == "actor":
		# Self-targeted inventory requirements mean goods available for personal
		# use. Physical custody alone must not advertise an entrusted meal as food.
		target = target.duplicate()
		target["inventory"] = actor.get("usable_inventory", actor.get("inventory", {}))
	var result: Dictionary = {"applicable": false, "ready": false, "reason": "invalid_target", "unknown": []}
	for rule: Dictionary in operation.targets:
		if not _matches(rule, actor, target, buildings): continue
		if not operation.recipe.is_empty() and operation.recipe.id not in buildings.get(target.get("definition", ""), {}).get("capabilities", {}).get(operation.recipe.facility_capability, {}).get("recipes", []): continue
		result.applicable = true
		var unknown: Array = []
		var reason: String = _target_reason(rule, target, unknown)
		if reason.is_empty() and operation.handler == "plant_crop":
			if not target.has("occupant"): reason = "unknown_target_state"
			elif int(target.occupant) > 0: reason = "occupied"
			elif not PLANTS[operation.plant_definition].substrates.has(Cultivation.spec(buildings[target.definition]).substrate) or PLANTS[operation.plant_definition].blocks: reason = "wrong_substrate"
			else: reason = Cultivation.title_reason(int(actor.get("id", 0)), target, int(target.get("organization", 0)))
		if reason.is_empty() and operation.handler == "fit_eaves":
			if not target.has("eaves"): reason = "unknown_target_state"
			elif target.eaves: reason = "already_has_eaves"
		if reason.is_empty() and operation.handler == "tend": reason = Cultivation.care_reason(target)
		if reason.is_empty() and operation.handler == "practice" and int(Growth.Defs.METHODS[operation.learning_method].source_qi_cost) > 0:
			if not target.has("source_qi_band"): reason = "unknown_target_state"
			elif int(target.source_qi_band) < 0: reason = "not_a_qi_source"
			elif int(target.source_qi_band) < int(Growth.Defs.METHODS[operation.learning_method].source_qi_cost): reason = "insufficient_stored_qi"
		if reason.is_empty() and operation.handler == "eat" and target.has("inventory") and Stock.known_quantity(actor, target, "meal", "eat") <= 0: reason = "no_food"
		var inputs: Dictionary = context.duplicate()
		inputs["organization"] = int(target.get("organization", 0))
		if reason.is_empty(): reason = access_reason(operation, actor, target, context, buildings)
		if reason.is_empty(): reason = readiness(operation, actor, inputs)
		if reason.is_empty() and not operation.recipe.is_empty(): reason = Production.readiness(operation, actor, target, buildings)
		if reason.is_empty() and not unknown.is_empty(): reason = "unknown_target_state"
		result.reason = reason
		result.unknown = unknown
		result.ready = reason.is_empty()
		if result.ready: break
	return result

static func access_reason(operation: Dictionary, actor: Dictionary, target: Dictionary, context: Dictionary = {}, buildings: Dictionary = {}) -> String:
	if buildings.is_empty(): buildings = BUILDINGS
	if operation.executor == "institutions":
		if not actor.get("permissions", {}).has(int(target.get("organization", 0))): return "not_authorized"
		if operation.handler == "post_duty" and actor.get("duties", {}).get(int(context.get("appointment", 0)), {}).get("channel") != target.id: return "not_authorized"
		return ""
	var place: Dictionary = target.duplicate()
	if not operation.recipe.is_empty(): place["processing_purpose"] = operation.recipe.purpose
	var inputs: Dictionary = stock_context(operation, target, context, buildings)
	if operation.handler in ["gather", "collect_source", "harvest"] and context.has("purpose"):
		if not context.purpose is String or context.purpose not in Stock.ISSUE_PURPOSES: return "invalid_purpose"
		if not Stock.permits_at(actor, target, context.purpose, str(inputs.get("item", ""))): return "not_authorized"
	return Stock.access_reason(actor, place, operation.handler, inputs)

static func stock_context(operation: Dictionary, target: Dictionary, context: Dictionary = {}, buildings: Dictionary = {}) -> Dictionary:
	if buildings.is_empty(): buildings = BUILDINGS
	var inputs: Dictionary = context.duplicate()
	if not operation.recipe.is_empty():
		inputs["recipe_items"] = operation.recipe.inputs.keys()
		for item: String in operation.recipe.outputs:
			if item not in inputs.recipe_items: inputs.recipe_items.append(item)
	if operation.handler == "fit_eaves": inputs["recipe_items"] = operation.required_items.keys()
	if operation.handler == "mine": inputs["item"] = "stone"
	if not inputs.has("item"):
		if operation.handler == "eat": inputs["item"] = "meal"
		elif operation.handler == "tend": inputs["item"] = "water"
		elif operation.handler == "collect_source": inputs["item"] = str(buildings.get(target.get("definition", ""), {}).get("capabilities", {}).get("stock_source", {}).get("item", ""))
		elif operation.handler == "harvest" or (operation.handler in ["cut", "uproot"] and target.get("kind") == "resource"): inputs["item"] = "wood"
		elif operation.handler in ["sow", "gather"]: inputs["item"] = str(PLANTS.get(target.get("definition", ""), {}).get("product", {}).get("item", ""))
		elif operation.handler == "plant_crop": inputs["item"] = str(PLANTS[operation.plant_definition].product.item)
	if operation.handler in ["cut", "uproot"]:
		inputs["recipe_items"] = []
		var plant: Dictionary = PLANTS.get(target.get("definition", ""), {})
		for product: String in ["product", "body_product"]:
			if plant.has(product) and plant[product].item not in inputs.recipe_items: inputs.recipe_items.append(plant[product].item)
	return inputs

static func candidates(actor: Dictionary, target: Dictionary, context: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	for id: String in options(target):
		var query: Dictionary = evaluate(Defs.OPERATIONS[id], actor, target, context)
		if query.applicable: result[id] = query
	return result

static func options(target: Dictionary) -> Array:
	var result: Array = Defs.TARGET_INDEX.get(target.get("kind", ""), []).duplicate()
	for id: String in Defs.TARGET_INDEX.get("*", []):
		if not result.has(id): result.append(id)
	return result

static func _matches(rule: Dictionary, actor: Dictionary, target: Dictionary, buildings: Dictionary) -> bool:
	if target.is_empty(): return false
	if not rule.kinds.is_empty() and target.get("kind", "") not in rule.kinds: return false
	if not rule.definitions.is_empty() and target.get("definition", "") not in rule.definitions: return false
	if rule.relation == "self" and actor.get("id", 0) != target.get("id", -1): return false
	if rule.relation == "other" and actor.get("id", 0) == target.get("id", -1): return false
	if rule.sapient and not target.get("sapient", false): return false
	if not rule.facility_capability.is_empty():
		if target.get("kind", "") == "blueprint" or not buildings.get(target.get("definition", ""), {}).get("capabilities", {}).has(rule.facility_capability): return false
	return true

static func _target_reason(rule: Dictionary, target: Dictionary, unknown: Array) -> String:
	if target.get("kind") == "actor":
		if not target.has("hp"): unknown.append("hp")
		elif int(target.hp) <= 0 and rule.actor_state == "living": return "target_dead"
		elif int(target.hp) > 0 and rule.actor_state == "dead": return "target_alive"
	if not rule.stages.is_empty() or not rule.excluded_stages.is_empty():
		if not target.has("stage"): unknown.append("stage")
		elif (not rule.stages.is_empty() and target.stage not in rule.stages) or target.stage in rule.excluded_stages: return "wrong_stage"
	if rule.nonempty or not rule.target_item.is_empty() or rule.free_capacity:
		if not target.has("inventory"): unknown.append("inventory")
		else:
			if rule.nonempty and target.inventory.is_empty(): return "empty"
			if not rule.target_item.is_empty() and int(target.inventory.get(rule.target_item, 0)) <= 0: return "no_food" if rule.target_item == "meal" else "empty"
			if rule.free_capacity:
				if not target.has("capacity"): unknown.append("capacity")
				elif int(target.capacity) >= 0:
					var count: int = 0
					for amount: int in target.inventory.values(): count += amount
					if count + int(target.get("reserved_capacity", 0)) >= int(target.capacity): return "full"
	return ""

static func readiness(operation: Dictionary, actor: Dictionary, context: Dictionary = {}) -> String:
	if int(actor.get("hp", 0)) <= 0: return "dead"
	if not actor.get("admission_reason", "").is_empty(): return actor.admission_reason
	for capability: String in operation.required_capabilities:
		if not actor.get("body_capabilities", {}).get(capability, false): return "body_has_no_%s_capability" % capability
	if not operation.recipe.is_empty(): pass # Target-aware material/WIP checks follow shared actor admission.
	elif operation.handler in ["tend", "plant_crop"]:
		var purpose: String = "cultivate"
		if not operation.required_items.is_empty() and Stock.input_group(actor, operation.required_items, purpose, int(context.get("organization", 0))).is_empty(): return "missing_items"
	else:
		for item: String in operation.required_items:
			if int(actor.get("usable_inventory", actor.get("inventory", {})).get(item, 0)) < int(operation.required_items[item]): return "missing_items"
	if not operation.required_method.is_empty() and not Growth.introduced(actor, operation.required_method): return "method_not_known"
	if operation.handler == "teach" and not Growth.mastered(actor, operation.learning_method): return "method_not_mastered"
	if operation.handler == "practice":
		var reason: String = Growth.practice_readiness(actor, operation.learning_method)
		if not reason.is_empty(): return reason
	if operation.handler in ["learn", "study"] and int(actor.get("methods", {}).get(operation.learning_method, {}).get("understanding", 0)) >= int(Growth.Defs.METHODS[operation.learning_method].introduction_points): return "already_understood"
	if operation.handler == "study" and not operation.get("learning_method", "").is_empty() and int(actor.get("readable", actor.get("inventory", {})).get(Growth.Defs.METHODS[operation.learning_method].study_item, 0)) <= 0: return "missing_book"
	if not operation.required_ability.is_empty() and not actor.get("abilities", {}).get(operation.required_ability, false): return "ability_not_mastered"
	if operation.injured and int(actor.hp) >= int(actor.get("max_hp", actor.get("stats", {}).get("max_hp", actor.hp))): return "full_health"
	if operation.handler == "mine" and int(actor.get("free_inventory_capacity", 1)) <= 0: return "full"
	if operation.actor_inventory and actor.get("carried", actor.get("inventory", {})).is_empty(): return "empty"
	if operation.help_target and int(context.get("help_target", 0)) <= 0: return "invalid_task"
	return Costs.check_view(actor, operation.costs) if not operation.costs.is_empty() else ""
