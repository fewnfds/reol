class_name PlayerCharacter
extends CharacterBody2D
## Placeholder player avatar.
##
## Movement is grid-aware: the world decides whether a step is legal, and the
## player sweeps its motion in small substeps so low FPS cannot tunnel through
## blocked cells. Speed ramps up/down instead of snapping to full velocity.

@export var speed: float = 240.0
@export var acceleration: float = 1800.0
@export var friction: float = 2600.0

const MAX_SUBSTEP_PX: float = 12.0

var cell: Vector2i = Vector2i.ZERO
var altitude: int = 0
var blocked: bool = false
var state: PawnState
var selected: bool = false

var _world: ReolWorld
var _velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	_world = get_parent().get_node_or_null("World") as ReolWorld
	z_index = 10


func setup_state(value: PawnState) -> void:
	state = value
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func selection_center() -> Vector2:
	var elevation: int = 0
	if _world != null:
		elevation = _world.get_elevation(cell)
	return global_position + Vector2(
		0.0,
		-float(
			elevation * ReolWorld.ELEVATION_PX
			+ altitude * ReolWorld.ALTITUDE_PX
		) - 12.0
	)


func spawn_at(spawn_cell: Vector2i) -> void:
	cell = spawn_cell
	global_position = TileGrid.cell_to_world(cell)
	_velocity = Vector2.ZERO
	blocked = false
	queue_redraw()


func set_altitude(value: int) -> void:
	altitude = clampi(value, 0, 2)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _world == null:
		return

	var direction := Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	var target_velocity: Vector2 = direction.normalized() * speed
	var rate: float = acceleration if direction != Vector2.ZERO else friction
	_velocity = _velocity.move_toward(target_velocity, rate * delta)
	if _velocity.length_squared() < 1.0:
		_velocity = Vector2.ZERO
		blocked = false
		return

	blocked = false
	var motion: Vector2 = _velocity * delta
	var substeps: int = maxi(1, ceili(motion.length() / MAX_SUBSTEP_PX))
	for _index in substeps:
		_move_step(motion / float(substeps))


func _move_step(motion: Vector2) -> void:
	var target: Vector2 = global_position + motion
	if _try_move_to(target):
		return

	var moved: bool = false
	if not is_zero_approx(motion.x):
		if _try_move_to(global_position + Vector2(motion.x, 0.0)):
			moved = true
		else:
			_velocity.x = 0.0
	if not is_zero_approx(motion.y):
		if _try_move_to(global_position + Vector2(0.0, motion.y)):
			moved = true
		else:
			_velocity.y = 0.0

	if not moved:
		blocked = true
		_velocity = Vector2.ZERO


func _try_move_to(target: Vector2) -> bool:
	var target_cell: Vector2i = TileGrid.world_to_cell(target)
	if target_cell == cell:
		global_position = target
		return true
	if not _world.can_step(cell, target_cell - cell):
		return false
	global_position = target
	cell = target_cell
	queue_redraw()
	return true


func _draw() -> void:
	var elevation: int = 0
	if _world != null:
		elevation = _world.get_elevation(cell)
	var ground_offset := Vector2(0.0, -float(elevation * ReolWorld.ELEVATION_PX))
	var body_offset := ground_offset - Vector2(
		0.0, float(altitude * ReolWorld.ALTITUDE_PX)
	)

	var shadow := PackedVector2Array([
		Vector2(-12.0, 2.0) + ground_offset,
		Vector2(0.0, 8.0) + ground_offset,
		Vector2(12.0, 2.0) + ground_offset,
		Vector2(0.0, -4.0) + ground_offset,
	])
	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.28))
	if selected:
		draw_arc(ground_offset, 17.0, 0.0, TAU, 24, Color("#e8c86a"), 2.0)
	draw_circle(Vector2(0.0, -20.0) + body_offset, 8.0, Color("#e6d3b3"))
	draw_rect(
		Rect2(Vector2(-8.0, -13.0) + body_offset, Vector2(16.0, 23.0)),
		Color("#b23a2f")
	)
	draw_rect(
		Rect2(Vector2(-6.0, 10.0) + body_offset, Vector2(5.0, 8.0)),
		Color("#2b2b2b")
	)
	draw_rect(
		Rect2(Vector2(1.0, 10.0) + body_offset, Vector2(5.0, 8.0)),
		Color("#2b2b2b")
	)

	if state != null:
		var font: Font = ThemeDB.fallback_font
		var text: String = state.display_name()
		var text_pos: Vector2 = body_offset + Vector2(-48.0, -36.0)
		draw_string_outline(
			font,
			text_pos,
			text,
			HORIZONTAL_ALIGNMENT_CENTER,
			96.0,
			12,
			3,
			Color(0.0, 0.0, 0.0, 0.85)
		)
		draw_string(
			font,
			text_pos,
			text,
			HORIZONTAL_ALIGNMENT_CENTER,
			96.0,
			12,
			Color("#e8e0d0")
		)
