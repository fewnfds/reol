extends RefCounted
## Read-only program definitions; mutable unit state belongs to Decisions.
const Library = preload("res://data/definitions/decisions/library.tres")
const Actions = preload("res://scripts/sim/kernel/action_defs.gd")
const EVALUATORS: Dictionary = {"rules": preload("res://scripts/sim/kernel/decision_rules.gd"), "range_score": preload("res://scripts/sim/kernel/decision_scripts/range_score.gd")}
static var _compiled: Dictionary = Library.compile()
static var ERRORS: PackedStringArray = _compiled.errors
static var POLICIES: Dictionary = Actions._freeze(_compiled.policies)
static var SIGNATURE: String = JSON.stringify({"version": 8, "policies": POLICIES, "scripts": {"range_score": EVALUATORS.range_score.LOGIC_VERSION}}, "", true).sha256_text()

static func parameters_valid(params: Dictionary) -> bool:
	for key: Variant in params:
		if key not in ["flee_health", "min", "max", "reaction_ms", "think_ms"]: return false
		var value: Variant = params[key]
		if not (value is int or value is float) or not is_finite(float(value)): return false
		if key == "flee_health" and (value < 0 or value > 1): return false
		if key in ["min", "max"] and (value < 0 or value > 20): return false
		if key == "reaction_ms" and (not value is int or value < 0 or value > 2000): return false
		if key == "think_ms" and (not value is int or value < 50 or value > 1000 or value % 50 != 0): return false
	return true
