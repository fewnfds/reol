class_name SimPersonalForaging
extends RefCounted
## Personal work definitions only. Original village systems retain all state.

const Shape = preload("res://scripts/sim/avian_schema.gd")


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "actions"]) or data.version != 1 or not data.actions is Dictionary or data.actions.is_empty():
		return false
	var public_actions: Dictionary = {}
	for id: Variant in data.actions:
		var action: Variant = data.actions[id]
		if not SimInventory._nonempty(id) or not Shape.keys(action, ["label", "kind", "resource", "source", "item", "amount", "minutes", "contribution", "public_action"]) or action.kind != "forage" or action.contribution != 0 or not Shape.count(action.amount, 1, 1000) or not Shape.count(action.minutes, 1, 1440):
			return false
		for field: String in ["label", "resource", "source", "item", "public_action"]:
			if not SimInventory._nonempty(action[field]):
				return false
		if public_actions.has(action.public_action) or id == action.public_action:
			return false
		public_actions[action.public_action] = true
	return true


static func install(config: Variant, rules: Dictionary) -> bool:
	if not config is Dictionary or not config.get("actions") is Dictionary:
		return false
	# Genuine pre-source worlds stay pre-source; no imaginary old harvests.
	if not config.has("resource_sources"):
		return true
	for id: String in rules.actions:
		var definition: Dictionary = rules.actions[id]
		if config.actions.has(id) or not config.resource_sources.has(definition.resource) or not config.actions.has(definition.public_action):
			return false
	for id: String in rules.actions:
		config.actions[id] = rules.actions[id].duplicate(true)
	return true


static func matches(config: Dictionary, rules: Dictionary) -> bool:
	for id: String in config.actions:
		var action: Dictionary = config.actions[id]
		if action.kind != "forage":
			continue
		if not rules.actions.has(id) or not Shape.same_record(action, rules.actions[id]):
			return false
		if not config.actions.has(action.public_action):
			return false
		var public: Dictionary = config.actions[action.public_action]
		if public.kind != "gather" or public.resource != action.resource or public.source != action.source or public.item != action.item:
			return false
	return true
