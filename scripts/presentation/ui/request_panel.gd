extends VBoxContainer
## Only the player's delivered messages. Buttons submit ordinary contact actions.
signal requested(action: String, payload: Dictionary)
const Style = preload("res://scripts/presentation/ui/style.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
var _signature: String = ""
var _page: int = 0
const PAGE_SIZE: int = 12

func refresh(player: Dictionary) -> void:
	var requests: Array = player.get("requests", [])
	var signature: String = str(requests) + str(int(player.get("hp", 0)) <= 0) + str(_page)
	if signature == _signature: return
	_signature = signature
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var hint: Label = Style.label(self, "答复需要走到对方面前。这里保留双方最后当面确认的消息。")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if requests.is_empty(): Style.label(self, "暂无来往约定。")
	var ordered: Array = requests.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary):
		var left: int = _priority(a)
		var right: int = _priority(b)
		return left < right if left != right else a.id > b.id)
	_page = mini(_page, maxi(0, (ordered.size() - 1) / PAGE_SIZE))
	if ordered.size() > PAGE_SIZE:
		var pages := HBoxContainer.new()
		add_child(pages)
		for direction: int in [-1, 1]:
			var button := Button.new()
			button.text = "上一页" if direction < 0 else "下一页"
			button.disabled = _page == 0 if direction < 0 else (_page + 1) * PAGE_SIZE >= ordered.size()
			pages.add_child(button)
			button.pressed.connect(func(): _page += direction; _signature = ""; refresh(player))
		Style.label(pages, "%d / %d" % [_page + 1, ceili(float(ordered.size()) / PAGE_SIZE)])
	for request: Dictionary in ordered.slice(_page * PAGE_SIZE, (_page + 1) * PAGE_SIZE):
		var recipient: bool = request.recipient == 1
		var other: int = int(request.issuer) if recipient else int(request.recipient)
		var purpose: String = str(Operations.OPERATIONS.get(request.terms.operation, {}).get("title", "交付"))
		if not request.terms.item.is_empty(): purpose += " " + Items.label(str(request.terms.item)) + "×%d" % int(request.quota)
		var title: Label = Style.label(self, "%s #%d · %s #%d\n%s · %s" % ["来自" if recipient else "发给", other, purpose, int(request.target), state_text(str(request.state)), reason_text(str(request.reason))])
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if request.state not in ["pending", "deferred", "accepted"]: continue
		if request.get("peer_known_dead", false):
			var known: Label = Style.label(self, "本人已知对方亡故；此处保留此前的消息。")
			known.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			continue
		if not request.get("peer_visible", false):
			var seek := Button.new()
			seek.focus_mode = Control.FOCUS_NONE
			seek.text = "前往上次获知的位置" if int(request.get("peer_tile", -1)) >= 0 else "暂无线索，需要重新寻找"
			seek.disabled = int(player.get("hp", 0)) <= 0 or int(request.get("peer_tile", -1)) < 0
			add_child(seek)
			seek.pressed.connect(func(): requested.emit("seek_request_peer", {"tile": int(request.peer_tile)}))
			continue
		var row := HBoxContainer.new()
		add_child(row)
		var decisions: Dictionary = {"accept": "接受", "refuse": "拒绝", "defer": "稍后答复"} if recipient and request.state in ["pending", "deferred"] else {"": "当面核对"}
		for decision: String in decisions:
			var button := Button.new()
			button.focus_mode = Control.FOCUS_NONE
			button.text = decisions[decision]
			button.disabled = int(player.get("hp", 0)) <= 0
			row.add_child(button)
			var input: Dictionary = {"kind": "respond_request", "target": other, "request": int(request.id)}
			if not decision.is_empty(): input["decision"] = decision
			button.pressed.connect(func(): requested.emit("respond_request", input))

static func _priority(request: Dictionary) -> int:
	if request.recipient == 1 and request.state in ["pending", "deferred"]: return 0
	return 1 if request.state in ["pending", "deferred", "accepted"] else 2

static func state_text(state: String) -> String:
	return {"pending": "待答复", "deferred": "暂缓答复", "accepted": "已接受", "refused": "已拒绝", "expired": "答复期已过", "fulfilled": "已履行", "cancelled": "已结束"}.get(state, state)

static func reason_text(reason: String) -> String:
	return {"request_delivered": "请求已送达", "accepted_share": "已承担约定责任", "request_deferred": "约定稍后答复", "deferred_need": "先处理生活需要", "deferred_busy": "暂有其他事务", "request_refused": "对方未接受", "refused_need": "当前生活或身体需要优先", "refused_busy": "其他目的或责任优先", "request_expired": "未在约定时间内答复", "share_completed": "责任已经履行", "share_released": "责任已经解除", "matter_closed": "事项已经结束", "task_satisfied": "此处已完成施工", "request_unavailable": "这次约定已无法继续", "method_not_known": "尚未掌握所需技艺", "refused_capability": "缺少所需行动能力", "no_known_method": "目前不知道如何办理", "refused_deadline": "预计来不及完成", "awaiting_response": "尚未收到答复"}.get(reason, "当前条件不支持这项约定")
