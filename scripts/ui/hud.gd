class_name GameHUD
extends CanvasLayer
## Development HUD: numeric status, passive terrain hover and unit inspection. Actions
## still route through the original adapters rather than editing these views.

signal help_requested
signal life_panels_requested

const UI = preload("res://scripts/ui/reol_ui_theme.gd")

var _world: ReolWorld
var _player: PlayerCharacter
var _camera: CameraController
var _fog: FogOfWar
var _screen: Control
var _time_label: Label
var _pace_label: Label
var _pause: Button
var _wait: Button
var _input_hint: Label
var _speeds: Array[Button] = []
var _diagnostics: PanelContainer
var _diagnostic_text: Label
var _performance_text: Label
var _previous_frame_usec: int = -1
var _frame_window_usec: int = 0
var _last_frame_usec: int = 0
var _frame_peak_usec: int = 0
var _pawn_panel: PanelContainer
var _pawn_name: Label
var _pawn_role: Label
var _pawn_resources: Label
var _pawn_mood: Label
var _activity: Label
var _help: Button
var _hunger_value: Label
var _energy_value: Label
var _pawn_state: PawnState
var _pawn_is_player: bool = false
var _display_name: String = ""
var _last_pawn_values: Array = []
var _refresh_queued: bool = false
var _last_second: int = -1
var _bird_avatar: bool = false
var inspector: DevelopmentInspectorPanel
var development_snapshot: Dictionary = {}
var _backend_text: Label
var _coordinates: Label
var _pointer: Vector2
var terrain_snapshot: Dictionary = {}
var _terrain_hover: PanelContainer
var _terrain_text: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_screen = Control.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.theme = UI.create()
	add_child(_screen)
	_build_time_bar()
	_build_pawn_panel()
	_build_diagnostics()
	_build_development()
	GameClock.tick.connect(_on_clock_tick)
	GameClock.paused_changed.connect(_on_clock_state_changed)
	GameClock.speed_changed.connect(_on_clock_speed_changed)
	GameClock.pacing_changed.connect(_on_clock_speed_changed)
	GameClock.wait_changed.connect(_on_wait_changed)
	GameClock.time_advanced.connect(_on_fine_time)
	_refresh_clock()
	_refresh_pawn_panel()


func set_world(world: ReolWorld, player: PlayerCharacter, camera: CameraController, fog: FogOfWar) -> void:
	_world = world
	_player = player
	_player.resources_changed.connect(_on_player_resources_changed)
	_camera = camera
	_fog = fog


func show_pawn_state(state: PawnState, is_player: bool = false, display_name: String = "") -> void:
	_pawn_state = state
	_pawn_is_player = is_player
	_display_name = display_name
	_last_pawn_values.clear()
	_refresh_pawn_panel()


func set_interaction(text_value: String, enabled: bool) -> void:
	if _help == null:
		return
	_help.text = "请求帮助 · available=%d" % int(enabled)
	_help.disabled = not enabled
	_help.tooltip_text = text_value


func set_activity(text_value: String) -> void:
	if _activity != null:
		_activity.text = text_value
		_activity.visible = not text_value.is_empty()


func set_bird_avatar(value: bool) -> void:
	_bird_avatar = value
	_pawn_panel.visible = not value
	_input_hint.text = "WASD · F/E/R" if value else "WASD · Shift · C"
	_input_hint.tooltip_text = "WASD振翅 · F落地 · E觅食 · R歇翅" if value else "WASD行走 · Shift闪身 · C交互 · 左键选择单位 · 地块信息跟随鼠标"


func diagnostics_visible() -> bool:
	return _diagnostics != null and _diagnostics.visible


func set_soul_avatar() -> void:
	set_bird_avatar(true)
	_input_hint.text = "E/C/Q/R/F · T"
	_input_hint.tooltip_text = "E感知 · C换气息 · Q传意 · R休眠 · F凝神 · T等候"


