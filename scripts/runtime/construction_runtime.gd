class_name ConstructionRuntime
extends CommittedWorldCanvas
## Ground presentation and construction book. All mutations use SimConstruction.

const UI = preload("res://scripts/ui/reol_ui_theme.gd")
const Walls = preload("res://scripts/world/wall_visuals.gd")
var panel: PanelContainer
var site_choice: OptionButton
var rotation_choice: OptionButton
var slot_choice: OptionButton
var item_choice: OptionButton
var recipe_choice: OptionButton
var amount_choice: SpinBox
var purpose_choice: OptionButton
var _grid_site: String = ""
var type_choice: OptionButton
var project_choice: OptionButton
var occupant_choice: OptionButton
var grid: GridContainer
var selection: Vector2i = Vector2i(-1, -1)
var _summary: Label
var _details: Label
var _space: Label
var _bed_details: Label
var _reply: Label
var _owner: WeakRef
var _cell_buttons: Dictionary = {}
var _observed_domain: SimConstruction
var _observed_world: RegionalSimulation
var _bed_widgets: Array[Control] = []
var _seat_button: Button
var _storage_widgets: Array[Control] = []
var _work_widgets: Array[Control] = []
var _pending_sight_cells: Dictionary[Vector2i, bool] = {}


func runtime() -> WorldContinuityRuntime:
	return _owner.get_ref() as WorldContinuityRuntime


func domain() -> SimConstruction:
	return runtime().world_sim.construction


