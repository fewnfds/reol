extends RefCounted
## Presentation vocabulary for the current commands, not a second rule engine.
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Art = preload("res://scripts/presentation/art.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Query = preload("res://scripts/sim/kernel/operation_query.gd")
const SubjectView = preload("res://scripts/presentation/ui/subject_view.gd")
const REASONS: Dictionary = {
	"management_updated": "管理安排已更新",
	"workspace_updated": "工作范围已刷新",
	"configuration_changed": "配置已变化，已刷新；请重试",
	"invalid_configuration": "配置无效，请核对对象、范围和数值",
	"invalid_worker": "人员不存在、已死亡或不属于本宗",
	"department_gone": "部门已不存在",
	"batch_paused": "本批已暂停，需在职责面板继续",
	"batch_cancelled": "本批已取消，原料仍在台内",
	"process_changed": "此批次已结束或更换",
	"production_target_met": "当前目标已达到、暂停或未配置",
	"shipment_changed": "运输条件已变化，请重新选取工作",
	"request_changed": "供料需求已变化",
	"storage_rejected": "仓储规则不接收此物品或品质",
	"entrusted_goods_cannot_be_dropped": "受托公物须交付或退回，不能当作个人物品丢弃",
	"supply_destination_required": "此仓限定供给去向，请按供料用途领出并送往获准设施",
	"conversion_blocked": "台内转换条件变化，原料与已做工时保留",

	"action_committed": "当前动作尚不能取消",
	"cooldown": "技能冷却中",
	"in_combat": "战斗中暂不能换装",
	"stunned": "受击硬直中",
	"paused": "世界已暂停",
	"dead": "人物已死亡",
	"empty": "这里暂时没有可取物品。",
	"empty_or_full": "物资不足或容器已满",
	"target_busy": "对方正在忙或操作位置被占用",
	"teacher_does_not_know": "对方尚未掌握这项本领",
	"learner_already_understood": "已理解这项入门内容，无需重复授课",
	"partner_left": "对方已离开共同活动",
	"replaced": "已改为其他行动",
	"cancelled": "已取消",
	"interrupted": "活动被打断",
	"combat": "转入战斗",
	"preempted": "优先处理其他事情",
	"actor_dead": "人物已死亡",
	"actor_removed": "人物已离开世界",
	"target_gone": "目标已消失",
	"out_of_reach": "超出交互范围",
	"no_operation_place": "没有可用操作位",
	"not_available_for_contact": "不满足交往条件",
	"unavailable": "条件未满足",
	"not_a_plant": "目标不是植物",
	"invalid_target": "目标无效",
	"invalid": "条件不符",
	"occupied": "栽培位置已有植物。",
	"no_potion_or_full": "无药物或生命已满",
	"out_of_reach_or_cooldown": "超出范围或冷却中",
	"target_not_visible_or_blocked": "目标不可见或被阻挡",
	"missing_material": "材料不足",
	"insufficient_material": "材料不足",
	"wrong_substrate": "栽培基质不适合这种植物。",
	"no_capacity": "容量不足",
	"blocked": "路径阻挡",
	"": "",
	"method_not_known": "尚未掌握所需技艺",
	"already_has_eaves": "这面墙已装屋檐。",
	"missing_items": "缺少符合用途的原料。",
	"insufficient_resource": "自身资源不足。",
	"unattended_in_progress": "本批仍在静置，完成后可收取。",
	"in_process_conflict": "设施正在加工另一配方。",
	"no_output_capacity": "成品存放空间不足。",
	"no_food": "这里没有餐食。",
	"not_authorized": "尚未获得此项使用许可。",
	"already_understood": "已经理解这项入门内容。",
	"method_not_mastered": "熟练掌握后才能传授。",
	"awaiting_participant": "等待对方主动参加。",
	"not_interested": "对方当前有自己的安排。",
	"not_needed": "植物健康且无需补水。",
	"water_excess": "基质过湿，当前照料不能排水。",
	"incompatible_cultivation_title": "不能用自己的种子占用他人的栽培位置。",
	"body_has_no_work_capability": "当前不能进行劳动。",
	"full": "存放空间已满。",
	"use_matter_offer": "此为宗门事项，需要通过事项委托。",
	"already_assigned": "此处已有同门承担施工。",
	"already_requested": "已送达这项请求，请等待或当面核对。",
	"request_on_cooldown": "对方刚刚回应过，请稍后再协商。",
	"too_many_requests": "当前来往约定过多，请先办结已有约定。",
	"cannot_commission": "无权委托此项事务。",
	"unknown_task": "尚未获知所托事务的地点。",
	"contact_not_completed": "尚未完成当面接触。",
	"peer_not_observed": "当前未见到对方。",
	"refused_capability": "缺少所需行动能力",
	"task_not_understood": "尚不清楚如何办理此事。",
	"matter_expired": "事项已过办理期限。",
	"no_open_share": "这份责任已由他人领受。",
	"post_unavailable": "这条告示已不能领受。",
	"cannot_accept_share": "目前没有可领受的份额。",
	"path_failed": "路途受阻，未能到达。",
	"invalid_task": "这处工地已不能委托。",
	"target_not_visible": "目标不在当前视野内。",
	"shared_clue": "交谈完成，获知新线索",
	"contact_established": "交谈完成，建立联系",
	"transferred": "物品已转移",
	"process_waiting": "劳动完成，转入静置",
	"request_delivered": "请求已送达",
	"accepted_share": "已承担约定责任",
	"request_deferred": "约定稍后答复",
	"deferred_need": "先处理生活需要",
	"deferred_busy": "暂有其他事务",
	"request_refused": "对方未接受",
	"refused_need": "当前生活或身体需要优先",
	"refused_busy": "其他目的或责任优先",
	"request_expired": "未在约定时间内答复",
	"share_completed": "责任已经履行",
	"share_released": "责任已经解除",
	"matter_closed": "事项已经结束",
	"task_satisfied": "此处已完成施工",
	"request_unavailable": "这次约定已无法继续",
	"no_known_method": "目前不知道如何办理",
	"refused_deadline": "预计来不及完成",
	"awaiting_response": "尚未收到答复"
}
static var buildings: Dictionary = {}
static var plants: Dictionary = {}
static var items: Dictionary = {}

static func load_definitions() -> void:
	if not buildings.is_empty(): return
	buildings = Query.BUILDINGS
	plants = Query.PLANTS
	items = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/items.json"))

static func title(data: Dictionary) -> String:
	if data.get("pending", false): return "正在察看 #%d…" % int(data.get("id", 0))
	load_definitions()
	var key: String = str(data.get("definition", ""))
	if data.get("kind") == "landmark": return "%s · 地区地标" % str(data.get("name", key))
	var item_key: String = Items.definition(key) if Items.valid(key) else key
	var definition: Dictionary = buildings.get(key, plants.get(key, items.get(item_key, {})))
	var quality: String = " Q%d" % Items.quality(key) if definition.has("slot") else ""
	return str(data.get("name", definition.get("label", key))) + quality + " #%d" % int(data.get("id", 0))

static func visible(frame: RefCounted, id: int, use_fog: bool) -> bool:
	return SubjectView.visible(frame, id, use_fog)

static func observed(frame: RefCounted, id: int, use_fog: bool) -> Dictionary:
	return SubjectView.observed(frame, id, use_fog)

static func command(id: String, text: String, glyph: String, enabled: bool = true) -> Dictionary:
	return {"id": id, "text": text, "icon": glyph, "enabled": enabled}

static func self_ready(actor: Dictionary, operation: String) -> bool:
	return Query.evaluate(Operations.OPERATIONS[operation], actor, actor).ready

static func for_target(data: Dictionary, player: Dictionary, help_target: int) -> Array[Dictionary]:
	load_definitions()
	var result: Array[Dictionary] = []
	if data.is_empty() or data.get("memory", false) or data.get("pending", false): return result
	for id: String in Operations.OPERATIONS:
		var operation: Dictionary = Operations.OPERATIONS[id]
		if not operation.target_menu: continue
		var query: Dictionary = Query.evaluate(operation, player, data, {"help_target": help_target})
		if not query.applicable: continue
		var command_id: String = operation.command_alias if not operation.command_alias.is_empty() else id
		var row: Dictionary = command(command_id, operation.title, operation.icon, query.ready)
		row["reason"] = query.reason
		row["hint"] = reason_text(query.reason)
		if operation.handler == "fit_eaves" and query.ready:
			row.hint = "到墙旁施工，完工消耗木材 ×%d。" % operation.required_items.wood
		if query.ready and not operation.recipe.is_empty() and not data.get("process", {}).is_empty():
			row.hint = "继续本批加工，无需重新投料。" if data.process.stage == "work" else "静置已完成，收取本批产物，无需重新投料。"
		if operation.handler in ["learn", "teach"] and query.ready:
			if operation.handler == "learn":
				var known: bool = data.get("teaches", {}).has(operation.learning_method)
				row.hint = "已知对方掌握；到场后仍需对方同意。" if known else "尚不知对方是否掌握，可当面询问；对方也可拒绝。"
				if data.get("teaching_refusals", {}).has(id):
					row.enabled = false
					row.hint = "此前当面确认：对方尚未掌握。获知新情况或稍后可再询问。"
			else: row.hint = "向此人传授；到场后需要对方自愿参加。"
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
	return str(REASONS.get(reason, "当前条件尚不满足。"))

static func art_key(definition: String) -> String:
	load_definitions()
	if buildings.get(definition, {}).has("art_key"): return str(buildings[definition].art_key)
	var mapping: Dictionary = {"wood_wall": "wall_0", "wood_door": "door", "wood_chest": "chest", "long_bed": "long_bed", "cook_stove": "stove", "wood_table": "table", "notice_desk": "table", "wood_chair": "chair", "wood_floor": "floor_preview", "planter": "planter", "water_well": "planter"}
	if mapping.has(definition): return mapping[definition]
	if plants.has(definition): return str(plants[definition].get("art_base", definition)) + "_2"
	return "item_" + definition