func _build_time_bar() -> void:
	var panel := PanelContainer.new()
	_screen.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 16
	panel.offset_right = 642
	panel.offset_top = 14
	panel.offset_bottom = 94
	var column := VBoxContainer.new()
	panel.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var title: Label = UI.label(row, "REOL / DEV", UI.PAPER, 17)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_label = UI.label(row, "", UI.PAPER)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.custom_minimum_size.x = 164
	_pace_label = UI.label(row, "", UI.WARNING, 13)
	_pace_label.tooltip_text = "世界随处理能力放慢，所有行动仍按原顺序发生。所选倍率保留。"
	var controls := HBoxContainer.new()
	column.add_child(controls)
	_pause = UI.button(controls, "暂停", GameClock.toggle_pause)
	_pause.custom_minimum_size.x = 72
	_pause.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_pause.tooltip_text = "空格：暂停或继续世界时间。"
	var life: Button = UI.button(controls, "生活 · F2", func() -> void: life_panels_requested.emit())
	life.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for speed: int in [1, 2, 4]:
		var button: Button = UI.button(controls, "%d×" % speed, GameClock.set_speed.bind(float(speed)))
		button.custom_minimum_size.x = 36
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.toggle_mode = true
		_speeds.append(button)
	_wait = UI.button(controls, "等候一刻", _request_wait)
	_wait.custom_minimum_size.x = 86
	_wait.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_wait.tooltip_text = "T：推进十五世界分钟，到时暂停；空格可中断，WASD取消等候。"
	_input_hint = UI.label(controls, "WASD · Shift · C", UI.MUTED, 12)
	_input_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _build_pawn_panel() -> void:
	_pawn_panel = PanelContainer.new()
	_screen.add_child(_pawn_panel)
	_pawn_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_pawn_panel.offset_left = -320
	_pawn_panel.offset_right = -16
	_pawn_panel.offset_top = 14
	_pawn_panel.offset_bottom = 242
	var column := VBoxContainer.new()
	_pawn_panel.add_child(column)
	_pawn_name = UI.label(column, "", UI.GOLD, 19)
	_pawn_role = UI.label(column, "", UI.MUTED, 13)
	_pawn_resources = UI.label(column, "", UI.PAPER, 13)
	_hunger_value = UI.label(column, "", UI.PAPER, 13)
	_energy_value = UI.label(column, "", UI.PAPER, 13)
	_pawn_mood = UI.label(column, "", UI.MUTED, 13)
	_activity = UI.label(column, "", UI.JADE, 13)
	_activity.visible = false
	_help = UI.button(column, "请求帮助 · available=0", _on_help_requested)
	_help.disabled = true
	_pawn_panel.visible = false


func _build_diagnostics() -> void:
	var performance_panel := PanelContainer.new()
	_screen.add_child(performance_panel)
	performance_panel.anchor_left = 0.5
	performance_panel.anchor_right = 0.5
	performance_panel.offset_left = 20
	performance_panel.offset_right = 304
	performance_panel.offset_top = 14
	performance_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_performance_text = UI.label(performance_panel, "FPS 采样中 · F3详情", UI.MUTED, 12)
	_performance_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_performance_text.tooltip_text = "FPS来自Godot原生指标，每秒更新；帧间隔用宿主单调时间测量，峰值每2秒重置。世界流速与画面FPS分别显示。"
	_diagnostics = PanelContainer.new()
	_screen.add_child(_diagnostics)
	_diagnostics.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_diagnostics.offset_left = 16
	_diagnostics.offset_right = 500
	_diagnostics.offset_top = 142
	_diagnostics.offset_bottom = 254
	_diagnostic_text = UI.label(_diagnostics, "", UI.MUTED, 12)
	_diagnostics.visible = false
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.timeout.connect(_refresh_diagnostics)
	add_child(timer)


