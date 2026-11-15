@tool
class_name UnitDecisionRule
extends Resource
## Ordered local rule. Readiness is checked in addition to this condition.
@export_enum("always", "near", "far", "hurt", "recent_hit") var condition: String = "always"
@export_range(0.0, 30.0) var threshold: float = 0.0
@export_enum("cast", "approach", "keep_range", "sequence", "wait") var action: String = "cast"
@export_enum("primary", "skill", "skill2", "skill3", "step") var button: String = "primary"
@export_range(0.0, 30.0) var min_distance: float = 0.0
@export_range(0.0, 30.0) var max_distance: float = 0.0 # 0 uses the loadout's effective range.
@export var sequence: PackedStringArray = PackedStringArray()
@export_range(0, 10000) var interval_ms: int = 0
@export_range(0.0, 10.0) var weight: float = 1.0

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if condition not in ["always", "near", "far", "hurt", "recent_hit"]: result.append("condition: unknown")
	if action not in ["cast", "approach", "keep_range", "sequence", "wait"]: result.append("action: unknown")
	if button not in ["primary", "skill", "skill2", "skill3", "step"]: result.append("button: unknown")
	for value: float in [threshold, min_distance, max_distance]:
		if not is_finite(value) or value < 0 or value > 30: result.append("distance/threshold: must be finite 0..30")
	if max_distance > 0 and min_distance > max_distance: result.append("distance: invalid band")
	if interval_ms < 0 or interval_ms > 10000: result.append("interval_ms: must be 0..10000")
	if not is_finite(weight) or weight < 0 or weight > 10: result.append("weight: must be finite 0..10")
	if sequence.size() > 8 or (action == "sequence" and sequence.is_empty()): result.append("sequence: requires 1..8 steps")
	for slot: String in sequence:
		if slot not in ["primary", "skill", "skill2", "skill3", "step"]: result.append("sequence: unknown button")
	return result

func values() -> Dictionary:
	return {"condition": condition, "threshold": threshold, "action": action, "button": button, "min": min_distance, "max": max_distance, "sequence": Array(sequence), "interval": interval_ms, "weight": weight}
