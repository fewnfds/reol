@tool
class_name OperationTargetRule
extends Resource
## Flat alternatives, never a nested expression language.
@export var kinds: PackedStringArray = []
@export var definitions: PackedStringArray = []
@export var facility_capability: String = ""
@export_enum("any", "self", "other") var relation: String = "any"
@export var sapient: bool = false
@export var stages: PackedInt32Array = []
@export var excluded_stages: PackedInt32Array = []
@export var nonempty: bool = false
@export var target_item: String = ""
@export var free_capacity: bool = false
@export_enum("living", "dead", "any") var actor_state: String = "living"

func values() -> Dictionary:
	return {"kinds": Array(kinds), "definitions": Array(definitions), "facility_capability": facility_capability,
		"relation": relation, "sapient": sapient, "stages": Array(stages), "excluded_stages": Array(excluded_stages),
		"nonempty": nonempty, "target_item": target_item, "free_capacity": free_capacity, "actor_state": actor_state}

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if relation not in ["any", "self", "other"]: result.append("relation: unknown")
	if actor_state not in ["living", "dead", "any"]: result.append("actor state: unknown")
	if not facility_capability.is_empty() and not facility_capability.is_valid_identifier(): result.append("facility capability: invalid")
	for stage: int in stages + excluded_stages:
		if stage < 0 or stage > 4: result.append("stage: unknown")
	for key: String in kinds + definitions:
		if not key.is_valid_identifier(): result.append("target identifier: invalid")
	if not target_item.is_empty() and not preload("res://scripts/sim/kernel/items.gd").valid(target_item): result.append("target item: unknown")
	return result
