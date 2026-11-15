@tool
extends Node
## Open the companion scene in a disposable editor; checks the real Inspector.
var errors: int = 0
func _ready() -> void:
	if Engine.is_editor_hint() and OS.get_cmdline_user_args().has("--combat-authoring-check"): call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok: errors += 1; push_error(message)
func preview(script_name: String = "preview") -> Control:
	for control: Node in EditorInterface.get_inspector().find_children("*", "Control", true, false):
		if control.get_script() != null and control.get_script().resource_path == "res://addons/reol_combat_authoring/" + script_name + ".gd": return control
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
	for path: String in ["res://data/definitions/actions/frost_marks.tres", "res://data/definitions/actions/blood_feed.tres", "res://data/definitions/combat/loadout_barrage.tres"]:
		EditorInterface.edit_resource(load(path))
		await frames()
		var panel: Control = preview("validation")
		check(panel != null, "Common Resource has no native validation: " + path)
		if panel != null:
			panel.refresh()
			check(panel._messages.text.contains("通过"), "Common Resource rejected in Inspector: " + path)
	var bad: Resource = load("res://data/definitions/actions/blood_feed.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	bad.template = "missing_reference"
	bad.mode = "emit"
	EditorInterface.edit_resource(bad)
	await frames()
	var panel: Control = preview("validation")
	if panel != null: check(panel._messages.text.contains("template"), "Missing template has no navigable field diagnostic")
	var bad_profile: Resource = load("res://data/definitions/combat/loadout_barrage.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	bad_profile.skill2 = "barrage"
	EditorInterface.edit_resource(bad_profile)
	await frames()
	panel = preview("validation")
	if panel != null: check(panel._messages.text.contains("skill2") and not panel._messages.text.contains("通过"), "Loadout id was accepted as an ability reference")
	var bad_entity: Resource = load("res://data/definitions/combat/wolf_call.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	bad_entity.entity.loadout = "star_arrow"
	EditorInterface.edit_resource(bad_entity)
	await frames()
	panel = preview("validation")
	if panel != null: check(panel._messages.text.contains("entity.loadout"), "Nested ability id was accepted as a companion profile")
	EditorInterface.edit_resource(load("res://data/definitions/combat/loadout_barrage.tres"))
	await frames()
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
