extends Node
## Pure 2D display boundary. The simulation and all world drawing stay in XY.
## UI/input stay in the window; only this world texture receives the image warp.
const WARP = preload("res://scripts/presentation/view_warp.gdshader")
const MAX_STRENGTH: float = 0.04
const SAMPLE_MARGIN: int = 2 # Filter guard; shake moves the camera, not the sampled UV.
var world := Node2D.new()
var viewport := SubViewport.new()
var camera := Camera2D.new()
var strength: float = 0.0
var _output := TextureRect.new()
var _material := ShaderMaterial.new()
var _size := Vector2.ONE
var _configured_strength: float = -1.0

func _ready() -> void:
	viewport.disable_3d = true
	viewport.world_2d = World2D.new()
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.add_child(world)
	world.add_child(camera)
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	layer.add_child(_output)
	_output.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_output.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_output.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_output.texture = viewport.get_texture()
	_material.shader = WARP
	_output.material = _material
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	get_viewport().size_changed.connect(sync)
	sync()

func sync() -> void:
	strength = clampf(strength, 0.0, MAX_STRENGTH)
	_size = get_viewport().get_visible_rect().size.max(Vector2.ONE)
	# Camera shake is already rendered inside the source texture. It requires
	# no additional UV margin. Keep matching pixel parity for a centred crop.
	var base := Vector2i(_size.ceil())
	var extent := Vector2i((_size / (1.0 - strength)).ceil())
	if strength > 0.0: extent += Vector2i.ONE * SAMPLE_MARGIN * 2
	extent.x += posmod(extent.x - base.x, 2)
	extent.y += posmod(extent.y - base.y, 2)
	if viewport.size != extent or _output.size != _size or _configured_strength != strength:
		viewport.size = extent
		_output.size = _size
		_material.set_shader_parameter("strength", strength)
		_material.set_shader_parameter("output_size", _size)
		_material.set_shader_parameter("source_size", Vector2(extent))
		_configured_strength = strength
	camera.force_update_scroll()

static func warp(point: Vector2, k: float) -> Vector2:
	return point / (1.0 - k * point.y)

static func unwarp(point: Vector2, k: float) -> Vector2:
	return point / (1.0 + k * point.y)

func project(pixel: Vector2, shaken: bool = true) -> Vector2:
	var source: Vector2 = viewport.canvas_transform * (pixel + (Vector2.ZERO if shaken else camera.offset))
	var normal: Vector2 = (source - Vector2(viewport.size) * 0.5) / (_size * 0.5)
	return (warp(normal, strength) + Vector2.ONE) * _size * 0.5

func ground(screen: Vector2, shaken: bool = false) -> Vector2:
	var normal: Vector2 = unwarp(screen / (_size * 0.5) - Vector2.ONE, strength)
	var source: Vector2 = normal * _size * 0.5 + Vector2(viewport.size) * 0.5
	var pixel: Vector2 = viewport.canvas_transform.affine_inverse() * source
	return pixel - (Vector2.ZERO if shaken else camera.offset)

func visible_rect() -> Rect2:
	var rect := Rect2(ground(Vector2.ZERO), Vector2.ZERO)
	for point: Vector2 in [Vector2(_size.x, 0), _size, Vector2(0, _size.y)]: rect = rect.expand(ground(point))
	return rect

func pan_pixels(delta: Vector2) -> void:
	var center: Vector2 = _size * 0.5
	camera.position += ground(center + delta) - ground(center)
	camera.force_update_scroll()
