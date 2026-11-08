class_name WorldContinuityPanel
extends PanelContainer
## Local observations and travel; development controls are kept out of the flow.

signal travel_requested(region_id: String)
signal route_toggle_requested
signal save_requested
signal load_requested

const UI = preload("res://scripts/ui/reol_ui_theme.gd")

var _heading: Label
var _observations: RichTextLabel
var _notice: Label
var _tools: VBoxContainer
var _tool_toggle: Button


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(348, 0)
	theme = UI.create()
	add_theme_stylebox_override("panel", UI.panel(UI.JADE.darkened(0.5)))
	var column := VBoxContainer.new()
	add_child(column)
	_heading = UI.label(column, "行旅与见闻", UI.JADE, 17)
	var travel := HBoxContainer.new()
	column.add_child(travel)
	UI.button(travel, "返回山门", _travel.bind("home"))
	UI.button(travel, "前往河湾", _travel.bind("river"))
	_observations = RichTextLabel.new()
	_observations.custom_minimum_size.y = 88
	_observations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_observations.bbcode_enabled = false
	_observations.scroll_active = true
	_observations.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(_observations)
	_notice = UI.label(column, "", UI.MUTED, 13)
	_notice.mouse_filter = Control.MOUSE_FILTER_PASS
	_notice.custom_minimum_size.y = 36
	_notice.max_lines_visible = 2
	var storage := HBoxContainer.new()
	column.add_child(storage)
	UI.button(storage, "保存近况", _save)
	UI.button(storage, "读取近况", _load)
	_tool_toggle = UI.button(column, "开发工具  +", _toggle_tools)
	_tool_toggle.add_theme_font_size_override("font_size", 12)
	_tool_toggle.custom_minimum_size.y = 24
	_tools = VBoxContainer.new()
	column.add_child(_tools)
	UI.label(_tools, "仅供场景验证，不属于人物能力。", UI.MUTED, 12)
	UI.button(_tools, "中断 / 恢复运粮道路", _toggle_route)
	_tools.visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -364
	offset_right = -16
	offset_top = -298
	offset_bottom = -16
	grow_vertical = Control.GROW_DIRECTION_BEGIN


func update_view(here: String, observations: String, notice: String) -> void:
	_heading.text = here.replace(" · 点击居民查看活动", "")
	_observations.text = observations
	update_notice(notice)


func update_notice(notice: String) -> void:
	_notice.text = notice
	_notice.tooltip_text = notice


func _toggle_tools() -> void:
	_tools.visible = not _tools.visible
	_tool_toggle.text = "开发工具  −" if _tools.visible else "开发工具  +"


func _travel(region_id: String) -> void:
	travel_requested.emit(region_id)


func _toggle_route() -> void:
	route_toggle_requested.emit()


func _save() -> void:
	save_requested.emit()


func _load() -> void:
	load_requested.emit()
