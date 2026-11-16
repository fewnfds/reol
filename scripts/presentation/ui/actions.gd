extends RefCounted
## Presentation vocabulary for the current commands, not a second rule engine.
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Art = preload("res://scripts/presentation/art.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Query = preload("res://scripts/sim/kernel/operation_query.gd")
static var buildings: Dictionary = {}
static var plants: Dictionary = {}
static var items: Dictionary = {}

static func load_definitions() -> void:
	if not buildings.is_empty(): return
	buildings = Query.BUILDINGS
	plants = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/plants.json")).types
	items = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/items.json"))

static func title(data: Dictionary) -> String:
	load_definitions()
	var key: String = str(data.get("definition", ""))
	var item_key: String = Items.definition(key) if Items.valid(key) else key
	var definition: Dictionary = buildings.get(key, plants.get(key, items.get(item_key, {})))
	var quality: String = " Q%d" % Items.quality(key) if definition.has("slot") else ""
	return str(data.get("name", definition.get("label", key))) + quality + " #%d" % int(data.get("id", 0))

static func visible(frame: RefCounted, id: int, use_fog: bool) -> bool:
	if id == 1: return true
	if frame.actor_slots.has(id):
		return not use_fog or frame.visible[frame.actor_slots[id]] != 0
	if not use_fog: return frame.objects.has(id)
	var memory: Dictionary = frame.perception.get("memories", {}).get(id, {})
	for tile: int in memory.get("cells", PackedInt32Array()):
		if frame.perception.tiles[tile] != 0: return true
	return false

static func observed(frame: RefCounted, id: int, use_fog: bool) -> Dictionary:
	if id == 0: return {}
	if visible(frame, id, use_fog):
		var value: Dictionary = frame.player if id == 1 else frame.inspected
		return value if int(value.get("id", 0)) == id else {}
	var old: Dictionary = frame.perception.get("memories", {}).get(id, {})
	if old.is_empty(): return {}
	var result: Dictionary = old.duplicate()
	result["memory"] = true
	return result

static func command(id: String, text: String, glyph: String, enabled: bool = true) -> Dictionary:
	return {"id": id, "text": text, "icon": glyph, "enabled": enabled}

static func self_ready(actor: Dictionary, operation: String) -> bool:
	return Query.evaluate(Operations.OPERATIONS[operation], actor, actor).ready

static func for_target(data: Dictionary, player: Dictionary, help_target: int) -> Array[Dictionary]:
	load_definitions()
	var result: Array[Dictionary] = []
	if data.is_empty() or data.get("memory", false): return result
	for id: String in Operations.OPERATIONS:
		var operation: Dictionary = Operations.OPERATIONS[id]
		if not operation.target_menu: continue
		var query: Dictionary = Query.evaluate(operation, player, data, {"help_target": help_target})
		if not query.applicable: continue
		var command_id: String = operation.command_alias if not operation.command_alias.is_empty() else id
		var row: Dictionary = command(command_id, operation.title, operation.icon, query.ready)
		row["reason"] = query.reason
		result.append(row)
	# These open local tools; they do not claim to execute a world operation.
	var alive: bool = int(player.get("hp", 0)) > 0
	if data.get("kind", "") == "blueprint": result.append(command("request_worker", "协作", "link", alive))
	var capabilities: Dictionary = buildings.get(data.get("definition", ""), {}).get("capabilities", {})
	if capabilities.has("cultivation") and data.get("kind") != "blueprint":
		result.append(command("plant_menu", "种植", "plant", alive and int(data.get("guest", 0)) == 0))
	return result

static func art_key(definition: String) -> String:
	var mapping: Dictionary = {"wood_wall": "wall_0", "wood_door": "door", "wood_chest": "chest", "long_bed": "long_bed", "cook_stove": "stove", "wood_table": "table", "wood_chair": "chair", "wood_roof": "roof", "wood_floor": "roof", "planter": "planter"}
	if mapping.has(definition): return mapping[definition]
	if plants.has(definition): return definition + "_2"
	return "item_" + definition
