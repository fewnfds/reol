extends RefCounted
## Localized display of committed facts. Never infers completion from admission.
const Actions = preload("res://scripts/presentation/ui/actions.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")
const NAMES: Dictionary = {"save": "保存", "load": "读取", "move": "移动", "journey": "旅行", "work": "自主工作", "heal": "用药", "action": "出招", "interrupt": "中断生活行动", "construct": "施工", "continue_build": "继续施工", "plant": "种植", "take": "拿取", "put": "放入", "drop": "丢下", "rest": "休息", "eat": "进食", "cook": "烹饪", "sow": "播种", "tend": "照料", "gather": "采收", "cut": "砍伐", "uproot": "拔除", "demolish": "拆除", "talk": "交谈", "trade": "交换", "learn": "请教", "study": "读书", "practice": "修行", "request_help": "协作", "ability": "回春", "weather": "天气", "body": "身体变化", "source": "场源切换", "build": "开发建造"}
const REASONS: Dictionary = {"action_committed": "当前动作尚不能取消", "cooldown": "技能冷却中", "in_combat": "战斗中暂不能换装", "stunned": "受击硬直中", "paused": "世界已暂停", "dead": "人物已死亡", "empty": "物资不足", "empty_or_full": "物资不足或容器已满", "target_busy": "目标被占用", "target_gone": "目标已消失", "out_of_reach": "超出交互范围", "no_operation_place": "没有可用操作位", "not_available_for_contact": "不满足交往条件", "unavailable": "条件未满足", "not_a_plant": "目标不是植物", "invalid_target": "目标无效", "invalid": "条件不符", "occupied": "位置被占用", "no_potion_or_full": "无药物或生命已满", "out_of_reach_or_cooldown": "超出范围或冷却中", "target_not_visible_or_blocked": "目标不可见或被阻挡", "missing_material": "材料不足", "insufficient_material": "材料不足", "wrong_substrate": "生境不符", "no_capacity": "容量不足", "blocked": "路径阻挡"}

static func name(action: String) -> String:
	if Actions.Operations.OPERATIONS.has(action): return str(Actions.Operations.OPERATIONS[action].title)
	if action == "combat_practice": return "重开练习"
	if action == "equip": return "装备"
	if action == "unequip": return "卸下"
	if action.begins_with("slash_") or action in ["shot", "cleave", "fan", "step"]: return action_name(action)
	return str(NAMES.get(action, "行动"))

static func line(event: Dictionary) -> String:
	var text: String
	var action: String = name(str(event.get("action", "")))
	match str(event.kind):
		"order": text = "%s指令已受理" % action
		"rejected": text = "%s未执行：%s" % [action, str(REASONS.get(event.get("reason", ""), "条件不符"))]
		"placed": text = "%s：已建立#%d" % ["种植点" if event.action == "plant" else "蓝图", event.target]
		"thermal_hit": text = "%s  耐受 −%.1f  HP −%d  → %.1f / %d" % ["寒冷" if event.cause == "cold" else "过热", float(event.absorbed), int(event.damage), float(event.tolerance), int(event.hp)]
		"tolerance_restored": text = "耐受已恢复"
		"tolerance_exhausted": text = "耐受耗尽"
		"hit": text = "受到攻击  HP −%d" % int(event.damage)
		"hit_dealt": text = "攻击命中  −%d" % int(event.damage)
		"evaded": text = "闪步避过攻击"
		"death": text = "%s死亡" % str({"cold": "冻伤导致", "heat": "热伤导致", "combat": "战斗导致"}.get(event.get("cause", ""), ""))
		"action_started": text = "开始%s" % action_name(str(event.action))
		"action_active": text = "%s生效" % action_name(str(event.action))
		"arrived": text = "已到达目的地"
		"path_failed": text = "寻路失败"
		"healed": text = "用药完成"
		"ability_used": text = "回春生效"
		"equipped": text = "已装备 %s Q%d" % [Items.label(str(event.item)), Items.quality(str(event.item))]
		"unequipped": text = "已卸下 %s" % str(Items.SLOTS.get(event.slot, event.slot))
		"transferred":
			Actions.load_definitions()
			text = "%s完成  %s Q%d ×%d" % [action, Items.label(str(event.get("item", ""))), Items.quality(str(event.get("item", ""))), int(event.get("amount", 0))]
		"completed": text = "%s完成" % action
		"target_gone", "out_of_reach", "empty_or_full": text = str(REASONS.get(event.kind, "行动未完成"))
		_:
			var key: String = str(event.kind)
			var social: Dictionary = {"request_delivered": "请求已送达", "accepted_share": "已接受约定责任", "request_deferred": "已约定稍后答复", "request_refused": "对方未接受", "deferred_need": "先处理生活需要", "deferred_busy": "暂有其他事务", "refused_need": "当前生活或身体需要优先", "refused_busy": "其他目的或责任优先", "request_unavailable": "这次约定已无法继续", "share_completed": "责任已经履行", "share_released": "责任已经解除", "matter_closed": "事项已经结束", "task_satisfied": "此处已完成施工", "request_expired": "答复期限已过", "awaiting_response": "尚未收到答复"}
			text = "%s：%s" % [action, str(social.get(key, "条件未满足"))]
	var start: float = int(event.first_ms) / 1000.0
	var finish: float = int(event.at_ms) / 1000.0
	return ("[%.1f–%.1fs] " % [start, finish] if start != finish else "[%.1fs] " % finish) + text

static func action_name(kind: String) -> String:
	if Defs.ACTIONS.has(kind): return str(Defs.ACTIONS[kind].title)
	return str({"slash_1": "斩击一段", "slash_2": "斩击二段", "slash_3": "斩击终结", "shot": "射击", "cleave": "重斩", "fan": "扇形箭", "step": "闪步", "enemy_light": "横斩", "enemy_heavy": "蓄力重劈", "enemy_shot": "瞄准射击"}.get(kind, "招式"))