func setup(adapter: WorldContinuityRuntime) -> void:
	_owner = weakref(adapter)
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 1
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	panel = PanelContainer.new()
	panel.theme = UI.create()
	panel.add_theme_stylebox_override("panel", UI.panel(UI.GOLD))
	screen.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -364
	panel.offset_right = -16
	panel.offset_top = 90
	panel.offset_bottom = -12
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	scroll.add_child(column)
	UI.label(column, "营造 · 工地与家具", UI.GOLD, 20)
	_summary = UI.label(column, "", UI.MUTED, 13)
	_summary.custom_minimum_size = Vector2(300, 48)
	var visit := HBoxContainer.new()
	column.add_child(visit)
	UI.button(visit, "走向柴粮库", approach_store)
	UI.button(visit, "划定工地", register_yard)
	site_choice = OptionButton.new()
	column.add_child(site_choice)
	site_choice.item_selected.connect(_site_selected)
	purpose_choice = OptionButton.new()
	column.add_child(purpose_choice)
	for row: Array in [["dwelling", "起居区域"], ["workshop", "作业区域"], ["storage", "储藏区域"], ["garden", "园圃区域"], ["restricted", "限制区域"]]:
		purpose_choice.add_item(row[1])
		purpose_choice.set_item_metadata(purpose_choice.item_count - 1, row[0])
	UI.button(column, "指定本工地用途", designate_site)
	UI.button(column, "取消本工地用途", clear_site_zone)
	grid = GridContainer.new()
	grid.columns = int(domain().definitions.site.width)
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	column.add_child(grid)
	type_choice = OptionButton.new()
	column.add_child(type_choice)
	for id: String in domain().definitions.types:
		var rule: Dictionary = domain().definitions.types[id]
		type_choice.add_item("%s · %s%d · %d分钟" % [rule.label, _item_label(str(rule.item)), int(rule.amount), int(rule.work_ms) / 60000])
		type_choice.set_item_metadata(type_choice.item_count - 1, id)
	type_choice.item_selected.connect(func(_index: int) -> void: select_cell(selection))
	rotation_choice = OptionButton.new()
	column.add_child(rotation_choice)
	for angle: int in [0, 90, 180, 270]:
		rotation_choice.add_item("朝向 %d°" % angle)
	UI.button(column, "在选中格画蓝图", place_selected)
	project_choice = OptionButton.new()
	column.add_child(project_choice)
	project_choice.item_selected.connect(_project_selected)
	var actions := GridContainer.new()
	actions.columns = 3
	column.add_child(actions)
	UI.button(actions, "亲自施工", act.bind("build"))
	UI.button(actions, "开 / 关门", operate_door)
	UI.button(actions, "拆除", act.bind("demolish"))
	UI.button(actions, "撤蓝图", revoke)
	UI.button(actions, "余料回库", act.bind("recover"))
	UI.button(actions, "停手", stop)
	_details = UI.label(column, "", UI.PAPER, 13)
	_details.custom_minimum_size = Vector2(300, 62)
	_space = UI.label(column, "", UI.MUTED, 13)
	_space.custom_minimum_size = Vector2(300, 34)
	var bed_start: int = column.get_child_count()
	UI.label(column, "床铺 · 本院使用安排", UI.GOLD, 15)
	occupant_choice = OptionButton.new()
	column.add_child(occupant_choice)
	occupant_choice.add_item("本院共用")
	occupant_choice.set_item_metadata(0, "")
	for actor: String in runtime().world_sim.resting.definitions.members:
		occupant_choice.add_item(_actor_name(actor))
		occupant_choice.set_item_metadata(occupant_choice.item_count - 1, actor)
	var bed_actions := HBoxContainer.new()
	column.add_child(bed_actions)
	UI.button(bed_actions, "安排床位", assign_bed)
	UI.button(bed_actions, "到床上休息", use_bed)
	_bed_details = UI.label(column, "", UI.PAPER, 13)
	_bed_details.custom_minimum_size = Vector2(300, 38)
	for widget: Control in column.get_children().slice(bed_start):
		_bed_widgets.append(widget)
	UI.label(column, "家具使用", UI.GOLD, 15)
	slot_choice = OptionButton.new()
	column.add_child(slot_choice)
	_seat_button = UI.button(column, "到座位坐一会", use_facility.bind("sit"))
	var storage_row := HBoxContainer.new()
	column.add_child(storage_row)
	_storage_widgets.append(storage_row)
	item_choice = OptionButton.new()
	storage_row.add_child(item_choice)
	for item: String in ["wood", "stone", "grain", "water", "meal", "herb", "dried_herb", "coin"]:
		item_choice.add_item(_item_label(item))
		item_choice.set_item_metadata(item_choice.item_count - 1, item)
	amount_choice = SpinBox.new()
	amount_choice.min_value = 1
	amount_choice.max_value = 1000
	amount_choice.value = 1
	storage_row.add_child(amount_choice)
	var storage_actions := HBoxContainer.new()
	column.add_child(storage_actions)
	_storage_widgets.append(storage_actions)
	UI.button(storage_actions, "放入", use_facility.bind("deposit"))
	UI.button(storage_actions, "取出", use_facility.bind("withdraw"))
	recipe_choice = OptionButton.new()
	column.add_child(recipe_choice)
	_work_widgets.append(recipe_choice)
	_work_widgets.append(UI.button(column, "用此工作台加工一批", produce_at_facility))
	_reply = UI.label(column, "工地公料由获准工程使用；可留给负责此事的同门。", UI.WARNING, 13)
	_reply.custom_minimum_size = Vector2(300, 44)
	UI.button(column, "收起 · N / Esc", panel.hide)
	panel.hide()
	for other: Control in [adapter.heat_method_adapter.panel, adapter.interaction_adapter.panel, adapter.object_adapter.panel, adapter.soul_adapter.panel, adapter.avian_adapter.panel, adapter.sparring_adapter.panel]:
		other.visibility_changed.connect(_other_panel_changed.bind(other))
	adapter.avatar_changed.connect(reset_observation)
	GameClock.time_advanced.connect(_on_advanced)
	if adapter.home_runtime()._fog != null:
		adapter.home_runtime()._fog.visibility_updated.connect(_on_visibility_updated)
	_bind_structure_changes()


