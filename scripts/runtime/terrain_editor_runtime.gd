class_name TerrainEditorRuntime
extends Node2D
## Explicit developer tool. The normal game has no free editing command.
## Preparation is a separate old-topology synchronization; strokes never tick.

const UI = preload("res://scripts/ui/reol_ui_theme.gd")
const SAVE_PATH: String = "user://terrain_editor.json"
const MODE_TERRAIN: int = 0
const MODE_PLACE: int = 1
const MODE_REMOVE: int = 2
const LABELS: Dictionary = {
	"no_world": "世界尚未装配。", "pending_time": "世界仍有欠算，请先接续原事务。",
	"unsynchronized_region": "区域尚未同步，请重新进入编辑。", "brush_limit": "单笔不能超过256格。",
	"invalid_patch": "不是可编辑的平面地块或笔触无效。", "fixed_space": "保留设施、工地、物料或落点不能直接改地。",
	"occupied": "这里承载着原身体或大型单位的占地。", "active_contact": "这里是进行中任务的接触范围。",
	"reserved_route": "笔触会堵住道路、完整在途路线或其转角。", "not_prepared": "须在暂停且已准备的原会话中编辑。",
	"local_motion": "请先结束闪身，再进入地形编辑。",
	"invalid_definition": "请选择可放置的实物定义。", "invalid_region": "请选择原世界中的所属区域。",
	"id_exhausted": "无法分配新的编辑命令和实物身份。", "not_managed": "此格没有可移除的受控实物。",
	"invalid_area": "点击的位置在地图之外。", "ground_occupied": "这里已有地面实物。",
	"terrain_blocked": "地形不允许放置。", "structure_blocked": "设施阻挡了放置。",
	"invalid_geometry": "实物占地超出地图或尺寸无效。", "target_reserved": "该位置被进行中的动作预约。",
	"object_in_use": "实物正在使用，暂不能移除。", "legacy_dependency": "实物仍被其他原事务引用。",
	"transaction_busy": "原世界事务尚未完成。", "environment_operation_unsupported": "当前环境会话不支持此编辑。",
}

var panel: PanelContainer
var overlay: Control
var mode_choice: OptionButton
var terrain_choice: OptionButton
var brush_choice: OptionButton
var object_choice: OptionButton
var region_choice: OptionButton
var _reply: Label
var _hint: Label
var _adapter: WeakRef
var _prepared_world: RegionalSimulation
var _prepared_ms: int = -1
var _cursor := Vector2i(-1, -1)


func setup(adapter: WorldContinuityRuntime) -> void:
	_adapter = weakref(adapter)
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 30
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_hint = UI.label(layer, "开发模式：F8 打开世界编辑", UI.GOLD, 13)
	_hint.position = Vector2(16, 46)
	_hint.size = Vector2(620, 28)
	overlay = Control.new()
	layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_canvas_input)
	panel = PanelContainer.new()
	panel.theme = UI.create()
	panel.add_theme_stylebox_override("panel", UI.panel(UI.GOLD))
	overlay.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(16, 78)
	panel.custom_minimum_size = Vector2(332, 0)
	var column := VBoxContainer.new()
	panel.add_child(column)
	UI.label(column, "世界编辑 · 开发模式", UI.GOLD, 20)
	UI.label(column, "暂停下左键编辑；F8 / Esc收起。\n开发放置不扣材料，不是玩家造物。退出后仍暂停。", UI.MUTED, 13)
	mode_choice = OptionButton.new()
	column.add_child(mode_choice)
	for label: String in ["地形", "实物放置", "实物移除"]:
		mode_choice.add_item(label)
	mode_choice.item_selected.connect(_on_mode_selected)
	terrain_choice = OptionButton.new()
	column.add_child(terrain_choice)
	for label: String in ["草地", "水面", "岩地"]:
		terrain_choice.add_item(label)
	terrain_choice.set_item_metadata(0, WorldMapData.TERRAIN_GRASS)
	terrain_choice.set_item_metadata(1, WorldMapData.TERRAIN_WATER)
	terrain_choice.set_item_metadata(2, WorldMapData.TERRAIN_ROCK)
	brush_choice = OptionButton.new()
	column.add_child(brush_choice)
	for width: int in [1, 3, 5]:
		brush_choice.add_item("%d × %d 格" % [width, width])
		brush_choice.set_item_metadata(brush_choice.item_count - 1, width)
	object_choice = OptionButton.new()
	column.add_child(object_choice)
	object_choice.item_selected.connect(_on_object_selected)
	region_choice = OptionButton.new()
	column.add_child(region_choice)
	UI.button(column, "保存编辑后的世界", save_world)
	UI.button(column, "读取编辑存档", load_world)
	UI.button(column, "退出编辑（保持暂停）", close)
	_reply = UI.label(column, "", UI.PAPER, 13)
	_reply.custom_minimum_size = Vector2(306, 62)
	overlay.hide()
	_on_mode_selected(MODE_TERRAIN)


