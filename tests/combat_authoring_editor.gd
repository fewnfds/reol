@tool
extends Node
## Open the companion scene in a disposable editor; checks the real Inspector.
var errors: int = 0
func _ready() -> void:
	if Engine.is_editor_hint() and OS.get_cmdline_user_args().has("--combat-authoring-check"): call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok: errors += 1; push_error(message)
func preview() -> Control:
	for control: Node in EditorInterface.get_inspector().find_children("*", "Control", true, false):
		if control.get_script() != null and control.get_script().resource_path == "res://addons/reol_combat_authoring/preview.gd": return control
	return null
func frames() -> void:
	for index: int in 12: await get_tree().process_frame
func _run() -> void:
	await frames()
	var definition: Resource = load("res://data/definitions/combat/fire_bolt.tres")
	EditorInterface.edit_resource(definition)
	await frames()
	var control: Control = preview()
	check(control != null, "Combat Inspector plugin missing")
	if control != null:
		check(control.size.y >= 280 and control.is_visible_in_tree(), "Resource preview has no visible layout")
		for button: Node in control.get_children():
			if button is Button: button.pressed.emit()
		check(control._validation.text.contains("通过"), "Real Inspector validation did not run")
	var invalid: Resource = definition.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	invalid.windup = -1
	EditorInterface.edit_resource(invalid)
	await frames()
	control = preview()
	if control != null:
		for button: Node in control.get_children():
			if button is Button: button.pressed.emit()
		check(control._validation.text.contains("timing"), "Invalid Resource has no field-level diagnostic")
	EditorInterface.edit_resource(definition)
	await frames()
	control = preview()
	if control != null:
		for button: Node in control.get_children():
			if button is Button: button.pressed.emit()
	await RenderingServer.frame_post_draw
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("res://logs/combat-authoring-editor.png")
	print("COMBAT_AUTHORING_EDITOR errors=", errors)
	get_tree().quit(0 if errors == 0 else 1)
