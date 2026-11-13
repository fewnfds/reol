extends RefCounted
## Presentation vocabulary for the current commands, not a second rule engine.
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Art = preload("res://scripts/presentation/art.gd")
static var buildings: Dictionary = {}
static var plants: Dictionary = {}
static var items: Dictionary = {}

static func load_definitions() -> void:
	if not buildings.is_empty(): return
	buildings = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/construction.json")).types
	plants = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/plants.json")).types
	items = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/items.json"))

static func title(data: Dictionary) -> String:
	load_definitions()
	var key: String = str(data.get("definition", ""))
	var definition: Dictionary = buildings.get(key, plants.get(key, items.get(key, {})))
	return str(data.get("name", definition.get("label", key))) + " #%d" % int(data.get("id", 0))

static func observed(frame: RefCounted, id: int, use_fog: bool) -> Dictionary:
	if id == 0: return {}
	var current: bool = id == 1 or not use_fog
	if frame.actor_slots.has(id):
		current = current or frame.visible[frame.actor_slots[id]] != 0
	else:
		var memory: Dictionary = frame.perception.get("memories", {}).get(id, {})
		for tile: int in memory.get("cells", PackedInt32Array()):
			if frame.perception.tiles[tile] != 0: current = true
	if current:
		var value: Dictionary = frame.player if id == 1 else frame.inspected
		return value if int(value.get("id", 0)) == id else {}
	var old: Dictionary = frame.perception.get("memories", {}).get(id, {})
	if old.is_empty(): return {}
	var result: Dictionary = old.duplicate()
	result["memory"] = true
	return result

static func command(id: String, text: String, glyph: String, enabled: bool = true) -> Dictionary:
	return {"id": id, "text": text, "icon": glyph, "enabled": enabled}

static func for_target(data: Dictionary, player: Dictionary, help_target: int) -> Array[Dictionary]:
	load_definitions()
	var result: Array[Dictionary] = []
	if data.is_empty() or data.get("memory", false): return result
	var kind: String = str(data.get("kind", ""))
	var definition: String = str(data.get("definition", ""))
	var actor: int = int(data.get("id", 0))
	var alive: bool = int(player.get("hp", 0)) > 0
	var capabilities: Dictionary = buildings.get(definition, {}).get("capabilities", {})
	if kind in ["pile", "chest", "resource"]:
		result.append(command("take", "拿取 R", "take", alive and not data.get("inventory", {}).is_empty()))
		result.append(command("put", "放入 Q", "put", alive and not player.get("inventory", {}).is_empty()))
	if kind in ["chest", "workbench", "furniture", "pile"] and int(data.get("inventory", {}).get("meal", 0)) > 0:
		result.append(command("eat", "进食", "potion", alive))
	if kind == "blueprint":
		result.append(command("continue_build", "施工", "work", alive))
		result.append(command("request_worker", "协作", "link", alive))
	elif capabilities.has("rest"):
		result.append(command("rest", "休息", "hold", alive))
	elif capabilities.has("workbench"):
		result.append(command("cook", "烹饪", "work", alive and int(player.get("inventory", {}).get("grain", 0)) >= 2 and int(player.get("inventory", {}).get("water", 0)) >= 1))
	if capabilities.has("cultivation"):
		result.append(command("plant_menu", "种植", "plant", alive and int(data.get("guest", 0)) == 0))
	if kind in ["plant", "resource"]:
		var stage: int = int(data.get("stage", -1))
		if kind == "plant":
			result.append(command("sow", "播种", "plant", alive and stage == 0))
			result.append(command("tend", "照料", "plant", alive and stage not in [0, 4]))
			result.append(command("gather", "采收", "take", alive and stage == 2 and not data.get("inventory", {}).is_empty()))
		if kind == "resource" or definition == "old_tree": result.append(command("cut", "砍伐", "work", alive))
		result.append(command("uproot", "拔除", "close", alive))
		if definition == "old_tree": result.append(command("practice", "修行", "person", alive and stage == 2))
	if (kind == "actor" and actor != 1 and int(data.get("hp", 0)) > 0) or data.get("sapient", false):
		for row: Array in [["talk", "交谈", "talk"], ["trade", "交换", "link"], ["learn", "请教", "book"]]:
			result.append(command(row[0], row[1], row[2], alive))
		if kind == "actor":
			result.append(command("request_help", "协作", "work", alive and help_target > 0))
			result.append(command("pursue", "攻击", "attack", alive))
	if kind not in ["actor", "plant", "resource", "pile", "depot"]:
		result.append(command("demolish", "拆除", "close", alive))
	return result

static func art_key(definition: String) -> String:
	var mapping: Dictionary = {"wood_wall": "wall_0", "wood_door": "door", "wood_chest": "chest", "long_bed": "long_bed", "cook_stove": "stove", "wood_table": "table", "wood_chair": "chair", "wood_roof": "roof", "wood_floor": "roof", "planter": "planter"}
	if mapping.has(definition): return mapping[definition]
	if plants.has(definition): return definition + "_2"
	return "item_" + definition
