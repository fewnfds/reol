class_name HeatMethodsRuntime
extends Node
## Authoring and authorized notes. Recipes do not bypass original artifact jobs.

const UI = preload("res://scripts/ui/reol_ui_theme.gd")
var panel: PanelContainer
var object_choice: OptionButton
var method_choice: OptionButton
var learner_choice: OptionButton
var flow_choice: OptionButton
var pulse_choice: OptionButton
var title_edit: LineEdit
var tabs: TabContainer
var record_choice: OptionButton
var recipient_choice: OptionButton
var place_choice: OptionButton
var _record_note: Label
var _note: Label
var _activity: Label
var _reply: Label
var _owner: WeakRef


func runtime() -> WorldContinuityRuntime:
	return _owner.get_ref() as WorldContinuityRuntime


func setup(adapter: WorldContinuityRuntime) -> void:
	_owner = weakref(adapter)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	panel = PanelContainer.new()
	panel.theme = UI.create()
	panel.add_theme_stylebox_override("panel", UI.panel(UI.GOLD))
	screen.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -282
	panel.offset_right = 282
	panel.offset_top = 72
	panel.offset_bottom = -12
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var frame := VBoxContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(frame)
	UI.label(frame, "温养手记", UI.GOLD, 20)
	tabs = TabContainer.new()
	tabs.custom_minimum_size.x = 500
	frame.add_child(tabs)
	var column := VBoxContainer.new()
	column.name = "试验与传授"
	tabs.add_child(column)
	UI.label(column, "草案须亲手验证；教人也需要对方答应并实际练习。", UI.MUTED, 13)
	object_choice = _field(column, "眼前器物")
	method_choice = _field(column, "已有版本")
	method_choice.item_selected.connect(_on_method_selected)
	var name_row := HBoxContainer.new()
	column.add_child(name_row)
	UI.label(name_row, "草案名称", UI.PAPER, 14).custom_minimum_size.x = 72
	title_edit = LineEdit.new()
	title_edit.placeholder_text = "例如：小灶留火法"
	title_edit.max_length = int(adapter.world_sim.heat_methods.definitions.title_length)
	title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(title_edit)
	var parameters := HBoxContainer.new()
	column.add_child(parameters)
	flow_choice = OptionButton.new()
	flow_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parameters.add_child(flow_choice)
	var rules: Dictionary = adapter.world_sim.heat_methods.definitions
	for flow: String in rules.flows:
		flow_choice.add_item(str(rules.flows[flow].label))
		flow_choice.set_item_metadata(flow_choice.item_count - 1, int(flow))
	pulse_choice = OptionButton.new()
	pulse_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parameters.add_child(pulse_choice)
	for pulse: int in rules.pulses:
		pulse_choice.add_item("持续%d分钟" % (pulse * int(rules.pulse_minutes)))
		pulse_choice.set_item_metadata(pulse_choice.item_count - 1, pulse)
	var actions := GridContainer.new()
	actions.columns = 2
	column.add_child(actions)
	UI.button(actions, "记下草案 / 修订", compose_selected)
	UI.button(actions, "亲自试验草案", act.bind("trial"))
	UI.button(actions, "按已学法温养", act.bind("use"))
	UI.button(actions, "停止我的操作", stop)
	UI.button(actions, "照已读步骤尝试", act.bind("record"))
	UI.button(actions, "走向眼前温石", approach_object)
	learner_choice = _field(column, "附近同门")
	UI.button(column, "商量传授这一版", teach_selected)
	_build_record_page()
	_note = UI.label(frame, "", UI.PAPER, 14)
	_note.custom_minimum_size = Vector2(490, 48)
	_activity = UI.label(frame, "", UI.JADE, 14)
	_activity.custom_minimum_size.y = 32
	_reply = UI.label(frame, "先学会引流基础，再尝试编排。急灌可能伤石，持续更久不等于灌得更急。", UI.WARNING, 14)
	_reply.custom_minimum_size.y = 42
	var bottom := HBoxContainer.new()
	frame.add_child(bottom)
	UI.button(bottom, "环顾 / 刷新", refresh_choices)
	UI.button(bottom, "收起 · M / Esc", panel.hide)
	panel.hide()
	GameClock.time_advanced.connect(_on_advanced)
	adapter.avatar_changed.connect(reset_observation)
	tabs.tab_changed.connect(func(_index: int) -> void: refresh_choices())


