@tool
class_name CombatDeliveryDef
extends Resource
## How an action reaches the world; different skills reuse the same delivery.
@export_enum("melee", "projectile", "area", "evade", "implement", "recall", "direct") var kind: String = "melee"
@export_group("Shape and Target")
@export_range(0.0, 20.0) var reach: float = 1.55
@export_range(0.01, 3.141593) var half_angle: float = 1.0
@export_range(0.02, 5.0) var radius: float = 0.1
@export_enum("direction", "point", "self", "object") var target: String = "direction"
@export_range(0.0, 30.0) var max_range: float = 8.0
@export var blocked_by_walls: bool = true
@export_enum("physical", "hostile", "self") var target_filter: String = "physical"
@export_group("Emission and Motion")
@export_range(1, 64) var count: int = 1
@export_range(0.0, 6.283185, 0.01) var spread: float = 0.16
@export_range(0.1, 60.0) var speed: float = 22.0
@export_range(0.1, 60.0) var backward_speed: float = 10.0
@export_range(50, 15000) var lifetime_ms: int = 2000
@export_range(0.0, 12.0) var turn_rate: float = 0.0
@export_range(0, 8) var pierce: int = 0
@export_group("Area / Implement")
@export_range(0, 5000) var delay_ms: int = 450
@export_range(0, 10000) var duration_ms: int = 0
@export_range(50, 5000) var period_ms: int = 500
@export_range(1, 1000) var durability: int = 60
@export_range(100, 3000) var contact_ms: int = 350

func values() -> Dictionary:
	return {"kind": kind, "reach": reach, "angle": half_angle, "radius": radius, "target": target,
		"range": max_range, "walls": blocked_by_walls, "filter": target_filter, "count": count, "spread": spread,
		"speed": speed, "backward_speed": backward_speed, "life": lifetime_ms, "turn": turn_rate, "pierce": pierce, "delay": delay_ms,
		"duration": duration_ms, "period": period_ms, "durability": durability, "contact_ms": contact_ms}

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if kind not in ["melee", "projectile", "area", "evade", "implement", "recall", "direct"]: result.append("kind: unknown delivery")
	if target not in ["direction", "point", "self", "object"] or target_filter not in ["physical", "hostile", "self"]: result.append("target/filter: unknown policy")
	for field: String in ["reach", "half_angle", "radius", "max_range", "spread", "speed", "backward_speed", "turn_rate"]:
		if not is_finite(get(field)) or float(get(field)) < 0: result.append(field + ": must be finite and nonnegative")
	if reach > 20 or half_angle <= 0 or half_angle > PI or radius < 0.02 or radius > 5 or max_range > 30 or speed <= 0 or speed > 60 or spread > TAU or turn_rate > 12: result.append("geometry/motion: out of range")
	if count < 1 or count > 64 or lifetime_ms < 50 or lifetime_ms > 15000 or pierce < 0 or pierce > 8: result.append("emission: out of range")
	if delay_ms < 0 or delay_ms > 5000 or duration_ms < 0 or duration_ms > 10000 or period_ms < 50 or period_ms > 5000: result.append("area timing: out of range")
	if durability < 1 or durability > 1000 or contact_ms < 100 or contact_ms > 3000: result.append("implement: invalid durability/contact period")
	if kind == "melee" and reach <= 0: result.append("reach: melee requires positive reach")
	if backward_speed <= 0 or backward_speed > 60: result.append("backward_speed: out of range")
	if kind == "area" and delay_ms < 1: result.append("delay_ms: area requires at least one world millisecond")
	if kind in ["melee", "projectile", "implement"] and (target != "direction" or target_filter == "self"): result.append("target/filter: this delivery requires direction and non-self targets")
	return result
