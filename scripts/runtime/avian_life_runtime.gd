class_name AvianLifeRuntime
extends CommittedWorldCanvas
## Local sight, intent routing and nonhuman views; persistent life stays in sim.

const UI = preload("res://scripts/ui/reol_ui_theme.gd")
var selected_bird: String = ""
var panel: PanelContainer
var _title: Label
var _line: Label
var _notice: Label
var _approach: Button
var _feed: Button
var _ask: Button
var _last_notice: String = ""
var _owner: WeakRef


func runtime() -> WorldContinuityRuntime:
	return _owner.get_ref() as WorldContinuityRuntime if _owner != null else null


func setup(adapter: WorldContinuityRuntime) -> void:
	_owner = weakref(adapter)
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 14
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	panel = PanelContainer.new()
	panel.theme = UI.create()
	panel.add_theme_stylebox_override("panel", UI.panel(UI.JADE))
	screen.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -230
	panel.offset_right = 230
	panel.offset_top = 110
	var column := VBoxContainer.new()
	panel.add_child(column)
	_title = UI.label(column, "草木间的邻居", UI.GOLD, 20)
	_line = UI.label(column, "", UI.PAPER, 16)
	_line.custom_minimum_size = Vector2(430, 72)
	_approach = UI.button(column, "走近它", submit.bind("approach"))
	var row := HBoxContainer.new()
	column.add_child(row)
	_feed = UI.button(row, "撒下一份饭粮", submit.bind("feed"))
	_ask = UI.button(row, "请它捎一枝药", submit.bind("ask_herb"))
	_notice = UI.label(column, "", UI.WARNING, 14)
	_notice.custom_minimum_size = Vector2(430, 54)
	UI.label(column, "先在生活页取一份饭，带到结籽草丛旁投喂。\n它先顾自己的生活；衔来的药会留在当地药圃。", UI.MUTED, 13)
	UI.button(column, "收起 · B / Esc", panel.hide)
	panel.hide()
	GameClock.time_advanced.connect(_on_time_advanced)
	refresh()


func select_bird(id: String) -> bool:
	if not _visible(id):
		return false
	selected_bird = id
	_last_notice = ""
	var adapter: WorldContinuityRuntime = runtime()
	if adapter.object_adapter != null:
		adapter.object_adapter.panel.hide()
	if adapter.sparring_adapter != null:
		adapter.sparring_adapter.panel.hide()
	panel.show()
	refresh()
	return true


func submit(verb: String) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter != null and not adapter.human_player_active():
		return SimAvianLife.response(false, "雀身用自己的行动与邻居相处。")
	if adapter == null or not _visible(selected_bird):
		return SimAvianLife.response(false, "眼下没看见它；先找回近处的身影。")
	adapter.prepare_player_command()
	var domain: SimAvianLife = adapter.world_sim.avian_life
	var result: Dictionary
	if verb == "approach":
		var target: Vector2i = adapter._home._world.find_walkable_near(domain.body_cell(selected_bird), 5)
		var accepted: bool = adapter.travel_to(str(domain.birds[selected_bird].region), target)
		result = SimAvianLife.response(accepted, "正在走近；它也会继续自己的生活。" if accepted else "眼下无法走过去，请先结束手头的事。")
	elif not adapter.player_journey.is_empty() or not adapter._home._player.motion.action.is_empty():
		result = SimAvianLife.response(false, "先站稳，再慢慢投食或比划请求。")
	elif verb == "feed":
		result = domain.offer_grain("player", selected_bird)
	elif verb == "ask_herb":
		var source: String = domain._nearest_site(selected_bird, "crevice", true)
		result = adapter.interaction_adapter.submit(SimAvianLife.subject_id(selected_bird), "fetch_herb", {"kind": "avian_site", "id": source}, "gesture")
	else:
		result = SimAvianLife.response(false, "暂时不会这样与它打交道。")
	_last_notice = str(result.line)
	adapter._refresh_panel()
	refresh()
	return result


func reset_observation() -> void:
	if not can_refresh_canvas():
		return
	clear_committed_canvas()
	selected_bird = ""
	_last_notice = ""
	panel.hide()
	queue_redraw()


func refresh() -> void:
	_notice.text = _last_notice
	if not can_refresh_canvas():
		return
	queue_redraw()
	if not panel.visible:
		return
	var adapter: WorldContinuityRuntime = runtime()
	var view: Dictionary = adapter.world_sim.avian_life.describe("player", selected_bird)
	var seeing: bool = bool(view.get("known", false)) and _visible(selected_bird)
	_title.text = str(view.get("label", "草木间的邻居")) if seeing else "身影已远"
	_line.text = str(view.line) if seeing else "它已离开视线；你不知道它此刻在做什么。"
	var near: bool = seeing and bool(view.get("near", false))
	_approach.visible = seeing and not near
	_feed.disabled = not near
	_ask.disabled = not near


func _on_time_advanced(_from: int, _to: int) -> void:
	refresh()


