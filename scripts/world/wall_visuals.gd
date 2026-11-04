class_name ReolWallVisuals
extends RefCounted
## Derived four-neighbour presentation, never occupancy or room authority.
## N/E/S/W bits are 1/2/4/8, shared with SimStructureQuery.wall_mask.

const DIRECTIONS: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
const BITS: Array[int] = [1, 2, 4, 8]
const WOOD := Color("#79583b")
const EDGE := Color("#453323")
const CAP := Color("#bea078")
const SHADOW := Color(0.0, 0.0, 0.0, 0.25)


static func draw_wall(canvas: CanvasItem, point: Vector2, mask: int) -> void:
	var reach: float = TileGrid.HALF_TILE
	# Joined arm endpoints reach the neighbouring cell's matching arm. Draw
	# shadows/outlines first so corners and T/cross junctions stay continuous.
	for index: int in range(4):
		if mask & BITS[index]:
			var end: Vector2 = point + DIRECTIONS[index] * reach
			canvas.draw_line(point + Vector2(3, 11), end + Vector2(3, 11), SHADOW, 23.0)
			canvas.draw_line(point, end, EDGE, 23.0)
	canvas.draw_rect(Rect2(point + Vector2(-12, -12), Vector2(24, 24)), EDGE)
	for index: int in range(4):
		if mask & BITS[index]:
			var end: Vector2 = point + DIRECTIONS[index] * reach
			canvas.draw_line(point, end, WOOD, 18.0)
			canvas.draw_line(point + Vector2(-2, -3), end + Vector2(-2, -3), CAP, 5.0)
	canvas.draw_rect(Rect2(point + Vector2(-8, -8), Vector2(16, 16)), WOOD)
	canvas.draw_rect(Rect2(point + Vector2(-8, -8), Vector2(16, 5)), CAP)
	if mask == 0:
		# The same mask can describe empty space or a solitary post. The caller
		# decides whether an actual built wall exists before requesting drawing.
		canvas.draw_rect(Rect2(point + Vector2(-10, 8), Vector2(20, 9)), EDGE)


static func draw_door(canvas: CanvasItem, point: Vector2, mask: int, opened: bool) -> void:
	# Orient the opening along its connecting wall. Ambiguous cross junctions
	# consistently choose east-west; this choice has no physical consequence.
	var axis: Vector2 = Vector2.RIGHT if mask & 10 else Vector2.DOWN
	var across := Vector2(-axis.y, axis.x)
	for sign_value: float in [-1.0, 1.0]:
		var post: Vector2 = point + axis * 23.0 * sign_value
		canvas.draw_line(post + Vector2(3, 10), post + Vector2(3, 14), SHADOW, 13.0)
		canvas.draw_line(post - across * 10.0, post + across * 10.0, EDGE, 12.0)
		canvas.draw_line(post - across * 9.0, post + across * 9.0, CAP, 5.0)
	if opened:
		canvas.draw_line(point - axis * 21.0, point - axis * 21.0 + across * 27.0, WOOD, 8.0)
	else:
		canvas.draw_line(point - axis * 21.0, point + axis * 21.0, EDGE, 20.0)
		canvas.draw_line(point - axis * 20.0, point + axis * 20.0, WOOD, 14.0)
		canvas.draw_line(point - axis * 20.0 - across * 4.0, point + axis * 20.0 - across * 4.0, CAP, 3.0)
		canvas.draw_circle(point + axis * 10.0, 3.0, Color("#d9be79"))
