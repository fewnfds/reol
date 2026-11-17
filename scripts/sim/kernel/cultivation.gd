extends RefCounted
## Container cultivation, not terrain hydrology. State stays on the real host.

static func spec(definition: Dictionary) -> Dictionary:
	return definition.get("capabilities", {}).get("cultivation", {})

static func ignores(record: Dictionary) -> bool:
	return record.kind == "pile" or record.get("layer", "ground") == "roof" or (record.get("layer", "ground") == "floor" and record.kind != "blueprint")

static func errors(definition: Dictionary) -> PackedStringArray:
	var value: Dictionary = spec(definition)
	var result := PackedStringArray()
	if value.is_empty(): return result
	if value.get("substrate") not in ["soil", "sand", "water"] or value.get("root_capacity") != 1: result.append("cultivation: unsupported substrate/root capacity")
	for key: String in ["water_capacity", "initial_water", "water_decay_ms", "water_per_item"]:
		var number: Variant = value.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or float(number) != floorf(float(number)) or number < 0 or number > 86400000: result.append("cultivation: invalid " + key)
	if result.is_empty() and (value.water_capacity != 100 or value.initial_water > value.water_capacity or value.water_decay_ms < 1000 or value.water_per_item <= 0 or value.water_per_item > value.water_capacity): result.append("cultivation: inconsistent water scale")
	return result

static func install(record: Dictionary, definition: Dictionary) -> void:
	var value: Dictionary = spec(definition)
	if value.is_empty() or record.has("water"): return
	record["water"] = int(value.initial_water)
	record["water_ms"] = 0
	record["guest"] = 0

static func advance(host: Dictionary, definition: Dictionary, delta_ms: int) -> void:
	if host.water <= 0:
		host.water_ms = 0
		return
	var period: int = int(spec(definition).water_decay_ms)
	var used: int = int(host.water_ms) + delta_ms
	host.water = maxi(0, int(host.water) - used / period)
	host.water_ms = used % period if host.water > 0 else 0

static func limit(definition: Dictionary, plant: Dictionary) -> int:
	return mini(int(spec(definition).water_capacity), int(plant.water_max))

static func water_band(amount: int, capacity: int) -> int:
	if amount <= 0: return 0
	if amount > capacity: return 4
	if amount < mini(40, capacity): return 1
	return 2 if amount < capacity else 3

static func care_reason(target: Dictionary) -> String:
	if not target.has("injured") or not target.has("water_band"): return "unknown_target_state"
	if int(target.water_band) == 4: return "water_excess"
	return "" if target.injured or (int(target.water_band) >= 0 and int(target.water_band) < 3) else "not_needed"

static func title_reason(actor: int, host: Dictionary, organization: int) -> String:
	return "incompatible_cultivation_title" if int(host.get("organization", 0)) != organization or (int(host.get("owner", 0)) > 0 and int(host.owner) != actor) else ""

static func valid(record: Dictionary, definition: Dictionary) -> bool:
	var value: Dictionary = spec(definition)
	if value.is_empty() or record.kind == "blueprint":
		return not record.has("water") and not record.has("water_ms") and not record.has("guest")
	return errors(definition).is_empty() and record.get("water") is int and record.water >= 0 and record.water <= value.water_capacity and record.get("water_ms") is int and record.water_ms >= 0 and record.water_ms < value.water_decay_ms and (record.water > 0 or record.water_ms == 0) and record.get("guest") is int and record.guest >= 0
