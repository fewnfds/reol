extends RefCounted
## Immutable authoring values. Runtime records never retain Resource instances.
const Library = preload("res://data/definitions/growth/library.tres")
static var _compiled: Dictionary = Library.compile()
static var ERRORS: PackedStringArray = _compiled.errors
static var METHODS: Dictionary = _freeze(_compiled.methods)
static var CONDITIONS: Dictionary = _freeze(_compiled.conditions)
static var SIGNATURE: String = signature(METHODS, CONDITIONS)

static func _freeze(value: Variant) -> Variant:
	if value is Dictionary:
		for child: Variant in value.values(): _freeze(child)
		value.make_read_only()
	elif value is Array:
		for child: Variant in value: _freeze(child)
		value.make_read_only()
	return value

static func signature(methods: Dictionary, conditions: Dictionary) -> String:
	var rules: Dictionary = {"methods": methods.duplicate(true), "conditions": conditions.duplicate(true)}
	for category: Dictionary in rules.values():
		for entry: Dictionary in category.values(): entry.erase("title")
	return JSON.stringify({"version": 1, "rules": rules}, "", true).sha256_text()
