extends Node2D
## Static placement comes from immutable object descriptors, inventory on inspection.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const TILE: float = 32.0
var objects: Dictionary = {}
var by_tile: Dictionary = {}


func adopt(value: Dictionary) -> void:
	if is_same(objects, value):
		return
	objects = value
	by_tile = {}
	for id: int in objects:
		var tile: int = objects[id].tile
		for member: int in objects[id].get("cells", PackedInt32Array([tile])):
			if not by_tile.has(member):
				by_tile[member] = []
			by_tile[member].append(id)
	queue_redraw()


func _draw() -> void:
	for id: int in objects:
		var object: Dictionary = objects[id]
		var point: Vector2 = Terrain.center(object.tile) * TILE
		match object.kind:
			"resource":
				draw_circle(point, 9, Color(0.24, 0.58, 0.3))
				draw_line(point, point - Vector2(0, 18), Color(0.4, 0.68, 0.3), 5)
			"chest":
				draw_rect(Rect2(point - Vector2(13, 11), Vector2(26, 22)), Color(0.76, 0.56, 0.2))
				draw_rect(Rect2(point - Vector2(13, 11), Vector2(26, 22)), Color(0.3, 0.2, 0.1), false, 2)
				draw_line(point - Vector2(12, 4), point + Vector2(12, -4), Color(0.95, 0.8, 0.4), 2)
			"pile":
				draw_rect(Rect2(point - Vector2(12, 5), Vector2(24, 10)), Color(0.6, 0.36, 0.18))
				draw_rect(Rect2(point - Vector2(8, 12), Vector2(18, 6)), Color(0.72, 0.48, 0.25))
			"blueprint", "bed", "workbench", "furniture", "table", "chair", "roof":
				var color: Color = Color(0.25, 0.65, 0.85, 0.5) if object.kind == "blueprint" else Color(0.58, 0.39, 0.23)
				if object.definition in ["wood_bed", "long_bed"]:
					color = Color(0.45, 0.61, 0.68)
				elif object.definition == "cook_stove":
					color = Color(0.65, 0.28, 0.15)
				if object.layer == "roof":
					color = Color(0.3, 0.4, 0.65, 0.25)
				for tile: int in object.cells:
					var rect := Rect2(Vector2(Terrain.cell(tile)) * TILE + Vector2(2, 2), Vector2(28, 28))
					draw_rect(rect, color)
					draw_rect(rect, Color(0.8, 0.85, 0.9), false, 1)
