extends "res://tests/run_tests.gd"
## Focused development run; final acceptance still uses godot.py check.


func _run_tests() -> void:
	test_social_admission()
	test_social_admission_runtime()
	print("Admission assertions: %d; failures: %d" % [checks, failed])
	quit(1 if failed > 0 else 0)
