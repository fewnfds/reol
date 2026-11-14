@tool
extends EditorInspectorPlugin
const Ability = preload("res://scripts/sim/definitions/combat/ability_def.gd")
const Preview = preload("res://addons/reol_combat_authoring/preview.gd")
func _can_handle(object: Object) -> bool: return object is Ability
func _parse_begin(object: Object) -> void:
	var preview := Preview.new()
	preview.definition = object
	add_custom_control(preview)
