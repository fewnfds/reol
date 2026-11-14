@tool
class_name CombatLoadoutDef
extends Resource
@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export var primary: String = ""
@export var skill: String = ""
@export var step: String = "step"
@export var equipment: String = "iron_sword"
@export var playable: bool = true
@export_range(0.5, 20.0) var engage_range: float = 1.5

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if not id.is_valid_identifier() or title.is_empty(): result.append("id/title: valid id and title required")
	if not is_finite(engage_range) or engage_range < 0.5 or engage_range > 20: result.append("engage_range: must be 0.5..20")
	return result

func values() -> Dictionary:
	return {"id": id, "title": title, "description": description, "primary": primary, "skill": skill,
		"step": step, "equipment": equipment, "playable": playable, "range": engage_range}
