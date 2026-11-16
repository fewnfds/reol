@tool
class_name OperationLibrary
extends Resource
const Operation = preload("res://scripts/sim/definitions/operations/operation_def.gd")
@export var operations: Array[Operation] = []
@export var required_ids: PackedStringArray = []

func compile() -> Dictionary:
	var result: Dictionary = {}
	var errors := PackedStringArray()
	for operation: Operation in operations:
		if operation == null: errors.append("operation: required"); continue
		if result.has(operation.id): errors.append("duplicate operation: " + operation.id); continue
		var problems: PackedStringArray = operation.errors()
		for problem: String in problems: errors.append(operation.id + ": " + problem)
		if problems.is_empty(): result[operation.id] = operation.values()
	for id: String in required_ids:
		if not result.has(id): errors.append("missing required operation: " + id)
	return {"operations": result if errors.is_empty() else {}, "errors": errors}
