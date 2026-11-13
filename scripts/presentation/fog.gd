extends Node2D
const ShaderFile = preload("res://scripts/presentation/fog.gdshader")
var shade := ShaderMaterial.new()
var explored: ImageTexture
var visibility: ImageTexture
var _loss: ImageTexture
var _loss_revision: int = -1
var revision: int = -1
var epoch: int = -1

func _init() -> void:
	shade.shader = ShaderFile
	material = shade
	z_index = -9

func adopt(frame: RefCounted) -> void:
	if epoch == frame.epoch and revision == frame.perception.get("revision", -1):
		return
	if epoch != frame.epoch: _loss_revision = -1
	epoch = frame.epoch
	revision = frame.perception.revision
	if _loss_revision != frame.perception.get("loss_revision", -1):
		_loss_revision = frame.perception.loss_revision
		var image := Image.create_from_data(512, 512, false, Image.FORMAT_RF, frame.perception.loss)
		if _loss == null:
			_loss = ImageTexture.create_from_image(image)
			shade.set_shader_parameter("loss_map", _loss)
		else: _loss.update(image)
	var history := Image.create_from_data(512, 512, false, Image.FORMAT_R8, frame.perception.explored)
	var current := Image.create_from_data(512, 512, false, Image.FORMAT_R8, frame.perception.tiles)
	if explored == null:
		explored = ImageTexture.create_from_image(history)
		visibility = ImageTexture.create_from_image(current)
		shade.set_shader_parameter("explored_map", explored)
	else:
		explored.update(history)
		visibility.update(current)
	queue_redraw()

func follow_view(origin: Vector2, sight_range: float) -> void:
	shade.set_shader_parameter("view_origin", origin)
	shade.set_shader_parameter("view_range", sight_range)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 512 * 32, 512 * 32), Color.WHITE)
