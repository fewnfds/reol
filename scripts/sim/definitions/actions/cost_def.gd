@tool
class_name ActionCostDef
extends Resource
@export_enum("item", "pool", "health", "energy", "qi") var kind: String = "pool"
@export var id: String = "mana"
@export_range(1, 100000) var amount: int = 10
func values() -> Dictionary:
	return {"kind": kind, "id": id, "amount": amount}
func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if kind not in ["item", "pool", "health", "energy", "qi"] or amount < 1 or amount > 100000: result.append("kind/amount: invalid cost")
	if kind in ["item", "pool"] and id.is_empty(): result.append("id: required")
	return result
