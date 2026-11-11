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
var complete: bool = true
var partial_cells: Dictionary = {}
var _faces: Array[Dictionary] = []


func rebuild() -> void:
	_faces.clear()
	if world == null:
		return
	var base: Vector2i = chunk * chunk_size
	if not complete:
		for cell: Vector2i in partial_cells:
			_draw_cell(cell, cell - base)
		queue_redraw()
		return
	for local_y in range(chunk_size):
		for local_x in range(chunk_size):
			var cell: Vector2i = base + Vector2i(local_x, local_y)
			_draw_cell(cell, Vector2i(local_x, local_y))
	queue_redraw()


func _draw_cell(cell: Vector2i, local_cell: Vector2i) -> void:
	var elevation: int = world.get_elevation(cell)
	if elevation <= 0:
		return
	var south: Vector2i = cell + Vector2i(0, 1)
	var south_elevation: int = world.get_elevation(south)
	if south_elevation < 0 or south_elevation >= elevation:
		return
	var drop: int = (elevation - south_elevation) * elevation_px
	var x: float = float(local_cell.x * tile_size)
	var y: float = float((local_cell.y + 1) * tile_size - elevation * elevation_px)
	var terrain: int = world.get_terrain(cell)
	var cliff_color := Color("#414c3c")
	if terrain == 2:
		cliff_color = Color("#4b4f47")
	elif terrain == 0:
		cliff_color = Color("#213b43")
	_faces.append({"rect": Rect2(x, y, float(tile_size), float(drop)), "color": cliff_color})


func _draw() -> void:
	# Drawing can overlap simulation. Terrain queries happened in the host's
	# complete-world phase; replay retains only display values.
	for face: Dictionary in _faces:
		var rect: Rect2 = face.rect
		var color: Color = face.color
		draw_rect(rect, color)
		draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), color.lightened(0.18), 1.0)
		draw_line(Vector2(rect.position.x, rect.end.y - 1), rect.end - Vector2(0, 1), color.darkened(0.2), 1.0)