func runtime() -> WorldContinuityRuntime:
	return null if _adapter == null else _adapter.get_ref() as WorldContinuityRuntime


func prepare() -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or adapter.world_sim == null:
		return _failed("no_world")
	var world: RegionalSimulation = adapter.world_sim
	if world.map_data == null or not world.map_data.inspect_terrain_patch([]).ok:
		return _failed("invalid_patch")
	if GameClock.has_pending_advance() or world.elapsed_ms != GameClock.elapsed_ms or world.elapsed_ms != world.target_ms:
		return _failed("pending_time")
	if not adapter.home_runtime()._player.motion.action.is_empty():
		return _failed("local_motion")
	GameClock.set_paused(true)
	# No time is dropped and no action is cancelled. Lazy original regions
	# settle their OLD interval before a later stroke can change terrain truth.
	if not world.synchronize_regions() or not world.environment_fields.settle_at_ms(world.elapsed_ms):
		return _failed("unsynchronized_region")
	if adapter.world_sim != world or GameClock.has_pending_advance() or world.elapsed_ms != GameClock.elapsed_ms or world.elapsed_ms != world.target_ms:
		return _failed("pending_time")
	_prepared_world = world
	_prepared_ms = world.elapsed_ms
	_populate_object_choices(world)
	_populate_region_choices(adapter, world)
	_on_mode_selected(mode_choice.selected)
	_hint.text = "开发编辑已暂停世界 · F8 / Esc 退出"
	overlay.show()
	_reply.text = "已准备：共同时间 %d ms。\n地表与实体仍属于原世界。" % _prepared_ms
	return {"ok": true}


func close() -> void:
	_prepared_world = null
	_prepared_ms = -1
	_hint.text = "开发模式：F8 打开世界编辑"
	overlay.hide()
	queue_redraw()


func apply_patch(rows: Variant) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if not _is_prepared(adapter):
		return _failed("not_prepared")
	var result: Dictionary = SimTerrainEdits.apply(_prepared_world, rows, adapter.player_journey)
	_reply.text = "已改 %d 格；%d ms，实体/物资/账簿保持原状态。" % [result.changed_cells.size(), _prepared_ms] if bool(result.ok) else str(LABELS.get(result.code, result.code))
	return result


func place_object(definition_id: String, cell: Vector2i) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if not _is_prepared(adapter):
		return _failed("not_prepared")
	var world: RegionalSimulation = _prepared_world
	var definition: Variant = world.artifacts.definitions.types.get(definition_id)
	if not _placeable_definition(definition):
		return _failed("invalid_definition")
	var region: String = str(region_choice.get_selected_metadata()) if region_choice.selected >= 0 else ""
	if not world.regions.has(region):
		return _failed("invalid_region")
	var id: String = _next_object_command(world)
	if id.is_empty():
		return _failed("id_exhausted")
	var request: Dictionary = {"command": id, "op": "spawn", "id": id, "definition": definition_id,
		"to": {"region": region, "cell": [cell.x, cell.y]}}
	var result: Dictionary = world.object_lifecycle.execute(request)
	_report_object_result(result, "已放置实物；开发编辑未扣材料。")
	if bool(result.get("ok", false)) and adapter.world_sim == world and adapter.object_adapter != null:
		adapter.object_adapter.refresh()
	return result