func _build_development() -> void:
	var panel := PanelContainer.new()
	_screen.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 16
	panel.offset_right = 642
	panel.offset_top = 106
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	panel.add_child(column)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coordinates = UI.label(column, "坐标等待采样", UI.PAPER, 13)
	_backend_text = UI.label(column, "环境等待完整结算快照", UI.PAPER, 13)
	inspector = DevelopmentInspectorPanel.new()
	_screen.add_child(inspector)
	# Keep F3's optional timing details clear of the numeric environment block.
	panel.resized.connect(func() -> void:
		_diagnostics.offset_top = panel.offset_top + panel.size.y + 12.0
		_diagnostics.offset_bottom = _diagnostics.offset_top + 162.0)
	_terrain_hover = PanelContainer.new()
	_terrain_hover.name = "TerrainHover"
	_terrain_hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain_hover.z_index = 100
	_screen.add_child(_terrain_hover)
	_terrain_text = UI.label(_terrain_hover, "", UI.PAPER, 12)
	_terrain_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_terrain_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain_hover.hide()


func set_pointer_position(point: Vector2) -> void:
	_pointer = point
	_refresh_coordinates()
	_position_terrain_hover()


func pointer_over_interface() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func set_terrain_snapshot(data: Dictionary) -> void:
	terrain_snapshot = data
	if data.is_empty():
		_terrain_hover.hide()
		return
	var cell: Vector2i = data.cell
	var natural: Dictionary = data.natural
	var lines: Array[String] = ["地块 (%d,%d) · terrain=%d · 高度=%d" % [cell.x, cell.y, data.terrain, data.elevation],
		"肥力=%s · 水分=%s · 矿化=%s" % [natural.get("fertility", "n/a"), natural.get("moisture_potential", "n/a"), natural.get("mineralization", "n/a")],
		"曝露=%s · 冠层=%s · 近水=%s" % [natural.get("exposure", "n/a"), natural.get("canopy_potential", "n/a"), natural.get("water_nearby", "n/a")]]
	var context: Dictionary = data.environment
	if context.get("ok", false):
		var elements: PackedFloat64Array = context.elements
		var tide: PackedInt32Array = context.element_tide_percent
		lines.append("温度=%.3f℃ · 照度=%.2f · roof=%d" % [context.temperature_c, context.light_relative, int(context.roofed)])
		lines.append("五行场 木%.0f / 火%.0f / 土%.0f / 金%.0f / 水%.0f" % [elements[0], elements[1], elements[2], elements[3], elements[4]])
		lines.append(_element_debug_line("base", context.elements_base))
		lines.append(_element_debug_line("target", context.elements_target))
		lines.append("潮汐 木%+d%% / 火%+d%% / 土%+d%% / 金%+d%% / 水%+d%%" % [tide[0], tide[1], tide[2], tide[3], tide[4]])
		lines.append("t=%dms · 五行=%dms · 潮汐=%dms" % [data.at_ms, context.elements_at_ms, context.element_tide_at_ms])
	else:
		lines.append("environment=unavailable · t=%dms" % data.at_ms)
	_terrain_text.text = "\n".join(lines)
	_terrain_hover.reset_size()
	_terrain_hover.show()
	_position_terrain_hover()


func _position_terrain_hover() -> void:
	if _terrain_hover == null or not _terrain_hover.visible:
		return
	var cursor: Vector2 = _screen.get_local_mouse_position()
	var target: Vector2 = cursor + Vector2(20, 20)
	var extent: Vector2 = _terrain_hover.size
	if target.x + extent.x > _screen.size.x - 8.0:
		target.x = cursor.x - extent.x - 20.0
	if target.y + extent.y > _screen.size.y - 8.0:
		target.y = cursor.y - extent.y - 20.0
	_terrain_hover.position = target.clamp(Vector2(8, 8), (_screen.size - extent - Vector2(8, 8)).max(Vector2(8, 8)))


