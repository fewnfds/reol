class_name CliffChunk
extends Node2D
## Draws south-facing cliff faces for one loaded chunk.
##
## Each elevation layer is shifted up by `elevation_px`. When the cell to the
## south is lower, the vertical gap is filled with a dark cliff strip.

var world: ReolWorld
var chunk: Vector2i = Vector2i.ZERO
var chunk_size: int = 64
var tile_size: int = 64
var elevation_px: int = 16


func _draw() -> void:
	if world == null:
		return
	var base: Vector2i = chunk * chunk_size
	for local_y in range(chunk_size):
		for local_x in range(chunk_size):
			var cell: Vector2i = base + Vector2i(local_x, local_y)
			var elevation: int = world.get_elevation(cell)
			if elevation <= 0:
				continue
			var south: Vector2i = cell + Vector2i(0, 1)
			var south_elevation: int = world.get_elevation(south)
			if south_elevation < 0 or south_elevation >= elevation:
				continue

			var drop: int = (elevation - south_elevation) * elevation_px
			var x: float = float(local_x * tile_size)
			var y: float = float((local_y + 1) * tile_size - elevation * elevation_px)
			var terrain: int = world.get_terrain(cell)
			var cliff_color := Color("#414c3c")
			if terrain == 2:
				cliff_color = Color("#4b4f47")
			elif terrain == 0:
				cliff_color = Color("#213b43")
			draw_rect(
				Rect2(x, y, float(tile_size), float(drop)),
				cliff_color
			)
			draw_line(
				Vector2(x, y),
				Vector2(x + float(tile_size), y),
				cliff_color.lightened(0.18),
				1.0
			)
			draw_line(Vector2(x, y + float(drop) - 1.0), Vector2(x + float(tile_size), y + float(drop) - 1.0), cliff_color.darkened(0.2), 1.0)
