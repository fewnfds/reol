extends RefCounted
## Authoring sources compiled once; no runtime reflection or script registry.
const LIBRARY = preload("res://data/definitions/operations/library.tres")
static var _compiled: Dictionary = LIBRARY.compile()
static var ERRORS: PackedStringArray = _compiled.errors
static var OPERATIONS: Dictionary = freeze(_compiled.operations)
static var TARGET_INDEX: Dictionary = _target_index()
static var SIGNATURE: String = signature(OPERATIONS)

static func _target_index() -> Dictionary:
	var result: Dictionary = {}
	for id: String in OPERATIONS:
		for rule: Dictionary in OPERATIONS[id].targets:
			for kind: String in rule.kinds if not rule.kinds.is_empty() else ["*"]:
				if not result.has(kind): result[kind] = []
				if not result[kind].has(id): result[kind].append(id)
	return freeze(result)

static func freeze(value: Variant) -> Variant:
	if value is Dictionary:
		for child: Variant in value.values(): freeze(child)
		value.make_read_only()
	elif value is Array:
		for child: Variant in value: freeze(child)
		value.make_read_only()
	return value

static func signature(operations: Dictionary) -> String:
	var rules: Dictionary = operations.duplicate(true)
	for operation: Dictionary in rules.values():
		for key: String in ["title", "icon", "target_menu", "command_alias"]: operation.erase(key)
		if not operation.recipe.is_empty(): operation.recipe.erase("title")
	return JSON.stringify({"version": 1, "operations": rules}, "", true).sha256_text()

static func capability_reason(record: Dictionary, operation: String) -> String:
	if not OPERATIONS.has(operation): return "unknown_operation"
	for capability: String in OPERATIONS[operation].required_capabilities:
		if not preload("res://scripts/sim/kernel/being_defs.gd").has(record, capability): return "body_has_no_%s_capability" % capability
	return ""

static func domain_action(action: Dictionary) -> Dictionary:
	var result: Dictionary = action.duplicate()
	result["operation_id"] = action.kind
	result.kind = OPERATIONS[action.kind].handler
	return result
