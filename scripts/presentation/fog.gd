extends Node2D
const ShaderFile = preload("res://scripts/presentation/fog.gdshader")
const OverlayShader = preload("res://scripts/presentation/fog_overlay.gdshader")
var shade := ShaderMaterial.new()
var mask := SubViewport.new()
var _dirty: bool = true
var _origin := Vector2.INF
var _range: float = -1.0
var explored: ImageTexture
var visibility: ImageTexture
var _loss: ImageTexture
var _loss_revision: int = -1
var revision: int = -1
var epoch: int = -1

func _init() -> void:
	shade.shader = ShaderFile
	mask.disable_3d = true
	mask.world_2d = World2D.new()
	mask.render_target_update_mode = SubViewport.UPDATE_DISABLED
	RenderingServer.viewport_set_measure_render_time(mask.get_viewport_rid(), true)
	var quad := Polygon2D.new()
	quad.polygon = PackedVector2Array([Vector2.ZERO, Vector2(16384, 0), Vector2(16384, 16384), Vector2(0, 16384)])
	quad.material = shade
	mask.add_child(quad)
	add_child(mask)
	var overlay := ShaderMaterial.new()
	overlay.shader = OverlayShader
	overlay.set_shader_parameter("fog_mask", mask.get_texture())
	material = overlay
	z_index = -9

func adopt(frame: RefCounted) -> void:
	if epoch == frame.epoch and revision == frame.perception.get("revision", -1):
		return
	if epoch != frame.epoch: _loss_revision = -1
	epoch = frame.epoch
	_dirty = true
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
	if origin == _origin and sight_range == _range: return
	_origin = origin
	_range = sight_range
	_dirty = true
	shade.set_shader_parameter("view_origin", origin)
	shade.set_shader_parameter("view_range", sight_range)

func sync_mask() -> bool:
	var viewport: Viewport = get_viewport()
	var extent: Vector2 = viewport.get_visible_rect().size
	var size := Vector2i((extent * 0.5).ceil()).max(Vector2i.ONE)
	if mask.size != size:
		mask.size = size
		_dirty = true
	var scale: Vector2 = Vector2(size) / extent
	var transform: Transform2D = viewport.get_canvas_transform()
	transform.x *= scale
	transform.y *= scale
	transform.origin *= scale
	if mask.canvas_transform != transform:
		mask.canvas_transform = transform
		_dirty = true
	var updated: bool = _dirty
	if updated:
		mask.render_target_update_mode = SubViewport.UPDATE_ONCE
		_dirty = false
	return updated

func _draw() -> void:
	draw_rect(Rect2(0, 0, 512 * 32, 512 * 32), Color.WHITE)
