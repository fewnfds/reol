extends Node2D
const ShaderFile = preload("res://scripts/presentation/fog.gdshader")
var shade := ShaderMaterial.new()
var explored: ImageTexture
var losses: ImageTexture
var revision: int = -1

func _init() -> void:
	shade.shader = ShaderFile
	material = shade
	z_index = 5

func adopt(frame: RefCounted) -> void:
	if revision == frame.perception.get("revision", -1):
		return
	revision = frame.perception.revision
	var history := Image.create_from_data(512, 512, false, Image.FORMAT_R8, frame.perception.explored)
	var cost := Image.create_from_data(512, 512, false, Image.FORMAT_R8, frame.perception.loss)
	if explored == null:
		explored = ImageTexture.create_from_image(history)
		losses = ImageTexture.create_from_image(cost)
		shade.set_shader_parameter("explored_map", explored)
		shade.set_shader_parameter("loss_map", losses)
	else:
		explored.update(history)
		losses.update(cost)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 512 * 32, 512 * 32), Color.WHITE)

func follow(point: Vector2) -> void:
	shade.set_shader_parameter("observer", point)
