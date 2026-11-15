@tool
class_name CombatLibrary
extends Resource
const Ability = preload("res://scripts/sim/definitions/combat/ability_def.gd")
const Loadout = preload("res://scripts/sim/definitions/combat/loadout_def.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
@export var abilities: Array[Ability] = []
@export var loadouts: Array[Loadout] = []

func compile() -> Dictionary:
	var errors := PackedStringArray()
	var actions: Dictionary = {}
	var profiles: Dictionary = {}
	for ability: Ability in abilities:
		if ability == null: errors.append("library.abilities: missing resource"); continue
		var problems: PackedStringArray = ability.errors()
		for error: String in problems: errors.append("%s: %s" % [ability.resource_path, error])
		if not problems.is_empty(): continue # Never compile a missing delivery/effect.
		for cost: Resource in ability.costs:
			if cost.kind == "item" and not Items.valid(cost.id): errors.append(ability.id + ".costs: unknown item " + cost.id)
		if actions.has(ability.id): errors.append("duplicate ability: " + ability.id)
		actions[ability.id] = ability.values()
	for key: String in actions:
		for rule: Dictionary in actions[key].reactions:
			if rule.mode in ["emit", "request"] and not actions.has(rule.template): errors.append(key + ".reactions: unknown template " + rule.template)
			elif rule.mode == "emit" and actions[rule.template].delivery.kind not in ["projectile", "area"]: errors.append(key + ".reactions: emit requires projectile/area; use request for a full action")
		var emitter: String = str(actions[key].delivery.get("emitter", ""))
		if not emitter.is_empty() and (not actions.has(emitter) or actions[emitter].delivery.kind != "projectile"): errors.append(key + ".delivery.emitter: expected projectile template")
		var next: String = actions[key].next
		if not next.is_empty() and not actions.has(next): errors.append(key + ".next: unknown ability " + next)
	for profile: Loadout in loadouts:
		if profile == null: errors.append("library.loadouts: missing resource"); continue
		var problems: PackedStringArray = profile.errors()
		for error: String in problems: errors.append("%s: %s" % [profile.resource_path, error])
		if not problems.is_empty(): continue
		if not Items.valid(profile.equipment) or Items.spec(profile.equipment).get("slot") != "weapon": errors.append(profile.id + ".equipment: expected a weapon item")
		if profile.id.is_empty() or profiles.has(profile.id): errors.append("empty/duplicate loadout: " + profile.id)
		for button: String in ["primary", "skill", "step"]:
			if not actions.has(profile.get(button)): errors.append(profile.id + "." + button + ": unknown ability")
		for button: String in ["skill2", "skill3"]:
			if not str(profile.get(button)).is_empty() and not actions.has(profile.get(button)): errors.append(profile.id + "." + button + ": unknown ability")
		profiles[profile.id] = profile.values()
	for key: String in actions:
		var entity: Dictionary = actions[key].get("entity", {})
		if not entity.is_empty() and entity.body == "companion" and not profiles.has(entity.loadout): errors.append(key + ".entity.loadout: unknown loadout " + entity.loadout)
	for profile: Loadout in loadouts:
		if profile == null: continue
		for rule: Resource in profile.reactions:
			if rule == null: continue
			if rule.mode in ["emit", "request"] and not actions.has(rule.template): errors.append(profile.id + ".reactions: unknown template " + rule.template)
			elif rule.mode == "emit" and actions[rule.template].delivery.kind not in ["projectile", "area"]: errors.append(profile.id + ".reactions: emit requires projectile/area")
	for item_id: String in Items.load_definitions():
		var item: Dictionary = Items.spec(item_id)
		for field: String in ["combat_loadout", "ai_loadout"]:
			if item.has(field) and not profiles.has(item[field]): errors.append(item_id + "." + field + ": unknown loadout")
	for fallback: String in ["sword", "light"]:
		if not profiles.has(fallback): errors.append("library: missing default loadout " + fallback)
	if actions.is_empty() or profiles.is_empty(): errors.append("library: abilities and loadouts required")
	_check_status_periods(self, {}, {}, errors, "library")
	return {"actions": actions if errors.is_empty() else {}, "loadouts": profiles if errors.is_empty() else {}, "errors": errors}

func _check_status_periods(resource: Resource, seen: Dictionary, periods: Dictionary, errors: PackedStringArray, path: String) -> void:
	if seen.has(resource): return
	seen[resource] = true
	var is_status: bool = resource.get_script() == preload("res://scripts/sim/definitions/actions/status_def.gd")
	var is_effect: bool = resource.get_script() == preload("res://scripts/sim/definitions/actions/effect_def.gd")
	if (is_status or is_effect) and resource.kind == "dot":
		var id: String = resource.id if is_status else resource.status_id
		if periods.has(id) and periods[id] != resource.period_ms: errors.append(path + ": dot status_id must use one shared period: " + id)
		periods[id] = resource.period_ms
	for property: Dictionary in resource.get_property_list():
		if property.usage & PROPERTY_USAGE_EDITOR == 0 or property.name == "script": continue
		var value: Variant = resource.get(property.name)
		if value is Resource: _check_status_periods(value, seen, periods, errors, path + "." + property.name)
		elif value is Array:
			for index: int in value.size():
				if value[index] is Resource: _check_status_periods(value[index], seen, periods, errors, "%s.%s[%d]" % [path, property.name, index])
