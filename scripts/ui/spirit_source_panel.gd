class_name SpiritSourcePanel
extends PanelContainer
## Receives a local perception and the player's own activity, never source stock.

signal action_requested(verb: String)
signal choice_changed

const UI = preload("res://scripts/ui/reol_ui_theme.gd")

var object_choice: OptionButton
var target_choice: OptionButton
var _title: Label
var _description: Label
var _activity: Label
var _notice: Label
var _terms: Label
var _approach: Button
var _begin: Button
var _stop: Button
var _back: Button


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UI.create()
	custom_minimum_size = Vector2(464, 0)
	add_theme_stylebox_override("panel", UI.panel(UI.WARNING))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	_title = UI.label(column, "地火隙 · 引息", UI.GOLD, 20)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(436, 86)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_description = UI.label(scroll, "走到灶旁，才能察觉地火隙的近况。", UI.PAPER, 16)
	_description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	object_choice = _choice(column, "作媒温石")
	object_choice.item_selected.connect(func(_index: int) -> void: choice_changed.emit())
	target_choice = _choice(column, "引入何处")
	for row: Array in [["本人 · 恢复灵气", "body"], ["温石 · 留作储热", "stone"]]:
		target_choice.add_item(str(row[0]))
		target_choice.set_item_metadata(target_choice.item_count - 1, str(row[1]))
	target_choice.item_selected.connect(func(_index: int) -> void: choice_changed.emit())
	_terms = UI.label(column, "引息需持续在场；完成才取得作用。", UI.MUTED, 13)
	_activity = UI.label(column, "", UI.JADE, 14)
	_activity.custom_minimum_size.y = 22
	_approach = UI.button(column, "走到灶旁", action_requested.emit.bind("approach"))
	_begin = UI.button(column, "引息", action_requested.emit.bind("begin"))
	_notice = UI.label(column, "", UI.WARNING, 14)
	_notice.custom_minimum_size.y = 40
	var row := HBoxContainer.new()
	column.add_child(row)
	_stop = UI.button(row, "停止引息", action_requested.emit.bind("cancel"))
	_back = UI.button(row, "回到温石", action_requested.emit.bind("object"))
	UI.button(row, "收起 · Esc", hide)
	UI.label(column, "源息有限，两种用途共享；听说手法不等于已经学会。", UI.MUTED, 12)
	visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -232
	offset_right = 232
	offset_top = -290
	offset_bottom = 290


func _choice(parent: Control, caption: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label: Label = UI.label(row, caption, UI.PAPER, 14)
	label.custom_minimum_size.x = 76
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var choice := OptionButton.new()
	choice.custom_minimum_size.y = 32
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.clip_text = true
	row.add_child(choice)
	return choice


func set_terms(duration_ms: int) -> void:
	_terms.text = "持续%d分钟，不预支灵气；完成后才引入目标。容量不足的余息会散去。" % ceili(float(duration_ms) / 60000.0)


func selected_object() -> String:
	return str(object_choice.get_selected_metadata()) if object_choice.selected >= 0 else ""


func selected_target() -> String:
	return str(target_choice.get_selected_metadata()) if target_choice.selected >= 0 else "body"


func update_view(view: Dictionary, status: Dictionary, notice: String, preferred_object: String = "") -> void:
	_title.text = str(view.get("label", "地火隙")) + " · 引息"
	_description.text = str(view.get("line", "眼下没有看清这处源隙。"))
	var chosen: String = selected_object() if preferred_object.is_empty() else preferred_object
	var objects: Array = view.get("objects", [])
	var signature: String = JSON.stringify(objects)
	if str(object_choice.get_meta("objects", "")) != signature:
		object_choice.clear()
		for object: Dictionary in objects:
			object_choice.add_item(str(object.get("label", "温石")))
			object_choice.set_item_metadata(object_choice.item_count - 1, str(object.get("id", "")))
			if str(object.get("id", "")) == chosen:
				object_choice.select(object_choice.item_count - 1)
		object_choice.set_meta("objects", signature)
	elif not chosen.is_empty():
		for index: int in range(object_choice.item_count):
			if str(object_choice.get_item_metadata(index)) == chosen:
				object_choice.select(index)
	var busy: bool = bool(status.get("busy", false))
	var near: bool = bool(view.get("near", false))
	_activity.text = "%s · 尚需%d秒" % [str(status.get("line", "正在引息")), int(status.get("seconds", status.get("remaining", 0)))] if busy else "引息要亲自在场，温石与身体也须空闲。"
	_notice.text = notice
	_notice.tooltip_text = notice
	object_choice.disabled = busy or objects.is_empty()
	target_choice.disabled = busy
	_begin.disabled = busy or not near or selected_object().is_empty()
	_begin.tooltip_text = "沿已学手法，将同一源息引入所选目标；能否完成由实际身体、器物和源况决定。"
	_approach.visible = not near
	_approach.disabled = busy or not bool(view.get("known", false))
	_stop.disabled = not busy
	_back.disabled = selected_object().is_empty() and preferred_object.is_empty()
