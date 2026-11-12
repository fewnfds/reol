extends Node2D
const ShaderFile = preload("res://scripts/presentation/fog.gdshader")
var shade := ShaderMaterial.new()
var explored: ImageTexture
var visibility: ImageTexture
var softness: ImageTexture
var revision: int = -1
var epoch: int = -1

func _init() -> void:
	shade.shader = ShaderFile
	material = shade
	z_index = -9

func adopt(frame: RefCounted) -> void:
	if epoch == frame.epoch and revision == frame.perception.get("revision", -1):
		return
	epoch = frame.epoch
	revision = frame.perception.revision
	var history := Image.create_from_data(512, 512, false, Image.FORMAT_R8, frame.perception.explored)
	var soft := Image.create_from_data(512, 512, false, Image.FORMAT_R8, frame.perception.softness)
	var current := Image.create_from_data(512, 512, false, Image.FORMAT_R8, frame.perception.tiles)
	if explored == null:
		explored = ImageTexture.create_from_image(history)
		visibility = ImageTexture.create_from_image(current)
		softness = ImageTexture.create_from_image(soft)
		shade.set_shader_parameter("explored_map", explored)
		shade.set_shader_parameter("visible_map", softness)
	else:
		explored.update(history)
		visibility.update(current)
		softness.update(soft)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 512 * 32, 512 * 32), Color.WHITE)
