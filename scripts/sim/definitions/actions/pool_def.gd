@tool
class_name ActionPoolDef
extends Resource
@export var id: String = "mana"
@export_range(1, 100000) var maximum: int = 100
@export_range(0, 100000) var initial: int = 100
@export_range(0, 1000) var regen_per_second: int = 6
func values() -> Dictionary:
	return {"id": id, "maximum": maximum, "initial": initial, "regen": regen_per_second}
func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if id in ["hp", "health", "life", "energy", "qi"]: result.append("id: reserved owner alias")
	if not id.is_valid_identifier() or maximum < 1 or maximum > 100000 or initial < 0 or initial > maximum or regen_per_second < 0 or regen_per_second > 1000: result.append("pool: invalid id/capacity/initial/regen")
	return result
