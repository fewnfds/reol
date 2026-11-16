@tool
class_name LifeGoalLibrary
extends Resource
const Goal = preload("res://scripts/sim/definitions/agency/goal_def.gd")
const Approach = preload("res://scripts/sim/definitions/agency/approach_def.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
@export var goals: Array[Goal] = []
@export var approaches: Array[Approach] = []

func compile() -> Dictionary:
	var result: Dictionary = {"goals": {}, "approaches": {}, "errors": PackedStringArray()}
	for approach: Approach in approaches:
		if approach == null:
			result.errors.append("null approach"); continue
		result.errors.append_array(approach.errors())
		if approach.pattern == "perform" and not approach.handler.is_empty():
			var supported: bool = false
			for operation: Dictionary in Operations.OPERATIONS.values():
				if operation.handler == approach.handler: supported = true; break
			if not supported: result.errors.append("unknown operation handler: " + approach.handler)
		if result.approaches.has(approach.id): result.errors.append("duplicate approach: " + approach.id)
		else: result.approaches[approach.id] = approach.values()
	for goal: Goal in goals:
		if goal == null:
			result.errors.append("null goal"); continue
		result.errors.append_array(goal.errors())
		if result.goals.has(goal.id): result.errors.append("duplicate goal: " + goal.id)
		else: result.goals[goal.id] = goal.values()
		for approach: String in goal.approaches:
			if not result.approaches.has(approach): result.errors.append("unknown approach: " + approach)
			elif result.approaches[approach].pattern not in {"resource": ["perform", "produce"], "recovery": ["perform"], "development": ["develop"], "delivery": ["deliver"], "operation": ["perform"], "custody": ["return"]}.get(goal.driver, []): result.errors.append("goal/approach mechanism mismatch: " + goal.id + "/" + approach)
	return result
