@tool
extends EditorInspectorPlugin
const Ability = preload("res://scripts/sim/definitions/combat/ability_def.gd")
const Preview = preload("res://addons/reol_combat_authoring/preview.gd")
const Validation = preload("res://addons/reol_combat_authoring/validation.gd")
func _can_handle(object: Object) -> bool:
	if not object is Resource or not object.has_method("errors") and not object.has_method("compile"): return false
	var script: Script = object.get_script()
	return script != null and (script.resource_path.begins_with("res://scripts/sim/definitions/actions/") or script.resource_path.begins_with("res://scripts/sim/definitions/combat/") or script.resource_path.begins_with("res://scripts/sim/definitions/decisions/"))
func _parse_begin(object: Object) -> void:
	if object is Ability:
		var preview := Preview.new()
		preview.definition = object
		add_custom_control(preview)
	var validation := Validation.new()
	validation.definition = object
	add_custom_control(validation)
