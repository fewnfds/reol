class_name CommittedWorldCanvas
extends Node2D
## Rebuildable visible draw parameters from one complete world boundary.
## Derived views provide runtime() and _build_canvas(); no simulation is copied.

var _canvas_commands: Array[Callable] = []
var _canvas_candidate: Array[Callable] = []
var _canvas_world: WeakRef
var _canvas_at_ms: int = -1
var _canvas_input_key: Variant
# Managed world views publish together after the clock's ordinary observers.
# Standalone views and changes outside clock advancement still capture at once.
var clock_published_canvas: bool = false


func _canvas_adapter() -> Node:
	return call("runtime") as Node if has_method("runtime") else null


func _current_canvas_world() -> RefCounted:
	var adapter: Node = _canvas_adapter()
	return adapter.get("world_sim") as RefCounted if adapter != null else null


func _world_is_complete(world: RefCounted) -> bool:
	if world == null:
		return false
	var kernel: Object = world.get("settlement") as Object
	return kernel == null or not bool(kernel.call("is_pending"))


func can_refresh_canvas() -> bool:
	return _world_is_complete(_current_canvas_world())


func clear_committed_canvas() -> void:
	if not can_refresh_canvas():
		return
	_canvas_commands.clear()
	_canvas_world = null
	_canvas_at_ms = -1
	redraw_committed_canvas()


func redraw_committed_canvas(publish: bool = false) -> void:
	if clock_published_canvas and GameClock.is_advancing() and not publish:
		return
	# Capture synchronously. A deferred _draw may run only after another
	# boundary has already suspended, so it must never be the capture owner.
	if refresh_committed_canvas():
		queue_redraw()


func refresh_committed_canvas() -> bool:
	var world: RefCounted = _current_canvas_world()
	if world == null or (_canvas_world != null and _canvas_world.get_ref() != world):
		_canvas_commands.clear()
		_canvas_world = null
		_canvas_at_ms = -1
		_canvas_input_key = null
	if not _world_is_complete(world):
		return false
	var input_key: Variant = _committed_canvas_input_key()
	if input_key != null and _canvas_world != null and input_key == _canvas_input_key:
		return false
	_canvas_candidate = []
	_build_canvas()
	var current: RefCounted = _current_canvas_world()
	if current == world and _world_is_complete(world):
		_canvas_commands = _canvas_candidate
		_canvas_world = weakref(world)
		_canvas_at_ms = int(world.get("elapsed_ms"))
		_canvas_input_key = input_key
	elif current != world:
		_canvas_commands.clear()
		_canvas_world = null
		_canvas_at_ms = -1
	_canvas_candidate = []
	return true


func _committed_canvas_input_key() -> Variant:
	# Time-dependent views retain the ordinary capture path. A view may opt in
	# only with a complete key for the inputs actually read by its drawing.
	return null


func _build_canvas() -> void:
	pass


func _draw() -> void:
	# Even an earlier queue_redraw may arrive during a suspended boundary.
	# Only these captured parameters are read while replaying that old view.
	draw_set_transform(Vector2.ZERO)
	for command: Callable in _canvas_commands:
		command.call()
	draw_set_transform(Vector2.ZERO)


func capture_custom(command: Callable) -> void:
	# Custom callbacks must only draw using captured presentation arguments.
	_canvas_candidate.append(command)


func capture_line(from: Vector2, to: Vector2, color: Color, width: float = -1.0, antialiased: bool = false) -> void:
	_canvas_candidate.append(draw_line.bind(from, to, color, width, antialiased))


func capture_rect(bounds: Rect2, color: Color, filled: bool = true, width: float = -1.0, antialiased: bool = false) -> void:
	_canvas_candidate.append(draw_rect.bind(bounds, color, filled, width, antialiased))


func capture_circle(center: Vector2, radius: float, color: Color, filled: bool = true, width: float = -1.0, antialiased: bool = false) -> void:
	_canvas_candidate.append(draw_circle.bind(center, radius, color, filled, width, antialiased))


func capture_arc(center: Vector2, radius: float, start: float, end: float, point_count: int, color: Color, width: float = -1.0, antialiased: bool = false) -> void:
	_canvas_candidate.append(draw_arc.bind(center, radius, start, end, point_count, color, width, antialiased))


func capture_polygon(points: PackedVector2Array, color: Color, uvs: PackedVector2Array = PackedVector2Array(), texture: Texture2D = null) -> void:
	_canvas_candidate.append(draw_colored_polygon.bind(points, color, uvs, texture))


func capture_polyline(points: PackedVector2Array, color: Color, width: float = -1.0, antialiased: bool = false) -> void:
	_canvas_candidate.append(draw_polyline.bind(points, color, width, antialiased))


func capture_text(font: Font, pos: Vector2, text: String, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, font_size: int = 16, color: Color = Color.WHITE, justification_flags: int = 3, direction: int = 0, orientation: int = 0, oversampling: float = 0.0) -> void:
	_canvas_candidate.append(draw_string.bind(font, pos, text, alignment, width, font_size, color, justification_flags, direction, orientation, oversampling))


func capture_text_outline(font: Font, pos: Vector2, text: String, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, font_size: int = 16, size: int = 1, color: Color = Color.WHITE, justification_flags: int = 3, direction: int = 0, orientation: int = 0, oversampling: float = 0.0) -> void:
	_canvas_candidate.append(draw_string_outline.bind(font, pos, text, alignment, width, font_size, size, color, justification_flags, direction, orientation, oversampling))


func capture_transform(offset: Vector2, rotation: float = 0.0, scale_value: Vector2 = Vector2.ONE) -> void:
	_canvas_candidate.append(draw_set_transform.bind(offset, rotation, scale_value))
