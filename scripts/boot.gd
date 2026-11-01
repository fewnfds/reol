extends Node2D
## Placeholder boot scene. Replace with the real main scene when M1 starts.


func _ready() -> void:
	var info := Engine.get_version_info()
	print("Reol boot OK - Godot %s (%s)" % [info["string"], info["build"]])
	print("Main scene: %s" % str(ProjectSettings.get_setting("application/run/main_scene", "")))
