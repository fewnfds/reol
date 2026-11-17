extends RefCounted
## Presentation of an observed activity, never another execution state.
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")

static func summary(subject: Dictionary) -> String:
	if subject.get("pending", false): return "正在察看…"
	if subject.get("memory", false): return "不在视野内，当前活动未明"
	if int(subject.get("hp", 0)) <= 0: return "已亡故"
	var activity: Dictionary = subject.get("activity", {})
	var phase: String = str(activity.get("phase", "idle"))
	var operation: String = str(activity.get("operation", ""))
	var text: String = str({"idle": "闲暇", "approaching": "行进中", "traveling": "行进中", "exploring": "附近走动", "combat": "交战中", "waiting": "等候中", "partner_waiting": "等待共同参与", "acting": "作业中", "working": "活动中"}.get(phase, "闲暇"))
	if phase in ["acting", "working"] and Operations.OPERATIONS.has(operation):
		text = str(Operations.OPERATIONS[operation].title) + "中"
		if activity.get("role") in ["teacher", "learner"]: text = "传授中" if activity.role == "teacher" else "学习中"
	if phase in ["waiting", "partner_waiting"]:
		text = str({"awaiting_participant": "等待对方参加", "target_busy": "等待操作位置空闲", "occupied": "等待占地腾空"}.get(activity.get("reason", ""), text))
	if phase not in ["approaching", "traveling", "exploring"] and int(activity.get("target", 0)) > 0:
		text += " · " + str(activity.get("target_label", "#%d" % int(activity.target)))
	return text

static func progress(subject: Dictionary, at: float) -> float:
	if subject.get("pending", false) or subject.get("memory", false) or int(subject.get("hp", 0)) <= 0: return -1.0
	var activity: Dictionary = subject.get("activity", {})
	if activity.get("phase") != "acting" or not activity.has("started_ms") or not activity.has("due_ms"): return -1.0
	var duration: int = int(activity.due_ms) - int(activity.started_ms)
	return clampf((at - int(activity.started_ms)) / duration, 0.0, 1.0) if duration > 0 else -1.0
