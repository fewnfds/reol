class_name SimSchema
extends RefCounted
## Definition validation only. Values are initial conditions, not permanent laws.
## Actor profiles declare the initial actor IDs; individual profile fields are
## optional. World cells and ContentDB references are checked by the runtime.

const VERSION: int = 1
const MAX_COUNT: int = 9007199254740991
const FACTORS: Array[String] = [
	"energy", "busy", "distance", "risk", "duty", "offer", "benevolence",
	"reliability", "affinity",
]
const OUTCOMES: Array[String] = [
	"fulfilled", "completed", "helped", "kept_promise", "failed",
	"broke_promise", "betrayed", "refused",
]
const POSITIVE_INTEGERS: Array[String] = [
	"navigation_budget", "move_minutes_per_cell", "decision_interval", "retry_minutes",
	"request_interval", "talk_radius", "history_limit", "action_timeout",
]


static func validate_config(value: Variant) -> bool:
	if not value is Dictionary or not _json_value(value):
		return false
	if not _integer(value.get("schema_version"), VERSION, VERSION) or not _integer(value.get("seed"), -MAX_COUNT):
		return false
	for field: String in POSITIVE_INTEGERS:
		if not _integer(value.get(field), 1):
			return false
	for field: String in ["navigation_radius", "observation_radius"]:
		if not _integer(value.get(field), 0):
			return false
	for field: String in [
		"needs", "initial_stock", "actor_profiles", "actions", "social_policy", "institution", "scenario",
	]:
		if not value.get(field) is Dictionary:
			return false
	if not _needs(value["needs"]):
		return false
	var places: Dictionary = _place_ids(value.get("place_defs"))
	if places.is_empty() or not _stock(value["initial_stock"], places):
		return false
	var actions: Dictionary = value["actions"]
	var resources: Variant = value.get("resource_sources", {})
	if not resources is Dictionary:
		return false
	for id: Variant in resources:
		var source: Variant = resources[id]
		if not _id(id) or str(id).contains(":") or not source is Dictionary or source.size() != 2 or not _id(source.get("definition")) or not places.has(source.get("place")):
			return false
	if actions.is_empty():
		return false
	for action_id: Variant in actions:
		if not _id(action_id) or not _action(actions[action_id], places, value["initial_stock"], resources):
			return false
		var action: Dictionary = actions[action_id]
		if action.kind == "gather" and (not actions.has(action.supports) or not actions.has(action.survey) or actions[action.survey].get("kind") != "visit" or actions[action.survey].get("target") != action.target):
			return false
	# These are the runtime's built-in need and reporting verbs, not content IDs.
	for verb: String in ["eat", "rest", "report", "check_kitchen"]:
		if not actions.has(verb):
			return false
	if (
		actions["eat"]["kind"] != "consume" or actions["rest"]["kind"] != "rest"
		or actions["report"]["kind"] != "visit" or actions["check_kitchen"]["kind"] != "visit"
	):
		return false
	var profiles: Dictionary = value["actor_profiles"]
	if profiles.is_empty() or not _profiles(profiles, actions):
		return false
	var controlled: Variant = value.get("controlled_actor", "player")
	if not _id(controlled) or not profiles.has(controlled):
		return false
	if value.has("autonomous_controller") and not value.autonomous_controller is bool:
		return false
	if profiles[controlled].get("autonomous", false) != value.get("autonomous_controller", false):
		return false
	return (
		_social_policy(value["social_policy"])
		and _institution(value["institution"], profiles)
		and _scenario(value["scenario"], profiles, actions)
	)


static func _needs(value: Dictionary) -> bool:
	for field: String in [
		"hunger_per_minute", "energy_per_minute", "work_energy_per_minute", "eat_below", "rest_below",
	]:
		if not _range(value.get(field), 0.0, 100.0):
			return false
	return true