func _build_record_page() -> void:
	var page := VBoxContainer.new()
	page.name = "实物记录"
	tabs.add_child(page)
	UI.label(page, "木牍须实际刻写、携带和阅读；拿到不等于练成。", UI.MUTED, 13)
	record_choice = _field(page, "眼前木牍")
	record_choice.item_selected.connect(func(_index: int) -> void: refresh())
	place_choice = _field(page, "放置设施")
	recipient_choice = _field(page, "交给眼前")
	var actions := GridContainer.new()
	actions.columns = 2
	page.add_child(actions)
	UI.button(actions, "刻写所选版本 · %d木料" % int(runtime().world_sim.method_records.definitions.cost), record_action.bind("write"))
	UI.button(actions, "花时间阅读", record_action.bind("read"))
	UI.button(actions, "收在原行囊", record_action.bind("take"))
	UI.button(actions, "放到所选设施", record_action.bind("place"))
	UI.button(actions, "商量并实际交接", record_action.bind("give"))
	UI.button(actions, "停止我的操作", stop)
	_record_note = UI.label(page, "", UI.JADE, 14)
	_record_note.custom_minimum_size = Vector2(470, 50)
	UI.label(page, "要刻写的版本在“试验与传授”页选择。抄写已读步骤仍需木料和时间，旧牍不会自动更新到新修订。", UI.MUTED, 13)


func selected_record() -> String:
	return str(record_choice.get_selected_metadata()) if record_choice.item_count > 0 else ""


func record_action(verb: String) -> void:
	if not _available():
		return
	var target: String = ""
	if verb == "place" and place_choice.item_count > 0:
		target = str(place_choice.get_selected_metadata())
	elif verb == "give" and recipient_choice.item_count > 0:
		target = str(recipient_choice.get_selected_metadata()).trim_prefix("subject:")
	runtime().hold_player_motion()
	var result: Dictionary = runtime().world_sim.method_records.begin("player", verb, "" if verb == "write" else selected_record(), selected_method() if verb == "write" else "", target)
	_reply.text = str(result.line)
	runtime()._refresh_panel()
	refresh_choices()


func _method_suffix(id: String) -> String:
	if runtime().world_sim.heat_methods.knows("player", id):
		return " · 已练"
	return " · 已读待练" if runtime().world_sim.method_records.has_read("player", id) else " · 草案待试"


