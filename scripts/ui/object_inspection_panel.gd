class_name ObjectInspectionPanel
extends PanelContainer
## Receives an authorized perception, never an object truth dictionary.

signal action_requested(verb: String)
signal draw_requested(target: String)

const UI = preload("res://scripts/ui/reol_ui_theme.gd")
var _title: Label
var _description: Label
var _activity: Label
var _notice: Label
var _buttons: Dictionary = {}
var _approach: Button
var _verbs: Dictionary = {}
var _thermal: bool = true
var _source_known: bool = false
var _draw_row: HBoxContainer
var _draw_targets: OptionButton
var _draw_button: Button


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UI.create()
	custom_minimum_size.x = 460
	add_theme_stylebox_override("panel", UI.panel(UI.GOLD))
	var column := VBoxContainer.new()
	add_child(column)
	_title = UI.label(column, "身边器物", UI.GOLD, 20)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 140)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_description = UI.label(scroll, "", UI.PAPER, 16)
	_description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_activity = UI.label(column, "", UI.JADE, 14)
	_approach = UI.button(column, "走近它", action_requested.emit.bind("approach"))
	var grid := GridContainer.new()
	grid.columns = 2
	column.add_child(grid)
	for entry: Array in [["inspect", "端详"], ["take", "取在手中"], ["study", "循纹探查"], ["use_research", "循内纹试引"], ["heat", "试着催动"], ["charge", "注灵温养"], ["place", "放回灶房"], ["dry", "以石烘药"], ["examine", "辨看石材"], ["force", "尝试强注灵气"], ["warm", "释热暖身"], ["enable", "启用"], ["disable", "关闭"], ["ask_examine", "请选中同门辨材"], ["ask_study", "请选中同门探查"]]:
		_buttons[str(entry[0])] = UI.button(grid, str(entry[1]), action_requested.emit.bind(str(entry[0])))
	_draw_row = HBoxContainer.new()
	column.add_child(_draw_row)
	_draw_targets = OptionButton.new()
	_draw_targets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_draw_row.add_child(_draw_targets)
	_draw_button = UI.button(_draw_row, "引至手边", _submit_draw)
	_draw_row.hide()
	_buttons["to_garden"] = UI.button(grid, "去药圃备料", action_requested.emit.bind("to_garden"))
	_buttons["methods"] = UI.button(grid, "温养手记 · M", action_requested.emit.bind("methods"))
	_buttons["spirit_source"] = UI.button(column, "灶旁地火隙 · 引息", action_requested.emit.bind("spirit_source"))
	_buttons.spirit_source.tooltip_text = "亲自到源隙近旁，借已学手法与真实温石引息；可引入本人，也可留在石中。"
	_buttons.spirit_source.visible = false
	_notice = UI.label(column, "", UI.WARNING, 14)
	_notice.custom_minimum_size.y = 40
	var row := HBoxContainer.new()
	column.add_child(row)
	UI.button(row, "停止操作", action_requested.emit.bind("cancel"))
	UI.button(row, "收起 · I / Esc", hide)
	UI.label(column, "WASD中断自己的操作；离开可能错过同门解释。", UI.MUTED, 12)
	visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -230
	offset_right = 230
	offset_top = -288
	offset_bottom = 288


