class_name ClothingRuntime
extends Node
## Personal wardrobe and nearby surface observations; no authority or item rules.

const UI = preload("res://scripts/ui/reol_ui_theme.gd")
var panel: PanelContainer
var choice: OptionButton
var preview: WardrobePreview
var note: Label
var observation: Label
var response: Label
var preview_direction: OptionButton
var preview_action: OptionButton
var preview_accessories: CheckBox
var buttons: Dictionary = {}
var _signature: String = ""
var _owner: WeakRef


class PreviewBody extends Node2D:
	var appearance: Dictionary = {}
	var pose: Dictionary = {"direction_index": 4, "action": "idle", "time_ms": 0, "started_ms": 0}


	func _process(_delta: float) -> void:
		if is_visible_in_tree() and int(pose.time_ms) != GameClock.elapsed_ms:
			pose.time_ms = GameClock.elapsed_ms
			queue_redraw()


	func _draw() -> void:
		PawnVisuals.draw_actor(self, Vector2.ZERO, Vector2.ZERO, Color("#827861"), "", false, true, appearance, pose)


class WardrobePreview extends Control:
	var body: PreviewBody
	var appearance: Dictionary = {}:
		set(value):
			appearance = value
			if body != null:
				body.appearance = value
				body.queue_redraw()


	func _init() -> void:
		body = PreviewBody.new()
		body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		body.scale = Vector2(2, 2)
		add_child(body)
		resized.connect(func() -> void: body.position = Vector2(size.x * 0.5, 83))


func runtime() -> WorldContinuityRuntime:
	return _owner.get_ref() as WorldContinuityRuntime


func setup(adapter: WorldContinuityRuntime) -> void:
	_owner = weakref(adapter)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 7
	add_child(layer)
	var screen := Control.new()
	layer.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.theme = UI.create()
	panel.add_theme_stylebox_override("panel", UI.panel(UI.JADE))
	screen.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -260
	panel.offset_right = 260
	panel.offset_top = 72
	panel.offset_bottom = -12
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.custom_minimum_size.x = 470
	scroll.add_child(column)
	UI.label(column, "衣着与随身物 · V", UI.GOLD, 20)
	UI.label(column, "穿着也是生活。换一身衣服，并不会换来职位或通行资格。", UI.MUTED, 13)
	preview = WardrobePreview.new()
	preview.custom_minimum_size.y = 116
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(preview)
	var viewing := HBoxContainer.new()
	column.add_child(viewing)
	preview_direction = OptionButton.new()
	viewing.add_child(preview_direction)
	for direction: String in ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]:
		preview_direction.add_item(direction)
	preview_direction.select(4)
	preview_direction.item_selected.connect(func(_index: int) -> void: update_preview_pose())
	preview_action = OptionButton.new()
	preview_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewing.add_child(preview_action)
	for action: String in ["站立预览", "行走预览", "抬手预览"]:
		preview_action.add_item(action)
	preview_action.item_selected.connect(func(_index: int) -> void: update_preview_pose())
	preview_accessories = CheckBox.new()
	preview_accessories.text = "示例左手剑 / 右腰玉佩（仅预览）"
	column.add_child(preview_accessories)
	preview_accessories.toggled.connect(func(_on: bool) -> void: update_preview_pose())
	choice = OptionButton.new()
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(choice)
	choice.item_selected.connect(func(_index: int) -> void: refresh())
	note = UI.label(column, "", UI.PAPER, 14)
	note.custom_minimum_size.y = 70
	var actions := GridContainer.new()
	actions.columns = 2
	column.add_child(actions)
	for verb: String in ["take", "wear", "remove", "place"]:
		buttons[verb] = UI.button(actions, {"take": "取入随身", "wear": "穿上这件", "remove": "脱下收起", "place": "留在住处"}[verb], act.bind(verb))
	UI.button(actions, "走回住处取放", approach)
	UI.button(actions, "停止整理衣物", cancel)
	observation = UI.label(column, "", UI.MUTED, 13)
	observation.custom_minimum_size.y = 60
	response = UI.label(column, "蓑衣须穿在外层才能挡雨；湿衣放进包中也不会立即干。", UI.WARNING, 14)
	response.custom_minimum_size.y = 44
	UI.button(column, "收起 · V / Esc", panel.hide)
	panel.hide()
	adapter.avatar_changed.connect(reset_observation)
	update_preview_pose()


func update_preview_pose() -> void:
	preview.body.pose = {"direction_index": preview_direction.selected,
		"action": ["idle", "walk", "gesture"][preview_action.selected],
		"time_ms": GameClock.elapsed_ms, "started_ms": GameClock.elapsed_ms,
		"technical_accessories": preview_accessories.button_pressed}
	preview.body.queue_redraw()


