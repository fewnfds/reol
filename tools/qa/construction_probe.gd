extends "res://tests/run_tests.gd"
## Targeted construction acceptance runner; same assertions and exit contract.


func _run_tests() -> void:
	test_construction()
	test_construction_runtime()
	print("Construction: %d assertions, %d failed" % [checks, failed])
	quit(1 if failed > 0 else 0)
