@tool
extends Resource
const Assignment = preload("res://scripts/sim/definitions/openings/work_assignment_def.gd")
@export var key: String = ""
@export var title: String = ""
@export var parent_key: String = ""
@export var facility_keys: PackedStringArray = []
@export var head_slot: int = -1
@export var assignments: Array[Assignment] = []
## Named work groups refer to symbolic placement groups, resolved only at assembly.
@export var groups: Dictionary[String, PackedStringArray] = {}

@export var supplier_key: String = ""
@export var production_operation: String = ""
@export var production_item: String = ""
@export_range(0, 1000000) var daily_target: int = 0
@export var storage_items: Dictionary[String, PackedStringArray] = {}