static func _place_ids(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not value is Array:
		return result
	for raw: Variant in value:
		if not raw is Dictionary or not _id(raw.get("id")) or not _text(raw.get("label")):
			return {}
		var place_id: String = raw["id"]
		if result.has(place_id) or place_id.begins_with("actor:") or place_id.begins_with("resource:"):
			return {}
		var offset: Variant = raw.get("offset")
		if not offset is Array or offset.size() != 2:
			return {}
		for coordinate: Variant in offset:
			if not _integer(coordinate, -2147483648, 2147483647):
				return {}
		result[place_id] = true
	return result


static func _stock(value: Dictionary, places: Dictionary) -> bool:
	for place_id: Variant in value:
		if not _id(place_id) or not places.has(place_id) or not _items(value[place_id], 0):
			return false
	return true


static func _items(value: Variant, minimum: int) -> bool:
	if not value is Dictionary:
		return false
	for item: Variant in value:
		if not _id(item) or not _integer(value[item], minimum):
			return false
	return true


static func _action(value: Variant, places: Dictionary, stock: Dictionary, resources: Dictionary) -> bool:
	if not value is Dictionary or not _text(value.get("label")):
		return false
	if not value.get("kind") in ["haul", "consume", "recipe", "rest", "visit", "gather", "forage", "irrigate"]:
		return false
	if not _integer(value.get("minutes"), 1):
		return false
	if value.has("contribution") and not _integer(value["contribution"], 0):
		return false
	for field: String in ["source", "target"]:
		if value.has(field) and (not _id(value[field]) or not places.has(value[field])):
			return false
	var kind: String = value["kind"]
	if kind == "irrigate":
		# A finite personal-water action, not a public delivery or production.
		return value.size() == 8 and resources.has(value.get("resource")) and resources[value.resource].place == value.get("target") and value.get("item") == "water" and _integer(value.get("amount"), 1) and value.get("contribution") == 0
	if kind == "forage":
		return resources.has(value.get("resource")) and resources[value.resource].place == value.get("source") and _id(value.get("item")) and _integer(value.get("amount"), 1) and value.get("contribution") == 0 and not value.has("target") and not value.has("stock_below") and not value.has("supports") and _id(value.get("public_action"))
	if kind == "gather":
		return resources.has(value.get("resource")) and resources[value.resource].place == value.get("source") and stock.has(value.get("target")) and _id(value.get("item")) and _integer(value.get("amount"), 1) and _integer(value.get("stock_below"), 0) and _id(value.get("supports")) and _id(value.get("survey"))
	if kind == "haul" or kind == "consume":
		if not _id(value.get("source")) or not stock.has(value["source"]):
			return false
		if not _id(value.get("item")) or not _integer(value.get("amount"), 1):
			return false
	if kind != "consume":
		if not _id(value.get("target")) or not places.has(value["target"]):
			return false
	if kind in ["recipe", "rest", "visit"] and value.has("source"):
		return false
	if kind == "haul":
		return (
			stock.has(value["target"]) and value["source"] != value["target"]
			and _integer(value.get("stock_below"), 0)
		)
	if kind == "consume":
		return _range(value.get("hunger_gain"), 0.0, 100.0)
	if kind == "rest":
		return _range(value.get("energy_gain"), 0.0, 100.0)
	if kind == "recipe":
		return (
			stock.has(value["target"]) and _items(value.get("inputs"), 1)
			and not value["inputs"].is_empty() and _items(value.get("outputs"), 1)
			and not value["outputs"].is_empty() and _integer(value.get("stock_below"), 0)
		)
	return true


static func _profiles(value: Dictionary, actions: Dictionary) -> bool:
	for actor_id: Variant in value:
		if not _id(actor_id) or not value[actor_id] is Dictionary:
			return false
		var profile: Dictionary = value[actor_id]
		if profile.has("definition_id") and not _id(profile["definition_id"]):
			return false
		for field: String in ["hunger", "energy"]:
			if profile.has(field) and not _range(profile[field], 0.0, 100.0):
				return false
		if profile.has("benevolence") and not _range(profile["benevolence"], 0.0, 1.0):
			return false
		if profile.has("autonomous") and not profile["autonomous"] is bool:
			return false
		if profile.has("duty"):
			if not profile["duty"] is String:
				return false
			if not profile["duty"].is_empty() and not actions.has(profile["duty"]):
				return false
	return true


static func _social_policy(value: Dictionary) -> bool:
	if not _number(value.get("bias")) or not _number(value.get("accept_threshold")):
		return false
	if not _number(value.get("uncertainty_band")) or float(value["uncertainty_band"]) < 0.0:
		return false
	if value.has("context_step") and (
		not _range(value["context_step"], 0.0, 1.0) or float(value["context_step"]) == 0.0
	):
		return false
	if not value.get("weights") is Dictionary or not value.get("outcome_effects") is Dictionary:
		return false
	var magnitude: float = absf(float(value["bias"])) + absf(float(value["accept_threshold"]))
	if not is_finite(magnitude):
		return false
	for factor: Variant in value["weights"]:
		if not factor is String or not FACTORS.has(factor) or not _number(value["weights"][factor]):
			return false
		magnitude += absf(float(value["weights"][factor]))
		if not is_finite(magnitude):
			return false
	for outcome: Variant in value["outcome_effects"]:
		if not outcome is String or not OUTCOMES.has(outcome):
			return false
		var effect: Variant = value["outcome_effects"][outcome]
		if not effect is Array or effect.size() != 2:
			return false
		if not _range(effect[0], -1.0, 1.0) or not _range(effect[1], -1.0, 1.0):
			return false
	return true


static func _institution(value: Dictionary, profiles: Dictionary) -> bool:
	if not _id(value.get("id")) or not value.get("offices") is Dictionary:
		return false
	for office_id: Variant in value["offices"]:
		var office: Variant = value["offices"][office_id]
		if not _id(office_id) or not office is Dictionary:
			return false
		if office.size() != 2 or not office.get("holder") is String or not office.get("permissions") is Array:
			return false
		if not office["holder"].is_empty() and not profiles.has(office["holder"]):
			return false
		var seen: Dictionary = {}
		for permission: Variant in office["permissions"]:
			if not permission in ["record", "pay", "authorize"] or seen.has(permission):
				return false
			seen[permission] = true
	return true


static func _scenario(value: Dictionary, profiles: Dictionary, actions: Dictionary) -> bool:
	if not _id(value.get("requester")) or not profiles.has(value["requester"]):
		return false
	if not _id(value.get("task")) or not actions.has(value["task"]):
		return false
	# The current shortage loop needs a hauling task's target/item/amount.
	if actions[value["task"]]["kind"] != "haul":
		return false
	if not value.get("helpers") is Array:
		return false
	var seen: Dictionary = {}
	for helper: Variant in value["helpers"]:
		if not _id(helper) or not profiles.has(helper) or helper == value["requester"] or seen.has(helper):
			return false
		seen[helper] = true
	return true


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _json_value(value: Variant, depth: int = 0) -> bool:
	if depth > 32:
		return false
	if value == null or value is String or value is bool:
		return true
	if value is int or value is float:
		return is_finite(float(value))
	if value is Array:
		for child: Variant in value:
			if not _json_value(child, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _json_value(value[key], depth + 1):
				return false
		return true
	return false


static func _range(value: Variant, minimum: float, maximum: float) -> bool:
	return _number(value) and float(value) >= minimum and float(value) <= maximum


static func _integer(value: Variant, minimum: int, maximum: int = MAX_COUNT) -> bool:
	return _range(value, minimum, maximum) and float(value) == floorf(float(value))


static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()


static func _id(value: Variant) -> bool:
	return _text(value) and value == value.strip_edges()
