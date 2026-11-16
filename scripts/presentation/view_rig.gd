extends Node
## Native 2D world and a single coordinate boundary for input and drawing.
## UI keeps its own CanvasLayer. No whole-world texture resampling pass.
var world := Node2D.new()
var camera := Camera2D.new()

func _ready() -> void:
	get_viewport().disable_3d = true
	world.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(world)
	world.add_child(camera)
	get_viewport().size_changed.connect(sync)
	sync()

func sync() -> void:
	camera.force_update_scroll()

func project(pixel: Vector2, shaken: bool = true) -> Vector2:
	return world.get_global_transform_with_canvas() * (pixel + (Vector2.ZERO if shaken else camera.offset))

func ground(screen: Vector2, shaken: bool = false) -> Vector2:
	# Mouse events use logical viewport coordinates; the Window stretch is
	# already removed by Godot. Shake remains an output-only camera offset.
	var pixel: Vector2 = world.get_global_transform_with_canvas().affine_inverse() * screen
	return pixel - (Vector2.ZERO if shaken else camera.offset)

func visible_rect() -> Rect2:
	var size: Vector2 = get_viewport().get_visible_rect().size
	var rect := Rect2(ground(Vector2.ZERO), Vector2.ZERO)
	for point: Vector2 in [Vector2(size.x, 0), size, Vector2(0, size.y)]: rect = rect.expand(ground(point))
	return rect

func pan_pixels(delta: Vector2) -> void:
	var center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	camera.position += ground(center + delta) - ground(center)
	camera.force_update_scroll()
