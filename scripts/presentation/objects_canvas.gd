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
			"landmark":
				draw_line(point, point - Vector2(0, 30), Color(0.6, 0.45, 0.2), 5)
				draw_rect(Rect2(point - Vector2(10, 30), Vector2(24, 12)), Color(0.5, 0.75, 0.7))
			"wall", "door":
				var rect := Rect2(Vector2(Terrain.cell(object.tile)) * TILE + Vector2.ONE, Vector2.ONE * (TILE - 2.0))
				draw_rect(rect, Color(0.4, 0.41, 0.42) if object.kind == "wall" else Color(0.43, 0.28, 0.15))
				if object.kind == "wall":
					draw_line(rect.position, rect.position + Vector2(30, 0), Color(0.7, 0.7, 0.6), 3)
			"plant":
				var stage: int = int(object.get("stage", 0))
				var color := Color(0.25, 0.65, 0.36)
				if object.definition == "fire_herb":
					color = Color(0.9, 0.3, 0.12)
				elif object.definition == "lotus":
					color = Color(0.9, 0.55, 0.75)
				if stage in [3, 4]:
					color = Color(0.44, 0.3, 0.18)
				if object.definition == "old_tree":
					if stage == 3:
						draw_rect(Rect2(point - Vector2(4, 7), Vector2(8, 7)), Color(0.4, 0.3, 0.2))
						draw_line(point - Vector2(4, 7), point + Vector2(4, -7), Color(0.65, 0.48, 0.3), 2)
					elif stage == 4:
						draw_line(point, point + Vector2.UP * 24, Color(0.4, 0.3, 0.2), 5)
						draw_line(point + Vector2(0, -12), point + Vector2(-9, -22), Color(0.4, 0.3, 0.2), 3)
						draw_line(point + Vector2(0, -15), point + Vector2(8, -26), Color(0.4, 0.3, 0.2), 3)
					else:
						_draw_tree(point, 24 if stage == 2 else 14, 18 if stage == 2 else 6, color)
				else:
					draw_circle(point, 11 if stage == 2 else 5, color)
				if object.get("sapient", false):
					draw_arc(point, 20, 0, TAU, 24, Color.GOLD, 2)
			"resource":
				_draw_tree(point, 20, 11, Color(0.24, 0.58, 0.3))
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


func _draw_tree(foot: Vector2, height: float, crown_radius: float, foliage: Color) -> void:
	# The tile position is the ground anchor. Canvas Y grows down, so both
	# resource trees and living plants put their crown above the same foot.
	var crown: Vector2 = foot + Vector2.UP * height
	draw_line(foot, crown, Color(0.4, 0.3, 0.2), maxf(3.0, crown_radius * 0.4))
	draw_circle(crown, crown_radius, foliage)
