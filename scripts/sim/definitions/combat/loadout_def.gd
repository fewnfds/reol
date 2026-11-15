@tool
class_name CombatLoadoutDef
extends Resource
const Reaction = preload("res://scripts/sim/definitions/actions/reaction_def.gd")
@export var reactions: Array[Reaction] = []
const Pool = preload("res://scripts/sim/definitions/actions/pool_def.gd")
@export var pools: Array[Pool] = []
@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export var primary: String = ""
@export var skill: String = ""
@export var skill2: String = ""
@export var skill3: String = ""
@export var step: String = "step"
@export var equipment: String = "iron_sword"
@export var playable: bool = true
@export_range(0.5, 20.0) var engage_range: float = 1.5

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if reactions.size() > 8: result.append("reactions: at most 8")
	for rule: Reaction in reactions:
		if rule == null: result.append("reactions: required resource"); continue
		for error: String in rule.errors(): result.append("reactions." + error)
	if pools.size() > 8: result.append("pools: at most 8")
	var seen: Dictionary = {}
	for pool: Pool in pools:
		if pool == null: result.append("pools: required resource"); continue
		for error: String in pool.errors(): result.append(error)
		if seen.has(pool.id): result.append("pools: duplicate " + pool.id)
		seen[pool.id] = true
	if not id.is_valid_identifier() or title.is_empty(): result.append("id/title: valid id and title required")
	if not is_finite(engage_range) or engage_range < 0.5 or engage_range > 20: result.append("engage_range: must be 0.5..20")
	return result

func _pool_values() -> Array:
	var result: Array = []
	for pool: Pool in pools: result.append(pool.values())
	return result

func _reaction_values() -> Array:
	var result: Array = []
	for rule: Reaction in reactions: result.append(rule.values())
	return result

func values() -> Dictionary:
	return {"reactions": _reaction_values(), "id": id, "title": title, "description": description, "primary": primary, "skill": skill, "skill2": skill2, "skill3": skill3,
		"pools": _pool_values(), "step": step, "equipment": equipment, "playable": playable, "range": engage_range}