func _bind_structure_changes() -> void:
	if _observed_domain != null and _observed_domain.structures_changed.is_connected(_on_structures_changed):
		_observed_domain.structures_changed.disconnect(_on_structures_changed)
	if _observed_world != null and _observed_world.action_finished.is_connected(_on_action_finished):
		_observed_world.action_finished.disconnect(_on_action_finished)
	if _observed_world != null and _observed_world.boundary_settled.is_connected(_on_boundary_settled):
		_observed_world.boundary_settled.disconnect(_on_boundary_settled)
	_observed_world = runtime().world_sim
	_observed_world.action_finished.connect(_on_action_finished)
	_observed_world.boundary_settled.connect(_on_boundary_settled)
	_observed_domain = domain()
	_observed_domain.structures_changed.connect(_on_structures_changed)


func _on_structures_changed(cells: Array[Vector2i]) -> void:
	if runtime().world_sim.settlement.is_pending():
		for cell: Vector2i in cells:
			_pending_sight_cells[cell] = true
		return
	runtime().home_runtime()._world.notify_sight_obstacles_changed(cells)
	queue_redraw()


func _on_boundary_settled(_at_ms: int) -> void:
	if GameClock.is_advancing():
		return # Several world boundaries can belong to one public clock slice.
	_flush_sight_changes()


func _flush_sight_changes() -> void:
	if not _pending_sight_cells.is_empty():
		var cells: Array[Vector2i] = []
		cells.assign(_pending_sight_cells.keys())
		_pending_sight_cells.clear()
		runtime().home_runtime()._world.notify_sight_obstacles_changed(cells)
	refresh_choices()
	refresh()
	queue_redraw()


func _on_visibility_updated() -> void:
	# A paused clock may never emit time_advanced after the delayed fog update.
	# Rebuild the visible list as well as the drawing and selected-cell details.
	if panel.visible:
		refresh_choices()
		refresh()
	queue_redraw()


func show_panel() -> void:
	if not runtime().human_player_active():
		return
	for other: Control in [runtime().heat_method_adapter.panel, runtime().interaction_adapter.panel, runtime().object_adapter.panel, runtime().soul_adapter.panel, runtime().avian_adapter.panel, runtime().sparring_adapter.panel]:
		other.hide()
	panel.show()
	refresh_choices()
	if not domain().site_contains(selection) and not domain().sites.is_empty():
		selection = SimRouteTravel.cell(domain().projects[selected_project()].cell) if domain().projects.has(selected_project()) else domain().site_bounds(selected_site()).position
	refresh()
	if is_inside_tree():
		type_choice.grab_focus()
	queue_redraw()


func _other_panel_changed(other: Control) -> void:
	if other.visible and panel.visible:
		panel.hide()
		queue_redraw()


func approach_store() -> void:
	var cell: Vector2i = SimRouteTravel.cell(runtime().world_sim.regions[domain().definitions.site.region].places[domain().definitions.site.source].cell)
	_reply.text = "正在前往柴粮库。" if runtime().travel_to(str(domain().definitions.site.region), cell) else "先停下手头的事情，再走向库房。"


func find_yard_origin() -> Vector2i:
	var source: Vector2i = SimRouteTravel.cell(runtime().world_sim.regions[domain().definitions.site.region].places[domain().definitions.site.source].cell)
	var size := Vector2i(int(domain().definitions.site.width), int(domain().definitions.site.height))
	var radius: int = int(domain().definitions.site.source_cells)
	for ring: int in range(1, radius + 1):
		for y: int in range(-ring, ring + 1):
			for x: int in range(-ring, ring + 1):
				if maxi(absi(x), absi(y)) != ring:
					continue
				var origin: Vector2i = source + Vector2i(x, y)
				if origin.distance_to(source) > radius:
					continue
				var valid: bool = true
				for cell: Vector2i in SimConstruction.cells_in(Rect2i(origin, size)):
					if not domain().terrain_open(cell) or domain().protected_cell(cell) or domain().site_contains(cell):
						valid = false
						break
				if valid and not runtime()._find_path(source, origin).is_empty():
					return origin
	return Vector2i(-1, -1)


func register_yard() -> void:
	if not _available():
		return
	var origin: Vector2i = find_yard_origin()
	var result: Dictionary = domain().register_site("player", origin)
	_reply.text = str(result.line)
	if result.ok:
		selection = origin
		_refresh_sites(str(result.site))
	refresh_choices()
	refresh()
	queue_redraw()


