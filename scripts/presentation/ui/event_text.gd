extends RefCounted
## Localized display of committed facts. Never infers completion from admission.
const Actions = preload("res://scripts/presentation/ui/actions.gd")
const NAMES: Dictionary = {"save": "保存", "load": "读取", "move": "移动", "journey": "旅行", "stop": "停止", "work": "自主工作", "heal": "用药", "attack": "攻击", "pursue": "追击", "hold": "驻守", "attack_move": "攻击移动", "construct": "施工", "continue_build": "继续施工", "plant": "种植", "take": "拿取", "put": "放入", "drop": "丢下", "rest": "休息", "eat": "进食", "cook": "烹饪", "sow": "播种", "tend": "照料", "gather": "采收", "cut": "砍伐", "uproot": "拔除", "demolish": "拆除", "talk": "交谈", "trade": "交换", "learn": "请教", "study": "读书", "practice": "修行", "request_help": "协作", "ability": "回春", "weather": "天气", "body": "身体变化", "source": "场源切换", "build": "开发建造"}
const REASONS: Dictionary = {"dead": "人物已死亡", "empty": "物资不足", "empty_or_full": "物资不足或容器已满", "target_busy": "目标被占用", "target_gone": "目标已消失", "out_of_reach": "超出交互范围", "no_operation_place": "没有可用操作位", "not_available_for_contact": "不满足交往条件", "unavailable": "条件未满足", "not_a_plant": "目标不是植物", "invalid_target": "目标无效", "invalid": "条件不符", "occupied": "位置被占用", "no_potion_or_full": "无药物或生命已满", "out_of_reach_or_cooldown": "超出范围或冷却中", "target_not_visible_or_blocked": "目标不可见或被阻挡", "missing_material": "材料不足", "insufficient_material": "材料不足", "wrong_substrate": "生境不符", "no_capacity": "容量不足", "blocked": "路径阻挡"}

static func name(action: String) -> String:
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
		"death": text = "%s死亡" % str({"cold": "冻伤导致", "heat": "热伤导致", "combat": "战斗导致"}.get(event.get("cause", ""), ""))
		"arrived": text = "已到达目的地"
		"path_failed": text = "寻路失败"
		"healed": text = "用药完成"
		"ability_used": text = "回春生效"
		"transferred":
			Actions.load_definitions()
			text = "%s完成  %s ×%d" % [action, str(Actions.items.get(event.get("item", ""), {}).get("label", "物资")), int(event.get("amount", 0))]
		"completed": text = "%s完成" % action
		"target_gone", "out_of_reach", "empty_or_full": text = str(REASONS.get(event.kind, "行动未完成"))
		_: text = "%s：条件未满足" % action
	var start: float = int(event.first_ms) / 1000.0
	var finish: float = int(event.at_ms) / 1000.0
	return ("[%.1f–%.1fs] " % [start, finish] if start != finish else "[%.1fs] " % finish) + text
