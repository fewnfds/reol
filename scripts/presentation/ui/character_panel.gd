extends VBoxContainer
## Explicit inspected identity. Read-only NPC views never change command ownership.
signal requested(action: String, payload: Dictionary)
const Items = preload("res://scripts/sim/kernel/items.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")
const Grid = preload("res://scripts/presentation/ui/item_grid.gd")
const EventText = preload("res://scripts/presentation/ui/event_text.gd")
var subject_id: int = 1
var events: RichTextLabel
var _stats: Label
var _practice: Label
var _gear := GridContainer.new()
var _study: Button
var _ability: Button
var _equipment_signature: String = ""
var _event_signature: String = ""
var _tabs := TabContainer.new()

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
	var practice := VBoxContainer.new()
	practice.name = "修行"
	_tabs.add_child(practice)
	_practice = Style.label(practice)
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
		_practice.text = "⊘"
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
	var stats: Dictionary = subject.get("stats", {})
	_stats.text = "HP %d / %d\n耐受 %.1f / %.0f\n近战 %d / %.0fms / %.1f\n远程 %d / %.0fms / %.1f\n防御 %d   移速 %.2f\n精力 %d   饥饿 %d\n%.2f°C" % [
		int(subject.hp), int(stats.get("max_hp", 100)), float(subject.tolerance), float(subject.max_tolerance),
		int(stats.get("melee", 0)), float(stats.get("melee_cooldown_ms", 0)), float(stats.get("melee_range", 0)),
		int(stats.get("ranged", 0)), float(stats.get("ranged_cooldown_ms", 0)), float(stats.get("ranged_range", 0)),
		int(stats.get("armor", 0)), float(stats.get("speed", 0)), int(subject.energy), int(subject.hunger), float(subject.temperature)]
	_practice.text = "灵气 %d\n修行 %d\n%s" % [int(subject.get("qi", 0)), int(subject.get("practice", 0)), str(subject.get("methods", {}).keys())]
	_study.disabled = subject_id != 1 or int(subject.hp) <= 0 or int(subject.inventory.get("breath_manual", 0)) <= 0
	_ability.disabled = subject_id != 1 or int(subject.hp) <= 0 or not subject.get("abilities", {}).get("wood_mend", false)
	var version: String = "%d:%d" % [subject_id, int(subject.get("events_version", 0))]
	if version != _event_signature:
		_event_signature = version
		var lines := PackedStringArray()
		for event: Dictionary in subject.get("events", []): lines.append(EventText.line(event))
		events.text = "\n".join(lines)
