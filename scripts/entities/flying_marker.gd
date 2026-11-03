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

	draw_set_transform(ground_offset + Vector2(0, 3), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 11.0, Color(0.04, 0.08, 0.08, 0.25))
	draw_set_transform(Vector2.ZERO)
	draw_colored_polygon(PackedVector2Array([
		body_offset + Vector2(-15, -6), body_offset + Vector2(0, -11),
		body_offset + Vector2(15, -6), body_offset + Vector2(4, -1),
		body_offset + Vector2(0, 6), body_offset + Vector2(-4, -1),
	]), Color("#9dc9be"))
	draw_line(body_offset + Vector2(-12, -6), body_offset + Vector2(12, -6), Color("#dce4cf"), 1.5)
	draw_circle(body_offset + Vector2(0, -11), 3.0, Color("#edf0d9"))
