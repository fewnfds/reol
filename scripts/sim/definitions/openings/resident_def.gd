@tool
class_name OpeningResidentDef
extends Resource
## Initial personal differences, not a runtime profession or forced schedule.
@export var slots: PackedInt32Array = []
@export var name_prefix: String = "弟子"
@export var mastered: PackedStringArray = []
@export var public_teachings: PackedStringArray = []
@export var introduced: PackedStringArray = []
@export var development: PackedStringArray = []
@export_range(-1, 255) var mentor_slot: int = -1
@export var instruction_targets: PackedInt32Array = []
@export var instruction_method: String = ""
@export var dispositions: Dictionary[String, float] = {}