func _field(parent: Control, caption: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label: Label = UI.label(row, caption, UI.PAPER, 14)
	label.custom_minimum_size.x = 72
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(390, 30)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return option


func approach_object() -> void:
	var id: String = selected_object()
	if id.is_empty():
		return
	var artifacts: SimArtifacts = runtime().world_sim.artifacts
	var region: String = str(artifacts.objects[id].region)
	_reply.text = "正走向眼前温石；到达后再动手。" if runtime().travel_to(region, artifacts.object_cell(id)) else "先完成或停止手头的事情，才能前往。"


func show_panel() -> void:
	if not runtime().human_player_active():
		return
	runtime().interaction_adapter.panel.hide()
	runtime().object_adapter.panel.hide()
	runtime().soul_adapter.panel.hide()
	runtime().avian_adapter.panel.hide()
	runtime().sparring_adapter.panel.hide()
	panel.show()
	refresh_choices()
	refresh()
	if is_inside_tree():
		method_choice.grab_focus()


func refresh_choices(selected: String = "") -> void:
	var previous: String = str(method_choice.get_selected_metadata()) if method_choice.item_count > 0 else ""
	method_choice.clear()
	for row: Dictionary in runtime().world_sim.heat_methods.visible_methods("player"):
		method_choice.add_item(str(row.label) + _method_suffix(str(row.id)))
		method_choice.set_item_metadata(method_choice.item_count - 1, row.id)
		if row.id == (previous if selected.is_empty() else selected):
			method_choice.select(method_choice.item_count - 1)
	var objects: Array[Dictionary] = runtime().interaction_adapter.objects_for("examine")
	runtime().interaction_adapter._fill(object_choice, objects)
	var receivers: Array[Dictionary] = []
	for row: Dictionary in runtime().interaction_adapter.receivers():
		if not str(row.key).begins_with("subject:avian:"):
			receivers.append(row)
	runtime().interaction_adapter._fill(learner_choice, receivers)
	var chosen: String = selected_record()
	record_choice.clear()
	for row: Dictionary in runtime().world_sim.method_records.visible("player"):
		record_choice.add_item(str(row.label))
		record_choice.set_item_metadata(record_choice.item_count - 1, str(row.id))
		if row.id == chosen:
			record_choice.select(record_choice.item_count - 1)
	runtime().interaction_adapter._fill(recipient_choice, receivers)
	place_choice.clear()
	var records: SimMethodRecords = runtime().world_sim.method_records
	for region: String in runtime().world_sim.regions:
		var sim: VillageSimulation = runtime().world_sim.regions[region]
		for place: String in sim.places:
			if records.cell_at("home", "actor:player").distance_to(records.cell_at(region, place)) <= float(records.definitions.interaction_cells):
				place_choice.add_item(str(sim.places[place].label))
				place_choice.set_item_metadata(place_choice.item_count - 1, region + "/" + place)
	refresh()


func selected_method() -> String:
	return str(method_choice.get_selected_metadata()) if method_choice.item_count > 0 else ""


func selected_object() -> String:
	return str(object_choice.get_selected_metadata().id) if object_choice.item_count > 0 else ""


func _available() -> bool:
	if not runtime().human_player_active() or not runtime().player_journey.is_empty() or not runtime()._home._player.motion.action.is_empty():
		_reply.text = "先停稳，再动手编排或与同门商量。"
		return false
	runtime().prepare_player_command()
	return true


func compose_selected() -> void:
	if not _available():
		return
	var methods: SimHeatMethods = runtime().world_sim.heat_methods
	var parent: String = selected_method()
	if methods.methods.has(parent) and methods.methods[parent].creator != runtime().avatar_subject:
		parent = ""
	var result: Dictionary = methods.compose("player", selected_object(), title_edit.text, int(flow_choice.get_selected_metadata()), int(pulse_choice.get_selected_metadata()), parent)
	_reply.text = str(result.line)
	if bool(result.ok):
		refresh_choices(str(result.method))


func act(mode: String) -> void:
	if not _available():
		return
	var result: Dictionary = runtime().world_sim.heat_methods.start("player", selected_object(), selected_method(), mode)
	_reply.text = str(result.line)
	runtime()._refresh_panel()
	refresh()


func teach_selected() -> void:
	if not _available() or learner_choice.item_count == 0:
		return
	var learner: String = str(learner_choice.get_selected_metadata()).trim_prefix("subject:")
	var result: Dictionary = runtime().world_sim.heat_methods.teach("player", learner, selected_object(), selected_method())
	_reply.text = str(result.line)
	runtime()._refresh_panel()
	refresh()


func stop() -> void:
	runtime().stop_player_action()
	_reply.text = "操作已中止；已付出的灵气和木料不退，未完成的阅读或练习不会授予本领。"
	refresh()


func refresh() -> void:
	if not panel.visible:
		return
	if not runtime().human_player_active():
		panel.hide()
		return
	var id: String = selected_method()
	var methods: SimHeatMethods = runtime().world_sim.heat_methods
	_note.text = "眼下没有你拟定、练过或实际读完的版本。"
	if methods.methods.has(id):
		var terms: Dictionary = methods.terms(id)
		var item_label: String = methods.label(id) + _method_suffix(id)
		if method_choice.get_item_text(method_choice.selected) != item_label:
			method_choice.set_item_text(method_choice.selected, item_label)
		_note.text = "%s；每次需%d分钟，投入%d灵气。%s" % [terms.label, int(terms.minutes), int(terms.qi), "你亲手练过这一版；只验证当时的器物和条件。" if methods.knows("player", id) else "你读过这一版步骤，尚未亲手证实；先具备引流基础再尝试。" if runtime().world_sim.method_records.has_read("player", id) else "这是草案，还没有亲手证实。"]
	var status: Dictionary = runtime().world_sim.artifacts.status("player", selected_object())
	_activity.text = str(status.line) + (" · 还需%d分钟" % int(status.remaining) if bool(status.get("busy", false)) else "")
	_record_note.text = str(runtime().world_sim.method_records.status("player").line)
	if runtime().world_sim.method_records.owns_actor("player"):
		_activity.text = _record_note.text


func _on_method_selected(_index: int) -> void:
	var methods: SimHeatMethods = runtime().world_sim.heat_methods
	var id: String = selected_method()
	if methods.methods.has(id):
		title_edit.text = str(methods.methods[id].title)
		for index: int in flow_choice.item_count:
			if flow_choice.get_item_metadata(index) == methods.methods[id].flow:
				flow_choice.select(index)
		for index: int in pulse_choice.item_count:
			if pulse_choice.get_item_metadata(index) == methods.methods[id].pulses:
				pulse_choice.select(index)
	refresh()


func reset_observation() -> void:
	panel.hide()
	method_choice.clear()
	record_choice.clear()
	title_edit.clear()
	_reply.text = "先选定已有版本，或按自己的思路记一份草案。"


func _on_advanced(_from: int, _to: int) -> void:
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not runtime().human_player_active() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_M:
		if panel.visible:
			panel.hide()
		else:
			show_panel()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and panel.visible:
		panel.hide()
		get_viewport().set_input_as_handled()
