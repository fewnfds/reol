@tool
class_name GrowthLibrary
extends Resource
const Method = preload("res://scripts/sim/definitions/growth/method_def.gd")
const Condition = preload("res://scripts/sim/definitions/growth/condition_def.gd")
@export var methods: Array[Method] = []
@export var conditions: Array[Condition] = []

func compile() -> Dictionary:
	var result: Dictionary = {"methods": {}, "conditions": {}, "errors": PackedStringArray()}
	if methods.size() > 64 or conditions.size() > 16: result.errors.append("growth catalog: too large")
	for category: String in ["methods", "conditions"]:
		for entry: Resource in get(category):
			if entry == null: result.errors.append(category + ": null definition"); continue
			if result[category].has(entry.id): result.errors.append(category + ": duplicate " + entry.id); continue
			var errors: PackedStringArray = entry.errors()
			for error: String in errors: result.errors.append(entry.id + ": " + error)
			if errors.is_empty(): result[category][entry.id] = entry.values()
	if not result.errors.is_empty():
		result.methods.clear()
		result.conditions.clear()
	return result
