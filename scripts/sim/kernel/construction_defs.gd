extends RefCounted
## Compile authoring objects and material choices into the existing facility IDs.
const Defs = preload("res://scripts/sim/kernel/operation_defs.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Positions = preload("res://scripts/sim/kernel/work_positions.gd")
const Sources = preload("res://scripts/sim/kernel/stock_sources.gd")
const Cultivation = preload("res://scripts/sim/kernel/cultivation.gd")

static var _compiled: Dictionary = compile(JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/construction.json")))
static var ERRORS: PackedStringArray = _compiled.errors
static var DEFINITIONS: Dictionary = Defs.freeze(_compiled.definitions)
static var MENU: Dictionary = Defs.freeze(_compiled.menu)

static func compile(data: Variant) -> Dictionary:
	var errors := PackedStringArray()
	var definitions: Dictionary = {}
	var menu: Dictionary = {}
	if not data is Dictionary or not data.get("materials") is Dictionary or not data.get("objects") is Dictionary:
		return {"errors": PackedStringArray(["construction: materials and objects are required"]), "definitions": {}, "menu": {}}
	var materials: Dictionary = {}
	for key: String in data.materials:
		var label: Variant = data.materials[key]
		if not key.is_valid_identifier() or not Items.valid(key) or not _has_text(label) or label in materials.values():
			errors.append("construction: invalid material " + key)
		else:
			materials[key] = label
	for key: String in data.objects:
		var object: Variant = data.objects[key]
		if (
			not key.is_valid_identifier()
			or not object is Dictionary
			or not _has_text(object.get("category"))
			or not _has_text(object.get("subcategory"))
			or not _has_text(object.get("label"))
			or not object.get("properties") is Dictionary
			or not object.get("variants") is Dictionary
			or object.variants.is_empty()
		):
			errors.append("construction: invalid object " + key)
			continue
		if not menu.has(object.category): menu[object.category] = {}
		var groups: Dictionary = menu[object.category]
		if not groups.has(object.subcategory): groups[object.subcategory] = {}
		var objects: Dictionary = groups[object.subcategory]
		if objects.has(object.label):
			errors.append("construction: duplicate menu label for " + key)
			continue
		var choices: Dictionary = {}
		objects[object.label] = choices
		for material: String in object.variants:
			var variant: Variant = object.variants[material]
			if (
				not materials.has(material)
				or not variant is Dictionary
				or not variant.get("id") is String
				or not variant.id.is_valid_identifier()
				or definitions.has(variant.id)
				or not _has_text(variant.get("label"))
				or not _positive_integer(variant.get("amount"))
				or not variant.get("overrides", {}) is Dictionary
			):
				errors.append("construction: invalid variant %s/%s" % [key, material])
				continue
			# An override replaces one whole property, including nested dictionaries.
			var spec: Dictionary = object.properties.duplicate(true)
			spec.merge(variant.get("overrides", {}).duplicate(true), true)
			spec.merge({"label": variant.label, "item": material, "amount": variant.amount}, true)
			var issues: PackedStringArray = _spec_errors(spec)
			if not issues.is_empty():
				errors.append("construction: %s: %s" % [variant.id, ", ".join(issues)])
				continue
			definitions[variant.id] = spec
			choices[materials[material]] = variant.id
	if data.objects.is_empty(): errors.append("construction: no buildable objects")
	if not errors.is_empty():
		return {"errors": errors, "definitions": {}, "menu": {}}
	return {"errors": errors, "definitions": definitions, "menu": menu}

static func _has_text(value: Variant) -> bool:
	return value is String and not value.is_empty() and value == value.strip_edges()

static func _positive_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value > 0 and value <= 2147483647 and value == int(value)

static func _spec_errors(spec: Dictionary) -> PackedStringArray:
	var size: Variant = spec.get("size")
	if not size is Array or size.size() != 2 or not _positive_integer(size[0]) or not _positive_integer(size[1]):
		return PackedStringArray(["invalid footprint"])
	if not _has_text(spec.get("kind")) or not _has_text(spec.get("layer")) or not _positive_integer(spec.get("max_hp")) or not _positive_integer(spec.get("work_ms")):
		return PackedStringArray(["invalid kind, layer, durability or work time"])
	for key: String in ["facts", "capabilities", "environment"]:
		if not spec.get(key, {} if key == "environment" else null) is Dictionary:
			return PackedStringArray(["invalid " + key])
	for value: Variant in spec.capabilities.values():
		if not value is Dictionary: return PackedStringArray(["invalid capability"])
	var errors: PackedStringArray = Positions.errors(spec.get("work_positions", {}))
	errors.append_array(Sources.errors(spec))
	errors.append_array(Cultivation.errors(spec))
	return errors
