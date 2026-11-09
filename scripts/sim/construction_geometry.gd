class_name SimConstructionGeometry
extends RefCounted
## Definition validation and detached geometry. No instances, clock or inventory.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const FACTS: Array[String] = ["movement_blocked", "enclosure_boundary", "thermal_barrier", "sight_blocked", "wall_connection", "roof_support"]
const CAPABILITIES: Array[String] = ["rest", "seat", "surface", "storage", "workbench", "cultivation"]


static func valid_type(row: Variant) -> bool:
	var fields: Array = ["label", "kind", "item", "amount", "work_ms", "demolish_ms", "salvage", "door", "layer", "size", "facts", "max_hp", "armor", "capabilities", "slots"]
	if row is Dictionary and row.has("environment"):
		fields.append("environment")
		if not SimEnvironmentLayout.valid_terms(row.environment):
			return false
	if not Shape.keys(row, fields):
		return false
	if not SimInventory._nonempty(row.label) or not SimInventory._nonempty(row.kind) or not SimInventory._nonempty(row.item) or not row.door is bool or row.layer not in ["ground", "roof"] or not _pair(row.size, 1, 8):
		return false
	if not Shape.count(row.amount, 1, 1000) or not Shape.count(row.salvage, 1, int(row.amount) - 1) or not Shape.count(row.work_ms, 1, 3600000) or not Shape.count(row.demolish_ms, 1, 3600000) or not Shape.count(row.max_hp, 1, 1000000) or not Shape.count(row.armor, 0, 1000000):
		return false
	if not Shape.keys(row.facts, FACTS) or not row.capabilities is Dictionary or not row.slots is Array or row.slots.size() > 64:
		return false
	for fact: String in FACTS:
		if not row.facts[fact] is bool:
			return false
	if row.layer == "roof" and (row.door or not row.capabilities.is_empty() or not row.slots.is_empty() or row.facts.values().has(true)):
		return false
	if row.door and (not row.facts.enclosure_boundary or not row.facts.movement_blocked):
		return false
	for capability: Variant in row.capabilities:
		if not capability is String or capability not in CAPABILITIES:
			return false
		var terms: Variant = row.capabilities[capability]
		match capability:
			"cultivation":
				if not Shape.keys(terms, ["substrate", "water_capacity", "initial_water", "root_capacity"]) or terms.substrate not in ["soil", "sand", "water"] or not Shape.count(terms.water_capacity, 1, 6000000) or not Shape.count(terms.initial_water, 0, int(terms.water_capacity)) or terms.root_capacity != 1:
					return false
			"storage":
				if not Shape.keys(terms, ["capacity", "items"]) or not Shape.count(terms.capacity, 1, 100000) or not SimEmbodiment._unique_texts(terms.items):
					return false
			"workbench":
				if not Shape.keys(terms, ["recipes"]) or not SimEmbodiment._unique_texts(terms.recipes) or terms.recipes.is_empty():
					return false
			_:
				if not Shape.keys(terms, []):
					return false
	if row.capabilities.has("rest") and row.facts.movement_blocked:
		return false
	var ids: Dictionary = {}
	for slot: Variant in row.slots:
		if not Shape.keys(slot, ["id", "capability", "cell", "facing", "requires"]) or not SimInventory._nonempty(slot.id) or ids.has(slot.id) or not row.capabilities.has(slot.capability) or slot.capability not in ["seat", "storage", "workbench"] or not _pair(slot.cell, -8, 8) or not _pair(slot.facing, -1, 1) or absi(int(slot.facing[0])) + absi(int(slot.facing[1])) != 1 or slot.requires not in ["", "surface"]:
			return false
		var inside: bool = Rect2i(Vector2i.ZERO, Vector2i(int(row.size[0]), int(row.size[1]))).has_point(SimRouteTravel.cell(slot.cell))
		if inside and (bool(row.facts.movement_blocked) or slot.capability != "seat") or slot.requires != "" and slot.capability != "seat":
			return false
		ids[slot.id] = true
	for capability: String in ["seat", "storage", "workbench"]:
		if row.capabilities.has(capability) and not row.slots.any(func(slot: Dictionary) -> bool: return slot.capability == capability):
			return false
	if row.capabilities.has("workbench") and row.slots.filter(func(slot: Dictionary) -> bool: return slot.capability == "workbench").size() != 1:
		return false
	return true


static func _pair(raw: Variant, minimum: int, maximum: int) -> bool:
	return raw is Array and raw.size() == 2 and Shape.count(raw[0], minimum, maximum) and Shape.count(raw[1], minimum, maximum)


static func rotate(offset: Vector2i, size: Vector2i, rotation: int) -> Vector2i:
	match rotation:
		1: return Vector2i(size.y - 1 - offset.y, offset.x)
		2: return Vector2i(size.x - 1 - offset.x, size.y - 1 - offset.y)
		3: return Vector2i(offset.y, size.x - 1 - offset.x)
	return offset


static func direction(offset: Vector2i, rotation: int) -> Vector2i:
	for _index: int in rotation:
		offset = Vector2i(-offset.y, offset.x)
	return offset


static func cells(project: Dictionary, rule: Dictionary) -> Array[Vector2i]:
	var origin: Vector2i = SimRouteTravel.cell(project.cell)
	var size := Vector2i(int(rule.size[0]), int(rule.size[1]))
	var result: Array[Vector2i] = []
	for y: int in size.y:
		for x: int in size.x:
			result.append(origin + rotate(Vector2i(x, y), size, int(project.rotation)))
	return result


static func slots(project: Dictionary, rule: Dictionary, capability: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var size := Vector2i(int(rule.size[0]), int(rule.size[1]))
	for slot: Dictionary in rule.slots:
		if not capability.is_empty() and slot.capability != capability:
			continue
		var row: Dictionary = slot.duplicate(true)
		row.cell = SimRouteTravel.cell(project.cell) + rotate(SimRouteTravel.cell(slot.cell), size, int(project.rotation))
		row.facing = direction(SimRouteTravel.cell(slot.facing), int(project.rotation))
		result.append(row)
	return result


static func fact(project: Dictionary, rule: Dictionary, name: String) -> bool:
	if project.state != "built":
		return false
	if bool(rule.door) and bool(project.open) and name in ["movement_blocked", "sight_blocked", "thermal_barrier"]:
		return false
	return bool(rule.facts.get(name, false))
