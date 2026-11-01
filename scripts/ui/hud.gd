class_name GameHUD
extends CanvasLayer
## Minimal debug HUD for the M1 iso slice.

var _world: ReolWorld
var _player: PlayerCharacter
var _camera: CameraController
var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16.0, 12.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color("#e8e0d0"))
	_label.add_theme_color_override("font_outline_color", Color("#0b0f12"))
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)


func set_world(world: ReolWorld, player: PlayerCharacter, camera: CameraController) -> void:
	_world = world
	_player = player
	_camera = camera


func _process(_delta: float) -> void:
	if _world == null or _player == null or _camera == null:
		return
	var elevation: int = _world.get_elevation(_player.cell)
	_label.text = (
		"Reol M1 · 2D 正交俯视\nFPS %d | cell (%d,%d) | elev %d | chunks %d | zoom %.2f\nWASD 移动 · 方向键 平移 · 滚轮缩放 · 中键拖拽 · F 居中"
		% [
			int(Engine.get_frames_per_second()),
			_player.cell.x,
			_player.cell.y,
			elevation,
			_world.loaded_chunk_count(),
			_camera.zoom.x,
		]
	)