func _available() -> bool:
	if not runtime().human_player_active() or not runtime().player_journey.is_empty() or not runtime()._home._player.motion.action.is_empty():
		_reply.text = "先停稳，再在工地登记或动手。"
		return false
	runtime().prepare_player_command()
	return true


func selected_project() -> String:
	return str(project_choice.get_selected_metadata()) if project_choice.item_count > 0 else ""


func place_selected() -> void:
	if not _available():
		return
	var result: Dictionary = domain().place("player", str(type_choice.get_selected_metadata()), selection, rotation_choice.selected)
	_reply.text = str(result.line)
	refresh_choices(str(result.get("project", "")))
	refresh()
	queue_redraw()


func act(kind: String) -> void:
	if not _available():
		return
	var result: Dictionary = domain().begin("player", selected_project(), kind)
	_reply.text = str(result.line)
	if result.ok:
		runtime()._home._player.motion.velocity = Vector2.ZERO
	runtime()._refresh_panel()
	refresh()


func operate_door() -> void:
	var id: String = selected_project()
	act("close" if domain().projects.has(id) and domain().projects[id].open else "open")


func revoke() -> void:
	if not _available():
		return
	_reply.text = str(domain().cancel_project("player", selected_project()).line)
	refresh_choices()
	refresh()
	queue_redraw()


func stop() -> void:
	var accepted: bool = runtime().stop_player_action()
	_reply.text = "已停下；工料、工时与已恢复的精神继续保留。" if accepted else "当前结算尚未完成，本次停止未受理。"
	refresh()


func assign_bed() -> void:
	if not _available():
		return
	_reply.text = str(runtime().world_sim.resting.assign("player", selected_project(), str(occupant_choice.get_selected_metadata())).line)
	refresh()


func use_bed() -> void:
	if not _available():
		return
	var result: Dictionary = runtime().world_sim.resting.begin("player", selected_project())
	_reply.text = str(result.line)
	if result.ok:
		runtime()._home._player.motion.velocity = Vector2.ZERO
	runtime()._refresh_panel()
	refresh()


func _actor_name(actor: String) -> String:
	return String(runtime()._home._content.get_pawn(StringName(runtime().world_sim.regions.home.actors[actor].definition_id)).display_name)


func refresh_choices(preferred: String = "") -> void:
	if runtime().world_sim.settlement.is_pending():
		return
	var previous: String = selected_project()
	project_choice.clear()
	for id: String in domain().projects:
		var project: Dictionary = domain().projects[id]
		if not domain().can_observe("player", SimRouteTravel.cell(project.cell)) or not _visible(SimRouteTravel.cell(project.cell)):
			continue
		project_choice.add_item("%s · %s" % [domain().definitions.types[project.type].label, str(SimRouteTravel.cell(project.cell))])
		project_choice.set_item_metadata(project_choice.item_count - 1, id)
		if id == (previous if preferred.is_empty() else preferred):
			project_choice.select(project_choice.item_count - 1)
	_refresh_sites()
	if _grid_site != selected_site() or _cell_buttons.is_empty():
		_grid_site = selected_site()
		for button: Button in _cell_buttons.values():
			grid.remove_child(button)
			button.queue_free()
		_cell_buttons.clear()
		if domain().sites.has(_grid_site):
			grid.columns = domain().site_bounds(_grid_site).size.x
			for cell: Vector2i in SimConstruction.cells_in(domain().site_bounds(_grid_site)):
				var button: Button = UI.button(grid, "·", select_cell.bind(cell))
				button.custom_minimum_size = Vector2(40, 25)
				button.add_theme_font_size_override("font_size", 14)
				button.tooltip_text = "工地格 %s" % str(cell)
				_cell_buttons[cell] = button


