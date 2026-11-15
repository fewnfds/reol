@tool
extends EditorPlugin
const Inspector = preload("res://addons/reol_combat_authoring/inspector.gd")
var inspector := Inspector.new()
func _enter_tree() -> void:
	add_inspector_plugin(inspector)
	add_tool_menu_item("Reol 战斗技能库", _open_library)
	add_tool_menu_item("Reol 单位策略库", _open_decisions)
func _exit_tree() -> void:
	remove_tool_menu_item("Reol 战斗技能库")
	remove_tool_menu_item("Reol 单位策略库")
	remove_inspector_plugin(inspector)
func _open_library() -> void:
	EditorInterface.edit_resource(load("res://data/definitions/combat/library.tres"))
func _open_decisions() -> void:
	EditorInterface.edit_resource(load("res://data/definitions/decisions/library.tres"))
