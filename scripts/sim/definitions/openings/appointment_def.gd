@tool
class_name OpeningAppointmentDef
extends Resource
## Symbolic local placement groups resolve once to canonical appointment IDs.
@export_range(0, 255) var actor_slot: int = 0
@export var role: String = ""
@export var target_key: String = ""
@export_range(0, 255) var target_index: int = 0
@export var source_keys: PackedStringArray = []
@export var sites_key: String = ""
@export_range(0, 255) var sites_start: int = 0
@export_range(0, 32) var sites_count: int = 0
@export var destination_key: String = ""
@export var channel_key: String = ""
