@tool
class_name OpeningLayoutDef
extends Resource
## A reusable room, work yard or other group of placement patterns.
const Placement = preload("res://scripts/sim/definitions/openings/placement_def.gd")
@export var id: String = ""
@export var origin: Vector2i = Vector2i.ZERO
@export_range(1, 100) var repeats: int = 1
@export var stride: Vector2i = Vector2i.ZERO
@export var placements: Array[Placement] = []
