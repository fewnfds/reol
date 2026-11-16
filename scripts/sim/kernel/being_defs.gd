extends RefCounted
## Shape and individual source differences, never a second mutable ability ledger.
const Form = preload("res://scripts/sim/definitions/beings/form_def.gd")
const Library = preload("res://data/definitions/beings/library.tres")
static var _compiled: Dictionary = Library.compile()
static var ERRORS: PackedStringArray = _compiled.errors
static var FORMS: Dictionary = _freeze(_compiled.forms)
static var SIGNATURE: String = signature(FORMS)

static func _freeze(value: Dictionary) -> Dictionary:
	for child: Variant in value.values():
		if child is Dictionary: _freeze(child)
	value.make_read_only()
	return value

static func signature(forms: Dictionary) -> String:
	var rules: Dictionary = forms.duplicate(true)
	for form: Dictionary in rules.values(): form.erase("title")
	return JSON.stringify({"version": 1, "forms": rules}, "", true).sha256_text()

static func has(record: Dictionary, capability: String) -> bool:
	if not Form.CAPABILITIES.has(capability): return false
	var form: Dictionary = FORMS.get(record.get("body_profile", ""), {})
	if form.is_empty(): return false
	return record.get("capability_overrides", {}).get(capability, form.capabilities[capability])

static func capabilities(record: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in Form.CAPABILITIES: result[key] = has(record, key)
	return result

static func valid_record(record: Dictionary) -> bool:
	if not ERRORS.is_empty() or not record.get("body_profile") is String or not FORMS.has(record.body_profile): return false
	if record.get("definition") != record.body_profile: return false
	if record.get("body_origin") not in ["independent", "summoned"]: return false
	for derived: String in ["capabilities", "body_capabilities", "needs_enabled", "environment_enabled", "can_work"]:
		if record.has(derived): return false # Effective values are derived, not save state.
	var changes: Variant = record.get("capability_overrides", {})
	if not changes is Dictionary: return false
	for key: Variant in changes:
		if not key is String or not Form.CAPABILITIES.has(key) or not changes[key] is bool: return false
	return true

static func population_member(record: Dictionary) -> bool:
	# This statistic counts persistent bodies, not sect membership or metabolism.
	return record.get("body_origin") == "independent"

