extends RefCounted
## Explicit domain state fields, deep detached at a joined owner boundary.
## This is not object reflection and never encodes scripts, Nodes or resources.


static func copy(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = copy(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry: Variant in value:
			result.append(copy(entry))
		return result
	if typeof(value) >= TYPE_PACKED_BYTE_ARRAY and typeof(value) <= TYPE_PACKED_VECTOR4_ARRAY:
		return value.duplicate()
	return value


static func capture(owner: RefCounted, fields: Array) -> Dictionary:
	var result: Dictionary = {}
	for field: String in fields:
		result[field] = copy(owner.get(field))
	return result


static func matches(owner: RefCounted, fields: Array, data: Dictionary) -> bool:
	for field: String in fields:
		if not data.has(field) or typeof(data[field]) != typeof(owner.get(field)):
			return false
	return true


static func apply(owner: RefCounted, fields: Array, data: Dictionary) -> void:
	for field: String in fields:
		var current: Variant = owner.get(field)
		if current is Array:
			current.assign(copy(data[field]))
		else:
			owner.set(field, copy(data[field]))
