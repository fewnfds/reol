extends RefCounted
## Localized display of committed facts. Never infers completion from admission.
const Actions = preload("res://scripts/presentation/ui/actions.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")
const NAMES: Dictionary = {"save": "保存", "load": "读取", "move": "移动", "journey": "旅行", "work": "自主工作", "heal": "用药", "action": "出招", "interrupt": "中断生活行动", "construct": "施工", "continue_build": "继续施工", "plant": "种植", "take": "拿取", "put": "放入", "drop": "丢下", "rest": "休息", "eat": "进食", "cook": "烹饪", "sow": "播种", "tend": "照料", "gather": "采收", "cut": "砍伐", "uproot": "拔除", "demolish": "拆除", "talk": "交谈", "trade": "交换", "learn": "请教", "study": "读书", "practice": "修行", "request_help": "协作", "ability": "回春", "weather": "天气", "body": "身体变化", "source": "场源切换", "build": "开发建造"}
const REASONS: Dictionary = Actions.REASONS

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
	var target: String = str(event.get("target_label", "#%d" % int(event.target) if int(event.get("target", 0)) > 0 else ""))
	if not target.is_empty(): action += " · " + target
	match str(event.kind):
		"session_started": text = "%s · %s：双方已到场，开始授业" % ["传授" if event.role == "teacher" else "请教", target]
		"activity_result":
			var operation: Dictionary = Actions.Operations.OPERATIONS[event.action]
			if event.role in ["teacher", "learner"]:
				var method: String = str(preload("res://scripts/sim/kernel/growth_defs.gd").METHODS[operation.learning_method].title)
				action = "%s%s · %s" % ["向对方传授" if event.role == "teacher" else "向对方请教", method, target]
			var reason: String = str(event.reason)
			if event.status == "completed":
				text = action + "：" + str(REASONS.get(reason, "完成")) if reason != "completed" else action + "：完成"
				if event.has("item") and int(event.get("amount", 0)) > 0: text += " · %s ×%d" % [Items.label(str(event.item)), int(event.amount)]
				if int(event.get("points_gained", 0)) > 0: text += " · 熟练 +%d" % int(event.points_gained)
			else:
				text = "%s：%s" % [action, {"refused": "未能开始", "interrupted": "已中断", "failed": "未完成"}.get(event.status, "未完成")]
				if REASONS.has(reason) and not str(REASONS[reason]).is_empty(): text += " · " + str(REASONS[reason])
		"order": text = "%s：指令已受理" % action
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
		"learner_already_understood": text = "%s：当面确认对方已理解，无需再授入门内容" % action
		"awaiting_participant": text = "%s：对方未主动参加，本次邀请已结束" % action
		"not_interested": text = "%s：对方当前有自己的安排" % action
		"teacher_does_not_know": text = "%s：对方尚未掌握这项本领" % action
		"target_gone", "out_of_reach", "empty_or_full": text = str(REASONS.get(event.kind, "行动未完成"))
		_: return ""
	var start: float = int(event.first_ms) / 1000.0
	var finish: float = int(event.at_ms) / 1000.0
	return ("[%.1f–%.1fs] " % [start, finish] if start != finish else "[%.1fs] " % finish) + text

static func action_name(kind: String) -> String:
	if Defs.ACTIONS.has(kind): return str(Defs.ACTIONS[kind].title)
	return str({"slash_1": "斩击一段", "slash_2": "斩击二段", "slash_3": "斩击终结", "shot": "射击", "cleave": "重斩", "fan": "扇形箭", "step": "闪步", "enemy_light": "横斩", "enemy_heavy": "蓄力重劈", "enemy_shot": "瞄准射击"}.get(kind, "招式"))