func select_cell(cell: Vector2i) -> void:
	if not domain().site_contains(cell) or not _visible(cell):
		return
	selection = cell
	var id: String = domain().project_at(cell, _selection_layer())
	if id.is_empty():
		var ids: Array = domain().projects.keys()
		ids.reverse()
		for candidate: String in ids:
			if SimRouteTravel.cell(domain().projects[candidate].cell) == cell and (domain().definitions.types[domain().projects[candidate].type].layer == "roof") == (_selection_layer() == "roof"):
				id = candidate
				break
	refresh_choices(id)
	refresh()
	queue_redraw()


func _project_selected(_index: int) -> void:
	var id: String = selected_project()
	if domain().projects.has(id):
		selection = SimRouteTravel.cell(domain().projects[id].cell)
	refresh()
	queue_redraw()


func _selection_layer() -> String:
	return str(domain().definitions.types[type_choice.get_selected_metadata()].layer)


func refresh() -> void:
	if panel == null or not panel.visible:
		return
	if runtime().world_sim.settlement.is_pending():
		return
	if not runtime().human_player_active():
		panel.hide()
		return
	var is_near: bool = not domain().sites.is_empty() and domain().can_observe("player", domain().site_bounds(selected_site()).get_center())
	_summary.text = "先走到库房附近，划定获准宗门工地。" if domain().sites.is_empty() else "工地 · 宗门所有。选格：%s\n□ 空地 ◇ 蓝图 ■ 墙 + 关门 / 开门 床" % str(selection) if is_near else "工地已登记；走近后查看当前施工情况。"
	grid.visible = is_near
	for cell: Vector2i in _cell_buttons:
		var id: String = domain().project_at(cell, _selection_layer())
		var marker: String = "□"
		if not id.is_empty():
			var project: Dictionary = domain().projects[id]
			marker = "◇" if project.state == "blueprint" else "顶" if _selection_layer() == "roof" else "床" if domain().is_bed(id) else "/" if project.open else "+" if domain().definitions.types[project.type].door else "■"
		var button: Button = _cell_buttons[cell]
		button.text = marker if _visible(cell) else "?"
		button.disabled = not _visible(cell)
		button.modulate = UI.GOLD if cell == selection else Color.WHITE
	_details.text = "蓝图留在现场，负责此事的同门看见后会按自己的状况接手。"
	_space.text = "在场选一格，查看墙门围合。"
	_bed_details.text = "选中建好的木床后，可安排或亲自使用。矮床可跨越，不阻断道路。"
	if domain().site_contains(selection) and _visible(selection) and domain().can_observe("player", selection):
		var space: Dictionary = domain().space_at(selection)
		_space.text = _describe_space(space)
		if domain().roofed(selection):
			_space.text = ("此格是墙或门口。" if space.is_empty() else "围合空间 · %d格。" % int(space.area) if space.enclosed else "开放空间。") + "\n此格有实际木屋面遮雨，不等于全屋保温。"
	var id: String = selected_project()
	if domain().projects.has(id) and domain().can_observe("player", SimRouteTravel.cell(domain().projects[id].cell)) and _visible(SimRouteTravel.cell(domain().projects[id].cell)):
		var project: Dictionary = domain().projects[id]
		var definition: Dictionary = domain().definitions.types[project.type]
		_details.text = "%s · %s\n耐久 %d/%d · 防护 %d\n%s" % [definition.label, str(selection), int(project.hp), int(definition.max_hp), int(definition.armor), str(project.line)]
		for job: Dictionary in domain().active.values():
			if job.project == id:
				var sim: RefCounted = runtime().world_sim.regions[domain().definitions.site.region]
				var label: String = String(runtime()._home._content.get_pawn(StringName(sim.actors[job.actor].definition_id)).display_name)
				var phase: String = "搬运" if str(job.phase).begins_with("to_") else "取料" if job.phase == "pickup" else "动工"
				_details.text = "%s正在%s，当前步骤还需%d秒。\n%s" % [label, phase, maxi(0, ceili(float(int(job.due_ms) - runtime().world_sim.elapsed_ms) / 1000.0)), str(project.line)]
		if domain().is_bed(id):
			var resting: SimResting = runtime().world_sim.resting
			var assigned: String = str(resting.allocations.get(id, ""))
			_bed_details.text = "本院共用。" if assigned.is_empty() else "安排给%s使用。" % _actor_name(assigned)
			for job: Dictionary in resting.active.values():
				if job.bed == id and _visible(SimRouteTravel.cell(runtime().world_sim.regions.home.actors[job.actor].cell)):
					_bed_details.text += "\n%s%s。" % [_actor_name(job.actor), "正在休息" if job.phase == "sleep" else "正在起身让位" if job.phase == "leave" else "正前来休息"]
			_bed_details.text += "\n到床后持续恢复精神，肚饿或精神充足会起身。"
			_bed_details.text += "\n床铺潮湿，休息恢复较慢。" if runtime().world_sim.weather.bed_is_wet(id) else "\n床铺干燥。"
	_refresh_facilities()


