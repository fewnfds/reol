class_name SoulVesselPanel
extends PanelContainer
## Only an authorized holder's perception and activity enter this view.

signal action_requested(verb: String)

const UI = preload("res://scripts/ui/reol_ui_theme.gd")
var _title: Label
var _description: Label
var _activity: Label
var _notice: Label
var _buttons: Dictionary = {}


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UI.create()
	custom_minimum_size.x = 460
	add_theme_stylebox_override("panel", UI.panel(UI.JADE))
	var column := VBoxContainer.new()
	add_child(column)
	_title = UI.label(column, "旧戒与传意", UI.GOLD, 20)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 152)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_description = UI.label(scroll, "", UI.PAPER, 16)
	_description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_activity = UI.label(column, "", UI.JADE, 14)
	var grid := GridContainer.new()
	grid.columns = 2
	column.add_child(grid)
	for entry: Array in [["approach", "走近旧戒"], ["take", "取在手中"], ["wake", "轻叩唤醒"], ["listen", "听一段旧事"], ["promise", "答应看药圃"], ["to_garden", "携戒去山门药圃"], ["fulfill", "与他看药木 · 履约"], ["guide", "请他指导温石"], ["sleep", "请他歇息"], ["force", "尝试强行唤醒"], ["give", "请选中同门接手"], ["place", "放在近处设施"]]:
		_buttons[str(entry[0])] = UI.button(grid, str(entry[1]), action_requested.emit.bind(str(entry[0])))
	_notice = UI.label(column, "", UI.WARNING, 14)
	_notice.custom_minimum_size.y = 44
	var row := HBoxContainer.new()
	column.add_child(row)
	UI.button(row, "中断接触", action_requested.emit.bind("cancel"))
	UI.button(row, "收起 · O / Esc", hide)
	UI.label(column, "持戒不等于支配他；听说也不等于会用。", UI.MUTED, 12)
	visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -230
	offset_right = 230
	offset_top = -275
	offset_bottom = 275


func set_terms(verbs: Dictionary) -> void:
	for verb: String in verbs:
		_buttons[verb].tooltip_text = "需%d秒，开始投入%d灵气；中断不退投入。" % [ceili(float(verbs[verb].ms) / 1000.0), int(verbs[verb].qi)]


func update_view(view: Dictionary, status: Dictionary, notice: String) -> void:
	_title.text = str(view.get("label", "旧戒")) + (" · 随身" if bool(view.get("held", false)) else "")
	_description.text = str(view.get("line", "眼下没有看清它。"))
	_notice.text = notice
	var busy: bool = bool(status.get("busy", false))
	_activity.text = "%s · 尚需%d秒" % [str(status.line), int(status.get("seconds", 0))] if busy else "贴近传意需要时间；你只能听到对方愿意说的话。"
	for button: Button in _buttons.values():
		button.disabled = busy or not bool(view.get("near", false))
	_buttons.approach.disabled = busy
	_buttons.approach.visible = not bool(view.get("near", false))
	_buttons.take.visible = not bool(view.get("held", false))
	for verb: String in ["wake", "force", "give", "place"]:
		_buttons[verb].visible = bool(view.get("held", false))
	for verb: String in ["listen", "promise", "to_garden", "fulfill", "guide", "sleep"]:
		_buttons[verb].visible = bool(view.get("held", false)) and bool(view.get("met", false))
