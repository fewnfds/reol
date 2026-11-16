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
		row["hint"] = reason_text(query.reason)
		if query.ready and not operation.recipe.is_empty() and not data.get("process", {}).is_empty():
			row.hint = "继续本批加工，无需重新投料。" if data.process.stage == "work" else "静置已完成，收取本批产物，无需重新投料。"
		result.append(row)
	# These open local tools; they do not claim to execute a world operation.
	var alive: bool = int(player.get("hp", 0)) > 0
	if data.get("kind", "") == "blueprint": result.append(command("request_worker", "协作", "link", alive))
	var capabilities: Dictionary = buildings.get(data.get("definition", ""), {}).get("capabilities", {})
	if capabilities.has("cultivation") and data.get("kind") != "blueprint":
		result.append(command("plant_menu", "种植", "plant", alive and int(data.get("guest", 0)) == 0))
	return result

static func reason_text(reason: String) -> String:
	return {"": "", "method_not_known": "尚未入门这门技艺。", "missing_items": "缺少符合用途的原料。", "insufficient_resource": "自身资源不足。",
		"unattended_in_progress": "本批仍在静置，完成后可收取。", "in_process_conflict": "设施正在加工另一配方。", "no_output_capacity": "成品存放空间不足。",
		"empty": "这里暂时没有可取物品。", "no_food": "这里没有餐食。", "not_authorized": "尚未获得此项使用许可。", "already_understood": "已经理解这项入门内容。",
		"body_has_no_work_capability": "当前不能进行劳动。", "full": "存放空间已满。"}.get(reason, "当前条件尚不满足。")

static func art_key(definition: String) -> String:
	var mapping: Dictionary = {"wood_wall": "wall_0", "wood_door": "door", "wood_chest": "chest", "long_bed": "long_bed", "cook_stove": "stove", "wood_table": "table", "wood_chair": "chair", "wood_roof": "roof", "wood_floor": "roof", "planter": "planter", "water_well": "planter"}
	if mapping.has(definition): return mapping[definition]
	if plants.has(definition): return definition + "_2"
	return "item_" + definition