func _refresh_coordinates() -> void:
	if _coordinates == null or development_snapshot.is_empty():
		return
	var cell: Vector2i = development_snapshot.cell
	var point: Vector2 = development_snapshot.position
	var cursor: Vector2i = TileGrid.world_to_cell(_pointer)
	_coordinates.text = "角色格 (%d,%d) · px (%.1f,%.1f)\n鼠标格 (%d,%d) · px (%.1f,%.1f)" % [cell.x, cell.y, point.x, point.y, cursor.x, cursor.y, _pointer.x, _pointer.y]


func set_development_snapshot(data: Dictionary) -> void:
	development_snapshot = data
	_refresh_coordinates()
	var context: Dictionary = data.environment
	var lines: Array[String] = ["后台快照 t=%dms · %s · weather=%s" % [data.at_ms, data.subject, data.weather]]
	if context.get("ok", false):
		var elements: PackedFloat64Array = context.elements
		lines.append("温度 %.3f ℃ · 照度 %.2f · roof=%d · room=%s" % [context.temperature_c, context.light_relative, int(context.roofed), str(context.room)])
		lines.append("木 %.0f / 火 %.0f / 土 %.0f / 金 %.0f / 水 %.0f" % [elements[0], elements[1], elements[2], elements[3], elements[4]])
		lines.append(_element_debug_line("base", context.elements_base))
		lines.append(_element_debug_line("target", context.elements_target))
		var tide: PackedInt32Array = context.element_tide_percent
		lines.append("潮汐 木%+d%% / 火%+d%% / 土%+d%% / 金%+d%% / 水%+d%%" % [tide[0], tide[1], tide[2], tide[3], tide[4]])
		lines.append("五行采样=%dms · 潮汐采样=%dms" % [context.elements_at_ms, context.element_tide_at_ms])
		lines.append("环境时刻=%dms · 冷热负担 energy_rate=%s" % [context.at_ms, str(data.exposure.get("burden_rate", "n/a"))])
	else:
		lines.append("环境 unavailable: " + str(context.get("reason", "unknown")))
	lines.append("地块信息跟随鼠标 · 左键选择单位 · 当前为DEV全知观察")
	_backend_text.text = "\n".join(lines)


func _element_debug_line(label: String, values: PackedFloat64Array) -> String:
	return "%s 木%.2f / 火%.2f / 土%.2f / 金%.2f / 水%.2f" % [label, values[0], values[1], values[2], values[3], values[4]]


func _process(_delta: float) -> void:
	# Presentation telemetry only, including pauses; no simulation reads or
	# engine-delta scaling. Keep constant storage and update labels at 2Hz.
	var now: int = Time.get_ticks_usec()
	if _previous_frame_usec >= 0:
		if now - _frame_window_usec >= 2000000:
			_frame_window_usec = now
			_frame_peak_usec = 0
		_last_frame_usec = now - _previous_frame_usec
		_frame_peak_usec = maxi(_frame_peak_usec, _last_frame_usec)
	_previous_frame_usec = now


func _on_clock_tick(_tick_index: int) -> void:
	# Runtime subscribers update the body during this same tick.
	if _refresh_queued:
		return
	_refresh_queued = true
	_refresh_status.call_deferred()


func _refresh_status() -> void:
	_refresh_queued = false
	_refresh_clock()
	_refresh_pawn_panel()


func _on_clock_state_changed(_paused: bool) -> void:
	_refresh_clock()


func _on_clock_speed_changed(_speed: float) -> void:
	_refresh_clock()


func _on_wait_changed(_waiting: bool) -> void:
	_refresh_clock()


func _on_fine_time(_from_ms: int, to_ms: int) -> void:
	@warning_ignore("integer_division")
	var second: int = to_ms / 1000
	if second != _last_second:
		_last_second = second
		_refresh_clock()


func _request_wait() -> void:
	if not GameClock.request_wait():
		set_activity("先停下脚步并收势，再等候。")


func _on_player_resources_changed() -> void:
	_refresh_pawn_panel()


func refresh_body() -> void:
	_refresh_pawn_panel()


