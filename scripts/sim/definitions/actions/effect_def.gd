@tool
class_name ActionEffectDef
extends Resource
const Status = preload("res://scripts/sim/definitions/actions/status_def.gd")
@export var status: Status
@export_range(0, 1000000) var amount: int = 0
@export var pool: String = "mana"
## A reusable hit payload. Mutable lifetime belongs to Effects, never this resource.
@export_enum("activation", "contact") var stage: String = "contact"
@export_enum("damage", "control", "slow", "dot", "domain", "status", "heal", "shield", "guard", "resource", "dispel") var kind: String = "damage"
@export_enum("tend") var operation: String = "tend"
@export var status_id: String = ""
@export_range(0.0, 20.0, 0.05) var magnitude: float = 1.0
@export_range(0, 60000) var duration_ms: int = 0
@export_range(0, 10000) var period_ms: int = 0
@export_range(0.0, 1.0, 0.01) var push: float = 0.0
@export_range(0, 1000) var punish_ms: int = 0

func values() -> Dictionary:
	return {"status": status.values() if status != null else {}, "amount": amount, "pool": pool, "operation": operation, "stage": stage, "kind": kind, "id": status_id, "magnitude": magnitude, "duration_ms": duration_ms,
		"period_ms": period_ms, "push": push, "punish_ms": punish_ms}

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if amount < 0 or amount > 1000000: result.append("amount: out of range")
	if kind == "status":
		if status == null: result.append("status: required")
		else:
			for error: String in status.errors(): result.append("status." + error)
	if kind in ["shield", "guard"] and duration_ms <= 0: result.append("duration_ms: defense needs positive duration")
	if kind == "guard" and (magnitude < 0 or magnitude > 1): result.append("magnitude: guard requires 0..1")
	if stage not in ["activation", "contact"]: result.append("stage: unknown execution scope")
	if kind == "domain" and operation != "tend": result.append("operation: unknown domain operation")
	if kind not in ["damage", "control", "slow", "dot", "domain", "status", "heal", "shield", "guard", "resource", "dispel"]: result.append("kind: unknown effect")
	if not is_finite(magnitude) or magnitude < 0.0 or magnitude > 20.0: result.append("magnitude: must be finite, 0..20")
	if duration_ms < 0 or duration_ms > 60000 or period_ms < 0 or period_ms > 10000: result.append("duration/period: out of range")
	if not is_finite(push) or push < 0 or push > 1 or punish_ms < 0 or punish_ms > 1000: result.append("control: invalid push/punish")
	if kind in ["slow", "dot"] and (not status_id.is_valid_identifier() or duration_ms <= 0): result.append("status: valid identifier and positive duration required")
	if kind == "slow" and (magnitude <= 0 or magnitude > 1): result.append("slow: multiplier must be (0,1]")
	if kind == "dot" and (period_ms < 50 or period_ms > duration_ms): result.append("dot: period must be 50..duration")
	return result
