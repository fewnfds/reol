extends RefCounted
## Shared immutable plant content; independent of Operations to avoid a cycle.
const Items = preload("res://scripts/sim/kernel/items.gd")
static var DEFINITIONS: Dictionary = _freeze(JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/plants.json")).types)
static var ERRORS: PackedStringArray = _errors(DEFINITIONS)
static var SIGNATURE: String = JSON.stringify(DEFINITIONS, "", true).sha256_text()

static func _freeze(value: Variant) -> Variant:
	if value is Dictionary:
		for child: Variant in value.values(): _freeze(child)
		value.make_read_only()
	elif value is Array:
		for child: Variant in value: _freeze(child)
		value.make_read_only()
	return value

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= low and value <= high

static func _errors(definitions: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	for id: String in definitions:
		var plant: Dictionary = definitions[id]
		if not id.is_valid_identifier() or plant.get("life") not in ["annual", "perennial"] or not plant.get("sapient") is bool or not plant.get("blocks") is bool or not plant.get("regrow") is bool: result.append(id + ": invalid identity/life")
		if plant.has("stored_qi"):
			var source: Variant = plant.stored_qi
			if not source is Dictionary or source.size() != 2 or not _integer(source.get("capacity"), 1, 3000) or not _integer(source.get("regen_per_second"), 0, 1000): result.append(id + ": invalid stored qi source")
		for field: String in ["mature_ms", "lifespan_ms", "injury_ms", "max_hp"]:
			if not _integer(plant.get(field), 1, 999999999999): result.append(id + ": invalid " + field)
		if not plant.get("substrates") is Array or plant.substrates.is_empty(): result.append(id + ": missing substrates")
		else:
			for substrate: String in plant.substrates:
				if substrate not in ["soil", "sand", "water"]: result.append(id + ": invalid substrate")
		if not plant.get("seasons") is Array or plant.seasons.is_empty(): result.append(id + ": missing seasons")
		else:
			for season: String in plant.seasons:
				if season not in ["春", "夏", "秋", "冬"]: result.append(id + ": invalid season")
		if not plant.get("temperature") is Array or plant.temperature.size() != 4: result.append(id + ": invalid temperatures")
		else:
			for number: Variant in plant.temperature:
				if not _integer(number, -1000, 2000): result.append(id + ": invalid temperature")
			if plant.temperature[2] > plant.temperature[0] or plant.temperature[0] > plant.temperature[1] or plant.temperature[1] > plant.temperature[3]: result.append(id + ": inconsistent temperatures")
		if not _integer(plant.get("water_min"), 0, 100) or not _integer(plant.get("water_max"), 0, 100) or plant.water_min > plant.water_max or not _integer(plant.get("light_min"), 0, 1000): result.append(id + ": invalid water/light")
		for field: String in ["product", "body_product"]:
			var product: Dictionary = plant.get(field, {})
			if not Items.valid(str(product.get("item", ""))): result.append(id + ": invalid product")
			for key: String in (["capacity", "period_ms"] if field == "product" else ["amount"]):
				if not _integer(product.get(key), 1, 999999999999): result.append(id + ": invalid " + key)
	return result
