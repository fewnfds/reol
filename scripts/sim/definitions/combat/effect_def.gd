@tool
class_name CombatEffectDef
extends Resource
## A reusable hit payload. Mutable lifetime belongs to Effects, never this resource.
@export_enum("damage", "control", "slow", "dot") var kind: String = "damage"
@export var status_id: String = ""
@export_range(0.0, 20.0, 0.05) var magnitude: float = 1.0
@export_range(0, 60000) var duration_ms: int = 0
@export_range(0, 10000) var period_ms: int = 0
@export_range(0.0, 1.0, 0.01) var push: float = 0.0
@export_range(0, 1000) var punish_ms: int = 0

func values() -> Dictionary:
	return {"kind": kind, "id": status_id, "magnitude": magnitude, "duration_ms": duration_ms,
		"period_ms": period_ms, "push": push, "punish_ms": punish_ms}

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if kind not in ["damage", "control", "slow", "dot"]: result.append("kind: unknown effect")
	if not is_finite(magnitude) or magnitude < 0.0 or magnitude > 20.0: result.append("magnitude: must be finite, 0..20")
	if duration_ms < 0 or duration_ms > 60000 or period_ms < 0 or period_ms > 10000: result.append("duration/period: out of range")
	if not is_finite(push) or push < 0 or push > 1 or punish_ms < 0 or punish_ms > 1000: result.append("control: invalid push/punish")
	if kind in ["slow", "dot"] and (status_id.is_empty() or duration_ms <= 0): result.append("status: id and duration required")
	if kind == "slow" and (magnitude <= 0 or magnitude > 1): result.append("slow: multiplier must be (0,1]")
	if kind == "dot" and (period_ms < 50 or period_ms > duration_ms): result.append("dot: period must be 50..duration")
	return result