func remove_object(cell: Vector2i) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if not _is_prepared(adapter):
		return _failed("not_prepared")
	var world: RegionalSimulation = _prepared_world
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var hits: Dictionary = world.query_space(Rect2i(cell, Vector2i.ONE), ["artifact"], "ground")
	if not bool(hits.get("ok", false)):
		_report_object_result(hits, "")
		return hits
	var object_id: String = ""
	for reference: Dictionary in hits.references:
		if lifecycle.manages(reference.id):
			object_id = reference.id
			break
	if object_id.is_empty() or not world.artifacts.objects.has(object_id):
		return _failed("not_managed")
	var item: Dictionary = world.artifacts.objects[object_id]
	var slot_id: String = str(item.container)
	var slot: Dictionary = lifecycle.ground.slots.get(slot_id, {})
	if not bool(slot.get("active", false)) or not SimObjectLifecycle.ground_cells(slot).has(cell):
		return _failed("source_changed")
	var command: String = _next_object_command(world)
	if command.is_empty():
		return _failed("id_exhausted")
	var request: Dictionary = {"command": command, "op": "remove", "id": object_id,
		"from": {"region": slot.region, "container": slot_id}}
	var result: Dictionary = lifecycle.execute(request)
	_report_object_result(result, "已移除受控实物。")
	if bool(result.get("ok", false)) and adapter.world_sim == world and adapter.object_adapter != null:
		adapter.object_adapter.refresh()
	return result


func _is_prepared(adapter: WorldContinuityRuntime) -> bool:
	if adapter == null or _prepared_world == null or overlay == null or not overlay.visible or not GameClock.paused or GameClock.has_pending_advance():
		return false
	if adapter.world_sim != _prepared_world or GameClock.elapsed_ms != _prepared_ms or _prepared_world.elapsed_ms != _prepared_ms or _prepared_world.target_ms != _prepared_ms:
		return false
	if adapter.home_runtime() == null or not adapter.home_runtime()._player.motion.action.is_empty():
		return false
	for sim: VillageSimulation in _prepared_world.regions.values():
		if sim.elapsed_ms != _prepared_ms:
			return false
	return true


func _next_object_command(world: RegionalSimulation) -> String:
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var start: int = lifecycle.receipts.size() + 1
	for offset: int in SimObjectLifecycle.MAX_RECEIPTS:
		var id: String = "dev_object_%d" % (start + offset)
		if lifecycle.receipts.has(id) or lifecycle.actions.has(id) or lifecycle.created.has(id) or world.artifacts.objects.has(id):
			continue
		if lifecycle.ground.slots.has("ground:" + id) or world.soul_vessels.vessels.has(id):
			continue
		return id
	return ""


func _placeable_definition(value: Variant) -> bool:
	return value is Dictionary and value.get("capabilities") is Array and value.capabilities.has("physical") and value.get("placement") is Dictionary


func _populate_object_choices(world: RegionalSimulation) -> void:
	var previous: String = str(object_choice.get_selected_metadata()) if object_choice.selected >= 0 else ""
	object_choice.clear()
	var ids: Array = world.artifacts.definitions.types.keys()
	ids.sort()
	for id: String in ids:
		var definition: Variant = world.artifacts.definitions.types[id]
		if not _placeable_definition(definition):
			continue
		object_choice.add_item("%s (%s)" % [str(definition.get("name", id)), id])
		object_choice.set_item_metadata(object_choice.item_count - 1, id)
		if id == previous:
			object_choice.select(object_choice.item_count - 1)
	object_choice.disabled = object_choice.item_count == 0
	if object_choice.item_count == 0:
		object_choice.add_item("没有可放置的实物定义")
		object_choice.set_item_metadata(0, "")


func _populate_region_choices(adapter: WorldContinuityRuntime, world: RegionalSimulation) -> void:
	region_choice.clear()
	var ids: Array = world.regions.keys()
	ids.sort()
	var preferred: String = adapter.current_region if world.regions.has(adapter.current_region) else "home"
	for id: String in ids:
		var label: String = str(adapter.settings.get("regions", {}).get(id, {}).get("label", id))
		region_choice.add_item("所属区域：" + label)
		region_choice.set_item_metadata(region_choice.item_count - 1, id)
		if id == preferred:
			region_choice.select(region_choice.item_count - 1)
	region_choice.disabled = region_choice.item_count == 0


