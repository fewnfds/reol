extends "res://tests/run_tests.gd"


func _run_tests() -> void:
	test_local_trade()
	test_local_trade_runtime()
	test_interaction_requests()
	test_settlement_services()
	test_roofs_weather_runtime()
	print("Local trade: %d assertions, %d failed" % [checks, failed])
	quit(1 if failed > 0 else 0)