func reset_observation() -> void:
	clear_committed_canvas()
	_pending_sight_cells.clear()
	_bind_structure_changes()
	panel.hide()
	project_choice.clear()
	site_choice.clear()
	_grid_site = ""
	selection = Vector2i(-1, -1)
	for button: Button in _cell_buttons.values():
		button.queue_free()
	_cell_buttons.clear()
	_reply.text = "在场查看工地，才能知道正在发生的事。"
	queue_redraw()


func _describe_space(space: Dictionary) -> String:
	if space.is_empty():
		return "此格是墙或门口。"
	if not space.enclosed:
		return "开放空间 · 未覆顶；墙门闭合后再查看围合。"
	var doorway: String = "无门口" if int(space.doors) == 0 else "门口闭合"
	if int(space.open_doors) > 0:
		doorway = "%d扇门敞开" % int(space.open_doors)
	return "围合空间 · %d格 · %s · %s\n未覆顶，不提供防雨或保温。" % [int(space.area), "地面平整" if space.flat else "地面有高差", doorway]


func _on_advanced(_from: int, _to: int) -> void:
	_flush_sight_changes()
	refresh()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not runtime().human_player_active():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_N:
			if panel.visible:
				panel.hide()
			else:
				show_panel()
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and panel.visible:
			panel.hide()
			queue_redraw()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and panel.visible:
		var point: Vector2 = get_global_mouse_position()
		for cell: Vector2i in _cell_buttons:
			if Rect2(_point(cell) - Vector2.ONE * TileGrid.TILE_SIZE / 2.0, Vector2.ONE * TileGrid.TILE_SIZE).has_point(point):
				select_cell(cell)
				get_viewport().set_input_as_handled()
				break


func _point(cell: Vector2i) -> Vector2:
	return TileGrid.cell_to_world(cell) - Vector2(0, runtime()._home._world.get_elevation(cell) * ReolWorld.ELEVATION_PX)


func _visible(cell: Vector2i) -> bool:
	return runtime()._home._fog == null or runtime()._home._fog.is_cell_visible(cell)


