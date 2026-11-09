class_name NaturalWorldRuntime
extends CommittedWorldCanvas
## Read-only local observation. Substrate affinities are not public qi gauges.

const UI = preload("res://scripts/ui/reol_ui_theme.gd")
var panel: PanelContainer
var selected_cell: Vector2i = Vector2i(-1, -1)
var _description: Label
var _owner: WeakRef
var _selection_bounds: Rect2
var _selection_visible: bool = false
var _plant_buttons: Dictionary = {}
var _plant_choice: OptionButton
var _selected_plant: String = ""
var _bound_world: WeakRef
var _painted_claims: Dictionary[Vector2i, bool] = {}


func setup(adapter: WorldContinuityRuntime) -> void:
	_owner = weakref(adapter)
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 7
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var screen := Control.new()
	layer.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.name = "NaturalObservation"
	panel.theme = UI.create()
	panel.add_theme_stylebox_override("panel", UI.panel(UI.JADE))
	screen.add_child(panel)
	panel.position = Vector2(24, 144)
	panel.custom_minimum_size = Vector2(340, 0)
	var column := VBoxContainer.new()
	panel.add_child(column)
	UI.label(column, "山川草木 · 眼前所见", UI.GOLD, 19)
	_description = UI.label(column, "", UI.PAPER, 14)
	_description.custom_minimum_size = Vector2(318, 150)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.label(column, "右键观察地面 · 只显示当前可见处", UI.MUTED, 12)
	_plant_choice = OptionButton.new()
	column.add_child(_plant_choice)
	_plant_choice.item_selected.connect(func(index: int) -> void:
		_selected_plant = str(_plant_choice.get_item_metadata(index)))
	var actions := GridContainer.new()
	actions.columns = 2
	column.add_child(actions)
	for pair: Array in [["harvest", "采摘产物"], ["cut", "伐取地上部"], ["uproot", "采走原株"], ["remove", "清除残株"], ["water", "浇水"], ["transplant", "移栽到邻格花盆"], ["ask_harvest", "试着商量采摘"], ["cancel", "中断行动"]]:
		_plant_buttons[pair[0]] = UI.button(actions, pair[1], _plant_action.bind(str(pair[0])))
	UI.button(column, "收起", panel.hide)
	panel.hide()
	adapter.avatar_changed.connect(reset_observation)
	adapter.region_changed.connect(func(_id: String) -> void: reset_observation())
	GameClock.time_advanced.connect(func(_from: int, _to: int) -> void: refresh())
	adapter.home_runtime()._player.cell_changed.connect(refresh)
	var fog: FogOfWar = adapter.home_runtime()._fog
	if fog != null:
		fog.visibility_updated.connect(refresh)
	panel.visibility_changed.connect(queue_redraw)


func runtime() -> WorldContinuityRuntime:
	return _owner.get_ref() as WorldContinuityRuntime if _owner != null else null


func reset_observation() -> void:
	selected_cell = Vector2i(-1, -1)
	_selected_plant = ""
	_selection_visible = false
	panel.hide()
	queue_redraw()


func observe(cell: Vector2i) -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or _presentation_pending() or adapter.soul_player_active() or not visible_cell(cell):
		return false
	selected_cell = cell
	_selected_plant = ""
	panel.show()
	refresh()
	return true


func visible_cell(cell: Vector2i) -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or _presentation_pending() or adapter.soul_player_active() or not adapter.world_sim.map_data.in_bounds(cell):
		return false
	var fog: FogOfWar = adapter.home_runtime()._fog
	return fog.is_cell_visible(cell) if fog != null else cell.distance_to(adapter.controlled_cell()) <= 5.0


