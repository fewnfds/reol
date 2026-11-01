class_name PlayerCharacter
extends CharacterBody2D
## Placeholder player avatar for the M1 iso slice.
## Grid-based blocking keeps movement deterministic; physics can replace it later.

@export var speed: float = 240.0

var cell: Vector2i = Vector2i.ZERO
var _world: ReolWorld


func _ready() -> void:
	_world = get_parent().get_node_or_null("World") as ReolWorld
	z_index = 10


func spawn_at(spawn_cell: Vector2i) -> void:
	cell = spawn_cell
	global_position = TileGrid.cell_to_world(cell)


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
	if _world.is_walkable(TileGrid.world_to_cell(target)):
		global_position = target
	else:
		var target_x: Vector2 = global_position + Vector2(motion.x, 0.0)
		if _world.is_walkable(TileGrid.world_to_cell(target_x)):
			global_position.x = target_x.x
		var target_y: Vector2 = global_position + Vector2(0.0, motion.y)
		if _world.is_walkable(TileGrid.world_to_cell(target_y)):
			global_position.y = target_y.y

	cell = TileGrid.world_to_cell(global_position)


func _draw() -> void:
	var shadow := PackedVector2Array([
		Vector2(-12.0, 2.0),
		Vector2(0.0, 8.0),
		Vector2(12.0, 2.0),
		Vector2(0.0, -4.0),
	])
	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.28))
	draw_circle(Vector2(0.0, -20.0), 8.0, Color("#e6d3b3"))
	draw_rect(Rect2(-8.0, -13.0, 16.0, 23.0), Color("#b23a2f"))
	draw_rect(Rect2(-6.0, 10.0, 5.0, 8.0), Color("#2b2b2b"))
	draw_rect(Rect2(1.0, 10.0, 5.0, 8.0), Color("#2b2b2b"))
