extends SceneTree
## CLI adapter for the same Node session exported by Windows Performance.

func _initialize() -> void:
	root.add_child(preload("res://scripts/diagnostics/crowd_stress_session.gd").new())