func describe(cell: Vector2i) -> String:
	if _presentation_pending():
		return _description.text if cell == selected_cell and _description != null else "世界事务仍在接续，请稍后观察。"
	if not visible_cell(cell):
		return "此处已离开视野，眼下的情形无法确认。"
	var adapter: WorldContinuityRuntime = runtime()
	for region: VillageSimulation in adapter.world_sim.regions.values():
		if SimWorkplaces.roofed(region.places, cell):
			var layout: Dictionary = region.places.records.workspace
			var line: String = "值事房 · 铺木地面\n墙体围合，屋面遮雨；画面采用剖开屋顶的视图。"
			for id: String in layout.fixtures:
				if SimRouteTravel.cell(layout.fixtures[id].cell) == cell:
					line += "\n这里安置着%s。" % str(layout.fixtures[id].label)
			if SimWorkplaces.blocked(region.places, cell):
				line += "\n墙与桌柜占据实际空间，需要绕行。"
			line += "\n办事要由有权的人回到桌前，依据机构记录核验。"
			line += "\n" + SimNaturalLight.description(SimNaturalLight.at_cell(adapter.world_sim, cell))
			line += _local_light_line(cell)
			return line
	var natural: Dictionary = adapter.world_sim.map_data.natural_cell(cell)
	var line: String = str(natural.get("label", "地面"))
	line += "\n土质%s，地势%s。" % ["丰厚" if int(natural.get("fertility", 0)) >= 60 else "瘠薄" if int(natural.get("fertility", 0)) < 35 else "平常", "敞露" if int(natural.get("exposure", 0)) >= 65 else "稍有遮蔽"]
	line += "\n此地%s。" % ("近水，较易涵养水分" if int(natural.get("water_nearby", 0)) > 0 else "偏于干燥" if int(natural.get("moisture_potential", 0)) < 35 else "草木有适生的土壤")
	var flora: Dictionary = natural.get("flora", {})
	if not flora.is_empty() and not adapter.world_sim.plants.overrides_flora(cell):
		line += "\n可见%s。" % ("青叶灌丛" if flora.id == "spirit_shrub" else str(flora.label))
	for id: String in adapter.world_sim.plants.ids_at(cell):
		var row: Dictionary = adapter.world_sim.plants.bodies[id]
		var label: String = "赤叶草" if row.definition == "fire_herb" else str(adapter.world_sim.plants.definitions.types[row.definition].label)
		line += "\n可见%s：%s。" % [label, {"growing": "枝叶尚幼", "mature": "枝叶长成", "flowering": "正在开花", "fruiting": "已到结果阶段", "root": "留有根桩", "dead": "已经枯死"}.get(row.stage, "仍在此处")]
		if row.dormant and row.stage not in ["dead", "removed"]:
			line += " 生长暂歇。"
		if row.contacts.has("player"):
			line += " 它曾回应过你，可以继续商量。"
	line += "\n五行影响尚未辨明；地表草木不代表可用灵气。"
	line += "\n" + SimNaturalLight.description(SimNaturalLight.at_cell(adapter.world_sim, cell))
	line += _local_light_line(cell)
	for region: VillageSimulation in adapter.world_sim.regions.values():
		for source: String in region.land_resources.sources:
			var place: String = str(region.config.resource_sources[source].place)
			if SimRouteTravel.cell(region.places[place].cell) == cell:
				line += "\n这里有%s，可按原有采集方式取用；有其实际储量。" % str(region.land_resources.terms_for(source).label)
	var weather_region: String = SimClimateRules.region_at(adapter.home_runtime()._content.climate, cell)
	if adapter.world_sim.weather.definitions.regions.has(weather_region) and adapter.world_sim.weather.current_kind(weather_region) == "rain" and not adapter.world_sim.construction.roofed(cell):
		line += "\n眼前正落着雨。"
	return line


func _local_light_line(cell: Vector2i) -> String:
	var text: String = SimLocalLight.description(SimLocalLight.at_cell(runtime().world_sim, cell))
	return "\n" + text if not text.is_empty() else ""


func refresh() -> void:
	redraw_committed_canvas()
	if panel == null or not panel.visible or _presentation_pending():
		return
	_description.text = describe(selected_cell)
	var ids: Array = runtime().world_sim.plants.ids_at(selected_cell) if visible_cell(selected_cell) else []
	var has_plant: bool = not ids.is_empty()
	_plant_choice.clear()
	if _selected_plant not in ids:
		_selected_plant = str(ids[0]) if has_plant else ""
	for id: String in ids:
		var row: Dictionary = runtime().world_sim.plants.bodies[id]
		_plant_choice.add_item("赤叶草" if row.definition == "fire_herb" else str(runtime().world_sim.plants.definitions.types[row.definition].label))
		var index: int = _plant_choice.item_count - 1
		_plant_choice.set_item_metadata(index, id)
		if id == _selected_plant:
			_plant_choice.select(index)
	_plant_choice.visible = has_plant
	for button: Button in _plant_buttons.values():
		button.visible = has_plant
	_selection_visible = visible_cell(selected_cell)
	if _selection_visible:
		var point: Vector2 = TileGrid.cell_to_world(selected_cell)
		point.y -= runtime().world_sim.map_data.get_elevation(selected_cell) * ReolWorld.ELEVATION_PX
		_selection_bounds = Rect2(point - Vector2.ONE * TileGrid.TILE_SIZE * 0.5, Vector2.ONE * TileGrid.TILE_SIZE)
	queue_redraw()


