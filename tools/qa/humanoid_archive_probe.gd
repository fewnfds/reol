extends "res://tests/run_tests.gd"


func _run_tests() -> void:
	load("res://tests/runtime/test_humanoid_archive.gd").new().run(self)
	print("Humanoid archive probe: %d assertions / %d failures" % [checks, failed])
	quit(1 if failed > 0 else 0)
