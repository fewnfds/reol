extends "res://tests/run_tests.gd"


func _run_tests() -> void:
	test_personal_foraging()
	test_personal_foraging_runtime()
	test_land_resources()
	test_local_trade_runtime()
	print("Personal foraging: %d assertions, %d failed" % [checks, failed])
	quit(1 if failed > 0 else 0)