func _refresh_clock() -> void:
	if _time_label == null:
		return
	@warning_ignore("integer_division")
	var second: int = (GameClock.elapsed_ms / 1000) % 60
	_time_label.text = GameClock.format_time() + ":%02d · t=%dms" % [second, GameClock.elapsed_ms]
	_pace_label.text = "缓行 %.2f×" % GameClock.effective_speed() if GameClock.pacing.rate < 0.97 and not GameClock.paused and GameClock.wait_target_ms == 0 else ""
	_pause.text = "继续" if GameClock.paused else "暂停"
	if _wait != null:
		_wait.text = "等候中" if GameClock.wait_target_ms > 0 else "等候一刻"
	for index in range(_speeds.size()):
		_speeds[index].set_pressed_no_signal(int(GameClock.speed) == [1, 2, 4][index])


func _refresh_pawn_panel() -> void:
	if _pawn_panel == null:
		return
	_pawn_panel.visible = _pawn_state != null and not _bird_avatar
	if _pawn_state == null or _bird_avatar:
		return
	var state: PawnState = _pawn_state
	var values: Array = [state, _pawn_is_player, state.qi, state.stamina, state.hunger, state.energy, state.mood, state.rank]
	if values == _last_pawn_values:
		return
	_last_pawn_values = values
	_pawn_name.text = ("你 · " if _pawn_is_player else "") + (state.display_name() if _display_name.is_empty() else _display_name)
	_pawn_role.text = "rank=%s · realm=%s" % [state.rank_name(), state.realm_name()]
	_pawn_resources.text = "灵气 %d/%d  ·  体力 %d/%d" % [state.qi, state.max_qi(), state.stamina, state.max_stamina()]
	_hunger_value.text = "hunger=%.3f / 100" % state.hunger
	_energy_value.text = "energy=%.3f / 100" % state.energy
	_pawn_mood.text = "mood=%.2f · definition=%s" % [state.mood, str(state.pawn_def.id)]


func _on_help_requested() -> void:
	help_requested.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		life_panels_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_diagnostics.visible = not _diagnostics.visible
		_refresh_diagnostics()
		get_viewport().set_input_as_handled()


func _refresh_diagnostics() -> void:
	var pace: Dictionary = GameClock.pacing_status()
	var flow: String = "暂停" if GameClock.paused else "等候" if GameClock.wait_target_ms > GameClock.elapsed_ms else "%.2f×" % float(pace.effective_speed)
	_performance_text.text = "FPS %d · 世界 %s\n帧 %.1fms · 本2s窗峰值 %.1fms · F3" % [int(Engine.get_frames_per_second()), flow, float(_last_frame_usec) / 1000.0, float(_frame_peak_usec) / 1000.0]
	if _diagnostics == null or not _diagnostics.visible or _world == null or _player == null or _camera == null:
		return
	var fog_text: String = "?"
	if _fog != null:
		fog_text = ["未见", "曾见", "可见"][_fog.get_state(_player.cell)]
	_diagnostic_text.text = "开发诊断 · F3收起  |  高度 %d / 飞行 %d\nFPS %d  |  画面帧间隔 %.2fms / 本2s窗峰值 %.2fms\n格 (%d,%d) %s  |  迷雾 %s  |  区块 %d  |  缩放 %.2f" % [_world.get_elevation(_player.cell), _player.altitude, int(Engine.get_frames_per_second()), float(_last_frame_usec) / 1000.0, float(_frame_peak_usec) / 1000.0, _player.cell.x, _player.cell.y, _world.terrain_name(_player.cell), fog_text, _world.loaded_chunk_count(), _camera.zoom.x]
	_diagnostic_text.text += "\n流速 %.2f× / 所选 %.0f×  |  已接纳欠算 %.1fms\n时钟调用 %.2fms / 峰值 %.2fms" % [pace.effective_speed, pace.requested_speed, pace.admitted_debt_ms, float(pace.last_work_usec) / 1000.0, float(pace.longest_work_usec) / 1000.0]
