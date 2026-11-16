extends RefCounted
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const LIBRARY = preload("res://data/definitions/institutions/library.tres")
static var _compiled: Dictionary = LIBRARY.compile()
static var ERRORS: PackedStringArray = _compiled.errors
static var ROLES: Dictionary = Operations.freeze(_compiled.roles)
static var SIGNATURE: String = signature(ROLES)

static func signature(roles: Dictionary) -> String:
	var values: Dictionary = roles.duplicate(true)
	for value: Dictionary in values.values(): value.erase("title")
	return JSON.stringify({"version": 1, "roles": values}, "", true).sha256_text()
