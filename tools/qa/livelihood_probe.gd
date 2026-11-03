extends "res://tests/run_tests.gd"


func _run_tests() -> void:
	test_autonomous_livelihood()
	test_autonomous_livelihood_runtime()
	print("Livelihood probe: %d assertions / %d failures" % [checks, failed])
	quit(1 if failed > 0 else 0)