func _build_canvas() -> void:
	if _owner == null or runtime() == null:
		return
	if panel.visible and not domain().sites.is_empty():
		for cell: Vector2i in SimConstruction.cells_in(domain().site_bounds(selected_site())):
			if _visible(cell):
				var space: Dictionary = domain().space_at(cell)
				if bool(space.get("enclosed", false)):
					capture_rect(Rect2(_point(cell) - Vector2(30, 30), Vector2(60, 60)), Color(UI.JADE, 0.13))
				capture_rect(Rect2(_point(cell) - Vector2(29, 29), Vector2(58, 58)), Color(UI.GOLD, 0.18), false, 1)
		if domain().site_contains(selection) and _visible(selection):
			capture_rect(Rect2(_point(selection) - Vector2(29, 29), Vector2(58, 58)), UI.GOLD, false, 2)
	var sim: RefCounted = runtime().world_sim.regions[domain().definitions.site.region]
	for id: String in domain().projects:
		var project: Dictionary = domain().projects[id]
		var definition: Dictionary = domain().definitions.types[project.type]
		for cell: Vector2i in domain().project_cells(id):
			if not _visible(cell):
				continue
			var p: Vector2 = _point(cell)
			if project.state == "blueprint":
				capture_rect(Rect2(p - Vector2(24, 18), Vector2(48, 36)), Color(UI.JADE, 0.25))
				capture_rect(Rect2(p - Vector2(24, 18), Vector2(48, 36)), UI.JADE, false, 2)
			elif project.state == "ruined":
				capture_rect(Rect2(p - Vector2(20, 12), Vector2(40, 24)), Color("635e56"))
			elif project.state == "built":
				if definition.layer == "roof":
					_draw_roof(p)
				elif domain().is_bed(id):
					_draw_bed(p)
				elif definition.facts.wall_connection:
					var mask: int = SimStructureQuery.wall_mask(runtime().world_sim, cell, _visible)
					if bool(definition.door):
						capture_custom(Callable(Walls, "draw_door").bind(self, p, mask, bool(project.open)))
					else:
						capture_custom(Callable(Walls, "draw_wall").bind(self, p, mask))
						if not definition.facts.sight_blocked:
							capture_rect(Rect2(p + Vector2(-12, -14), Vector2(24, 18)), Color("8ca7a4"))
				else:
					_draw_furniture(p, definition, int(project.rotation))
		var raw: Array = sim.actors[project.carrier].cell if not str(project.carrier).is_empty() else project.material_cell
		var material_cell: Vector2i = SimRouteTravel.cell(raw)
		if sim.inventory.quantity(id, str(definition.item)) > 0 and _visible(material_cell):
			var p: Vector2 = _point(material_cell) + Vector2(12, 16)
			for i: int in 3:
				capture_line(p + Vector2(-8, i * 4), p + Vector2(8, i * 4 - 3), Color("ae8553"), 4)


func _draw_roof(p: Vector2) -> void:
	var bounds := Rect2(p + Vector2(-31, -48), Vector2(62, 62))
	capture_rect(bounds, Color(0.54, 0.53, 0.38, 0.22))
	capture_rect(bounds, Color("b7ad7d"), false, 2)
	for x: int in range(-22, 28, 10):
		capture_line(p + Vector2(x, -47), p + Vector2(x, 13), Color(0.74, 0.72, 0.5, 0.30), 2)


func _draw_bed(p: Vector2) -> void:
	_draw_shadow(p)
	capture_rect(Rect2(p + Vector2(-20, -25), Vector2(40, 49)), Color("68492f"))
	capture_rect(Rect2(p + Vector2(-16, -21), Vector2(32, 41)), Color("80928b"))
	capture_rect(Rect2(p + Vector2(-13, -19), Vector2(26, 10)), Color("d6cdb1"))
	capture_line(p + Vector2(-21, -26), p + Vector2(21, -26), Color("b49666"), 5)
	capture_line(p + Vector2(-21, 23), p + Vector2(21, 23), Color("b49666"), 4)


func _draw_shadow(p: Vector2) -> void:
	capture_rect(Rect2(p + Vector2(-29, 14), Vector2(61, 10)), Color(0, 0, 0, 0.23))


func selected_site() -> String:
	return str(site_choice.get_selected_metadata()) if site_choice != null and site_choice.item_count > 0 else "sect_yard"


func _refresh_sites(preferred: String = "") -> void:
	var previous: String = selected_site() if preferred.is_empty() else preferred
	site_choice.clear()
	for id: String in domain().sites:
		var origin: Vector2i = domain().site_bounds(id).position
		site_choice.add_item("工地 %s" % str(origin))
		site_choice.set_item_metadata(site_choice.item_count - 1, id)
		if id == previous: site_choice.select(site_choice.item_count - 1)


func _site_selected(_index: int) -> void:
	selection = domain().site_bounds(selected_site()).position
	refresh_choices()
	refresh()
	queue_redraw()


func designate_site() -> void:
	if not _available(): return
	_reply.text = str(domain().designate("player", domain().site_bounds(selected_site()), str(purpose_choice.get_selected_metadata())).line)
	refresh()


