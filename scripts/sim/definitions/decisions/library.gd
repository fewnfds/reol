@tool
class_name UnitDecisionLibrary
extends Resource
const Policy = preload("res://scripts/sim/definitions/decisions/policy_def.gd")
@export var policies: Array[Policy] = []

func compile() -> Dictionary:
	var errors := PackedStringArray()
	var result: Dictionary = {}
	for policy: Policy in policies:
		if policy == null: errors.append("policy: required"); continue
		for error: String in policy.errors(): errors.append(policy.id + ": " + error)
		if result.has(policy.id): errors.append("duplicate policy: " + policy.id)
		if policy.errors().is_empty(): result[policy.id] = policy.values()
	for required: String in ["resident", "basic", "pressure", "heavy", "ranged", "cautious"]:
		if not result.has(required): errors.append("missing policy: " + required)
	return {"policies": result, "errors": errors}
