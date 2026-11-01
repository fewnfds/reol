class_name GameHUD
extends CanvasLayer
## Minimal debug HUD for the M1 iso slice.

var _world: ReolWorld
var _player: PlayerCharacter
var _camera: CameraController
var _fog: FogOfWar
var _label: Label


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
		"Reol M1 · 2D 正交俯视\n%s · %s | FPS %d | cell (%d,%d) | %s | elev %d | alt %d | fog %s | chunks %d | zoom %.2f\n空格 暂停 · 1/2/4 速度 · WASD 移动 · 方向键 平移 · 滚轮缩放 · 中键拖拽 · F 居中"
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
