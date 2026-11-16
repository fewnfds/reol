extends RefCounted
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const LIBRARY = preload("res://data/definitions/agency/library.tres")
const DISPOSITIONS: Array[String] = ["curiosity", "dutifulness", "sociability", "persistence"]
static var _compiled: Dictionary = LIBRARY.compile()
static var ERRORS: PackedStringArray = _compiled.errors
static var GOALS: Dictionary = Operations.freeze(_compiled.goals)
static var APPROACHES: Dictionary = Operations.freeze(_compiled.approaches)
static var SIGNATURE: String = signature(GOALS, APPROACHES)

static func crossed_need(metric: String, before: int, after: int) -> bool:
	# Owner-side life choices need a wake when a quiet/sleeping person's needs
	# become relevant or urgent; do not poll their whole purpose set every tick.
	if before >= 4000 and after < 4000: return true # Existing body-event contract.
	for goal: Dictionary in GOALS.values():
		if goal.driver == "resource" and goal.metric == metric:
			for threshold: int in [int(goal.comfort), int(goal.emergency) + 1]:
				if before >= threshold and after < threshold: return true
	return false

static func signature(goals: Dictionary, approaches: Dictionary) -> String:
	var values: Dictionary = {"goals": goals.duplicate(true), "approaches": approaches.duplicate(true)}
	for category: Dictionary in values.values():
		for value: Dictionary in category.values(): value.erase("title")
	return JSON.stringify({"version": 1, "rules": values}, "", true).sha256_text()
