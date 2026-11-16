@tool
class_name ProductionRecipeDef
extends Resource
## Material transformation only; approach, consent and occupation stay in OperationDef.
const Items = preload("res://scripts/sim/kernel/items.gd")
const GrowthDefs = preload("res://scripts/sim/kernel/growth_defs.gd")
const Cost = preload("res://scripts/sim/definitions/actions/cost_def.gd")
@export var id: String = ""
@export var title: String = ""
@export var facility_capability: String = "workbench"
@export var purpose: String = "cook"
@export var inputs: Dictionary[String, int] = {}
@export var outputs: Dictionary[String, int] = {}
@export_range(1, 300000) var work_ms: int = 4000
@export_range(0, 86400000) var passive_ms: int = 0
@export_range(0, 300000) var finish_ms: int = 0
@export var method: String = ""
@export_range(0, 100000) var practice_points: int = 0
@export var costs: Array[Cost] = []

func values() -> Dictionary:
	var payments: Array = []
	for cost: Cost in costs: payments.append(cost.values())
	return {"id": id, "title": title, "facility_capability": facility_capability, "purpose": purpose,
		"inputs": inputs.duplicate(), "outputs": outputs.duplicate(), "work_ms": work_ms, "passive_ms": passive_ms,
		"finish_ms": finish_ms, "method": method, "practice_points": practice_points, "costs": payments}

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if not id.is_valid_identifier() or title.is_empty() or not facility_capability.is_valid_identifier(): result.append("recipe identity/capability: invalid")
	if purpose not in ["cook", "produce"]: result.append("recipe purpose: unsupported material processing grant")
	for contents: Dictionary in [inputs, outputs]:
		if contents.is_empty() or contents.size() > 16: result.append("recipe items: require 1..16")
		for item: String in contents:
			if not Items.valid(item) or contents[item] <= 0 or contents[item] > 10000: result.append("recipe item: invalid")
	if work_ms < 1 or work_ms > 300000 or passive_ms < 0 or passive_ms > 86400000 or finish_ms < 0 or finish_ms > 300000 or ((passive_ms > 0) != (finish_ms > 0)): result.append("recipe timing: invalid")
	if (not method.is_empty() and not GrowthDefs.METHODS.has(method)) or practice_points < 0 or practice_points > 100000 or (practice_points > 0 and method.is_empty()): result.append("recipe learning: invalid")
	if costs.size() > 8: result.append("recipe costs: at most 8")
	for cost: Cost in costs:
		if cost == null: result.append("recipe cost: required"); continue
		result.append_array(cost.errors())
		if cost.kind == "item": result.append("recipe item payments belong in physical inputs")
	return result
