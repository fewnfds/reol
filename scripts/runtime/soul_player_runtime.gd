class_name SoulPlayerRuntime
extends Node
## Own-life input and authorized spiritual screen; human bodies remain autonomous.

const UI = preload("res://scripts/ui/reol_ui_theme.gd")
var _owner: WeakRef
var _main: WeakRef
var _sense: SoulSenseView
var _status: PanelContainer
var _actions: PanelContainer
var _name: Label
var _condition: Label
var _activity: Label
var _target: Label
var _notice: Label
var _selected: String = ""
var _seen_event: String = ""
var _buttons: Dictionary = {}


func setup(main: Node2D, adapter: WorldContinuityRuntime) -> void:
	_owner = weakref(adapter)
	adapter.save_finished.connect(_on_save_finished)
	_main = weakref(main)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var perception_layer := CanvasLayer.new()
	perception_layer.layer = 0
	add_child(perception_layer)
	_sense = SoulSenseView.new()
	perception_layer.add_child(_sense)
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 6
	add_child(ui_layer)
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.theme = UI.create()
	ui_layer.add_child(screen)
	_status = PanelContainer.new()
	_status.add_theme_stylebox_override("panel", UI.panel(UI.JADE))
	screen.add_child(_status)
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_status.offset_left = -340
	_status.offset_right = -16
	_status.offset_top = 14
	var status_column := VBoxContainer.new()
	_status.add_child(status_column)
	_name = UI.label(status_column, "你 · 戒中残识", UI.GOLD, 20)
	_condition = UI.label(status_column, "", UI.PAPER, 16)
	_condition.custom_minimum_size = Vector2(296, 48)
	_activity = UI.label(status_column, "", UI.JADE, 14)
	_activity.custom_minimum_size.y = 42
	_actions = PanelContainer.new()
	_actions.add_theme_stylebox_override("panel", UI.panel(UI.JADE))
	screen.add_child(_actions)
	_actions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_actions.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_actions.offset_left = 16
	_actions.offset_right = 420
	_actions.offset_top = -290
	_actions.offset_bottom = -16
	var column := VBoxContainer.new()
	_actions.add_child(column)
	UI.label(column, "残识所至，亦是一个人的世界", UI.GOLD, 18)
	_target = UI.label(column, "", UI.PAPER, 14)
	var grid := GridContainer.new()
	grid.columns = 2
	column.add_child(grid)
	for row: Array in [["observe", "感受灵机 · E"], ["next", "换一道气息 · C"], ["call", "传意求携戒 · Q"], ["sleep", "收敛休息 · R"], ["wake", "重新凝神 · F"], ["cancel", "撤回请求"]]:
		_buttons[str(row[0])] = UI.button(grid, str(row[1]), submit.bind(str(row[0])))
	_notice = UI.label(column, "你不再有手脚；可传意、协商、感知与等待。", UI.WARNING, 14)
	_notice.custom_minimum_size = Vector2(376, 54)
	var storage := HBoxContainer.new()
	column.add_child(storage)
	UI.button(storage, "保存 · F5", save_game)
	UI.button(storage, "读取 · F9", load_game)
	UI.label(column, "T 等候；WASD不能替持有人行走。", UI.MUTED, 12)
	set_active(false)


func runtime() -> WorldContinuityRuntime:
	return _owner.get_ref() as WorldContinuityRuntime


func set_active(value: bool) -> void:
	_sense.visible = value
	_status.visible = value
	_actions.visible = value
	if value:
		_selected = ""
		_seen_event = ""
		project()


