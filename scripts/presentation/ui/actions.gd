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
	if capabilities.has("records") and data.get("kind") != "blueprint":
		var read: Dictionary = player.get("known_channels", {}).get(int(data.id), {})
		for post: Dictionary in read.get("posts", {}).values():
			if post.state == "open" and _can_close_post(player, post):
				var close: Dictionary = command("close_post", "撤回告示 #%d" % int(post.matter), "work", alive)
				close["payload"] = {"matter": int(post.matter)}
				close["hint"] = "在本案撤回并释放尚未履行的责任；已交付实物与已完成劳动保留。"
				result.append(close)
			if post.state != "open" or post.blocked or int(post.unclaimed) <= 0 or (int(post.deadline_ms) > 0 and int(player.get("at_ms", 0)) >= int(post.deadline_ms)): continue
			if player.get("responsibilities", {}).values().any(func(share: Dictionary): return share.matter == post.matter): continue
			var capable: bool = preload("res://scripts/sim/kernel/agency_institutions.gd")._actionable(player, post, int(player.get("at_ms", 0)))
			var row: Dictionary = command("accept_post", "受理 #%d · %s×%d" % [int(post.matter), Items.label(post.item), mini(int(post.quota), int(post.unclaimed))], "work", alive and capable)
			row["payload"] = {"matter": int(post.matter)}
			row["hint"] = "本人已读记录；到告示案签领时重新核对。待领%d，已回报%d/%d。%s" % [int(post.unclaimed), int(post.reported), int(post.total), "" if capable else "当前尚无办理所需的身体能力或技艺。"]
			result.append(row)
		for duty: Dictionary in player.get("duties", {}).values():
			if duty.channel != data.id: continue
			var row: Dictionary = command("post_duty", "履职 · " + str(duty.title), "work", alive)
			row["payload"] = {"appointment": int(duty.appointment)}
			row["hint"] = "按本人近期察看的库存办理；需要先到负责地点检查。"
			result.append(row)
		for receipt: Dictionary in player.get("channel_receipts", []):
			if receipt.channel != data.id: continue
			var row: Dictionary = command("report_matter", "回报 #%d · 已办%d" % [int(receipt.matter), int(receipt.fulfilled)], "work", alive)
			row["payload"] = {"share": int(receipt.share)}
			result.append(row)
			if receipt.state == "accepted":
				row = command("report_matter", "受阻释责 #%d" % int(receipt.matter), "work", alive)
				row["payload"] = {"share": int(receipt.share), "blocked": true}
				result.append(row)
	return result

static func _can_close_post(actor: Dictionary, post: Dictionary) -> bool:
	var stock = preload("res://scripts/sim/kernel/stock_rules.gd")
	var target: Dictionary = {"id": post.target, "organization": post.organization}
	var required: Array = [post.item]
	if post.kind == "produce": required = Operations.OPERATIONS[post.operation].recipe.inputs.keys() + Operations.OPERATIONS[post.operation].recipe.outputs.keys()
	return required.all(func(item: String): return stock.permits_at(actor, target, "commission", item))

static func reason_text(reason: String) -> String:
	return {"": "", "method_not_known": "尚未入门这门技艺。", "missing_items": "缺少符合用途的原料。", "insufficient_resource": "自身资源不足。",
		"unattended_in_progress": "本批仍在静置，完成后可收取。", "in_process_conflict": "设施正在加工另一配方。", "no_output_capacity": "成品存放空间不足。",
		"empty": "这里暂时没有可取物品。", "no_food": "这里没有餐食。", "not_authorized": "尚未获得此项使用许可。", "already_understood": "已经理解这项入门内容。",
		"method_not_mastered": "熟练掌握后才能传授。", "awaiting_participant": "等待对方主动参加。", "not_interested": "对方当前有自己的安排。",
		"body_has_no_work_capability": "当前不能进行劳动。", "full": "存放空间已满。"}.get(reason, "当前条件尚不满足。")

static func art_key(definition: String) -> String:
	var mapping: Dictionary = {"wood_wall": "wall_0", "wood_door": "door", "wood_chest": "chest", "long_bed": "long_bed", "cook_stove": "stove", "wood_table": "table", "notice_desk": "table", "wood_chair": "chair", "wood_roof": "roof", "wood_floor": "roof", "planter": "planter", "water_well": "planter"}
	if mapping.has(definition): return mapping[definition]
	if plants.has(definition): return definition + "_2"
	return "item_" + definition
