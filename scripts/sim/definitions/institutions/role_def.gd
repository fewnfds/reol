@tool
class_name InstitutionRoleDef
extends Resource
## A role describes authority. An appointment supplies its actual people/places.
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Duty = preload("res://scripts/sim/definitions/institutions/duty_def.gd")
@export var id: String = ""
@export var title: String = ""
@export var purposes: PackedStringArray = []
@export var stock_items: PackedStringArray = []
@export var all_items: bool = false
@export var duty: Duty

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if not id.is_valid_identifier() or id.length() > 64 or title.is_empty(): result.append("role id/title required")
	if purposes.is_empty(): result.append("role purposes required")
	for purpose: String in purposes:
		if purpose not in Stock.PURPOSES or purposes.count(purpose) != 1: result.append("invalid/repeated role purpose: " + purpose)
	for item: String in stock_items:
		if not Items.valid(item) or stock_items.count(item) != 1: result.append("invalid/repeated role item: " + item)
	if all_items and not stock_items.is_empty(): result.append("role all_items and stock_items are exclusive")
	for purpose: String in purposes:
		if purpose not in ["rest", "demolish"] and not all_items and stock_items.is_empty(): result.append("role stock authority requires items or explicit all_items")
	if duty != null:
		result.append_array(duty.errors())
		var required: Array = ["commission", "take"]
		var inputs: Array = [duty.item]
		if duty.kind == "delivery": required.append_array(["put", "supply"])
		else:
			var recipe: Dictionary = Duty.Operations.OPERATIONS.get(duty.operation, {}).get("recipe", {})
			if not recipe.is_empty(): required.append(recipe.purpose); inputs.append_array(recipe.inputs.keys())
		for purpose: String in required:
			if purpose not in purposes: result.append("duty role missing purpose: " + purpose)
		for item: String in inputs:
			if not all_items and item not in stock_items: result.append("duty role missing item: " + item)
	return result

func values() -> Dictionary:
	var grants: Array = Array(purposes); grants.sort()
	var items: Array = Array(stock_items); items.sort()
	return {"id": id, "title": title, "purposes": grants, "items": items, "all_items": all_items, "duty": duty.values() if duty != null else {}}
