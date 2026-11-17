@tool
class_name LifeGoalDef
extends Resource
## Driver is a shared state/evaluation mechanism, never a character-specific plan.
@export var id: String = ""
@export var title: String = ""
@export_enum("resource", "recovery", "development", "delivery", "operation", "custody", "responsibility", "duty", "service", "reporting", "responses") var driver: String = "resource"
@export var approaches: PackedStringArray = []
@export var metric: String = ""
@export_range(1, 10000) var comfort: int = 7000
@export_range(0, 10000) var emergency: int = 1500
@export_range(0.5, 4.0) var exponent: float = 2.0
@export_range(0.05, 2.0) var weight: float = 1.0
@export var disposition: String = ""

func values() -> Dictionary:
	var result: Dictionary = {"id": id, "title": title, "driver": driver, "approaches": Array(approaches), "weight": weight, "disposition": disposition}
	if driver == "resource": result.merge({"metric": metric, "comfort": comfort, "emergency": emergency, "exponent": exponent})
	return result

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if not id.is_valid_identifier() or title.is_empty(): result.append("goal id/title: required")
	if driver not in ["resource", "recovery", "development", "delivery", "operation", "custody", "responsibility", "duty", "service", "reporting", "responses"]: result.append("goal driver: unsupported")
	if approaches.is_empty() or approaches.size() > 8: result.append("goal approaches: require 1..8")
	for approach: String in approaches:
		if not approach.is_valid_identifier() or approaches.count(approach) != 1: result.append("goal approach: invalid or repeated")
	if not is_finite(weight) or weight < 0.05 or weight > 2.0: result.append("goal weight: out of range")
	if disposition not in ["", "curiosity", "dutifulness"]: result.append("goal disposition: unsupported")
	if driver == "resource":
		if metric not in ["hunger", "energy"] or comfort <= 0 or comfort > 10000 or emergency < 0 or emergency >= comfort: result.append("resource goal: invalid need thresholds")
		if not is_finite(exponent) or exponent < 0.5 or exponent > 4.0: result.append("resource goal: invalid curve")
	elif not metric.is_empty(): result.append("metric: only used by resource driver")
	return result