func reset_observation() -> void:
	_signature = ""
	panel.hide()
	response.text = "环顾眼前，再整理自己的衣物。"


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_V:
		if panel.visible:
			panel.hide()
		elif runtime().human_player_active():
			panel.show()
			refresh()
			choice.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and panel.visible:
		panel.hide()
		get_viewport().set_input_as_handled()


func selected() -> String:
	return str(choice.get_selected_metadata()) if choice.item_count > 0 else ""


func visible_objects() -> Array[String]:
	var domain: SimClothing = runtime().world_sim.clothing
	var result: Array[String] = []
	for id: String in RegionalSimulation._sorted_keys(domain.objects):
		var object: Dictionary = domain.objects[id]
		if object.owner != "player":
			continue
		if domain.held("player", id) or not str(object.container).begins_with("actor:") and runtime()._home._player.cell.distance_to(domain.cell(str(object.region), str(object.container))) <= float(domain.definitions.interaction_cells):
			result.append(id)
	return result


func refresh() -> void:
	if runtime() != null and runtime().world_sim.settlement.is_pending():
		return
	if not panel.visible:
		return
	if not runtime().human_player_active():
		panel.hide()
		return
	var domain: SimClothing = runtime().world_sim.clothing
	var rows: Array[String] = visible_objects()
	var signature: String = str(rows)
	for id: String in rows:
		signature += str(domain.objects[id])
	if signature != _signature:
		var previous: String = selected()
		choice.clear()
		for id: String in rows:
			var object: Dictionary = domain.objects[id]
			choice.add_item("%s · %s" % [domain.definitions.types[object.type].label, "穿着" if object.worn else "随身" if domain.held("player", id) else "住处存放"])
			choice.set_item_metadata(choice.item_count - 1, id)
			if id == previous:
				choice.select(choice.item_count - 1)
		_signature = signature
	preview.appearance = domain.appearance("player")
	preview.queue_redraw()
	var id: String = selected()
	var busy: bool = not runtime().world_sim.native_action_allowed("player") or runtime()._home.simulation.actor_has_action("player") or not runtime().player_journey.is_empty() or not runtime()._home._player.motion.action.is_empty()
	for verb: String in buttons:
		buttons[verb].disabled = id.is_empty() or busy or not domain._allowed("player", verb, id, "dorm" if verb == "place" else "")
	var detail: String = "附近没有自己的可取衣物；可回住处寻找。"
	if not id.is_empty():
		var item: Dictionary = domain.objects[id]
		detail = "%s\n%s" % [domain.definitions.types[item.type].cue, "摸起来已经湿透，需要晾干。" if int(item.wet) >= int(domain.definitions.wet_threshold) else "略有潮意。" if int(item.wet) > 0 else "摸起来是干的。"]
	note.text = detail + "\n" + domain.status("player")
	var lines: Array[String] = []
	for actor: String in RegionalSimulation._actor_ids(runtime().world_sim.regions):
		if actor == "player":
			continue
		var at: Vector2i = domain.cell(domain.home(actor), "actor:" + actor)
		if at.distance_to(runtime()._home._player.cell) > float(runtime()._home.simulation.config.observation_radius) or runtime()._home._fog != null and not runtime()._home._fog.is_cell_visible(at):
			continue
		var person: Dictionary = runtime().world_sim.regions[domain.home(actor)].actor_state(actor)
		var label: String = str(runtime().settings.runtime.remote_names.get(actor, runtime()._home._content.get_pawn(StringName(person.definition_id)).display_name))
		lines.append(label + "：" + domain.seen_clothing("player", actor))
	observation.text = "眼前衣着\n" + ("\n".join(lines) if not lines.is_empty() else "周围无人可细看；看不到他人的行囊。")


func act(verb: String) -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if not adapter.human_player_active() or not adapter.player_journey.is_empty() or not adapter._home._player.motion.action.is_empty() or not adapter._home._player.motion.velocity.is_zero_approx():
		response.text = "先停稳，再整理衣物。"
		return
	adapter.prepare_player_command()
	var result: Dictionary = adapter.world_sim.clothing.begin("player", verb, selected(), "dorm" if verb == "place" else "")
	response.text = str(result.line)
	refresh()


func approach() -> void:
	response.text = "正在走回住处，抵达后再取放。" if runtime().travel_to("home", runtime().world_sim.clothing.cell("home", "dorm")) else "先完成或停止手头事务；眼下无法走回住处。"
	refresh()


func cancel() -> void:
	if runtime().human_player_active():
		if runtime().world_sim.settlement != null and runtime().world_sim.settlement.is_pending():
			response.text = "当前结算尚未完成，本次停止未受理。"
		else:
			var accepted: bool = runtime().world_sim.clothing.cancel("player")
			response.text = "已停手，未完成的衣物动作不会改变物品位置或穿法。" if accepted else "眼下没有正在进行的衣物动作。"
		refresh()
