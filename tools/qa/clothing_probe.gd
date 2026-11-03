extends "res://tests/run_tests.gd"


func _run_tests() -> void:
	test_clothing()
	test_clothing_runtime()
	print("Clothing probe: %d assertions / %d failures" % [checks, failed])
	quit(1 if failed > 0 else 0)
