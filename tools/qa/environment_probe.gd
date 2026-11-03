extends "res://tests/run_tests.gd"


func _run_tests() -> void:
	load("res://tests/sim/test_calendar_climate.gd").new().run(self)
	load("res://tests/sim/test_environment.gd").new().run(self)
	load("res://tests/runtime/test_environment_runtime.gd").new().run(self)
	print("Environment probe: %d assertions / %d failures" % [checks, failed])
	quit(1 if failed > 0 else 0)