func update_view(view: Dictionary, status: Dictionary, notice: String) -> void:
	_title.text = str(view.get("label", "身边器物")) + (" · 随身" if bool(view.get("held", false)) else "")
	_description.text = str(view.get("line", "眼下没有看清它。"))
	_notice.text = notice
	var busy: bool = bool(status.get("busy", false))
	_activity.text = "%s · 尚需%d分钟" % [str(status.line), int(status.remaining)] if busy or bool(status.get("checking", false)) else "端详和展开已有信息不同；动手需要时间。"
	if busy and status.has("remaining_ms"):
		_activity.text = "%s · 尚需%.1f秒" % [str(status.line), float(status.remaining_ms) / 1000.0]
	var near: bool = bool(view.get("near", false))
	_approach.visible = not near
	_approach.disabled = busy
	for verb: String in _buttons:
		var button: Button = _buttons[verb]
		button.disabled = busy or not near
		button.visible = _verbs.has(verb)
	var method: bool = bool(view.get("method", false))
	var held: bool = bool(view.get("held", false))
	_buttons.charge.visible = _verbs.has("charge") and method
	_buttons.dry.visible = _verbs.has("dry") and method
	_buttons.warm.visible = _verbs.has("warm") and method and held
	_buttons.to_garden.visible = _thermal and method and held
	_buttons.methods.visible = _thermal
	_buttons.spirit_source.visible = _thermal and _source_known
	_buttons.ask_examine.visible = _verbs.has("examine")
	_buttons.ask_study.visible = _verbs.has("study")
	_buttons.place.visible = _verbs.has("place") and held
	_buttons.take.visible = _verbs.has("take") and not held
	_buttons.use_research.visible = _verbs.has("use_research") and held and not method
	_buttons.enable.visible = _verbs.has("enable") and method and near and view.has("enabled") and not bool(view.enabled)
	_buttons.disable.visible = _verbs.has("disable") and near and view.has("enabled") and bool(view.enabled)
	_draw_row.visible = _verbs.has("draw") and held and method
	_draw_button.disabled = busy or _draw_targets.item_count == 0
	_draw_targets.disabled = busy
	if _verbs.has("draw"):
		_draw_button.tooltip_text = "凝神%.1f秒，开始投入%d灵气；只引同高、无遮挡且松置的短距小器物。" % [float(_verbs.draw.duration_ms) / 1000.0, int(_verbs.draw.qi)]
	if _verbs.has("heat"):
		_buttons.heat.text = "以石催火" if method else str(_verbs.heat.label)


func set_terms(verbs: Dictionary, thermal: bool = true) -> void:
	_verbs = verbs.duplicate(true)
	_thermal = thermal
	for verb: String in _buttons:
		_buttons[verb].tooltip_text = ""
		if not verbs.has(verb):
			continue
		_buttons[verb].text = str(verbs[verb].label)
		_buttons[verb].tooltip_text = "需%d分钟，无须投入灵气。" % int(verbs[verb].minutes) if int(verbs[verb].qi) == 0 else "需%d分钟，开始时投入%d灵气；中断不返还已投入灵气。" % [int(verbs[verb].minutes), int(verbs[verb].qi)]
	for verb: String in ["examine", "study"]:
		if verbs.has(verb):
			_buttons["ask_" + verb].tooltip_text = "请选中的同门动手，能否答应取决于本人；操作需%d分钟。" % int(verbs[verb].minutes)
	if verbs.has("warm"):
		_buttons.warm.tooltip_text = "需%d分钟，无须追加灵气。完成后消耗石内一份已有余热，在此处留下有限暖流；移动、中断都不会提前释热。" % int(verbs.warm.minutes)
	_buttons.spirit_source.tooltip_text = "亲自到源隙近旁，借已学手法与真实温石引息；可引入本人，也可留在石中。" if thermal else ""


func set_source_entry(known: bool) -> void:
	_source_known = known
	_buttons.spirit_source.visible = _thermal and known


func set_draw_targets(choices: Array[Dictionary]) -> void:
	var previous: String = selected_draw_target()
	_draw_targets.clear()
	for choice: Dictionary in choices:
		_draw_targets.add_item(str(choice.label))
		_draw_targets.set_item_metadata(_draw_targets.item_count - 1, str(choice.id))
		if str(choice.id) == previous:
			_draw_targets.select(_draw_targets.item_count - 1)
	_draw_targets.tooltip_text = "只列眼前松置的小器物；没有目标时可回住处看看原来的木剑。"
	_draw_button.disabled = choices.is_empty()


func selected_draw_target() -> String:
	return str(_draw_targets.get_item_metadata(_draw_targets.selected)) if _draw_targets.selected >= 0 else ""


func _submit_draw() -> void:
	var target: String = selected_draw_target()
	if not target.is_empty():
		draw_requested.emit(target)
