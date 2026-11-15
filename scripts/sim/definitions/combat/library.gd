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
	var status_periods: Dictionary = {}
	for ability: Ability in abilities:
		if ability == null: errors.append("library.abilities: missing resource"); continue
		var problems: PackedStringArray = ability.errors()
		for error: String in problems: errors.append("%s: %s" % [ability.resource_path, error])
		if not problems.is_empty(): continue # Never compile a missing delivery/effect.
		if ability.cost_amount > 0 and not Items.valid(ability.cost_item): errors.append(ability.id + ".cost_item: unknown item")
		if actions.has(ability.id): errors.append("duplicate ability: " + ability.id)
		for effect: Resource in ability.bundle.effects:
			if effect == null or effect.kind != "dot": continue
			if status_periods.has(effect.status_id) and status_periods[effect.status_id] != effect.period_ms: errors.append(ability.id + ": dot status_id must use one shared period: " + effect.status_id)
			status_periods[effect.status_id] = effect.period_ms
		actions[ability.id] = ability.values()
	for key: String in actions:
		var next: String = actions[key].next
		if not next.is_empty() and not actions.has(next): errors.append(key + ".next: unknown ability " + next)
	for profile: Loadout in loadouts:
		if profile == null: errors.append("library.loadouts: missing resource"); continue
		for error: String in profile.errors(): errors.append("%s: %s" % [profile.resource_path, error])
		if not Items.valid(profile.equipment) or Items.spec(profile.equipment).get("slot") != "weapon": errors.append(profile.id + ".equipment: expected a weapon item")
		if profile.id.is_empty() or profiles.has(profile.id): errors.append("empty/duplicate loadout: " + profile.id)
		for button: String in ["primary", "skill", "step"]:
			if not actions.has(profile.get(button)): errors.append(profile.id + "." + button + ": unknown ability")
		profiles[profile.id] = profile.values()
	for item_id: String in Items.load_definitions():
		var item: Dictionary = Items.spec(item_id)
		for field: String in ["combat_loadout", "ai_loadout"]:
			if item.has(field) and not profiles.has(item[field]): errors.append(item_id + "." + field + ": unknown loadout")
	for fallback: String in ["sword", "light"]:
		if not profiles.has(fallback): errors.append("library: missing default loadout " + fallback)
	if actions.is_empty() or profiles.is_empty(): errors.append("library: abilities and loadouts required")
	return {"actions": actions if errors.is_empty() else {}, "loadouts": profiles if errors.is_empty() else {}, "errors": errors}
