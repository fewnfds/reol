class_name PlayerCharacter
extends CharacterBody2D
## Placeholder player avatar for the M1 iso slice.
## Grid-based blocking keeps movement deterministic; physics can replace it later.

@export var speed: float = 240.0

var cell: Vector2i = Vector2i.ZERO
var altitude: int = 0
var _world: ReolWorld


func _ready() -> void:
	_world = get_parent().get_node_or_null("World") as ReolWorld
	z_index = 10


func spawn_at(spawn_cell: Vector2i) -> void:
	cell = spawn_cell
	global_position = TileGrid.cell_to_world(cell)
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
	if direction == Vector2.ZERO:
		return

	var motion: Vector2 = direction.normalized() * speed * delta
	var target: Vector2 = global_position + motion
	if _world.can_move(cell, TileGrid.world_to_cell(target)):
		global_position = target
	else:
		var target_x: Vector2 = global_position + Vector2(motion.x, 0.0)
		if _world.can_move(cell, TileGrid.world_to_cell(target_x)):
			global_position.x = target_x.x
			cell = TileGrid.world_to_cell(global_position)
		var target_y: Vector2 = global_position + Vector2(0.0, motion.y)
		if _world.can_move(cell, TileGrid.world_to_cell(target_y)):
			global_position.y = target_y.y

	var new_cell: Vector2i = TileGrid.world_to_cell(global_position)
	if new_cell != cell:
		cell = new_cell
		queue_redraw()


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
