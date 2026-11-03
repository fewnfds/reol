class_name VillagePanel
extends PanelContainer
## Displays observable activity and the player's own knowledge.

signal action_requested(action_id: String)
signal help_requested
signal save_requested
signal load_requested

const UI = preload("res://scripts/ui/reol_ui_theme.gd")

var _title: Label
var _status: Label
var _details: Label
var _events: RichTextLabel
var _notice: Label
var _help: Button


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(456.0, 0.0)
	_build_interface()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 12.0
	offset_right = 468.0
	offset_top = -344.0
	offset_bottom = -12.0
	grow_vertical = Control.GROW_DIRECTION_BEGIN


func update_view(
	title: String,
	status: String,
	details: String,
	known_lines: Array[String],
	notice: String,
	can_help: bool
) -> void:
	_title.text = "生活与往来 · %s" % title
	_status.text = status
	_details.text = details
	_events.text = "你记得的见闻\n%s" % (
		"\n".join(known_lines) if not known_lines.is_empty() else "暂时没有新的见闻。"
	)
	_notice.text = notice
	_help.disabled = not can_help


func _build_interface() -> void:
	theme = UI.create()
	add_theme_stylebox_override("panel", UI.panel(UI.GOLD.darkened(0.5)))

	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 0)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)

	_title = _add_label(column)
	_title.add_theme_font_size_override("font_size", 17)
	_title.add_theme_color_override("font_color", Color("#e8c86a"))
	_status = _add_label(column)
	_details = _add_label(column)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 5)
	column.add_child(actions)
	_add_button(actions, "你去吃饭", _on_action_pressed.bind("eat"))
	_add_button(actions, "你去休息", _on_action_pressed.bind("rest"))
	_add_button(actions, "你去搬柴", _on_action_pressed.bind("deliver_wood"))
	_add_button(actions, "你去交工", _on_action_pressed.bind("report"))

	_help = _add_button(column, "请选中的人帮忙搬柴", _on_help_pressed)
	_help.disabled = true
	_help.tooltip_text = "先在附近选中一位同门，再向他开口。"

	_events = RichTextLabel.new()
	_events.custom_minimum_size = Vector2(0.0, 78.0)
	_events.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_events.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_events.bbcode_enabled = false
	_events.scroll_active = true
	_events.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(_events)

	_notice = _add_label(column)
	_notice.add_theme_font_size_override("font_size", 13)
	_notice.add_theme_color_override("font_color", Color("#b9c8ba"))
	_notice.custom_minimum_size.y = 20.0

	var storage := HBoxContainer.new()
	storage.add_theme_constant_override("separation", 5)
	column.add_child(storage)
	_add_button(storage, "记下近况 F5", _on_save_pressed)
	_add_button(storage, "读取近况 F9", _on_load_pressed)


func _add_label(parent: Node) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _add_button(parent: Node, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _on_action_pressed(action_id: String) -> void:
	action_requested.emit(action_id)


func _on_help_pressed() -> void:
	help_requested.emit()


func _on_save_pressed() -> void:
	save_requested.emit()


func _on_load_pressed() -> void:
	load_requested.emit()
