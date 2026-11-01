class_name GameHUD
extends CanvasLayer
## Minimal debug HUD for the M1 iso slice.

var _world: ReolWorld
var _player: PlayerCharacter
var _camera: CameraController
var _fog: FogOfWar
var _label: Label
var _pawn_panel: Panel
var _pawn_label: Label
var _pawn_state: PawnState
var _pawn_is_player: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.position = Vector2(16.0, 12.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color("#e8e0d0"))
	_label.add_theme_color_override("font_outline_color", Color("#0b0f12"))
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)
	_build_pawn_panel()


func set_world(
	world: ReolWorld,
	player: PlayerCharacter,
	camera: CameraController,
	fog: FogOfWar
) -> void:
	_world = world
	_player = player
	_camera = camera
	_fog = fog


func show_pawn_state(state: PawnState, is_player: bool = false) -> void:
	_pawn_state = state
	_pawn_is_player = is_player
	_refresh_pawn_panel()


func _build_pawn_panel() -> void:
	_pawn_panel = Panel.new()
	_pawn_panel.position = Vector2(908.0, 12.0)
	_pawn_panel.size = Vector2(356.0, 268.0)
	_pawn_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.07, 0.84)
	style.border_color = Color(0.45, 0.5, 0.42, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	_pawn_panel.add_theme_stylebox_override("panel", style)
	add_child(_pawn_panel)

	_pawn_label = Label.new()
	_pawn_label.position = Vector2(12.0, 10.0)
	_pawn_label.size = Vector2(332.0, 248.0)
	_pawn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pawn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pawn_label.add_theme_font_size_override("font_size", 14)
	_pawn_label.add_theme_color_override("font_color", Color("#e8e0d0"))
	_pawn_panel.add_child(_pawn_label)
	_pawn_panel.visible = false


func _refresh_pawn_panel() -> void:
	if _pawn_panel == null:
		return
	if _pawn_state == null:
		_pawn_panel.visible = false
		return
	_pawn_panel.visible = true
	var state: PawnState = _pawn_state
	var title: String = state.rank_name()
	if (
		not state.role_name().is_empty()
		and state.role_name() != state.rank_name()
	):
		title += " · " + state.role_name()
	if _pawn_is_player:
		title = "【你】%s · %s" % [state.display_name(), title]
	else:
		title = "%s · %s" % [state.display_name(), title]
	_pawn_label.text = (
		"%s\n出身：%s\n境界：%s\n灵力 %d/%d　体力 %d/%d\n饱食 %d　疲劳 %d　心情 %d\n贡献 %d　声望 %d\n\n%s"
		% [
			title,
			state.origin_name(),
			state.realm_name(),
			state.qi,
			state.max_qi(),
			state.stamina,
			state.max_stamina(),
			int(state.hunger),
			int(state.fatigue),
			int(state.mood),
			state.contribution,
			state.reputation,
			state.bio_text(),
		]
	)


func _process(_delta: float) -> void:
	if _world == null or _player == null or _camera == null:
		return
	var elevation: int = _world.get_elevation(_player.cell)
	var terrain: String = _world.terrain_name(_player.cell)
	var fog_text: String = "?"
	if _fog != null:
		var fog_states: Array[String] = ["hidden", "explored", "visible"]
		fog_text = fog_states[_fog.get_state(_player.cell)]
	var speed_text: String = "暂停" if GameClock.paused else "%dx" % int(GameClock.speed)
	_label.text = (
		"Reol M2 · 宗门生活\n%s · %s | FPS %d | cell (%d,%d) | %s | elev %d | alt %d | fog %s | chunks %d | zoom %.2f\n左键 选中 · 空格 暂停 · 1/2/4 速度 · WASD 移动 · 方向键 平移 · 滚轮缩放 · 中键拖拽 · F 居中"
		% [
			GameClock.format_time(),
			speed_text,
			int(Engine.get_frames_per_second()),
			_player.cell.x,
			_player.cell.y,
			terrain,
			elevation,
			_player.altitude,
			fog_text,
			_world.loaded_chunk_count(),
			_camera.zoom.x,
		]
	)
