class_name SnapshotValues
extends RefCounted
## Stateless JSON boundary helpers. No scene, runtime, or domain ownership.


static func finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


static func valid_integer(value: Variant, minimum: int) -> bool:
	return finite_number(value) and float(value) == floorf(float(value)) and float(value) >= minimum


static func number_pair(value: Variant, integers_only: bool = false) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for component: Variant in value:
		if not finite_number(component):
			return false
		if integers_only and float(component) != floorf(float(component)):
			return false
	return true


static func canonical_json(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


static func normalized(value: Variant) -> Variant:
	# JSON has one numeric representation. Compare integral floats and integers
	# through the existing full-precision JSON representation, without rounding
	# fractional positions or changing the stored snapshot's numeric values.
	return JSON.parse_string(canonical_json(value))


static func for_save(value: Variant) -> Variant:
	# Dictionary dot syntax can add StringName keys. Convert those at the save
	# boundary; leave unsupported values intact so SimSaveStore still rejects them.
	if value is StringName:
		return String(value)
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(for_save(item))
		return items
	if value is Dictionary:
		var record: Dictionary = {}
		for key: Variant in value:
			var json_key: Variant = String(key) if key is StringName else key
			record[json_key] = for_save(value[key])
		return record
	return value
