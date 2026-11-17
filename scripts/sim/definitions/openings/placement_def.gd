@tool
class_name OpeningPlacementDef
extends Resource
## An authored placement pattern. Expanded identities belong to world owners.
@export var key: String = ""
@export var definition: String = ""
@export var offsets: Array[Vector2i] = [Vector2i.ZERO]
@export var extent: Vector2i = Vector2i.ONE
@export var spacing: Vector2i = Vector2i.ONE
@export_range(0, 3) var facing: int = 0
@export var stock: Dictionary[String, int] = {}
@export var member_food_service: bool = false

func points() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset: Vector2i in offsets:
		for y: int in extent.y:
			for x: int in extent.x: result.append(offset + Vector2i(x * spacing.x, y * spacing.y))
	return result
