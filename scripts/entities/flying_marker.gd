class_name FlyingMarker
extends Node2D
## Placeholder flying unit used to verify altitude offset + ground shadow.

var world: ReolWorld
var cell: Vector2i = Vector2i.ZERO
var altitude: int = 1


func setup(world_ref: ReolWorld, spawn_cell: Vector2i, spawn_altitude: int) -> void:
	world = world_ref
	cell = spawn_cell
	altitude = clampi(spawn_altitude, 1, 2)
	global_position = TileGrid.cell_to_world(cell)
	z_index = 11
	queue_redraw()


func _draw() -> void:
	var elevation: int = 0
	if world != null:
		elevation = world.get_elevation(cell)
	var ground_offset := Vector2(0.0, -float(elevation * ReolWorld.ELEVATION_PX))
	var body_offset := ground_offset - Vector2(
		0.0, float(altitude * ReolWorld.ALTITUDE_PX)
	)

	draw_circle(Vector2(0.0, 0.0) + ground_offset, 9.0, Color(0.0, 0.0, 0.0, 0.22))
	draw_circle(Vector2(0.0, -8.0) + body_offset, 10.0, Color("#7fd1c7"))
	draw_line(
		Vector2(0.0, -4.0) + body_offset,
		Vector2(0.0, 6.0) + body_offset,
		Color("#e8e0d0"),
		2.0
	)
	draw_circle(Vector2(0.0, -14.0) + body_offset, 3.0, Color("#e8e0d0"))
