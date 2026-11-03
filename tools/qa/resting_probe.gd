extends "res://tests/run_tests.gd"
## Bounded work-package acceptance; failures retain the normal nonzero contract.


func _run_tests() -> void:
	test_rooms_and_rest()
	test_rooms_and_rest_runtime()
	print("Rooms/rest: %d assertions, %d failed" % [checks, failed])
	quit(1 if failed > 0 else 0)
