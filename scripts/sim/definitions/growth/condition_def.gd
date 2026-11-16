@tool
class_name PersistentConditionDef
extends Resource
## Persistent individual condition, separate from temporary combat contributions.
@export var id: String = ""
@export var title: String = ""
@export var causes: PackedStringArray = []
@export var required_capability: String = "metabolism"
@export_range(0.1, 1.0) var speed_scale: float = 1.0
@export_range(0.1, 1.0) var learning_scale: float = 1.0
@export_range(1, 10000) var rest_recovery: int = 500
@export_range(1, 10000) var recovery_needed: int = 1000

func values() -> Dictionary:
	return {"id": id, "title": title, "causes": Array(causes), "required_capability": required_capability,
		"speed_scale": speed_scale, "learning_scale": learning_scale, "rest_recovery": rest_recovery, "recovery_needed": recovery_needed}

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if not id.is_valid_identifier() or title.is_empty(): result.append("id/title: required")
	if causes.is_empty() or causes.size() > 16: result.append("causes: require 1..16")
	for cause: String in causes:
		if not cause.is_valid_identifier() or causes.count(cause) != 1: result.append("cause: invalid/duplicate")
	if not preload("res://scripts/sim/definitions/beings/form_def.gd").CAPABILITIES.has(required_capability): result.append("capability: unknown")
	for scale: float in [speed_scale, learning_scale]:
		if not is_finite(scale) or scale < 0.1 or scale > 1.0: result.append("scale: invalid")
	if rest_recovery < 1 or rest_recovery > 10000 or recovery_needed < 1 or recovery_needed > 10000: result.append("recovery: invalid")
	return result