func _refresh_facilities() -> void:
	var previous: String = str(slot_choice.get_selected_metadata()) if slot_choice.item_count > 0 else ""
	slot_choice.clear()
	recipe_choice.clear()
	var id: String = selected_project()
	var visible_project: bool = domain().projects.has(id) and _visible(SimRouteTravel.cell(domain().projects[id].cell))
	var capabilities: Dictionary = domain().definitions.types[domain().projects[id].type].capabilities if visible_project else {}
	for widget: Control in _bed_widgets: widget.visible = visible_project and domain().is_bed(id)
	_seat_button.visible = capabilities.has("seat")
	for widget: Control in _storage_widgets: widget.visible = capabilities.has("storage")
	for widget: Control in _work_widgets: widget.visible = capabilities.has("workbench")
	slot_choice.visible = visible_project and not domain().operation_slots(id).is_empty()
	if not visible_project: return
	for row: Dictionary in domain().operation_slots(id):
		var label: String = "座位" if row.capability == "seat" else "取放位置" if row.capability == "storage" else "作业位置"
		slot_choice.add_item("%s · %s" % [label, str(row.cell)])
		slot_choice.set_item_metadata(slot_choice.item_count - 1, row.id)
		if row.id == previous: slot_choice.select(slot_choice.item_count - 1)
	var capability: Dictionary = domain().definitions.types[domain().projects[id].type].capabilities.get("workbench", {})
	for recipe: String in capability.get("recipes", []):
		recipe_choice.add_item(str(runtime().world_sim.personal_production.definitions.recipes[recipe].label))
		recipe_choice.set_item_metadata(recipe_choice.item_count - 1, recipe)


func use_facility(kind: String) -> void:
	if not _available() or slot_choice.item_count == 0: return
	var item: String = "" if kind == "sit" else str(item_choice.get_selected_metadata())
	var amount: int = 0 if kind == "sit" else int(amount_choice.value)
	var result: Dictionary = runtime().world_sim.facility_use.begin("player", selected_project(), str(slot_choice.get_selected_metadata()), kind, item, amount)
	if result.ok: GameClock.cancel_wait()
	_reply.text = str(result.line)
	runtime()._refresh_panel()
	refresh()


func produce_at_facility() -> void:
	if not _available() or recipe_choice.item_count == 0: return
	_reply.text = str(runtime().world_sim.personal_production.create("player", str(domain().definitions.site.region), str(recipe_choice.get_selected_metadata()), selected_project()).line)
	refresh()


func _draw_furniture(p: Vector2, definition: Dictionary, rotation: int) -> void:
	_draw_shadow(p)
	var color := Color("866340")
	if definition.capabilities.has("storage"): color = Color("a48754")
	elif definition.capabilities.has("workbench"): color = Color("69777a")
	elif definition.capabilities.has("seat"): color = Color("aa916b")
	capture_rect(Rect2(p - Vector2(22, 19), Vector2(44, 38)), color)
	capture_rect(Rect2(p - Vector2(22, 19), Vector2(44, 38)), Color("3e352d"), false, 2)
	var facing: Vector2i = SimConstructionGeometry.direction(Vector2i.UP, rotation)
	capture_line(p, p + Vector2(facing) * 15.0, UI.PAPER, 2)


func _item_label(item: String) -> String:
	return str({"wood": "木料", "stone": "石料", "grain": "谷物", "water": "水", "meal": "饭食", "herb": "药草", "dried_herb": "焙药", "coin": "钱币"}.get(item, "材料"))


func _on_action_finished(outcome: Dictionary) -> void:
	if GameClock.is_advancing():
		return # The clock's completed projection refreshes the same fact once.
	if outcome.actor == "player" and outcome.domain in ["construction", "facility_use"]:
		runtime()._refresh_panel()
		refresh()


func clear_site_zone() -> void:
	if not _available(): return
	var bounds: Rect2i = domain().site_bounds(selected_site())
	for id: String in domain().zones.keys():
		var zone: Dictionary = domain().zones[id]
		if SimRouteTravel.cell(zone.origin) == bounds.position and SimRouteTravel.cell(zone.size) == bounds.size:
			_reply.text = str(domain().clear_zone("player", id).line)
	refresh()
