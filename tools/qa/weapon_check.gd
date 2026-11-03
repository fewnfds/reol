extends "res://tests/run_tests.gd"
## Run the original weapon rules and runtime suites without the full check.


func _run_tests() -> void:
	print("Reol weapon tests - Godot %s" % Engine.get_version_info()["string"])
	test_weapon_items()
	test_weapon_items_runtime()
	print("Weapon assertions: %d, failures: %d" % [checks, failed])
	quit(1 if failed > 0 else 0)
