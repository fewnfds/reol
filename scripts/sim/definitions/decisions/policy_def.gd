@tool
class_name UnitDecisionPolicy
extends Resource
const Rule = preload("res://scripts/sim/definitions/decisions/rule_def.gd")
@export var id: String = ""
@export var title: String = ""
@export_enum("rules", "range_score") var evaluator: String = "rules"
@export_enum("fight", "flee", "ignore") var threat_response: String = "fight"
@export_range(0.0, 1.0) var flee_health: float = 0.0
@export_range(0.0, 20.0) var preferred_min: float = 0.0
@export_range(0.0, 20.0) var preferred_max: float = 0.0
@export_range(0, 2000) var reaction_ms: int = 220
@export_range(50, 1000, 50) var think_ms: int = 50
@export var rules: Array[Rule] = []

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if not id.is_valid_identifier() or title.is_empty(): result.append("id/title: required")
	if evaluator not in ["rules", "range_score"]: result.append("evaluator: not registered")
	if threat_response not in ["fight", "flee", "ignore"]: result.append("threat_response: unknown")
	if not is_finite(flee_health) or flee_health < 0 or flee_health > 1: result.append("flee_health: must be 0..1")
	if not is_finite(preferred_min) or not is_finite(preferred_max) or preferred_min < 0 or preferred_max < preferred_min or preferred_max > 20: result.append("preferred distance: invalid band")
	if reaction_ms < 0 or reaction_ms > 2000 or think_ms < 50 or think_ms > 1000 or think_ms % 50 != 0: result.append("cadence: invalid")
	if rules.size() > 24: result.append("rules: at most 24")
	for rule: Rule in rules:
		if rule == null: result.append("rules: required resource"); continue
		result.append_array(rule.errors())
	return result

func values() -> Dictionary:
	var rows: Array = []
	for rule: Rule in rules: rows.append(rule.values())
	return {"id": id, "title": title, "evaluator": evaluator, "response": threat_response, "flee_health": flee_health, "min": preferred_min, "max": preferred_max, "reaction_ms": reaction_ms, "think_ms": think_ms, "rules": rows}