func project() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if not adapter.soul_player_active():
		return
	if adapter.world_sim.settlement != null and adapter.world_sim.settlement.is_pending():
		return
	var agency: SimSoulAgency = adapter.world_sim.soul_vessels.agency
	var id: String = adapter.soul_avatar_id()
	var view: Dictionary = agency.perceive(id)
	if not agency.events.is_empty() and str(agency.events.back().id) != _seen_event:
		_seen_event = str(agency.events.back().id)
		_notice.text = str(view.latest)
	var selected_row: Dictionary = {}
	for row: Dictionary in view.signals:
		if row.id == _selected:
			selected_row = row
	if selected_row.is_empty() and not view.signals.is_empty():
		selected_row = view.signals[0]
	_selected = str(selected_row.get("id", ""))
	_sense.update_perception(view, _selected)
	_name.text = "你 · " + str(view.name) + "的残识"
	_condition.text = str(view.line) + ("\n载体被人携着" if bool(view.carried) else "\n载体静置在原处")
	if bool(view.seal_broken):
		_condition.text += "\n封纹已断，外感暂时受阻"
	_activity.text = str(view.activity) + (" · 还需%d秒" % int(view.seconds) if bool(view.busy) else "")
	if bool(view.errand):
		_activity.text += "\n有人正在履行携戒的约定"
	_target.text = "传意对象：" + str(selected_row.get("label", "眼下没有感到近处气息"))
	for verb: String in ["observe", "call", "sleep", "wake"]:
		_buttons[verb].disabled = bool(view.busy)
	_buttons.call.disabled = bool(view.busy) or _selected.is_empty() or bool(view.errand)
	_buttons.wake.visible = not bool(view.awake)
	_buttons.sleep.visible = bool(view.awake)
	var main: Node2D = _main.get_ref()
	main.fog.set_observer(0, int(agency.domain.definitions.agency.sense_cells))
	main.fog.set_focus(adapter.controlled_cell())
	adapter._panel.hide()
	adapter.service_adapter.panel.hide()


func submit(verb: String) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if not adapter.soul_player_active():
		return {"ok": false, "line": "眼下不是这段残识的人生。"}
	var agency: SimSoulAgency = adapter.world_sim.soul_vessels.agency
	if verb == "next":
		var signals: Array = agency.perceive(adapter.soul_avatar_id()).signals
		var index: int = -1
		for n: int in signals.size():
			if signals[n].id == _selected:
				index = n
		if not signals.is_empty():
			_selected = str(signals[(index + 1) % signals.size()].id)
		project()
		return {"ok": not signals.is_empty(), "line": "已改向你感到的另一道气息。"}
	var result: Dictionary
	if verb == "cancel":
		var accepted: bool = adapter.stop_player_action()
		result = {"ok": accepted, "line": "请求已撤回，世界与实际保管位置继续。" if accepted else "本次撤回未受理；请待当前结算完成后重试。"}
	else:
		result = agency.command(adapter.soul_avatar_id(), verb, _selected if verb == "call" else "")
	_notice.text = str(result.line)
	project()
	return result


func save_game() -> void:
	var result: Error = runtime().request_save(VillageRuntime.SAVE_PATH)
	_notice.text = "正在完成当前结算，随后保存……" if result == OK else "未能受理保存：" + error_string(result)


func _on_save_finished(path: String, result: Error) -> void:
	if path == VillageRuntime.SAVE_PATH:
		_notice.text = "已记下这段残识与同一个世界。" if result == OK else "保存失败：" + error_string(result)


func load_game() -> void:
	var result: Error = runtime().load_game(VillageRuntime.SAVE_PATH)
	_notice.text = "已接续原主体、载体与进行中约定。" if result == OK else "没有可读取的近况。"


func _unhandled_input(event: InputEvent) -> void:
	if not runtime().soul_player_active() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_F5, KEY_F9]:
		if event.keycode == KEY_F5:
			save_game()
		else:
			load_game()
		get_viewport().set_input_as_handled()
		return
	var verb: String = {KEY_E: "observe", KEY_C: "next", KEY_Q: "call", KEY_R: "sleep", KEY_F: "wake"}.get(event.keycode, "")
	if not verb.is_empty():
		submit(verb)
		get_viewport().set_input_as_handled()
