@tool
extends Resource
## One-time authored employment/authority; titles are presentation only.
@export var actor_slots: PackedInt32Array = []
@export var duties: PackedStringArray = []
@export var groups: PackedStringArray = []
@export var title: String = "成员"
@export var capabilities: PackedStringArray = []
@export var descendants: bool = false
@export var authority_group: String = ""
