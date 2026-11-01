class_name CameraController
extends Camera2D
## Fixed-angle orthographic top-down camera: free pan + zoom, no rotation.

@export var pan_speed: float = 760.0
@export var zoom_step: float = 0.1
@export var min_zoom: float = 0.75
@export var max_zoom: float = 1.5

var _world_rect: Rect2 = Rect2()
var _focus_target: Node2D
var _dragging: bool = false


func setup(world_rect: Rect2, start_position: Vector2) -> void:
	_world_rect = world_rect
	global_position = start_position
	make_current()
	_clamp_to_world()


func set_focus_target(target: Node2D) -> void:
	_focus_target = target


func _process(delta: float) -> void:
	var direction := Input.get_vector(
		"camera_left", "camera_right", "camera_up", "camera_down"
	)
	if direction != Vector2.ZERO:
		global_position += direction.normalized() * pan_speed * delta / zoom.x
		_clamp_to_world()

	if Input.is_action_just_pressed("zoom_in"):
		_zoom_by(zoom_step)
	elif Input.is_action_just_pressed("zoom_out"):
		_zoom_by(-zoom_step)

	if Input.is_action_just_pressed("center_camera") and _focus_target != null:
		global_position = _focus_target.global_position
		_clamp_to_world()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mouse_button.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mouse_motion := event as InputEventMouseMotion
		global_position -= mouse_motion.relative / zoom.x
		_clamp_to_world()


func _zoom_by(amount: float) -> void:
	var next_zoom: float = clampf(zoom.x + amount, min_zoom, max_zoom)
	zoom = Vector2(next_zoom, next_zoom)
	_clamp_to_world()


func _clamp_to_world() -> void:
	if _world_rect.size == Vector2.ZERO:
		return
	var half_view: Vector2 = get_viewport_rect().size * 0.5 / zoom
	var min_x: float = _world_rect.position.x + half_view.x
	var max_x: float = _world_rect.end.x - half_view.x
	var min_y: float = _world_rect.position.y + half_view.y
	var max_y: float = _world_rect.end.y - half_view.y

	if min_x > max_x:
		global_position.x = _world_rect.get_center().x
	else:
		global_position.x = clampf(global_position.x, min_x, max_x)

	if min_y > max_y:
		global_position.y = _world_rect.get_center().y
	else:
		global_position.y = clampf(global_position.y, min_y, max_y)
