@tool
class_name BeingFormLibrary
extends Resource
const Form = preload("res://scripts/sim/definitions/beings/form_def.gd")
@export var forms: Array[Form] = []

func compile() -> Dictionary:
	var errors := PackedStringArray()
	var result: Dictionary = {}
	for form: Form in forms:
		if form == null: errors.append("form: required"); continue
		var problems: PackedStringArray = form.errors()
		for problem: String in problems: errors.append(form.id + ": " + problem)
		if result.has(form.id): errors.append("duplicate form: " + form.id); continue
		if problems.is_empty(): result[form.id] = form.values()
	if not result.has("human"): errors.append("missing initial form: human")
	if not result.has("companion"): errors.append("missing summoned form: companion")
	return {"forms": result if errors.is_empty() else {}, "errors": errors}
