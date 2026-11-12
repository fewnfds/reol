extends Node2D
## Static canvas is rebuilt only when adopting another terrain revision.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const TILE: float = 32.0
const SOURCE_COLORS: Array[Color] = [Color.ORANGE_RED, Color.SKY_BLUE, Color.SILVER, Color.LIME_GREEN, Color.DODGER_BLUE, Color.RED, Color.SANDY_BROWN]
var terrain: RefCounted


func adopt(value: RefCounted) -> void:
	if terrain == value:
		return
	terrain = value
	queue_redraw()


func _draw() -> void:
	if terrain == null:
		return
	draw_rect(Rect2(0, 0, Terrain.SIZE * TILE, Terrain.SIZE * TILE), Color(0.11, 0.17, 0.13))
	for y: int in range(160, 281):
		draw_line(Vector2(160, y) * TILE, Vector2(280, y) * TILE, Color(0.16, 0.22, 0.17), 0.6)
	for x: int in range(160, 281):
		draw_line(Vector2(x, 160) * TILE, Vector2(x, 280) * TILE, Color(0.16, 0.22, 0.17), 0.6)
	for tile: int in terrain.structures:
		var rect := Rect2(Vector2(Terrain.cell(tile)) * TILE + Vector2.ONE, Vector2.ONE * (TILE - 2.0))
		var color := Color(0.38, 0.39, 0.4) if terrain.blocked[tile] != 0 else Color(0.29, 0.25, 0.21)
		draw_rect(rect, color)
		if terrain.blocked[tile] != 0:
			draw_line(rect.position, rect.end - Vector2(0, rect.size.y), Color(0.62, 0.61, 0.57), 3.0)
	for tile: int in terrain.resources:
		var point: Vector2 = Terrain.center(tile) * TILE
		draw_circle(point, 9.0, Color(0.24, 0.58, 0.3))
		draw_line(point, point - Vector2(0, 18), Color(0.4, 0.68, 0.3), 5.0)
	for tile: int in terrain.depots:
		draw_rect(Rect2(Vector2(Terrain.cell(tile)) * TILE + Vector2(2, 2), Vector2(28, 28)), Color(0.76, 0.56, 0.2))
	for source: int in terrain.source_cells.size():
		var color: Color = SOURCE_COLORS[terrain.source_channels[source]]
		draw_circle(Terrain.center(terrain.source_cells[source]) * TILE, 5.0, color)