func _presentation_pending() -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	return adapter != null and adapter.world_sim != null and adapter.world_sim.settlement != null and adapter.world_sim.settlement.is_pending()


func cell_at_point(point: Vector2) -> Vector2i:
	var map: WorldMapData = runtime().world_sim.map_data
	for level: int in range(ReolWorld.ELEVATION_LEVELS - 1, -1, -1):
		var cell: Vector2i = TileGrid.world_to_cell(point + Vector2(0, level * ReolWorld.ELEVATION_PX))
		if map.in_bounds(cell) and map.get_elevation(cell) == level:
			return cell
	return Vector2i(-1, -1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var point: Vector2 = get_canvas_transform().affine_inverse() * event.position
		if observe(cell_at_point(point)):
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and panel.visible:
		panel.hide()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	super._draw()
	if panel == null or not panel.visible or not _selection_visible:
		return
	# Redraw may already be queued when a later boundary suspends. Draw the
	# last accepted local projection instead of reading that partial world.
	draw_rect(_selection_bounds, Color("#c3bf91"), false, 2.0)


func _build_canvas() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or adapter.world_sim == null:
		return
	var world: RegionalSimulation = adapter.world_sim
	if _bound_world == null or _bound_world.get_ref() != world:
		_bound_world = weakref(world)
		_painted_claims.clear()
		adapter.home_runtime()._world.flora_override = world.plants.overrides_flora
	var center: Vector2i = adapter.controlled_cell()
	for y: int in range(center.y - 14, center.y + 15):
		for x: int in range(center.x - 14, center.x + 15):
			var cell := Vector2i(x, y)
			if not visible_cell(cell):
				continue
			if world.plants.overrides_flora(cell) and not _painted_claims.has(cell):
				adapter.home_runtime()._world.refresh_flora(cell)
				_painted_claims[cell] = true
			for id: String in world.plants.ids_at(cell):
				var row: Dictionary = world.plants.bodies[id]
				var point: Vector2 = TileGrid.cell_to_world(cell)
				var tree: bool = bool(world.plants.definitions.types[row.definition].blocks)
				var color := Color("#b55b43") if row.definition == "fire_herb" else Color("#739653")
				if row.stage in ["root", "dead"]:
					capture_rect(Rect2(point - Vector2(5, 3), Vector2(10, 6)), Color("#79654c"))
				else:
					if tree:
						capture_rect(Rect2(point - Vector2(4, 5), Vector2(8, 12)), Color("#79654c"))
					capture_circle(point - Vector2(0, 9 if tree else 3), 15 if tree else 7, color)
					if row.stage == "fruiting":
						capture_circle(point - Vector2(2, 7), 2.5, Color("#d5bd73"))


func _plant_action(verb: String) -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or _presentation_pending() or not adapter.human_player_active() or not visible_cell(selected_cell):
		return
	var plants: SimPlants = adapter.world_sim.plants
	if verb == "cancel":
		plants.cancel("player")
		refresh()
		return
	var ids: Array = plants.ids_at(selected_cell)
	if ids.is_empty():
		return
	var id: String = _selected_plant if _selected_plant in ids else str(ids[0])
	var reply: Dictionary
	if verb == "ask_harvest":
		reply = SimInteractionRequests.submit(adapter.world_sim, {"sender": "subject:player", "receiver": "subject:plant:" + id, "verb": "ask_harvest", "object": {"kind": "plant", "id": id}, "medium": "spoken", "conditions": {}})
		if not bool(reply.get("ok", false)):
			reply["line"] = "草木没有回应。"
	else:
		var destination: Dictionary = {}
		if verb == "transplant":
			for direction: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
				var cell: Vector2i = selected_cell + direction
				var support: String = adapter.world_sim.construction.project_at(cell)
				if adapter.world_sim.construction.has_capability(support, "cultivation"):
					destination = {"cell": [cell.x, cell.y], "support": support}
					break
		reply = plants.jobs.begin("player", id, verb, destination)
		if bool(reply.get("ok", false)):
			adapter.hold_player_motion(true)
	refresh()
	_description.text += "\n" + str(reply.get("line", "行动已受理；继续时间后执行。" if bool(reply.get("ok", false)) else "眼下条件不合，未能执行。"))
