@tool
class_name BeingFormDef
extends Resource
## Authoring source only. Runtime consumers use the compiled value table.
const CAPABILITIES: Array[String] = ["work", "contact", "metabolism", "environment"]
@export var id: String = ""
@export var title: String = ""
@export_flags("Work", "Contact", "Metabolism", "Environment") var capabilities: int = 15

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if not id.is_valid_identifier() or title.is_empty(): result.append("id/title: required")
	if capabilities < 0 or capabilities > 15: result.append("capabilities: unknown bits")
	return result

func values() -> Dictionary:
	var enabled: Dictionary = {}
	for index: int in CAPABILITIES.size(): enabled[CAPABILITIES[index]] = (capabilities & (1 << index)) != 0
	return {"id": id, "title": title, "capabilities": enabled}
