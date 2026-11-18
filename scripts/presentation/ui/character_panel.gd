extends VBoxContainer
## Explicit inspected identity. Read-only NPC views never change command ownership.
signal requested(action: String, payload: Dictionary)
const Items = preload("res://scripts/sim/kernel/items.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")
const Grid = preload("res://scripts/presentation/ui/item_grid.gd")
const ActivityText = preload("res://scripts/presentation/ui/activity_text.gd")
const EventText = preload("res://scripts/presentation/ui/event_text.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const RequestPanel = preload("res://scripts/presentation/ui/request_panel.gd")
var subject_id: int = 1
var events: RichTextLabel
var _header: Label
var _bag: Button
var _overview: Label
var _stats: Label
var _activity: Label
var activity_progress := ProgressBar.new()
var _practice: Label
var _responsibilities: Label
var _gear := GridContainer.new()
var _study: Button
var _ability: Button
var _equipment_signature: String = ""
var _event_signature: String = ""
var _tabs := TabContainer.new()
var _requests: VBoxContainer

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	add_child(head)
	_header = Style.label(head, "#%d" % subject_id)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bag = Button.new()
	_bag.focus_mode = Control.FOCUS_NONE
	_bag.text = "背包"
	_bag.icon = Style.icon("bag")
	head.add_child(_bag)
	_bag.pressed.connect(func(): requested.emit("inspect_bag", {"subject": subject_id}))
	add_child(_tabs)
	_tabs.custom_minimum_size = Vector2(324, 180)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	var body: VBoxContainer = _page("概览")
	_overview = Style.label(body)
	_overview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_activity = Style.label(body)
	_activity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	activity_progress.max_value = 1.0
	activity_progress.show_percentage = true
	activity_progress.custom_minimum_size.y = 12
	body.add_child(activity_progress)
	_stats = Style.label(body)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gear.columns = 2
	body.add_child(_gear)
	var practice: VBoxContainer = _page("修行")
	_practice = Style.label(practice)
	_practice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_study = Button.new()
	_study.focus_mode = Control.FOCUS_NONE
	_study.text = "读书"
	_study.visible = subject_id == 1
	_study.pressed.connect(func(): requested.emit("study", {}))
	practice.add_child(_study)
	_ability = Button.new()
	_ability.focus_mode = Control.FOCUS_NONE
	_ability.text = "回春"
	_ability.visible = subject_id == 1
	_ability.pressed.connect(func(): requested.emit("ability", {}))
	practice.add_child(_ability)
	var social := ScrollContainer.new()
	social.name = "职责"
	_tabs.add_child(social)
	_responsibilities = Style.label(social)
	_responsibilities.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_responsibilities.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if subject_id == 1:
		var messages := ScrollContainer.new()
		messages.name = "约定"
		_tabs.add_child(messages)
		_requests = RequestPanel.new()
		_requests.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		messages.add_child(_requests)
		_requests.requested.connect(func(action: String, payload: Dictionary): requested.emit(action, payload))
	events = RichTextLabel.new()
	events.name = "事件"
	events.scroll_following = true
	events.selection_enabled = true
	_tabs.add_child(events)

func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	return body

func _rest_text(subject: Dictionary) -> String:
	var places := PackedStringArray()
	for id: int in subject.get("service_targets", {}).get("rest", []): places.append("床榻 #%d" % id)
	return "可用休养处：" + "、".join(places) if not places.is_empty() else "休养处：尚未获知或分配"

func _known_teachings(subject: Dictionary) -> String:
	var lines := PackedStringArray()
	for method: String in subject.get("teaches", {}):
		if Growth.Defs.METHODS.has(method): lines.append(str(Growth.Defs.METHODS[method].title))
	return "已知可传授：\n" + "\n".join(lines) if not lines.is_empty() else "尚未获知所传本领。"

func _membership_text(subject: Dictionary) -> String:
	var titles := PackedStringArray()
	for membership: Dictionary in subject.get("memberships", []): titles.append(str(membership.name))
	return "所属：" + "、".join(titles) if not titles.is_empty() else "所属：尚未获知" if subject.get("observed_other", false) or subject.get("memory", false) else "暂无所属宗门"

func refresh(subject: Dictionary) -> void:
	var matching: bool = int(subject.get("id", 0)) == subject_id
	var known: bool = matching and not subject.get("memory", false) and not subject.get("pending", false)
	_header.text = "%s #%d%s" % [str(subject.get("name", "")), subject_id, " · 本人" if subject_id == 1 else (" · 先前所知" if subject.get("memory", false) else "")]
	if known:
		var sex: String = str(subject.get("sex", ""))
		if not sex.is_empty(): _header.text += " · " + ("女" if sex == "female" else "男")
		var title: String = str(subject.get("resident_title", ""))
		if not title.is_empty(): _header.text += " · " + title
	_bag.visible = subject_id == 1
	_bag.disabled = not known
	_overview.text = (_membership_text(subject) + "\n" + _rest_text(subject)) if matching and not subject.get("pending", false) else ("正在察看…" if subject.get("pending", false) else "暂无所知。")
	if subject.get("memory", false): _overview.text = "不在视野内；此处仅保留先前的目击信息。"
	if not known:
		activity_progress.hide()
		_event_signature = ""
		_stats.text = "不在视野内；当前状况未明。" if matching and subject.get("memory", false) else "暂无所知。"
		_activity.text = "先前目击于 %.1f 秒" % (int(subject.get("seen_ms", 0)) / 1000.0) if subject.get("memory", false) else ""
		_practice.text = _known_teachings(subject) if matching else "暂无所知。"
		_responsibilities.text = "当前任职与办理状态尚未核实。"
		events.text = ""
		_study.disabled = true
		_ability.disabled = true
	var equipment: Dictionary = subject.get("equipment", {}) if known else {}
	var signature: String = str(equipment) + str(known) + str(subject.get("hp", 0) <= 0)
	if signature != _equipment_signature:
		_equipment_signature = signature
		for child: Node in _gear.get_children():
			_gear.remove_child(child)
			child.queue_free()
		for slot: String in Items.SLOTS:
			var key: String = str(equipment.get(slot, ""))
			var button := Button.new()
			button.focus_mode = Control.FOCUS_NONE
			button.text = "%s\n%s" % [Items.SLOTS[slot], "—" if key.is_empty() else "%s Q%d" % [Items.label(key), Items.quality(key)]]
			button.icon = Style.icon("lock") if key.is_empty() else Grid.item_icon(key)
			button.custom_minimum_size = Vector2(150, 62)
			button.disabled = not known or subject_id != 1 or key.is_empty() or int(subject.get("hp", 0)) <= 0
			button.tooltip_text = ("空槽位" if key.is_empty() else Grid.item_tooltip(key)) if subject_id != 1 else ("空槽位" if key.is_empty() else "卸下\n" + Grid.item_tooltip(key))
			button.pressed.connect(func(): requested.emit("unequip", {"slot": slot}))
			_gear.add_child(button)
	if not known: return
	if _requests != null: _requests.refresh(subject)
	if subject_id != 1:
		_stats.text = str(subject.get("appearance", "当前状况未明。"))
		_practice.text = _known_teachings(subject)
		var public_roles: Array = subject.get("public_roles", [])
		_responsibilities.text = _rest_text(subject) + "\n\n" + ("任职：\n" + "\n".join(public_roles) if not public_roles.is_empty() else "暂无已知任职。")
		events.text = "暂无可知记录。"
		_study.disabled = true; _ability.disabled = true
	else:
		_refresh_self(subject)
	_refresh_activity(subject)

func _refresh_self(subject: Dictionary) -> void:
	var stats: Dictionary = subject.get("stats", {})
	_stats.text = "HP %d / %d\n耐受 %.1f / %.0f\n近战基础 %d   远程基础 %d\n防御 %d   移速 %.2f\n精力 %d   饥饿 %d\n%.2f°C" % [
		int(subject.hp), int(stats.get("max_hp", 100)), float(subject.tolerance), float(subject.max_tolerance),
		int(stats.get("melee", 0)), int(stats.get("ranged", 0)),
		int(stats.get("armor", 0)), float(stats.get("speed", 0)), int(subject.energy), int(subject.hunger), float(subject.temperature)]
	var lines := PackedStringArray(["灵力 %d / 3000" % int(subject.get("qi", 0)), "体魄 %d · 悟性 %d" % [Growth.aptitude(subject, "physique"), Growth.aptitude(subject, "comprehension")]])
	for method: String in subject.get("methods", {}):
		var entry: Dictionary = subject.methods[method]
		var spec: Dictionary = Growth.Defs.METHODS[method]
		lines.append("%s\n理解 %d/%d · 实践 %d/%d" % [spec.title, entry.understanding, spec.introduction_points, entry.progress, spec.mastery_points])
	for condition: String in subject.get("conditions", {}): lines.append("%s · 休养 %d/%d" % [Growth.Defs.CONDITIONS[condition].title, subject.conditions[condition].recovery, Growth.Defs.CONDITIONS[condition].recovery_needed])
	_practice.text = "\n".join(lines)
	var social_lines := PackedStringArray()
	for duty: Dictionary in subject.get("duties", {}).values():
		if duty.kind == "cultivation":
			social_lines.append("%s\n照管%d处田畦 · 归入仓库 #%d\n巡田、补种、照料与采收" % [duty.title, duty.sites.size(), int(duty.destination)])
		else: social_lines.append("%s\n负责 #%d · 告示案 #%d\n%s 库存低于%d时补至%d" % [duty.title, int(duty.target), int(duty.channel), Items.label(duty.item), int(duty.low), int(duty.desired)])
	for share: Dictionary in subject.get("responsibilities", {}).values(): social_lines.append("事项 #%d · 剩余%d/%d\n对象 #%d%s" % [int(share.matter), int(share.remaining), int(share.quota), int(share.target), " · 已超期，仍负责任" if share.overdue else ""])
	for receipt: Dictionary in subject.get("reports", []): social_lines.append("待回报 #%d · 已办%d · 告示案 #%d" % [int(receipt.matter), int(receipt.fulfilled), int(receipt.channel)])
	_responsibilities.text = _rest_text(subject) + "\n\n" + ("\n\n".join(social_lines) if not social_lines.is_empty() else "暂无任职职责或已受事项。")
	_study.disabled = not preload("res://scripts/presentation/ui/actions.gd").self_ready(subject, "study")
	_ability.disabled = not preload("res://scripts/presentation/ui/actions.gd").self_ready(subject, "wood_mend")
	var version: String = "%d:%d:%d" % [subject_id, int(subject.get("view_epoch", 0)), int(subject.get("events_version", 0))]
	if version != _event_signature:
		_event_signature = version
		var event_lines := PackedStringArray()
		for event: Dictionary in subject.get("events", []):
			var line: String = EventText.line(event)
			if not line.is_empty(): event_lines.append(line)
		events.text = "\n".join(event_lines)

func _refresh_activity(subject: Dictionary) -> void:
	if int(subject.get("hp", 0)) <= 0:
		_activity.text = "已亡故"; return
	_activity.text = ActivityText.summary(subject)
	if subject_id == 1:
		var reason: String = str(subject.get("admission_reason", ""))
		if not reason.is_empty(): _activity.text += "\n" + preload("res://scripts/presentation/ui/actions.gd").reason_text(reason)
		_activity.text += "\n自主生活中；移动可切回亲自操作。" if subject.get("autonomous", false) else "\n由你亲自操作。"

func advance_progress(subject: Dictionary, at: float) -> void:
	var value: float = ActivityText.progress(subject, at)
	activity_progress.visible = value >= 0.0
	if value >= 0.0: activity_progress.value = value
