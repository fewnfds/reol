@tool
class_name LearnedMethodDef
extends Resource
## Learning content; execution and material conservation stay with their domains.
@export var id: String = ""
@export var title: String = ""
@export var study_item: String = ""
@export_range(1, 100000) var introduction_points: int = 200
@export_range(1, 100000) var mastery_points: int = 1000
@export var requires_introduction: bool = true
@export var unlocks: PackedStringArray = []
## Only an explicitly associated noncombat activity uses this duration modifier.
@export_range(0.5, 1.0) var mastered_duration_scale: float = 1.0
@export_range(0, 3000) var source_qi_cost: int = 0
@export_range(0, 3000) var qi_gain: int = 0
@export_range(0, 10000) var energy_cost: int = 0
@export_range(0, 10000) var satiety_cost: int = 0

func values() -> Dictionary:
	return {"id": id, "title": title, "study_item": study_item, "introduction_points": introduction_points, "mastery_points": mastery_points,
		"requires_introduction": requires_introduction, "unlocks": Array(unlocks), "mastered_duration_scale": mastered_duration_scale,
		"source_qi_cost": source_qi_cost, "qi_gain": qi_gain, "energy_cost": energy_cost, "satiety_cost": satiety_cost}

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if not id.is_valid_identifier() or title.is_empty(): result.append("id/title: required")
	if not study_item.is_empty() and not preload("res://scripts/sim/kernel/items.gd").valid(study_item): result.append("study item: unknown")
	if introduction_points < 1 or introduction_points > 100000 or mastery_points < 1 or mastery_points > 100000 or not is_finite(mastered_duration_scale) or mastered_duration_scale < 0.5 or mastered_duration_scale > 1.0: result.append("mastery: invalid bounds")
	if unlocks.size() > 8: result.append("unlocks: at most 8")
	for ability: String in unlocks:
		if not ability.is_valid_identifier() or unlocks.count(ability) != 1: result.append("unlock: invalid/duplicate")
	for amount: int in [source_qi_cost, qi_gain, energy_cost, satiety_cost]:
		if amount < 0 or amount > 10000: result.append("practice amount: invalid")
	if source_qi_cost > preload("res://scripts/sim/kernel/resource_pools.gd").QI_MAXIMUM or qi_gain > preload("res://scripts/sim/kernel/resource_pools.gd").QI_MAXIMUM or (qi_gain > 0 and source_qi_cost < qi_gain): result.append("qi conversion: invalid source")
	return result
