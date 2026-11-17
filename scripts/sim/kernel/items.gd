extends RefCounted
## Canonical stack keys. Only gear has quality variants in the current demo.
## No individual identity until an item has individual mutable state.
const SLOTS: Dictionary = {"weapon": "武器", "body": "衣甲", "feet": "鞋履", "charm": "饰物"}
static var definitions: Dictionary = _definitions()

static func _definitions() -> Dictionary:
	# Loaded before any detached planner starts; no lazy shared write in workers.
	var values: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/items.json"))
	_freeze(values)
	return values

static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for child: Variant in value.values(): _freeze(child)
		value.make_read_only()
	elif value is Array:
		for child: Variant in value: _freeze(child)
		value.make_read_only()

static func load_definitions() -> Dictionary:
	return definitions

static func definition(key: String) -> String:
	return key.get_slice("@", 0)

static func quality(key: String) -> int:
	return int(key.get_slice("@", 1)) if key.contains("@") else 1

static func key_for(id: String, grade: int = 1) -> String:
	return id if grade == 1 else "%s@%d" % [id, grade]

static func valid(key: String) -> bool:
	var id: String = definition(key)
	var grade: int = quality(key)
	var spec: Dictionary = load_definitions().get(id, {})
	return not spec.is_empty() and grade >= 1 and grade <= 3 and key == key_for(id, grade) and (grade == 1 or spec.has("slot"))

static func spec(key: String) -> Dictionary:
	return load_definitions().get(definition(key), {})

static func bonuses(key: String) -> Dictionary:
	var result: Dictionary = {}
	for stat: String in spec(key).get("stats", {}):
		result[stat] = float(spec(key).stats[stat]) * (1.0 + (quality(key) - 1) * 0.25)
	return result

static func label(key: String) -> String:
	return str(spec(key).get("label", key))