func _on_mode_selected(index: int) -> void:
	terrain_choice.visible = index == MODE_TERRAIN
	brush_choice.visible = index == MODE_TERRAIN
	object_choice.visible = index == MODE_PLACE
	region_choice.visible = index == MODE_PLACE
	queue_redraw()


func _on_object_selected(_index: int) -> void:
	queue_redraw()


func _report_object_result(result: Dictionary, success: String) -> void:
	if bool(result.get("ok", false)):
		_reply.text = success
	else:
		var reason: String = str(result.get("reason", result.get("code", "unknown")))
		_reply.text = str(LABELS.get(reason, reason))


func save_world() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or adapter.world_sim != _prepared_world or not GameClock.paused:
		_failed("not_prepared")
		return
	var result: Error = adapter.save_game(SAVE_PATH)
	_reply.text = "已保存；下次可由存档接口恢复完整世界。\n" + SAVE_PATH if result == OK else "保存失败：" + error_string(result)


func load_world() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not GameClock.paused or adapter.world_sim != _prepared_world:
		_failed("not_prepared")
		return
	var result: Error = adapter.load_game(SAVE_PATH)
	if result != OK:
		_reply.text = "读取失败；当前世界保留：" + error_string(result)
		return
	close()
	if prepare().ok:
		_reply.text = "已恢复编辑存档，人物和在途过程仍是保存时的状态。"


func handle_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		if overlay.visible:
			close()
		else:
			prepare()
		return true
	if not overlay.visible:
		return false
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			close()
		# Block game commands and time keys before the usual UI adapters.
		return true
	return false


func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# GUI input is local to the overlay. Resolve the event itself through
		# its canvas and the world camera; OS pointer polling can disagree with
		# queued input and scaled-window/replayed events.
		var viewport_point: Vector2 = overlay.get_global_transform_with_canvas() * event.position
		var center: Vector2i = TileGrid.world_to_cell(get_canvas_transform().affine_inverse() * viewport_point)
		match mode_choice.selected:
			MODE_TERRAIN:
				var width: int = int(brush_choice.get_selected_metadata())
				var radius: int = width >> 1
				var rows: Array = []
				for y: int in range(center.y - radius, center.y + radius + 1):
					for x: int in range(center.x - radius, center.x + radius + 1):
						rows.append([x, y, int(terrain_choice.get_selected_metadata())])
				apply_patch(rows)
			MODE_PLACE:
				var definition_id: String = str(object_choice.get_selected_metadata()) if object_choice.selected >= 0 else ""
				place_object(definition_id, center)
			MODE_REMOVE:
				remove_object(center)
	overlay.accept_event()


func _process(_delta: float) -> void:
	if not overlay.visible:
		return
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or adapter.world_sim != _prepared_world or not GameClock.paused or GameClock.elapsed_ms != _prepared_ms:
		close()
		return
	var cursor: Vector2i = TileGrid.world_to_cell(get_global_mouse_position())
	if cursor != _cursor:
		_cursor = cursor
	queue_redraw()


func _draw() -> void:
	if overlay != null and overlay.visible:
		var width: int = int(brush_choice.get_selected_metadata()) if mode_choice.selected == MODE_TERRAIN else 1
		var bounds := Rect2(Vector2(_cursor - Vector2i.ONE * (width >> 1)) * TileGrid.TILE_SIZE, Vector2.ONE * width * TileGrid.TILE_SIZE)
		draw_rect(bounds, Color(UI.GOLD, 0.15), true)
		draw_rect(bounds, UI.GOLD, false, 2.0)
		if mode_choice.selected == MODE_PLACE and _prepared_world != null and object_choice.selected >= 0:
			var definition: Variant = _prepared_world.artifacts.definitions.types.get(str(object_choice.get_selected_metadata()))
			if _placeable_definition(definition):
				var footprint: Array = definition.placement.footprint
				var area := Rect2(Vector2(_cursor) * TileGrid.TILE_SIZE, Vector2(int(footprint[0]), int(footprint[1])) * TileGrid.TILE_SIZE)
				draw_rect(area, Color(UI.GOLD, 0.65), false, 2.0)


func _failed(code: String) -> Dictionary:
	if _hint != null:
		_hint.text = str(LABELS.get(code, code)) + "（F8重试）"
	if _reply != null:
		_reply.text = str(LABELS.get(code, code))
	return {"ok": false, "code": code}
