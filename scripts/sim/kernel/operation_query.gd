extends RefCounted
## Pure queries consume detached personal observations. Never accept a World.
const Defs = preload("res://scripts/sim/kernel/operation_defs.gd")
const Costs = preload("res://scripts/sim/kernel/action_costs.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
static var BUILDINGS: Dictionary = Defs.freeze(JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/construction.json")).types)

static func evaluate(operation: Dictionary, actor: Dictionary, target: Dictionary, context: Dictionary = {}, buildings: Dictionary = {}) -> Dictionary:
	if buildings.is_empty(): buildings = BUILDINGS
	var result: Dictionary = {"applicable": false, "ready": false, "reason": "invalid_target", "unknown": []}
	for rule: Dictionary in operation.targets:
		if not _matches(rule, actor, target, buildings): continue
		result.applicable = true
		var unknown: Array = []
		var reason: String = _target_reason(rule, target, unknown)
		if reason.is_empty(): reason = readiness(operation, actor, context)
		if reason.is_empty() and not unknown.is_empty(): reason = "unknown_target_state"
		result.reason = reason
		result.unknown = unknown
		result.ready = reason.is_empty()
		if result.ready: break
	return result

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
		elif int(target.hp) <= 0: return "target_dead"
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
					if count >= int(target.capacity): return "full"
	return ""

static func readiness(operation: Dictionary, actor: Dictionary, context: Dictionary = {}) -> String:
	if int(actor.get("hp", 0)) <= 0: return "dead"
	if not actor.get("admission_reason", "").is_empty(): return actor.admission_reason
	for capability: String in operation.required_capabilities:
		if not actor.get("body_capabilities", {}).get(capability, false): return "body_has_no_%s_capability" % capability
	for item: String in operation.required_items:
		if int(actor.get("inventory", {}).get(item, 0)) < int(operation.required_items[item]): return "missing_items"
	if not operation.required_method.is_empty() and not Growth.introduced(actor, operation.required_method): return "method_not_known"
	if operation.handler in ["learn", "study"] and int(actor.get("methods", {}).get(operation.learning_method, {}).get("understanding", 0)) >= int(Growth.Defs.METHODS[operation.learning_method].introduction_points): return "already_understood"
	if operation.handler == "study" and not operation.get("learning_method", "").is_empty() and int(actor.get("inventory", {}).get(Growth.Defs.METHODS[operation.learning_method].study_item, 0)) <= 0: return "missing_book"
	if not operation.required_ability.is_empty() and not actor.get("abilities", {}).get(operation.required_ability, false): return "ability_not_mastered"
	if operation.injured and int(actor.hp) >= int(actor.get("max_hp", actor.get("stats", {}).get("max_hp", actor.hp))): return "full_health"
	if operation.actor_inventory and actor.get("inventory", {}).is_empty(): return "empty"
	if operation.help_target and int(context.get("help_target", 0)) <= 0: return "invalid_task"
	return Costs.check_view(actor, operation.costs) if not operation.costs.is_empty() else ""
