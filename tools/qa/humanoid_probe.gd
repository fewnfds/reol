extends "res://tests/run_tests.gd"


func _run_tests() -> void:
	load("res://tests/entities/test_humanoid_appearance.gd").new().run(self)
	load("res://tests/sim/test_body_facing.gd").new().run(self)
	load("res://tests/runtime/test_humanoid_runtime.gd").new().run(self)
	print("Humanoid probe: %d assertions / %d failures" % [checks, failed])
	quit(1 if failed > 0 else 0)
