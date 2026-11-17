extends VBoxContainer
## Explicit inspected identity. Read-only NPC views never change command ownership.
signal requested(action: String, payload: Dictionary)
const Items = preload("res://scripts/sim/kernel/items.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")
const Grid = preload("res://scripts/presentation/ui/item_grid.gd")
const EventText = preload("res://scripts/presentation/ui/event_text.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const RequestPanel = preload("res://scripts/presentation/ui/request_panel.gd")
var subject_id: int = 1
var events: RichTextLabel
var _stats: Label
var _activity: Label
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
	var head := HBoxContainer.new()
	add_child(head)
	var name_label: Label = Style.label(head, "#%d" % subject_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bag := Button.new()
	bag.focus_mode = Control.FOCUS_NONE
	bag.text = "背包"
	bag.icon = Style.icon("bag")
	head.add_child(bag)
	bag.pressed.connect(func(): requested.emit("inspect_bag", {"subject": subject_id}))
	add_child(_tabs)
	_tabs.custom_minimum_size = Vector2(324, 368)
	_tabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	var body := VBoxContainer.new()
	body.name = "装备"
	_tabs.add_child(body)
	_gear.columns = 2
	body.add_child(_gear)
	_stats = Style.label(body)
	_activity = Style.label(body)
	var practice := VBoxContainer.new()
	practice.name = "修行"
	_tabs.add_child(practice)
	_practice = Style.label(practice)
	_practice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_study = Button.new()
	_study.focus_mode = Control.FOCUS_NONE
	_study.text = "读书"
	_study.pressed.connect(func(): requested.emit("study", {}))
	practice.add_child(_study)
	_ability = Button.new()
	_ability.focus_mode = Control.FOCUS_NONE
	_ability.text = "回春"
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

func refresh(subject: Dictionary) -> void:
	var known: bool = int(subject.get("id", 0)) == subject_id and not subject.get("memory", false)
	if not known:
		_event_signature = ""
		_stats.text = "⊘ #%d" % subject_id
		_activity.text = ""
		_practice.text = "⊘"
		_responsibilities.text = "⊘"
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
			button.tooltip_text = "卸下" if key.is_empty() else "卸下\n" + Grid.item_tooltip(key)
			button.pressed.connect(func(): requested.emit("unequip", {"slot": slot}))
			_gear.add_child(button)
	if not known: return
	if _requests != null: _requests.refresh(subject)
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
	for duty: Dictionary in subject.get("duties", {}).values(): social_lines.append("%s\n负责 #%d · 告示案 #%d\n%s 库存低于%d时补至%d" % [duty.title, int(duty.target), int(duty.channel), Items.label(duty.item), int(duty.low), int(duty.desired)])
	for share: Dictionary in subject.get("responsibilities", {}).values(): social_lines.append("事项 #%d · 剩余%d/%d\n对象 #%d%s" % [int(share.matter), int(share.remaining), int(share.quota), int(share.target), " · 已超期，仍负责任" if share.overdue else ""])
	for receipt: Dictionary in subject.get("reports", []): social_lines.append("待回报 #%d · 已办%d · 告示案 #%d" % [int(receipt.matter), int(receipt.fulfilled), int(receipt.channel)])
	_responsibilities.text = "\n\n".join(social_lines) if not social_lines.is_empty() else "暂无任职职责或已受事项。"
	var activity: Dictionary = subject.get("activity", {})
	var operation: String = str(activity.get("operation", ""))
	var phase: String = str({"approaching": "前往", "waiting": "等待", "acting": "进行", "partner_waiting": "应邀等候", "traveling": "赶路", "exploring": "探查", "combat": "战斗", "working": "活动"}.get(activity.get("phase", ""), "空闲"))
	_activity.text = "%s%s" % [phase, " · " + str(EventText.Actions.Operations.OPERATIONS[operation].title) if EventText.Actions.Operations.OPERATIONS.has(operation) else ""]
	_study.disabled = subject_id != 1 or not preload("res://scripts/presentation/ui/actions.gd").self_ready(subject, "study")
	_ability.disabled = subject_id != 1 or not preload("res://scripts/presentation/ui/actions.gd").self_ready(subject, "wood_mend")
	var version: String = "%d:%d" % [subject_id, int(subject.get("events_version", 0))]
	if version != _event_signature:
		_event_signature = version
		var event_lines := PackedStringArray()
		for event: Dictionary in subject.get("events", []): event_lines.append(EventText.line(event))
		events.text = "\n".join(event_lines)
