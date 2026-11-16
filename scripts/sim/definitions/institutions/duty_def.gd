@tool
class_name InstitutionDutyDef
extends Resource
## One recurring policy, with actual places supplied by an appointment.
const Items = preload("res://scripts/sim/kernel/items.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
@export_enum("delivery", "produce") var kind: String = "delivery"
@export var item: String = "meal"
@export var operation: String = ""
@export_range(0, 100000) var low: int = 3
@export_range(1, 100000) var desired: int = 6
@export_range(1, 100000) var quota: int = 3
@export_range(5000, 3600000) var review_ms: int = 15000
@export_range(10000, 86400000) var deadline_ms: int = 120000

func values() -> Dictionary:
	return {"kind": kind, "item": item, "operation": operation, "low": low, "desired": desired, "quota": quota, "review_ms": review_ms, "deadline_ms": deadline_ms}

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if kind not in ["delivery", "produce"] or not Items.valid(item): result.append("duty kind/item invalid")
	if low < 0 or desired <= low or desired > 100000 or quota < 1 or quota > desired: result.append("duty stock band/quota invalid")
	if review_ms < 5000 or review_ms > 3600000 or deadline_ms < 10000 or deadline_ms > 86400000: result.append("duty timing invalid")
	if kind == "delivery" and not operation.is_empty(): result.append("delivery duty has no production operation")
	if kind == "produce" and not Operations.OPERATIONS.get(operation, {}).get("recipe", {}).get("outputs", {}).has(item): result.append("production duty requires a matching recipe output")
	return result
