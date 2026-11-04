class_name TerrainEditorRuntime
extends Node2D
## Explicit developer tool. The normal game has no free terraforming command.
## Preparation is a separate old-topology synchronization; strokes never tick.

const UI = preload("res://scripts/ui/reol_ui_theme.gd")
const SAVE_PATH: String = "user://terrain_editor.json"
const LABELS: Dictionary = {
	"no_world": "世界尚未装配。", "pending_time": "世界仍有欠算，请先接续原事务。",
	"unsynchronized_region": "区域尚未同步，请重新进入编辑。", "brush_limit": "单笔不能超过256格。",
	"invalid_patch": "不是可编辑的平面地块或笔触无效。", "fixed_space": "保留设施、工地、物料或落点不能直接改地。",
	"occupied": "这里承载着原身体或大型单位的占地。", "active_contact": "这里是进行中任务的接触范围。",
	"reserved_route": "笔触会堵住道路、完整在途路线或其转角。", "not_prepared": "须在暂停且已准备的原会话中编辑。",
	"local_motion": "请先结束闪身，再进入地形编辑。",
}

var panel: PanelContainer
var overlay: Control
var terrain_choice: OptionButton
var brush_choice: OptionButton
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
	_hint = UI.label(layer, "开发模式：F8 打开地形编辑", UI.GOLD, 13)
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
	UI.label(column, "地形编辑 · 开发模式", UI.GOLD, 20)
	UI.label(column, "暂停下左键改地；F8 / Esc收起。\n编辑不推进时间，不扣物资。退出后仍暂停。", UI.MUTED, 13)
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
	UI.button(column, "保存编辑后的世界", save_world)
	UI.button(column, "读取编辑存档", load_world)
	UI.button(column, "退出编辑（保持暂停）", close)
	_reply = UI.label(column, "", UI.PAPER, 13)
	_reply.custom_minimum_size = Vector2(306, 62)
	overlay.hide()


func runtime() -> WorldContinuityRuntime:
	return null if _adapter == null else _adapter.get_ref() as WorldContinuityRuntime


func prepare() -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or adapter.world_sim == null:
		return _failed("no_world")
	var world: RegionalSimulation = adapter.world_sim
	if world.map_data == null or not world.map_data.inspect_terrain_patch([]).ok:
		return _failed("invalid_patch")
	if world.elapsed_ms != GameClock.elapsed_ms or world.elapsed_ms != world.target_ms:
		return _failed("pending_time")
	if not adapter.home_runtime()._player.motion.action.is_empty():
		return _failed("local_motion")
	GameClock.set_paused(true)
	# No time is dropped and no action is cancelled. Lazy original regions
	# settle their OLD interval before a later stroke can change terrain truth.
	if not world.synchronize_regions() or not world.local_heat.settle_at_ms(world.elapsed_ms):
		return _failed("unsynchronized_region")
	_prepared_world = world
	_prepared_ms = world.elapsed_ms
	_hint.text = "开发编辑已暂停世界 · F8 / Esc 退出"
	overlay.show()
	_reply.text = "已准备：共同时间 %d ms。\n地表与实体仍属于原世界。" % _prepared_ms
	return {"ok": true}


func close() -> void:
	_prepared_world = null
	_prepared_ms = -1
	_hint.text = "开发模式：F8 打开地形编辑"
	overlay.hide()
	queue_redraw()


func apply_patch(rows: Variant) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not overlay.visible or not GameClock.paused or adapter.world_sim != _prepared_world or GameClock.elapsed_ms != _prepared_ms or _prepared_world.elapsed_ms != _prepared_ms or not adapter.home_runtime()._player.motion.action.is_empty():
		return _failed("not_prepared")
	var result: Dictionary = SimTerrainEdits.apply(_prepared_world, rows, adapter.player_journey)
	_reply.text = "已改 %d 格；%d ms，实体/物资/账簿保持原状态。" % [result.changed_cells.size(), _prepared_ms] if bool(result.ok) else str(LABELS.get(result.code, result.code))
	return result


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
		var width: int = int(brush_choice.get_selected_metadata())
		var radius: int = width >> 1
		# GUI input is local to the overlay. Resolve the event itself through
		# its canvas and the world camera; OS pointer polling can disagree with
		# queued input and scaled-window/replayed events.
		var viewport_point: Vector2 = overlay.get_global_transform_with_canvas() * event.position
		var center: Vector2i = TileGrid.world_to_cell(get_canvas_transform().affine_inverse() * viewport_point)
		var rows: Array = []
		for y: int in range(center.y - radius, center.y + radius + 1):
			for x: int in range(center.x - radius, center.x + radius + 1):
				rows.append([x, y, int(terrain_choice.get_selected_metadata())])
		apply_patch(rows)
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
		var width: int = int(brush_choice.get_selected_metadata())
		var bounds := Rect2(Vector2(_cursor - Vector2i.ONE * (width >> 1)) * TileGrid.TILE_SIZE, Vector2.ONE * width * TileGrid.TILE_SIZE)
		draw_rect(bounds, Color(UI.GOLD, 0.15), true)
		draw_rect(bounds, UI.GOLD, false, 2.0)


func _failed(code: String) -> Dictionary:
	if _hint != null:
		_hint.text = str(LABELS.get(code, code)) + "（F8重试）"
	if _reply != null:
		_reply.text = str(LABELS.get(code, code))
	return {"ok": false, "code": code}
