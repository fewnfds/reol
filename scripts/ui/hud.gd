class_name GameHUD
extends CanvasLayer
## Player-facing status; technical diagnostics are optional and sampled slowly.

signal help_requested

const UI = preload("res://scripts/ui/reol_ui_theme.gd")

var _world: ReolWorld
var _player: PlayerCharacter
var _camera: CameraController
var _fog: FogOfWar
var _screen: Control
var _time_label: Label
var _pause: Button
var _wait: Button
var _input_hint: Label
var _speeds: Array[Button] = []
var _diagnostics: PanelContainer
var _diagnostic_text: Label
var _pawn_panel: PanelContainer
var _pawn_name: Label
var _pawn_role: Label
var _pawn_resources: Label
var _pawn_mood: Label
var _pawn_bio: Label
var _activity: Label
var _help: Button
var _hunger: ProgressBar
var _energy: ProgressBar
var _hunger_value: Label
var _energy_value: Label
var _pawn_state: PawnState
var _pawn_is_player: bool = false
var _display_name: String = ""
var _last_pawn_values: Array = []
var _refresh_queued: bool = false
var _last_second: int = -1
var _bird_avatar: bool = false


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
	GameClock.tick.connect(_on_clock_tick)
	GameClock.paused_changed.connect(_on_clock_state_changed)
	GameClock.speed_changed.connect(_on_clock_speed_changed)
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
	_help.text = text_value if not text_value.is_empty() else "选择附近同门，可开口求助"
	_help.disabled = not enabled
	_help.tooltip_text = "求助会考虑对方的体力、距离、已有工作和对你的看法。"


func set_activity(text_value: String) -> void:
	if _activity != null:
		_activity.text = text_value
		_activity.visible = not text_value.is_empty()


func set_bird_avatar(value: bool) -> void:
	_bird_avatar = value
	_pawn_panel.visible = not value
	_input_hint.text = "WASD 振翅 · F 落地 · E 觅食 · R 歇翅" if value else "WASD 行走 · Shift 闪身 · C 交互 · 右键观察"


func diagnostics_visible() -> bool:
	return _diagnostics != null and _diagnostics.visible


func set_soul_avatar() -> void:
	set_bird_avatar(true)
	_input_hint.text = "E 感知 · C 换气息 · Q 传意 · R 休眠 · F 凝神 · T 等候"


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
	var title: Label = UI.label(row, "REOL  /  一山一宗", UI.GOLD, 19)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_label = UI.label(row, "", UI.PAPER)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.custom_minimum_size.x = 164
	var controls := HBoxContainer.new()
	column.add_child(controls)
	_pause = UI.button(controls, "暂停", GameClock.toggle_pause)
	_pause.custom_minimum_size.x = 72
	_pause.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_pause.tooltip_text = "空格：暂停或继续世界时间。"
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
	_input_hint = UI.label(controls, "WASD 行走 · Shift 闪身 · C 交互 · 右键观察", UI.MUTED, 12)
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
	var hunger_row: Dictionary = _need_row(column, "饱食")
	_hunger = hunger_row.bar
	_hunger_value = hunger_row.value
	var energy_row: Dictionary = _need_row(column, "精力")
	_energy = energy_row.bar
	_energy_value = energy_row.value
	_pawn_mood = UI.label(column, "", UI.MUTED, 13)
	_activity = UI.label(column, "", UI.JADE, 13)
	_activity.visible = false
	_help = UI.button(column, "选择附近同门，可开口求助", _on_help_requested)
	_help.disabled = true
	var biography: Button = UI.button(column, "人物档案", _toggle_biography)
	biography.add_theme_font_size_override("font_size", 12)
	biography.custom_minimum_size.y = 24
	_pawn_bio = UI.label(column, "", UI.MUTED, 13)
	_pawn_bio.visible = false
	_pawn_panel.visible = false


func _need_row(parent: Node, caption: String) -> Dictionary:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label: Label = UI.label(row, caption, UI.MUTED, 13)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.custom_minimum_size.x = 32
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(80, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	row.add_child(bar)
	var amount: Label = UI.label(row, "", UI.PAPER, 13)
	amount.custom_minimum_size.x = 26
	amount.size_flags_horizontal = Control.SIZE_SHRINK_END
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return {"bar": bar, "value": amount}


func _build_diagnostics() -> void:
	_diagnostics = PanelContainer.new()
	_screen.add_child(_diagnostics)
	_diagnostics.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_diagnostics.offset_left = 16
	_diagnostics.offset_right = 500
	_diagnostics.offset_top = 106
	_diagnostics.offset_bottom = 178
	_diagnostic_text = UI.label(_diagnostics, "", UI.MUTED, 12)
	_diagnostics.visible = false
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.timeout.connect(_refresh_diagnostics)
	add_child(timer)


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
	_time_label.text = GameClock.format_time() + ":%02d" % second
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
	var values: Array = [state, _pawn_is_player, state.qi, state.stamina, int(state.hunger), int(state.energy), int(state.mood), state.rank]
	if values == _last_pawn_values:
		return
	_last_pawn_values = values
	_pawn_name.text = ("你 · " if _pawn_is_player else "") + (state.display_name() if _display_name.is_empty() else _display_name)
	var role: String = state.rank_name()
	if not state.role_name().is_empty() and state.role_name() != role:
		role += " · " + state.role_name()
	_pawn_role.text = "%s  /  %s" % [role, state.realm_name()]
	_pawn_resources.text = "灵力 %d/%d  ·  体力 %d/%d" % [state.qi, state.max_qi(), state.stamina, state.max_stamina()]
	_hunger.value = state.hunger
	_energy.value = state.energy
	_hunger_value.text = str(int(state.hunger))
	_energy_value.text = str(int(state.energy))
	_hunger.modulate = UI.WARNING if state.hunger < 35 else Color.WHITE
	_energy.modulate = UI.WARNING if state.energy < 35 else Color.WHITE
	_pawn_mood.text = "心情 %d  ·  出身 %s" % [int(state.mood), state.origin_name()]
	_pawn_bio.text = state.bio_text()


func _toggle_biography() -> void:
	_pawn_bio.visible = not _pawn_bio.visible


func _on_help_requested() -> void:
	help_requested.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_diagnostics.visible = not _diagnostics.visible
		_refresh_diagnostics()
		get_viewport().set_input_as_handled()


func _refresh_diagnostics() -> void:
	if _diagnostics == null or not _diagnostics.visible or _world == null or _player == null or _camera == null:
		return
	var fog_text: String = "?"
	if _fog != null:
		fog_text = ["未见", "曾见", "可见"][_fog.get_state(_player.cell)]
	_diagnostic_text.text = "开发诊断 · F3收起\nFPS %d  |  格 (%d,%d)  %s  |  高度 %d / 飞行 %d\n迷雾 %s  |  区块 %d  |  缩放 %.2f" % [int(Engine.get_frames_per_second()), _player.cell.x, _player.cell.y, _world.terrain_name(_player.cell), _world.get_elevation(_player.cell), _player.altitude, fog_text, _world.loaded_chunk_count(), _camera.zoom.x]