func _visible(id: String) -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter != null and not adapter.human_player_active():
		var domain: SimAvianLife = adapter.world_sim.avian_life
		return domain.birds.has(id) and adapter.controlled_cell().distance_to(domain.body_cell(id)) <= float(domain.rules().observation_cells) and (adapter._home._fog == null or adapter._home._fog.is_cell_visible(domain.body_cell(id)))
	if adapter == null or not adapter.world_sim.avian_life.visible_to("player", id):
		return false
	return adapter._home._fog == null or adapter._home._fog.is_cell_visible(adapter.world_sim.avian_life.body_cell(id))


func _bird_point(id: String) -> Vector2:
	var adapter: WorldContinuityRuntime = runtime()
	var domain: SimAvianLife = adapter.world_sim.avian_life
	var body: Dictionary = domain.birds[id]
	return SimAvianLife.point(body) - Vector2(0, adapter._home._world.get_elevation(domain.body_cell(id)) * ReolWorld.ELEVATION_PX + int(body.altitude) * ReolWorld.ALTITUDE_PX + 5)


func _unhandled_input(event: InputEvent) -> void:
	if not runtime().human_player_active():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and panel.visible:
			panel.hide()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_B:
			if panel.visible:
				panel.hide()
			else:
				for id: String in SimAvianLife.sorted_keys(runtime().world_sim.avian_life.birds):
					if select_bird(id):
						break
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for id: String in runtime().world_sim.avian_life.birds:
			if _visible(id) and get_global_mouse_position().distance_to(_bird_point(id)) <= 18.0 and select_bird(id):
				get_viewport().set_input_as_handled()
				break


func _build_canvas() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or adapter.world_sim == null:
		return
	var domain: SimAvianLife = adapter.world_sim.avian_life
	var font: Font = ThemeDB.fallback_font
	for id: String in domain.sites:
		var site: Dictionary = domain.sites[id]
		var cell: Vector2i = SimRouteTravel.cell(site.cell)
		if adapter._home._fog != null and not adapter._home._fog.is_cell_visible(cell):
			continue
		var point: Vector2 = TileGrid.cell_to_world(cell) - Vector2(0, adapter._home._world.get_elevation(cell) * ReolWorld.ELEVATION_PX)
		if site.type == "seeds":
			for x: int in 5:
				var tip: Vector2 = point + Vector2(x * 4 - 8, -7 - (x % 2) * 5)
				capture_line(point + Vector2(x * 3 - 6, 4), tip, Color("#b5bd75"), 1.5)
				capture_circle(tip, 2, Color("#d4bc6d"))
		elif site.type == "roost":
			capture_line(point + Vector2(0, 5), point + Vector2(0, -32), Color("#6b5944"), 6)
			capture_circle(point + Vector2(0, -32), 17, Color("#537b55"))
			capture_arc(point + Vector2(9, -24), 9, 0, PI, 12, Color("#bb9a62"), 3)
		elif site.type == "crevice":
			capture_polygon(PackedVector2Array([point + Vector2(-17, 3), point + Vector2(-12, -17), point + Vector2(13, -14), point + Vector2(18, 3)]), Color("#7c847d"))
			capture_line(point + Vector2(-4, -7), point + Vector2(5, -9), Color("#253432"), 5)
			capture_line(point + Vector2(2, -9), point + Vector2(4, -17), UI.JADE, 2)
		else:
			continue
		capture_text(font, point + Vector2(-27, 18), str(domain.definitions.site_types[site.type].label), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UI.PAPER)
	for id: String in domain.birds:
		if not _visible(id):
			continue
		var body: Dictionary = domain.birds[id]
		var point: Vector2 = _bird_point(id)
		var ground: Vector2 = SimAvianLife.point(body) - Vector2(0, adapter._home._world.get_elevation(domain.body_cell(id)) * ReolWorld.ELEVATION_PX)
		capture_transform(ground, 0, Vector2(1, 0.4))
		capture_circle(Vector2.ZERO, 7, Color(0.08, 0.12, 0.12, 0.4))
		capture_transform(Vector2.ZERO)
		var flying: bool = body.active.get("verb") == "fly"
		var wing: float = 9.0 + 4.0 * sin(float(GameClock.elapsed_ms % 600) / 600.0 * TAU) if flying else 5.0
		capture_line(point + Vector2(-wing, -3), point + Vector2(0, 2), Color("#d0bc8c"), 3)
		capture_line(point + Vector2(0, 2), point + Vector2(wing, -3), Color("#d0bc8c"), 3)
		capture_circle(point, 4.5, Color("#7b7151"))
		capture_circle(point + Vector2(3, -3), 3, Color("#d9cfab"))
		capture_circle(point + Vector2(4, -4), 0.8, Color("#202b2b"))
		if domain.inventory.quantity("bird:" + id, "herb") > 0:
			capture_line(point + Vector2(5, -1), point + Vector2(15, -6), UI.JADE, 1.5)
			capture_circle(point + Vector2(12, -6), 2, Color("#aac57f"))
		if id == selected_bird and panel.visible:
			capture_arc(point, 13, 0, TAU, 24, UI.GOLD, 1.5)
		capture_text(font, point + Vector2(-10, -14), str(body.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UI.PAPER)
